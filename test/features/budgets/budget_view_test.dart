import 'package:finn/core/money/money.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/budgets/application/budget_view.dart';
import 'package:finn/features/budgets/domain/budget.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fixtures.dart';

// fxToday = 10 Oct 2026; the October period is 1–31 Oct (31 days), so 10
// days have passed and 22 are left (counting today).
void main() {
  BudgetPace paceFor(int spent, {int limit = 10000, int warningBps = 8000, BudgetStatus status = BudgetStatus.active}) {
    final b = budget(id: 'b', limit: limit, warningBps: warningBps, status: status);
    final s = snapshotOf(budgets: [b], transactions: [if (spent > 0) tx(spent, d(2026, 10, 5))]);
    return BudgetPace.of(s.budgetUsage('b')!, s.today);
  }

  group('BudgetPace', () {
    test('steady spending is on track, with a safe daily amount and a projection', () {
      final p = paceFor(3000);
      expect(p.state, BudgetState.onTrack);
      expect(p.daysLeft, 22);
      expect(p.elapsedDays, 10);
      expect(p.projected, rs(9300)); // 3,000 × 31 / 10
      expect(p.safePerDay, rs(7000).scale(1, 22));
      expect(p.runsOutOn, isNull);
    });

    test('spending faster than the month is at risk and says when the limit runs out', () {
      final p = paceFor(5000);
      expect(p.state, BudgetState.risk);
      expect(p.projected, rs(15500));
      // 10,000 / (5,000 per 10 days) = day 20.
      expect(p.runsOutOn, d(2026, 10, 20));
    });

    test('reaching the warning threshold is at risk even on pace', () {
      final p = paceFor(2500, warningBps: 2000);
      expect(p.projected! < rs(10000), isTrue);
      expect(p.state, BudgetState.risk);
      expect(p.runsOutOn, isNull);
    });

    test('over the limit and paused', () {
      expect(paceFor(12000).state, BudgetState.over);
      expect(paceFor(12000).safePerDay, isNull);
      expect(paceFor(3000, status: BudgetStatus.paused).state, BudgetState.paused);
    });
  });

  group('filterBudgets', () {
    late List<BudgetPace> paces;
    final names = <String, String>{'over': 'Zeta', 'risk': 'Alpha', 'ok': 'Mid', 'paused': 'Beta'};

    setUp(() {
      final budgets = [
        budget(id: 'ok', category: SeedCategoryIds.food, limit: 10000),
        budget(id: 'over', category: SeedCategoryIds.groceries, limit: 1000),
        budget(id: 'paused', category: SeedCategoryIds.shopping, status: BudgetStatus.paused),
        budget(id: 'risk', category: SeedCategoryIds.transport, limit: 10000),
      ];
      final s = snapshotOf(budgets: budgets, transactions: [
        tx(1000, d(2026, 10, 2), category: SeedCategoryIds.food),
        tx(2000, d(2026, 10, 2), category: SeedCategoryIds.groceries),
        tx(6000, d(2026, 10, 2), category: SeedCategoryIds.transport),
      ]);
      paces = buildBudgetsPulse(s).paces;
    });

    List<String> ids(BudgetListFilter f) =>
        [for (final p in filterBudgets(paces, f, (p) => names[p.usage.budget.id]!)) p.usage.budget.id];

    test('most urgent first: over, at risk, on track, paused', () {
      expect(ids(const BudgetListFilter()), ['over', 'risk', 'ok', 'paused']);
    });

    test('status and sort options', () {
      expect(ids(const BudgetListFilter(state: BudgetState.risk)), ['risk']);
      expect(ids(const BudgetListFilter(sort: BudgetSort.name)), ['risk', 'paused', 'ok', 'over']);
      expect(ids(const BudgetListFilter(sort: BudgetSort.left)).take(2), ['paused', 'ok']);
      expect(const BudgetListFilter(sort: BudgetSort.name).optionCount, 1);
    });
  });

  test('pulse totals only active monthly budgets and counts each status', () {
    final s = snapshotOf(
      budgets: [budget(id: 'a', limit: 10000), budget(id: 'p', category: SeedCategoryIds.shopping, status: BudgetStatus.paused)],
      transactions: [tx(4000, d(2026, 10, 3)), tx(500, d(2026, 10, 3), category: SeedCategoryIds.shopping)],
    );
    final o = buildBudgetsPulse(s);
    expect(o.limit, rs(10000));
    expect(o.spent, rs(4000));
    expect(o.daysLeft, 22);
    expect(o.projected, rs(12400));
    expect(o.count(BudgetState.risk), 1);
    expect(o.count(BudgetState.paused), 1);
  });

  test('burn buckets spending per day and payees by total', () {
    final s = snapshotOf(budgets: [budget(id: 'b')], transactions: [
      tx(300, d(2026, 10, 1), counterparty: 'Swiggy'),
      tx(200, d(2026, 10, 1), counterparty: 'Zomato'),
      tx(700, d(2026, 10, 4), counterparty: 'Swiggy'),
    ]);
    final burn = buildBudgetBurn(s, s.budgetUsage('b')!);
    expect(burn.daily.length, 31);
    expect(burn.daily[0], 50000);
    expect(burn.daily[3], 70000);
    expect(burn.cumulative[3], 120000);
    expect(burn.todayIndex, 9);
    expect(burn.transactions.first.amount, rs(700));
    final payees = topPayees(burn.transactions);
    expect(payees.first.$1, 'Swiggy');
    expect(payees.first.$2, const Money.rupees(1000));
    expect(payees.first.$3, 2);
  });
}
