import 'dart:convert';

import 'package:finn/design_system/design_system.dart';
import 'package:finn/features/export/application/export_controller.dart';
import 'package:finn/features/export/application/export_file_sink.dart';
import 'package:finn/features/export/application/export_service.dart';
import 'package:finn/features/export/presentation/export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

class _FakeSink implements ExportFileSink {
  List<ExportArtifact>? delivered;
  bool fail = false;

  @override
  Future<ExportDeliveryStatus> deliver(List<ExportArtifact> files, {String? subject, Rect? origin}) async {
    if (fail) throw StateError('share failed');
    delivered = files;
    return ExportDeliveryStatus.delivered;
  }
}

Future<void> _pump(WidgetTester tester, TestEnv env, _FakeSink sink) async {
  tester.view.physicalSize = const Size(420, 1400) * tester.view.devicePixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...env.overrides, exportFileSinkProvider.overrideWithValue(sink)],
      child: MaterialApp(
        theme: FinnTheme.light(),
        home: const MotionScope(reduceMotion: true, child: ExportScreen()),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> _runExport(WidgetTester tester) async {
  await tester.tap(find.byType(FinnButton).last);
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('exports the selected modules as JSON through the sink', (tester) async {
    final env = await TestEnv.create();
    final sink = _FakeSink();
    await _pump(tester, env, sink);

    expect(find.text('Export data'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('format-json')));
    await tester.pumpAndSettle();

    // Clear everything, then pick only assets.
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one thing to export.'), findsOneWidget);
    final button = tester.widget<FinnButton>(find.byType(FinnButton).last);
    expect(button.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('module-assets')));
    await tester.pumpAndSettle();
    expect(find.textContaining('5 records'), findsWidgets);

    await _runExport(tester);

    final files = sink.delivered;
    expect(files, isNotNull);
    expect(files, hasLength(1));
    expect(files!.single.fileName, endsWith('.json'));
    final json = jsonDecode(utf8.decode(files.single.bytes)) as Map<String, Object?>;
    expect(json.toString(), contains('Hyundai i20'));
    final done = find.text('1 file created');
    await tester.scrollUntilVisible(done, 300, scrollable: find.byType(Scrollable).first);
    expect(done, findsOneWidget);
  });

  testWidgets('shows a failure when sharing fails', (tester) async {
    final env = await TestEnv.create();
    final sink = _FakeSink()..fail = true;
    await _pump(tester, env, sink);

    await _runExport(tester);
    final banner = find.text('Export did not finish');
    await tester.scrollUntilVisible(banner, 300, scrollable: find.byType(Scrollable).first);
    expect(banner, findsOneWidget);
  });

  testWidgets('custom range shows date pickers', (tester) async {
    final env = await TestEnv.create();
    await _pump(tester, env, _FakeSink());
    final custom = find.text(ExportRangePreset.custom.label);
    await tester.ensureVisible(custom);
    await tester.pumpAndSettle();
    await tester.tap(custom);
    await tester.pumpAndSettle();
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
  });
}
