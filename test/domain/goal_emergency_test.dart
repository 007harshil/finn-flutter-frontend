import 'package:finn/core/money/money.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund_calculator.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/goals/domain/goal_calculator.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

const goals = GoalCalculator();
const ef = EmergencyFundCalculator();
final today = DateTime(2026, 10, 10);
final stamp = DateTime(2026, 1, 1);
DateTime d(int y, int m, int day) => DateTime(y, m, day);
Money rs(int v) => Money.rupees(v);

SavingsGoal goal({
  String id = 'g1',
  int target = 100000,
  DateTime? targetDate,
  int? planned,
}) =>
    SavingsGoal(
      id: id,
      name: 'Japan trip',
      category: GoalCategory.travel,
      target: rs(target),
      targetDate: targetDate,
      plannedMonthlyContribution: planned == null ? null : rs(planned),
      colorIndex: 1,
      createdAt: stamp,
      updatedAt: stamp,
    );

int _n = 0;
SavingsMovement mv(int rupees, DateTime date, {
  bool withdraw = false,
  String bucket = 'g1',
  SavingsBucketType type = SavingsBucketType.goal,
}) =>
    SavingsMovement(
      id: 'sv_${_n++}',
      bucketType: type,
      bucketId: bucket,
      kind: withdraw ? SavingsMovementKind.withdrawal : SavingsMovementKind.contribution,
      amount: rs(rupees),
      date: date,
      createdAt: stamp,
    );

SavingsMovement efMv(int rupees, DateTime date, {bool withdraw = false}) =>
    mv(rupees, date, withdraw: withdraw, bucket: SavingsMovement.emergencyFundBucketId, type: SavingsBucketType.emergencyFund);

void main() {
  group('GoalCalculator', () {
    final history = [
      mv(30000, d(2026, 8, 5)),
      mv(10000, d(2026, 9, 5)),
      mv(5000, d(2026, 9, 20), withdraw: true),
      mv(50000, d(2026, 10, 20)), // future-dated: ignored
      mv(99999, d(2026, 9, 1), bucket: 'g2'), // another goal
      mv(7777, d(2026, 9, 1), bucket: 'g1', type: SavingsBucketType.emergencyFund), // other bucket type
    ];

    test('saved and progress are derived from this goal\'s movements up to today', () {
      final g = goals.progress(goal(), history, today);
      expect(g.saved, rs(35000));
      expect(g.remaining, rs(65000));
      expect(g.progressBps, 3500);
      expect(g.progress, 0.35);
      expect(g.isAchieved, isFalse);
      expect(g.movements.length, 3);
      expect(g.movements.first.date, d(2026, 9, 20), reason: 'newest first');
    });

    test('average uses the last three full months (Jul–Sep), half-up', () {
      final g = goals.progress(goal(), [...history, mv(1000, d(2026, 10, 2)), mv(2000, d(2026, 6, 30))], today);
      // Window total 30,000 + 10,000 − 5,000 = 35,000 → 11,666.67 per month.
      expect(g.averageMonthlyContribution, Money.fromPaise(1166667));
    });

    test('estimate from the recent average when there is no plan', () {
      final g = goals.progress(goal(), history, today);
      // 65,000 / 11,666.67 = 5.57 → 6 months.
      expect(g.estimatedCompletion, d(2027, 4, 10));
      expect(g.onTrack, isNull, reason: 'no target date');
      expect(g.requiredMonthly, isNull);
    });

    test('the plan is preferred over the average', () {
      final g = goals.progress(goal(planned: 10000), history, today);
      // 65,000 / 10,000 = 6.5 → 7 months.
      expect(g.estimatedCompletion, d(2027, 5, 10));
    });

    test('requiredMonthly rounds up and counts a partial month as one', () {
      final exact = goals.progress(goal(targetDate: d(2027, 4, 10)), history, today);
      expect(exact.requiredMonthly, Money.fromPaise(1083334)); // 65,000 / 6
      final partial = goals.progress(goal(targetDate: d(2027, 4, 15)), history, today);
      expect(partial.requiredMonthly, Money.fromPaise(928572)); // 65,000 / 7
      final soon = goals.progress(goal(targetDate: d(2026, 10, 5)), history, today);
      expect(soon.requiredMonthly, rs(65000), reason: 'target date passed: everything now');
      final sameMonth = goals.progress(goal(targetDate: d(2026, 10, 25)), history, today);
      expect(sameMonth.requiredMonthly, rs(65000));
    });

    test('onTrack compares the estimate with the target date', () {
      final behind = goals.progress(goal(targetDate: d(2027, 4, 10), planned: 10000), history, today);
      expect(behind.estimatedCompletion, d(2027, 5, 10));
      expect(behind.onTrack, isFalse);
      final ahead = goals.progress(goal(targetDate: d(2027, 6, 1), planned: 10000), history, today);
      expect(ahead.onTrack, isTrue);
      final onTheDay = goals.progress(goal(targetDate: d(2027, 5, 10), planned: 10000), history, today);
      expect(onTheDay.onTrack, isTrue);
    });

    test('achieved goals', () {
      final g = goals.progress(goal(targetDate: d(2027, 1, 1)), [mv(100000, d(2026, 7, 1)), mv(20000, d(2026, 9, 9))], today);
      expect(g.saved, rs(120000));
      expect(g.isAchieved, isTrue);
      expect(g.progressBps, 10000);
      expect(g.remaining, Money.zero);
      expect(g.onTrack, isTrue);
      expect(g.requiredMonthly, isNull);
      expect(g.estimatedCompletion, d(2026, 9, 9));
    });

    test('no honest estimate without history, with a negative trend, or with a zero target', () {
      final onlyThisMonth = goals.progress(goal(targetDate: d(2027, 6, 1)), [mv(5000, d(2026, 10, 2))], today);
      expect(onlyThisMonth.averageMonthlyContribution, isNull);
      expect(onlyThisMonth.estimatedCompletion, isNull);
      expect(onlyThisMonth.onTrack, isNull);
      expect(onlyThisMonth.requiredMonthly, isNotNull);

      final shrinking = goals.progress(goal(), [mv(50000, d(2026, 6, 1)), mv(30000, d(2026, 8, 1), withdraw: true)], today);
      expect(shrinking.averageMonthlyContribution, rs(-10000));
      expect(shrinking.estimatedCompletion, isNull);

      final idle = goals.progress(goal(), [mv(50000, d(2026, 5, 1))], today);
      expect(idle.averageMonthlyContribution, Money.zero);
      expect(idle.estimatedCompletion, isNull);

      final empty = goals.progress(goal(), const [], today);
      expect(empty.saved, Money.zero);
      expect(empty.estimatedCompletion, isNull);
      expect(goals.progress(goal(target: 0), const [], today).isAchieved, isFalse);
    });
  });

  group('EmergencyFundCalculator', () {
    const plan = EmergencyFundPlan(
      essentialMonthlyExpenses: Money.rupees(40000),
      targetMonths: 6,
      updatedAt: _planStamp,
    );

    EmergencyFundStatus status(List<SavingsMovement> movements, {EmergencyFundPlan? p = plan}) => ef.status(
          plan: p,
          movements: movements,
          transactions: const [],
          categories: const {},
          today: today,
        );

    test('coverage in tenths of a month, truncated', () {
      expect(plan.target, rs(240000));
      final s = status([efMv(100000, d(2026, 7, 1))]);
      expect(s.saved, rs(100000));
      expect(s.coverageTenths, 25);
      expect(s.coverageMonths, 2.5);
      expect(s.progressBps, 4167);
      expect(s.remaining, rs(140000));
      expect(status([efMv(39999, d(2026, 7, 1))]).coverageTenths, 9);
    });

    test('levels', () {
      expect(status([efMv(79999, d(2026, 7, 1))]).level, EmergencyFundLevel.critical); // 1.9 months
      expect(status([efMv(80000, d(2026, 7, 1))]).level, EmergencyFundLevel.building); // 2.0 months
      expect(status([efMv(239999, d(2026, 7, 1))]).level, EmergencyFundLevel.building);
      expect(status([efMv(240000, d(2026, 7, 1))]).level, EmergencyFundLevel.funded);
      expect(status([efMv(300000, d(2026, 7, 1))]).level, EmergencyFundLevel.funded);
      expect(status(const []).level, EmergencyFundLevel.critical);
      final none = status([efMv(1000, d(2026, 7, 1))], p: null);
      expect(none.level, EmergencyFundLevel.notConfigured);
      expect(none.coverageTenths, isNull);
      expect(none.target, Money.zero);
      final zero = status(const [], p: plan.copyWith(essentialMonthlyExpenses: Money.zero));
      expect(zero.level, EmergencyFundLevel.notConfigured);
    });

    test('target override replaces the computed target', () {
      final p = plan.copyWith(targetOverride: () => rs(100000));
      expect(p.target, rs(100000));
      expect(status([efMv(100000, d(2026, 7, 1))], p: p).level, EmergencyFundLevel.funded);
      final unknownEssentials = EmergencyFundPlan(
          essentialMonthlyExpenses: Money.zero, targetMonths: 6, targetOverride: rs(50000), updatedAt: _planStamp);
      final s = status([efMv(10000, d(2026, 7, 1))], p: unknownEssentials);
      expect(s.coverageTenths, isNull);
      expect(s.level, EmergencyFundLevel.building);
    });

    test('only emergency-fund movements up to today; withdrawals subtract', () {
      final s = status([
        efMv(100000, d(2026, 7, 1)),
        efMv(20000, d(2026, 9, 1), withdraw: true),
        efMv(50000, d(2026, 10, 11)), // future
        mv(70000, d(2026, 8, 1)), // a goal
      ]);
      expect(s.saved, rs(80000));
      expect(s.movements.length, 2);
    });

    test('suggestion averages essential categories + EMIs over the last 3 full months', () {
      TransactionCategory cat(String id, {bool essential = false, TransactionType type = TransactionType.expense}) =>
          TransactionCategory(id: id, name: id, type: type, iconKey: 'x', colorIndex: 0, isEssential: essential);
      final cats = {
        for (final c in [
          cat('rent', essential: true),
          cat('groceries', essential: true),
          cat('food'),
          cat(SystemCategories.loanEmi),
          cat('salary', type: TransactionType.income),
        ])
          c.id: c,
      };
      Transaction t(String c, int rupees, DateTime date, {TransactionType type = TransactionType.expense}) => Transaction(
          id: 'tx_${_n++}', type: type, amount: rs(rupees), categoryId: c, date: date, createdAt: stamp, updatedAt: stamp);
      final txs = [
        t('rent', 28000, d(2026, 7, 3)),
        t('rent', 28000, d(2026, 8, 3)),
        t('rent', 28000, d(2026, 9, 3)),
        t('groceries', 6000, d(2026, 8, 20)),
        t(SystemCategories.loanEmi, 12602, d(2026, 9, 5)),
        t('food', 5000, d(2026, 8, 1)), // not essential
        t('salary', 125000, d(2026, 8, 1), type: TransactionType.income),
        t('rent', 28000, d(2026, 10, 3)), // current month
        t('rent', 28000, d(2026, 6, 30)), // before the window
      ];
      // (84,000 + 6,000 + 12,602) / 3 = 34,200.67 → ₹34,201.
      expect(ef.suggestEssentialMonthly(txs, cats, today), rs(34201));
      expect(ef.suggestEssentialMonthly(const [], cats, today), isNull);
      expect(ef.suggestEssentialMonthly([t('food', 100, d(2026, 8, 1))], cats, today), isNull);
      final s = ef.status(plan: null, movements: const [], transactions: txs, categories: cats, today: today);
      expect(s.suggestedEssentialMonthly, rs(34201));
      expect(s.plan, isNull, reason: 'a suggestion is never applied silently');
    });
  });
}

const _planStamp = _Stamp();

class _Stamp implements DateTime {
  const _Stamp();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
