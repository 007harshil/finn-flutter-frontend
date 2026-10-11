import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/result/result.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../categories/domain/category.dart';
import '../application/transaction_filter.dart';

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
  late final TextEditingController _search =
      TextEditingController(text: ref.read(transactionFilterProvider).query);
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
          FinnMenuItem(
            value: s,
            label: s.label,
            icon: s == current ? LucideIcons.check : _sortIcon(s),
          ),
      ],
    );
    if (picked != null) _filter.setSort(picked);
  }

  Future<void> _pickCategories() async {
    final filter = ref.read(transactionFilterProvider);
    final cats = ref.read(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
    final picked = await showFinnSheet<Set<String>>(
      context,
      builder: (_) => _CategoryFilterSheet(
        categories: cats.values.where((c) => filter.type == null || c.type == filter.type).toList(),
        selected: filter.categoryIds,
      ),
    );
    if (picked != null) _filter.setCategories(picked);
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
                      onPickCategories: _pickCategories,
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
          padding: pad(Space.x3),
          sliver: SliverToBoxAdapter(child: _SelectedCategoriesBar(filter: filter)),
        ),
        SliverPadding(
          padding: pad(Space.x4),
          sliver: SliverToBoxAdapter(
            child: refined
                ? EmptyState(
                    icon: LucideIcons.searchX,
                    title: 'No transactions match these filters',
                    message: 'Try a different search, type or category, or widen the dates.',
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
          child: StaggeredEntrance(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SummaryStrip(feed: feed),
                _SelectedCategoriesBar(filter: filter),
              ],
            ),
          ),
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
    required this.onPickCategories,
  });

  final double side;
  final TextEditingController search;
  final VoidCallback onPickRange;
  final VoidCallback onPickCategories;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final month = ref.watch(transactionFilterProvider.select((f) => f.month));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    final type = ref.watch(transactionFilterProvider.select((f) => f.type));
    final catCount = ref.watch(transactionFilterProvider.select((f) => f.categoryIds.length));
    final bounds = ref.watch(activityMonthBoundsProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(side, Space.x2, side, Space.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: range == null
                      ? MonthSwitcher(
                          month: month,
                          min: bounds.first,
                          max: bounds.last,
                          onChanged: notifier.setMonth,
                        )
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
            const SizedBox(height: Space.x2),
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
                  count: catCount,
                  color: c.primary,
                  semanticsLabel: catCount == 0 ? null : '$catCount categories selected',
                  child: FinnIconButton(
                    icon: LucideIcons.slidersHorizontal,
                    tooltip: 'Filter by category',
                    variant: catCount == 0 ? FinnIconButtonVariant.outline : FinnIconButtonVariant.filled,
                    onPressed: onPickCategories,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.x2),
            SegmentedTabs<TransactionType?>(
              items: const [
                SegmentItem(null, 'All'),
                SegmentItem(TransactionType.income, 'Income'),
                SegmentItem(TransactionType.expense, 'Expense'),
              ],
              selected: type,
              onChanged: (t) => notifier.setType(
                t,
                categories: ref.read(categoriesByIdProvider).value ?? const {},
              ),
            ),
          ],
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
// Summary + list pieces
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.feed});

  final TransactionFeed feed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final f = feed.filter;
    final period = f.hasCustomRange ? _rangeLabel(f.range) : DateFormats.monthYear.format(f.month.start);
    final net = feed.net;
    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${feed.count} transaction${feed.count == 1 ? '' : 's'} · $period'.toUpperCase(),
            style: t.eyebrow,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: Space.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _SummaryFigure(
                  label: 'Income',
                  icon: LucideIcons.arrowDownLeft,
                  color: c.positive,
                  amount: feed.income,
                ),
              ),
              Expanded(
                child: _SummaryFigure(
                  label: 'Spent',
                  icon: LucideIcons.arrowUpRight,
                  color: c.negative,
                  amount: -feed.expense,
                ),
              ),
              Expanded(
                child: _SummaryFigure(
                  label: 'Net',
                  icon: net.isNegative ? LucideIcons.trendingDown : LucideIcons.trendingUp,
                  color: net.isNegative ? c.negative : c.positive,
                  amount: net,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({required this.label, required this.icon, required this.color, required this.amount});

  final String label;
  final IconData icon;
  final Color color;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: Space.x1),
              Flexible(child: Text(label, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: Space.x1),
          AnimatedAmount(
            amount,
            sign: amount.isZero ? SignDisplay.auto : SignDisplay.always,
            decimals: DecimalDisplay.none,
            fit: true,
            style: t.amountSmall.copyWith(color: amount.isZero ? null : color),
          ),
        ],
      ),
    );
  }
}

/// Removable chips for the selected categories.
class _SelectedCategoriesBar extends ConsumerWidget {
  const _SelectedCategoriesBar({required this.filter});

  final TransactionFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (filter.categoryIds.isEmpty) return const SizedBox.shrink();
    final cats = ref.watch(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
    final ids = filter.categoryIds.toList()..sort((a, b) => (cats[a]?.name ?? a).compareTo(cats[b]?.name ?? b));
    return Padding(
      padding: const EdgeInsets.only(top: Space.x2),
      child: Row(
        children: [
          Expanded(
            child: FilterChipBar<String>(
              padding: EdgeInsets.zero,
              items: [
                for (final id in ids) FilterChipItem(id, cats[id]?.name ?? 'Deleted category'),
              ],
              selected: filter.categoryIds,
              onChanged: (next) => ref.read(transactionFilterProvider.notifier).setCategories(next),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(transactionFilterProvider.notifier).setCategories(const {}),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

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
      _ => date.year == today.year
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

// ---------------------------------------------------------------------------
// Category multi-select
// ---------------------------------------------------------------------------

class _CategoryFilterSheet extends StatefulWidget {
  const _CategoryFilterSheet({required this.categories, required this.selected});

  final List<TransactionCategory> categories;
  final Set<String> selected;

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  late final Set<String> _selected = {...widget.selected};
  late final List<TransactionCategory> _sorted = [...widget.categories]..sort((a, b) {
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      if (a.type != b.type) return a.type == TransactionType.expense ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnSheetScaffold(
      title: 'Filter by category',
      description: 'Show only transactions in the categories you pick.',
      footer: Row(
        children: [
          Expanded(
            child: FinnButton(
              label: 'Clear',
              variant: FinnButtonVariant.outline,
              expand: true,
              onPressed: _selected.isEmpty ? null : () => setState(_selected.clear),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            flex: 2,
            child: FinnButton(
              label: _selected.isEmpty ? 'Show all' : 'Show ${_selected.length} selected',
              icon: LucideIcons.check,
              expand: true,
              onPressed: () => Navigator.of(context).pop(Set<String>.of(_selected)),
            ),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cat in _sorted)
            CheckboxListTile(
              key: ValueKey(cat.id),
              value: _selected.contains(cat.id),
              onChanged: (v) => setState(() => v == true ? _selected.add(cat.id) : _selected.remove(cat.id)),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              activeColor: c.primary,
              secondary: CategoryAvatar(category: cat, size: 36),
              title: Text(cat.name, style: t.bodyStrong),
              subtitle: Text(
                [cat.type.label, if (cat.isArchived) 'Archived'].join(' · '),
                style: t.caption,
              ),
            ),
        ],
      ),
    );
  }
}
