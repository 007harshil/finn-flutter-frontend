import '../../../actions/action.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../accounts/domain/money_account.dart';
import '../domain/financial_profile.dart';

/// Input for updating the user's financial starting point.
class UpdateProfileInput extends ActionInput {
  const UpdateProfileInput({
    required this.displayName,
    required this.openingBalance,
    required this.openingDate,
    this.monthlyIncomeEstimate,
  });

  final String displayName;

  /// Cash (bank + wallet) when tracking started. Zero or more.
  final Money openingBalance;
  final DateTime openingDate;
  final Money? monthlyIncomeEstimate;

  factory UpdateProfileInput.fromJson(Map<String, Object?> j) => UpdateProfileInput(
        displayName: In.str(j, 'displayName'),
        openingBalance: In.money(j, 'openingBalance'),
        openingDate: In.date(j, 'openingDate'),
        monthlyIncomeEstimate: In.moneyOpt(j, 'monthlyIncomeEstimate'),
      );

  @override
  Map<String, Object?> toJson() => {
        'displayName': displayName,
        'openingBalance': Out.money(openingBalance),
        'openingDate': Out.date(openingDate),
        'monthlyIncomeEstimate': Out.moneyOpt(monthlyIncomeEstimate),
      };
}

/// Largest opening balance accepted (₹1,000 crore) — guards against typos.
const Money maxOpeningBalance = Money.rupees(10000000000);

Map<String, String> validateProfile(UpdateProfileInput i, FinanceSnapshot s) {
  final errors = <String, String>{};
  final name = i.displayName.trim();
  if (name.isEmpty) {
    errors['displayName'] = 'Enter a name.';
  } else if (name.length > 40) {
    errors['displayName'] = 'Keep the name under 40 characters.';
  }
  if (i.openingBalance.isNegative) errors['openingBalance'] = 'Enter zero or more.';
  if (i.openingBalance > maxOpeningBalance) errors['openingBalance'] = 'That amount looks too large. Please check it.';
  if (i.openingDate.dateOnly.isAfter(s.today)) errors['openingDate'] = 'The start date cannot be in the future.';
  final income = i.monthlyIncomeEstimate;
  if (income != null && income.isNegative) errors['monthlyIncomeEstimate'] = 'Enter zero or more.';
  if (income != null && income > maxOpeningBalance) {
    errors['monthlyIncomeEstimate'] = 'That amount looks too large. Please check it.';
  }
  return errors;
}

/// Updates (or creates) the [FinancialProfile]. Changing the opening
/// balance or date recalculates every balance, so those edits require an
/// explicit review; renaming does not.
class UpdateProfileAction extends FinancialAction<UpdateProfileInput, FinancialProfile> {
  const UpdateProfileAction();

  @override
  ActionDescriptor get descriptor => const ActionDescriptor(
        id: 'profile.update',
        module: 'settings',
        title: 'Update profile',
        description: 'Changes your name, opening balance, start date or income estimate. '
            'Changing the opening balance or start date recalculates every balance.',
        risk: ActionRisk.consequential,
        fields: [
          ActionFieldSpec('displayName', FieldKind.string, 'Name, 1–40 characters'),
          ActionFieldSpec('openingBalance', FieldKind.money, 'Cash when tracking started, zero or more'),
          ActionFieldSpec('openingDate', FieldKind.date, 'Date tracking started (not in the future)'),
          ActionFieldSpec('monthlyIncomeEstimate', FieldKind.money, 'Typical monthly income', required: false),
        ],
      );

  @override
  UpdateProfileInput decode(Map<String, Object?> json) => UpdateProfileInput.fromJson(json);

  /// Whether [input] changes the figures every balance is derived from.
  static bool changesBalances(UpdateProfileInput input, FinancialProfile? existing) =>
      existing == null ||
      existing.openingBalance != input.openingBalance ||
      !existing.openingDate.dateOnly.isSameDay(input.openingDate);

  @override
  Result<ActionPreview> prepare(UpdateProfileInput input, FinanceSnapshot s, ActionEnvironment env) {
    final errors = validateProfile(input, s);
    if (errors.isNotEmpty) return Result.err(AppFailure.validation(errors.values.first, fields: errors));
    final existing = s.profile;
    final balanceChange = changesBalances(input, existing);
    final lines = <PreviewLine>[
      PreviewLine('Name', input.displayName.trim()),
      PreviewLine('Opening balance', input.openingBalance.format(), emphasis: balanceChange),
      PreviewLine('Tracking since', DateFormats.dayMonthYear.format(input.openingDate)),
      if (input.monthlyIncomeEstimate != null) PreviewLine('Monthly income estimate', input.monthlyIncomeEstimate!.format()),
    ];
    final warnings = <String>[];
    if (balanceChange && existing != null) {
      final newCash = _cashWith(s, input);
      final delta = newCash - s.balance.cash;
      lines.add(PreviewLine('Cash balance', '${s.balance.cash.format()} → ${newCash.format()}', emphasis: true));
      warnings.add('Every balance is recalculated from the opening balance and start date '
          '(${delta.format(sign: SignDisplay.always)} change to cash).');
      if (newCash < s.balance.earmarked) {
        warnings.add('Cash would be less than the ${s.balance.earmarked.format()} earmarked for goals and emergencies.');
      }
    }
    return Result.ok(preview(
      input,
      title: balanceChange ? 'Update starting point?' : 'Save profile',
      summary: balanceChange ? 'Opening balance set to ${input.openingBalance.format()}' : 'Profile updated',
      lines: lines,
      warnings: warnings,
      requiresConfirmation: balanceChange && existing != null,
    ));
  }

  /// Cash recomputed with the new opening balance and date applied to the
  /// Cash account (`acc_cash`).
  static Money _cashWith(FinanceSnapshot s, UpdateProfileInput input) {
    final date = input.openingDate.dateOnly;
    return FinanceSnapshot.ledgerCalc
        .balance(
          profile: s.profile?.copyWith(openingBalance: input.openingBalance, openingDate: date),
          accounts: [
            for (final a in s.accounts)
              if (a.id == cashAccountId) a.copyWith(opening: input.openingBalance, openingDate: date) else a,
          ],
          transfers: s.transfers,
          transactions: s.transactions,
          movements: s.savingsMovements,
          asOf: s.today,
        )
        .cash;
  }

  @override
  Future<Result<FinancialProfile>> execute(UpdateProfileInput input, FinanceSnapshot s, ActionEnvironment env) async {
    final profile = FinancialProfile(
      displayName: input.displayName.trim(),
      openingBalance: input.openingBalance,
      openingDate: input.openingDate.dateOnly,
      monthlyIncomeEstimate: input.monthlyIncomeEstimate,
    );
    await env.repos.profile.set(profile);
    // The ledger reads the Cash account, not the profile: keep it in step.
    final now = env.clock.now();
    final cash = s.account(cashAccountId);
    if (cash != null) {
      await env.repos.moneyAccounts.save(cash.copyWith(
        opening: input.openingBalance,
        openingDate: profile.openingDate,
        updatedAt: now,
        version: cash.version + 1,
      ));
    } else if (s.accounts.isEmpty) {
      await env.repos.moneyAccounts.save(MoneyAccount(
        id: cashAccountId,
        name: 'Cash',
        kind: MoneyAccountKind.cash,
        opening: input.openingBalance,
        openingDate: profile.openingDate,
        isDefault: true,
        createdAt: now,
        updatedAt: now,
      ));
    }
    return Result.ok(profile);
  }
}
