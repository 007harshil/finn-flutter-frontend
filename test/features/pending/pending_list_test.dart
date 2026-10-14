import 'package:finn/core/money/money.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/pending/presentation/pending_screen.dart';
import 'package:finn/features/pending/presentation/pending_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';
import '../../journeys/journey_helpers.dart';

// Demo seed, active items (today = testNow). Pending items have no due date;
// only how long each one has waited matters.
//   Ananya Iyer  owes me ₹3,000 left of ₹5,000, open 50 days
//   Neha Kapoor  owes me ₹850, open 35 days
//   Rahul Verma  I owe   ₹2,000 left of ₹3,200, open 24 days
//   Priya Nair   owes me ₹6,500, open 20 days
//   Rahul Verma  I owe   ₹780, open 9 days
//   Karan Mehta + Arjun Shah owe me ₹1,200 each, open 6 days: one split bill
//     (Team dinner at Toit, 4 ways with me; Sneha Patil already settled)
void main() {
  late TestEnv env;
  late List<PendingView> views;

  setUp(() async {
    env = await TestEnv.create();
    views = (await env.snapshot()).pendingViews;
  });

  List<String> purposes(PendingFilter f) => [for (final v in filterPending(views, f)) v.payment.purpose];

  group('filter and sort', () {
    test('default order is waiting longest first: whom to ask or pay first', () {
      expect(purposes(const PendingFilter()), [
        'Emergency cash',
        'Office lunch',
        'Concert tickets',
        'Goa trip hotel share',
        'Cab to airport',
        'Team dinner at Toit',
        'Team dinner at Toit',
      ]);
    });

    test('largest amount sorts by what is left', () {
      expect(purposes(const PendingFilter(sort: PendingSort.amount)).first, 'Goa trip hotel share');
      expect(purposes(const PendingFilter(sort: PendingSort.amount)).last, 'Cab to airport');
    });

    test('age buckets, direction and reason filters combine', () {
      expect(purposes(const PendingFilter(ages: {PendingAge.long})), ['Emergency cash', 'Office lunch', 'Concert tickets']);
      expect(purposes(const PendingFilter(ages: {PendingAge.weeks})), ['Goa trip hotel share', 'Cab to airport']);
      expect(purposes(const PendingFilter(ages: {PendingAge.fresh})), ['Team dinner at Toit', 'Team dinner at Toit']);
      expect(
        purposes(const PendingFilter(ages: {PendingAge.long}, direction: PendingDirection.owedToMe)),
        ['Emergency cash', 'Office lunch'],
      );
      expect(purposes(const PendingFilter(kinds: {PendingKind.lent})), ['Emergency cash']);
      expect(const PendingFilter(ages: {PendingAge.long}, direction: PendingDirection.iOwe).activeCount, 2);
    });

    test('items with one person share a group at the rank of their longest-waiting item', () {
      final entries = buildPendingEntries(views, const PendingFilter());
      expect(entries, hasLength(5));
      final group = entries[2] as PendingPersonGroup;
      expect(group.name, 'Rahul Verma');
      expect(group.toPay, const Money.rupees(2780));
      expect(buildPendingEntries(views, const PendingFilter(groupByPerson: false)), hasLength(6),
          reason: 'a split stays one entry even when people are not grouped');
    });

    test('overview sums each side and lists who has waited longest', () {
      final o = PendingOverview.of(views);
      expect(o.toPay, const Money.rupees(2780));
      expect(o.toCollect, const Money.rupees(12750));
      expect(o.net, const Money.rupees(9970));
      expect(o.longCount, 3);
      expect(o.longToCollect, const Money.rupees(3850));
      expect(o.longToPay, const Money.rupees(2000));
      expect([for (final v in o.oldest) v.payment.counterparty], ['Ananya Iyer', 'Neha Kapoor', 'Rahul Verma']);
      expect(o.people, 6);
    });

    test('the age sentence is informative, with no deadline wording', () {
      final ananya = views.firstWhere((v) => v.payment.purpose == 'Emergency cash');
      expect(pendingAgeSentence(ananya), 'Ananya Iyer has not returned your money yet. 50 days have passed.');
      final rahul = views.firstWhere((v) => v.payment.purpose == 'Concert tickets');
      expect(pendingAgeSentence(rahul), 'You have not paid Rahul Verma back yet. 24 days have passed.');
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester tester, {bool reduceMotion = true, double width = 400}) async {
      tester.view.physicalSize = Size(width, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(ProviderScope(
        overrides: env.overrides,
        child: MaterialApp(
          theme: FinnTheme.light(),
          home: MotionScope(reduceMotion: reduceMotion, child: const PendingScreen()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('over-3-weeks shortcut narrows the list and toggles back', (tester) async {
      await pump(tester);
      expect(find.text('Priya Nair'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pending-attn:long')));
      await tester.pumpAndSettle();
      expect(find.text('Ananya Iyer'), findsOneWidget);
      expect(find.text('Priya Nair'), findsNothing, reason: 'open 20 days');
      expect(find.text('3 ITEMS'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('pending-attn:long')));
      await tester.pumpAndSettle();
      expect(find.text('Priya Nair'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sort & filter sheet applies a sort with a live count', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('pending-options')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Name A–Z'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OWED TO ME'));
      await tester.pumpAndSettle();
      expect(find.text('Show 5 items'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pending-apply')));
      await tester.pumpAndSettle();

      expect(find.text('Rahul Verma'), findsNothing);
      final a = tester.getTopLeft(find.text('Ananya Iyer')).dy;
      final n = tester.getTopLeft(find.text('Neha Kapoor')).dy;
      final p = tester.getTopLeft(find.text('Priya Nair')).dy;
      expect(a < n && n < p, isTrue, reason: 'name order');
      expect(find.text('Name A–Z'), findsOneWidget, reason: 'current sort shown above the list');
      expect(tester.takeException(), isNull);
    });

    testWidgets('search finds by purpose; tabs switch to settled items', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('pending-search')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cab');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('Cab to airport'), findsOneWidget);
      expect(find.text('Priya Nair'), findsNothing);

      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Settled 2', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.text('Vikram Rao'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders with full motion on a narrow screen', (tester) async {
      await pump(tester, reduceMotion: false, width: 320);
      await tester.tap(find.byKey(const ValueKey('pending-attn:long')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Concert tickets'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('swiping a row right opens the settle sheet', (tester) async {
    await env.pumpApp(tester);
    await tester.pumpAndSettle();
    await scrollAndTap(tester, find.byKey(const ValueKey('quick-tile:Pending payments')));
    final id = views.firstWhere((v) => v.payment.purpose == 'Goa trip hotel share').payment.id;
    await scrollTo(tester, find.byKey(ValueKey(id)));
    await tester.drag(find.byKey(ValueKey(id)), const Offset(260, 0));
    await tester.pumpAndSettle();
    expect(find.text('OUTSTANDING'), findsOneWidget);
    expect(find.text('Record money from Priya Nair'), findsOneWidget);
  });
}
