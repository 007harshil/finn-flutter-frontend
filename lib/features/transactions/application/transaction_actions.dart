import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/clock.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/transaction.dart';

/// Input for creating or updating a manual transaction.
class TransactionInput extends ActionInput {
  const TransactionInput({
    required this.type,
    required this.amount,
    required this.categoryId,
    required this.date,
    this.paymentMethod,
    this.counterparty,
    this.note,
  });

  final TransactionType type;
  final Money amount;
  final String categoryId;
  final DateTime date;
  final PaymentMethod? paymentMethod;
  final String? counterparty;
  final String? note;

  factory TransactionInput.fromJson(Map<String, Object?> j) => TransactionInput(
    type: In.enumeration(j, 'type', TransactionType.values),
    amount: In.money(j, 'amount'),
    categoryId: In.str(j, 'categoryId'),
    date: In.date(j, 'date'),
    paymentMethod: In.enumOpt(j, 'paymentMethod', PaymentMethod.values),
    counterparty: In.strOpt(j, 'counterparty'),
    note: In.strOpt(j, 'note'),
  );

  @override
  Map<String, Object?> toJson() => {
    'type': type.name,
    'amount': Out.money(amount),
    'categoryId': categoryId,
    'date': Out.date(date),
    'paymentMethod': paymentMethod?.name,
    'counterparty': counterparty,
    'note': note,
  };
}

const _fields = [
  ActionFieldSpec('type', FieldKind.enumeration, 'income or expense', allowedValues: ['income', 'expense']),
  ActionFieldSpec('amount', FieldKind.money, 'Amount in rupees, greater than zero'),
  ActionFieldSpec('categoryId', FieldKind.id, 'Category id matching the type'),
  ActionFieldSpec('date', FieldKind.date, 'Date the money moved (not in the future)'),
  ActionFieldSpec(
    'paymentMethod',
    FieldKind.enumeration,
    'How it was paid',
    required: false,
    allowedValues: ['upi', 'card', 'cash', 'bankTransfer', 'wallet', 'other'],
  ),
  ActionFieldSpec('counterparty', FieldKind.string, 'Merchant or person', required: false),
  ActionFieldSpec('note', FieldKind.string, 'Free-text note', required: false),
];

/// Maximum single amount accepted (₹10 crore) — guards against typos.
const Money maxTransactionAmount = Money.rupees(100000000);

Map<String, String> validateTransaction(TransactionInput i, FinanceSnapshot s) {
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
  if ((i.counterparty?.length ?? 0) > 80) errors['counterparty'] = 'Keep this under 80 characters.';
  if ((i.note?.length ?? 0) > 500) errors['note'] = 'Keep the note under 500 characters.';
  return errors;
}

List<PreviewLine> _lines(TransactionInput i, FinanceSnapshot s) => [
  PreviewLine('Type', i.type.label),
  PreviewLine('Amount', i.amount.format(), emphasis: true),
  PreviewLine('Category', s.category(i.categoryId)?.name ?? '—'),
  PreviewLine('Date', DateFormats.dayMonthYear.format(i.date)),
  if (i.paymentMethod != null) PreviewLine('Paid via', i.paymentMethod!.label),
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
      paymentMethod: input.paymentMethod,
      counterparty: input.counterparty,
      note: input.note,
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.transactions.save(tx);
    return Result.ok(tx);
  }
}

extension on TransactionInput {
  bool get isExpense => type == TransactionType.expense;
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
    final errors = validateTransaction(input.data, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(
      preview(
        input,
        title: 'Save changes',
        summary:
            'Update ${existing.amount.format()} ${existing.type.label.toLowerCase()} to ${input.data.amount.format()}',
        lines: _lines(input.data, s),
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
      paymentMethod: () => d.paymentMethod,
      counterparty: () => d.counterparty,
      note: () => d.note,
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.transactions.save(updated);
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
  PaymentMethod? method,
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
    paymentMethod: method,
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
