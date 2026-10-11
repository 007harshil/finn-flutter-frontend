import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/core/ids/id_generator.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/persistence/persistence_driver.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/domain/finance_repositories.dart';
import 'package:finn/features/settings/domain/financial_profile.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed "today" for action tests: Saturday 10 Oct 2026, 09:00.
final harnessNow = DateTime(2026, 10, 10, 9);

/// Opening balance used by [ActionHarness] (₹1,00,000 on 1 Jan 2026).
const harnessOpening = Money.rupees(100000);

/// In-memory action environment without any UI dependencies.
///
/// Starts from the `empty` scenario (system + standard categories only) plus
/// a profile with [harnessOpening], so every amount in a test is explicit.
class ActionHarness {
  ActionHarness._(this.store, this.clock, this.ids, this.repos, this.env, this.dispatcher);

  final LocalDataStore store;
  final FixedClock clock;
  final SequentialIdGenerator ids;
  final FinanceRepositories repos;
  final ActionEnvironment env;
  final OperationDispatcher dispatcher;
  int _key = 0;

  static Future<ActionHarness> create({DataScenario scenario = DataScenario.empty, bool withProfile = true}) async {
    final clock = FixedClock(harnessNow);
    final store = LocalDataStore(driver: MemoryDriver());
    await store.open(scenario: scenario, today: clock.today(), forceSeed: true);
    if (withProfile && scenario == DataScenario.empty) {
      await store.profile.set(FinancialProfile(
        displayName: 'Test',
        openingBalance: harnessOpening,
        openingDate: DateTime(2026, 1, 1),
      ));
    }
    final repos = FinanceRepositories(
      transactions: store.transactions, categories: store.categories, budgets: store.budgets,
      goals: store.goals, savingsMovements: store.savingsMovements, loans: store.loans,
      loanPayments: store.loanPayments, subscriptions: store.subscriptions, pending: store.pending,
      settlements: store.settlements, assets: store.assets, profile: store.profile,
      emergencyPlan: store.emergencyPlan, alertInbox: store.alertInbox,
    );
    final ids = SequentialIdGenerator();
    final env = ActionEnvironment(
      repos: repos,
      clock: clock,
      ids: ids,
      loadSnapshot: () => repos.loadSnapshot(clock, monthStartDay: 1),
    );
    return ActionHarness._(store, clock, ids, repos, env, OperationDispatcher(environment: env));
  }

  Future<FinanceSnapshot> snapshot() => repos.loadSnapshot(clock, monthStartDay: 1);

  String nextKey() => 'test_${_key++}';

  /// Dispatches from the UI channel, confirming the preview when asked.
  /// Fails the test unless the action completes.
  Future<O> run<I extends ActionInput, O>(FinancialAction<I, O> action, I input, {String? key}) async {
    final k = key ?? nextKey();
    var out = await dispatcher.dispatch(action, input, idempotencyKey: k);
    if (out is ActionNeedsConfirmation<O>) {
      out = await dispatcher.dispatch(action, input,
          idempotencyKey: k, confirmation: ActionConfirmation(out.preview.fingerprint));
    }
    if (out is ActionRejected<O>) fail('Expected ${action.descriptor.id} to complete, got ${out.failure}');
    if (out is! ActionCompleted<O>) fail('Expected ${action.descriptor.id} to complete, got $out');
    return out.value;
  }

  /// Dispatches (confirming when asked) and returns the rejection failure.
  Future<AppFailure> reject<I extends ActionInput, O>(FinancialAction<I, O> action, I input) async {
    final k = nextKey();
    var out = await dispatcher.dispatch(action, input, idempotencyKey: k);
    if (out is ActionNeedsConfirmation<O>) {
      out = await dispatcher.dispatch(action, input,
          idempotencyKey: k, confirmation: ActionConfirmation(out.preview.fingerprint));
    }
    if (out is! ActionRejected<O>) fail('Expected ${action.descriptor.id} to be rejected, got $out');
    return out.failure;
  }
}
