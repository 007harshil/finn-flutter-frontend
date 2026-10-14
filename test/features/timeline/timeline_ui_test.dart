import 'package:finn/features/timeline/presentation/timeline_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

void main() {
  testWidgets('timeline shows the chapter cover and steps back through months', (tester) async {
    tester.view.physicalSize = const Size(400, 900) * tester.view.devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    final env = await TestEnv.create();
    await env.pumpWidget(tester, const TimelineScreen());
    await tester.pumpAndSettle();

    expect(find.text('Timeline'), findsOneWidget);
    expect(find.text('YOUR FINANCIAL STORY'), findsOneWidget);
    expect(find.textContaining('KEY MOMENT', skipOffstage: false), findsOneWidget);

    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
