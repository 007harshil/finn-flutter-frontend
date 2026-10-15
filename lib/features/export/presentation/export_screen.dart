import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../categories/domain/category.dart';
import '../application/export_controller.dart';
import '../application/export_file_sink.dart';
import '../application/export_service.dart';

/// Export records as CSV, JSON or a PDF report and hand them to the share
/// sheet.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  final _buttonKey = GlobalKey();
  ExportFormat _format = ExportFormat.csv;
  ExportRangePreset _preset = ExportRangePreset.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  Set<ExportModule> _modules = ExportModule.values.toSet();

  /// Null = every category.
  Set<String>? _categoryIds;

  DateRange _range(DateTime today) {
    DateRange? custom;
    if (_preset == ExportRangePreset.custom) {
      final start = _customStart ?? today.startOfMonth;
      var end = _customEnd ?? today;
      if (end.isBefore(start)) end = start;
      custom = DateRange(start, end);
    }
    return exportPresetRange(_preset, today, earliest: ref.read(exportEarliestDateProvider), custom: custom);
  }

  Rect? _origin() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _export(DateRange range) {
    ref.read(exportControllerProvider.notifier).run(
          ExportRequest(
            range: range,
            modules: _modules,
            format: _format,
            categoryIds: _modules.contains(ExportModule.transactions) ? _categoryIds : null,
          ),
          origin: _origin(),
        );
  }

  void _onRunChanged(ExportRunState? prev, ExportRunState next) {
    if (prev?.phase == next.phase) return;
    switch (next.phase) {
      case ExportPhase.success:
        final files = next.artifacts.length;
        if (next.delivery == ExportDeliveryStatus.dismissed) {
          FinnToast.info(context, 'Export not shared', subtitle: 'Your files are ready whenever you try again.');
        } else {
          FinnToast.success(context, files == 1 ? 'Export ready' : '$files files ready',
              subtitle: 'Keep them somewhere private.');
        }
      case ExportPhase.failure:
        FinnToast.error(context, next.errorMessage ?? 'Export failed', subtitle: 'Nothing was shared.');
      case ExportPhase.idle || ExportPhase.preparing || ExportPhase.sharing:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(exportControllerProvider, _onRunChanged);
    final today = ref.watch(todayProvider);
    ref.watch(exportEarliestDateProvider);
    final range = _range(today);
    final includeTx = _modules.contains(ExportModule.transactions);
    final counts = ref
        .watch(exportCountsProvider(ExportCountsKey(range, includeTx ? _categoryIds : null)))
        .value;
    final run = ref.watch(exportControllerProvider);
    final total = counts == null ? null : _modules.fold<int>(0, (sum, m) => sum + (counts[m] ?? 0));
    final t = context.type;

    final busy = run.isBusy;
    final label = switch (run.phase) {
      ExportPhase.preparing => 'Preparing files…',
      ExportPhase.sharing => 'Opening share sheet…',
      _ => total == null
          ? 'Export ${_format.label}'
          : 'Export ${_format.label} · $total record${total == 1 ? '' : 's'}',
    };
    return LedgerPage(
      storageKey: 'export',
      appBar: const LedgerAppBar(title: 'Export data'),
      slivers: [
        PageBlock(
          top: Sp.xl,
          child: _FormatSection(selected: _format, onChanged: (f) => setState(() => _format = f)),
        ),
        PageBlock(
          top: Sp.section,
          child: _PeriodSection(
            preset: _preset,
            range: range,
            today: today,
            onPreset: (p) => setState(() {
              _preset = p;
              if (p == ExportRangePreset.custom) {
                _customStart ??= range.start;
                _customEnd ??= range.end;
              }
            }),
            onStart: (d) => setState(() => _customStart = d),
            onEnd: (d) => setState(() => _customEnd = d),
          ),
        ),
        PageBlock(
          top: Sp.section,
          child: _ModulesSection(
            modules: _modules,
            counts: counts,
            onChanged: (m) => setState(() => _modules = m),
          ),
        ),
        if (includeTx)
          PageBlock(
            top: Sp.section,
            child: _CategorySection(
              selected: _categoryIds,
              onChanged: (ids) => setState(() => _categoryIds = ids),
            ),
          ),
        PageBlock(
          top: Sp.section,
          bottom: Sp.xl,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (run.phase == ExportPhase.failure && run.errorMessage != null) ...[
                Text('Export did not finish', style: t.bodyStrong),
                const SizedBox(height: Sp.sm),
                LedgerNote(tone: NoteTone.alert, icon: LucideIcons.circleAlert, text: run.errorMessage!),
                const SizedBox(height: Sp.lg),
              ] else if (run.phase == ExportPhase.success) ...[
                Text(
                  run.artifacts.length == 1 ? '1 file created' : '${run.artifacts.length} files created',
                  style: t.bodyStrong,
                ),
                const SizedBox(height: Sp.sm),
                LedgerNote(
                  icon: LucideIcons.circleCheck,
                  text: run.artifacts.map((a) => a.fileName).join('\n'),
                ),
                const SizedBox(height: Sp.lg),
              ],
              const LedgerNote(
                tone: NoteTone.caution,
                icon: LucideIcons.lock,
                text: 'Exports contain your personal financial details. Share them only with people and apps you trust.',
              ),
              const SizedBox(height: Sp.lg),
              LedgerButton(
                key: _buttonKey,
                label: label,
                icon: LucideIcons.share2,
                expand: true,
                loading: busy,
                onPressed: busy || _modules.isEmpty ? null : () => _export(range),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Format
// ---------------------------------------------------------------------------

class _FormatSection extends StatelessWidget {
  const _FormatSection({required this.selected, required this.onChanged});
  final ExportFormat selected;
  final ValueChanged<ExportFormat> onChanged;

  static IconData _icon(ExportFormat f) => switch (f) {
        ExportFormat.csv => LucideIcons.fileSpreadsheet,
        ExportFormat.json => LucideIcons.fileJson,
        ExportFormat.pdf => LucideIcons.fileText,
      };

  @override
  Widget build(BuildContext context) {
    return LedgerSection(
      title: 'Format',
      child: LedgerPanel(
        children: [
          for (final f in ExportFormat.values)
            LedgerOptionRow(
              key: ValueKey('format-${f.name}'),
              leading: IconWell(icon: _icon(f)),
              title: f.label,
              subtitle: f.description,
              selected: f == selected,
              onTap: () => onChanged(f),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Period
// ---------------------------------------------------------------------------

class _PeriodSection extends StatelessWidget {
  const _PeriodSection({
    required this.preset,
    required this.range,
    required this.today,
    required this.onPreset,
    required this.onStart,
    required this.onEnd,
  });

  final ExportRangePreset preset;
  final DateRange range;
  final DateTime today;
  final ValueChanged<ExportRangePreset> onPreset;
  final ValueChanged<DateTime> onStart;
  final ValueChanged<DateTime> onEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final fmt = DateFormats.dayMonthYear;
    return LedgerSection(
      title: 'Period',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerChoiceChips<ExportRangePreset>(
            options: [for (final p in ExportRangePreset.values) LedgerOption(p, p.label)],
            selected: preset,
            onChanged: onPreset,
          ),
          if (preset == ExportRangePreset.custom) ...[
            const SizedBox(height: Sp.lg),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: LedgerDateField(
                    label: 'From',
                    value: range.start,
                    firstDate: DateTime(today.year - 30),
                    lastDate: today,
                    onChanged: onStart,
                  ),
                ),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: LedgerDateField(
                    label: 'To',
                    value: range.end,
                    firstDate: range.start,
                    lastDate: today,
                    onChanged: onEnd,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Sp.md),
          Text(
            '${fmt.format(range.start)} – ${fmt.format(range.end)}. Applies to dated records; '
            'loans, budgets and assets are always included in full.',
            style: t.label.copyWith(color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Modules
// ---------------------------------------------------------------------------

class _ModulesSection extends StatelessWidget {
  const _ModulesSection({required this.modules, required this.counts, required this.onChanged});

  final Set<ExportModule> modules;
  final Map<ExportModule, int>? counts;
  final ValueChanged<Set<ExportModule>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final all = modules.length == ExportModule.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSection(
          title: 'What to include',
          actionLabel: all ? 'Clear all' : 'Select all',
          onAction: () => onChanged(all ? <ExportModule>{} : ExportModule.values.toSet()),
          child: LedgerPanel(
            children: [
              for (final m in ExportModule.values)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
                  child: LedgerSwitchRow(
                    key: ValueKey('module-${m.name}'),
                    title: m.label,
                    subtitle: _moduleSubtitle(m, counts?[m]),
                    value: modules.contains(m),
                    onChanged: (on) => onChanged(on ? {...modules, m} : ({...modules}..remove(m))),
                  ),
                ),
            ],
          ),
        ),
        if (modules.isEmpty) ...[
          const SizedBox(height: Sp.sm),
          Text('Choose at least one thing to export.', style: t.label.copyWith(color: c.red)),
        ],
      ],
    );
  }

  static String _moduleSubtitle(ExportModule m, int? n) {
    if (n == null) return m.description;
    return '${m.description} · ${n == 1 ? '1 record' : '$n records'}';
  }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

class _CategorySection extends ConsumerWidget {
  const _CategorySection({required this.selected, required this.onChanged});

  final Set<String>? selected;
  final ValueChanged<Set<String>?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final categories = ref.watch(categoriesStreamProvider).value ?? const <TransactionCategory>[];
    final active = categories.where((x) => !x.isArchived).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final all = selected == null;
    return LedgerSection(
      title: 'Transaction categories',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerSegmented<bool>(
            segments: const [LedgerSegment(true, 'All categories'), LedgerSegment(false, 'Choose')],
            selected: all,
            onChanged: (v) => onChanged(v ? null : <String>{}),
          ),
          if (!all) ...[
            const SizedBox(height: Sp.md),
            Wrap(
              spacing: Sp.sm,
              runSpacing: Sp.sm,
              children: [
                for (final cat in active)
                  LedgerChip(
                    key: ValueKey('cat-${cat.id}'),
                    icon: CategoryIcons.of(cat.iconKey),
                    label: cat.name,
                    selected: selected!.contains(cat.id),
                    onTap: () => onChanged(
                      selected!.contains(cat.id) ? ({...selected!}..remove(cat.id)) : {...selected!, cat.id},
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Sp.sm),
            Text(
              selected!.isEmpty
                  ? 'Pick one or more. No transactions are exported until you do.'
                  : '${selected!.length} selected. Only transactions in these categories are exported.',
              style: t.label.copyWith(color: c.inkSoft),
            ),
          ],
        ],
      ),
    );
  }
}
