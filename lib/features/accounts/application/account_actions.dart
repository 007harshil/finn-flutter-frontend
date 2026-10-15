import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../domain/money_account.dart';

/// Largest balance accepted (Rs 1,000 crore) — guards against typos.
const Money maxAccountAmount = Money.rupees(10000000000);

/// Input for creating or editing a money account.
class AccountInput extends ActionInput {
  const AccountInput({
    required this.name,
    required this.kind,
    required this.openingBalance,
    this.institution,
    this.last4,
    this.openingDate,
    this.creditLimit,
    this.isDefault,
    this.note,
  });

  final String name;
  final MoneyAccountKind kind;

  /// Asset kinds: money in it on [openingDate]. Credit card: amount owed.
  final Money openingBalance;
  final String? institution;
  final String? last4;

  /// Defaults to today on create.
  final DateTime? openingDate;
  final Money? creditLimit;

  /// Create only: make this the default account.
  final bool? isDefault;
  final String? note;

  factory AccountInput.fromJson(Map<String, Object?> j) => AccountInput(
        name: In.str(j, 'name'),
        kind: In.enumeration(j, 'kind', MoneyAccountKind.values),
        institution: In.strOpt(j, 'institution'),
        last4: In.strOpt(j, 'last4'),
        openingBalance: In.money(j, 'openingBalance'),
        openingDate: In.dateOpt(j, 'openingDate'),
        creditLimit: In.moneyOpt(j, 'creditLimit'),
        isDefault: j['isDefault'] == null ? null : In.boolean(j, 'isDefault'),
        note: In.strOpt(j, 'note'),
      );

  @override
  Map<String, Object?> toJson() => {
        'name': name,
        'kind': kind.name,
        'institution': institution,
        'last4': last4,
        'openingBalance': Out.money(openingBalance),
        'openingDate': Out.dateOpt(openingDate),
        'creditLimit': Out.moneyOpt(creditLimit),
        if (isDefault != null) 'isDefault': isDefault,
        'note': note,
      };
}

const _fields = [
  ActionFieldSpec('name', FieldKind.string, 'Account name, 1–40 characters, e.g. "SBI" or "HDFC Millennia"'),
  ActionFieldSpec('kind', FieldKind.enumeration, 'Kind of account',
      allowedValues: ['cash', 'bank', 'debitCard', 'creditCard', 'promoCard', 'otherCard']),
  ActionFieldSpec('institution', FieldKind.string, 'Bank or card issuer, up to 40 characters', required: false),
  ActionFieldSpec('last4', FieldKind.string, 'Last 4 digits (cards only)', required: false),
  ActionFieldSpec('openingBalance', FieldKind.money,
      'Money in the account on the opening date (credit card: amount owed). Zero or more'),
  ActionFieldSpec('openingDate', FieldKind.date, 'Date the opening balance is as of (default today)', required: false),
  ActionFieldSpec('creditLimit', FieldKind.money, 'Credit limit (credit cards only)', required: false),
  ActionFieldSpec('isDefault', FieldKind.boolean, 'Make this the default account', required: false),
  ActionFieldSpec('note', FieldKind.string, 'Note, up to 200 characters', required: false),
];

/// Fields of accounts.update: the create fields without `isDefault` (use
/// accounts.setDefault).
final _updateFields = [
  for (final f in _fields)
    if (f.name != 'isDefault') f,
];

String? _clean(String? v) {
  final t = v?.trim();
  return t == null || t.isEmpty ? null : t;
}

Map<String, String> validateAccount(AccountInput i, FinanceSnapshot s) {
  final e = <String, String>{};
  final name = i.name.trim();
  if (name.isEmpty) {
    e['name'] = 'Enter a name.';
  } else if (name.length > 40) {
    e['name'] = 'Keep the name under 40 characters.';
  }
  if ((i.institution?.trim().length ?? 0) > 40) e['institution'] = 'Keep this under 40 characters.';
  final last4 = _clean(i.last4);
  if (last4 != null) {
    if (!i.kind.isCard) {
      e['last4'] = 'Only cards have last 4 digits.';
    } else if (!RegExp(r'^\d{4}$').hasMatch(last4)) {
      e['last4'] = 'Enter exactly 4 digits.';
    }
  }
  if (i.openingBalance.isNegative) e['openingBalance'] = 'Enter zero or more.';
  if (i.openingBalance > maxAccountAmount) e['openingBalance'] = 'That amount looks too large. Please check it.';
  final date = i.openingDate;
  if (date != null && date.dateOnly.isAfter(s.today)) e['openingDate'] = 'The date cannot be in the future.';
  final limit = i.creditLimit;
  if (limit != null) {
    if (i.kind != MoneyAccountKind.creditCard) {
      e['creditLimit'] = 'Only credit cards have a limit.';
    } else if (limit.isNegative) {
      e['creditLimit'] = 'Enter zero or more.';
    } else if (limit > maxAccountAmount) {
      e['creditLimit'] = 'That amount looks too large. Please check it.';
    }
  }
  if ((i.note?.length ?? 0) > 200) e['note'] = 'Keep the note under 200 characters.';
  return e;
}

List<PreviewLine> _lines(AccountInput i, FinanceSnapshot s) => [
      PreviewLine('Account', i.name.trim()),
      PreviewLine('Kind', i.kind.label),
      if (_clean(i.institution) != null) PreviewLine('Institution', _clean(i.institution)!),
      if (_clean(i.last4) != null) PreviewLine('Card', '····${_clean(i.last4)}'),
      PreviewLine(i.kind.isLiability ? 'Owed' : 'Opening balance', i.openingBalance.format(), emphasis: true),
      PreviewLine('As of', DateFormats.dayMonthYear.format(i.openingDate ?? s.today)),
      if (i.creditLimit != null) PreviewLine('Credit limit', i.creditLimit!.format()),
    ];

bool _hasMovements(FinanceSnapshot s, String accountId) =>
    s.transactions.any((t) => t.accountId == accountId) ||
    s.transfers.any((t) => t.fromAccountId == accountId || t.toAccountId == accountId);

bool _isReferenced(FinanceSnapshot s, String accountId) =>
    _hasMovements(s, accountId) ||
    s.subscriptions.any((x) => x.accountId == accountId) ||
    s.settlements.any((x) => x.accountId == accountId);

/// Account balance after changing opening values (preview helper).
AccountBalance? _balanceOf(FinanceSnapshot s, String id) =>
    s.accountBalances.where((b) => b.account.id == id).firstOrNull;

// ---------------------------------------------------------------------------
// accounts.create
// ---------------------------------------------------------------------------

class CreateAccountAction extends FinancialAction<AccountInput, MoneyAccount> {
  const CreateAccountAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'accounts.create',
        module: 'accounts',
        title: 'Add an account',
        description: 'Adds cash, a bank account or a card with its own balance. '
            'Credit cards are tracked as amount owed and never count as money.',
        risk: ActionRisk.low,
        movesMoney: true,
        fields: _fields,
      );

  @override
  AccountInput decode(Map<String, Object?> json) => AccountInput.fromJson(json);

  @override
  Result<ActionPreview> prepare(AccountInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateAccount(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final warnings = <String>[
      if (s.accounts.any((a) => a.kind == input.kind && a.name.trim().toLowerCase() == input.name.trim().toLowerCase()))
        'You already have a ${input.kind.label.toLowerCase()} called "${input.name.trim()}".',
    ];
    return Result.ok(preview(
      input,
      title: 'Add account',
      summary: 'Added ${input.name.trim()}',
      lines: _lines(input, s),
      warnings: warnings,
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(AccountInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final now = env.clock.now();
    final hasDefault = s.activeAccounts.any((a) => a.isDefault);
    final makeDefault = input.isDefault == true || !hasDefault;
    if (makeDefault) {
      for (final a in s.accounts.where((a) => a.isDefault)) {
        await env.repos.moneyAccounts.save(
          a.copyWith(isDefault: false, updatedAt: now, version: a.version + 1),
        );
      }
    }
    final nextOrder = s.accounts.isEmpty ? 0 : s.accounts.map((a) => a.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    final account = MoneyAccount(
      id: env.ids.next('acc'),
      name: input.name.trim(),
      kind: input.kind,
      institution: _clean(input.institution),
      last4: _clean(input.last4),
      opening: input.openingBalance,
      openingDate: (input.openingDate ?? s.today).dateOnly,
      creditLimit: input.creditLimit == null || input.creditLimit!.isZero ? null : input.creditLimit,
      isDefault: makeDefault,
      sortOrder: nextOrder,
      note: _clean(input.note),
      createdAt: now,
      updatedAt: now,
    );
    await env.repos.moneyAccounts.save(account);
    return Result.ok(account);
  }
}

// ---------------------------------------------------------------------------
// accounts.update
// ---------------------------------------------------------------------------

class UpdateAccountInput extends ActionInput {
  const UpdateAccountInput({required this.id, this.version, required this.data});
  final String id;

  /// Version the user edited; a mismatch means it changed elsewhere.
  final int? version;
  final AccountInput data;

  @override
  Map<String, Object?> toJson() => {'id': id, if (version != null) 'version': version, ...data.toJson()};
}

class UpdateAccountAction extends FinancialAction<UpdateAccountInput, MoneyAccount> {
  const UpdateAccountAction();

  @override
  ActionDescriptor get descriptor => ActionDescriptor(
        id: 'accounts.update',
        module: 'accounts',
        title: 'Edit an account',
        description: 'Changes an account\'s name, kind, opening balance or limit. Balances update automatically. '
            'Switching between a credit card and any other kind is only possible while it has no movements.',
        risk: ActionRisk.low,
        movesMoney: true,
        fields: [
          const ActionFieldSpec('id', FieldKind.id, 'Account id'),
          const ActionFieldSpec('version', FieldKind.integer, 'Version that was read', required: false),
          ..._updateFields,
        ],
      );

  @override
  UpdateAccountInput decode(Map<String, Object?> json) => UpdateAccountInput(
        id: In.str(json, 'id'),
        version: In.intOpt(json, 'version') ?? In.intOpt(json, 'expectedVersion'),
        data: AccountInput.fromJson(json),
      );

  @override
  Result<ActionPreview> prepare(UpdateAccountInput input, FinanceSnapshot s, ActionEnvironment env) {
    final existing = s.account(input.id);
    if (existing == null) return const Result.err(AppFailure.notFound('This account no longer exists.'));
    if (input.version != null && existing.version != input.version) {
      return const Result.err(
          AppFailure(FailureCode.staleData, 'This account changed since you opened it. Reload and try again.'));
    }
    final errors = validateAccount(input.data, s);
    if (input.data.kind.isLiability != existing.kind.isLiability && _hasMovements(s, existing.id)) {
      errors['kind'] = 'This account has movements, so it cannot become '
          '${input.data.kind.isLiability ? 'a credit card' : 'a non-credit account'}.';
    }
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    return Result.ok(preview(
      input,
      title: 'Save changes',
      summary: 'Updated ${input.data.name.trim()}',
      lines: _lines(input.data, s),
      warnings: [
        if (s.accounts.any((a) =>
            a.id != existing.id &&
            a.kind == input.data.kind &&
            a.name.trim().toLowerCase() == input.data.name.trim().toLowerCase()))
          'You already have a ${input.data.kind.label.toLowerCase()} called "${input.data.name.trim()}".',
      ],
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(UpdateAccountInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final existing = s.account(input.id)!;
    final d = input.data;
    final updated = existing.copyWith(
      name: d.name.trim(),
      kind: d.kind,
      institution: () => _clean(d.institution),
      last4: () => _clean(d.last4),
      opening: d.openingBalance,
      openingDate: (d.openingDate ?? existing.openingDate).dateOnly,
      creditLimit: () =>
          d.kind == MoneyAccountKind.creditCard && d.creditLimit != null && !d.creditLimit!.isZero ? d.creditLimit : null,
      note: () => _clean(d.note),
      updatedAt: env.clock.now(),
      version: existing.version + 1,
    );
    await env.repos.moneyAccounts.save(updated);
    return Result.ok(updated);
  }
}

// ---------------------------------------------------------------------------
// accounts.setBalance ("Correct balance")
// ---------------------------------------------------------------------------

class SetAccountBalanceInput extends ActionInput {
  const SetAccountBalanceInput({required this.id, required this.balance, this.asOf});
  final String id;

  /// The balance the account should show (amount owed for credit cards).
  final Money balance;

  /// Defaults to today.
  final DateTime? asOf;

  @override
  Map<String, Object?> toJson() => {'id': id, 'balance': Out.money(balance), 'asOf': Out.dateOpt(asOf)};
}

class SetAccountBalanceAction extends FinancialAction<SetAccountBalanceInput, MoneyAccount> {
  const SetAccountBalanceAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'accounts.setBalance',
        module: 'accounts',
        title: 'Correct an account balance',
        description: 'Sets the account\'s opening figures so its balance today (amount owed for a credit card) '
            'equals the value given. Existing transactions are kept.',
        risk: ActionRisk.consequential,
        movesMoney: true,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Account id'),
          ActionFieldSpec('balance', FieldKind.money, 'What the account should show now (credit card: amount owed)'),
          ActionFieldSpec('asOf', FieldKind.date, 'Date the balance is as of (default today)', required: false),
        ],
      );

  @override
  SetAccountBalanceInput decode(Map<String, Object?> json) => SetAccountBalanceInput(
        id: In.str(json, 'id'),
        balance: In.money(json, 'balance'),
        asOf: In.dateOpt(json, 'asOf'),
      );

  /// The opening amount that makes the balance on today equal the target
  /// when counting from [asOf]. Credit cards owe `opening - flow`.
  /// Keeps the account's opening date; when that would need a negative
  /// opening amount the opening date moves to `asOf` (like the server).
  static ({Money opening, DateTime date}) _newOpening(SetAccountBalanceInput i, MoneyAccount a, FinanceSnapshot s) {
    Money from(DateTime start) {
      final flow = FinanceSnapshot.ledgerCalc.accountFlow(
        accountId: a.id,
        from: start,
        to: s.today,
        transactions: s.transactions,
        transfers: s.transfers,
      );
      return a.isLiability ? i.balance + flow : i.balance - flow;
    }

    final kept = from(a.openingDate.dateOnly);
    if (!kept.isNegative) return (opening: kept, date: a.openingDate.dateOnly);
    final asOf = (i.asOf ?? s.today).dateOnly;
    return (opening: from(asOf), date: asOf);
  }

  @override
  Result<ActionPreview> prepare(SetAccountBalanceInput input, FinanceSnapshot s, ActionEnvironment env) {
    final a = s.account(input.id);
    if (a == null) return const Result.err(AppFailure.notFound('This account no longer exists.'));
    final e = <String, String>{};
    if (input.balance.isNegative && a.isLiability) e['balance'] = 'Enter zero or more.';
    if (input.balance.paise.abs() > maxAccountAmount.paise) e['balance'] = 'That amount looks too large. Please check it.';
    if (input.asOf != null && input.asOf!.dateOnly.isAfter(s.today)) e['asOf'] = 'The date cannot be in the future.';
    if (e.isEmpty && _newOpening(input, a, s).opening.isNegative) {
      e['balance'] = 'Movements since then are larger than that balance. Edit those transactions instead.';
    }
    if (e.isNotEmpty) return Result.err(AppFailure.validation(e.values.first, fields: e));
    final old = _balanceOf(s, a.id)?.balance ?? Money.zero;
    return Result.ok(preview(
      input,
      title: 'Correct balance',
      summary: '${a.name} ${a.isLiability ? 'owed' : 'balance'} set to ${input.balance.format()}',
      lines: [
        PreviewLine('Account', a.name),
        PreviewLine(a.isLiability ? 'Owed' : 'Balance', '${old.format()} → ${input.balance.format()}', emphasis: true),
      ],
      warnings: const ['Your transactions are kept. The account\'s opening figures change to match.'],
      basis: {'v': a.version, 'bal': old.paise},
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(SetAccountBalanceInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final a = s.account(input.id)!;
    final updated = a.copyWith(
      opening: _newOpening(input, a, s).opening,
      openingDate: _newOpening(input, a, s).date,
      updatedAt: env.clock.now(),
      version: a.version + 1,
    );
    await env.repos.moneyAccounts.save(updated);
    return Result.ok(updated);
  }
}

// ---------------------------------------------------------------------------
// accounts.setDefault / accounts.archive / accounts.delete
// ---------------------------------------------------------------------------

class AccountIdInput extends ActionInput {
  const AccountIdInput({required this.id});
  final String id;

  @override
  Map<String, Object?> toJson() => {'id': id};
}

class SetDefaultAccountAction extends FinancialAction<AccountIdInput, MoneyAccount> {
  const SetDefaultAccountAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'accounts.setDefault',
        module: 'accounts',
        title: 'Set the default account',
        description: 'Makes an account the one preselected in forms and used when none is given.',
        risk: ActionRisk.low,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Account id')],
      );

  @override
  AccountIdInput decode(Map<String, Object?> json) => AccountIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(AccountIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final a = s.account(input.id);
    if (a == null) return const Result.err(AppFailure.notFound('This account no longer exists.'));
    if (a.isArchived) return Result.err(AppFailure.validation('${a.name} is archived. Restore it first.'));
    return Result.ok(preview(
      input,
      title: 'Set default account',
      summary: '${a.name} is now your default account',
      lines: [PreviewLine('Default account', a.name, emphasis: true)],
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(AccountIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final a = s.account(input.id)!;
    final now = env.clock.now();
    for (final other in s.accounts.where((x) => x.isDefault && x.id != a.id)) {
      await env.repos.moneyAccounts.save(other.copyWith(isDefault: false, updatedAt: now, version: other.version + 1));
    }
    final updated = a.isDefault ? a : a.copyWith(isDefault: true, updatedAt: now, version: a.version + 1);
    if (!a.isDefault) await env.repos.moneyAccounts.save(updated);
    return Result.ok(updated);
  }
}

class ArchiveAccountInput extends ActionInput {
  const ArchiveAccountInput({required this.id, required this.archived});
  final String id;
  final bool archived;

  @override
  Map<String, Object?> toJson() => {'id': id, 'archived': archived};
}

class ArchiveAccountAction extends FinancialAction<ArchiveAccountInput, MoneyAccount> {
  const ArchiveAccountAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'accounts.archive',
        module: 'accounts',
        title: 'Archive or restore an account',
        description: 'Hides an account from pickers and Home. History and balance are kept. '
            'The default or last active account cannot be archived.',
        risk: ActionRisk.low,
        fields: [
          ActionFieldSpec('id', FieldKind.id, 'Account id'),
          ActionFieldSpec('archived', FieldKind.boolean, 'true to archive, false to restore'),
        ],
      );

  @override
  ArchiveAccountInput decode(Map<String, Object?> json) =>
      ArchiveAccountInput(id: In.str(json, 'id'), archived: In.boolean(json, 'archived'));

  @override
  Result<ActionPreview> prepare(ArchiveAccountInput input, FinanceSnapshot s, ActionEnvironment env) {
    final a = s.account(input.id);
    if (a == null) return const Result.err(AppFailure.notFound('This account no longer exists.'));
    if (input.archived && !a.isArchived) {
      if (a.isDefault) {
        return const Result.err(AppFailure.validation('Choose another default account before archiving this one.'));
      }
      if (s.activeAccounts.length <= 1) {
        return const Result.err(AppFailure.validation('You need at least one active account.'));
      }
    }
    return Result.ok(preview(
      input,
      title: input.archived ? 'Archive account' : 'Restore account',
      summary: input.archived ? 'Archived ${a.name}' : 'Restored ${a.name}',
      lines: [PreviewLine('Account', a.name)],
      warnings: [if (input.archived) 'Its history and balance are kept. It is hidden from pickers and Home.'],
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(ArchiveAccountInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final a = s.account(input.id)!;
    if (a.isArchived == input.archived) return Result.ok(a);
    final updated = a.copyWith(isArchived: input.archived, updatedAt: env.clock.now(), version: a.version + 1);
    await env.repos.moneyAccounts.save(updated);
    return Result.ok(updated);
  }
}

class DeleteAccountAction extends FinancialAction<AccountIdInput, MoneyAccount> {
  const DeleteAccountAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'accounts.delete',
        module: 'accounts',
        title: 'Delete an account',
        description: 'Removes an account that nothing refers to. Accounts with transactions, transfers, '
            'subscriptions or settlements must be archived instead.',
        risk: ActionRisk.consequential,
        reversible: false,
        fields: [ActionFieldSpec('id', FieldKind.id, 'Account id')],
      );

  @override
  AccountIdInput decode(Map<String, Object?> json) => AccountIdInput(id: In.str(json, 'id'));

  @override
  Result<ActionPreview> prepare(AccountIdInput input, FinanceSnapshot s, ActionEnvironment env) {
    final a = s.account(input.id);
    if (a == null) return const Result.err(AppFailure.notFound('This account no longer exists.'));
    if (s.accounts.length <= 1) {
      return const Result.err(AppFailure.validation('You need at least one account.'));
    }
    if (_isReferenced(s, a.id)) {
      return Result.err(AppFailure.validation(
          '${a.name} is used by existing transactions, transfers or subscriptions. Archive it instead.'));
    }
    return Result.ok(preview(
      input,
      title: 'Delete account?',
      summary: 'Deleted ${a.name}',
      lines: [PreviewLine('Account', a.name), PreviewLine('Kind', a.kind.label)],
      warnings: const ['This cannot be undone.'],
      basis: {'v': a.version},
    ));
  }

  @override
  Future<Result<MoneyAccount>> execute(AccountIdInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final a = s.account(input.id)!;
    await env.repos.moneyAccounts.delete(a.id);
    if (a.isDefault) {
      // Hand the default to the next active account.
      final next = s.activeAccounts.where((x) => x.id != a.id).firstOrNull;
      if (next != null) {
        await env.repos.moneyAccounts.save(
          next.copyWith(isDefault: true, updatedAt: env.clock.now(), version: next.version + 1),
        );
      }
    }
    return Result.ok(a);
  }
}
