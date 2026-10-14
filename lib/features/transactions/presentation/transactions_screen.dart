import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../design_system/luxe/luxe.dart';
import '../../../features/transactions/domain/transaction.dart';
import '../../../shared/presentation/category_icons.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../../categories/domain/category.dart';
import '../application/transaction_filter.dart';
import 'widgets/activity_filter_sheet.dart';
import 'widgets/activity_summary.dart';

/// Rows rendered per page of the client-side pagination.
const int _pageSize = 60;

/// "Activity": the ledger. Every completed transaction, filterable by
/// period, text, type, category, amount, method and source.
///
/// Layout: serif title with sort → a pinned, frosted filter bar (period,
/// search, filters, type and active-filter chips) → the period summary →
/// the ledger grouped by day. Filter state lives in
/// [transactionFilterProvider] so it survives tab switches.
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
    final picked = await showLuxeMenu<TransactionSort>(
      context,
      eyebrow: 'Order the ledger',
      title: 'Sort by',
      items: [
        for (final s in TransactionSort.values)
          LuxeMenuItem(
            value: s,
            label: s.label,
            icon: s == current ? LucideIcons.check : _sortIcon(s),
            hint: s == current ? 'Current' : null,
          ),
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

    return LuxePage(
      storageKey: 'activity-list',
      compactTitle: 'Activity',
      onNotification: (n) => _onScroll(n, feed),
      slivers: [
        luxeBox(
          Reveal(
            child: _Title(onSort: _pickSort, onPickRange: _pickRange),
          ),
          top: 4,
        ),
        PinnedHeaderSliver(
          child: _FilterBar(search: _search, onPickRange: _pickRange, onOpenFilters: _openFilters),
        ),
        ..._content(context, feedValue),
      ],
    );
  }

  List<Widget> _content(BuildContext context, AsyncValue<TransactionFeed> value) {
    if (!value.hasValue) {
      if (value.hasError) {
        final e = value.error;
        return [
          luxeBox(
            LuxeError(
              title: 'Could not load your transactions',
              message: e is AppFailure ? e.message : 'Please try again.',
              onRetry: () => refreshFinanceData(ref),
            ),
            top: 24,
          ),
        ];
      }
      return [luxeBox(const _ActivitySkeleton(), top: 14)];
    }

    final feed = value.requireValue;
    final filter = feed.filter;
    if (feed.isEmpty) {
      final refined = filter.hasRefinements;
      return [
        luxeBox(
          refined
              ? LuxeEmpty(
                  icon: LucideIcons.searchX,
                  title: 'No transactions match',
                  message: 'Try a different search or filter, or widen the dates.',
                  actionLabel: 'Clear filters',
                  actionIcon: LucideIcons.filterX,
                  onAction: _clearRefinements,
                )
              : LuxeEmpty(
                  icon: LucideIcons.inbox,
                  title: 'Nothing recorded ${_periodPhrase(filter)}',
                  message: 'Income and expenses you record will appear here.',
                  actionLabel: 'Add transaction',
                  actionIcon: LucideIcons.plus,
                  onAction: () => context.push(AppRoutes.newTransaction()),
                ),
          top: 12,
        ),
      ];
    }

    final rows = math.min(_visibleRows, feed.count);
    final entryCount = feed.entryCountFor(rows);
    final grouped = filter.sort.groupsByDate;
    final today = ref.read(todayProvider);
    return [
      luxeBox(Reveal(index: 1, child: ActivitySummary(feed: feed)), top: 14),
      SliverPadding(
        padding: const EdgeInsets.only(top: 10),
        sliver: SliverList.builder(
          itemCount: entryCount,
          itemBuilder: (context, i) {
            final entry = switch (feed.entries[i]) {
              FeedDayHeader(:final date, :final net, :final count) => _DayHeader(
                key: ValueKey('day-${date.millisecondsSinceEpoch}'),
                date: date,
                today: today,
                net: net,
                count: count,
              ),
              FeedTransaction(:final transaction) => _LedgerRow(
                key: ValueKey(transaction.id),
                transaction: transaction,
                showDate: !grouped,
              ),
            };
            final row = ResponsiveCenter(
              padding: const EdgeInsets.symmetric(horizontal: LuxeSpace.gutter),
              child: entry,
            );
            // Only the first screenful choreographs in; the rest just appear.
            return i < 12 ? Reveal(index: i + 2, offset: 12, blur: 0, child: row) : row;
          },
        ),
      ),
      if (rows < feed.count)
        luxeBox(
          LuxeButton(
            label: 'Load more (${feed.count - rows} left)',
            icon: LucideIcons.chevronDown,
            variant: LuxeButtonVariant.outline,
            expand: true,
            onPressed: () => setState(() => _visibleRows += _pageSize),
          ),
          top: 16,
        )
      else if (feed.count > 8)
        luxeBox(
          Column(
            children: [
              Icon(LucideIcons.feather, size: 16, color: context.luxe.inkMute),
              const SizedBox(height: 8),
              Text(
                "That's everything ${_periodPhrase(filter)}",
                textAlign: TextAlign.center,
                style: context.lt.caption,
              ),
            ],
          ),
          top: 28,
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

class _Title extends ConsumerWidget {
  const _Title({required this.onSort, required this.onPickRange});

  final VoidCallback onSort;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(transactionFilterProvider.select((f) => f.sort));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeTopBar(
          actions: [
            LuxeIconButton(
              icon: LucideIcons.calendarRange,
              tooltip: 'Choose a date range',
              active: range != null,
              onPressed: onPickRange,
            ),
            LuxeIconButton(
              icon: LucideIcons.arrowUpDown,
              tooltip: 'Sort: ${sort.label}',
              active: sort != TransactionSort.newest,
              onPressed: onSort,
            ),
          ],
        ),
        const SizedBox(height: 18),
        const LuxeTitle(eyebrow: 'Your ledger', title: 'Activity'),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// Period, search, filters and type in one frosted band that stays pinned
/// while the ledger scrolls beneath it.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.search, required this.onPickRange, required this.onOpenFilters});

  final TextEditingController search;
  final VoidCallback onPickRange;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.luxe;
    final month = ref.watch(transactionFilterProvider.select((f) => f.month));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    final advanced = ref.watch(transactionFilterProvider.select((f) => f.advancedCount));
    final bounds = ref.watch(activityMonthBoundsProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: p.canvas.withValues(alpha: 0.86),
            border: Border(bottom: BorderSide(color: p.line)),
          ),
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter - 6, 2, LuxeSpace.gutter, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
                  child: range == null
                      ? LuxeMonthStepper(
                          key: const ValueKey('month'),
                          month: month,
                          min: bounds.first,
                          max: bounds.last,
                          compact: true,
                          onChanged: notifier.setMonth,
                        )
                      : Padding(
                          key: const ValueKey('range'),
                          padding: const EdgeInsets.only(left: 6, top: 4, bottom: 4),
                          child: _RangePill(range: range, onClear: notifier.clearRange, onTap: onPickRange),
                        ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchField(controller: search, onChanged: notifier.setQuery),
                      ),
                      const SizedBox(width: 8),
                      LuxeIconButton(
                        key: const ValueKey('activity-filters'),
                        icon: LucideIcons.slidersHorizontal,
                        tooltip: 'Filters',
                        semanticLabel: advanced == 0 ? 'Filters' : 'Filters, $advanced on',
                        active: advanced > 0,
                        badge: advanced,
                        onPressed: onOpenFilters,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _QuickFilters(onOpenFilters: onOpenFilters),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
      height: 46,
      decoration: BoxDecoration(
        color: focused ? p.paper : p.sunk,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: focused ? p.ink : Colors.transparent),
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(LucideIcons.search, size: 17, color: focused ? p.ink : p.inkMute),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
              textInputAction: TextInputAction.search,
              style: t.body,
              cursorColor: p.gold,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search payee, note or ₹',
                hintStyle: t.body.c(p.inkMute),
                hintMaxLines: 1,
              ),
            ),
          ),
          if (widget.controller.text.isNotEmpty)
            IconButton(
              tooltip: 'Clear search',
              onPressed: () {
                widget.controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              icon: Icon(LucideIcons.x, size: 16, color: p.inkSoft),
            )
          else
            const SizedBox(width: 14),
        ],
      ),
    );
  }
}

/// The type switch, then one removable chip per active filter so the whole
/// filter state reads at a glance.
class _QuickFilters extends ConsumerWidget {
  const _QuickFilters({required this.onOpenFilters});

  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.luxe;
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

    // A plain row (not a lazy list) so every active chip exists at once.
    return SizedBox(
      height: 46,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Center(
              child: SizedBox(
                width: 246,
                child: LuxeSegmented<TransactionType?>(
                  height: 38,
                  selected: f.type,
                  onChanged: (t) => notifier.setType(t, categories: cats),
                  segments: [
                    const LuxeSegment(null, 'All'),
                    LuxeSegment(TransactionType.income, 'Income', color: p.positive),
                    LuxeSegment(TransactionType.expense, 'Expense', color: p.negative),
                  ],
                ),
              ),
            ),
            for (final (key, label, onRemove) in chips) ...[
              const SizedBox(width: 6),
              Reveal(
                key: ValueKey('reveal-filter:$key'),
                scale: 0.85,
                offset: 0,
                blur: 0,
                duration: LuxeDurations.base,
                child: LuxeChip(
                  key: ValueKey('active-filter:$key'),
                  label: label,
                  selected: true,
                  height: 34,
                  trailing: LucideIcons.x,
                  semanticLabel: '$label filter. Remove',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onRemove();
                  },
                ),
              ),
            ],
            if (chips.isEmpty) ...[
              const SizedBox(width: 6),
              LuxeChip(
                label: 'Amount, category…',
                icon: LucideIcons.plus,
                height: 34,
                semanticLabel: 'Filter by amount, category, payment method or source',
                onTap: onOpenFilters,
              ),
            ],
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
    final p = context.luxe;
    final label = _rangeLabel(range);
    return Container(
      height: 44,
      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(22)),
      child: Row(
        children: [
          Expanded(
            child: Squish(
              onTap: onTap,
              semanticLabel: 'Date range $label. Change',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    Icon(LucideIcons.calendarRange, size: 16, color: p.canvas),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.lt.label.w(700).c(p.canvas),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Back to monthly view',
            onPressed: onClear,
            icon: Icon(LucideIcons.x, size: 16, color: p.canvas),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ledger
// ---------------------------------------------------------------------------

class _DayHeader extends StatelessWidget {
  const _DayHeader({super.key, required this.date, required this.today, required this.net, required this.count});

  final DateTime date;
  final DateTime today;
  final Money net;
  final int count;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
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
        padding: const EdgeInsets.only(top: 22, bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label, maxLines: 1, style: t.title.copyWith(fontSize: 20)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('$count', style: t.micro.w(700).c(p.goldInk)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: AmountText(
                  net,
                  sign: net.isZero ? SignDisplay.auto : SignDisplay.always,
                  fit: true,
                  textAlign: TextAlign.end,
                  style: t.numberSmall.c(p.inkSoft),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One ledger line: tinted category mark, payee and context, amount.
class _LedgerRow extends ConsumerWidget {
  const _LedgerRow({super.key, required this.transaction, this.showDate = false});

  final Transaction transaction;
  final bool showDate;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.luxe;
    final text = context.lt;
    final t = transaction;
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final subtitle = <String>[
      if (t.displayTitle != null && category != null) category.name,
      if (showDate) '${t.date.day} ${_months[t.date.month - 1]}',
      if (t.paymentMethod != null) t.paymentMethod!.label,
    ].join(' · ');
    final accent = p.mute(AccentSwatches.solid(category?.colorIndex ?? 6));
    final amount = t.isIncome ? t.amount : -t.amount;
    return Squish(
      onTap: () => context.push(AppRoutes.transaction(t.id)),
      scale: 0.985,
      semanticLabel: '$title, ${t.type.label}, ${MoneyFormatter.spoken(t.amount)}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: p.line)),
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: p.tint(accent, 0.13), shape: BoxShape.circle),
                  child: Icon(CategoryIcons.of(category?.iconKey), size: 19, color: accent),
                ),
                if (t.isLinked)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: p.paper,
                        shape: BoxShape.circle,
                        border: Border.all(color: p.line),
                      ),
                      child: Icon(LucideIcons.link2, size: 10, color: p.inkSoft),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.heading.copyWith(fontSize: 15)),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.38),
              child: AmountText(
                amount,
                sign: SignDisplay.always,
                fit: true,
                textAlign: TextAlign.end,
                style: text.number.c(t.isIncome ? p.positive : p.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) => LuxeShimmer(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeBone(height: 190, radius: LuxeSpace.rCard),
        const SizedBox(height: 26),
        const LuxeBone(width: 120, height: 20),
        for (var i = 0; i < 6; i++)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Row(
              children: [
                LuxeBone(width: 44, height: 44, radius: 22),
                SizedBox(width: 14),
                Expanded(child: LuxeBone(height: 14)),
                SizedBox(width: 40),
                LuxeBone(width: 64, height: 14),
              ],
            ),
          ),
      ],
    ),
  );
}
