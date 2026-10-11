import 'package:finn/features/export/presentation/export_screen.dart';
import 'package:finn/features/net_worth/presentation/net_worth_screen.dart';
import 'package:finn/features/settings/presentation/notification_settings_screen.dart';
import 'package:finn/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

/// Renders each screen at a small phone width and scrolls through it; any
/// overflow fails the test.
void main() {
  for (final (name, screen) in [
    ('settings', const SettingsScreen()),
    ('notifications', const NotificationSettingsScreen()),
    ('net worth', const NetWorthScreen()),
    ('export', const ExportScreen()),
  ]) {
    testWidgets('$name lays out at 320 px wide', (tester) async {
      tester.view.physicalSize = const Size(320, 640) * tester.view.devicePixelRatio;
      addTearDown(tester.view.resetPhysicalSize);
      final env = await TestEnv.create();
      await env.pumpWidget(tester, screen);
      await tester.pumpAndSettle();
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -400), warnIfMissed: false);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }
}
