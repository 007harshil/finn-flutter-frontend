import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart'
    show AmountText, AmountVisibility, AnimatedAmount, BottomClearanceX, FinnMenuItem, showFinnActionMenu;
import '../../../shared/presentation/async_view.dart';
import '../../../ui/ui.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

/// Money owed between the user and other people. Obligations only: the
/// balance changes when an item is settled.
///
/// Top to bottom: the net position with what goes out and what comes
/// back (each a filter), the status tabs when there is history, any active
/// filters, then one panel of rows with several items for one person or
/// one bill kept together.
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
    return UiPage(
      title: 'Money owed',
      actions: [
        UiIconButton(
          key: const ValueKey('pending-search'),
          icon: LucideIcons.search,
          tooltip: 'Search',
          onPressed: _toggleSearch,
        ),
        UiIconButton(
          key: const ValueKey('pending-options'),
          icon: LucideIcons.slidersHorizontal,
          tooltip: _filter.activeCount > 0 ? 'Sort & filter, ${_filter.activeCount} on' : 'Sort & filter',
          badge: _filter.activeCount,
          onPressed: _openOptions,
        ),
        UiIconButton(
          icon: LucideIcons.plus,
          tooltip: 'Add money owed',
          onPressed: () => context.push(AppRoutes.newPending(owedToMe: _filter.direction == PendingDirection.owedToMe)),
        ),
      ],
      body: AsyncView<PendingOverview>(
        value: ref.watch(pendingOverviewProvider),
        loading: const _Placeholder(),
        builder: (context, o) {
          if (o.counts.values.every((n) => n == 0)) {
            return Center(
              child: SingleChildScrollView(
                child: UiEmpty(
                  icon: LucideIcons.handshake,
                  title: 'All square',
                  message: 'Track a shared bill, money lent to a friend or a reimbursement.',
                  action: 'Add money owed',
                  onAction: () => context.push(AppRoutes.newPending()),
                ),
              ),
            );
          }
          final entries = ref.watch(pendingEntriesProvider(_filter)).value ?? const <PendingEntry>[];
          final history = (o.counts[PendingTab.settled] ?? 0) + (o.counts[PendingTab.writtenOff] ?? 0) > 0;
          return CustomScrollView(
            key: const PageStorageKey('pending-list'),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: UiColumnWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_searching) ...[
                          UiSearchField(
                            hint: 'Search people or purposes',
                            onChanged: (q) => _set(_filter.copyWith(query: q)),
                            onClose: _toggleSearch,
                          ),
                          const SizedBox(height: UiSpace.lg),
                        ] else ...[
                          UiReveal(
                            index: 0,
                            child: _Position(
                              overview: o,
                              filter: _filter,
                              onDirection: _toggleDirection,
                              onLong: _toggleLong,
                            ),
                          ),
                          const SizedBox(height: UiSpace.section),
                        ],
                        if (history) ...[
                          UiSegmented<PendingTab>(
                            segments: [
                              for (final tab in PendingTab.values) UiSegment(tab, tab.label, count: o.counts[tab] ?? 0),
                            ],
                            selected: _filter.tab,
                            onChanged: (t) => _set(_filter.copyWith(tab: t)),
                          ),
                          const SizedBox(height: UiSpace.sm),
                        ],
                        _ActiveFilters(filter: _filter, onChanged: _set, onSort: _openOptions),
                        const SizedBox(height: UiSpace.xs),
                      ],
                    ),
                  ),
                ),
              ),
              if (entries.isEmpty)
                SliverToBoxAdapter(child: _Empty(filter: _filter))
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
                  sliver: SliverList.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) => UiColumnWidth(
                      child: UiPanelSlice(
                        first: i == 0,
                        last: i == entries.length - 1,
                        ruleIndent: UiSpace.lg,
                        child: _Entry(entry: entries[i]),
                      ),
                    ),
                  ),
                ),
              SliverPadding(padding: EdgeInsets.only(bottom: context.bottomClearance)),
            ],
          );
        },
      ),
    );
  }
}

/// The net figure, then what goes out and what comes back (tap either to
/// show only that side), and a shortcut to items waiting over three weeks.
class _Position extends StatelessWidget {
  const _Position({required this.overview, required this.filter, required this.onDirection, required this.onLong});

  final PendingOverview overview;
  final PendingFilter filter;
  final ValueChanged<PendingDirection> onDirection;
  final VoidCallback onLong;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final o = overview;
    final net = o.net;
    final square = o.activeCount == 0;
    final active = filter.tab == PendingTab.active;
    final longOn = active && filter.ages.length == 1 && filter.ages.contains(PendingAge.long);
    final label = square
        ? 'All square'
        : (net.isNegative ? 'You owe overall' : (net.isZero ? 'Evenly balanced' : 'Coming back to you'));
    String spoken(Money m) => AmountVisibility.hiddenOf(context) ? 'an amount' : AmountText.spokenLabel(m);
    Widget side(PendingDirection d) {
      final owe = d.isOwe;
      final amount = owe ? o.toPay : o.toCollect;
      final count = owe ? o.payCount : o.collectCount;
      final name = owe ? 'To pay' : 'To collect';
      final selected = active && filter.direction == d;
      return UiStat(
        label: '$name · $count',
        dot: owe ? c.ink : c.positive,
        end: !owe,
        selected: selected,
        semanticLabel: '$name, ${spoken(amount)}, $count ${count == 1 ? 'item' : 'items'}. '
            '${selected ? 'Showing only these' : 'Show only these'}',
        value: AmountText(amount, style: t.figureSmall, decimals: DecimalDisplay.none),
        onTap: () => onDirection(d),
      );
    }

    return UiHero(
      label: label,
      value: AnimatedAmount(net.abs(), style: t.amount, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
      footer: square
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: side(PendingDirection.iOwe)),
                    const SizedBox(width: UiSpace.lg),
                    Expanded(child: side(PendingDirection.owedToMe)),
                  ],
                ),
                if (o.longCount > 0 || longOn)
                  UiChipButton(
                    key: const ValueKey('pending-attn:long'),
                    label: longOn ? 'Over 3 weeks' : '${o.longCount} over 3 weeks',
                    trailingIcon: longOn ? LucideIcons.x : null,
                    color: c.warning,
                    semanticLabel: longOn ? 'Show every item' : 'Show only items waiting over 3 weeks',
                    onTap: onLong,
                  ),
              ],
            ),
    );
  }
}

/// Current sort (when not the default) and removable filter chips.
/// Nothing at all when the list is unfiltered.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filter, required this.onChanged, required this.onSort});

  final PendingFilter filter;
  final ValueChanged<PendingFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final f = filter;
    final removable = <(String, VoidCallback)>[
      if (f.direction != null)
        (f.direction!.isOwe ? 'I owe' : 'Owed to me', () => onChanged(f.copyWith(direction: () => null))),
      for (final a in f.ages) (a.label, () => onChanged(f.copyWith(ages: {...f.ages}..remove(a)))),
      for (final k in f.kinds) (k.label, () => onChanged(f.copyWith(kinds: {...f.kinds}..remove(k)))),
    ];
    final sorted = f.sort != PendingSort.waiting;
    if (removable.isEmpty && !sorted) return const SizedBox.shrink();
    return Wrap(
      spacing: UiSpace.sm,
      children: [
        if (sorted)
          UiChipButton(
            label: f.sort.label,
            trailingIcon: LucideIcons.chevronDown,
            semanticLabel: 'Sorted by ${f.sort.label}. Change',
            onTap: onSort,
          ),
        for (final (label, remove) in removable)
          UiChipButton(label: label, trailingIcon: LucideIcons.x, semanticLabel: 'Remove filter $label', onTap: remove),
        if (removable.length > 1) UiTextButton(label: 'Clear all', onTap: () => onChanged(f.cleared())),
      ],
    );
  }
}

/// One entry of the list: a single item, a person with several items, or
/// a bill split between several people.
class _Entry extends StatelessWidget {
  const _Entry({required this.entry});

  final PendingEntry entry;

  Future<void> _quickActions(BuildContext context, PendingView v) async {
    final owe = v.payment.direction.isOwe;
    final choice = await showFinnActionMenu<int>(
      context,
      title: '${v.payment.counterparty} · ${v.payment.purpose}',
      items: [
        if (v.status.isActive)
          FinnMenuItem(value: 0, label: owe ? 'Settle · I paid' : 'Settle · I received', icon: LucideIcons.circleCheck),
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
    final e = entry;
    return switch (e) {
      PendingItemEntry(:final view) => _row(context, view),
      PendingPersonGroup() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PersonHeader(group: e),
          for (final v in e.items) ...[const UiRule(indent: 64), _row(context, v, grouped: true)],
        ],
      ),
      PendingSplitEntry() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PendingSplitHeader(
            split: e.split,
            shown: e.count,
            onTap: () => context.push(AppRoutes.pendingItem(e.items.first.payment.id)),
          ),
          for (final v in e.items) ...[const UiRule(indent: 64), _row(context, v, inSplit: true)],
        ],
      ),
    };
  }
}

/// A person with several items: their name and where the items net out.
class _PersonHeader extends StatelessWidget {
  const _PersonHeader({required this.group});

  final PendingPersonGroup group;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final g = group;
    final net = g.toCollect - g.toPay;
    return Semantics(
      header: true,
      child: UiListRow(
        key: ValueKey('person-${g.name}'),
        leading: UiInitials(name: g.name),
        title: g.name,
        subtitle: '${g.count} items',
        semanticLabel: '${g.name}, ${g.count} items',
        trailing: AmountText(
          net,
          sign: net.isZero ? SignDisplay.auto : SignDisplay.always,
          decimals: DecimalDisplay.none,
          style: t.figureSmall.copyWith(color: net.isPositive ? c.positive : null),
        ),
        onTap: null,
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
      return const UiEmpty(icon: LucideIcons.searchX, title: 'No matches', message: 'Try another name or clear the filters.');
    }
    return switch (filter.tab) {
      PendingTab.active => const UiEmpty(icon: LucideIcons.circleCheck, title: 'Nothing open', message: 'You are all square.'),
      PendingTab.settled => const UiEmpty(icon: LucideIcons.circleCheck, title: 'Nothing settled yet'),
      PendingTab.writtenOff => const UiEmpty(icon: LucideIcons.ban, title: 'Nothing written off'),
    };
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, 0),
      child: UiColumnWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiPlaceholder(width: 120, height: 12),
            SizedBox(height: UiSpace.md),
            UiPlaceholder(width: 180, height: 40),
            SizedBox(height: UiSpace.lg),
            UiPlaceholder(height: 44),
            SizedBox(height: UiSpace.section),
            UiPlaceholder(height: 260, radius: UiRadius.panel),
          ],
        ),
      ),
    );
  }
}
