import 'package:finn/core/money/money.dart';
import 'package:finn/core/money/money_format.dart';
import 'package:finn/features/emergency_fund/domain/emergency_fund.dart';
import 'package:finn/features/goals/presentation/savings_widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'journey_helpers.dart';

/// The hero texts that describe [s] on the emergency fund screen.
void expectHeroShows(EmergencyFundStatus s) {
  expect(find.text(s.level.label), findsOneWidget);
  expect(find.text('Covers about ${coverageLabel(s.coverageMonths!)} of essentials'), findsOneWidget);
  expect(find.text('${formatBps(s.progressBps, decimals: 0)} of ${s.target.format()}'), findsOneWidget);
}

void main() {
  testWidgets('re-planning the emergency fund and adding money updates coverage everywhere', (tester) async {
    final env = await TestEnv.create();
    final before = await env.snapshot();
    const essentials = Money.rupees(40000);
    const added = Money.rupees(10000);

    await env.pumpApp(tester);
    await tester.pumpAndSettle();

    // Home quick access → Emergency fund.
    await scrollAndTap(tester, find.byKey(const ValueKey('quick-tile:Emergency fund')));
    expectHeroShows(before.emergency);

    // 1. Configure: essentials ₹40,000 × 6 months (no money moves).
    await tester.tap(find.byTooltip('Edit plan'));
    await tester.pumpAndSettle();
    expect(find.text('Edit emergency fund plan'), findsOneWidget);
    await enterAmount(tester, '40000');
    await tapButton(tester, 'Save changes');
    await settle(tester);
    expect(find.text('Edit emergency fund plan'), findsNothing);

    final planned = await env.snapshot();
    expect(planned.emergencyPlan!.essentialMonthlyExpenses, essentials);
    expect(planned.emergency.target, const Money.rupees(240000)); // 6 months
    expect(planned.emergency.saved, before.emergency.saved);
    expect(planned.emergency.coverageMonths, greaterThan(before.emergency.coverageMonths!));
    expect(planned.balance.available, before.balance.available, reason: 'planning moves no money');
    expectHeroShows(planned.emergency);

    // 2. Add money, approve the review.
    await tapButton(tester, 'Add money');
    await tester.pumpAndSettle();
    expect(find.text('Add money to emergency fund'), findsOneWidget);
    await enterAmount(tester, '10000');
    await tapButton(tester, 'Add money');
    await confirmReview(tester);
    expect(find.text('Add money to emergency fund'), findsNothing);

    final after = await env.snapshot();
    expect(after.emergency.saved, planned.emergency.saved + added);
    expect(after.emergency.coverageMonths, greaterThan(planned.emergency.coverageMonths!));
    expect(after.emergency.progressBps, greaterThan(planned.emergency.progressBps));
    expect(after.balance.cash, before.balance.cash);
    expect(after.balance.available, before.balance.available - added);
    await scrollTo(tester, find.text('Set aside'), up: true);
    expectHeroShows(after.emergency);

    // Home: set aside up, available down.
    await tapTab(tester, 'Home');
    expect(inHero(rupees(after.balance.available)), findsOneWidget);
    expect(inHero(rupees(after.balance.earmarked)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
