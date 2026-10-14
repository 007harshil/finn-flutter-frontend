import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

/// Money owed between the user and other people. Obligations only: the
/// cash balance changes when an item is settled.
///
/// Top to bottom: the net position as the one number with what is to get
/// and to pay, then status tabs with quick filters (side, waiting over
/// three weeks), search and sort, then one panel of items, longest waiting
/// first, with several items for one person (or one split bill) together.
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  PendingFilter _filter = const PendingFilter();
  bool _searching = false;

  void _set(PendingFilter f) => setState(() => _filter = f);

  Future<void> _openOptions() async {
    final next = await showPendingViewOptions(context, _filter);
    if (next != null && mounted) _set(next);
  }

  void _toggleDirection(PendingDirection d) =>
      _set(_filter.copyWith(tab: PendingTab.active, direction: () => _filter.direction == d ? null : d));

  void _toggleLong() {
    final on = _filter.ages.length == 1 && _filter.ages.contains(PendingAge.long);
    _set(_filter.copyWith(tab: PendingTab.active, ages: on ? const {} : {PendingAge.long}));
  }

  void _toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching) _filter = _filter.copyWith(query: '');
      });

  @override
  Widget build(BuildContext context) {
    return LedgerPage(
      storageKey: 'pending-list',
      appBar: LedgerAppBar(
        title: 'Money owed',
        actions: [
          LedgerIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add money owed',
            onPressed: () => context.push(AppRoutes.newPending(owedToMe: _filter.direction == PendingDirection.owedToMe)),
          ),
        ],
      ),
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<PendingOverview>(
            value: ref.watch(pendingOverviewProvider),
            loading: const LedgerPageSkeleton(),
            builder: (context, o) {
              final entries = ref.watch(pendingEntriesProvider(_filter)).value ?? const <PendingEntry>[];
              final shown = entries.fold<int>(0, (n, e) => n + pendingEntryCount(e));
              final any = o.counts.values.any((n) => n > 0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PageColumn(top: Sp.lg, child: _Hero(overview: o)),
                  if (!any)
                    PageColumn(top: Sp.xl, child: _Empty(filter: _filter))
                  else ...[
                    PageColumn(
                      top: Sp.section,
                      child: _Controls(
                        overview: o,
                        filter: _filter,
                        searching: _searching,
                        onTab: (t) => _set(_filter.copyWith(tab: t)),
                        onDirection: _toggleDirection,
                        onLong: _toggleLong,
                        onSearch: (q) => _set(_filter.copyWith(query: q)),
                        onSearchToggle: _toggleSearch,
                        onOptions: _openOptions,
                      ),
                    ),
                    if (_filter.activeCount > 0 || _filter.sort != PendingSort.waiting || _filter.query.trim().isNotEmpty)
                      PageColumn(
                        top: Sp.md,
                        child: _FilterSummary(
                          filter: _filter,
                          count: shown,
                          onSort: _openOptions,
                          onClear: () => _set(_filter.cleared()),
                        ),
                      ),
                    PageColumn(
                      top: Sp.md,
                      child: entries.isEmpty ? _Empty(filter: _filter) : _List(entries: entries),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// The one-glance answer: which way the money leans overall, then each
/// side when there are two.
class _Hero extends StatelessWidget {
  const _Hero({required this.overview});

  final PendingOverview overview;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final o = overview;
    if (o.activeCount == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('All square', style: t.title),
          const SizedBox(height: Sp.xs),
          Text('Nobody owes you and you owe nobody.', style: t.label),
        ],
      );
    }
    final net = o.net;
    final label = net.isPositive ? 'You’ll get overall' : (net.isNegative ? 'You owe overall' : 'Evenly balanced');
    final both = o.toPay.isPositive && o.toCollect.isPositive;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: t.label),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(
          net.abs(),
          style: t.figureXL.copyWith(color: net.isPositive ? c.green : c.ink),
          decimals: DecimalDisplay.none,
          fit: true,
          animateOnMount: true,
        ),
        const SizedBox(height: Sp.xs),
        Text('Not part of your balance until settled.', style: t.label),
        if (both) ...[
          const SizedBox(height: Sp.xl),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: LedgerStat(
                  label: 'To get',
                  value: AmountText(o.toCollect, style: t.figure.copyWith(color: c.green), decimals: DecimalDisplay.none),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerStat(
                  label: 'To pay',
                  value: AmountText(o.toPay, style: t.figure, decimals: DecimalDisplay.none),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Controls
// ---------------------------------------------------------------------------

/// Status tabs, then (on Active) quick filters, search and sort & filter.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.overview,
    required this.filter,
    required this.searching,
    required this.onTab,
    required this.onDirection,
    required this.onLong,
    required this.onSearch,
    required this.onSearchToggle,
    required this.onOptions,
  });

  final PendingOverview overview;
  final PendingFilter filter;
  final bool searching;
  final ValueChanged<PendingTab> onTab;
  final ValueChanged<PendingDirection> onDirection;
  final VoidCallback onLong;
  final ValueChanged<String> onSearch;
  final VoidCallback onSearchToggle;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final o = overview;
    final f = filter;
    final active = f.tab == PendingTab.active;
    final longOn = active && f.ages.length == 1 && f.ages.contains(PendingAge.long);
    Widget side(PendingDirection d, String label, int n) => LedgerChip(
          key: ValueKey('pending-side:${d.name}'),
          label: label,
          count: n,
          selected: f.direction == d,
          semanticLabel: '$label, $n ${n == 1 ? 'item' : 'items'}',
          onTap: () => onDirection(d),
        );
    // Waiting longest leads: those are the people to ask (or pay) first.
    final chips = <Widget>[
      if (active && (o.longCount > 0 || longOn))
        LedgerChip(
          key: const ValueKey('pending-attn:long'),
          label: 'Over 3 weeks',
          count: o.longCount,
          dot: c.amber,
          selected: longOn,
          semanticLabel: '${o.longCount} waiting over 3 weeks',
          onTap: onLong,
        ),
      if (active && o.collectCount > 0) side(PendingDirection.owedToMe, 'To get', o.collectCount),
      if (active && o.payCount > 0) side(PendingDirection.iOwe, 'To pay', o.payCount),
    ];
    final tools = [
      LedgerIconButton(
        key: const ValueKey('pending-search'),
        icon: LucideIcons.search,
        tooltip: 'Search',
        onPressed: onSearchToggle,
      ),
      LedgerIconButton(
        key: const ValueKey('pending-options'),
        icon: LucideIcons.slidersHorizontal,
        tooltip: 'Sort & filter',
        selected: f.activeCount > 0,
        badge: f.activeCount,
        badgeLabel: '${f.activeCount} filters on',
        onPressed: onOptions,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerSegmented<PendingTab>(
          selected: f.tab,
          onChanged: onTab,
          segments: [
            for (final tab in PendingTab.values)
              LedgerSegment(tab, tab.label, count: o.counts[tab] ?? 0, key: ValueKey('pending-tab:${tab.name}')),
          ],
        ),
        const SizedBox(height: Sp.md),
        if (searching)
          Row(
            children: [
              Expanded(child: LedgerSearchField(hint: 'Search people or purposes', onChanged: onSearch)),
              const SizedBox(width: Sp.xs),
              LedgerIconButton(icon: LucideIcons.x, tooltip: 'Close search', onPressed: onSearchToggle),
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Wrap, not scroll: every filter stays visible on narrow phones.
              Expanded(child: Wrap(spacing: Sp.sm, runSpacing: Sp.sm, children: chips)),
              const SizedBox(width: Sp.xs),
              ...tools,
            ],
          ),
      ],
    );
  }
}

/// Result count, the current sort (tap to change) and a way back to
/// everything. Shown only when the list is narrowed or re-ordered.
class _FilterSummary extends StatelessWidget {
  const _FilterSummary({required this.filter, required this.count, required this.onSort, required this.onClear});

  final PendingFilter filter;
  final int count;
  final VoidCallback onSort;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final f = filter;
    return Row(
      children: [
        Text('$count ${count == 1 ? 'item' : 'items'}', style: t.label),
        const SizedBox(width: Sp.md),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                if (f.sort != PendingSort.waiting)
                  LedgerChip(
                    label: f.sort.label,
                    icon: LucideIcons.arrowDownUp,
                    semanticLabel: 'Sorted by ${f.sort.label}. Change',
                    onTap: onSort,
                  ),
                if (f.activeCount > 0)
                  LedgerButton(
                    label: 'Clear filters',
                    variant: LedgerButtonVariant.quiet,
                    small: true,
                    onPressed: onClear,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

/// Every entry in one panel. A person with several items, or a split bill,
/// gets a header row with its items nested under it.
class _List extends StatelessWidget {
  const _List({required this.entries});

  final List<PendingEntry> entries;

  Future<void> _quickActions(BuildContext context, PendingView v) async {
    final owe = v.payment.direction.isOwe;
    final choice = await showFinnActionMenu<int>(
      context,
      title: '${v.payment.counterparty}, ${v.payment.purpose}',
      items: [
        if (v.status.isActive)
          FinnMenuItem(value: 0, label: owe ? 'Settle, I paid' : 'Settle, I received', icon: LucideIcons.circleCheck),
        const FinnMenuItem(value: 1, label: 'Open details', icon: LucideIcons.arrowUpRight),
        if (v.status.isActive && !owe) const FinnMenuItem(value: 2, label: 'Send a reminder', icon: LucideIcons.send),
      ],
    );
    if (!context.mounted || choice == null) return;
    switch (choice) {
      case 0:
        context.push(AppRoutes.settlePending(v.payment.id));
      case 1:
        context.push(AppRoutes.pendingItem(v.payment.id));
      case 2:
        await sharePendingReminder(context, v);
    }
  }

  Widget _row(BuildContext context, PendingView v, {bool grouped = false, bool inSplit = false}) => KeyedSubtree(
        key: ValueKey(v.payment.id),
        child: PendingRow(
          view: v,
          grouped: grouped,
          inSplit: inSplit,
          onTap: () => context.push(AppRoutes.pendingItem(v.payment.id)),
          onSettle: () => context.push(AppRoutes.settlePending(v.payment.id)),
          onLongPress: () => _quickActions(context, v),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return LedgerPanel(
      dividerIndent: Sp.lg + 40 + Sp.md + 2,
      children: [
        for (final e in entries)
          ...switch (e) {
            PendingItemEntry(:final view) => [_row(context, view)],
            PendingPersonGroup() => [
                _GroupHeader(group: e),
                for (final v in e.items) _row(context, v, grouped: true),
              ],
            PendingSplitEntry() => [
                PendingSplitHeader(
                  split: e.split,
                  shown: e.count,
                  onTap: () => context.push(AppRoutes.pendingItem(e.items.first.payment.id)),
                ),
                for (final v in e.items) _row(context, v, inSplit: true),
              ],
          },
      ],
    );
  }
}

/// A person with several items: who, how many, and where it nets out.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final PendingPersonGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final g = group;
    final net = g.toCollect - g.toPay;
    final side = net.isNegative ? 'to pay' : (net.isPositive ? 'to get' : 'evens out');
    return Semantics(
      header: true,
      child: LedgerRow(
        key: ValueKey('person-${g.name}'),
        leading: PendingInitials(name: g.name, shared: g.items.any((v) => v.payment.isShared)),
        title: g.name,
        subtitle: '${g.count} separate items',
        trailing: AmountText(net.abs(), style: t.figure.copyWith(color: net.isPositive ? c.green : c.ink)),
        trailingSub: Text(side, style: t.small),
        semanticLabel: '${g.name}, ${g.count} separate items. ${pendingSpoken(context, net.abs())} $side in total.',
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.filter});

  final PendingFilter filter;

  @override
  Widget build(BuildContext context) {
    if (filter.query.trim().isNotEmpty || filter.activeCount > 0) {
      return const LedgerEmpty(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'Try a different name or clear the filters.',
      );
    }
    return switch (filter.tab) {
      PendingTab.active => LedgerEmpty(
          title: 'Nothing open',
          message: 'Track a shared bill, a loan to a friend or a reimbursement. '
              'Your balance changes only when you settle.',
          actionLabel: 'Add money owed',
          onAction: () => context.push(AppRoutes.newPending()),
        ),
      PendingTab.settled => const LedgerEmpty(
          title: 'Nothing settled yet',
          message: 'Items you settle in full appear here with their history.',
        ),
      PendingTab.writtenOff => const LedgerEmpty(
          title: 'Nothing written off',
          message: 'Items you no longer expect to be paid appear here.',
        ),
    };
  }
}
