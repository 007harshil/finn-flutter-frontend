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
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';
import '../../settings/application/tracking_start.dart';

class LoanInput extends ActionInput {
  const LoanInput({
    required this.name,
    required this.counterparty,
    required this.direction,
    required this.structure,
    required this.principal,
    required this.rate,
    required this.startDate,
    required this.firstDueDate,
    required this.frequency,
    this.tenureInstallments,
    this.maturityDate,
    this.prepaymentStrategy = PrepaymentStrategy.reduceTenure,
    this.recordDisbursement = false,
    this.note,
  });

  final String name;
  final String counterparty;
  final LoanDirection direction;
  final LoanStructure structure;
  final Money principal;
  final InterestRate rate;
  final DateTime startDate;
  final DateTime firstDueDate;
  final Frequency frequency;
  final int? tenureInstallments;
  final DateTime? maturityDate;
  final PrepaymentStrategy prepaymentStrategy;

  /// Record the disbursement as a cash movement (borrowed: money in;
  /// lent: money out). Leave false for loans taken before tracking began.
  final bool recordDisbursement;
  final String? note;

  factory LoanInput.fromJson(Map<String, Object?> j) => LoanInput(
    name: In.str(j, 'name'),
    counterparty: In.str(j, 'counterparty'),
    direction: In.enumeration(j, 'direction', LoanDirection.values),
    structure: In.enumeration(j, 'structure', LoanStructure.values),
    principal: In.money(j, 'principal'),
    rate: InterestRate(In.integer(j, 'rateBps')),
    startDate: In.date(j, 'startDate'),
    firstDueDate: In.date(j, 'firstDueDate'),
    frequency: In.enumeration(j, 'frequency', Frequency.values),
    tenureInstallments: In.intOpt(j, 'tenureInstallments'),
    maturityDate: In.dateOpt(j, 'maturityDate'),
    prepaymentStrategy:
        In.enumOpt(j, 'prepaymentStrategy', PrepaymentStrategy.values) ?? PrepaymentStrategy.reduceTenure,
    recordDisbursement: In.boolean(j, 'recordDisbursement', fallback: false),
    note: In.strOpt(j, 'note'),
  );

  @override
  Map<String, Object?> toJson() => {
    'name': name,
    'counterparty': counterparty,
    'direction': direction.name,
    'structure': structure.name,
    'principal': Out.money(principal),
    'rateBps': rate.bps,
    'startDate': Out.date(startDate),
    'firstDueDate': Out.date(firstDueDate),
    'frequency': frequency.name,
    'tenureInstallments': tenureInstallments,
    'maturityDate': Out.dateOpt(maturityDate),
    'prepaymentStrategy': prepaymentStrategy.name,
    'recordDisbursement': recordDisbursement,
    'note': note,
  };

  Loan toLoan(String id, DateTime now, {String? disbursementTransactionId, int version = 1, DateTime? createdAt}) =>
      Loan(
        id: id,
        name: name.trim(),
        counterparty: counterparty.trim(),
        direction: direction,
        structure: structure,
        principal: principal,
        rate: rate,
        startDate: startDate.dateOnly,
        firstDueDate: firstDueDate.dateOnly,
        frequency: frequency,
        tenureInstallments: structure == LoanStructure.amortizing ? tenureInstallments : null,
        maturityDate: structure == LoanStructure.interestOnly ? maturityDate?.dateOnly : null,
        prepaymentStrategy: prepaymentStrategy,
        disbursementTransactionId: disbursementTransactionId,
        note: note,
        createdAt: createdAt ?? now,
        updatedAt: now,
        version: version,
      );
}

const _calc = LoanCalculator();

Map<String, String> validateLoan(LoanInput i, FinanceSnapshot s) {
  final e = <String, String>{};
  if (i.name.trim().isEmpty) e['name'] = 'Give this loan a name.';
  if (i.counterparty.trim().isEmpty) {
    e['counterparty'] = i.direction == LoanDirection.borrowed ? 'Who lent you the money?' : 'Who did you lend to?';
  }
  if (!i.principal.isPositive) e['principal'] = 'Enter the loan amount.';
  if (i.principal > maxTransactionAmount) e['principal'] = 'That amount looks too large. Please check it.';
  if (i.rate.bps < 0 || i.rate.bps > 6000) e['rate'] = 'Enter an annual rate between 0% and 60%.';
  if (i.frequency == Frequency.weekly) e['frequency'] = 'Weekly repayment is not supported.';
  if (i.firstDueDate.dateOnly.isBefore(i.startDate.dateOnly)) {
    e['firstDueDate'] = 'The first due date must be after the start date.';
  }
  if (i.recordDisbursement && i.startDate.dateOnly.isAfter(s.today)) {
    e['startDate'] = 'A future disbursement cannot be recorded as cash yet.';
  }
  if (i.structure == LoanStructure.amortizing) {
    final n = i.tenureInstallments;
    if (n == null || n < 1 || n > 480) {
      e['tenureInstallments'] = 'Enter between 1 and 480 instalments.';
    } else if (i.principal.isPositive && i.rate.bps >= 0) {
      final emi = _calc.emi(i.principal, i.rate, n, i.frequency.periodsPerYear);
      if (emi <= _calc.periodInterest(i.principal, i.rate, i.frequency.periodsPerYear)) {
        e['tenureInstallments'] = 'This tenure never repays the principal.';
      }
    }
  } else if (i.maturityDate != null && i.maturityDate!.dateOnly.isBefore(i.firstDueDate.dateOnly)) {
    e['maturityDate'] = 'Maturity must be after the first due date.';
  }
  return e;
}

class CreateLoanAction extends FinancialAction<LoanInput, Loan> {
  const CreateLoanAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'loans.create',
    module: 'loans',
    title: 'Add a loan',
    description: 'Adds a borrowed or lent loan (EMI or interest-only). Optionally records the disbursement as cash.',
    risk: ActionRisk.low,
    fields: [
      ActionFieldSpec('name', FieldKind.string, 'Label, e.g. "Car loan"'),
      ActionFieldSpec('counterparty', FieldKind.string, 'Bank or person'),
      ActionFieldSpec('direction', FieldKind.enumeration, 'borrowed or lent', allowedValues: ['borrowed', 'lent']),
      ActionFieldSpec(
        'structure',
        FieldKind.enumeration,
        'amortizing (EMI) or interestOnly',
        allowedValues: ['amortizing', 'interestOnly'],
      ),
      ActionFieldSpec('principal', FieldKind.money, 'Loan amount'),
      ActionFieldSpec('rateBps', FieldKind.rate, 'Annual interest in basis points (10.5% = 1050)'),
      ActionFieldSpec('startDate', FieldKind.date, 'Disbursement date'),
      ActionFieldSpec('firstDueDate', FieldKind.date, 'First instalment/interest due date'),
      ActionFieldSpec(
        'frequency',
        FieldKind.enumeration,
        'Repayment frequency',
        allowedValues: ['monthly', 'quarterly', 'halfYearly', 'yearly'],
      ),
      ActionFieldSpec('tenureInstallments', FieldKind.integer, 'Number of EMIs (amortizing only)', required: false),
      ActionFieldSpec('maturityDate', FieldKind.date, 'Principal due date (interest-only, optional)', required: false),
      ActionFieldSpec(
        'recordDisbursement',
        FieldKind.boolean,
        'Record the disbursement as a cash movement',
        required: false,
      ),
    ],
  );

  @override
  LoanInput decode(Map<String, Object?> json) => LoanInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(LoanInput input, FinanceSnapshot s, ActionEnvironment env) {
    final e = validateLoan(input, s);
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final ppy = input.frequency.periodsPerYear;
    final lines = <PreviewLine>[
      PreviewLine('Principal', input.principal.format(), emphasis: true),
      PreviewLine('Interest', '${input.rate.label} p.a. · ${input.structure.label}'),
    ];
    if (input.structure == LoanStructure.amortizing) {
      final schedule = _calc.originalSchedule(input.toLoan('preview', env.clock.now()));
      lines
        ..add(
          PreviewLine(
            '${input.frequency.label} EMI',
            _calc.emi(input.principal, input.rate, input.tenureInstallments!, ppy).format(),
          ),
        )
        ..add(PreviewLine('Total interest', Money.sum(schedule.map((r) => r.interest)).format()))
        ..add(PreviewLine('Last instalment', DateFormats.dayMonthYear.format(schedule.last.dueDate)));
    } else {
      lines.add(
        PreviewLine(
          'Interest per ${input.frequency.unit}',
          _calc.periodInterest(input.principal, input.rate, ppy).format(),
        ),
      );
    }
    lines.add(
      PreviewLine(
        'Cash balance',
        !input.recordDisbursement
            ? 'Unchanged (existing loan)'
            : (input.direction == LoanDirection.borrowed
                  ? input.principal.format(sign: SignDisplay.always)
                  : (-input.principal).format()),
      ),
    );
    return Result.ok(
      preview(
        input,
        title: 'Add ${input.name}',
        summary:
            '${input.direction.phrase} ${input.principal.format()} ${input.direction == LoanDirection.borrowed ? 'from' : 'to'} ${input.counterparty}',
        lines: lines,
        requiresConfirmation: input.recordDisbursement,
      ),
    );
  }

  @override
  Future<Result<Loan>> execute(LoanInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final id = env.ids.next('loan');
    Transaction? tx;
    if (input.recordDisbursement) {
      final borrowed = input.direction == LoanDirection.borrowed;
      tx = buildLinkedTransaction(
        env: env,
        type: borrowed ? TransactionType.income : TransactionType.expense,
        amount: input.principal,
        categoryId: borrowed ? SystemCategories.loanReceived : SystemCategories.loanGiven,
        date: input.startDate,
        origin: TransactionOrigin.loanDisbursement,
        originRefId: id,
        counterparty: input.counterparty.trim(),
        note: '${input.name} · disbursement',
        method: PaymentMethod.bankTransfer,
      );
      await env.repos.transactions.save(tx);
      await extendTrackingStart(env, tx.date);
    }
    final loan = input.toLoan(id, env.clock.now(), disbursementTransactionId: tx?.id);
    await env.repos.loans.save(loan);
    return Result.ok(loan);
  }
}

class UpdateLoanInput extends ActionInput {
  const UpdateLoanInput({required this.id, required this.expectedVersion, required this.data});
  final String id;
  final int expectedVersion;
  final LoanInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, 'expectedVersion': expectedVersion, ...data.toJson()};
}

/// Edits a loan. Terms (principal, rate, structure, dates, tenure) can only
/// change while no payments are recorded; afterwards only descriptive
/// fields and the prepayment strategy are editable.
class UpdateLoanAction extends FinancialAction<UpdateLoanInput, Loan> {
  const UpdateLoanAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'loans.update',
    module: 'loans',
    title: 'Edit a loan',
    description: 'Edits loan details. Terms are locked once payments exist.',
    risk: ActionRisk.low,
    fields: [
      ActionFieldSpec('id', FieldKind.id, 'Loan id'),
      ActionFieldSpec('expectedVersion', FieldKind.integer, 'Version read'),
    ],
  );

  @override
  UpdateLoanInput decode(Map<String, Object?> json) => UpdateLoanInput(
    id: In.str(json, 'id'),
    expectedVersion: In.integer(json, 'expectedVersion'),
    data: LoanInput.fromJson(json),
  );

  @override
  Result<ActionPreview> prepare(UpdateLoanInput input, FinanceSnapshot s, ActionEnvironment env) {
    final st = s.loan(input.id);
    if (st == null) return const Result.err(AppFailure.notFound('This loan no longer exists.'));
    if (st.loan.version != input.expectedVersion) {
      return const Result.err(
        AppFailure(FailureCode.staleData, 'This loan changed since you opened it. Reload and try again.'),
      );
    }
    final d = input.data;
    final l = st.loan;
    final termsChanged =
        d.principal != l.principal ||
        d.rate != l.rate ||
        d.structure != l.structure ||
        d.direction != l.direction ||
        d.frequency != l.frequency ||
        !d.startDate.isSameDay(l.startDate) ||
        !d.firstDueDate.isSameDay(l.firstDueDate) ||
        d.tenureInstallments != l.tenureInstallments;
    if (termsChanged && st.payments.isNotEmpty) {
      return const Result.err(
        AppFailure(
          FailureCode.notPermitted,
          'Loan terms cannot change after payments are recorded. Record a prepayment instead, or add a new loan.',
        ),
      );
    }
    final e = validateLoan(d, s)..remove('startDate');
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    return Result.ok(preview(input, title: 'Save changes', summary: 'Update ${l.name}'));
  }

  @override
  Future<Result<Loan>> execute(UpdateLoanInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final l = s.loan(input.id)!.loan;
    final updated = input.data.toLoan(
      l.id,
      env.clock.now(),
      disbursementTransactionId: l.disbursementTransactionId,
      version: l.version + 1,
      createdAt: l.createdAt,
    );
    await env.repos.loans.save(updated);
    return Result.ok(updated);
  }
}

class LoanPaymentInput extends ActionInput {
  const LoanPaymentInput({
    required this.loanId,
    required this.kind,
    required this.amount,
    required this.date,
    this.method,
    this.recordCashMovement = true,
    this.note,
  });

  final String loanId;
  final LoanPaymentKind kind;
  final Money amount;
  final DateTime date;
  final PaymentMethod? method;
  final bool recordCashMovement;
  final String? note;

  @override
  Map<String, Object?> toJson() => {
    'loanId': loanId,
    'kind': kind.name,
    'amount': Out.money(amount),
    'date': Out.date(date),
    'method': method?.name,
    'recordCashMovement': recordCashMovement,
    'note': note,
  };
}

class RecordLoanPaymentAction extends FinancialAction<LoanPaymentInput, LoanPayment> {
  const RecordLoanPaymentAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'loans.recordPayment',
    module: 'loans',
    title: 'Record a loan payment',
    description:
        'Records an EMI, an interest payment, or a principal prepayment. '
        'Interest due is paid first; the rest reduces principal.',
    risk: ActionRisk.consequential,
    movesMoney: true,
    reversible: false,
    fields: [
      ActionFieldSpec('loanId', FieldKind.id, 'Loan id'),
      ActionFieldSpec(
        'kind',
        FieldKind.enumeration,
        'installment, interest, or principal',
        allowedValues: ['installment', 'interest', 'principal'],
      ),
      ActionFieldSpec('amount', FieldKind.money, 'Amount paid (or received for lent loans)'),
      ActionFieldSpec('date', FieldKind.date, 'Payment date'),
      ActionFieldSpec('method', FieldKind.enumeration, 'Payment method', required: false),
      ActionFieldSpec(
        'recordCashMovement',
        FieldKind.boolean,
        'Create the matching cash transaction (default true)',
        required: false,
      ),
    ],
  );

  @override
  LoanPaymentInput decode(Map<String, Object?> j) => LoanPaymentInput(
    loanId: In.str(j, 'loanId'),
    kind: In.enumeration(j, 'kind', LoanPaymentKind.values),
    amount: In.money(j, 'amount'),
    date: In.date(j, 'date'),
    method: In.enumOpt(j, 'method', PaymentMethod.values),
    recordCashMovement: In.boolean(j, 'recordCashMovement', fallback: true),
    note: In.strOpt(j, 'note'),
  );

  /// Splits the payment; shared by [prepare] and the payment form.
  Result<LoanPaymentPreview> split(LoanPaymentInput input, FinanceSnapshot s) {
    final st = s.loan(input.loanId);
    if (st == null) return const Result.err(AppFailure.notFound('This loan no longer exists.'));
    if (input.date.dateOnly.isAfter(s.today)) {
      return const Result.err(
        AppFailure.validation(
          'The date cannot be in the future.',
          fields: {'date': 'The date cannot be in the future.'},
        ),
      );
    }
    if (input.date.dateOnly.isBefore(st.loan.startDate)) {
      return const Result.err(
        AppFailure.validation('The date is before the loan started.', fields: {'date': 'Before the loan start date.'}),
      );
    }
    return _calc.previewPayment(state: st, kind: input.kind, amount: input.amount);
  }

  @override
  Result<ActionPreview> prepare(LoanPaymentInput input, FinanceSnapshot s, ActionEnvironment env) {
    final r = split(input, s);
    if (r case Err(:final failure)) return Result.err(failure);
    final p = (r as Ok<LoanPaymentPreview>).value;
    final loan = s.loan(input.loanId)!.loan;
    final borrowed = loan.isBorrowed;
    final warnings = <String>[];
    if (borrowed && input.recordCashMovement && input.amount > s.balance.available) {
      warnings.add('This is more than your available balance of ${s.balance.available.format()}.');
    }
    if (p.includesPrepayment && input.kind != LoanPaymentKind.principal) {
      warnings.add(
        'Includes ${(input.amount - p.interestPortion - (s.loan(input.loanId)!.nextDue?.principal ?? Money.zero)).format()} extra towards principal.',
      );
    }
    return Result.ok(
      preview(
        input,
        title: borrowed ? 'Record ${input.kind.label.toLowerCase()}' : 'Record repayment received',
        summary: '${borrowed ? 'Pay' : 'Receive'} ${input.amount.format()} · ${loan.name}',
        lines: [
          if (p.periodNumber != null)
            PreviewLine(
              loan.isAmortizing ? 'Instalment' : 'Interest period',
              '#${p.periodNumber}${p.dueDate == null ? '' : ' · due ${DateFormats.dayMonthYear.format(p.dueDate!)}'}',
            ),
          PreviewLine('Towards interest', p.interestPortion.format()),
          PreviewLine('Towards principal', p.principalPortion.format(), emphasis: true),
          PreviewLine('Outstanding', '${p.outstandingBefore.format()} → ${p.outstandingAfter.format()}'),
          PreviewLine(
            'Cash balance',
            !input.recordCashMovement
                ? 'Not recorded as cash'
                : (borrowed ? (-input.amount).format() : input.amount.format(sign: SignDisplay.always)),
          ),
        ],
        warnings: [...warnings, if (p.closesLoan) 'This payment closes the loan.'],
        basis: {
          'v': loan.version,
          'payments': s.loan(input.loanId)!.payments.length,
          'outstanding': p.outstandingBefore.paise,
        },
      ),
    );
  }

  @override
  Future<Result<LoanPayment>> execute(LoanPaymentInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final p = (split(input, s) as Ok<LoanPaymentPreview>).value;
    final loan = s.loan(input.loanId)!.loan;
    Transaction? tx;
    if (input.recordCashMovement) {
      tx = buildLinkedTransaction(
        env: env,
        type: loan.isBorrowed ? TransactionType.expense : TransactionType.income,
        amount: input.amount,
        categoryId: loan.isBorrowed ? SystemCategories.loanEmi : SystemCategories.loanRepaymentReceived,
        date: input.date,
        origin: TransactionOrigin.loanRepayment,
        originRefId: loan.id,
        method: input.method,
        counterparty: loan.counterparty,
        note: '${loan.name} · ${input.kind.label}${p.periodNumber != null ? ' #${p.periodNumber}' : ''}',
      );
      await env.repos.transactions.save(tx);
      await extendTrackingStart(env, tx.date);
    }
    final payment = LoanPayment(
      id: env.ids.next('lp'),
      loanId: loan.id,
      kind: input.kind,
      date: input.date.dateOnly,
      interestComponent: p.interestPortion,
      principalComponent: p.principalPortion,
      periodNumber: p.periodNumber,
      transactionId: tx?.id,
      note: input.note,
      createdAt: env.clock.now(),
    );
    try {
      await env.repos.loanPayments.save(payment);
      if (p.closesLoan) {
        await env.repos.loans.save(
          loan.copyWith(status: LoanStatus.closed, updatedAt: env.clock.now(), version: loan.version + 1),
        );
      }
    } catch (_) {
      if (tx != null) await env.repos.transactions.delete(tx.id);
      rethrow;
    }
    return Result.ok(payment);
  }
}

class LoanIdInput extends ActionInput {
  const LoanIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

/// Deletes a loan with no recorded payments (and its disbursement entry).
class DeleteLoanAction extends FinancialAction<LoanIdInput, Loan> {
  const DeleteLoanAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
    id: 'loans.delete',
    module: 'loans',
    title: 'Delete a loan',
    description: 'Removes a loan added by mistake. Loans with payments cannot be deleted.',
    risk: ActionRisk.consequential,
    reversible: false,
    movesMoney: true,
    fields: [ActionFieldSpec('id', FieldKind.id, 'Loan id')],
  );

  @override
  LoanIdInput decode(Map<String, Object?> json) => LoanIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(LoanIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final st = s.loan(input.id);
    if (st == null) return const Result.err(AppFailure.notFound('This loan no longer exists.'));
    if (st.payments.isNotEmpty) {
      return const Result.err(
        AppFailure(FailureCode.notPermitted, 'This loan has payments recorded, so it is kept for your history.'),
      );
    }
    return Result.ok(
      preview(
        input,
        title: 'Delete ${st.loan.name}?',
        summary: 'Delete ${st.loan.name} with ${st.loan.counterparty}',
        warnings: [
          if (st.loan.disbursementTransactionId != null) 'The recorded disbursement transaction will also be removed.',
          'This cannot be undone.',
        ],
        basis: {'v': st.loan.version},
      ),
    );
  }

  @override
  Future<Result<Loan>> execute(LoanIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final l = s.loan(input.id)!.loan;
    if (l.disbursementTransactionId != null) await env.repos.transactions.delete(l.disbursementTransactionId!);
    await env.repos.loans.delete(l.id);
    return Result.ok(l);
  }
}
