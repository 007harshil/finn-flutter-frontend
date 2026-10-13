import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/shell/app_drawer.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart'
    show AmountText, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../../ui/ui.dart';
import '../../categories/domain/category.dart';
import '../application/transaction_filter.dart';
import 'widgets/activity_filter_sheet.dart';

/// Rows rendered per page of the client-side pagination.
const int _pageSize = 60;

/// "Activity": every completed transaction for a month (or a custom range),
/// with in/out totals that double as the type filter, search, and a filter
/// sheet. Filter state lives in [transactionFilterProvider] so it survives
/// tab switches; the filtered feed is derived in [transactionFeedProvider].
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key, this.initialType, this.initialMonth});

  final TransactionType? initialType;
  final MonthKey? initialMonth;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  late bool _searching = ref.read(transactionFilterProvider).query.isNotEmpty;
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

  TransactionFilterController get _filter => ref.read(transactionFilterProvider.notifier);

  void _toggleSearch() {
    setState(() => _searching = !_searching);
    if (!_searching) _filter.setQuery('');
  }

  void _clearRefinements() {
    setState(() => _searching = false);
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
    final advanced = ref.watch(transactionFilterProvider.select((f) => f.advancedCount));
    ref.listen(transactionFilterProvider, (prev, next) {
      if (prev != next && _visibleRows != _pageSize) setState(() => _visibleRows = _pageSize);
    });
    final feed = feedValue.value;

    return UiPage(
      leading: const AppMenuButton(),
      title: 'Activity',
      actions: [
        UiIconButton(
          key: const ValueKey('activity-search'),
          icon: LucideIcons.search,
          tooltip: _searching ? 'Close search' : 'Search',
          onPressed: _toggleSearch,
        ),
        UiIconButton(
          key: const ValueKey('activity-filters'),
          icon: LucideIcons.slidersHorizontal,
          tooltip: advanced == 0 ? 'Filters' : 'Filters, $advanced on',
          badge: advanced,
          onPressed: _openFilters,
        ),
      ],
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onScroll(n, feed),
        child: CustomScrollView(
          key: const PageStorageKey('activity-list'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(UiSpace.gutter, 0, UiSpace.gutter, 0),
              sliver: SliverToBoxAdapter(
                child: UiColumnWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_searching) ...[
                        UiSearchField(
                          hint: 'Name, note, category or amount',
                          initialValue: ref.read(transactionFilterProvider).query,
                          onChanged: _filter.setQuery,
                          onClose: _toggleSearch,
                        ),
                        const SizedBox(height: UiSpace.xs),
                      ],
                      _PeriodBar(onPickRange: _pickRange),
                    ],
                  ),
                ),
              ),
            ),
            ..._content(context, feedValue),
            SliverToBoxAdapter(child: SizedBox(height: context.bottomClearance)),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(BuildContext context, AsyncValue<TransactionFeed> value) {
    Widget box(Widget child, {double top = 0}) => SliverPadding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, top, UiSpace.gutter, 0),
      sliver: SliverToBoxAdapter(child: UiColumnWidth(child: child)),
    );

    if (!value.hasValue) {
      if (value.hasError) {
        return [
          box(
            UiEmpty(
              icon: LucideIcons.cloudOff,
              title: 'Could not load your transactions',
              message: 'Check your connection and try again.',
              action: 'Try again',
              onAction: () => refreshFinanceData(ref),
            ),
          ),
        ];
      }
      return [box(const _Placeholder(), top: UiSpace.md)];
    }

    final feed = value.requireValue;
    final filter = feed.filter;
    final summary = box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiReveal(index: 0, child: _Summary(feed: feed)),
          _ActiveFilters(onSort: _pickSort, onClearAll: _clearRefinements),
        ],
      ),
      top: UiSpace.sm,
    );

    if (feed.isEmpty) {
      final refined = filter.hasRefinements;
      return [
        summary,
        box(
          refined
              ? UiEmpty(
                  icon: LucideIcons.searchX,
                  title: 'No matches',
                  message: 'Try another search or filter, or widen the dates.',
                  action: 'Clear filters',
                  onAction: _clearRefinements,
                )
              : UiEmpty(
                  icon: LucideIcons.inbox,
                  title: 'Nothing recorded ${_periodPhrase(filter)}',
                  action: 'Add transaction',
                  onAction: () => context.push(AppRoutes.newTransaction()),
                ),
        ),
      ];
    }

    final rows = math.min(_visibleRows, feed.count);
    final entryCount = feed.entryCountFor(rows);
    final grouped = filter.sort.groupsByDate;
    final today = ref.read(todayProvider);
    final entries = feed.entries;
    bool isHeader(int i) => i >= entryCount || entries[i] is FeedDayHeader;

    return [
      summary,
      box(
        UiSectionTitle(
          title: feed.count == 1 ? '1 transaction' : '${feed.count} transactions',
          action: filter.sort.label,
          onAction: _pickSort,
        ),
        top: UiSpace.lg,
      ),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
        sliver: SliverList.builder(
          itemCount: entryCount,
          itemBuilder: (context, i) => UiColumnWidth(
            child: switch (entries[i]) {
              FeedDayHeader(:final date, :final net, :final count) => _DayHeader(
                key: ValueKey('day-${date.millisecondsSinceEpoch}'),
                date: date,
                today: today,
                net: net,
                count: count,
                first: i == 0,
              ),
              FeedTransaction(:final transaction) => UiPanelSlice(
                key: ValueKey(transaction.id),
                first: i == 0 || isHeader(i - 1),
                last: i == entryCount - 1 || isHeader(i + 1),
                child: TransactionRow(transaction: transaction, showDate: !grouped),
              ),
            },
          ),
        ),
      ),
      if (rows < feed.count)
        box(
          UiSecondaryButton(
            label: 'Show more',
            icon: LucideIcons.chevronDown,
            onPressed: () => setState(() => _visibleRows += _pageSize),
          ),
          top: UiSpace.lg,
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
    f.hasCustomRange ? 'in these dates' : 'in ${DateFormats.monthYear.format(f.month.start)}';

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

/// "‹ October 2026 ›" with a calendar for a custom range; a custom range
/// replaces the stepper until it is cleared.
class _PeriodBar extends ConsumerWidget {
  const _PeriodBar({required this.onPickRange});

  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiType.of(context);
    final month = ref.watch(transactionFilterProvider.select((f) => f.month));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    final bounds = ref.watch(activityMonthBoundsProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    if (range != null) {
      final label = _rangeLabel(range);
      return SizedBox(
        height: UiSpace.touch,
        child: Row(
          children: [
            Flexible(
              child: Semantics(
                button: true,
                label: 'Dates $label. Change',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onPickRange,
                  borderRadius: UiRadius.chip,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: UiSpace.xs, vertical: UiSpace.sm),
                    child: Text(
                      label,
                      style: t.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            UiIconButton(icon: LucideIcons.x, tooltip: 'Back to monthly view', size: 18, onPressed: notifier.clearRange),
          ],
        ),
      );
    }

    return UiPeriodStepper(
      label: DateFormats.monthYear.format(month.start),
      onPrevious: month > bounds.first ? () => notifier.setMonth(month.previous) : null,
      onNext: month < bounds.last ? () => notifier.setMonth(month.next) : null,
      trailing: UiIconButton(
        icon: LucideIcons.calendarRange,
        tooltip: 'Choose dates',
        size: 18,
        onPressed: onPickRange,
      ),
    );
  }
}

/// In and out for the period (each one also filters the list to that
/// type), what was kept, and one line comparing spending with the period
/// before.
class _Summary extends ConsumerWidget {
  const _Summary({required this.feed});

  final TransactionFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final f = feed.filter;
    final notifier = ref.read(transactionFilterProvider.notifier);
    void toggle(TransactionType type) {
      final cats = ref.read(categoriesByIdProvider).value ?? const <String, TransactionCategory>{};
      notifier.setType(f.type == type ? null : type, categories: cats);
    }

    final net = feed.net;
    final showNet = f.type == null && !(feed.income.isZero && feed.expense.isZero);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: UiStat(
                key: const ValueKey('activity-in'),
                label: 'In',
                value: AmountText(
                  feed.income,
                  style: t.figure.copyWith(color: feed.income.isZero ? null : c.positive),
                  decimals: DecimalDisplay.none,
                ),
                selected: f.type == TransactionType.income,
                semanticLabel: 'Money in, ${MoneyFormatter.spoken(feed.income)}. Show only income',
                onTap: () => toggle(TransactionType.income),
              ),
            ),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: UiStat(
                key: const ValueKey('activity-out'),
                label: 'Out',
                value: AmountText(feed.expense, style: t.figure, decimals: DecimalDisplay.none),
                selected: f.type == TransactionType.expense,
                semanticLabel: 'Money out, ${MoneyFormatter.spoken(feed.expense)}. Show only spending',
                onTap: () => toggle(TransactionType.expense),
              ),
            ),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: showNet
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: UiSpace.xs),
                      child: UiStat(
                        label: net.isNegative ? 'Overspent' : 'Kept',
                        value: AmountText(
                          net.abs(),
                          style: t.figure.copyWith(color: net.isNegative ? c.negative : null),
                          decimals: DecimalDisplay.none,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        _Trend(feed: feed),
      ],
    );
  }
}

/// "Spending 12% lower than Sep". Nothing when there is no fair comparison.
class _Trend extends StatelessWidget {
  const _Trend({required this.feed});

  final TransactionFeed feed;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final f = feed.filter;
    final incomeMode = f.type == TransactionType.income;
    final now = incomeMode ? feed.income : feed.expense;
    final before = incomeMode ? feed.previousIncome : feed.previousExpense;
    if (before.isZero || now.isZero || f.query.trim().isNotEmpty) return const SizedBox.shrink();
    final pct = ((now.paise - before.paise) * 100 / before.paise).round();
    final vs = f.hasCustomRange ? 'the dates before' : DateFormats.shortMonth.format(f.month.previous.start);
    final what = incomeMode ? 'Income' : 'Spending';
    final up = pct > 0;
    final good = incomeMode ? up : !up;
    return UiNotice(
      icon: pct == 0 ? LucideIcons.equal : (up ? LucideIcons.trendingUp : LucideIcons.trendingDown),
      color: pct == 0 ? null : (good ? c.positive : c.negative),
      text: pct == 0 ? '$what same as $vs' : '$what ${pct.abs()}% ${up ? 'higher' : 'lower'} than $vs',
    );
  }
}

/// A removable chip per filter set in the filter sheet, so the whole
/// filter state reads at a glance. Hidden when nothing is set.
class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.onSort, required this.onClearAll});

  final VoidCallback onSort;
  final VoidCallback onClearAll;

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
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: UiSpace.sm),
      child: Wrap(
        spacing: UiSpace.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (key, label, onRemove) in chips)
            UiChipButton(
              key: ValueKey('active-filter:$key'),
              label: label,
              trailingIcon: LucideIcons.x,
              semanticLabel: 'Remove filter $label',
              onTap: onRemove,
            ),
          if (chips.length > 1) UiTextButton(label: 'Clear all', onTap: onClearAll),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List pieces
// ---------------------------------------------------------------------------

/// "Today" · net for the day, above that day's panel.
class _DayHeader extends StatelessWidget {
  const _DayHeader({
    super.key,
    required this.date,
    required this.today,
    required this.net,
    required this.count,
    required this.first,
  });

  final DateTime date;
  final DateTime today;
  final Money net;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
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
        padding: EdgeInsets.fromLTRB(UiSpace.xs, first ? 0 : UiSpace.lg, UiSpace.xs, UiSpace.sm),
        child: Row(
          children: [
            Expanded(child: Text(label, style: t.label)),
            AmountText(net, sign: net.isZero ? SignDisplay.auto : SignDisplay.always, style: t.small),
          ],
        ),
      ),
    );
  }
}

/// Shaped like the summary and first day, so nothing jumps on load.
class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: UiPlaceholder(height: 44)),
            SizedBox(width: UiSpace.md),
            Expanded(child: UiPlaceholder(height: 44)),
            SizedBox(width: UiSpace.md),
            Expanded(child: UiPlaceholder(height: 44)),
          ],
        ),
        SizedBox(height: UiSpace.section),
        UiPlaceholder(width: 120, height: 14),
        SizedBox(height: UiSpace.md),
        UiPlaceholder(height: 300, radius: UiRadius.panel),
      ],
    );
  }
}
