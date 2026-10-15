import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../settings/application/tracking_start.dart';
import '../domain/transfer.dart';
import 'account_support.dart';

/// Largest single transfer accepted (Rs 10 crore) — guards against typos.
const Money maxTransferAmount = Money.rupees(100000000);

/// Input for creating or updating a transfer between own accounts.
class TransferInput extends ActionInput {
  const TransferInput({
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.date,
    this.channel,
    this.note,
  });

  final String fromAccountId;
  final String toAccountId;
  final Money amount;
  final DateTime date;
  final String? channel;
  final String? note;

  factory TransferInput.fromJson(Map<String, Object?> j) => TransferInput(
        fromAccountId: In.str(j, 'fromAccountId'),
        toAccountId: In.str(j, 'toAccountId'),
        amount: In.money(j, 'amount'),
        date: In.date(j, 'date'),
        channel: In.strOpt(j, 'channel'),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {
        'fromAccountId': fromAccountId,
        'toAccountId': toAccountId,
        'amount': Out.money(amount),
        'date': Out.date(date),
        'channel': channel,
        'note': note,
      };
}

const _fields = [
  ActionFieldSpec('fromAccountId', FieldKind.id, 'Account the money leaves'),
  ActionFieldSpec('toAccountId', FieldKind.id, 'Account the money goes to (different from the source)'),
  ActionFieldSpec('amount', FieldKind.money, 'Amount in rupees, greater than zero'),
  ActionFieldSpec('date', FieldKind.date, 'Date of the transfer (not in the future)'),
  ActionFieldSpec('channel', FieldKind.string, 'Optional: ATM, NEFT, UPI … (up to 30 characters)', required: false),
  ActionFieldSpec('note', FieldKind.string, 'Free-text note', required: false),
];

/// [existing] is the transfer being edited, whose archived accounts may stay.
Map<String, String> validateTransfer(TransferInput i, FinanceSnapshot s, {Transfer? existing}) {
  final e = <String, String>{};
  if (i.fromAccountId == i.toAccountId) {
    e['toAccountId'] = 'Choose two different accounts.';
  }
  final fromErr = accountWriteError(s, i.fromAccountId, keepAccountId: existing?.fromAccountId);
  if (fromErr != null) e['fromAccountId'] = fromErr;
  final toErr = accountWriteError(s, i.toAccountId, keepAccountId: existing?.toAccountId);
  if (toErr != null && !e.containsKey('toAccountId')) e['toAccountId'] = toErr;
  if (!i.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
  if (i.amount > maxTransferAmount) e['amount'] = 'That amount looks too large. Please check it.';
  if (i.date.dateOnly.isAfter(s.today)) e['date'] = 'The date cannot be in the future.';
  final ch = channelError(i.channel);
  if (ch != null) e['channel'] = ch;
  if ((i.note?.length ?? 0) > 500) e['note'] = 'Keep the note under 500 characters.';
  return e;
}

List<PreviewLine> _lines(TransferInput i, FinanceSnapshot s) => [
      PreviewLine('From', s.account(i.fromAccountId)?.name ?? '—'),
      PreviewLine('To', s.account(i.toAccountId)?.name ?? '—'),
      PreviewLine('Amount', i.amount.format(), emphasis: true),
      PreviewLine('Date', DateFormats.dayMonthYear.format(i.date)),
      if (cleanChannel(i.channel) != null) PreviewLine('Channel', cleanChannel(i.channel)!),
      const PreviewLine('Income / spending', 'Not affected'),
    ];

List<String> _warnings(TransferInput i, FinanceSnapshot s, {Transfer? replacing}) {
  final from = s.account(i.fromAccountId);
  if (from == null || from.isLiability) return const [];
  var bal = s.balance.balanceOf(from.id) ?? Money.zero;
  if (replacing != null && replacing.fromAccountId == from.id) bal += replacing.amount;
  if (i.amount > bal) return ['${from.name} has ${bal.format()}; this would overdraw it.'];
  return const [];
}

class CreateTransferAction extends FinancialAction<TransferInput, Transfer> {
  const CreateTransferAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'transfers.create',
        module: 'accounts',
        title: 'Transfer between accounts',
        description: 'Moves money between your own accounts (ATM withdrawal, credit-card bill payment). '
            'Not income or spending.',
        risk: ActionRisk.low,
        movesMoney: true,
        fields: _fields,
      );

  @override
  TransferInput decode(Map<String, Object?> json) => TransferInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(TransferInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateTransfer(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(preview(
      input,
      title: 'Transfer',
      summary: 'Moved ${input.amount.format()} from ${s.account(input.fromAccountId)?.name ?? '—'} '
          'to ${s.account(input.toAccountId)?.name ?? '—'}',
      lines: _lines(input, s),
      warnings: _warnings(input, s),
    ));
  }

  @override
  Future<Result<Transfer>> execute(TransferInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final t = Transfer(
      id: env.ids.next('trf'),
      fromAccountId: input.fromAccountId,
      toAccountId: input.toAccountId,
      amount: input.amount,
      date: input.date.dateOnly,
      channel: cleanChannel(input.channel),
      note: input.note?.trim().isEmpty ?? true ? null : input.note!.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.transfers.save(t);
    await extendTrackingStart(env, t.date, accountIds: [t.fromAccountId, t.toAccountId]);
    return Result.ok(t);
  }
}

class UpdateTransferInput extends ActionInput {
  const UpdateTransferInput({required this.id, this.version, required this.data});
  final String id;
  final int? version;
  final TransferInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, if (version != null) 'version': version, ...data.toJson()};
}

class UpdateTransferAction extends FinancialAction<UpdateTransferInput, Transfer> {
  const UpdateTransferAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'transfers.update',
        module: 'accounts',
        title: 'Edit a transfer',
        description: 'Changes a transfer between your own accounts. Balances update automatically.',
        risk: ActionRisk.low,
        movesMoney: true,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Transfer id'),
          ActionFieldSpec('version', FieldKind.integer, 'Version that was read', required: false),
          ..._fields,
        ],
      );

  @override
  UpdateTransferInput decode(Map<String, Object?> json) => UpdateTransferInput(
        id: In.str(json, 'id'),
        version: In.intOpt(json, 'version') ?? In.intOpt(json, 'expectedVersion'),
        data: TransferInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdateTransferInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = s.transfers.where((t) => t.id == input.id).firstOrNull;
    if (existing == null) return const Result.err(AppFailure.notFound('This transfer no longer exists.'));
    if (input.version != null && existing.version != input.version) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This transfer changed since you opened it. Reload and try again.'));
    }
    final errors = validateTransfer(input.data, s, existing: existing);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: 'Updated transfer to ${input.data.amount.format()}',
      lines: _lines(input.data, s),
      warnings: _warnings(input.data, s, replacing: existing),
    ));
  }

  @override
  Future<Result<Transfer>> execute(UpdateTransferInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final existing = s.transfers.firstWhere((t) => t.id == input.id);
    final d = input.data;
    final updated = existing.copyWith(
      fromAccountId: d.fromAccountId,
      toAccountId: d.toAccountId,
      amount: d.amount,
      date: d.date.dateOnly,
      channel: () => cleanChannel(d.channel),
      note: () => d.note?.trim().isEmpty ?? true ? null : d.note!.trim(),
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.transfers.save(updated);
    await extendTrackingStart(env, updated.date, accountIds: [updated.fromAccountId, updated.toAccountId]);
    return Result.ok(updated);
  }
}

class DeleteTransferInput extends ActionInput {
  const DeleteTransferInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class DeleteTransferAction extends FinancialAction<DeleteTransferInput, Transfer> {
  const DeleteTransferAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'transfers.delete',
        module: 'accounts',
        title: 'Delete a transfer',
        description: 'Permanently removes a transfer and reverses its effect on both account balances.',
        risk: ActionRisk.consequential,
        reversible: false,
        movesMoney: true,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Transfer id')],
      );

  @override
  DeleteTransferInput decode(Map<String, Object?> json) => DeleteTransferInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(DeleteTransferInput input, FinanceSnapshot s, ActionEnvironment env) {
    final t = s.transfers.where((x) => x.id == input.id).firstOrNull;
    if (t == null) return const Result.err(AppFailure.notFound('This transfer no longer exists.'));
    return Result.ok(preview(
      input,
      title: 'Delete transfer?',
      summary: 'Delete ${t.amount.format()} transfer on ${DateFormats.dayMonthYear.format(t.date)}',
      lines: [
        PreviewLine('From', s.account(t.fromAccountId)?.name ?? '—'),
        PreviewLine('To', s.account(t.toAccountId)?.name ?? '—'),
      ],
      warnings: const ['This cannot be undone.'],
      basis: {'v': t.version},
    ));
  }

  @override
  Future<Result<Transfer>> execute(DeleteTransferInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final t = s.transfers.firstWhere((x) => x.id == input.id);
    await env.repos.transfers.delete(t.id);
    return Result.ok(t);
  }
}
