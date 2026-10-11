import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/goals/application/goal_actions.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

GoalInput japan({int target = 200000, int? initial, DateTime? targetDate, String name = 'Japan trip'}) => GoalInput(
      name: name,
      category: GoalCategory.travel,
      target: Money.rupees(target),
      colorIndex: 2,
      targetDate: targetDate,
      initialAllocation: initial == null ? null : Money.rupees(initial),
    );

GoalMovementInput move(String goalId, int rupees, {DateTime? date}) =>
    GoalMovementInput(goalId: goalId, amount: Money.rupees(rupees), date: date ?? DateTime(2026, 10, 10));

void main() {
  late ActionHarness h;
  setUp(() async => h = await ActionHarness.create());

  group('goals.create', () {
    test('without a starting amount: no review, nothing earmarked', () async {
      final out = await h.dispatcher.dispatch(const CreateGoalAction(), japan(), idempotencyKey: 'k');
      final goal = (out as ActionCompleted<SavingsGoal>).value;
      expect(goal.name, 'Japan trip');
      expect((await h.snapshot()).balance.earmarked, Money.zero);
    });

    test('a starting amount is earmarked today (needs review); cash and net worth unchanged', () async {
      final asked = await h.dispatcher.dispatch(const CreateGoalAction(), japan(initial: 20000), idempotencyKey: 'k');
      expect(asked, isA<ActionNeedsConfirmation<SavingsGoal>>());
      final goal = await h.run(const CreateGoalAction(), japan(initial: 20000));
      final s = await h.snapshot();
      final m = s.savingsMovements.single;
      expect(m.bucketId, goal.id);
      expect(m.date, DateTime(2026, 10, 10));
      expect(m.note, 'Starting amount');
      expect(s.goal(goal.id)!.saved, const Money.rupees(20000));
      expect(s.balance.cash, harnessOpening);
      expect(s.balance.available, harnessOpening - const Money.rupees(20000));
      expect(s.netWorth.netWorth, harnessOpening);
    });

    test('validation', () async {
      await h.run(const CreateGoalAction(), japan());
      Future<Iterable<String>> fields(GoalInput i) async => (await h.reject(const CreateGoalAction(), i)).fieldErrors.keys;
      expect(await fields(japan(name: 'JAPAN TRIP')), ['name'], reason: 'active names are unique, case-insensitive');
      expect(await fields(japan(name: ' ')), ['name']);
      expect(await fields(japan(name: 'x' * 51)), ['name']);
      expect(await fields(japan(name: 'Car', target: 0)), ['target']);
      expect(await fields(japan(name: 'Car', targetDate: DateTime(2026, 10, 10))), ['targetDate']);
      expect(await fields(japan(name: 'Car', initial: 100001)), ['initialAllocation']);
    });
  });

  group('contributions and withdrawals', () {
    late SavingsGoal goal;
    setUp(() async => goal = await h.run(const CreateGoalAction(), japan(target: 50000)));

    test('contribute earmarks available cash; withdraw releases it', () async {
      final asked = await h.dispatcher.dispatch(const GoalMovementAction.contribute(), move(goal.id, 30000), idempotencyKey: 'k');
      final lines = {for (final l in (asked as ActionNeedsConfirmation).preview.lines) l.label: l.value};
      expect(lines['Net worth'], 'Unchanged');
      expect(lines['Saved in goal'], '₹0 → ₹30,000');

      await h.run(const GoalMovementAction.contribute(), move(goal.id, 30000));
      await h.run(const GoalMovementAction.withdraw(), move(goal.id, 5000));
      final s = await h.snapshot();
      expect(s.goal(goal.id)!.saved, const Money.rupees(25000));
      expect(s.balance.earmarkedGoals, const Money.rupees(25000));
      expect(s.balance.available, harnessOpening - const Money.rupees(25000));
      expect(s.balance.cash, harnessOpening);
      expect(s.monthSummary(s.currentMonth).transactionCount, 0, reason: 'allocations are not income or spending');
    });

    test('a contribution that completes the goal says so', () async {
      final out = await h.dispatcher.dispatch(const GoalMovementAction.contribute(), move(goal.id, 50000), idempotencyKey: 'k');
      expect((out as ActionNeedsConfirmation).preview.warnings, ['This completes your goal!']);
    });

    test('cannot set aside more than is available or withdraw more than is saved', () async {
      final tooMuch = await h.reject(const GoalMovementAction.contribute(), move(goal.id, 100001));
      expect(tooMuch.fieldErrors['amount'], startsWith('Only ₹1,00,000'));
      await h.run(const GoalMovementAction.contribute(), move(goal.id, 1000));
      final over = await h.reject(const GoalMovementAction.withdraw(), move(goal.id, 1001));
      expect(over.fieldErrors['amount'], 'Only ₹1,000 is saved in this goal.');
      expect((await h.reject(const GoalMovementAction.contribute(), move(goal.id, 0))).fieldErrors.keys, ['amount']);
      expect((await h.reject(const GoalMovementAction.contribute(), move(goal.id, 1, date: DateTime(2026, 10, 11))))
          .fieldErrors
          .keys, ['date']);
    });

    test('archived goals accept no movements; restore makes them active again', () async {
      final archived = await h.run(const ArchiveGoalAction(), GoalIdInput(id: goal.id));
      expect(archived.status, GoalStatus.archived);
      expect((await h.reject(const GoalMovementAction.contribute(), move(goal.id, 10))).message, 'This goal is archived.');
      // An archived name can be reused.
      await h.run(const CreateGoalAction(), japan());
      final restored = await h.run(const ArchiveGoalAction(), GoalIdInput(id: goal.id));
      expect(restored.status, GoalStatus.active);
      expect(restored.version, 3);
    });
  });

  group('goals.update', () {
    test('edits details without touching the saved amount; stale versions are rejected', () async {
      final goal = await h.run(const CreateGoalAction(), japan(initial: 10000));
      final updated = await h.run(const UpdateGoalAction(),
          UpdateGoalInput(id: goal.id, expectedVersion: 1, data: japan(target: 300000, initial: 99999999)));
      expect(updated.target, const Money.rupees(300000));
      expect(updated.version, 2);
      final s = await h.snapshot();
      expect(s.goal(goal.id)!.saved, const Money.rupees(10000), reason: 'initialAllocation is ignored on update');
      expect((await h.reject(const UpdateGoalAction(), UpdateGoalInput(id: goal.id, expectedVersion: 1, data: japan()))).code,
          FailureCode.staleData);
    });
  });

  group('goals.delete', () {
    test('releases everything earmarked, including future-dated movements', () async {
      final goal = await h.run(const CreateGoalAction(), japan(initial: 10000));
      await h.repos.savingsMovements.save(SavingsMovement(
        id: 'sv_future',
        bucketType: SavingsBucketType.goal,
        bucketId: goal.id,
        kind: SavingsMovementKind.contribution,
        amount: const Money.rupees(500),
        date: DateTime(2026, 11, 1),
        createdAt: harnessNow,
      ));
      final keep = await h.run(const CreateGoalAction(), japan(name: 'Laptop', initial: 2000));

      final asked = await h.dispatcher.dispatch(const DeleteGoalAction(), GoalIdInput(id: goal.id), idempotencyKey: 'd');
      final lines = {for (final l in (asked as ActionNeedsConfirmation).preview.lines) l.label: l.value};
      expect(lines['Returned to available cash'], '₹10,000');

      await h.run(const DeleteGoalAction(), GoalIdInput(id: goal.id));
      final s = await h.snapshot();
      expect(s.goals.map((g) => g.id), [keep.id]);
      expect(s.savingsMovements.every((m) => m.bucketId == keep.id), isTrue);
      expect(s.balance.available, harnessOpening - const Money.rupees(2000));
    });

    test('missing goals', () async {
      expect((await h.reject(const DeleteGoalAction(), const GoalIdInput(id: 'nope'))).code, FailureCode.notFound);
      expect((await h.reject(const GoalMovementAction.withdraw(), move('nope', 1))).code, FailureCode.notFound);
    });
  });
}
