import 'package:finn/core/persistence/persistence_driver.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/domain/finance_repositories.dart';
import 'package:finn/features/alerts/domain/alert_engine.dart';
import 'package:finn/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('demo scenario produces a coherent, positive financial picture', () async {
    final clock = FixedClock(DateTime(2026, 10, 10, 9));
    final store = LocalDataStore(driver: MemoryDriver());
    await store.open(scenario: DataScenario.demo, today: clock.today());
    final repos = FinanceRepositories(
      transactions: store.transactions, categories: store.categories, budgets: store.budgets,
      goals: store.goals, savingsMovements: store.savingsMovements, loans: store.loans,
      loanPayments: store.loanPayments, subscriptions: store.subscriptions, pending: store.pending,
      settlements: store.settlements, assets: store.assets, moneyAccounts: store.moneyAccounts, transfers: store.transfers, profile: store.profile,
      emergencyPlan: store.emergencyPlan, alertInbox: store.alertInbox,
        users: store.users, friends: store.friends, sharedLedger: store.sharedLedger,
    );
    final s = await repos.loadSnapshot(clock, monthStartDay: 1);
    final b = s.balance;
    // ignore: avoid_print
    print('cash=${b.cash} earmarked=${b.earmarked} available=${b.available} '
        'tx=${s.transactions.length} debt=${s.totalDebt} netWorth=${s.netWorth.netWorth}');
    final alerts = const AlertEngine().generate(s, const AppSettings());
    for (final a in alerts) {
      // ignore: avoid_print
      print('${a.severity.name}: ${a.title}');
    }
    expect(b.available.isPositive, isTrue);
    expect(s.loanStates.every((l) => l.warning == null), isTrue);
    expect(alerts, isNotEmpty);
  });
}
