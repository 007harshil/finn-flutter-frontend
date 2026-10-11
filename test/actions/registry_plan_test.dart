import 'package:finn/actions/action.dart';
import 'package:finn/actions/action_plan.dart';
import 'package:finn/actions/action_registry.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/mock/seed_data.dart';
import 'package:finn/features/goals/application/goal_actions.dart';
import 'package:finn/features/goals/domain/goal.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'action_harness.dart';

void main() {
  late ActionHarness h;
  late ActionRegistry registry;

  setUp(() async {
    h = await ActionHarness.create();
    registry = ActionRegistry(allActions);
  });

  group('ActionRegistry', () {
    test('ids are unique and every registered action describes itself', () {
      final ids = registry.descriptors.map((d) => d.id).toList();
      expect(ids.toSet().length, ids.length);
      expect(ids, containsAll(['transactions.create', 'loans.recordPayment', 'goals.contribute', 'pending.settle']));
      final described = registry.describe();
      final create = described.firstWhere((d) => d['id'] == 'transactions.create');
      expect(create['risk'], 'low');
      expect(create['movesMoney'], isTrue);
      expect((create['fields'] as List).map((f) => (f as Map)['name']), containsAll(['type', 'amount', 'categoryId', 'date']));
      expect(() => ActionRegistry([const CreateTransactionAction(), const CreateTransactionAction()]), throwsStateError);
    });

    test('decode reports unknown operations and malformed input', () {
      expect(registry.decode('nope.create', const {}).failureOrNull!.code, FailureCode.notFound);
      final bad = registry.decode('transactions.create', {'type': 'expense', 'amount': '12.345', 'categoryId': 'c', 'date': '2026-10-01'});
      expect(bad.failureOrNull!.code, FailureCode.validation);
      expect(bad.failureOrNull!.fieldErrors.keys, ['amount']);
      final ok = registry.decode('transactions.create',
          {'type': 'expense', 'amount': '1,250.50', 'categoryId': SeedCategoryIds.food, 'date': '2026-10-01'});
      final input = ok.valueOrNull! as TransactionInput;
      expect(input.amount, Money.fromPaise(125050));
      expect(input.date, DateTime(2026, 10, 1));
    });

    test('dispatchJson uses the agent channel: confirmation first, then execution', () async {
      final json = {'type': 'expense', 'amount': 300, 'categoryId': SeedCategoryIds.food, 'date': '2026-10-09'};
      final asked = await registry.dispatchJson(h.dispatcher, 'transactions.create', json, idempotencyKey: 'a1');
      expect(asked, isA<ActionNeedsConfirmation<Object?>>());
      final fp = (asked as ActionNeedsConfirmation<Object?>).preview.fingerprint;
      final done = await registry.dispatchJson(h.dispatcher, 'transactions.create', json,
          idempotencyKey: 'a1', confirmation: ActionConfirmation(fp, confirmedBy: 'agent-user'));
      expect(done, isA<ActionCompleted<Object?>>());
      expect((await h.snapshot()).transactions.single.amount, const Money.rupees(300));
      expect(h.dispatcher.audit.entries.single.channel, ActionChannel.agent);

      final unknown = await registry.dispatchJson(h.dispatcher, 'nope', const {}, idempotencyKey: 'a2');
      expect((unknown as ActionRejected<Object?>).failure.code, FailureCode.notFound);
    });
  });

  group('In / Out helpers', () {
    test('money accepts rupees as numbers or strings with up to two decimals', () {
      expect(In.money({'a': 1250.5}, 'a'), Money.fromPaise(125050));
      expect(In.money({'a': '₹ 1,25,000'}, 'a'), const Money.rupees(125000));
      expect(() => In.money({'a': -5}, 'a'), throwsA(isA<AppFailure>()));
      expect(() => In.money({'a': '1.234'}, 'a'), throwsA(isA<AppFailure>()));
      expect(In.moneyOpt(const {}, 'a'), isNull);
      expect(Out.money(Money.fromPaise(125050)), '1250.50');
    });

    test('dates must be real yyyy-MM-dd dates', () {
      expect(In.date({'d': '2028-02-29'}, 'd'), DateTime(2028, 2, 29));
      expect(() => In.date({'d': '2026-02-30'}, 'd'), throwsA(isA<AppFailure>()));
      expect(() => In.date({'d': '10/10/2026'}, 'd'), throwsA(isA<AppFailure>()));
      expect(Out.date(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('strings, integers, booleans and enums', () {
      expect(In.str({'s': '  Rent '}, 's'), 'Rent');
      expect(() => In.str({'s': '  '}, 's'), throwsA(isA<AppFailure>()));
      expect(In.strOpt({'s': ' '}, 's'), isNull);
      expect(In.integer({'i': 3.0}, 'i'), 3);
      expect(() => In.integer({'i': 3.5}, 'i'), throwsA(isA<AppFailure>()));
      expect(In.boolean(const {}, 'b', fallback: true), isTrue);
      expect(() => In.boolean(const {}, 'b'), throwsA(isA<AppFailure>()));
      expect(In.enumeration({'e': 'goal'}, 'e', SavingsBucketType.values), SavingsBucketType.goal);
      final failure = (() {
        try {
          In.enumeration({'e': 'x'}, 'e', SavingsBucketType.values);
        } on AppFailure catch (f) {
          return f;
        }
        return null;
      })();
      expect(failure!.message, contains('goal, emergencyFund'));
    });
  });

  group('PlanExecutor', () {
    late PlanExecutor executor;
    late SavingsGoal goal;

    setUp(() async {
      executor = PlanExecutor(registry: registry, dispatcher: h.dispatcher);
      goal = await h.run(
        const CreateGoalAction(),
        const GoalInput(name: 'Japan trip', category: GoalCategory.travel, target: Money.rupees(200000), colorIndex: 1),
      );
    });

    ActionPlan plan(String id, {List<PlannedStep>? steps}) => ActionPlan(
          planId: id,
          steps: steps ??
              [
                const PlannedStep(stepId: 'pay', actionId: 'transactions.create', input: {
                  'type': 'expense',
                  'amount': 500,
                  'categoryId': SeedCategoryIds.food,
                  'date': '2026-10-09',
                  'counterparty': 'Rahul',
                }),
                PlannedStep(
                  stepId: 'save',
                  actionId: 'goals.contribute',
                  input: {'goalId': goal.id, 'amount': 2000, 'date': '2026-10-10'},
                  dependsOn: const ['pay'],
                ),
              ],
        );

    Future<Set<String>> approveAll(ActionPlan p) async =>
        {for (final r in await executor.prepare(p)) if (r.preview != null) r.preview!.fingerprint};

    test('prepare validates every step without executing anything', () async {
      final reports = await executor.prepare(plan('p', steps: [
        ...plan('p').steps,
        const PlannedStep(stepId: 'bad', actionId: 'transactions.create', input: {'type': 'expense'}),
        const PlannedStep(stepId: 'unknown', actionId: 'nope.create', input: {}),
      ]));
      expect(reports.map((r) => r.status), [StepStatus.ready, StepStatus.ready, StepStatus.invalid, StepStatus.invalid]);
      expect(reports[1].preview!.summary, 'Set aside ₹2,000 for Japan trip');
      final s = await h.snapshot();
      expect(s.transactions, isEmpty);
      expect(s.savingsMovements, isEmpty);
    });

    test('approved steps run in order; each step commits independently', () async {
      final p = plan('p1');
      final reports = await executor.execute(p, approvedFingerprints: await approveAll(p));
      expect(reports.map((r) => r.status), [StepStatus.succeeded, StepStatus.succeeded]);
      final s = await h.snapshot();
      expect(s.transactions.single.counterparty, 'Rahul');
      expect(s.goal(goal.id)!.saved, const Money.rupees(2000));
      expect(h.dispatcher.audit.entries.first.confirmedBy, 'plan:p1');
    });

    test('re-running the same plan replays instead of duplicating', () async {
      final p = plan('p1');
      final approved = await approveAll(p);
      await executor.execute(p, approvedFingerprints: approved);
      final again = await executor.execute(p, approvedFingerprints: approved);
      expect(again.map((r) => r.status), [StepStatus.succeeded, StepStatus.succeeded]);
      final s = await h.snapshot();
      expect(s.transactions.length, 1);
      expect(s.savingsMovements.length, 1);
    });

    test('unapproved steps do not run and their dependants are skipped', () async {
      final p = plan('p2');
      final prepared = await executor.prepare(p);
      final reports = await executor.execute(p, approvedFingerprints: {prepared[1].preview!.fingerprint});
      expect(reports.map((r) => r.status), [StepStatus.notApproved, StepStatus.skipped]);
      expect((await h.snapshot()).transactions, isEmpty);
    });

    test('a step whose record changed after approval is stale and halts the plan', () async {
      final p = plan('p3', steps: [
        PlannedStep(stepId: 'save', actionId: 'goals.contribute', input: {'goalId': goal.id, 'amount': 2000, 'date': '2026-10-10'}),
        const PlannedStep(stepId: 'pay', actionId: 'transactions.create', input: {
          'type': 'expense',
          'amount': 500,
          'categoryId': SeedCategoryIds.food,
          'date': '2026-10-09',
        }),
      ]);
      final approved = await approveAll(p);
      // Meanwhile, money is added to the goal from another screen.
      await h.run(const GoalMovementAction.contribute(),
          GoalMovementInput(goalId: goal.id, amount: const Money.rupees(100), date: DateTime(2026, 10, 10)));

      final reports = await executor.execute(p, approvedFingerprints: approved);
      expect(reports.map((r) => r.status), [StepStatus.notApproved, StepStatus.skipped]);
      expect(reports.first.failure!.code, FailureCode.staleData);
      expect((await h.snapshot()).goal(goal.id)!.saved, const Money.rupees(100));
    });

    test('a failing step halts the rest unless stopOnFailure is false', () async {
      PlannedStep tooMuch(String id) => PlannedStep(
          stepId: id, actionId: 'goals.contribute', input: {'goalId': goal.id, 'amount': 99999999, 'date': '2026-10-10'});
      const pay = PlannedStep(stepId: 'pay', actionId: 'transactions.create', input: {
        'type': 'expense',
        'amount': 500,
        'categoryId': SeedCategoryIds.food,
        'date': '2026-10-09',
      });
      final payFp = (await executor.prepare(ActionPlan(planId: 'x', steps: const [pay]))).single.preview!.fingerprint;
      final contributeFp = previewFingerprintOf(
          'goals.contribute', GoalMovementInput(goalId: goal.id, amount: const Money.rupees(99999999), date: DateTime(2026, 10, 10)),
          basis: {'v': 1, 'saved': 0});

      final halted = await executor.execute(ActionPlan(planId: 'h', steps: [tooMuch('big'), pay]),
          approvedFingerprints: {payFp, contributeFp});
      expect(halted.map((r) => r.status), [StepStatus.failed, StepStatus.skipped]);
      expect(halted.first.failure!.code, FailureCode.validation);

      final continued = await executor.execute(ActionPlan(planId: 'c', steps: [tooMuch('big'), pay]),
          approvedFingerprints: {payFp, contributeFp}, stopOnFailure: false);
      expect(continued.map((r) => r.status), [StepStatus.failed, StepStatus.succeeded]);
    });
  });
}
