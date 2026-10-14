import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../shared/presentation/luxe_async.dart';
import '../../../shared/presentation/luxe_page.dart';
import '../domain/pending_payment.dart';
import 'pending_split_ui.dart';
import 'pending_ui.dart';

/// Money owed between the user and other people. Obligations only — the
/// cash balance changes when an item is settled.
///
/// Top to bottom: the title; an obsidian card with the net position and a
/// balance scale that tips towards the heavier side (tap a pan to see only
/// that side); who has waited longest; a pinned bar with status tabs,
/// search and sort & filter; then people and bills as cards.
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  PendingFilter _filter = const PendingFilter();
  bool _searching = false;

  /// Rows that already played their entrance, so scrolling back never
  /// replays it; rows new to a filter still rise in.
  final Set<String> _entered = {};

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

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(pendingOverviewProvider);
    final o = overview.value;
    final entries = ref.watch(pendingEntriesProvider(_filter)).value ?? const <PendingEntry>[];
    final shown = entries.fold<int>(0, (n, e) => n + pendingEntryCount(e));
    return LuxeDetailPage(
      title: 'Money owed',
      storageKey: 'pending-list',
      actions: [
        LuxeIconButton(
          icon: LucideIcons.plus,
          tooltip: 'Add money owed',
          style: LuxeIconStyle.ink,
          size: 40,
          onPressed: () => context.push(AppRoutes.newPending(owedToMe: _filter.direction == PendingDirection.owedToMe)),
        ),
      ],
      slivers: [
        luxeBox(
          const Reveal(
            child: LuxePageTitle(eyebrow: 'Between people', title: 'Money owed'),
          ),
          top: 4,
          bottom: 22,
        ),
        if (o == null)
          SliverToBoxAdapter(
            child: LuxeAsync<PendingOverview>(
              value: overview,
              loading: const LuxePageSkeleton(title: false, hero: 280, rows: 3),
              errorTitle: 'Could not load money owed',
              builder: (_, _) => const SizedBox.shrink(),
            ),
          )
        else ...[
          luxeBox(
            Reveal(
              index: 1,
              scale: 0.97,
              child: _PositionCard(
                overview: o,
                selected: _filter.tab == PendingTab.active ? _filter.direction : null,
                onDirection: _toggleDirection,
              ),
            ),
          ),
          luxeBox(
            Reveal(
              index: 2,
              child: _WaitingStrip(
                overview: o,
                filter: _filter,
                onLong: _toggleLong,
                onOpen: (v) => context.push(AppRoutes.pendingItem(v.payment.id)),
              ),
            ),
            top: 18,
            bottom: 4,
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: LuxePinnedBar(
              height: 64,
              child: _Controls(
                overview: o,
                filter: _filter,
                searching: _searching,
                onTab: (t) => _set(_filter.copyWith(tab: t)),
                onSearch: (q) => _set(_filter.copyWith(query: q)),
                onSearchToggle: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _filter = _filter.copyWith(query: '');
                }),
                onOptions: _openOptions,
              ),
            ),
          ),
          luxeBox(_ActiveFilters(filter: _filter, count: shown, onChanged: _set, onSort: _openOptions), top: 4),
          if (entries.isEmpty)
            luxeBox(_Empty(filter: _filter), top: 8)
          else
            SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, i) => ResponsiveCenter(
                padding: const EdgeInsets.fromLTRB(LuxeSpace.gutter, 0, LuxeSpace.gutter, 12),
                child: _EntryCard(entry: entries[i], index: i, entered: _entered),
              ),
            ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Position card
// ---------------------------------------------------------------------------

/// The one-glance answer: who is ahead and by how much, and a scale that
/// shows it.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.overview, required this.selected, required this.onDirection});

  final PendingOverview overview;
  final PendingDirection? selected;
  final ValueChanged<PendingDirection> onDirection;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final net = o.net;
    final square = o.activeCount == 0;
    final payTone = p.isDark ? p.negative : const Color(0xFFF0A49B);
    final collectTone = p.isDark ? p.positive : const Color(0xFF9BD3B5);
    final (String verdict, Color tone) = square
        ? ('All square', p.onObsidianSoft)
        : net.isNegative
        ? ('You owe overall', payTone)
        : net.isZero
        ? ('Evenly balanced', p.onObsidianSoft)
        : ('Coming back to you', collectTone);
    return LuxeObsidian(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('NET POSITION', style: t.eyebrow.copyWith(fontSize: 10, color: p.onObsidianSoft)),
              ),
              if (!square) ...[
                Icon(LucideIcons.users, size: 13, color: p.onObsidianSoft),
                const SizedBox(width: 6),
                Text('${o.people} ${o.people == 1 ? 'person' : 'people'}', style: t.micro.c(p.onObsidianSoft)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (square)
            Text(verdict, style: t.display.copyWith(fontSize: 38, color: p.onObsidian))
          else
            LuxeAmount(net.abs(), countFromZero: true, style: t.display.copyWith(fontSize: 40, color: p.onObsidian)),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!square) ...[
                Icon(net.isNegative ? LucideIcons.arrowUpRight : LucideIcons.arrowDownLeft, size: 14, color: tone),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  square ? 'Nothing open with anyone.' : '$verdict · not in your balance',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.label.w(700).c(tone),
                ),
              ),
            ],
          ),
          if (!square) ...[
            const SizedBox(height: 10),
            _BalanceScale(
              overview: o,
              selected: selected,
              onSide: onDirection,
              payTone: payTone,
              collectTone: collectTone,
            ),
          ],
        ],
      ),
    );
  }
}

/// A balance scale: what you owe in the left pan, what comes back in the
/// right. The beam starts level and swings (with a little overshoot) until
/// it rests tipped towards the heavier side. Tap a pan, or its figure, to
/// see only that side.
class _BalanceScale extends StatelessWidget {
  const _BalanceScale({
    required this.overview,
    required this.selected,
    required this.onSide,
    required this.payTone,
    required this.collectTone,
  });

  final PendingOverview overview;
  final PendingDirection? selected;
  final ValueChanged<PendingDirection> onSide;
  final Color payTone;
  final Color collectTone;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final o = overview;
    final total = o.toPay.paise + o.toCollect.paise;
    // -1 = all to pay (left heavy), +1 = all to collect (right heavy).
    final balance = total == 0 ? 0.0 : (o.toCollect.paise - o.toPay.paise) / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'You owe ${_spoken(context, o.toPay)}, others owe you ${_spoken(context, o.toCollect)}',
          child: LayoutBuilder(
            builder: (context, box) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) {
                HapticFeedback.selectionClick();
                onSide(d.localPosition.dx < box.maxWidth / 2 ? PendingDirection.iOwe : PendingDirection.owedToMe);
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: balance),
                duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1500),
                curve: Curves.elasticOut,
                builder: (context, b, _) => CustomPaint(
                  size: Size(box.maxWidth, 88),
                  painter: _ScalePainter(
                    balance: b,
                    beam: p.gold,
                    pivot: p.onObsidian,
                    chain: p.onObsidian.withValues(alpha: 0.35),
                    pay: payTone.withValues(alpha: selected == PendingDirection.owedToMe ? 0.25 : 1),
                    collect: collectTone.withValues(alpha: selected == PendingDirection.iOwe ? 0.25 : 1),
                    payWeight: total == 0 ? 0.5 : o.toPay.paise / total,
                    collectWeight: total == 0 ? 0.5 : o.toCollect.paise / total,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _Side(
                label: 'To pay',
                amount: o.toPay,
                count: o.payCount,
                direction: PendingDirection.iOwe,
                color: payTone,
                selected: selected == PendingDirection.iOwe,
                onTap: () => onSide(PendingDirection.iOwe),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _Side(
                label: 'To collect',
                amount: o.toCollect,
                count: o.collectCount,
                direction: PendingDirection.owedToMe,
                color: collectTone,
                selected: selected == PendingDirection.owedToMe,
                end: true,
                onTap: () => onSide(PendingDirection.owedToMe),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Spoken amount for semantics that respects hidden balances.
String _spoken(BuildContext context, Money m) =>
    AmountVisibility.hiddenOf(context) ? 'an amount' : AmountText.spokenLabel(m);

class _ScalePainter extends CustomPainter {
  _ScalePainter({
    required this.balance,
    required this.beam,
    required this.pivot,
    required this.chain,
    required this.pay,
    required this.collect,
    required this.payWeight,
    required this.collectWeight,
  });

  final double balance;
  final Color beam;
  final Color pivot;
  final Color chain;
  final Color pay;
  final Color collect;
  final double payWeight;
  final double collectWeight;

  static const _maxTilt = 0.22; // radians

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    const top = 12.0;
    final half = math.min(w * 0.38, 150.0);
    final angle = -balance * _maxTilt; // heavier side goes down
    final dx = math.cos(angle) * half;
    final dy = math.sin(angle) * half;
    final left = Offset(cx - dx, top - dy);
    final right = Offset(cx + dx, top + dy);

    // Stand.
    final stand = Paint()
      ..color = pivot.withValues(alpha: 0.18)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, top), Offset(cx, size.height - 6), stand);
    canvas.drawLine(Offset(cx - 22, size.height - 6), Offset(cx + 22, size.height - 6), stand..strokeWidth = 1.4);

    // Beam.
    canvas.drawLine(
      left,
      right,
      Paint()
        ..shader = LinearGradient(colors: [beam.withValues(alpha: 0.6), beam, beam.withValues(alpha: 0.6)])
            .createShader(Rect.fromPoints(left, right))
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(cx, top), 6, Paint()..color = beam.withValues(alpha: 0.25));
    canvas.drawCircle(Offset(cx, top), 3.2, Paint()..color = pivot);

    void pan(Offset hook, Color color, double weight) {
      final drop = 36.0;
      final r = 12 + 12 * weight;
      final base = hook + Offset(0, drop);
      final cp = Paint()
        ..color = chain
        ..strokeWidth = 0.8;
      canvas.drawLine(hook, base + Offset(-r, 0), cp);
      canvas.drawLine(hook, base + Offset(r, 0), cp);
      canvas.drawCircle(hook, 2.2, Paint()..color = beam);
      final bowl = Path()
        ..moveTo(base.dx - r, base.dy)
        ..quadraticBezierTo(base.dx, base.dy + r * 0.7, base.dx + r, base.dy)
        ..close();
      canvas.drawPath(bowl, Paint()..color = color.withValues(alpha: color.a * 0.22));
      canvas.drawPath(
        bowl,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color,
      );
      // The weight sitting in the pan.
      canvas.drawCircle(base + Offset(0, -3 - 4 * weight), 3 + 5 * weight, Paint()..color = color);
    }

    pan(left, pay, payWeight);
    pan(right, collect, collectWeight);
  }

  @override
  bool shouldRepaint(_ScalePainter o) => o.balance != balance || o.pay != pay || o.collect != collect || o.beam != beam;
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.amount,
    required this.count,
    required this.direction,
    required this.color,
    required this.selected,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final Money amount;
  final int count;
  final PendingDirection direction;
  final Color color;
  final bool selected;
  final bool end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return Squish(
      onTap: onTap,
      selected: selected,
      semanticLabel:
          '$label, $count ${count == 1 ? 'item' : 'items'}. ${selected ? 'Showing only these' : 'Show only these'}',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: context.reduceMotion ? Duration.zero : LuxeDurations.quick,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? p.onObsidian.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color.withValues(alpha: 0.6) : p.onObsidian.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!end) ...[Icon(direction.icon, size: 12, color: color), const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    '${label.toUpperCase()} · $count',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.eyebrow.copyWith(fontSize: 9.5, color: color),
                  ),
                ),
                if (end) ...[const SizedBox(width: 5), Icon(direction.icon, size: 12, color: color)],
              ],
            ),
            const SizedBox(height: 4),
            LuxeAmount(
              amount,
              textAlign: end ? TextAlign.end : TextAlign.start,
              style: t.number.copyWith(fontSize: 17, color: p.onObsidian),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whom to ask (or pay) first. No deadlines exist for money between
/// people, so priority is how long each item has waited: a shortcut to
/// every item over three weeks, plus the three oldest as chips.
class _WaitingStrip extends StatelessWidget {
  const _WaitingStrip({required this.overview, required this.filter, required this.onLong, required this.onOpen});

  final PendingOverview overview;
  final PendingFilter filter;
  final VoidCallback onLong;
  final ValueChanged<PendingView> onOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final o = overview;
    final longOn = filter.tab == PendingTab.active && filter.ages.length == 1 && filter.ages.contains(PendingAge.long);
    final chips = <Widget>[
      if (o.longCount > 0)
        LuxeChip(
          key: const ValueKey('pending-attn:long'),
          icon: longOn ? LucideIcons.check : LucideIcons.hourglass,
          label: '${o.longCount} over 3 weeks',
          selected: longOn,
          semanticLabel: '${o.longCount} over 3 weeks. ${longOn ? 'Showing only these' : 'Show only these'}',
          onTap: onLong,
        ),
      for (final v in o.oldest)
        LuxeChip(
          key: ValueKey('pending-oldest:${v.payment.id}'),
          dot: v.payment.direction.tone(p),
          label: '${v.payment.counterparty.split(' ').first} · ${pendingDays(v.daysOpen)}',
          semanticLabel: pendingAgeSentence(v),
          trailing: LucideIcons.arrowUpRight,
          onTap: () => onOpen(v),
        ),
    ];
    if (chips.isEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 15, color: p.positive),
          const SizedBox(width: 8),
          Expanded(child: Text('Nothing open. Add an item when money changes hands.', style: t.caption)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 14,
              height: 1.5,
              decoration: BoxDecoration(gradient: p.goldGradient, borderRadius: BorderRadius.circular(1)),
            ),
            const SizedBox(width: 8),
            Semantics(header: true, child: Text('WAITING LONGEST', style: t.eyebrow.c(p.inkSoft))),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No deadlines — ask the oldest first',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.micro,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Reveal(index: 3 + i, offset: 0, blur: 0, scale: 0.9, child: chips[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned controls
// ---------------------------------------------------------------------------

class _Controls extends StatelessWidget {
  const _Controls({
    required this.overview,
    required this.filter,
    required this.searching,
    required this.onTab,
    required this.onSearch,
    required this.onSearchToggle,
    required this.onOptions,
  });

  final PendingOverview overview;
  final PendingFilter filter;
  final bool searching;
  final ValueChanged<PendingTab> onTab;
  final ValueChanged<String> onSearch;
  final VoidCallback onSearchToggle;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return AnimatedSwitcher(
      duration: context.reduceMotion ? Duration.zero : LuxeDurations.base,
      switchInCurve: LuxeCurves.arrive,
      switchOutCurve: LuxeCurves.leave,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: searching
          ? Row(
              key: const ValueKey('search'),
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: p.paper,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: p.lineStrong),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.search, size: 16, color: p.inkMute),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            autofocus: true,
                            onChanged: onSearch,
                            style: t.body,
                            cursorColor: p.goldInk,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              isCollapsed: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              hintText: 'Search people or purposes',
                              hintStyle: t.body.c(p.inkMute),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                LuxeIconButton(
                  icon: LucideIcons.x,
                  tooltip: 'Close search',
                  style: LuxeIconStyle.ghost,
                  size: 40,
                  onPressed: onSearchToggle,
                ),
              ],
            )
          : Row(
              key: const ValueKey('tabs'),
              children: [
                Expanded(
                  child: LuxeSegmented<PendingTab>(
                    segments: [
                      for (final tab in PendingTab.values)
                        LuxeSegment(tab, tab.label, count: overview.counts[tab] ?? 0),
                    ],
                    selected: filter.tab,
                    onChanged: onTab,
                  ),
                ),
                const SizedBox(width: 4),
                LuxeIconButton(
                  key: const ValueKey('pending-search'),
                  icon: LucideIcons.search,
                  tooltip: 'Search',
                  style: LuxeIconStyle.ghost,
                  size: 40,
                  onPressed: onSearchToggle,
                ),
                LuxeIconButton(
                  key: const ValueKey('pending-options'),
                  icon: LucideIcons.slidersHorizontal,
                  tooltip: 'Sort & filter',
                  size: 40,
                  active: filter.activeCount > 0,
                  badge: filter.activeCount,
                  onPressed: onOptions,
                ),
              ],
            ),
    );
  }
}

/// Result count, current sort and removable filter chips in one line.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filter, required this.count, required this.onChanged, required this.onSort});

  final PendingFilter filter;
  final int count;
  final ValueChanged<PendingFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final f = filter;
    final removable = <(String, VoidCallback)>[
      if (f.direction != null)
        (f.direction!.isOwe ? 'I owe' : 'Owed to me', () => onChanged(f.copyWith(direction: () => null))),
      for (final a in f.ages) (a.label, () => onChanged(f.copyWith(ages: {...f.ages}..remove(a)))),
      for (final k in f.kinds) (k.label, () => onChanged(f.copyWith(kinds: {...f.kinds}..remove(k)))),
    ];
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'ITEM' : 'ITEMS'}', style: t.eyebrow),
          const SizedBox(width: 10),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  LuxeChip(
                    icon: f.sort.icon,
                    label: f.sort.label,
                    trailing: LucideIcons.chevronDown,
                    height: 32,
                    semanticLabel: 'Sorted by ${f.sort.label}. Change',
                    onTap: onSort,
                  ),
                  for (final (label, remove) in removable) ...[
                    const SizedBox(width: 6),
                    LuxeChip(
                      label: label,
                      trailing: LucideIcons.x,
                      selected: true,
                      height: 32,
                      semanticLabel: 'Remove filter $label',
                      onTap: remove,
                    ),
                  ],
                  if (removable.length > 1)
                    LuxeLink(label: 'Clear all', icon: LucideIcons.x, onTap: () => onChanged(f.cleared())),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

/// One card in the list: a single item, a person with several items, or a
/// bill split between several people.
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.index, required this.entered});

  final PendingEntry entry;
  final int index;
  final Set<String> entered;

  Future<void> _quickActions(BuildContext context, PendingView v) async {
    final owe = v.payment.direction.isOwe;
    final choice = await showLuxeMenu<int>(
      context,
      title: v.payment.purpose,
      eyebrow: v.payment.counterparty,
      items: [
        if (v.status.isActive)
          LuxeMenuItem(value: 0, label: owe ? 'Settle · I paid' : 'Settle · I received', icon: LucideIcons.circleCheck),
        const LuxeMenuItem(value: 1, label: 'Open details', icon: LucideIcons.arrowUpRight),
        if (v.status.isActive && !owe)
          const LuxeMenuItem(value: 2, label: 'Send a reminder', icon: LucideIcons.send, hint: 'A polite nudge'),
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
    final p = context.luxe;
    final e = entry;
    final id = switch (e) {
      PendingItemEntry(:final view) => view.payment.id,
      PendingPersonGroup(:final name) => 'person-$name',
      PendingSplitEntry(:final split) => 'split-${split.split.id}',
    };
    final Widget body = switch (e) {
      PendingItemEntry(:final view) => _row(context, view),
      PendingPersonGroup() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _GroupHeader(group: e),
          for (final v in e.items) ...[const LuxeHairline(indent: 62), _row(context, v, grouped: true)],
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
          for (final v in e.items) ...[const LuxeHairline(indent: 64), _row(context, v, inSplit: true)],
        ],
      ),
    };
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: p.paper,
        borderRadius: BorderRadius.circular(LuxeSpace.rTile + 2),
        border: Border.all(color: p.line),
        boxShadow: p.lift,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(LuxeSpace.rTile + 2), child: body),
    );
    final first = entered.add(id);
    if (!first || index > 10) return card;
    return Reveal(index: index, child: card);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final PendingPersonGroup group;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final g = group;
    final net = g.toCollect - g.toPay;
    final tone = net.isNegative ? p.negative : (net.isPositive ? p.positive : p.inkMute);
    return Semantics(
      header: true,
      label: '${g.name}, ${g.count} separate items',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('person-${g.name}'),
        color: p.canvas.withValues(alpha: 0.5),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Row(
          children: [
            PendingAvatar(name: g.name, color: tone, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.heading.copyWith(fontSize: 15)),
                  Text('${g.count} separate items', style: t.caption),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                LuxeAmount(net.abs(), fit: false, style: t.number.copyWith(color: tone)),
                Text(
                  net.isNegative ? 'you owe in total' : (net.isPositive ? 'owes you in total' : 'evens out'),
                  style: t.micro,
                ),
              ],
            ),
          ],
        ),
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
      return const LuxeEmpty(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'Try a different name or clear the filters.',
      );
    }
    return switch (filter.tab) {
      PendingTab.active => LuxeEmpty(
        icon: LucideIcons.handshake,
        title: 'All square',
        message:
            'Track money you owe or are owed — a shared bill, a loan to a friend, a reimbursement. '
            'Your balance changes only when you settle.',
        actionLabel: 'Add money owed',
        actionIcon: LucideIcons.plus,
        onAction: () => context.push(AppRoutes.newPending()),
      ),
      PendingTab.settled => const LuxeEmpty(
        icon: LucideIcons.circleCheck,
        title: 'Nothing settled yet',
        message: 'Items you settle in full appear here with their history.',
      ),
      PendingTab.writtenOff => const LuxeEmpty(
        icon: LucideIcons.ban,
        title: 'Nothing written off',
        message: 'Items you no longer expect to be paid appear here.',
      ),
    };
  }
}
