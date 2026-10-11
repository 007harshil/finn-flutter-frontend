import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/goals/application/goal_actions.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/settings/application/profile_actions.dart';
import 'package:finn/features/settings/domain/financial_profile.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

UpdateProfileInput profile({String name = 'Test', int opening = 100000, DateTime? since, int? income}) => UpdateProfileInput(
      displayName: name,
      openingBalance: Money.rupees(opening),
      openingDate: since ?? DateTime(2026, 1, 1),
      monthlyIncomeEstimate: income == null ? null : Money.rupees(income),
    );

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  test('renaming does not touch balances and needs no review', () async {
    final out = await h.dispatcher.dispatch(const UpdateProfileAction(), profile(name: '  Asha ', income: 90000), idempotencyKey: 'k');
    final p = (out as ActionCompleted<FinancialProfile>).value;
    expect(p.displayName, 'Asha');
    expect(p.monthlyIncomeEstimate, const Money.rupees(90000));
    expect(out.preview.summary, 'Profile updated');
    expect((await h.snapshot()).balance.cash, harnessOpening);
  });

  test('changing the opening balance previews the new cash and needs a review', () async {
    await h.run(
      const CreateTransactionAction(),
      TransactionInput(type: TransactionType.expense, amount: const Money.rupees(5000), categoryId: SeedCategoryIds.rent, date: DateTime(2026, 3, 1)),
    );
    final out = await h.dispatcher.dispatch(const UpdateProfileAction(), profile(opening: 120000), idempotencyKey: 'k');
    final preview = (out as ActionNeedsConfirmation<FinancialProfile>).preview;
    final cashLine = preview.lines.firstWhere((l) => l.label == 'Cash balance');
    expect(cashLine.value, '₹95,000 → ₹1,15,000');
    expect(preview.warnings.first, contains('+₹20,000 change to cash'));

    await h.run(const UpdateProfileAction(), profile(opening: 120000));
    expect((await h.snapshot()).balance.cash, const Money.rupees(115000));
  });

  test('moving the start date later drops earlier transactions from cash', () async {
    await h.run(
      const CreateTransactionAction(),
      TransactionInput(type: TransactionType.expense, amount: const Money.rupees(5000), categoryId: SeedCategoryIds.rent, date: DateTime(2026, 3, 1)),
    );
    expect(UpdateProfileAction.changesBalances(profile(since: DateTime(2026, 4, 1)), (await h.snapshot()).profile), isTrue);
    await h.run(const UpdateProfileAction(), profile(since: DateTime(2026, 4, 1)));
    expect((await h.snapshot()).balance.cash, harnessOpening);
  });

  test('warns when cash would fall below earmarked savings', () async {
    await h.run(
      const CreateGoalAction(),
      const GoalInput(
          name: 'House', category: GoalCategory.home, target: Money.rupees(500000), colorIndex: 1, initialAllocation: Money.rupees(60000)),
    );
    final preview = (await h.dispatcher.preview(const UpdateProfileAction(), profile(opening: 50000))).valueOrNull!;
    expect(preview.warnings.last, startsWith('Cash would be less than the ₹60,000 earmarked'));
  });

  test('a first profile (onboarding) needs no review', () async {
    final fresh = await ActionHarness.create(withProfile: false);
    expect(UpdateProfileAction.changesBalances(profile(), null), isTrue);
    final out = await fresh.dispatcher.dispatch(const UpdateProfileAction(), profile(opening: 25000), idempotencyKey: 'k');
    expect(out, isA<ActionCompleted<FinancialProfile>>());
    expect((await fresh.snapshot()).balance.cash, const Money.rupees(25000));
  });

  test('validation', () async {
    Future<Iterable<String>> fields(UpdateProfileInput i) async => (await h.reject(const UpdateProfileAction(), i)).fieldErrors.keys;
    expect(await fields(profile(name: ' ')), ['displayName']);
    expect(await fields(profile(name: 'x' * 41)), ['displayName']);
    expect(await fields(profile(opening: -1)), ['openingBalance']);
    expect(await fields(profile(since: DateTime(2026, 10, 11))), ['openingDate']);
    expect(await fields(profile(income: -1)), ['monthlyIncomeEstimate']);
    await h.run(const UpdateProfileAction(), profile(opening: 0, since: DateTime(2026, 10, 10)));
  });
}
