import 'package:finn/features/subscriptions/domain/subscription.dart';
import 'package:finn/features/subscriptions/presentation/subscription_detail_screen.dart';
import 'package:finn/features/subscriptions/presentation/subscription_form_sheet.dart';
import 'package:finn/features/subscriptions/presentation/subscription_ui.dart';
import 'package:finn/features/subscriptions/presentation/subscriptions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());

  Future<Subscription> byName(String name) async =>
      (await env.snapshot()).subscriptions.firstWhere((s) => s.name == name);

  Future<void> sized(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
  }

  test('overview counts only active plans and totals the next 30 days', () async {
    final s = await env.snapshot();
    final o = SubscriptionsOverview.of(s);
    expect(o.paused.map((x) => x.name), contains('Disney+ Hotstar'));
    expect(o.monthly, const SubscriptionCalculator().monthlyCommitment(s.subscriptions));
    expect(o.upcoming, isNotEmpty);
    expect(o.upcoming.every((e) => e.subscription.isActive), isTrue);
    expect(o.overdueCount, greaterThanOrEqualTo(1)); // Cult.fit is past due
  });

  testWidgets('subscriptions screen shows commitment, upcoming and a pay action for overdue', (tester) async {
    await sized(tester);
    await env.pumpWidget(tester, const SubscriptionsScreen());
    await tester.pumpAndSettle();
    expect(find.text('Subscriptions'), findsOneWidget);
    expect(find.text('Per month'), findsOneWidget);
    expect(find.textContaining('Due soon', findRichText: true), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mark paid'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Mark paid'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detail shows next renewal and history', (tester) async {
    await sized(tester);
    final sub = await byName('Netflix Premium');
    await env.pumpWidget(tester, SubscriptionDetailScreen(id: sub.id));
    await tester.pumpAndSettle();
    expect(find.text('Next renewal'), findsOneWidget);
    expect(find.text('Mark paid'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('Payment history', findRichText: true), 300, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Payment history', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused detail offers resume instead of mark paid', (tester) async {
    await sized(tester);
    final sub = await byName('Disney+ Hotstar');
    await env.pumpWidget(tester, SubscriptionDetailScreen(id: sub.id));
    await tester.pumpAndSettle();
    expect(find.text('Mark paid'), findsNothing);
    expect(find.text('Resume'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('form sheet renders for add and edit', (tester) async {
    await sized(tester);
    await env.pumpWidget(tester, const SubscriptionFormSheet());
    await tester.pumpAndSettle();
    expect(find.text('New subscription'), findsOneWidget);
    expect(tester.takeException(), isNull);

    final sub = await byName('Spotify Premium');
    await env.pumpWidget(tester, SubscriptionFormSheet(subscriptionId: sub.id));
    await tester.pumpAndSettle();
    expect(find.text('Edit subscription'), findsOneWidget);
    expect(find.text('Spotify Premium'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
