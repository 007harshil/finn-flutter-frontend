import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../../finance/overdraft.dart';
import '../../accounts/application/account_support.dart';
import '../domain/transaction.dart';
import '../../settings/application/tracking_start.dart';

/// Input for creating or updating a manual transaction.
class TransactionInput extends ActionInput {
  const TransactionInput({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.accountId,
    this.splits = const [],
    this.channel,
    this.counterparty,
    this.note,
  });

  final TransactionType type;
  final Money amount;
  final String categoryId;
  final DateTime date;
  /// Account hit; null resolves to the user's default account.
  final String? accountId;

  /// Parts paid from different accounts (two or more, adding up to
  /// [amount]). Empty when one account carries the whole amount.
  final List<AccountLeg> splits;
  final String? channel;
  final String? counterparty;
  final String? note;

  factory TransactionInput.fromJson(Map<String, Object?> j) => TransactionInput(
    type: In.enumeration(j, 'type', TransactionType.values),
    amount: In.money(j, 'amount'),
    categoryId: In.str(j, 'categoryId'),
    date: In.date(j, 'date'),
    accountId: In.strOpt(j, 'accountId'),
    splits: decodeAccountSplits(j),
    channel: In.strOpt(j, 'channel'),
    counterparty: In.strOpt(j, 'counterparty'),
    note: In.strOpt(j, 'note'),
  );

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'amount': Out.money(amount),
    'categoryId': categoryId,
    'date': Out.date(date),
    'accountId': accountId,
    if (splits.isNotEmpty) 'splits': encodeAccountSplits(splits),
    'channel': channel,
    'counterparty': counterparty,
    'note': note,
  };
}

/// Decodes `splits: [{accountId, amount}]` (amounts in rupees).
List<AccountLeg> decodeAccountSplits(Map<String, Object?> j) {
  final raw = j['splits'];
  if (raw == null) return const [];
  if (raw is! List) {
    throw const AppFailure.validation('Invalid "splits": expected a list.', fields: {'splits': 'Expected a list'});
  }
  return [
    for (final e in raw)
      if (e is Map)
        AccountLeg(In.str(Map<String, Object?>.from(e), 'accountId'), In.money(Map<String, Object?>.from(e), 'amount'))
      else
        throw const AppFailure.validation('Invalid "splits".', fields: {'splits': 'Expected accountId and amount'}),
  ];
}

List<Map<String, Object?>> encodeAccountSplits(List<AccountLeg> legs) => [
  for (final l in legs) {'accountId': l.accountId, 'amount': Out.money(l.amount)},
];

/// Why [legs] cannot split [amount], or null. Two or more different
/// writable accounts, each part above zero, parts adding up to [amount].
String? accountSplitError(FinanceSnapshot s, Money amount, List<AccountLeg> legs, {List<AccountLeg> keep = const []}) {
  if (legs.isEmpty) return null;
  if (legs.length < 2) return 'Choose at least two accounts to split the payment.';
  final ids = legs.map((l) => l.accountId).toSet();
  if (ids.length != legs.length) return 'Each account can appear only once.';
  if (legs.any((l) => !l.amount.isPositive)) return 'Enter an amount for each account.';
  final total = Money.sum(legs.map((l) => l.amount));
  if (total != amount) return 'The parts add up to ${total.format()}, not ${amount.format()}.';
  final kept = keep.map((l) => l.accountId).toSet();
  for (final l in legs) {
    final err = accountWriteError(s, l.accountId, keepAccountId: kept.contains(l.accountId) ? l.accountId : null);
    if (err != null) return err;
  }
  return null;
}

const _fields = [
  ActionFieldSpec('type', FieldKind.enumeration, 'income or expense', allowedValues: ['income', 'expense']),
  ActionFieldSpec('amount', FieldKind.money, 'Amount in rupees, greater than zero'),
  ActionFieldSpec('categoryId', FieldKind.id, 'Category id matching the type'),
  ActionFieldSpec('date', FieldKind.date, 'Date the money moved (not in the future)'),
  ActionFieldSpec(
    'accountId',
    FieldKind.id,
    'Money account it hit (cash, bank or card). Omit for the default account',
    required: false,
  ),
  ActionFieldSpec(
    'splits',
    FieldKind.string,
    'Optional: pay from several accounts, a list of {accountId, amount} adding up to amount. Overrides accountId',
    required: false,
  ),
  ActionFieldSpec('channel', FieldKind.string, 'Optional: UPI, IMPS, NEFT, Cheque, ATM … (up to 30 characters)', required: false),
  ActionFieldSpec('counterparty', FieldKind.string, 'Merchant or person', required: false),
  ActionFieldSpec('note', FieldKind.string, 'Free-text note', required: false),
];

/// Maximum single amount accepted (₹10 crore) — guards against typos.
const Money maxTransactionAmount = Money.rupees(100000000);

Map<String, String> validateTransaction(TransactionInput i, FinanceSnapshot s, {Transaction? existing}) {
  final errors = <String, String>{};
  if (!i.amount.isPositive) errors['amount'] = 'Enter an amount greater than zero.';
  if (i.amount > maxTransactionAmount) errors['amount'] = 'That amount looks too large. Please check it.';
  final cat = s.category(i.categoryId);
  if (cat == null || cat.isArchived) {
    errors['categoryId'] = 'Choose a category.';
  } else if (cat.type != i.type) {
    errors['categoryId'] = 'This category is for ${cat.type.label.toLowerCase()}.';
  } else if (cat.isSystem && !(cat.id.endsWith('_other_out') || cat.id.endsWith('_other_in'))) {
    errors['categoryId'] = 'This category is managed automatically. Choose another.';
  }
  if (i.date.dateOnly.isAfter(s.today)) errors['date'] = 'The date cannot be in the future.';
  if (i.splits.isEmpty) {
    final accountErr = accountWriteError(s, i.accountId ?? existing?.accountId ?? s.defaultAccountId, keepAccountId: existing?.accountId);
    if (accountErr != null) errors['accountId'] = accountErr;
  } else {
    final splitErr = accountSplitError(s, i.amount, i.splits, keep: existing?.legs ?? const []);
    if (splitErr != null) errors['splits'] = splitErr;
  }
  final channelErr = channelError(i.channel);
  if (channelErr != null) errors['channel'] = channelErr;
  if ((i.counterparty?.length ?? 0) > 80) errors['counterparty'] = 'Keep this under 80 characters.';
  if ((i.note?.length ?? 0) > 500) errors['note'] = 'Keep the note under 500 characters.';
  return errors;
}

List<PreviewLine> _lines(TransactionInput i, FinanceSnapshot s, {Transaction? existing}) => [
  PreviewLine('Type', i.type.label),
  PreviewLine('Amount', i.amount.format(), emphasis: true),
  PreviewLine('Category', s.category(i.categoryId)?.name ?? '—'),
  PreviewLine('Date', DateFormats.dayMonthYear.format(i.date)),
  if (i.splits.length > 1)
    for (final l in i.splits) PreviewLine(s.account(l.accountId)?.name ?? '—', l.amount.format())
  else
    PreviewLine('Account', s.account(i.accountId ?? existing?.accountId ?? s.defaultAccountId)?.name ?? '—'),
  if (cleanChannel(i.channel) != null) PreviewLine('Channel', cleanChannel(i.channel)!),
  if (i.counterparty != null) PreviewLine(i.type.isIncome ? 'From' : 'To', i.counterparty!),
];

class CreateTransactionAction extends FinancialAction<TransactionInput, Transaction> {
  const CreateTransactionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'transactions.create',
    module: 'transactions',
    title: 'Record a transaction',
    description: 'Records completed income or an expense. Changes the cash balance.',
    risk: ActionRisk.low,
    movesMoney: true,
    fields: _fields,
  );

  @override
  TransactionInput decode(Map<String, Object?> json) => TransactionInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(TransactionInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateTransaction(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final short = transactionOverdraft(
      s,
      add: [input.draft(s.defaultAccountId)],
      canSplit: input.isExpense && input.splits.isEmpty,
    );
    if (short != null) return Result.err(short);
    final warnings = <String>[];
    if (input.isExpense && input.amount > s.balance.available) {
      warnings.add('This is more than your available balance of ${s.balance.available.format()}.');
    }
    return Result.ok(
      preview(
        input,
        title: 'Record ${input.type.label.toLowerCase()}',
        summary: '${input.type.isIncome ? 'Received' : 'Spent'} ${input.amount.format()}',
        lines: _lines(input, s),
        warnings: warnings,
      ),
    );
  }

  @override
  Future<Result<Transaction>> execute(TransactionInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final tx = Transaction(
      id: env.ids.next('tx'),
      type: input.type,
      amount: input.amount,
      categoryId: input.categoryId,
      date: input.date.dateOnly,
      accountId: input.splits.length > 1 ? input.splits.first.accountId : resolveAccountId(s, input.accountId),
      splits: input.splits.length > 1 ? List.unmodifiable(input.splits) : const [],
      channel: cleanChannel(input.channel),
      counterparty: input.counterparty,
      note: input.note,
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.transactions.save(tx);
    await extendTrackingStart(env, tx.date, accountIds: tx.legs.map((l) => l.accountId));
    return Result.ok(tx);
  }
}

extension TransactionInputDraft on TransactionInput {
  bool get isExpense => type == TransactionType.expense;

  /// This input as a throwaway transaction, for balance checks.
  Transaction draft(String fallbackAccountId) => draftTransaction(
    type: type,
    amount: amount,
    date: date.dateOnly,
    accountId: accountId ?? fallbackAccountId,
    splits: splits,
  );
}

class UpdateTransactionInput extends ActionInput {
  const UpdateTransactionInput({required this.id, required this.expectedVersion, required this.data});
  final String id;

  /// Version the user edited; a mismatch means someone else changed it.
  final int expectedVersion;
  final TransactionInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdateTransactionAction extends FinancialAction<UpdateTransactionInput, Transaction> {
  const UpdateTransactionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'transactions.update',
    module: 'transactions',
    title: 'Edit a transaction',
    description: 'Changes a manual transaction. Balances, budgets and analytics update automatically.',
    risk: ActionRisk.low,
    movesMoney: true,
    fields: [
      ActionFieldSpec('id', FieldKind.id, 'Transaction id'),
      ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
      ..._fields,
    ],
  );

  @override
  UpdateTransactionInput decode(Map<String, Object?> json) => UpdateTransactionInput(
    id: In.str(json, 'id'),
    expectedVersion: In.integer(json, 'expectedVersion'),
    data: TransactionInput.fromJson(json),
  );

  @override
  Result<ActionPreview> prepare(UpdateTransactionInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = s.transactionById[input.id];
    if (existing == null) return const Result.err(AppFailure.notFound('This transaction no longer exists.'));
    if (existing.isLinked) {
      return Result.err(
        AppFailure(
          FailureCode.notPermitted,
          'This transaction was created by ${existing.origin.label.toLowerCase()}. Change it from there.',
        ),
      );
    }
    if (existing.version != input.expectedVersion) {
      return const Result.err(
        AppFailure(FailureCode.staleData, 'This transaction changed since you opened it. Reload and try again.'),
      );
    }
    final errors = validateTransaction(input.data, s, existing: existing);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final short = transactionOverdraft(
      s,
      add: [input.data.draft(existing.accountId)],
      remove: {existing.id},
      canSplit: input.data.isExpense && input.data.splits.isEmpty,
    );
    if (short != null) return Result.err(short);
    return Result.ok(
      preview(
        input,
        title: 'Save changes',
        summary:
            'Update ${existing.amount.format()} ${existing.type.label.toLowerCase()} to ${input.data.amount.format()}',
        lines: _lines(input.data, s, existing: existing),
      ),
    );
  }

  @override
  Future<Result<Transaction>> execute(UpdateTransactionInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final existing = s.transactionById[input.id]!;
    final d = input.data;
    final updated = existing.copyWith(
      type: d.type,
      amount: d.amount,
      categoryId: d.categoryId,
      date: d.date.dateOnly,
      accountId: d.splits.length > 1 ? d.splits.first.accountId : (d.accountId ?? existing.accountId),
      splits: d.splits.length > 1 ? List.unmodifiable(d.splits) : const [],
      channel: () => cleanChannel(d.channel),
      counterparty: () => d.counterparty,
      note: () => d.note,
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.transactions.save(updated);
    await extendTrackingStart(env, updated.date, accountIds: updated.legs.map((l) => l.accountId));
    return Result.ok(updated);
  }
}

class DeleteTransactionInput extends ActionInput {
  const DeleteTransactionInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class DeleteTransactionAction extends FinancialAction<DeleteTransactionInput, Transaction> {
  const DeleteTransactionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'transactions.delete',
    module: 'transactions',
    title: 'Delete a transaction',
    description: 'Permanently removes a manual transaction and reverses its effect on balances.',
    risk: ActionRisk.consequential,
    reversible: false,
    movesMoney: true,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Transaction id')],
  );

  @override
  DeleteTransactionInput decode(Map<String, Object?> json) => DeleteTransactionInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(DeleteTransactionInput input, FinanceSnapshot s, ActionEnvironment env) {
    final t = s.transactionById[input.id];
    if (t == null) return const Result.err(AppFailure.notFound('This transaction no longer exists.'));
    if (t.isLinked) {
      return Result.err(
        AppFailure(
          FailureCode.notPermitted,
          'This transaction belongs to a ${t.origin.label.toLowerCase()}. Reverse it from there.',
        ),
      );
    }
    final short = transactionOverdraft(s, remove: {t.id}, field: 'id');
    if (short != null) return Result.err(short);
    return Result.ok(
      preview(
        input,
        title: 'Delete transaction?',
        summary:
            'Delete ${t.amount.format()} ${t.type.label.toLowerCase()} on ${DateFormats.dayMonthYear.format(t.date)}',
        lines: [
          PreviewLine('Category', s.category(t.categoryId)?.name ?? '—'),
          PreviewLine(
            'Balance effect',
            (t.isIncome ? -t.amount : t.amount).format(sign: SignDisplay.always),
            emphasis: true,
          ),
        ],
        warnings: const ['This cannot be undone.'],
        basis: {'v': t.version},
      ),
    );
  }

  @override
  Future<Result<Transaction>> execute(DeleteTransactionInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final t = s.transactionById[input.id]!;
    await env.repos.transactions.delete(t.id);
    return Result.ok(t);
  }
}

/// Shared helper for actions in other modules that must create a linked
/// cash movement (repayments, settlements, subscription payments).
Transaction buildLinkedTransaction({
  required ActionEnvironment env,
  required TransactionType type,
  required Money amount,
  required String categoryId,
  required DateTime date,
  required TransactionOrigin origin,
  required String originRefId,
  required String accountId,
  List<AccountLeg> splits = const [],
  String? channel,
  String? counterparty,
  String? note,
}) {
  final now = env.clock.now();
  return Transaction(
    id: env.ids.next('tx'),
    type: type,
    amount: amount,
    categoryId: categoryId,
    date: date.dateOnly,
    accountId: splits.length > 1 ? splits.first.accountId : accountId,
    splits: splits.length > 1 ? List.unmodifiable(splits) : const [],
    channel: cleanChannel(channel),
    counterparty: counterparty,
    note: note,
    origin: origin,
    originRefId: originRefId,
    createdAt: now,
    updatedAt: now,
  );
}

/// Common date guard used by money-moving actions.
String? validateNotFuture(DateTime date, Clock clock) =>
    date.dateOnly.isAfter(clock.today()) ? 'The date cannot be in the future.' : null;
