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
import '../../../features/transactions/domain/transaction.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../accounts/domain/transfer.dart';
import '../../accounts/presentation/transfer_form_sheet.dart';
import '../../accounts/presentation/widgets/transfer_row.dart';
import '../application/transaction_filter.dart';
import 'widgets/activity_filter_sheet.dart';
import 'widgets/activity_summary.dart';

/// Rows rendered per page of the client-side pagination.
const int _pageSize = 60;

/// Hairline indent between rows: lines up with the row text.
const double _rowIndent = Sp.lg + 40 + Sp.md + 2;

/// Height of the page title block; past it, content runs under the
/// pinned filters and they get a hairline edge.
const double _titleExtent = 52;

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
  final ValueNotifier<bool> _scrolledUnder = ValueNotifier(false);
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
    _scrolledUnder.dispose();
    super.dispose();
  }

  TransactionFilterController get _filter => ref.read(transactionFilterProvider.notifier);

  void _clearRefinements() {
    _search.clear();
    _filter.clearRefinements();
  }

  bool _onScroll(ScrollNotification n, TransactionFeed? feed) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _scrolledUnder.value = n.metrics.pixels > _titleExtent;
    if (feed == null || _extendQueued || _visibleRows >= feed.rowCount) return false;
    if (n.metrics.extentAfter < 600) {
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

    return NotificationListener<ScrollNotification>(
      onNotification: (n) => _onScroll(n, feed),
      child: LedgerPage(
        storageKey: 'activity-list',
        slivers: [
          PageBlock(
            child: PageHeader(
              title: 'Activity',
              actions: [
                LedgerIconButton(
                  key: const ValueKey('activity-transfer'),
                  icon: LucideIcons.arrowLeftRight,
                  tooltip: 'Record a transfer',
                  onPressed: () => showTransferSheet(context),
                ),
                _SortButton(onPressed: _pickSort),
              ],
            ),
          ),
          PinnedHeaderSliver(
            child: _FilterHeader(
              search: _search,
              scrolledUnder: _scrolledUnder,
              onPickRange: _pickRange,
              onOpenFilters: _openFilters,
            ),
          ),
          ..._content(context, feedValue),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, AsyncValue<TransactionFeed> value) {
    if (!value.hasValue) {
      if (value.hasError) {
        final e = value.error;
        return [
          PageBlock(
            top: Sp.xl,
            child: LedgerEmpty(
              icon: LucideIcons.cloudOff,
              title: 'Could not load your transactions',
              message: e is AppFailure ? e.message : 'Please try again.',
              actionLabel: 'Try again',
              onAction: () => refreshFinanceData(ref),
            ),
          ),
        ];
      }
      return const [PageBlock(top: Sp.xl, child: _ActivitySkeleton())];
    }

    final feed = value.requireValue;
    final filter = feed.filter;
    if (feed.hasNoRows) {
      final refined = filter.hasRefinements;
      return [
        // Keep the switches and filter chips in reach so a filter that
        // empties the list can be undone where it was set.
        if (refined) PageBlock(top: Sp.xl, child: ActivitySummary(feed: feed)),
        PageBlock(
          top: refined ? Sp.lg : Sp.xl,
          child: refined
              ? LedgerEmpty(
                  icon: LucideIcons.searchX,
                  title: 'No transactions match these filters',
                  message: 'Try a different search or filter, or widen the dates.',
                  actionLabel: 'Clear filters',
                  onAction: _clearRefinements,
                )
              : LedgerEmpty(
                  icon: LucideIcons.inbox,
                  title: 'Nothing recorded ${_periodPhrase(filter)}',
                  message: 'Income and expenses you record will appear here.',
                  actionLabel: 'Add transaction',
                  onAction: () => context.push(AppRoutes.newTransaction()),
                ),
        ),
      ];
    }

    final rows = math.min(_visibleRows, feed.rowCount);
    final items = _items(feed, feed.entryCountFor(rows));
    final grouped = filter.sort.groupsByDate;
    final today = ref.read(todayProvider);
    return [
      PageBlock(top: Sp.xl, child: ActivitySummary(feed: feed)),
      SliverPadding(
        padding: const EdgeInsets.only(top: Sp.lg),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => switch (items[i]) {
            _HeaderItem(:final header) => PageColumn(
                key: ValueKey('day-${header.date.millisecondsSinceEpoch}'),
                child: _DayHeader(date: header.date, today: today, net: header.net, count: header.count),
              ),
            _RowItem(:final transaction, :final first, :final last) => PageColumn(
                child: LedgerPanelSlice(
                  first: first,
                  last: last,
                  dividerIndent: _rowIndent,
                  child: TransactionRow(
                    key: ValueKey(transaction.id),
                    transaction: transaction,
                    showDate: !grouped,
                  ),
                ),
              ),
            _TransferItem(:final transfer, :final first, :final last) => PageColumn(
                child: LedgerPanelSlice(
                  first: first,
                  last: last,
                  dividerIndent: _rowIndent,
                  child: TransferRow(key: ValueKey(transfer.id), transfer: transfer, showDate: !grouped),
                ),
              ),
          },
        ),
      ),
      if (rows < feed.rowCount)
        PageBlock(
          top: Sp.xl,
          child: LedgerButton(
            label: 'Load more (${feed.rowCount - rows} left)',
            variant: LedgerButtonVariant.secondary,
            expand: true,
            onPressed: () => setState(() => _visibleRows += _pageSize),
          ),
        )
      else if (feed.rowCount > 8)
        PageBlock(
          top: Sp.xl,
          child: Text(
            "That's everything ${_periodPhrase(filter)}",
            textAlign: TextAlign.center,
            style: context.type.small,
          ),
        ),
    ];
  }
}

/// Flattens the first [count] feed entries into day headers and rows that
/// know where their day's panel starts and ends.
List<_Item> _items(TransactionFeed feed, int count) {
  final entries = feed.entries;
  final out = <_Item>[];
  var open = true;
  for (var i = 0; i < count; i++) {
    switch (entries[i]) {
      case final FeedDayHeader h:
        out.add(_HeaderItem(h));
        open = true;
      case FeedTransaction(:final transaction):
        final last = i + 1 >= count || entries[i + 1] is FeedDayHeader;
        out.add(_RowItem(transaction, first: open, last: last));
        open = false;
      case FeedTransfer(:final transfer):
        final last = i + 1 >= count || entries[i + 1] is FeedDayHeader;
        out.add(_TransferItem(transfer, first: open, last: last));
        open = false;
    }
  }
  return out;
}

sealed class _Item {
  const _Item();
}

final class _HeaderItem extends _Item {
  const _HeaderItem(this.header);
  final FeedDayHeader header;
}

final class _RowItem extends _Item {
  const _RowItem(this.transaction, {required this.first, required this.last});
  final Transaction transaction;
  final bool first;
  final bool last;
}

final class _TransferItem extends _Item {
  const _TransferItem(this.transfer, {required this.first, required this.last});
  final Transfer transfer;
  final bool first;
  final bool last;
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

class _SortButton extends ConsumerWidget {
  const _SortButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sort = ref.watch(transactionFilterProvider.select((f) => f.sort));
    return LedgerIconButton(
      icon: LucideIcons.arrowUpDown,
      tooltip: 'Sort: ${sort.label}',
      selected: sort != TransactionSort.newest,
      onPressed: onPressed,
    );
  }
}

/// Period and search, pinned while the list scrolls under them.
class _FilterHeader extends ConsumerWidget {
  const _FilterHeader({
    required this.search,
    required this.scrolledUnder,
    required this.onPickRange,
    required this.onOpenFilters,
  });

  final TextEditingController search;
  final ValueNotifier<bool> scrolledUnder;
  final VoidCallback onPickRange;
  final VoidCallback onOpenFilters;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final month = ref.watch(transactionFilterProvider.select((f) => f.month));
    final range = ref.watch(transactionFilterProvider.select((f) => f.customRange));
    final advanced = ref.watch(transactionFilterProvider.select((f) => f.advancedCount));
    final bounds = ref.watch(activityMonthBoundsProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);

    final body = PageColumn(
      top: Sp.sm,
      bottom: Sp.md,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: range == null
                    ? Transform.translate(
                        // Optically align the left arrow with the gutter.
                        offset: const Offset(-12, 0),
                        child: MonthStepper(month: month, min: bounds.first, max: bounds.last, onChanged: notifier.setMonth),
                      )
                    : _RangePill(range: range, onClear: notifier.clearRange, onTap: onPickRange),
              ),
              const SizedBox(width: Sp.xs),
              LedgerIconButton(
                icon: LucideIcons.calendarRange,
                tooltip: 'Choose a date range',
                selected: range != null,
                onPressed: onPickRange,
              ),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Expanded(
                child: LedgerSearchField(
                  controller: search,
                  hint: 'Search name, note or amount',
                  onChanged: notifier.setQuery,
                ),
              ),
              const SizedBox(width: Sp.xs),
              LedgerIconButton(
                key: const ValueKey('activity-filters'),
                icon: LucideIcons.slidersHorizontal,
                tooltip: 'Filters',
                selected: advanced > 0,
                badge: advanced,
                badgeLabel: advanced == 0 ? null : '$advanced filter${advanced == 1 ? '' : 's'} on',
                onPressed: onOpenFilters,
              ),
            ],
          ),
        ],
      ),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: scrolledUnder,
      builder: (context, under, child) => AnimatedContainer(
        duration: context.motion.fast,
        decoration: BoxDecoration(
          color: c.paper,
          border: Border(bottom: BorderSide(color: under ? c.line : c.paper)),
        ),
        child: child,
      ),
      child: body,
    );
  }
}

/// A custom date range in place of the month switcher: tap to change it,
/// the cross returns to months.
class _RangePill extends StatelessWidget {
  const _RangePill({required this.range, required this.onClear, required this.onTap});

  final DateRange range;
  final VoidCallback onClear;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final label = _rangeLabel(range);
    return Material(
      color: c.sunken,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              label: 'Date range $label. Change',
              excludeSemantics: true,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.only(left: Sp.lg),
                  child: SizedBox(
                    height: 44,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(label, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Back to monthly view',
            onPressed: onClear,
            icon: Icon(LucideIcons.x, size: 18, color: c.inkSoft),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List pieces
// ---------------------------------------------------------------------------

/// "Today", "Yesterday", "Fri, 9 Oct" with the day's net on the right.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.today, required this.net, required this.count});

  final DateTime date;
  final DateTime today;
  final Money net;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final diff = daysBetween(today, date);
    final label = switch (diff) {
      0 => 'Today',
      -1 => 'Yesterday',
      _ =>
        date.year == today.year
            ? DateFormats.shortWeekdayDayMonth.format(date)
            : '${DateFormats.shortWeekdayDayMonth.format(date)} ${date.year}',
    };
    final sign = net.isZero ? SignDisplay.auto : SignDisplay.always;
    return Semantics(
      header: true,
      label: '$label, $count transaction${count == 1 ? '' : 's'}'
          '${hidden ? '' : ', net ${AmountText.spokenLabel(net, sign: sign)}'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Sp.xl, bottom: Sp.sm),
        child: Row(
          children: [
            Expanded(child: Text(label, style: t.labelStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: Sp.md),
            AmountText(net, sign: sign, decimals: DecimalDisplay.none, style: t.figureSmall),
          ],
        ),
      ),
    );
  }
}

class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: const ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LedgerSkeleton(width: 70, height: 14),
                      SizedBox(height: Sp.sm),
                      LedgerSkeleton(width: 130, height: 30),
                    ],
                  ),
                ),
                SizedBox(width: Sp.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LedgerSkeleton(width: 70, height: 14),
                      SizedBox(height: Sp.sm),
                      LedgerSkeleton(width: 130, height: 30),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: Sp.lg),
            LedgerSkeleton(width: 240, height: 16),
            SizedBox(height: Sp.xl),
            LedgerSkeleton(height: 8, radius: 4),
            SizedBox(height: Sp.xl + Sp.lg),
            LedgerSkeleton(width: 90, height: 14),
            SizedBox(height: Sp.sm),
            LedgerSkeleton(height: 6 * 64, radius: Rad.lg),
          ],
        ),
      ),
    );
  }
}
