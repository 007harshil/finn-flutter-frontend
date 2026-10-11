import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
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

    final sections = <Widget>[
      _FormatSection(selected: _format, onChanged: (f) => setState(() => _format = f)),
      _PeriodSection(
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
      _ModulesSection(
        modules: _modules,
        counts: counts,
        onChanged: (m) => setState(() => _modules = m),
      ),
      if (includeTx)
        _CategorySection(
          selected: _categoryIds,
          onChanged: (ids) => setState(() => _categoryIds = ids),
        ),
      if (run.phase == ExportPhase.failure && run.errorMessage != null)
        InfoBanner(tone: FinnTone.negative, title: 'Export did not finish', message: run.errorMessage!)
      else if (run.phase == ExportPhase.success)
        InfoBanner(
          tone: FinnTone.positive,
          title: run.artifacts.length == 1 ? '1 file created' : '${run.artifacts.length} files created',
          message: run.artifacts.map((a) => a.fileName).join('\n'),
        ),
      const InfoBanner(
        tone: FinnTone.warning,
        icon: LucideIcons.lock,
        message: 'Exports contain your personal financial details. Share them only with people and apps you trust.',
      ),
    ];

    final busy = run.isBusy;
    final label = switch (run.phase) {
      ExportPhase.preparing => 'Preparing files…',
      ExportPhase.sharing => 'Opening share sheet…',
      _ => total == null
          ? 'Export ${_format.label}'
          : 'Export ${_format.label} · $total record${total == 1 ? '' : 's'}',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Export data')),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              key: const PageStorageKey('export'),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x6),
                  sliver: SliverList.separated(
                    itemCount: sections.length,
                    separatorBuilder: (_, _) => const SizedBox(height: Space.x6),
                    itemBuilder: (context, i) => ResponsiveCenter(
                      padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                      child: StaggeredEntrance(index: i, child: sections[i]),
                    ),
                  ),
                ),
              ],
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: context.colors.surface,
              border: Border(top: BorderSide(color: context.colors.border)),
            ),
            child: SafeArea(
              top: false,
              child: ResponsiveCenter(
                padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x3),
                child: FinnButton(
                  key: _buttonKey,
                  label: label,
                  icon: LucideIcons.share2,
                  expand: true,
                  size: FinnButtonSize.lg,
                  loading: busy,
                  onPressed: busy || _modules.isEmpty ? null : () => _export(range),
                ),
              ),
            ),
          ),
        ],
      ),
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
    final c = context.colors;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: LucideIcons.fileText, title: 'Format', tileColor: c.primary),
        const SizedBox(height: Space.x3),
        for (final f in ExportFormat.values) ...[
          Semantics(
            selected: f == selected,
            inMutuallyExclusiveGroup: true,
            child: FinnCard(
              key: ValueKey('format-${f.name}'),
              onTap: () => onChanged(f),
              padding: const EdgeInsets.all(Space.x3 + 2),
              border: BorderSide(color: f == selected ? c.primary : c.border, width: f == selected ? 2 : 1),
              child: Row(
                children: [
                  IconTile(
                    icon: _icon(f),
                    background: f == selected ? c.primary : c.surfaceMuted,
                    foreground: f == selected ? c.onPrimary : c.textSecondary,
                    size: 36,
                    radius: Radii.md,
                    iconSize: 18,
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.label, style: t.bodyStrong),
                        Text(f.description, style: t.caption),
                      ],
                    ),
                  ),
                  Icon(
                    f == selected ? LucideIcons.circleCheck : LucideIcons.circle,
                    size: 20,
                    color: f == selected ? c.primary : c.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Space.x2),
        ],
      ],
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
    final c = context.colors;
    final t = context.text;
    final fmt = DateFormats.dayMonthYear;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: LucideIcons.calendarRange, title: 'Period', tileColor: c.accentTransactions),
        const SizedBox(height: Space.x3),
        FilterChipBar<ExportRangePreset>(
          padding: EdgeInsets.zero,
          multiSelect: false,
          items: [for (final p in ExportRangePreset.values) FilterChipItem(p, p.label)],
          selected: {preset},
          onChanged: (s) {
            if (s.isNotEmpty) onPreset(s.first);
          },
        ),
        if (preset == ExportRangePreset.custom) ...[
          const SizedBox(height: Space.x4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DateField(
                  label: 'From',
                  value: range.start,
                  firstDate: DateTime(today.year - 30),
                  lastDate: today,
                  onChanged: onStart,
                ),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: DateField(
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
        const SizedBox(height: Space.x3),
        Text(
          '${fmt.format(range.start)} – ${fmt.format(range.end)}. Applies to dated records such as transactions '
          'and payments; loans, budgets and assets are always included in full.',
          style: t.caption,
        ),
      ],
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
    final c = context.colors;
    final t = context.text;
    final all = modules.length == ExportModule.values.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: LucideIcons.listChecks,
          title: 'What to include',
          tileColor: c.accentNetWorth,
          trailing: TextButton(
            onPressed: () => onChanged(all ? <ExportModule>{} : ExportModule.values.toSet()),
            child: Text(all ? 'Clear all' : 'Select all'),
          ),
        ),
        const SizedBox(height: Space.x3),
        FinnCard(
          padding: const EdgeInsets.symmetric(vertical: Space.x1),
          child: Column(
            children: [
              for (var i = 0; i < ExportModule.values.length; i++) ...[
                if (i > 0) const FinnDivider(indent: Space.x4),
                _ModuleRow(
                  key: ValueKey('module-${ExportModule.values[i].name}'),
                  module: ExportModule.values[i],
                  count: counts?[ExportModule.values[i]],
                  selected: modules.contains(ExportModule.values[i]),
                  onChanged: (on) {
                    final m = ExportModule.values[i];
                    onChanged(on ? {...modules, m} : ({...modules}..remove(m)));
                  },
                ),
              ],
            ],
          ),
        ),
        if (modules.isEmpty) ...[
          const SizedBox(height: Space.x2),
          Text('Choose at least one thing to export.', style: t.caption.copyWith(color: c.negative)),
        ],
      ],
    );
  }
}

class _ModuleRow extends StatelessWidget {
  const _ModuleRow({super.key, required this.module, required this.count, required this.selected, required this.onChanged});

  final ExportModule module;
  final int? count;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final n = count;
    return MergeSemantics(
      child: InkWell(
        onTap: () => onChanged(!selected),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1, Space.x4, Space.x1),
            child: Row(
              children: [
                Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
                const SizedBox(width: Space.x1),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(module.label, style: t.bodyStrong),
                      Text(module.description, style: t.caption),
                    ],
                  ),
                ),
                if (n != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x0_5),
                    decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rSm),
                    child: Text(n == 1 ? '1 record' : '$n records', style: t.micro),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
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
    final c = context.colors;
    final t = context.text;
    final categories = ref.watch(categoriesStreamProvider).value ?? const <TransactionCategory>[];
    final active = categories.where((x) => !x.isArchived).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    final all = selected == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(icon: LucideIcons.tags, title: 'Transaction categories', tileColor: c.accentBudgets),
        const SizedBox(height: Space.x3),
        SegmentedTabs<bool>(
          items: const [SegmentItem(true, 'All categories'), SegmentItem(false, 'Choose')],
          selected: all,
          onChanged: (v) => onChanged(v ? null : <String>{}),
        ),
        if (!all) ...[
          const SizedBox(height: Space.x3),
          Wrap(
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final cat in active)
                FilterChip(
                  key: ValueKey('cat-${cat.id}'),
                  avatar: Icon(CategoryIcons.of(cat.iconKey), size: 16),
                  label: Text(cat.name),
                  selected: selected!.contains(cat.id),
                  onSelected: (on) => onChanged(on ? {...selected!, cat.id} : ({...selected!}..remove(cat.id))),
                ),
            ],
          ),
          const SizedBox(height: Space.x2),
          Text(
            selected!.isEmpty
                ? 'Pick one or more categories. No transactions are exported until you do.'
                : '${selected!.length} selected. Only transactions in these categories are exported.',
            style: t.caption,
          ),
        ],
      ],
    );
  }
}
