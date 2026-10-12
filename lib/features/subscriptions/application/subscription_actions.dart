import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../core/time/frequency.dart';
import '../../../finance/finance_snapshot.dart';
import '../../categories/domain/category.dart';
import '../../transactions/application/transaction_actions.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/subscription.dart';
import '../../settings/application/tracking_start.dart';

// ---------------------------------------------------------------------------
// Schedule helpers (pure). A due date passing NEVER creates a transaction:
// only [MarkSubscriptionPaidAction] records a payment.
// ---------------------------------------------------------------------------

abstract final class SubscriptionSchedule {
  /// Day of month the schedule is anchored to. A due date clamped to a short
  /// month (31 Jan → 28 Feb) returns to the start date's day afterwards.
  static int anchorDay(Subscription s) {
    final due = s.nextDueDate;
    final start = s.startDate;
    if (start != null && start.day > due.day && due.day == due.daysInMonth) return start.day;
    return due.day;
  }

  /// The due date one frequency step after the current [Subscription.nextDueDate].
  static DateTime nextCycleAfterCurrent(Subscription s) =>
      s.frequency.next(s.nextDueDate.dateOnly, anchorDay: anchorDay(s)).dateOnly;

  /// Note written on the payment transaction; identifies the cycle it paid.
  static String paymentNote(Subscription s, DateTime cycle) =>
      '${s.frequency.label} renewal · for ${DateFormats.dayMonthYear.format(cycle)}';

  static String _cycleMarker(DateTime cycle) => 'for ${DateFormats.dayMonthYear.format(cycle)}';

  /// Whether a payment transaction already exists for the cycle due on [cycle].
  /// Payments recorded by FiNN carry the cycle in their note; older entries
  /// without a marker count when their date equals the cycle date.
  static bool isCyclePaid(Subscription s, DateTime cycle, Iterable<Transaction> linked) {
    final marker = _cycleMarker(cycle);
    for (final t in linked) {
      if (t.origin != TransactionOrigin.subscription || t.originRefId != s.id) continue;
      final note = t.note ?? '';
      if (note.contains(' · for ')) {
        if (note.endsWith(marker)) return true;
      } else if (t.date.isSameDay(cycle)) {
        return true;
      }
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Create / update
// ---------------------------------------------------------------------------

class SubscriptionInput extends ActionInput {
  const SubscriptionInput({
    required this.name,
    required this.amount,
    required this.categoryId,
    required this.frequency,
    required this.nextDueDate,
    this.startDate,
    this.autoRenews = true,
    this.paymentMethod,
    this.note,
  });

  final String name;
  final Money amount;
  final String categoryId;
  final Frequency frequency;
  final DateTime nextDueDate;
  final DateTime? startDate;
  final bool autoRenews;
  final PaymentMethod? paymentMethod;
  final String? note;

  factory SubscriptionInput.fromJson(Map<String, Object?> j) => SubscriptionInput(
        name: In.str(j, 'name'),
        amount: In.money(j, 'amount'),
        categoryId: In.str(j, 'categoryId'),
        frequency: In.enumeration(j, 'frequency', Frequency.values),
        nextDueDate: In.date(j, 'nextDueDate'),
        startDate: In.dateOpt(j, 'startDate'),
        autoRenews: In.boolean(j, 'autoRenews', fallback: true),
        paymentMethod: In.enumOpt(j, 'paymentMethod', PaymentMethod.values),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {
        'name': name,
        'amount': Out.money(amount),
        'categoryId': categoryId,
        'frequency': frequency.name,
        'nextDueDate': Out.date(nextDueDate),
        'startDate': Out.dateOpt(startDate),
        'autoRenews': autoRenews,
        'paymentMethod': paymentMethod?.name,
        'note': note,
      };
}

const _subscriptionFields = [
  ActionFieldSpec('name', FieldKind.string, 'Service name, e.g. "Netflix"'),
  ActionFieldSpec('amount', FieldKind.money, 'Amount per cycle in rupees, greater than zero'),
  ActionFieldSpec('categoryId', FieldKind.id, 'Expense category id'),
  ActionFieldSpec('frequency', FieldKind.enumeration, 'Billing frequency',
      allowedValues: ['weekly', 'monthly', 'quarterly', 'halfYearly', 'yearly']),
  ActionFieldSpec('nextDueDate', FieldKind.date, 'Next renewal date'),
  ActionFieldSpec('startDate', FieldKind.date, 'When the subscription started', required: false),
  ActionFieldSpec('autoRenews', FieldKind.boolean, 'Renews automatically (informational)', required: false),
  ActionFieldSpec('paymentMethod', FieldKind.enumeration, 'Usual payment method', required: false,
      allowedValues: ['upi', 'card', 'cash', 'bankTransfer', 'wallet', 'other']),
  ActionFieldSpec('note', FieldKind.string, 'Note', required: false),
];

Map<String, String> validateSubscription(SubscriptionInput i, FinanceSnapshot s) {
  final e = <String, String>{};
  final name = i.name.trim();
  if (name.isEmpty) e['name'] = 'Enter the service name.';
  if (name.length > 60) e['name'] = 'Keep the name under 60 characters.';
  if (!i.amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
  if (i.amount > maxTransactionAmount) e['amount'] = 'That amount looks too large. Please check it.';
  final cat = s.category(i.categoryId);
  if (cat == null || cat.isArchived) {
    e['categoryId'] = 'Choose a category.';
  } else if (cat.type != TransactionType.expense) {
    e['categoryId'] = 'Choose an expense category.';
  } else if (cat.isSystem && cat.id != SystemCategories.uncategorizedExpense) {
    e['categoryId'] = 'This category is managed automatically. Choose another.';
  }
  final start = i.startDate;
  if (start != null && start.dateOnly.isAfter(i.nextDueDate.dateOnly)) {
    e['startDate'] = 'The start date must be on or before the next due date.';
  }
  if ((i.note?.length ?? 0) > 500) e['note'] = 'Keep the note under 500 characters.';
  return e;
}

List<PreviewLine> _subscriptionLines(SubscriptionInput i, FinanceSnapshot s) => [
      PreviewLine('Amount', '${i.amount.format()} ${i.frequency.label.toLowerCase()}', emphasis: true),
      PreviewLine('Per month', i.frequency.monthlyEquivalent(i.amount).format()),
      PreviewLine('Category', s.category(i.categoryId)?.name ?? '—'),
      PreviewLine('Next due', DateFormats.dayMonthYear.format(i.nextDueDate)),
      const PreviewLine('Cash balance', 'Unchanged until you mark a payment as paid'),
    ];

class CreateSubscriptionAction extends FinancialAction<SubscriptionInput, Subscription> {
  const CreateSubscriptionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.create',
        module: 'subscriptions',
        title: 'Add a subscription',
        description: 'Tracks a recurring cost. Upcoming charges are projections; nothing is paid automatically.',
        risk: ActionRisk.low,
        fields: _subscriptionFields,
      );

  @override
  SubscriptionInput decode(Map<String, Object?> json) => SubscriptionInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(SubscriptionInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = validateSubscription(input, s);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(
      input,
      title: 'Add ${input.name.trim()}',
      summary: '${input.name.trim()} added · ${input.amount.format()} ${input.frequency.label.toLowerCase()}',
      lines: _subscriptionLines(input, s),
    ));
  }

  @override
  Future<Result<Subscription>> execute(SubscriptionInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final sub = Subscription(
      id: env.ids.next('sub'),
      name: input.name.trim(),
      amount: input.amount,
      categoryId: input.categoryId,
      frequency: input.frequency,
      nextDueDate: input.nextDueDate.dateOnly,
      startDate: input.startDate?.dateOnly,
      autoRenews: input.autoRenews,
      paymentMethod: input.paymentMethod,
      note: input.note,
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.subscriptions.save(sub);
    return Result.ok(sub);
  }
}

class UpdateSubscriptionInput extends ActionInput {
  const UpdateSubscriptionInput({required this.id, required this.expectedVersion, required this.data});
  final String id;
  final int expectedVersion;
  final SubscriptionInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

Subscription? _find(FinanceSnapshot s, String id) => s.subscriptions.where((x) => x.id == id).firstOrNull;

class UpdateSubscriptionAction extends FinancialAction<UpdateSubscriptionInput, Subscription> {
  const UpdateSubscriptionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.update',
        module: 'subscriptions',
        title: 'Edit a subscription',
        description: 'Changes a subscription. Past payments are not affected.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Subscription id'),
          ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version that was read'),
          ..._subscriptionFields,
        ],
      );

  @override
  UpdateSubscriptionInput decode(Map<String, Object?> json) => UpdateSubscriptionInput(
        id: In.str(json, 'id'),
        expectedVersion: In.integer(json, 'expectedVersion'),
        data: SubscriptionInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdateSubscriptionInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = _find(s, input.id);
    if (existing == null) return const Result.err(AppFailure.notFound('This subscription no longer exists.'));
    if (existing.version != input.expectedVersion) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This subscription changed since you opened it. Reload and try again.'));
    }
    final e = validateSubscription(input.data, s);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: '${input.data.name.trim()} updated',
      lines: _subscriptionLines(input.data, s),
    ));
  }

  @override
  Future<Result<Subscription>> execute(UpdateSubscriptionInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final existing = _find(s, input.id)!;
    final d = input.data;
    final updated = existing.copyWith(
      name: d.name.trim(),
      amount: d.amount,
      categoryId: d.categoryId,
      frequency: d.frequency,
      nextDueDate: d.nextDueDate.dateOnly,
      startDate: () => d.startDate?.dateOnly,
      autoRenews: d.autoRenews,
      paymentMethod: () => d.paymentMethod,
      note: () => d.note,
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.subscriptions.save(updated);
    return Result.ok(updated);
  }
}

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

class SubscriptionStatusInput extends ActionInput {
  const SubscriptionStatusInput({required this.id, required this.status});
  final String id;
  final SubscriptionStatus status;

  @override
  Map<String, Object?> toJson() => {'id': id, 'status': status.name};
}

class SetSubscriptionStatusAction extends FinancialAction<SubscriptionStatusInput, Subscription> {
  const SetSubscriptionStatusAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.setStatus',
        module: 'subscriptions',
        title: 'Pause, resume or cancel a subscription',
        description: 'Changes whether a subscription counts towards your monthly commitment. Past payments are kept.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Subscription id'),
          ActionFieldSpec('status', FieldKind.enumeration, 'New status', allowedValues: ['active', 'paused', 'cancelled']),
        ],
      );

  @override
  SubscriptionStatusInput decode(Map<String, Object?> json) => SubscriptionStatusInput(
        id: In.str(json, 'id'),
        status: In.enumeration(json, 'status', SubscriptionStatus.values),
      );

  @override
  Result<ActionPreview> prepare(SubscriptionStatusInput input, FinanceSnapshot s, ActionEnvironment env) {
    final sub = _find(s, input.id);
    if (sub == null) return const Result.err(AppFailure.notFound('This subscription no longer exists.'));
    if (sub.status == input.status) {
      return Result.err(AppFailure.validation('${sub.name} is already ${input.status.label.toLowerCase()}.'));
    }
    final verb = switch (input.status) {
      SubscriptionStatus.active => sub.status == SubscriptionStatus.paused ? 'resumed' : 'reactivated',
      SubscriptionStatus.paused => 'paused',
      SubscriptionStatus.cancelled => 'cancelled',
    };
    return Result.ok(preview(
      input,
      title: '${sub.name} $verb',
      summary: '${sub.name} $verb',
      lines: [
        PreviewLine('Status', '${sub.status.label} → ${input.status.label}'),
        PreviewLine('Monthly commitment',
            input.status == SubscriptionStatus.active ? '+${sub.monthlyEquivalent.format()}' : '−${sub.monthlyEquivalent.format()}'),
      ],
    ));
  }

  @override
  Future<Result<Subscription>> execute(SubscriptionStatusInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final sub = _find(s, input.id)!;
    final updated = sub.copyWith(status: input.status, updatedAt: env.clock.now(), version: sub.version + 1);
    await env.repos.subscriptions.save(updated);
    return Result.ok(updated);
  }
}

// ---------------------------------------------------------------------------
// Mark paid / skip
// ---------------------------------------------------------------------------

class MarkSubscriptionPaidInput extends ActionInput {
  const MarkSubscriptionPaidInput({
    required this.subscriptionId,
    this.cycleDate,
    this.date,
    this.amount,
    this.method,
  });

  final String subscriptionId;

  /// Due date of the cycle being paid. Defaults to the current next due
  /// date; when given and it no longer matches, the request is rejected
  /// (prevents paying the same cycle twice from stale screens).
  final DateTime? cycleDate;

  /// Payment date. Defaults to the due date (or today when that is ahead).
  final DateTime? date;

  /// Amount paid. Defaults to the subscription amount.
  final Money? amount;
  final PaymentMethod? method;

  @override
  Map<String, Object?> toJson() => {
        'subscriptionId': subscriptionId,
        'cycleDate': Out.dateOpt(cycleDate),
        'date': Out.dateOpt(date),
        'amount': Out.moneyOpt(amount),
        'method': method?.name,
      };
}

/// Resolved values of a mark-paid request.
class SubscriptionPaymentPlan {
  const SubscriptionPaymentPlan({
    required this.subscription,
    required this.cycle,
    required this.date,
    required this.amount,
    required this.method,
    required this.nextDueDate,
  });

  final Subscription subscription;
  final DateTime cycle;
  final DateTime date;
  final Money amount;
  final PaymentMethod? method;
  final DateTime nextDueDate;
}

class MarkSubscriptionPaidAction extends FinancialAction<MarkSubscriptionPaidInput, Transaction> {
  const MarkSubscriptionPaidAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.markPaid',
        module: 'subscriptions',
        title: 'Mark a subscription as paid',
        description: 'Records one renewal payment as an expense and moves the next due date forward by one cycle. '
            'Each cycle can be paid only once.',
        risk: ActionRisk.consequential,
        movesMoney: true,
        reversible: false,
        fields: [
          ActionFieldSpec('subscriptionId', FieldKind.id, 'Subscription id'),
          ActionFieldSpec('cycleDate', FieldKind.date, 'Due date of the cycle being paid (defaults to next due date)', required: false),
          ActionFieldSpec('date', FieldKind.date, 'Payment date, not in the future (defaults to the due date)', required: false),
          ActionFieldSpec('amount', FieldKind.money, 'Amount paid (defaults to the subscription amount)', required: false),
          ActionFieldSpec('method', FieldKind.enumeration, 'Payment method', required: false,
              allowedValues: ['upi', 'card', 'cash', 'bankTransfer', 'wallet', 'other']),
        ],
      );

  @override
  MarkSubscriptionPaidInput decode(Map<String, Object?> j) => MarkSubscriptionPaidInput(
        subscriptionId: In.str(j, 'subscriptionId'),
        cycleDate: In.dateOpt(j, 'cycleDate'),
        date: In.dateOpt(j, 'date'),
        amount: In.moneyOpt(j, 'amount'),
        method: In.enumOpt(j, 'method', PaymentMethod.values),
      );

  /// Validates and resolves defaults; shared by [prepare] and [execute].
  Result<SubscriptionPaymentPlan> plan(MarkSubscriptionPaidInput input, FinanceSnapshot s) {
    final sub = _find(s, input.subscriptionId);
    if (sub == null) return const Result.err(AppFailure.notFound('This subscription no longer exists.'));
    if (!sub.isActive) {
      return Result.err(AppFailure.validation(
          '${sub.name} is ${sub.status.label.toLowerCase()}. Resume it before recording a payment.'));
    }
    final cycle = sub.nextDueDate.dateOnly;
    final requested = input.cycleDate?.dateOnly;
    final linked = s.linkedTransactions(sub.id);
    if (requested != null && !requested.isSameDay(cycle)) {
      if (requested.isBefore(cycle) || SubscriptionSchedule.isCyclePaid(sub, requested, linked)) {
        return Result.err(AppFailure(FailureCode.duplicate,
            'The renewal due ${DateFormats.dayMonthYear.format(requested)} is already settled.'));
      }
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This subscription changed since you opened it. Reload and try again.'));
    }
    if (SubscriptionSchedule.isCyclePaid(sub, cycle, linked)) {
      return Result.err(AppFailure(FailureCode.duplicate,
          'A payment for the renewal due ${DateFormats.dayMonthYear.format(cycle)} is already recorded.'));
    }
    final date = (input.date ?? (cycle.isAfter(s.today) ? s.today : cycle)).dateOnly;
    final amount = input.amount ?? sub.amount;
    final e = <String, String>{};
    if (date.isAfter(s.today)) e['date'] = 'The date cannot be in the future.';
    if (!amount.isPositive) e['amount'] = 'Enter an amount greater than zero.';
    if (amount > maxTransactionAmount) e['amount'] = 'That amount looks too large. Please check it.';
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(SubscriptionPaymentPlan(
      subscription: sub,
      cycle: cycle,
      date: date,
      amount: amount,
      method: input.method ?? sub.paymentMethod,
      nextDueDate: SubscriptionSchedule.nextCycleAfterCurrent(sub),
    ));
  }

  @override
  Result<ActionPreview> prepare(MarkSubscriptionPaidInput input, FinanceSnapshot s, ActionEnvironment env) {
    final r = plan(input, s);
    if (r case Err(:final failure)) return Result.err(failure);
    final p = (r as Ok<SubscriptionPaymentPlan>).value;
    final warnings = <String>[
      if (p.amount > s.balance.available) 'This is more than your available balance of ${s.balance.available.format()}.',
      if (p.amount != p.subscription.amount)
        'This differs from the usual ${p.subscription.amount.format()}. The subscription amount stays the same.',
    ];
    return Result.ok(preview(
      input,
      title: 'Mark ${p.subscription.name} as paid',
      summary: 'Paid ${p.amount.format()} · ${p.subscription.name}',
      lines: [
        PreviewLine('Renewal due', DateFormats.dayMonthYear.format(p.cycle)),
        PreviewLine('Paid on', DateFormats.dayMonthYear.format(p.date)),
        if (p.method != null) PreviewLine('Paid via', p.method!.label),
        PreviewLine('Cash balance', (-p.amount).format(), emphasis: true),
        PreviewLine('Next due', DateFormats.dayMonthYear.format(p.nextDueDate)),
      ],
      warnings: warnings,
    ));
  }

  @override
  Future<Result<Transaction>> execute(MarkSubscriptionPaidInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final p = (plan(input, s) as Ok<SubscriptionPaymentPlan>).value;
    final sub = p.subscription;
    final category = s.category(sub.categoryId);
    final tx = buildLinkedTransaction(
      env: env,
      type: TransactionType.expense,
      amount: p.amount,
      categoryId: category == null ? SystemCategories.uncategorizedExpense : sub.categoryId,
      date: p.date,
      origin: TransactionOrigin.subscription,
      originRefId: sub.id,
      method: p.method,
      counterparty: sub.name,
      note: SubscriptionSchedule.paymentNote(sub, p.cycle),
    );
    await env.repos.transactions.save(tx);
    await extendTrackingStart(env, tx.date);
    try {
      await env.repos.subscriptions.save(sub.copyWith(
        nextDueDate: p.nextDueDate,
        updatedAt: env.clock.now(),
        version: sub.version + 1,
      ));
    } catch (_) {
      // Compensate so a payment never exists without its cycle advancing.
      await env.repos.transactions.delete(tx.id);
      rethrow;
    }
    return Result.ok(tx);
  }
}

class SkipSubscriptionCycleInput extends ActionInput {
  const SkipSubscriptionCycleInput({required this.subscriptionId, this.cycleDate});
  final String subscriptionId;

  /// Due date of the cycle being skipped (defaults to the next due date).
  final DateTime? cycleDate;

  @override
  Map<String, Object?> toJson() => {'subscriptionId': subscriptionId, 'cycleDate': Out.dateOpt(cycleDate)};
}

class SkipSubscriptionCycleAction extends FinancialAction<SkipSubscriptionCycleInput, Subscription> {
  const SkipSubscriptionCycleAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.skipCycle',
        module: 'subscriptions',
        title: 'Skip a renewal',
        description: 'Moves the next due date forward by one cycle without recording a payment '
            '(for example a free month or a waived charge).',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('subscriptionId', FieldKind.id, 'Subscription id'),
          ActionFieldSpec('cycleDate', FieldKind.date, 'Due date of the cycle being skipped', required: false),
        ],
      );

  @override
  SkipSubscriptionCycleInput decode(Map<String, Object?> j) =>
      SkipSubscriptionCycleInput(subscriptionId: In.str(j, 'subscriptionId'), cycleDate: In.dateOpt(j, 'cycleDate'));

  @override
  Result<ActionPreview> prepare(SkipSubscriptionCycleInput input, FinanceSnapshot s, ActionEnvironment env) {
    final sub = _find(s, input.subscriptionId);
    if (sub == null) return const Result.err(AppFailure.notFound('This subscription no longer exists.'));
    if (!sub.isActive) return Result.err(AppFailure.validation('${sub.name} is ${sub.status.label.toLowerCase()}.'));
    final requested = input.cycleDate;
    if (requested != null && !requested.isSameDay(sub.nextDueDate)) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This subscription changed since you opened it. Reload and try again.'));
    }
    final next = SubscriptionSchedule.nextCycleAfterCurrent(sub);
    return Result.ok(preview(
      input,
      title: 'Skip this renewal?',
      summary: 'Skipped the ${DateFormats.dayMonth.format(sub.nextDueDate)} renewal of ${sub.name}',
      lines: [
        PreviewLine('Skipped', DateFormats.dayMonthYear.format(sub.nextDueDate)),
        PreviewLine('Next due', DateFormats.dayMonthYear.format(next)),
        const PreviewLine('Cash balance', 'Unchanged'),
      ],
    ));
  }

  @override
  Future<Result<Subscription>> execute(SkipSubscriptionCycleInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final sub = _find(s, input.subscriptionId)!;
    final updated = sub.copyWith(
      nextDueDate: SubscriptionSchedule.nextCycleAfterCurrent(sub),
      updatedAt: env.clock.now(),
      version: sub.version + 1,
    );
    await env.repos.subscriptions.save(updated);
    return Result.ok(updated);
  }
}

// ---------------------------------------------------------------------------
// Delete
// ---------------------------------------------------------------------------

class SubscriptionIdInput extends ActionInput {
  const SubscriptionIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class DeleteSubscriptionAction extends FinancialAction<SubscriptionIdInput, Subscription> {
  const DeleteSubscriptionAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'subscriptions.delete',
        module: 'subscriptions',
        title: 'Delete a subscription',
        description: 'Removes a subscription. Payments already recorded stay in your transactions.',
        risk: ActionRisk.consequential,
        reversible: false,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Subscription id')],
      );

  @override
  SubscriptionIdInput decode(Map<String, Object?> json) => SubscriptionIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(SubscriptionIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final sub = _find(s, input.id);
    if (sub == null) return const Result.err(AppFailure.notFound('This subscription no longer exists.'));
    final paid = s.linkedTransactions(sub.id).length;
    return Result.ok(preview(
      input,
      title: 'Delete ${sub.name}?',
      summary: '${sub.name} deleted',
      lines: [
        PreviewLine('Amount', '${sub.amount.format()} ${sub.frequency.label.toLowerCase()}'),
        PreviewLine('Recorded payments', paid == 0 ? 'None' : '$paid kept in transactions'),
      ],
      warnings: const ['This cannot be undone. To stop tracking without losing it, cancel instead.'],
    ));
  }

  @override
  Future<Result<Subscription>> execute(SubscriptionIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final sub = _find(s, input.id)!;
    await env.repos.subscriptions.delete(sub.id);
    return Result.ok(sub);
  }
}
