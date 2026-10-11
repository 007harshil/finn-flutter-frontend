import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/analytics/presentation/insight_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {required bool reduced}) => MaterialApp(
      theme: FinnTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  for (final reduced in [true, false]) {
    testWidgets('HowCalculated expands and collapses (reduced motion: $reduced)', (tester) async {
      await tester.pumpWidget(_wrap(const HowCalculated(text: 'Income minus spending.'), reduced: reduced));
      expect(find.text('Income minus spending.'), findsNothing);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Income minus spending.'), findsOneWidget);

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Income minus spending.'), findsNothing);
    });
  }
}
