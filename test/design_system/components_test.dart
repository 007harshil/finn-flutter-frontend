import 'package:finn/core/money/money.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: FinnTheme.light(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('AmountText formats Indian grouping', (tester) async {
    await tester.pumpWidget(_wrap(const AmountText(Money.rupees(125000))));
    expect(find.text('₹1,25,000'), findsOneWidget);
    expect(find.bySemanticsLabel('1,25,000 rupees'), findsOneWidget);
  });

  testWidgets('AmountText masks when AmountVisibility hidden', (tester) async {
    await tester.pumpWidget(
      _wrap(const AmountVisibility(hidden: true, child: AmountText(Money.rupees(125000)))),
    );
    expect(find.text('₹1,25,000'), findsNothing);
    expect(find.text('₹ ••••'), findsOneWidget);
  });

  testWidgets('FinnButton loading disables tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(FinnButton(label: 'Save', loading: true, onPressed: () => taps++)),
    );
    await tester.tap(find.byType(FinnButton), warnIfMissed: false);
    await tester.pump();
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(_wrap(FinnButton(label: 'Save', onPressed: () => taps++)));
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('SegmentedTabs calls onChanged', (tester) async {
    String? changed;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320,
          child: SegmentedTabs<String>(
            items: const [SegmentItem('a', 'Expense'), SegmentItem('b', 'Income', count: 3)],
            selected: 'a',
            onChanged: (v) => changed = v,
          ),
        ),
      ),
    );
    expect(find.text('EXPENSE'), findsOneWidget);
    await tester.tap(find.text('INCOME'));
    await tester.pumpAndSettle();
    expect(changed, 'b');
  });

  testWidgets('EmptyState shows action', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _wrap(
        EmptyState(
          icon: LucideIcons.inbox,
          title: 'No transactions',
          message: 'Add your first one.',
          actionLabel: 'Add transaction',
          onAction: () => tapped = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('NO TRANSACTIONS'), findsOneWidget);
    await tester.tap(find.text('Add transaction'));
    expect(tapped, isTrue);
  });

  test('AmountField.parse and formatter', () {
    expect(AmountField.parse('1250.5'), const Money.fromPaise(125050));
    expect(AmountField.parse(''), isNull);
    const f = AmountInputFormatter();
    const old = TextEditingValue(text: '12.3');
    expect(f.formatEditUpdate(old, const TextEditingValue(text: '12.345')).text, '12.3');
    expect(f.formatEditUpdate(old, const TextEditingValue(text: '-1')).text, '12.3');
  });
}
