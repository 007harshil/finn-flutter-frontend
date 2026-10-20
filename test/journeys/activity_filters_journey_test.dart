import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/transactions/application/transaction_filter.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

void main() {
  testWidgets('activity summary explains the month and filters narrow the list', (tester) async {
    final env = await TestEnv.create();
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    await tapTab(tester, 'Activity');

    ProviderContainer container() => ProviderScope.containerOf(tester.element(find.byKey(const ValueKey('activity-filters'))));
    TransactionFilter filter() => container().read(transactionFilterProvider);

    // One-line verdict plus money in / money out.
    expect(find.textContaining(RegExp(r'^(Kept|Overspent|Spent|Earned)')), findsWidgets);
    expect(find.text('Money in'), findsOneWidget);
    expect(find.text('Money out'), findsOneWidget);

    // The two figures double as the type switch: tap to narrow, tap again for all.
    await tester.tap(find.byKey(const ValueKey('activity-type:income')));
    await tester.pumpAndSettle();
    expect(filter().type, TransactionType.income);
    expect(find.textContaining(RegExp(r'^Earned')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('activity-type:expense')));
    await tester.pumpAndSettle();
    expect(filter().type, TransactionType.expense);
    await tester.tap(find.byKey(const ValueKey('activity-type:expense')));
    await tester.pumpAndSettle();
    expect(filter().type, isNull);

    // Tapping a legend chip filters to that category; it shows as selected, once.
    final legend = find.byWidgetPredicate((w) => w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('pulse-legend:') &&
        !(w.key! as ValueKey<String>).value.endsWith('_other'));
    if (legend.evaluate().isNotEmpty) {
      await tester.tap(legend.first);
      await tester.pumpAndSettle();
      expect(filter().categoryIds, hasLength(1));
      // The legend chip already shows it: no second chip for the same category.
      expect(find.byKey(ValueKey('active-filter:cat:${filter().categoryIds.single}')), findsNothing);
      await tester.tap(legend.first);
      await tester.pumpAndSettle();
      expect(filter().categoryIds, isEmpty);
    }

    // Filter sheet: amount preset, account, live count, apply.
    await tester.tap(find.byKey(const ValueKey('activity-filters')));
    await tester.pumpAndSettle();
    expect(find.text('Filters'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('filter-amount:500-2000')));
    await tester.pumpAndSettle();
    await scrollAndTap(tester, find.byKey(const ValueKey('filter-account:acc_sbi')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-filter-apply')));
    await tester.pumpAndSettle();

    final f = filter();
    expect(f.amount, const AmountRange(minPaise: 50000, maxPaise: 200000));
    expect(f.advancedCount, 2);
    expect(find.byKey(const ValueKey('active-filter:amount')), findsOneWidget);
    expect(find.byKey(const ValueKey('active-filter:accounts')), findsOneWidget);

    // Removing a chip clears just that filter.
    await tester.tap(find.byKey(const ValueKey('active-filter:amount')));
    await tester.pumpAndSettle();
    expect(filter().amount, isNull);
    expect(filter().accountIds, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  // Small phone + heavy data: summary, list and filter sheet must not overflow.
  testWidgets('activity lays out at 320 px wide (stressed data)', (tester) async {
    tester.view.physicalSize = const Size(320, 640) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    // Full motion: every transition must also finish and settle.
    final env = await TestEnv.create(
      scenario: DataScenario.stressed,
      prefsValues: {'finn.settings.v1': '{"onboardingComplete":true,"motion":"full"}'},
    );
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    await tapTab(tester, 'Activity');
    await tester.tap(find.byKey(const ValueKey('activity-type:expense')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('activity-filters')));
    await tester.pumpAndSettle();
    final more = find.byKey(const ValueKey('filter-category-more'));
    if (more.evaluate().isNotEmpty) {
      await scrollAndTap(tester, more);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  });
}
