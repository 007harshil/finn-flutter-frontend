import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/accounts/application/account_actions.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/emergency_fund/application/emergency_actions.dart';
import 'package:finn/features/goals/application/goal_actions.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

/// Mirrors finn-backend/tests/savings-accounts.test.ts. Cash (the default
/// account) holds the harness opening balance; SBI 10,000 and HDFC 4,000 are
/// added next to it.
const _rs = Money.rupees;
final _day = DateTime(2026, 10, 5);

EmergencyFundMovementInput _ef(int rupees, {String? account, DateTime? date}) =>
    EmergencyFundMovementInput(amount: _rs(rupees), date: date ?? _day, accountId: account);

GoalMovementInput _gm(String goalId, int rupees, {String? account}) =>
    GoalMovementInput(goalId: goalId, amount: _rs(rupees), date: _day, accountId: account);

GoalInput _goal(String name, int target, {int? start, String? account}) => GoalInput(
  name: name,
  category: GoalCategory.other,
  target: _rs(target),
  colorIndex: 5,
  initialAllocation: start == null ? null : _rs(start),
  accountId: account,
);

AccountBalance _row(FinanceSnapshot s, String id) => s.balance.accounts.firstWhere((a) => a.account.id == id);

void main() {
  late ActionHarness h;
  late String sbi;
  late String hdfc;

  setUp(() async {
    h = await ActionHarness.create();
    Future<String> open(String name, int rupees) async => (await h.run(
      const CreateAccountAction(),
      AccountInput(
        name: name,
        kind: MoneyAccountKind.bank,
        openingBalance: _rs(rupees),
        openingDate: DateTime(2026, 10, 1),
      ),
    )).id;
    sbi = await open('SBI', 10000);
    hdfc = await open('HDFC', 4000);
  });

  group('set aside on an account', () {
    test('a contribution lowers available (account and total) but never the balance', () async {
      final goal = await h.run(const CreateGoalAction(), _goal('Trip', 50000));
      await h.run(const GoalMovementAction.contribute(), _gm(goal.id, 3000, account: sbi));
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(1000, account: sbi));
      final s = await h.snapshot();
      final a = _row(s, sbi);
      expect(a.balance, _rs(10000));
      expect(a.earmarked, _rs(4000));
      expect(a.available, _rs(6000));
      expect(_row(s, hdfc).earmarked, Money.zero);
      expect(_row(s, hdfc).available, _rs(4000));
      expect(s.balance.cash, harnessOpening + _rs(14000));
      expect(s.balance.earmarked, _rs(4000));
      expect(s.balance.available, harnessOpening + _rs(10000));
      expect(s.balance.earmarkedUnassigned, Money.zero);
    });

    test('preview names the account and its free money', () async {
      final out = await h.dispatcher.preview(const EmergencyFundMovementAction.contribute(), _ef(1000, account: hdfc));
      final lines = {for (final l in out.valueOrNull!.lines) l.label: l.value};
      expect(lines['Set aside on'], 'HDFC');
      expect(lines['Free to spend in HDFC'], '₹4,000 → ₹3,000');
      expect(lines.containsKey('Available to spend (total)'), isTrue);
      expect(lines['Net worth'], 'Unchanged');
    });

    test('cannot set aside more than the account has free, even if other accounts do', () async {
      final err = await h.reject(const EmergencyFundMovementAction.contribute(), _ef(5000, account: hdfc));
      expect(err.fieldErrors['amount'], 'Only ₹4,000 in HDFC is free to set aside.');
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(9000, account: sbi));
      final again = await h.reject(const EmergencyFundMovementAction.contribute(), _ef(1500, account: sbi));
      expect(again.fieldErrors['amount'], 'Only ₹1,000 in SBI is free to set aside.');
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(1000, account: sbi));
      final none = await h.reject(const EmergencyFundMovementAction.contribute(), _ef(1, account: sbi));
      expect(none.fieldErrors['amount'], 'There is no free money in SBI to set aside.');
    });

    test('spending from an account leaves the set-aside amount untouched', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(8000, account: sbi));
      await h.run(
        const CreateTransactionAction(),
        TransactionInput(
          type: TransactionType.expense,
          amount: _rs(500),
          categoryId: SeedCategoryIds.rent,
          date: DateTime(2026, 10, 6),
          accountId: sbi,
        ),
      );
      final a = _row(await h.snapshot(), sbi);
      expect(a.balance, _rs(9500));
      expect(a.earmarked, _rs(8000));
      expect(a.available, _rs(1500));
    });

    test('omitting the account uses the default account; credit cards are refused', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(500));
      final cash = _row(await h.snapshot(), cashAccountId);
      expect(cash.earmarked, _rs(500));
      expect(cash.available, harnessOpening - _rs(500));
      final card = await h.run(
        const CreateAccountAction(),
        AccountInput(
          name: 'Visa',
          kind: MoneyAccountKind.creditCard,
          openingBalance: Money.zero,
          openingDate: DateTime(2026, 10, 1),
        ),
      );
      final err = await h.reject(const EmergencyFundMovementAction.contribute(), _ef(100, account: card.id));
      expect(err.fieldErrors['accountId'], 'A credit card cannot hold savings.');
      expect(err.message, 'Choose an account that holds money.');
      final unknown = await h.reject(const EmergencyFundMovementAction.contribute(), _ef(100, account: 'nope'));
      expect(unknown.fieldErrors['accountId'], 'This account does not exist.');
    });

    test('goal starting amount is set aside on the chosen account', () async {
      await h.run(const CreateGoalAction(), _goal('Bike', 20000, start: 2500, account: sbi));
      expect(_row(await h.snapshot(), sbi).earmarked, _rs(2500));
      final err = await h.reject(const CreateGoalAction(), _goal('Car', 20000, start: 9000, account: sbi));
      expect(err.fieldErrors['initialAllocation'], 'Only ₹7,500 in SBI is free to set aside.');
      final preview = await h.dispatcher.preview(
        const CreateGoalAction(),
        _goal('Boat', 20000, start: 1000, account: hdfc),
      );
      final lines = {for (final l in preview.valueOrNull!.lines) l.label: l.value};
      expect(lines['Set aside on'], 'HDFC');
      expect(lines['Free to spend in HDFC'], '₹4,000 → ₹3,000');
    });

    test('goal contributions use the same account rules', () async {
      final goal = await h.run(const CreateGoalAction(), _goal('Trip', 50000));
      final err = await h.reject(const GoalMovementAction.contribute(), _gm(goal.id, 4500, account: hdfc));
      expect(err.fieldErrors['amount'], 'Only ₹4,000 in HDFC is free to set aside.');
      final m = await h.run(const GoalMovementAction.contribute(), _gm(goal.id, 4000, account: hdfc));
      expect(m.accountId, hdfc);
    });
  });

  group('release', () {
    test('withdrawing from a named account frees only that account; too much there is refused', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(3000, account: sbi));
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(2000, account: hdfc));
      final err = await h.reject(const EmergencyFundMovementAction.withdraw(), _ef(2500, account: hdfc));
      expect(err.fieldErrors['amount'], 'Only ₹2,000 is set aside on HDFC.');
      await h.run(const EmergencyFundMovementAction.withdraw(), _ef(1000, account: sbi));
      final s = await h.snapshot();
      expect(_row(s, sbi).earmarked, _rs(2000));
      expect(_row(s, hdfc).earmarked, _rs(2000));
      final nothing = await h.reject(const EmergencyFundMovementAction.withdraw(), _ef(1, account: cashAccountId));
      expect(nothing.fieldErrors['amount'], 'Nothing is set aside on Cash.');
    });

    test('withdrawing without an account releases from the largest holdings first', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(3000, account: sbi));
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(2000, account: hdfc));
      final preview = await h.dispatcher.preview(const EmergencyFundMovementAction.withdraw(), _ef(4000));
      final lines = {for (final l in preview.valueOrNull!.lines) l.label: l.value};
      expect(lines['Released on SBI'], '₹3,000');
      expect(lines['Released on HDFC'], '₹1,000');
      final first = await h.run(const EmergencyFundMovementAction.withdraw(), _ef(4000));
      expect(first.accountId, sbi);
      final s = await h.snapshot();
      expect(_row(s, sbi).earmarked, Money.zero);
      expect(_row(s, hdfc).earmarked, _rs(1000));
      expect(s.balance.earmarked, _rs(1000));
    });

    test('more than the bucket holds keeps the total-saved messages', () async {
      final goal = await h.run(const CreateGoalAction(), _goal('Trip', 50000, start: 1000, account: sbi));
      final err = await h.reject(const GoalMovementAction.withdraw(), _gm(goal.id, 2000));
      expect(err.fieldErrors['amount'], 'Only ₹1,000 is saved in this goal.');
      final ef = await h.reject(const EmergencyFundMovementAction.withdraw(), _ef(1));
      expect(ef.fieldErrors['amount'], 'Only ₹0 is in your emergency fund.');
    });

    test('deleting a goal releases its set-aside money on every account', () async {
      final goal = await h.run(const CreateGoalAction(), _goal('Trip', 9000, start: 1000, account: sbi));
      await h.run(const GoalMovementAction.contribute(), _gm(goal.id, 500, account: hdfc));
      await h.run(const DeleteGoalAction(), GoalIdInput(id: goal.id));
      final s = await h.snapshot();
      expect(_row(s, sbi).earmarked, Money.zero);
      expect(_row(s, sbi).available, _rs(10000));
      expect(_row(s, hdfc).earmarked, Money.zero);
      expect(s.savingsMovements, isEmpty);
    });
  });

  group('accounts with savings', () {
    test('cannot be deleted while money is set aside on them; archiving is allowed', () async {
      await h.run(const EmergencyFundMovementAction.contribute(), _ef(100, account: sbi));
      final err = await h.reject(const DeleteAccountAction(), AccountIdInput(id: sbi));
      expect(err.message, contains('Archive it instead'));
      await h.run(const ArchiveAccountAction(), ArchiveAccountInput(id: sbi, archived: true));
    });
  });
}
