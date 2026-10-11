import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../domain/repositories.dart';
import '../../../finance/finance_snapshot.dart';
import '../../categories/domain/category.dart';
import '../../transactions/application/transaction_actions.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/pending_payment.dart';

class PendingInput extends ActionInput {
  const PendingInput({
    required this.counterparty,
    required this.direction,
    required this.kind,
    required this.amount,
    required this.purpose,
    required this.createdDate,
    this.notes,
    this.linkedUserId,
  });

  final String counterparty;
  final PendingDirection direction;
  final PendingKind kind;
  final Money amount;
  final String purpose;
  final DateTime createdDate;
  final String? notes;

  /// FiNN user to share this item with (double entry). Null keeps it private.
  final String? linkedUserId;

  factory PendingInput.fromJson(Map<String, Object?> j) => PendingInput(
        counterparty: In.str(j, 'counterparty'),
        direction: In.enumeration(j, 'direction', PendingDirection.values),
        kind: In.enumOpt(j, 'kind', PendingKind.values) ?? PendingKind.other,
        amount: In.money(j, 'amount'),
        purpose: In.str(j, 'purpose'),
        createdDate: In.date(j, 'createdDate'),
        notes: In.strOpt(j, 'notes'),
        linkedUserId: In.strOpt(j, 'linkedUserId'),
      );

  @override
  Map<String, Object?> toJson() => {
        'counterparty': counterparty,
        'direction': direction.name,
        'kind': kind.name,
        'amount': Out.money(amount),
        'purpose': purpose,
        'createdDate': Out.date(createdDate),
        'notes': notes,
        'linkedUserId': linkedUserId,
      };
}

const _pendingFields = [
  ActionFieldSpec('counterparty', FieldKind.string, 'Person or organisation'),
  ActionFieldSpec('direction', FieldKind.enumeration, 'iOwe = I must pay; owedToMe = I will receive',
      allowedValues: ['iOwe', 'owedToMe']),
  ActionFieldSpec('kind', FieldKind.enumeration, 'Reason', required: false,
      allowedValues: ['borrowed', 'lent', 'sharedExpense', 'reimbursement', 'other']),
  ActionFieldSpec('amount', FieldKind.money, 'Original amount in rupees'),
  ActionFieldSpec('purpose', FieldKind.string, 'Short description'),
  ActionFieldSpec('createdDate', FieldKind.date, 'When the obligation arose'),
  ActionFieldSpec('notes', FieldKind.string, 'Notes', required: false),
  ActionFieldSpec('linkedUserId', FieldKind.id,
      'FiNN user to share with; the item then also appears in their account. Find ids with the user directory.',
      required: false),
];

Map<String, String> _validatePending(PendingInput i, FinanceSnapshot s, UserDirectory users, {Money minimum = Money.zero}) {
  final e = <String, String>{};
  final link = i.linkedUserId;
  if (link != null) {
    if (link == users.me.id) {
      e['linkedUserId'] = 'You cannot share an item with yourself.';
    } else if (users.known(link) == null) {
      e['linkedUserId'] = 'That FiNN user could not be found. Search again.';
    }
  }
  if (i.counterparty.trim().isEmpty) e['counterparty'] = "Enter the person's name.";
  if (i.counterparty.length > 60) e['counterparty'] = 'Keep the name under 60 characters.';
  if (!i.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
  if (i.amount > maxTransactionAmount) e['amount'] = 'That amount looks too large. Please check it.';
  if (minimum.isPositive && i.amount < minimum) {
    e['amount'] = '${minimum.format()} has already been settled, so the amount cannot be lower.';
  }
  if (i.purpose.trim().isEmpty) e['purpose'] = 'Add a short description.';
  if (i.createdDate.dateOnly.isAfter(s.today)) e['createdDate'] = 'The date cannot be in the future.';
  return e;
}

class CreatePendingAction extends FinancialAction<PendingInput, PendingPayment> {
  const CreatePendingAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'pending.create',
        module: 'pending',
        title: 'Track money owed',
        description: 'Records an obligation between you and someone else. Does not change your cash balance.',
        risk: ActionRisk.low,
        fields: _pendingFields,
      );

  @override
  PendingInput decode(Map<String, Object?> json) => PendingInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(PendingInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = _validatePending(input, s, env.repos.users);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final owe = input.direction == PendingDirection.iOwe;
    return Result.ok(preview(
      input,
      title: owe ? 'You owe ${input.counterparty}' : '${input.counterparty} owes you',
      summary: '${owe ? 'Owe' : 'Collect'} ${input.amount.format()} · ${input.purpose}',
      lines: [
        PreviewLine('Amount', input.amount.format(), emphasis: true),
        PreviewLine('Reason', input.kind.label),
        if (input.linkedUserId != null)
          PreviewLine('Shared with', '${env.repos.users.known(input.linkedUserId!)!.handle} · also in their FiNN'),
        const PreviewLine('Cash balance', 'Unchanged until settled'),
      ],
    ));
  }

  @override
  Future<Result<PendingPayment>> execute(PendingInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final user = input.linkedUserId == null ? null : env.repos.users.known(input.linkedUserId!);
    final p = PendingPayment(
      id: env.ids.next('pend'),
      counterparty: user?.name ?? input.counterparty.trim(),
      direction: input.direction,
      kind: input.kind,
      originalAmount: input.amount,
      purpose: input.purpose.trim(),
      createdDate: input.createdDate.dateOnly,
      notes: input.notes,
      createdAt: now,
      updatedAt: now,
      link: user == null
          ? null
          : PendingLink(userId: user.id, handle: user.handle, sharedId: env.ids.next('shr'), createdByMe: true),
    );
    await env.repos.pending.save(p);
    await syncSharedPending(env, p);
    return Result.ok(p);
  }
}

class UpdatePendingInput extends ActionInput {
  const UpdatePendingInput({required this.id, required this.expectedVersion, required this.data});
  final String id;
  final int expectedVersion;

  /// Direction cannot change after creation; it is ignored here.
  final PendingInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

class UpdatePendingAction extends FinancialAction<UpdatePendingInput, PendingPayment> {
  const UpdatePendingAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'pending.update',
        module: 'pending',
        title: 'Edit money owed',
        description: 'Edits the details of a pending payment. The original amount cannot go below what was already settled.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Pending payment id'),
          ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
          ..._pendingFields,
        ],
      );

  @override
  UpdatePendingInput decode(Map<String, Object?> json) => UpdatePendingInput(
        id: In.str(json, 'id'),
        expectedVersion: In.integer(json, 'expectedVersion'),
        data: PendingInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdatePendingInput input, FinanceSnapshot s, ActionEnvironment env) {
    final v = s.pendingView(input.id);
    if (v == null) return const Result.err(AppFailure.notFound('This item no longer exists.'));
    if (v.payment.version != input.expectedVersion) {
      return const Result.err(AppFailure(FailureCode.staleData, 'This item changed since you opened it. Reload and try again.'));
    }
    final link = v.payment.link;
    if (link != null && !link.createdByMe) {
      return Result.err(AppFailure(FailureCode.notPermitted,
          'Only ${v.payment.counterparty} can change the details of this shared item. You can still record a settlement.'));
    }
    if (link != null && input.data.linkedUserId != null && input.data.linkedUserId != link.userId) {
      return const Result.err(AppFailure(FailureCode.notPermitted, 'The person on a shared item cannot change.'));
    }
    final e = _validatePending(input.data, s, env.repos.users, minimum: v.settled);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: 'Update ${v.payment.purpose} with ${input.data.counterparty}',
      lines: [
        PreviewLine('Original amount', input.data.amount.format(), emphasis: true),
        PreviewLine('Already settled', v.settled.format()),
        PreviewLine('Outstanding after edit', (input.data.amount - v.settled).format()),
      ],
    ));
  }

  @override
  Future<Result<PendingPayment>> execute(UpdatePendingInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final p = s.pendingView(input.id)!.payment;
    final d = input.data;
    // A private item can be shared later; a shared one keeps its person.
    final user = p.link == null && d.linkedUserId != null ? env.repos.users.known(d.linkedUserId!) : null;
    final updated = p.copyWith(
      counterparty: p.link != null ? p.counterparty : (user?.name ?? d.counterparty.trim()),
      kind: d.kind,
      originalAmount: d.amount,
      purpose: d.purpose.trim(),
      createdDate: d.createdDate.dateOnly,
      notes: () => d.notes,
      updatedAt: env.clock.now(),
      version: p.version + 1,
      link: user == null
          ? null
          : () => PendingLink(userId: user.id, handle: user.handle, sharedId: env.ids.next('shr'), createdByMe: true),
    );
    await env.repos.pending.save(updated);
    await syncSharedPending(env, updated);
    return Result.ok(updated);
  }
}

class SettlePendingInput extends ActionInput {
  const SettlePendingInput({
    required this.pendingId,
    required this.amount,
    required this.date,
    this.method,
    this.recordCashMovement = true,
    this.note,
  });

  final String pendingId;
  final Money amount;
  final DateTime date;
  final PaymentMethod? method;

  /// When true, a linked income/expense transaction is created so the cash
  /// balance reflects the settlement. False for settlements outside tracked
  /// cash (e.g. offset against another debt).
  final bool recordCashMovement;
  final String? note;

  @override
  Map<String, Object?> toJson() => {
        'pendingId': pendingId,
        'amount': Out.money(amount),
        'date': Out.date(date),
        'method': method?.name,
        'recordCashMovement': recordCashMovement,
        'note': note,
      };
}

class SettlePendingAction extends FinancialAction<SettlePendingInput, PendingSettlement> {
  const SettlePendingAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'pending.settle',
        module: 'pending',
        title: 'Settle money owed',
        description: 'Records a full or partial settlement. Creates the matching cash movement once (never twice).',
        risk: ActionRisk.consequential,
        movesMoney: true,
        reversible: false,
        fields: [
          ActionFieldSpec('pendingId', FieldKind.id, 'Exact pending payment id. Use pending.resolve to find it by name; never guess.'),
          ActionFieldSpec('amount', FieldKind.money, 'Amount settled now (≤ outstanding)'),
          ActionFieldSpec('date', FieldKind.date, 'Settlement date'),
          ActionFieldSpec('method', FieldKind.enumeration, 'Payment method', required: false,
              allowedValues: ['upi', 'card', 'cash', 'bankTransfer', 'wallet', 'other']),
          ActionFieldSpec('recordCashMovement', FieldKind.boolean, 'Create the matching cash transaction (default true)', required: false),
          ActionFieldSpec('note', FieldKind.string, 'Reference', required: false),
        ],
      );

  @override
  SettlePendingInput decode(Map<String, Object?> j) => SettlePendingInput(
        pendingId: In.str(j, 'pendingId'),
        amount: In.money(j, 'amount'),
        date: In.date(j, 'date'),
        method: In.enumOpt(j, 'method', PaymentMethod.values),
        recordCashMovement: In.boolean(j, 'recordCashMovement', fallback: true),
        note: In.strOpt(j, 'note'),
      );

  @override
  Result<ActionPreview> prepare(SettlePendingInput input, FinanceSnapshot s, ActionEnvironment env) {
    final v = s.pendingView(input.pendingId);
    if (v == null) return const Result.err(AppFailure.notFound('This item no longer exists.'));
    if (!v.status.isActive) {
      return Result.err(AppFailure.validation('This item is already ${v.status.label.toLowerCase()}.'));
    }
    final e = <String, String>{};
    if (!input.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
    if (input.amount > v.outstanding) e['amount'] = 'Only ${v.outstanding.format()} is outstanding.';
    if (input.date.dateOnly.isAfter(s.today)) e['date'] = 'The date cannot be in the future.';
    if (input.date.dateOnly.isBefore(v.payment.createdDate)) e['date'] = 'The date is before this item was created.';
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));

    final owe = v.payment.direction == PendingDirection.iOwe;
    final remaining = v.outstanding - input.amount;
    final warnings = <String>[];
    if (owe && input.recordCashMovement && input.amount > s.balance.available) {
      warnings.add('This is more than your available balance of ${s.balance.available.format()}.');
    }
    final cashLine = !input.recordCashMovement
        ? 'Not recorded as cash'
        : (owe ? (-input.amount).format() : input.amount.format(sign: SignDisplay.always));
    return Result.ok(preview(
      input,
      title: remaining.isZero ? 'Settle in full' : 'Record partial settlement',
      summary: owe
          ? 'Pay ${v.payment.counterparty} ${input.amount.format()}'
          : 'Receive ${input.amount.format()} from ${v.payment.counterparty}',
      lines: [
        PreviewLine('For', v.payment.purpose),
        PreviewLine('Original', v.payment.originalAmount.format()),
        PreviewLine('Settled before', v.settled.format()),
        PreviewLine('This settlement', input.amount.format(), emphasis: true),
        PreviewLine('Remaining after', remaining.format()),
        PreviewLine('Cash balance', cashLine),
      ],
      warnings: warnings,
      basis: {'v': v.payment.version, 'settled': v.settled.paise},
    ));
  }

  @override
  Future<Result<PendingSettlement>> execute(SettlePendingInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final v = s.pendingView(input.pendingId)!;
    final owe = v.payment.direction == PendingDirection.iOwe;
    Transaction? tx;
    if (input.recordCashMovement) {
      tx = buildLinkedTransaction(
        env: env,
        type: owe ? TransactionType.expense : TransactionType.income,
        amount: input.amount,
        categoryId: owe ? SystemCategories.settlementPaid : SystemCategories.settlementReceived,
        date: input.date,
        origin: TransactionOrigin.pendingSettlement,
        originRefId: v.payment.id,
        method: input.method,
        counterparty: v.payment.counterparty,
        note: 'Settlement · ${v.payment.purpose}',
      );
      await env.repos.transactions.save(tx);
    }
    final settlement = PendingSettlement(
      id: env.ids.next('set'),
      pendingId: v.payment.id,
      amount: input.amount,
      date: input.date.dateOnly,
      method: input.method,
      transactionId: tx?.id,
      note: input.note,
      createdAt: env.clock.now(),
    );
    try {
      await env.repos.settlements.save(settlement);
    } catch (_) {
      // Compensate so a cash movement never exists without its settlement.
      if (tx != null) await env.repos.transactions.delete(tx.id);
      rethrow;
    }
    await syncSharedPending(env, v.payment);
    return Result.ok(settlement);
  }
}

class PendingIdInput extends ActionInput {
  const PendingIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// Writes off an obligation that will not be settled.
class CancelPendingAction extends FinancialAction<PendingIdInput, PendingPayment> {
  const CancelPendingAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'pending.cancel',
        module: 'pending',
        title: 'Write off money owed',
        description: 'Marks the remaining amount as no longer expected. Recorded settlements are kept.',
        risk: ActionRisk.consequential,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Pending payment id')],
      );

  @override
  PendingIdInput decode(Map<String, Object?> json) => PendingIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(PendingIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final v = s.pendingView(input.id);
    if (v == null) return const Result.err(AppFailure.notFound('This item no longer exists.'));
    if (!v.status.isActive) return const Result.err(AppFailure.validation('This item is already closed.'));
    if (v.payment.isShared && v.payment.direction == PendingDirection.iOwe) {
      return Result.err(AppFailure(FailureCode.notPermitted,
          'This is shared with ${v.payment.counterparty}, who is owed the money. Only they can write it off.'));
    }
    return Result.ok(preview(
      input,
      title: 'Write off ${v.outstanding.format()}?',
      summary: 'Write off ${v.outstanding.format()} with ${v.payment.counterparty}',
      lines: [PreviewLine('For', v.payment.purpose), PreviewLine('Already settled', v.settled.format())],
      basis: {'v': v.payment.version, 'settled': v.settled.paise},
    ));
  }

  @override
  Future<Result<PendingPayment>> execute(PendingIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final p = s.pendingView(input.id)!.payment;
    final updated = p.copyWith(isCancelled: true, updatedAt: env.clock.now(), version: p.version + 1);
    await env.repos.pending.save(updated);
    await syncSharedPending(env, updated);
    return Result.ok(updated);
  }
}

/// Deletes an item that has no settlements (mistaken entries only).
class DeletePendingAction extends FinancialAction<PendingIdInput, PendingPayment> {
  const DeletePendingAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'pending.delete',
        module: 'pending',
        title: 'Delete pending item',
        description: 'Removes an item created by mistake. Items with settlements must be written off instead.',
        risk: ActionRisk.consequential,
        reversible: false,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Pending payment id')],
      );

  @override
  PendingIdInput decode(Map<String, Object?> json) => PendingIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(PendingIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final v = s.pendingView(input.id);
    if (v == null) return const Result.err(AppFailure.notFound('This item no longer exists.'));
    if (v.settlements.isNotEmpty) {
      return const Result.err(AppFailure(FailureCode.notPermitted,
          'This item has settlements recorded. Write it off instead so your history stays accurate.'));
    }
    final link = v.payment.link;
    if (link != null && !link.createdByMe) {
      return Result.err(AppFailure(FailureCode.notPermitted, 'Only ${v.payment.counterparty} can delete this shared item.'));
    }
    return Result.ok(preview(
      input,
      title: 'Delete this item?',
      summary: 'Delete ${v.payment.purpose} with ${v.payment.counterparty}',
      warnings: const ['This cannot be undone.'],
      basis: {'v': v.payment.version},
    ));
  }

  @override
  Future<Result<PendingPayment>> execute(PendingIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final p = s.pendingView(input.id)!.payment;
    await env.repos.pending.delete(p.id);
    await syncSharedPending(env, p, removed: true);
    return Result.ok(p);
  }
}

/// Safe lookup of an active obligation by counterparty name, for future
/// conversational use ("settle Rahul's 500"). Never picks arbitrarily.
class PendingResolver {
  const PendingResolver();

  Result<PendingView> resolve(FinanceSnapshot s, String counterparty, {PendingDirection? direction, Money? amount}) {
    final name = counterparty.trim().toLowerCase();
    var candidates = s.pendingViews.where((v) =>
        v.status.isActive &&
        v.payment.counterparty.toLowerCase() == name &&
        (direction == null || v.payment.direction == direction)).toList();
    if (candidates.isEmpty && name.isNotEmpty) {
      candidates = s.pendingViews
          .where((v) =>
              v.status.isActive &&
              v.payment.counterparty.toLowerCase().contains(name) &&
              (direction == null || v.payment.direction == direction))
          .toList();
    }
    if (amount != null && candidates.length > 1) {
      final exact = candidates.where((v) => v.outstanding == amount).toList();
      if (exact.length == 1) candidates = exact;
    }
    if (candidates.isEmpty) {
      return Result.err(AppFailure.notFound('No open item found for "$counterparty".'));
    }
    if (candidates.length > 1) {
      final list = candidates.map((v) => '${v.payment.purpose} (${v.outstanding.format()})').join(', ');
      return Result.err(AppFailure(FailureCode.ambiguous,
          '${candidates.length} open items match "$counterparty": $list. Please choose one.'));
    }
    return Result.ok(candidates.single);
  }
}

/// Keeps the other side of a shared item in step (double entry): writes
/// the counterparty's mirror after every change to [p], or removes it when
/// [removed]. No-op for private items. Reads settlements fresh so the
/// mirror always matches what was just saved.
Future<void> syncSharedPending(ActionEnvironment env, PendingPayment p, {bool removed = false}) async {
  final link = p.link;
  if (link == null) return;
  final key = MirrorEntry.keyOf(link.userId, link.sharedId);
  if (removed) {
    await env.repos.sharedLedger.delete(key);
    return;
  }
  final current = await env.repos.pending.getById(p.id) ?? p;
  final settlements = (await env.repos.settlements.getAll()).where((x) => x.pendingId == p.id).toList()
    ..sort((a, b) => b.date.compareTo(a.date));
  await env.repos.sharedLedger.save(mirrorOf(current, settlements, me: env.repos.users.me));
}
