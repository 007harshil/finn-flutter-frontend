import 'package:finn/features/goals/application/goal_view.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/fixtures.dart';

// fxToday = 10 Oct 2026; goals are created 1 Jan 2026 (fxStamp).
void main() {
  test('expected share runs from creation to the target date', () {
    final s = snapshotOf(goals: [savingsGoal(targetDate: d(2027, 1, 1))]);
    // 282 of 365 days.
    expect(expectedShare(s.goal('g1')!, s.today), closeTo(282 / 365, 1e-9));
    expect(expectedShare(snapshotOf(goals: [savingsGoal()]).goal('g1')!, fxToday), isNull);
  });

  test('finishWith rounds months up and refuses to guess without money', () {
    expect(finishWith(rs(10000), rs(3000), fxToday), d(2027, 2, 10));
    expect(finishWith(rs(10000), rs(0), fxToday), isNull);
    expect(finishWith(rs(0), rs(0), fxToday), fxToday);
    expect(monthsUntil(fxToday, d(2027, 1, 9)), 2);
    expect(monthsApart(d(2027, 3, 1), d(2027, 1, 20)), 2);
  });

  group('board and filters', () {
    late GoalsBoard board;

    setUp(() {
      final s = snapshotOf(
        goals: [
          savingsGoal(id: 'behind', name: 'Car', target: 100000, targetDate: d(2026, 12, 1), planned: 1000),
          savingsGoal(id: 'ok', name: 'Bike', target: 20000, targetDate: d(2027, 6, 1), planned: 5000),
          savingsGoal(id: 'free', name: 'Art', target: 50000),
          savingsGoal(id: 'done', name: 'Phone', target: 10000),
          savingsGoal(id: 'old', name: 'Old', target: 10000, status: GoalStatus.archived),
        ],
        movements: [
          goalMove(10000, d(2026, 2, 1), goalId: 'done'),
          goalMove(5000, d(2026, 2, 1), goalId: 'behind'),
          goalMove(2000, d(2026, 2, 1), goalId: 'free'),
        ],
      );
      board = buildGoalsBoard(s);
    });

    List<String> ids(GoalListFilter f) => [for (final g in filterGoals(board.all, f)) g.goal.id];

    test('tabs, counts and monthly effort', () {
      expect(board.tabCounts, {GoalTab.active: 3, GoalTab.completed: 1, GoalTab.archived: 1});
      expect(board.count(GoalPace.behind), 1);
      expect(board.count(GoalPace.onTrack), 1);
      expect(board.count(GoalPace.noPlan), 1);
      expect(board.saved, rs(7000));
      expect(board.target, rs(170000));
      expect(board.plannedMonthly, rs(6000));
      expect(board.neededMonthly.isPositive, isTrue);
    });

    test('sorts and filters', () {
      expect(ids(const GoalListFilter()), ['behind', 'free', 'ok']); // closest to done
      expect(ids(const GoalListFilter(sort: GoalSort.soonest)), ['behind', 'ok', 'free']);
      expect(ids(const GoalListFilter(sort: GoalSort.behind)), ['behind', 'free', 'ok']);
      expect(ids(const GoalListFilter(sort: GoalSort.name)), ['free', 'ok', 'behind']);
      expect(ids(const GoalListFilter(paces: {GoalPace.onTrack})), ['ok']);
      expect(ids(const GoalListFilter(tab: GoalTab.completed)), ['done']);
      expect(ids(const GoalListFilter(tab: GoalTab.archived)), ['old']);
      expect(ids(const GoalListFilter(categories: {GoalCategory.home})), isEmpty);
      expect(const GoalListFilter(paces: {GoalPace.behind}, sort: GoalSort.name).activeCount, 2);
    });
  });

  test('saved over time is a running total, oldest first', () {
    final points = savedOverTime([
      goalMove(500, d(2026, 3, 1), withdraw: true),
      goalMove(2000, d(2026, 2, 1)),
      goalMove(1000, d(2026, 4, 1)),
    ]);
    expect([for (final p in points) p.$2], [rs(2000), rs(1500), rs(2500)]);
  });
}
