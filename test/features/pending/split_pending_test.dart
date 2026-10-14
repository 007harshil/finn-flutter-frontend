import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_providers.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/data/dto/dtos.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/pending/presentation/pending_detail_screen.dart';
import 'package:finn/features/pending/presentation/pending_form_sheet.dart';
import 'package:finn/features/pending/presentation/pending_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<ActionOutcome<O>> _run<I extends ActionInput, O>(
  ProviderContainer container,
  FinancialAction<I, O> action,
  I input, {
  required String key,
}) async {
  final dispatcher = container.read(actionDispatcherProvider);
  var outcome = await dispatcher.dispatch(action, input, idempotencyKey: key);
  if (outcome is ActionNeedsConfirmation<O>) {
    outcome = await dispatcher.dispatch(action, input,
        idempotencyKey: key, confirmation: ActionConfirmation(outcome.preview.fingerprint));
  }
  return outcome;
}

List<int> _paise(SplitOutcome o) => [for (final m in o.shares) m.paise];

void main() {
  group('calculator', () {
    test('equal split adds up exactly; the first person (me) absorbs the leftover paisa', () {
      final o = SplitCalculator.compute(const Money.rupees(100), SplitMethod.equally, [0, 0, 0]);
      expect(_paise(o), [3334, 3333, 3333]);
    });

    test('exact amounts must add up to the total', () {
      expect(SplitCalculator.compute(const Money.rupees(100), SplitMethod.exact, [6000, 4000]).isValid, isTrue);
      expect(SplitCalculator.compute(const Money.rupees(100), SplitMethod.exact, [6000, 3000]).error,
          contains('₹10 of the total is not given'));
      expect(SplitCalculator.compute(const Money.rupees(100), SplitMethod.exact, [6000, 5000]).error,
          contains('₹10 more than the total'));
    });

    test('percentages must add up to 100%', () {
      final ok = SplitCalculator.compute(const Money.rupees(1000), SplitMethod.percent, [5000, 3000, 2000]);
      expect(_paise(ok), [50000, 30000, 20000]);
      expect(SplitCalculator.compute(const Money.rupees(1000), SplitMethod.percent, [5000, 3000]).error,
          'Percentages add up to 80%, not 100%.');
    });

    test('shares divide by parts', () {
      final o = SplitCalculator.compute(const Money.rupees(1000), SplitMethod.shares, [2, 1, 1]);
      expect(_paise(o), [50000, 25000, 25000]);
      expect(SplitCalculator.compute(const Money.rupees(1000), SplitMethod.shares, [0, 0]).isValid, isFalse);
    });

    test('adjustments add or take off an equal part', () {
      // ₹1,000 with +₹100 for the second person: ₹300 each, then +₹100.
      final o = SplitCalculator.compute(const Money.rupees(1000), SplitMethod.adjustment, [0, 10000, 0]);
      expect(_paise(o), [30000, 40000, 30000]);
      expect(SplitCalculator.compute(const Money.rupees(100), SplitMethod.adjustment, [-12000, 0]).isValid, isFalse);
    });

    test('part labels describe each method', () {
      const s = PendingSplit(id: 's', method: SplitMethod.percent, includesMe: false, part: 3333);
      expect(s.partLabel, '33.33%');
      expect(s.withPart(4000).partLabel, '40%');
      expect(const PendingSplit(id: 's', method: SplitMethod.shares, includesMe: false, part: 2).partLabel, '2 shares');
    });
  });

  group('actions', () {
    late TestEnv env;
    late ProviderContainer container;

    setUp(() async {
      env = await TestEnv.create();
      container = env.container();
    });

    tearDown(() => container.dispose());

    SplitPendingInput input({
      SplitMethod method = SplitMethod.equally,
      bool includeMe = true,
      int myValue = 0,
      List<SplitPersonInput>? people,
      PendingDirection direction = PendingDirection.owedToMe,
      int total = 3000,
    }) =>
        SplitPendingInput(
          direction: direction,
          kind: PendingKind.sharedExpense,
          total: Money.rupees(total),
          purpose: 'Weekend cabin',
          createdDate: testNow,
          method: method,
          includeMe: includeMe,
          myValue: myValue,
          people: people ??
              const [
                SplitPersonInput(counterparty: 'Asha'),
                SplitPersonInput(counterparty: 'x', linkedUserId: 'u_ramesh'),
              ],
        );

    test('one split creates one item per person, all tied to the same bill', () async {
      final outcome = await _run(container, const CreateSplitPendingAction(), input(), key: 'eq');
      final items = (outcome as ActionCompleted<List<PendingPayment>>).value;
      expect([for (final p in items) p.counterparty], ['Asha', 'Ramesh Kumar']);
      expect([for (final p in items) p.originalAmount], everyElement(const Money.rupees(1000)));
      expect(items.map((p) => p.split!.id).toSet(), hasLength(1));
      expect(items.first.split!.myShare, const Money.rupees(1000));
      expect(items.first.link, isNull);
      expect(items.last.link!.userId, 'u_ramesh', reason: 'a FiNN user in a split is shared with them');
      expect(await env.store.sharedLedger.getById(MirrorEntry.keyOf('u_ramesh', items.last.link!.sharedId)), isNotNull);

      final split = PendingSplitView.collect((await env.snapshot()).pendingViews)[items.first.split!.id]!;
      expect(split.total, const Money.rupees(3000));
      expect(split.people, 3);
      expect(split.outstanding, const Money.rupees(2000));
    });

    test('shares, without me: the whole bill is owed', () async {
      final outcome = await _run(
        container,
        const CreateSplitPendingAction(),
        input(
          method: SplitMethod.shares,
          includeMe: false,
          people: const [SplitPersonInput(counterparty: 'Asha', value: 2), SplitPersonInput(counterparty: 'Bina', value: 1)],
        ),
        key: 'shares',
      );
      final items = (outcome as ActionCompleted<List<PendingPayment>>).value;
      expect([for (final p in items) p.originalAmount], [const Money.rupees(2000), const Money.rupees(1000)]);
      expect(items.first.split!.partLabel, '2 shares');
    });

    test('invalid splits are rejected with field errors', () async {
      Future<Set<String>> errors(SplitPendingInput i) async =>
          ((await _run(container, const CreateSplitPendingAction(), i, key: '${i.hashCode}')) as ActionRejected)
              .failure
              .fieldErrors
              .keys
              .toSet();

      expect(await errors(input(people: const [SplitPersonInput(counterparty: 'Asha')])), contains('people'));
      expect(
        await errors(input(people: const [SplitPersonInput(counterparty: 'Asha'), SplitPersonInput(counterparty: 'asha')])),
        contains('people.1.counterparty'),
      );
      expect(await errors(input(direction: PendingDirection.iOwe)), contains('includeMe'));
      expect(await errors(input(method: SplitMethod.percent, myValue: 5000)), contains('split'));
    });

    test('decodes agent JSON in human units', () {
      final i = const CreateSplitPendingAction().decode({
        'direction': 'owedToMe',
        'total': '1000',
        'purpose': 'Lunch',
        'createdDate': '2026-10-10',
        'method': 'percent',
        'includeMe': true,
        'myValue': 50,
        'people': [
          {'counterparty': 'Asha', 'value': '30%'},
          {'counterparty': 'Bina', 'value': 20},
        ],
      });
      expect(i.values, [5000, 3000, 2000]);
      expect(i.kind, PendingKind.sharedExpense);
    });

    test('editing one person changes the bill total and marks their part exact', () async {
      final items = ((await _run(container, const CreateSplitPendingAction(), input(), key: 'e')) as ActionCompleted<List<PendingPayment>>).value;
      final asha = items.first;
      await _run(
        container,
        const UpdatePendingAction(),
        UpdatePendingInput(
          id: asha.id,
          expectedVersion: asha.version,
          data: PendingInput(
            counterparty: 'Asha',
            direction: asha.direction,
            kind: asha.kind,
            amount: const Money.rupees(1500),
            purpose: asha.purpose,
            createdDate: asha.createdDate,
          ),
        ),
        key: 'edit',
      );
      final views = (await env.snapshot()).pendingViews;
      final split = PendingSplitView.collect(views)[asha.split!.id]!;
      expect(split.total, const Money.rupees(3500));
      expect(split.members.first.payment.split!.partLabel, 'Exact amount');
      expect(split.methodLabel, 'Custom');
    });

    test('a split survives a JSON round trip', () {
      const s = PendingSplit(id: 's', method: SplitMethod.adjustment, includesMe: true, myShare: Money.rupees(10), part: -500);
      final p = PendingPayment(
        id: 'p',
        counterparty: 'A',
        direction: PendingDirection.owedToMe,
        kind: PendingKind.sharedExpense,
        originalAmount: const Money.rupees(5),
        purpose: 'x',
        createdDate: testNow,
        createdAt: testNow,
        updatedAt: testNow,
        split: s,
      );
      expect(PendingDto.fromJson(PendingDto.toJson(p)).split, s);
    });
  });

  group('screens', () {
    late TestEnv env;

    setUp(() async => env = await TestEnv.create());

    testWidgets('the seeded dinner split is one entry in the list', (tester) async {
      final views = (await env.snapshot()).pendingViews;
      final entries = buildPendingEntries(views, const PendingFilter());
      final split = entries.whereType<PendingSplitEntry>().single;
      expect(split.items.map((v) => v.payment.counterparty), ['Karan Mehta', 'Arjun Shah']);
      expect(split.split.people, 4);
      expect(split.split.total, const Money.rupees(4800));
      expect(split.split.settledCount, 1, reason: 'Sneha settled');
    });

    testWidgets('detail shows the split card with everyone in the bill', (tester) async {
      tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final karan = (await env.snapshot()).pendingViews.firstWhere((v) => v.payment.counterparty == 'Karan Mehta');
      await env.pumpWidget(tester, PendingDetailScreen(id: karan.payment.id));
      await tester.pumpAndSettle();
      final card = find.byKey(const ValueKey('pending-split-card'));
      await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Split bill · 4 people'), findsOneWidget);
      expect(find.text('This item'), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text('Sneha Patil')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('every split method lays out on a narrow phone', (tester) async {
      tester.view.physicalSize = const Size(320, 1600) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await env.pumpWidget(tester, const PendingFormSheet(owedToMe: true));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pending-add-person')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.descendant(of: find.byType(AmountField), matching: find.byType(TextField)).first, '1234567.89');
      await tester.pumpAndSettle();
      for (final m in SplitMethod.values) {
        await tester.ensureVisible(find.byKey(ValueKey('split-method:${m.name}')));
        await tester.tap(find.byKey(ValueKey('split-method:${m.name}')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: m.name);
      }
    });

    testWidgets('adding a second person turns the form into a split with live shares', (tester) async {
      tester.view.physicalSize = const Size(400, 1600) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      await env.pumpWidget(tester, const PendingFormSheet(owedToMe: true));
      await tester.pumpAndSettle();

      Finder field(Finder parent) => find.descendant(of: parent, matching: find.byType(TextField)).first;
      await tester.enterText(field(find.byKey(const ValueKey('pending-person:0'))), 'Asha');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('pending-split-editor')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('pending-add-person')));
      await tester.pumpAndSettle();
      await tester.enterText(field(find.byKey(const ValueKey('pending-person:1'))), 'Bina');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(field(find.byType(AmountField)), '3000');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('pending-split-editor')), findsOneWidget);
      expect(find.textContaining('₹1,000 each', findRichText: true), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('split-method:exact')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('split-value:0')), '1500');
      await tester.pumpAndSettle();
      expect(find.textContaining('more than the total'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('split-value:1')), '500');
      await tester.pumpAndSettle();
      expect(find.textContaining('Adds up to ₹3,000', findRichText: true), findsOneWidget);

      await tester.enterText(field(find.widgetWithText(FinnTextField, 'What is it for?')), 'Cabin');
      await tester.tap(find.text('Split with 2 people'));
      await tester.pumpAndSettle();

      final created = (await env.snapshot()).pendingViews.where((v) => v.payment.purpose == 'Cabin').toList();
      expect({for (final v in created) v.payment.counterparty: v.payment.originalAmount},
          {'Asha': const Money.rupees(1500), 'Bina': const Money.rupees(500)});
      expect(created.first.payment.split!.myShare, const Money.rupees(1000));
      expect(tester.takeException(), isNull);
    });
  });
}

