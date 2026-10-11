import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';

/// "Available to spend" hero: one number, and a bar that is your cash with
/// the set-aside part hatched out, so the gap between the two reads at a
/// glance. Tap the bar to split set-aside money into goals and emergencies;
/// tap anywhere else for the full maths.
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<BalanceSnapshot>(
      value: ref.watch(balanceProvider),
      loading: const SkeletonPulse(child: CardSkeleton(height: 168, radius: Radii.xxxl)),
      builder: (context, b) => _HeroContent(balance: b),
    );
  }
}

/// Shares of the bar, each 0..1. The bar is cash; when more is set aside
/// than there is cash, the set-aside parts fill it and [over] is true.
@immutable
class _Shares {
  const _Shares({required this.free, required this.goals, required this.emergency, required this.over});

  factory _Shares.of(BalanceSnapshot b) {
    final over = b.available.isNegative;
    final base = over ? b.earmarked.paise : b.cash.paise;
    if (base <= 0) return const _Shares(free: 0, goals: 0, emergency: 0, over: false);
    double share(int paise) => (paise / base).clamp(0.0, 1.0);
    return _Shares(
      free: over ? 0 : share(b.available.paise),
      goals: share(b.earmarkedGoals.paise),
      emergency: share(b.earmarkedEmergency.paise),
      over: over,
    );
  }

  final double free;
  final double goals;
  final double emergency;
  final bool over;

  static _Shares lerp(_Shares a, _Shares b, double t) => _Shares(
        free: a.free + (b.free - a.free) * t,
        goals: a.goals + (b.goals - a.goals) * t,
        emergency: a.emergency + (b.emergency - a.emergency) * t,
        over: t < 0.5 ? a.over : b.over,
      );

  /// "11%", "<1%" for a sliver, "0%".
  String get freeLabel {
    final pct = free * 100;
    if (pct > 0 && pct < 1) return '<1%';
    return '${pct.round()}%';
  }

  @override
  bool operator ==(Object other) =>
      other is _Shares &&
      other.free == free &&
      other.goals == goals &&
      other.emergency == emergency &&
      other.over == over;

  @override
  int get hashCode => Object.hash(free, goals, emergency, over);
}

class _SharesTween extends Tween<_Shares> {
  _SharesTween({required _Shares super.end}) : super(begin: end);

  @override
  _Shares lerp(double t) => _Shares.lerp(begin!, end!, t);
}

class _HeroContent extends StatefulWidget {
  const _HeroContent({required this.balance});

  final BalanceSnapshot balance;

  @override
  State<_HeroContent> createState() => _HeroContentState();
}

class _HeroContentState extends State<_HeroContent> {
  bool _split = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _split = !_split);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final b = widget.balance;
    final shares = _Shares.of(b);
    final hidden = AmountVisibility.hiddenOf(context);
    const soft = Colors.white70;
    return GradientHeroCard(
      watermark: LucideIcons.wallet,
      padding: const EdgeInsets.fromLTRB(Space.x5, Space.x4, Space.x5, Space.x4),
      semanticLabel: 'Available to spend. Double tap for the full breakdown.',
      onTap: () => showFinnSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: b)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('AVAILABLE TO SPEND', style: t.eyebrow.copyWith(color: soft)),
              ),
              const Icon(LucideIcons.info, size: 16, color: soft),
            ],
          ),
          const SizedBox(height: Space.x1),
          Row(
            children: [
              Expanded(
                child: AnimatedAmount(
                  b.available,
                  style: t.amountHero.copyWith(color: Colors.white),
                  decimals: DecimalDisplay.none,
                  fit: true,
                  animateOnMount: true,
                ),
              ),
              if (!hidden && (b.cash.isPositive || shares.over)) ...[
                const SizedBox(width: Space.x3),
                _FreeChip(shares: shares),
              ],
            ],
          ),
          const SizedBox(height: Space.x3),
          _AllocationPanel(balance: b, shares: shares, split: _split, onToggle: _toggle),
        ],
      ),
    );
  }
}

/// "11% free", or a warning when set-aside money exceeds cash.
class _FreeChip extends StatelessWidget {
  const _FreeChip({required this.shares});

  final _Shares shares;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final over = shares.over;
    final fg = over ? c.warning : Colors.white;
    return Semantics(
      label: over ? 'More is set aside than you have in cash' : '${shares.freeLabel} of your cash is free to spend',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x1),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: over ? 0.18 : 0.1),
          borderRadius: Radii.rFull,
          border: Border.all(color: fg.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(over ? LucideIcons.triangleAlert : LucideIcons.sparkles, size: 12, color: fg),
            const SizedBox(width: Space.x1),
            Text(
              over ? 'Over-committed' : '${shares.freeLabel} of cash',
              style: t.micro.copyWith(color: fg, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

/// The cash bar plus its legend. Tapping toggles the goals / emergency split.
class _AllocationPanel extends StatelessWidget {
  const _AllocationPanel({required this.balance, required this.shares, required this.split, required this.onToggle});

  final BalanceSnapshot balance;
  final _Shares shares;
  final bool split;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final motion = context.motion;
    final legend = split
        ? Row(
            key: const ValueKey('split'),
            children: [
              Expanded(
                child: _HeroStat(label: 'For goals', amount: balance.earmarkedGoals, dot: c.accentGoals),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: _HeroStat(
                  label: 'Emergency fund',
                  amount: balance.earmarkedEmergency,
                  dot: c.accentEmergency,
                  end: true,
                  expanded: true,
                ),
              ),
            ],
          )
        : Row(
            key: const ValueKey('cash'),
            children: [
              Expanded(
                child: _HeroStat(label: 'Cash · bank & wallet', amount: balance.cash),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: _HeroStat(label: 'Set aside', amount: balance.earmarked, icon: LucideIcons.lock, end: true),
              ),
            ],
          );
    return Semantics(
      button: true,
      toggled: split,
      label: 'Split set-aside money into goals and emergencies',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.only(top: Space.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TweenAnimationBuilder<_Shares>(
                tween: _SharesTween(end: shares),
                duration: motion.slow,
                curve: motion.standard,
                builder: (context, s, _) => _AllocationBar(shares: s, split: split),
              ),
              const SizedBox(height: Space.x2_5),
              AnimatedSwitcher(
                duration: motion.normal,
                switchInCurve: motion.standard,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: legend,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whole width = cash. Bright part = free to spend; hatched part = set
/// aside (locked). Sweeps in once, then a single highlight crosses the free
/// part. In split mode the hatched part separates into goals / emergency.
class _AllocationBar extends StatefulWidget {
  const _AllocationBar({required this.shares, required this.split});

  final _Shares shares;
  final bool split;

  @override
  State<_AllocationBar> createState() => _AllocationBarState();
}

class _AllocationBarState extends State<_AllocationBar> with TickerProviderStateMixin {
  // Sweep-in then one highlight pass, both on [_intro]. Finite, so
  // pumpAndSettle and battery are unaffected.
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _split = AnimationController(vsync: this, value: widget.split ? 1 : 0);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final m = context.motion;
    _split.duration = m.slow;
    if (!_started) {
      _started = true;
      if (m.reduced) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    } else if (m.reduced) {
      _intro.value = 1;
    }
  }

  @override
  void didUpdateWidget(_AllocationBar old) {
    super.didUpdateWidget(old);
    if (old.split != widget.split) {
      _split.animateTo(widget.split ? 1 : 0, curve: Curves2.emphasized);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _split.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return RepaintBoundary(
      child: SizedBox(
        height: 12,
        width: double.infinity,
        child: CustomPaint(
          painter: _AllocationPainter(
            intro: _intro,
            split: _split,
            shares: widget.shares,
            free: c.positive,
            goals: c.accentGoals,
            emergency: c.accentEmergency,
            warning: c.warning,
          ),
        ),
      ),
    );
  }
}

class _AllocationPainter extends CustomPainter {
  _AllocationPainter({
    required this.intro,
    required this.split,
    required this.shares,
    required this.free,
    required this.goals,
    required this.emergency,
    required this.warning,
  }) : super(repaint: Listenable.merge([intro, split]));

  final Animation<double> intro;
  final Animation<double> split;
  final _Shares shares;
  final Color free;
  final Color goals;
  final Color emergency;
  final Color warning;

  static const _sweep = Interval(0, 0.6, curve: Curves2.emphasized);
  static const _shine = Interval(0.55, 1, curve: Curves.easeInOut);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final track = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(h / 2));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.1));

    final reveal = _sweep.transform(intro.value);
    if (reveal <= 0) return;
    canvas.save();
    canvas.clipRRect(track);
    canvas.clipRect(Rect.fromLTWH(0, 0, w * reveal, h));

    final s = split.value;
    final gap = 2.0 * s;
    final freeW = shares.free * w;

    if (freeW > 0) {
      final rect = Rect.fromLTWH(0, 0, freeW, h);
      canvas.drawRect(
        rect,
        Paint()..shader = LinearGradient(colors: [Color.lerp(free, Colors.white, 0.35)!, free]).createShader(rect),
      );
    }

    // Set-aside money: hatched (locked) as one block, coloured by purpose
    // once split.
    final locked = shares.over ? warning.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.2);
    var x = freeW + (freeW > 0 ? gap : 0);
    for (final (share, color) in [(shares.goals, goals), (shares.emergency, emergency)]) {
      final width = share * w;
      if (width <= 0) continue;
      final rect = Rect.fromLTWH(x, 0, math.max(0, width - gap), h);
      canvas.drawRect(rect, Paint()..color = Color.lerp(locked, color, s)!);
      _hatch(canvas, rect, Colors.white.withValues(alpha: 0.16 * (1 - s)));
      x += width;
    }

    final shine = _shine.transform(intro.value);
    if (freeW > 0 && shine > 0 && shine < 1) {
      final band = h * 4;
      final cx = -band + (freeW + band * 2) * shine;
      final rect = Rect.fromLTWH(cx - band, 0, band * 2, h);
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, freeW, h));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.55),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
      canvas.restore();
    }
    canvas.restore();
  }

  void _hatch(Canvas canvas, Rect rect, Color color) {
    if (color.a <= 0.01) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2;
    canvas.save();
    canvas.clipRect(rect);
    for (var x = rect.left - rect.height; x < rect.right; x += 6) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + rect.height, rect.top), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_AllocationPainter old) =>
      old.shares != shares ||
      old.free != free ||
      old.goals != goals ||
      old.emergency != emergency ||
      old.warning != warning;
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.amount,
    this.icon,
    this.dot,
    this.end = false,
    this.expanded = false,
  });

  final String label;
  final Money amount;
  final IconData? icon;
  final Color? dot;

  /// Right-aligned, with the split / unsplit chevron.
  final bool end;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    const soft = Colors.white70;
    final ic = icon;
    final d = dot;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (d != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: d, shape: BoxShape.circle),
                ),
                const SizedBox(width: Space.x1_5),
              ],
              if (ic != null) ...[Icon(ic, size: 11, color: soft), const SizedBox(width: Space.x1)],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: t.micro.copyWith(color: soft, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (end) ...[
                const SizedBox(width: Space.x0_5),
                ExcludeSemantics(
                  child: Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 12, color: soft),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.x0_5),
          AmountText(
            amount,
            style: t.amountMedium.copyWith(color: Colors.white, fontSize: 17),
            decimals: DecimalDisplay.none,
            fit: true,
            textAlign: end ? TextAlign.end : null,
          ),
        ],
      ),
    );
  }
}

/// Explains how "available to spend" is derived from the ledger.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool strong = false, Color? color}) {
      return KeyValueRow(
        label: label,
        valueWidget: AmountText(amount, sign: sign, color: color, style: strong ? t.amountMedium : t.amountSmall),
      );
    }

    return FinnSheetScaffold(
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is simply earmarked so you do not spend it by accident.',
      footer: FinnButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: c.positive),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const FinnDivider(),
          line('Cash · bank & wallet', balance.cash, strong: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const FinnDivider(),
          line('Available to spend', balance.available, strong: true),
          const SizedBox(height: Space.x4),
          const InfoBanner(
            message:
                'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
          ),
        ],
      ),
    );
  }
}
