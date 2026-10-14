import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/shell/app_drawer.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../categories/domain/category.dart';
import '../application/transaction_filter.dart';
import 'widgets/activity_filter_sheet.dart';
import 'widgets/activity_pulse.dart';

/// Rows rendered per page of the client-side pagination.
const int _pageSize = 60;

/// "Activity": every completed transaction, filterable by period, text,
/// type and category. Filter state lives in [transactionFilterProvider] so
/// it survives tab switches; the filtered feed is derived in
/// [transactionFeedProvider].
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialType, this.initialMonth});

  final TransactionType? initialType;
  final MonthKey? initialMonth;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late final TextEditingController _search = TextEditingController(text: ref.read(transactionFilterProvider).query);
  int _visibleRows = _pageSize;
  bool _extendQueued = false;

  @override
  void initState() {
    super.initState();
    _applyRoute(widget.initialType, widget.initialMonth);
  }

  @override
  void didUpdateWidget(TransactionsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialType != widget.initialType || oldWidget.initialMonth != widget.initialMonth) {
      _applyRoute(widget.initialType, widget.initialMonth);
    }
  }

  void _applyRoute(TransactionType? type, MonthKey? month) {
    if (type == null && month == null) return;
    // Providers cannot be modified while the tree builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(transactionFilterProvider.notifier).applyRoute(type: type, month: month);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  TransactionFilterController get _filter => ref.read(transactionFilterProvider.notifier);

  void _clearRefinements() {
    _search.clear();
    _filter.clearRefinements();
  }

  bool _onScroll(ScrollNotification n, TransactionFeed? feed) {
    if (feed == null || _extendQueued || _visibleRows >= feed.count) return false;
    if (n.metrics.axis == Axis.vertical && n.metrics.extentAfter < 600) {
      _extendQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _extendQueued = false;
        if (mounted) setState(() => _visibleRows += _pageSize);
      });
    }
    return false;
  }

  Future<void> _pickRange() async {
    final today = ref.read(todayProvider);
    final current = ref.read(transactionFilterProvider).range;
    final end = current.end.isAfter(today) ? today : current.end;
    final start = current.start.isAfter(end) ? end : current.start;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: today,
      initialDateRange: DateTimeRange(start: start, end: end),
      helpText: 'Show transactions between',
      saveText: 'Apply',
    );
    if (picked == null || !mounted) return;
    _filter.setRange(DateRange(picked.start, picked.end));
  }

  Future<void> _pickSort() async {
    final current = ref.read(transactionFilterProvider).sort;
    final picked = await showFinnActionMenu<TransactionSort>(
      context,
      title: 'Sort by',
      items: [
        for (final s in TransactionSort.values)
          FinnMenuItem(value: s, label: s.label, icon: s == current ? LucideIcons.check : _sortIcon(s)),
      ],
    );
    if (picked != null) _filter.setSort(picked);
  }

  Future<void> _openFilters() async {
    final picked = await showActivityFilterSheet(context, ref.read(transactionFilterProvider));
    if (picked != null && mounted) _filter.applyAdvanced(picked);
  }

  @override
  Widget build(BuildContext context) {
    final feedValue = ref.watch(transactionFeedProvider);
    ref.listen(transactionFilterProvider, (prev, next) {
      if (prev != next && _visibleRows != _pageSize) setState(() => _visibleRows = _pageSize);
    });
    final feed = feedValue.value;
    final c = context.colors;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final side = math.max(Space.gutter, (box.maxWidth - Space.maxContentWidth) / 2);
            return NotificationListener<ScrollNotification>(
              onNotification: (n) => _onScroll(n, feed),
              child: CustomScrollView(
                key: const PageStorageKey('activity-list'),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(side, Space.x4, side, Space.x2),
                    sliver: SliverToBoxAdapter(child: _TitleRow(onSort: _pickSort)),
                  ),
                  PinnedHeaderSliver(
                    child: _FilterHeader(
                      side: side,
                      search: _search,
                      onPickRange: _pickRange,
                      onOpenFilters: _openFilters,
                    ),
                  ),
                  ..._content(context, feedValue, side),
                  SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, AsyncValue<TransactionFeed> value, double side) {
    EdgeInsets pad([double top = 0]) => EdgeInsets.fromLTRB(side, top, side, 0);
    if (!value.hasValue) {
      if (value.hasError) {
        final e = value.error;
        return [
          SliverPadding(
            padding: pad(Space.x6),
            sliver: SliverToBoxAdapter(
              child: ErrorState(
                title: 'Could not load your transactions',
                message: e is AppFailure ? e.message : 'Please try again.',
                onRetry: () => refreshFinanceData(ref),
              ),
            ),
          ),
        ];
      }
      return [
        SliverPadding(
          padding: pad(Space.x3),
          sliver: const SliverToBoxAdapter(
            child: SkeletonPulse(
              child: Column(
                children: [
                  CardSkeleton(height: 92),
                  SizedBox(height: Space.x4),
                  ListSkeleton(count: 8, padding: EdgeInsets.zero),
                ],
              ),
            ),
          ),
        ),
      ];
    }

    final feed = value.requireValue;
    final filter = feed.filter;
    if (feed.isEmpty) {
      final refined = filter.hasRefinements;
      return [
        SliverPadding(
          padding: pad(Space.x4),
          sliver: SliverToBoxAdapter(
            child: refined
                ? EmptyState(
                    icon: LucideIcons.searchX,
                    title: 'No transactions match these filters',
                    message: 'Try a different search or filter, or widen the dates.',
                    actionLabel: 'Clear filters',
                    actionIcon: LucideIcons.filterX,
                    onAction: _clearRefinements,
                  )
                : EmptyState(
                    icon: LucideIcons.inbox,
                    title: 'Nothing recorded ${_periodPhrase(filter)}',
                    message: 'Income and expenses you record will appear here.',
                    actionLabel: 'Add transaction',
                    actionIcon: LucideIcons.plus,
                    onAction: () => context.push(AppRoutes.newTransaction()),
                  ),
          ),
        ),
      ];
    }

    final rows = math.min(_visibleRows, feed.count);
    final entryCount = feed.entryCountFor(rows);
    final grouped = filter.sort.groupsByDate;
    final today = ref.read(todayProvider);
    return [
      SliverPadding(
        padding: pad(Space.x3),
        sliver: SliverToBoxAdapter(
          child: StaggeredEntrance(child: ActivityPulse(feed: feed)),
        ),
      ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(side, Space.x2, side, 0),
        sliver: SliverList.builder(
          itemCount: entryCount,
          itemBuilder: (context, i) => switch (feed.entries[i]) {
            FeedDayHeader(:final date, :final net, :final count) => _DayHeader(
              key: ValueKey('day-${date.millisecondsSinceEpoch}'),
              date: date,
              today: today,
              net: net,
              count: count,
            ),
            FeedTransaction(:final transaction) => TransactionRow(
              key: ValueKey(transaction.id),
              transaction: transaction,
              showDate: !grouped,
            ),
          },
        ),
      ),
      if (rows < feed.count)
        SliverPadding(
          padding: pad(Space.x4),
          sliver: SliverToBoxAdapter(
            child: FinnButton(
              label: 'Load more (${feed.count - rows} left)',
              icon: LucideIcons.chevronDown,
              variant: FinnButtonVariant.outline,
              expand: true,
              onPressed: () => setState(() => _visibleRows += _pageSize),
            ),
          ),
        )
      else if (feed.count > 8)
        SliverPadding(
          padding: pad(Space.x5),
          sliver: SliverToBoxAdapter(
            child: Text(
              "That's everything ${_periodPhrase(filter)}",
              textAlign: TextAlign.center,
              style: context.text.caption,
            ),
          ),
        ),
    ];
  }
}

IconData _sortIcon(TransactionSort s) => switch (s) {
  TransactionSort.newest => LucideIcons.arrowDownWideNarrow,
  TransactionSort.oldest => LucideIcons.arrowUpNarrowWide,
  TransactionSort.highest => LucideIcons.trendingUp,
  TransactionSort.lowest => LucideIcons.trendingDown,
};

String _rangeLabel(DateRange r) {
  final sameYear = r.start.year == r.end.year;
  final start = sameYear ? DateFormats.dayMonth.format(r.start) : DateFormats.dayMonthYear.format(r.start);
  return '$start – ${DateFormats.dayMonthYear.format(r.end)}';
}

String _periodPhrase(TransactionFilter f) =>
    f.hasCustomRange ? 'in this date range' : 'in ${DateFormats.monthYear.format(f.month.start)}';

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _TitleRow extends ConsumerWidget {
  const _TitleRow({required this.onSort});

  final VoidCallback onSort;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(transactionFilterProvider.select((f) => f.sort));
    return Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text('Activity', style: context.text.pageTitle)),
        ),
        FinnIconButton(
          icon: LucideIcons.arrowUpDown,
          tooltip: 'Sort: ${sort.label}',
          variant: sort == TransactionSort.newest ? FinnIconButtonVariant.outline : FinnIconButtonVariant.filled,
          onPressed: onSort,
        ),
      ],
    );
  }
}

class _FilterHeader extends ConsumerWidget {
  const _FilterHeader({
    required this.side,
    required this.search,
    required this.onPickRange,
    required this.onOpenFilters,
  });

  final double side;
  final TextEditingController search;
  final VoidCallback onPickRange;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final month = ref.watch(transactionFilterProvider.select((f) => f.month));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    final advanced = ref.watch(transactionFilterProvider.select((f) => f.advancedCount));
    final bounds = ref.watch(activityMonthBoundsProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, Space.x1, side, Space.x2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const AppMenuButton(variant: FinnIconButtonVariant.outline, size: FinnButtonSize.sm),
                if (AppDrawerScope.maybeOf(context) != null) const SizedBox(width: Space.x2),
                Expanded(
                  child: range == null
                      ? MonthSwitcher(month: month, min: bounds.first, max: bounds.last, onChanged: notifier.setMonth)
                      : _RangePill(range: range, onClear: notifier.clearRange, onTap: onPickRange),
                ),
                const SizedBox(width: Space.x2),
                FinnIconButton(
                  icon: LucideIcons.calendarRange,
                  tooltip: 'Choose a date range',
                  variant: range == null ? FinnIconButtonVariant.outline : FinnIconButtonVariant.filled,
                  size: FinnButtonSize.sm,
                  onPressed: onPickRange,
                ),
              ],
            ),
            const SizedBox(height: Space.x1_5),
            Row(
              children: [
                Expanded(
                  child: FinnSearchField(
                    controller: search,
                    hint: 'Search name, note, category or ₹',
                    onChanged: notifier.setQuery,
                  ),
                ),
                const SizedBox(width: Space.x2),
                CountBadge(
                  count: advanced,
                  color: c.primary,
                  semanticsLabel: advanced == 0 ? null : '$advanced filters on',
                  child: FinnIconButton(
                    key: const ValueKey('activity-filters'),
                    icon: LucideIcons.slidersHorizontal,
                    tooltip: 'Filters',
                    variant: advanced == 0 ? FinnIconButtonVariant.outline : FinnIconButtonVariant.filled,
                    onPressed: onOpenFilters,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x1_5),
            _QuickFilterRow(onOpenFilters: onOpenFilters),
          ],
        ),
      ),
    );
  }
}

/// One slim row: the income/expense toggle, then a removable chip per
/// active filter so the whole filter state reads at a glance.
class _QuickFilterRow extends ConsumerWidget {
  const _QuickFilterRow({required this.onOpenFilters});

  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(transactionFilterProvider);
    final cats = ref.watch(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
    final notifier = ref.read(transactionFilterProvider.notifier);
    String catName(String id) => cats[id]?.name ?? 'Deleted category';

    final chips = <(String, String, VoidCallback)>[
      if (f.amount != null) ('amount', amountRangeLabel(f.amount), () => notifier.setAmount(null)),
      if (f.categoryIds.length <= 2)
        for (final id in f.categoryIds) ('cat:$id', catName(id), () => notifier.toggleCategory(id))
      else
        ('cats', '${f.categoryIds.length} categories', () => notifier.setCategories(const {})),
      if (f.methods.length == 1)
        ('methods', f.methods.single.label, () => notifier.setMethods(const {}))
      else if (f.methods.length > 1)
        ('methods', '${f.methods.length} payment methods', () => notifier.setMethods(const {})),
      if (f.origins.length == 1)
        ('origins', originLabel(f.origins.single), () => notifier.setOrigins(const {}))
      else if (f.origins.length > 1)
        ('origins', '${f.origins.length} sources', () => notifier.setOrigins(const {})),
    ];

    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _TypeToggle(
            selected: f.type,
            onChanged: (t) => notifier.setType(t, categories: cats),
          ),
          for (final (key, label, onRemove) in chips) ...[
            const SizedBox(width: Space.x1_5),
            _ActiveChip(key: ValueKey('active-filter:$key'), label: label, onRemove: onRemove),
          ],
          if (chips.isEmpty) ...[const SizedBox(width: Space.x1_5), _AddFilterChip(onTap: onOpenFilters)],
        ],
      ),
    );
  }
}

/// Compact All / In / Out switch with a sliding thumb.
class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.selected, required this.onChanged});

  final TransactionType? selected;
  final ValueChanged<TransactionType?> onChanged;

  static const _items = <(TransactionType?, String)>[
    (null, 'All'),
    (TransactionType.income, 'Income'),
    (TransactionType.expense, 'Expense'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final index = _items.indexWhere((i) => i.$1 == selected);
    final accent = switch (selected) {
      TransactionType.income => c.positive,
      TransactionType.expense => c.negative,
      null => c.textPrimary,
    };
    return Container(
      width: 204,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(-1 + index.toDouble(), 0),
            duration: context.motion.normal,
            curve: Curves2.emphasized,
            child: FractionallySizedBox(
              widthFactor: 1 / _items.length,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.isDark ? c.border : c.surface,
                  borderRadius: Radii.rFull,
                  boxShadow: c.isDark ? Elevation.none : Elevation.sm,
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final (value, label) in _items)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: value == selected,
                    inMutuallyExclusiveGroup: true,
                    label: label,
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (value == selected) return;
                        HapticFeedback.selectionClick();
                        onChanged(value);
                      },
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: context.motion.fast,
                          style: t.micro.copyWith(
                            color: value == selected ? accent : c.textSecondary,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                          child: Text(label.toUpperCase()),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({super.key, required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final chip = Semantics(
      button: true,
      label: '$label filter. Remove',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onRemove();
        },
        child: Container(
          padding: const EdgeInsets.only(left: Space.x3, right: Space.x2),
          decoration: BoxDecoration(
            color: c.primary.withValues(alpha: 0.1),
            borderRadius: Radii.rFull,
            border: Border.all(color: c.primary.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.micro.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: Space.x1),
              Icon(LucideIcons.x, size: 13, color: c.textSecondary),
            ],
          ),
        ),
      ),
    );
    if (context.reduceMotion) return chip;
    return chip.animate().fadeIn(duration: Durations2.fast).scaleXY(begin: 0.85, curve: Curves2.emphasized);
  }
}

class _AddFilterChip extends StatelessWidget {
  const _AddFilterChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Filter by amount, category, payment method or source',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.x3),
          decoration: BoxDecoration(
            borderRadius: Radii.rFull,
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.plus, size: 13, color: c.textSecondary),
              const SizedBox(width: Space.x1),
              Text(
                'Amount, category…',
                style: context.text.micro.copyWith(color: c.textSecondary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  const _RangePill({required this.range, required this.onClear, required this.onTap});

  final DateRange range;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = _rangeLabel(range);
    return Container(
      constraints: const BoxConstraints(minHeight: Dimens.buttonHeightSm),
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: Radii.rFull,
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Date range $label. Change',
              excludeSemantics: true,
              child: InkWell(
                borderRadius: Radii.rFull,
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.calendarRange, size: 16, color: c.textSecondary),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.text.label.copyWith(color: c.textPrimary, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Back to monthly view',
            onPressed: onClear,
            icon: Icon(LucideIcons.x, size: 16, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List pieces
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({super.key, required this.date, required this.today, required this.net, required this.count});

  final DateTime date;
  final DateTime today;
  final Money net;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final diff = daysBetween(today, date);
    final label = switch (diff) {
      0 => 'Today',
      -1 => 'Yesterday',
      _ =>
        date.year == today.year
            ? DateFormats.shortWeekdayDayMonth.format(date)
            : '${DateFormats.shortWeekdayDayMonth.format(date)} ${date.year}',
    };
    return Semantics(
      header: true,
      label: '$label, $count transaction${count == 1 ? '' : 's'}, net ${MoneyFormatter.spoken(net)}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x1, Space.x4, Space.x1, Space.x1),
        child: Row(
          children: [
            Expanded(child: Text(label.toUpperCase(), style: t.eyebrow)),
            AmountText(
              net,
              sign: net.isZero ? SignDisplay.auto : SignDisplay.always,
              style: t.caption.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
