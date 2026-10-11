import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Money owed between the user and other people. Obligations only — the
/// cash balance changes when an item is settled.
///
/// Layout, top to bottom: one position card (net figure, a balance beam of
/// what goes out vs. what comes back, and tappable "needs attention"
/// shortcuts), a pinned bar with status tabs, search and sort & filter,
/// then compact two-line rows grouped by person.
class PendingScreen extends ConsumerStatefulWidget {
  const PendingScreen({super.key});

  @override
  ConsumerState<PendingScreen> createState() => _PendingScreenState();
}

class _PendingScreenState extends ConsumerState<PendingScreen> {
  PendingFilter _filter = const PendingFilter();
  bool _searching = false;

  /// Rows that already played their entrance, so scrolling back never
  /// replays it; rows new to a filter still slide in.
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Money owed'),
        actions: [
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add money owed',
            variant: FinnIconButtonVariant.filled,
            onPressed: () => context.push(AppRoutes.newPending(owedToMe: _filter.direction == PendingDirection.owedToMe)),
          ),
          const SizedBox(width: Space.x3),
        ],
      ),
      body: AsyncView<PendingOverview>(
        value: overview,
        loading: const _PendingSkeleton(),
        builder: (context, o) {
          final entries = ref.watch(pendingEntriesProvider(_filter)).value ?? const <PendingEntry>[];
          final shown = entries.fold<int>(0, (n, e) => n + (e is PendingPersonGroup ? e.count : 1));
          return CustomScrollView(
            key: const PageStorageKey('pending-list'),
            slivers: [
              _boxed(
                Padding(
                  padding: const EdgeInsets.only(top: Space.x1, bottom: Space.x3),
                  child: StaggeredEntrance(
                    child: _PositionCard(
                      overview: o,
                      filter: _filter,
                      onDirection: _toggleDirection,
                      onLong: _toggleLong,
                      onOpen: (v) => context.push(AppRoutes.pendingItem(v.payment.id)),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _ControlsDelegate(
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
              _boxed(
                _ActiveFilters(
                  filter: _filter,
                  count: shown,
                  onChanged: _set,
                  onSort: _openOptions,
                ),
              ),
              if (entries.isEmpty)
                _boxed(Padding(padding: const EdgeInsets.only(top: Space.x4), child: _Empty(filter: _filter)))
              else
                SliverList.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, i) => ResponsiveCenter(
                    padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
                    child: _EntryCard(entry: entries[i], index: i, entered: _entered),
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

Widget _boxed(Widget child) => SliverToBoxAdapter(
      child: ResponsiveCenter(padding: const EdgeInsets.symmetric(horizontal: Space.gutter), child: child),
    );

// ---------------------------------------------------------------------------
// Position card
// ---------------------------------------------------------------------------

/// The one-glance answer: who is ahead, by how much, and what needs action.
class _PositionCard extends StatelessWidget {
  const _PositionCard({
    required this.overview,
    required this.filter,
    required this.onDirection,
    required this.onLong,
    required this.onOpen,
  });

  final PendingOverview overview;
  final PendingFilter filter;
  final ValueChanged<PendingDirection> onDirection;
  final VoidCallback onLong;
  final ValueChanged<PendingView> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    final net = o.net;
    final square = o.activeCount == 0;
    final (String verdict, Color tone) = square
        ? ('All square', c.textSecondary)
        : net.isNegative
            ? ('You owe overall', c.negative)
            : net.isZero
                ? ('Evenly balanced', c.textSecondary)
                : ('Coming back to you', c.positive);
    final active = filter.tab == PendingTab.active;
    return FinnCard(
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
      radius: Radii.xxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('NET POSITION', style: t.eyebrow)),
              if (!square) ...[
                Icon(LucideIcons.users, size: 13, color: c.textTertiary),
                const SizedBox(width: Space.x1),
                Text('${o.people} ${o.people == 1 ? 'person' : 'people'}', style: t.micro),
              ],
            ],
          ),
          const SizedBox(height: Space.x1),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: square
                    ? Text(verdict, style: t.title)
                    : AnimatedAmount(
                        net.abs(),
                        animateOnMount: true,
                        fit: true,
                        style: t.amountLarge.copyWith(color: tone),
                      ),
              ),
              if (!square) ...[
                const SizedBox(width: Space.x2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(verdict, style: t.caption.copyWith(color: tone, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text('Not part of your balance until settled.', style: t.micro),
          if (!square) ...[
            const SizedBox(height: Space.x3),
            _BalanceBeam(overview: o, selected: active ? filter.direction : null, onSide: onDirection),
          ],
          const SizedBox(height: Space.x3),
          const FinnDivider(),
          const SizedBox(height: Space.x2_5),
          _WaitingStrip(overview: o, filter: filter, onLong: onLong, onOpen: onOpen),
        ],
      ),
    );
  }
}

/// Two-sided bar: what you owe on the left, what comes back on the right.
/// The knob settles where the two meet like a balance finding its level;
/// hatched ends are the part waiting over three weeks. Tap a side (or its
/// legend) to show only that direction.
class _BalanceBeam extends StatelessWidget {
  const _BalanceBeam({required this.overview, required this.selected, required this.onSide});

  final PendingOverview overview;
  final PendingDirection? selected;
  final ValueChanged<PendingDirection> onSide;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = overview;
    final total = o.toPay.paise + o.toCollect.paise;
    final split = total == 0 ? 0.5 : o.toPay.paise / total;
    double share(Money part, Money whole) => whole.isPositive ? (part.paise / whole.paise).clamp(0.0, 1.0) : 0;
    final dimPay = selected == PendingDirection.owedToMe;
    final dimCollect = selected == PendingDirection.iOwe;
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
                onSide(d.localPosition.dx < box.maxWidth * split ? PendingDirection.iOwe : PendingDirection.owedToMe);
              },
              child: TweenAnimationBuilder<double>(
                // Starts level, then tips toward the heavier side.
                tween: Tween(begin: 0.5, end: split),
                duration: context.reduceMotion ? Duration.zero : const Duration(milliseconds: 1100),
                curve: Curves.elasticOut,
                builder: (context, s, _) => CustomPaint(
                  size: Size(box.maxWidth, 26),
                  painter: _BeamPainter(
                    split: s.clamp(0.0, 1.0),
                    payLong: share(o.longToPay, o.toPay),
                    collectLong: share(o.longToCollect, o.toCollect),
                    pay: c.negative.withValues(alpha: dimPay ? 0.22 : 1),
                    collect: c.positive.withValues(alpha: dimCollect ? 0.22 : 1),
                    knob: c.surface,
                    knobBorder: c.textPrimary,
                    showKnob: o.toPay.isPositive && o.toCollect.isPositive,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.x1),
        Row(
          children: [
            Expanded(
              child: _BeamLegend(
                label: 'To pay',
                amount: o.toPay,
                count: o.payCount,
                direction: PendingDirection.iOwe,
                selected: selected == PendingDirection.iOwe,
                onTap: () => onSide(PendingDirection.iOwe),
              ),
            ),
            const SizedBox(width: Space.x2),
            Expanded(
              child: _BeamLegend(
                label: 'To collect',
                amount: o.toCollect,
                count: o.collectCount,
                direction: PendingDirection.owedToMe,
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

class _BeamLegend extends StatelessWidget {
  const _BeamLegend({
    required this.label,
    required this.amount,
    required this.count,
    required this.direction,
    required this.selected,
    required this.onTap,
    this.end = false,
  });

  final String label;
  final Money amount;
  final int count;
  final PendingDirection direction;
  final bool selected;
  final bool end;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final color = direction.color(c);
    final align = end ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label, $count ${count == 1 ? 'item' : 'items'}. ${selected ? 'Showing only these' : 'Show only these'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.rMd,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: context.motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: Space.x1_5, vertical: Space.x1),
          decoration: BoxDecoration(
            color: selected ? direction.soft(c) : Colors.transparent,
            borderRadius: Radii.rMd,
          ),
          child: Column(
            crossAxisAlignment: align,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!end) ...[Icon(direction.icon, size: 12, color: color), const SizedBox(width: 3)],
                  Flexible(
                    child: Text(
                      '${label.toUpperCase()} · $count',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.micro.copyWith(color: color, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                    ),
                  ),
                  if (end) ...[const SizedBox(width: 3), Icon(direction.icon, size: 12, color: color)],
                ],
              ),
              AmountText(amount, style: t.amountSmall, fit: true, textAlign: end ? TextAlign.end : TextAlign.start),
            ],
          ),
        ),
      ),
    );
  }
}

class _BeamPainter extends CustomPainter {
  const _BeamPainter({
    required this.split,
    required this.payLong,
    required this.collectLong,
    required this.pay,
    required this.collect,
    required this.knob,
    required this.knobBorder,
    required this.showKnob,
  });

  /// Share of the bar that is money the user owes (0..1).
  final double split;

  /// Part of each side waiting over three weeks (0..1 of that side).
  final double payLong;
  final double collectLong;
  final Color pay;
  final Color collect;
  final Color knob;
  final Color knobBorder;
  final bool showKnob;

  static const _bar = 12.0;
  static const _gap = 3.0;

  void _side(Canvas canvas, Rect rect, Color color, double long, {required bool fromLeft}) {
    if (rect.width <= 0) return;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(_bar / 2));
    canvas.drawRRect(rrect, Paint()..color = color);
    if (long <= 0) return;
    // Hatch the long-waiting part at the outer end of the side.
    final w = rect.width * long;
    final hatch = fromLeft
        ? Rect.fromLTWH(rect.left, rect.top, w, rect.height)
        : Rect.fromLTWH(rect.right - w, rect.top, w, rect.height);
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.clipRect(hatch);
    final stripe = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    for (var x = hatch.left - rect.height; x < hatch.right; x += 6) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), stripe);
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - _bar) / 2;
    final w = size.width;
    final at = w * split;
    final gap = showKnob ? _gap : 0.0;
    _side(canvas, Rect.fromLTRB(0, top, (at - gap).clamp(0, w), top + _bar), pay, payLong, fromLeft: true);
    _side(canvas, Rect.fromLTRB((at + gap).clamp(0, w), top, w, top + _bar), collect, collectLong, fromLeft: false);
    if (!showKnob) return;
    const r = 9.0;
    final center = Offset(at.clamp(r, w - r), size.height / 2);
    canvas.drawCircle(center.translate(0, 1.5), r, Paint()..color = Colors.black.withValues(alpha: 0.18));
    canvas.drawCircle(center, r, Paint()..color = knob);
    canvas.drawCircle(
      center,
      r - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = knobBorder,
    );
    canvas.drawCircle(center, 2.5, Paint()..color = knobBorder);
  }

  @override
  bool shouldRepaint(_BeamPainter old) =>
      old.split != split ||
      old.payLong != payLong ||
      old.collectLong != collectLong ||
      old.pay != pay ||
      old.collect != collect ||
      old.knob != knob ||
      old.knobBorder != knobBorder ||
      old.showKnob != showKnob;
}

/// Whom to ask (or pay) first. No deadlines exist for money between
/// people, so priority is simply how long each item has waited: the three
/// oldest open items as chips (tap = open it), plus a shortcut that shows
/// every item waiting over three weeks.
class _WaitingStrip extends StatelessWidget {
  const _WaitingStrip({required this.overview, required this.filter, required this.onLong, required this.onOpen});

  final PendingOverview overview;
  final PendingFilter filter;
  final VoidCallback onLong;
  final ValueChanged<PendingView> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final o = overview;
    final chips = <Widget>[
      if (o.longCount > 0)
        _AttentionChip(
          key: const ValueKey('pending-attn:long'),
          icon: LucideIcons.hourglass,
          label: '${o.longCount} over 3 weeks',
          color: c.warning,
          selected: filter.tab == PendingTab.active && filter.ages.length == 1 && filter.ages.contains(PendingAge.long),
          onTap: onLong,
        ),
      for (final v in o.oldest)
        _AttentionChip(
          key: ValueKey('pending-oldest:${v.payment.id}'),
          icon: v.payment.direction.icon,
          label: '${v.payment.counterparty.split(' ').first} · ${pendingDays(v.daysOpen)}',
          semantics: pendingAgeSentence(v),
          color: v.payment.direction.color(c),
          selected: false,
          onTap: () => onOpen(v),
        ),
    ];
    if (chips.isEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.circleCheck, size: 14, color: c.positive),
          const SizedBox(width: Space.x1_5),
          Expanded(
            child: Text('Nothing open. Add an item when money changes hands.', style: t.caption),
          ),
        ],
      );
    }
    final scroller = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: Space.x2),
            chips[i].maybeAnimate(
              context,
              (a) => a
                  .fadeIn(delay: 250.ms + 70.ms * i, duration: 300.ms)
                  .slideX(begin: 0.25, end: 0, delay: 250.ms + 70.ms * i, duration: 420.ms, curve: Curves.easeOutCubic),
            ),
          ],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('WAITING LONGEST', style: t.eyebrow),
            const SizedBox(width: Space.x1_5),
            Expanded(
              child: Text('No deadlines — ask the oldest first',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro),
            ),
          ],
        ),
        const SizedBox(height: Space.x2),
        scroller,
      ],
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
    this.semantics,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  /// Spoken label for chips that open an item instead of filtering.
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = selected ? c.onSolid : color;
    return Semantics(
      button: true,
      selected: selected,
      label: semantics ?? '$label. ${selected ? 'Showing only these' : 'Show only these'}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.rFull,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: context.motion.fast,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2_5),
            decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: c.isDark ? 0.18 : 0.1),
              borderRadius: Radii.rFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? LucideIcons.check : icon, size: 13, color: fg),
                const SizedBox(width: Space.x1_5),
                Text(label, style: context.text.label.copyWith(color: fg, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pinned controls
// ---------------------------------------------------------------------------

class _ControlsDelegate extends SliverPersistentHeaderDelegate {
  const _ControlsDelegate({required this.child});

  final Widget child;

  static const _height = 56.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: overlapsContent ? Border(bottom: BorderSide(color: c.border)) : null,
      ),
      child: ResponsiveCenter(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter, vertical: Space.x2),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(_ControlsDelegate old) => old.child != child;
}

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
    final c = context.colors;
    return AnimatedSwitcher(
      duration: context.motion.normal,
      switchInCurve: Curves2.emphasized,
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
                  child: SizedBox(
                    height: 40,
                    child: FinnSearchField(
                      hint: 'Search people or purposes',
                      autofocus: true,
                      onChanged: onSearch,
                    ),
                  ),
                ),
                const SizedBox(width: Space.x1),
                FinnIconButton(icon: LucideIcons.x, tooltip: 'Close search', onPressed: onSearchToggle),
              ],
            )
          : Row(
              key: const ValueKey('tabs'),
              children: [
                Expanded(
                  child: _StatusTabs(selected: filter.tab, counts: overview.counts, onChanged: onTab),
                ),
                const SizedBox(width: Space.x1),
                FinnIconButton(
                  key: const ValueKey('pending-search'),
                  icon: LucideIcons.search,
                  tooltip: 'Search',
                  onPressed: onSearchToggle,
                ),
                CountBadge(
                  count: filter.activeCount,
                  color: c.primary,
                  semanticsLabel: '${filter.activeCount} filters on',
                  child: FinnIconButton(
                    key: const ValueKey('pending-options'),
                    icon: LucideIcons.slidersHorizontal,
                    tooltip: 'Sort & filter',
                    variant: filter.activeCount > 0 ? FinnIconButtonVariant.filled : FinnIconButtonVariant.ghost,
                    onPressed: onOptions,
                  ),
                ),
              ],
            ),
    );
  }
}

/// Compact sliding tabs: sentence-case labels with counts that scale down
/// instead of clipping on narrow screens.
class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.selected, required this.counts, required this.onChanged});

  final PendingTab selected;
  final Map<PendingTab, int> counts;
  final ValueChanged<PendingTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    const tabs = PendingTab.values;
    final index = tabs.indexOf(selected);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: Radii.rFull),
      child: Stack(
        children: [
          AnimatedAlign(
            alignment: Alignment(-1 + 2 * index / (tabs.length - 1), 0),
            duration: context.motion.normal,
            curve: Curves2.emphasized,
            child: FractionallySizedBox(
              widthFactor: 1 / tabs.length,
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
              for (final tab in tabs)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: tab == selected,
                    inMutuallyExclusiveGroup: true,
                    label: '${tab.label}, ${counts[tab] ?? 0}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (tab == selected) return;
                        HapticFeedback.selectionClick();
                        onChanged(tab);
                      },
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Space.x1_5),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text.rich(
                              TextSpan(children: [
                                TextSpan(text: tab.label),
                                TextSpan(
                                  text: ' ${counts[tab] ?? 0}',
                                  style: TextStyle(
                                    color: tab == selected ? c.primary : c.textTertiary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ]),
                              maxLines: 1,
                              style: t.label.copyWith(
                                color: tab == selected ? c.textPrimary : c.textSecondary,
                                fontWeight: tab == selected ? FontWeight.w800 : FontWeight.w600,
                              ),
                            ),
                          ),
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

/// Result count, current sort and removable filter chips in one line.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.filter, required this.count, required this.onChanged, required this.onSort});

  final PendingFilter filter;
  final int count;
  final ValueChanged<PendingFilter> onChanged;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final f = filter;
    final removable = <(String, VoidCallback)>[
      if (f.direction != null) (f.direction!.isOwe ? 'I owe' : 'Owed to me', () => onChanged(f.copyWith(direction: () => null))),
      for (final a in f.ages) (a.label, () => onChanged(f.copyWith(ages: {...f.ages}..remove(a)))),
      for (final k in f.kinds) (k.label, () => onChanged(f.copyWith(kinds: {...f.kinds}..remove(k)))),
    ];
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Text('$count ${count == 1 ? 'ITEM' : 'ITEMS'}', style: t.eyebrow),
          const SizedBox(width: Space.x2),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SmallChip(
                    icon: f.sort.icon,
                    label: f.sort.label,
                    trailing: LucideIcons.chevronDown,
                    onTap: onSort,
                    semantics: 'Sorted by ${f.sort.label}. Change',
                  ),
                  for (final (label, remove) in removable) ...[
                    const SizedBox(width: Space.x1_5),
                    _SmallChip(
                      label: label,
                      trailing: LucideIcons.x,
                      color: c.primary,
                      onTap: remove,
                      semantics: 'Remove filter $label',
                    ),
                  ],
                  if (removable.length > 1) ...[
                    const SizedBox(width: Space.x1),
                    TextButton(
                      onPressed: () => onChanged(f.cleared()),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                        textStyle: t.label.copyWith(fontWeight: FontWeight.w800),
                      ),
                      child: const Text('Clear all'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({
    required this.label,
    required this.onTap,
    required this.semantics,
    this.icon,
    this.trailing,
    this.color,
  });

  final String label;
  final IconData? icon;
  final IconData? trailing;
  final Color? color;
  final VoidCallback onTap;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? c.textSecondary;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: Radii.rFull,
          onTap: onTap,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: Space.x2_5),
            decoration: BoxDecoration(
              color: color == null ? c.surfaceMuted : color!.withValues(alpha: c.isDark ? 0.2 : 0.1),
              borderRadius: Radii.rFull,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: Space.x1)],
                Text(label, style: context.text.micro.copyWith(color: fg, fontWeight: FontWeight.w800)),
                if (trailing != null) ...[const SizedBox(width: 3), Icon(trailing, size: 12, color: fg)],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// List
// ---------------------------------------------------------------------------

/// One card in the list: a single item, or a person with several items.
class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry, required this.index, required this.entered});

  final PendingEntry entry;
  final int index;
  final Set<String> entered;

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

  Widget _row(BuildContext context, PendingView v, {bool grouped = false}) => KeyedSubtree(
        key: ValueKey(v.payment.id),
        child: PendingRow(
          view: v,
          grouped: grouped,
          onTap: () => context.push(AppRoutes.pendingItem(v.payment.id)),
          onSettle: () => context.push(AppRoutes.settlePending(v.payment.id)),
          onLongPress: () => _quickActions(context, v),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final e = entry;
    final id = switch (e) {
      PendingItemEntry(:final view) => view.payment.id,
      PendingPersonGroup(:final name) => 'person-$name',
    };
    final Widget body = switch (e) {
      PendingItemEntry(:final view) => _row(context, view),
      PendingPersonGroup() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _GroupHeader(group: e),
            for (final v in e.items) ...[
              const FinnDivider(indent: Space.x3 + 30 + Space.x3),
              _row(context, v, grouped: true),
            ],
          ],
        ),
    };
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.rXl,
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(borderRadius: Radii.rXl, child: body),
    );

    final first = entered.add(id);
    if (!first || index > 10) return card;
    final delay = 40.ms * index;
    return card.maybeAnimate(
      context,
      (a) => a
          .fadeIn(delay: delay, duration: 260.ms)
          .slideY(begin: 0.18, end: 0, delay: delay, duration: 380.ms, curve: Curves.easeOutCubic),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final PendingPersonGroup group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final g = group;
    final net = g.toCollect - g.toPay;
    final tone = net.isNegative ? c.negative : (net.isPositive ? c.positive : c.textSecondary);
    return Semantics(
      header: true,
      label: '${g.name}, ${g.count} separate items',
      excludeSemantics: true,
      child: Padding(
        key: ValueKey('person-${g.name}'),
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2_5),
        child: Row(
          children: [
            PendingAvatar(name: g.name, color: tone),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                  Text('${g.count} separate items', style: t.caption),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AmountText(net.abs(), style: t.amountSmall.copyWith(color: tone)),
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
      return const EmptyState(
        icon: LucideIcons.searchX,
        title: 'No matches',
        message: 'Try a different name or clear the filters.',
      );
    }
    return switch (filter.tab) {
      PendingTab.active => EmptyState(
          icon: LucideIcons.handshake,
          title: 'All square',
          message: 'Track money you owe or are owed — a shared bill, a loan to a friend, a reimbursement. '
              'Your balance changes only when you settle.',
          actionLabel: 'Add money owed',
          actionIcon: LucideIcons.plus,
          onAction: () => context.push(AppRoutes.newPending()),
        ),
      PendingTab.settled => const EmptyState(
          icon: LucideIcons.circleCheck,
          title: 'Nothing settled yet',
          message: 'Items you settle in full appear here with their history.',
        ),
      PendingTab.writtenOff => const EmptyState(
          icon: LucideIcons.ban,
          title: 'Nothing written off',
          message: 'Items you no longer expect to be paid appear here.',
        ),
    };
  }
}

class _PendingSkeleton extends StatelessWidget {
  const _PendingSkeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardSkeleton(height: 188, radius: Radii.xxl),
              SizedBox(height: Space.x3),
              SkeletonBox(height: 40, radius: Radii.full),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 64),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 64),
              SizedBox(height: Space.x2),
              CardSkeleton(height: 64),
            ],
          ),
        ),
      );
}
