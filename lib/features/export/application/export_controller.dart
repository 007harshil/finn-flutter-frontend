import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import 'export_file_sink.dart';
import 'export_service.dart';

/// Quick date ranges offered on the export screen.
enum ExportRangePreset {
  thisMonth('This month'),
  last3Months('Last 3 months'),
  financialYear('This financial year'),
  allTime('All time'),
  custom('Custom');

  const ExportRangePreset(this.label);
  final String label;
}

/// Start of the Indian financial year (1 April) containing [day].
DateTime financialYearStart(DateTime day) => DateTime(day.month >= 4 ? day.year : day.year - 1, 4);

/// Resolves [preset] to a concrete range ending today. [earliest] is the
/// first dated record (used for "All time").
DateRange exportPresetRange(ExportRangePreset preset, DateTime today, {DateTime? earliest, DateRange? custom}) {
  final t = today.dateOnly;
  return switch (preset) {
    ExportRangePreset.thisMonth => DateRange(t.startOfMonth, t),
    ExportRangePreset.last3Months => DateRange(DateTime(t.year, t.month - 2), t),
    ExportRangePreset.financialYear => DateRange(financialYearStart(t), t),
    ExportRangePreset.allTime => DateRange(earliest == null || earliest.isAfter(t) ? t : earliest, t),
    ExportRangePreset.custom => custom ?? DateRange(t.startOfMonth, t),
  };
}

/// Earliest date of any dated record (or the tracking start date).
DateTime? earliestRecordDate(FinanceSnapshot s) {
  DateTime? min;
  void see(DateTime d) {
    if (min == null || d.isBefore(min!)) min = d.dateOnly;
  }

  // Transactions are sorted newest first.
  if (s.transactions.isNotEmpty) see(s.transactions.last.date);
  final p = s.profile;
  if (p != null) see(p.openingDate);
  for (final m in s.savingsMovements) {
    see(m.date);
  }
  for (final x in s.loanPayments) {
    see(x.date);
  }
  for (final x in s.settlements) {
    see(x.date);
  }
  return min;
}

final exportEarliestDateProvider =
    Provider<DateTime?>((ref) => ref.watch(financeSnapshotProvider).whenData(earliestRecordDate).value);

/// Key for [exportCountsProvider].
@immutable
class ExportCountsKey {
  ExportCountsKey(this.range, Set<String>? categoryIds)
      : categoryIds = categoryIds == null ? null : (categoryIds.toList()..sort());

  final DateRange range;
  final List<String>? categoryIds;

  @override
  bool operator ==(Object other) =>
      other is ExportCountsKey &&
      other.range == range &&
      listEquals(other.categoryIds, categoryIds) &&
      (other.categoryIds == null) == (categoryIds == null);

  @override
  int get hashCode => Object.hash(range, categoryIds == null ? null : Object.hashAll(categoryIds!));
}

/// Records each module would export for a range and category filter.
final exportCountsProvider = Provider.family<AsyncValue<Map<ExportModule, int>>, ExportCountsKey>((ref, key) {
  return ref.watch(financeSnapshotProvider).whenData((s) => const ExportService().counts(
        s,
        ExportRequest(
          range: key.range,
          modules: ExportModule.values.toSet(),
          format: ExportFormat.csv,
          categoryIds: key.categoryIds?.toSet(),
        ),
      ));
});

/// Delivery mechanism; overridden in tests.
final exportFileSinkProvider = Provider<ExportFileSink>((ref) => const ShareExportFileSink());

enum ExportPhase { idle, preparing, sharing, success, failure }

@immutable
class ExportRunState {
  const ExportRunState({
    this.phase = ExportPhase.idle,
    this.artifacts = const [],
    this.delivery,
    this.errorMessage,
  });

  final ExportPhase phase;
  final List<ExportArtifact> artifacts;
  final ExportDeliveryStatus? delivery;
  final String? errorMessage;

  bool get isBusy => phase == ExportPhase.preparing || phase == ExportPhase.sharing;
}

/// Runs an export: fresh snapshot → files (off the UI isolate when large)
/// → share sheet.
class ExportController extends Notifier<ExportRunState> {
  @override
  ExportRunState build() => const ExportRunState();

  void reset() {
    if (!state.isBusy) state = const ExportRunState();
  }

  Future<void> run(ExportRequest request, {Rect? origin}) async {
    if (state.isBusy) return;
    if (request.modules.isEmpty) {
      state = const ExportRunState(phase: ExportPhase.failure, errorMessage: 'Choose at least one thing to export.');
      return;
    }
    state = const ExportRunState(phase: ExportPhase.preparing);
    List<ExportArtifact> files;
    try {
      final repos = ref.read(financeRepositoriesProvider);
      final clock = ref.read(clockProvider);
      final snapshot = await repos.loadSnapshot(clock, monthStartDay: ref.read(settingsProvider).monthStartDay);
      final job = ExportJob(snapshot, request, clock.now());
      final large = snapshot.transactions.length > exportIsolateThreshold;
      files = large ? await compute(generateExport, job) : await generateExport(job);
    } on AppFailure catch (f) {
      if (!ref.mounted) return;
      state = ExportRunState(phase: ExportPhase.failure, errorMessage: f.message);
      return;
    } catch (e, st) {
      debugPrint('Export failed: $e\n$st');
      if (!ref.mounted) return;
      state = const ExportRunState(
        phase: ExportPhase.failure,
        errorMessage: 'We could not prepare your files. Nothing was shared.',
      );
      return;
    }
    if (!ref.mounted) return;
    if (files.isEmpty) {
      state = const ExportRunState(phase: ExportPhase.failure, errorMessage: 'There was nothing to export.');
      return;
    }
    state = ExportRunState(phase: ExportPhase.sharing, artifacts: files);
    try {
      final status = await ref.read(exportFileSinkProvider).deliver(
            files,
            subject: 'FiNN export',
            origin: origin,
          );
      if (!ref.mounted) return;
      state = ExportRunState(phase: ExportPhase.success, artifacts: files, delivery: status);
    } catch (e, st) {
      debugPrint('Export sharing failed: $e\n$st');
      if (!ref.mounted) return;
      state = ExportRunState(
        phase: ExportPhase.failure,
        artifacts: files,
        errorMessage: 'Your files were created but could not be shared. Please try again.',
      );
    }
  }
}

final exportControllerProvider = NotifierProvider.autoDispose<ExportController, ExportRunState>(ExportController.new);
