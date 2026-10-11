import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FinnTextField with label and suffix accepts text', (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: FinnTheme.light(),
        home: Scaffold(
          body: FinnTextField(label: 'Interest rate', controller: controller, suffix: const Text('% p.a.')),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), '9.5');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('9.5'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Interest rate')), findsWidgets);
    handle.dispose();
  });
}
