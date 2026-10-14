import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/result/result.dart';
import '../../../../design_system/design_system.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../../../finance/ledger.dart';

/// "Available to spend" as an obsidian card: one serif figure, and a
/// hairline bar that is your cash with the set-aside part engraved out.
///
/// The card leans towards the finger (a live 3D tilt with a moving
/// specular sheen) and springs back when released. Tap the bar to split
/// set-aside money into goals and emergencies; tap anywhere else for the
/// full maths.
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(balanceProvider);
    if (value.hasValue) return _HeroContent(balance: value.requireValue);
    if (value.hasError) {
      final e = value.error;
      return LuxeCard(
        child: LuxeError(
          title: 'Balance unavailable',
          message: e is AppFailure ? e.message : null,
          onRetry: () => refreshFinanceData(ref),
        ),
      );
    }
    return const LuxeShimmer(child: LuxeBone(height: 236, radius: LuxeSpace.rCard));
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
  _SharesTween({required _Shares super.end})
    : super(begin: const _Shares(free: 0, goals: 0, emergency: 0, over: false));

  @override
  _Shares lerp(double t) => _Shares.lerp(begin!, end!, t);
}

/// Colours used on the obsidian surface (same in both themes).
abstract final class _Ob {
  static const ink = Color(0xFFF6F1E7);
  static const soft = Color(0xFFB9AF9F);
  static const goals = Color(0xFFA9BCDD);
  static const emergency = Color(0xFF93C9A9);
  static const warning = Color(0xFFF0C27A);
}

class _HeroContent extends StatefulWidget {
  const _HeroContent({required this.balance});

  final BalanceSnapshot balance;

  @override
  State<_HeroContent> createState() => _HeroContentState();
}

class _HeroContentState extends State<_HeroContent> with TickerProviderStateMixin {
  bool _split = false;

  /// Tilt in -1..1 on each axis; springs back to rest on release.
  final ValueNotifier<Offset> _tilt = ValueNotifier(Offset.zero);
  late final AnimationController _spring = AnimationController.unbounded(vsync: this)..addListener(_onSpring);
  Offset _released = Offset.zero;

  /// One slow pass of light across the card when it first appears.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.reduceMotion) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _spring.dispose();
    _intro.dispose();
    _tilt.dispose();
    super.dispose();
  }

  void _onSpring() => _tilt.value = _released * _spring.value;

  void _lean(Offset local, Size size) {
    if (context.reduceMotion || size.isEmpty) return;
    _spring.stop();
    final x = (local.dx / size.width * 2 - 1).clamp(-1.0, 1.0);
    final y = (local.dy / size.height * 2 - 1).clamp(-1.0, 1.0);
    _tilt.value = Offset(x, y);
  }

  void _release() {
    if (_tilt.value == Offset.zero) return;
    _released = _tilt.value;
    _spring.value = 1;
    _spring.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 180, damping: 14), 1, 0, 0));
  }

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _split = !_split);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final b = widget.balance;
    final shares = _Shares.of(b);
    final hidden = AmountVisibility.hiddenOf(context);

    final face = Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: Color(0xFFD7B67A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text('AVAILABLE TO SPEND', style: t.eyebrow.c(_Ob.soft), maxLines: 1)),
              const Icon(LucideIcons.info, size: 16, color: _Ob.soft),
            ],
          ),
          const SizedBox(height: 18),
          LuxeAmount(
            b.available,
            style: t.display.copyWith(fontSize: 54, color: _Ob.ink, letterSpacing: -1.6),
            countFromZero: true,
          ),
          if (!hidden && (b.cash.isPositive || shares.over)) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: _FreeTag(shares: shares),
            ),
          ],
          const SizedBox(height: 22),
          _Allocation(balance: b, shares: shares, split: _split, onToggle: _toggle),
        ],
      ),
    );

    return Semantics(
      button: true,
      label: 'Available to spend. Double tap for the full breakdown.',
      onTap: () => _openBreakdown(context, b),
      child: LayoutBuilder(
        builder: (context, box) {
          final size = Size(box.maxWidth, 280);
          return Listener(
            onPointerDown: (e) => _lean(e.localPosition, size),
            onPointerMove: (e) => _lean(e.localPosition, size),
            onPointerUp: (_) => _release(),
            onPointerCancel: (_) => _release(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => _openBreakdown(context, b),
              child: ValueListenableBuilder<Offset>(
                valueListenable: _tilt,
                child: face,
                builder: (context, tilt, child) {
                  final m = Matrix4.identity()
                    ..setEntry(3, 2, 0.0012)
                    ..rotateX(-tilt.dy * 0.07)
                    ..rotateY(tilt.dx * 0.09);
                  return Transform(
                    alignment: Alignment.center,
                    transform: m,
                    child: _ObsidianSurface(tilt: tilt, intro: _intro, child: child!),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _openBreakdown(BuildContext context, BalanceSnapshot b) =>
      showLuxeSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: b));
}

/// Near-black card with an engraved guilloché, a champagne hairline and a
/// specular highlight that follows the tilt.
class _ObsidianSurface extends StatelessWidget {
  const _ObsidianSurface({required this.tilt, required this.intro, required this.child});

  final Offset tilt;
  final Animation<double> intro;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    const radius = BorderRadius.all(Radius.circular(30));
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: p.heroShadow),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _EngravingPainter(gradient: p.obsidianGradient),
          foregroundPainter: _SheenPainter(tilt: tilt, intro: intro, edge: p.obsidianEdge),
          child: child,
        ),
      ),
    );
  }
}

class _EngravingPainter extends CustomPainter {
  _EngravingPainter({required this.gradient});

  final Gradient gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
    // Guilloché: fine concentric ellipses rippling from the top-right.
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7
      ..color = const Color(0xFFD7B67A).withValues(alpha: 0.07);
    final c = Offset(size.width * 1.02, -size.height * 0.1);
    for (var i = 1; i <= 22; i++) {
      final r = i * 17.0;
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2.4, height: r * 1.7), line);
    }
    // A soft warm glow low on the left.
    final glow = RadialGradient(colors: [const Color(0xFFD7B67A).withValues(alpha: 0.10), const Color(0x00D7B67A)])
        .createShader(Rect.fromCircle(center: Offset(0, size.height), radius: size.width * 0.7));
    canvas.drawCircle(Offset(0, size.height), size.width * 0.7, Paint()..shader = glow);
  }

  @override
  bool shouldRepaint(_EngravingPainter old) => old.gradient != gradient;
}

class _SheenPainter extends CustomPainter {
  _SheenPainter({required this.tilt, required this.intro, required this.edge}) : super(repaint: intro);

  final Offset tilt;
  final Animation<double> intro;
  final Color edge;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Hairline edge, brighter at the top like light catching metal.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), const Radius.circular(30)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge.withValues(alpha: 0.9), edge.withValues(alpha: 0.15)],
        ).createShader(rect),
    );

    // Specular highlight that follows the finger.
    final strength = (tilt.distance / 1.4).clamp(0.0, 1.0);
    if (strength > 0.01) {
      final center = Offset(size.width * (0.5 + tilt.dx * 0.5), size.height * (0.5 + tilt.dy * 0.5));
      final shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.10 * strength),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.6));
      canvas.drawCircle(center, size.width * 0.6, Paint()..shader = shader);
    }

    // One diagonal pass of light on entrance.
    final v = intro.value;
    if (v > 0.25 && v < 1) {
      final k = Curves.easeInOutCubic.transform((v - 0.25) / 0.75);
      final x = -size.width * 0.6 + k * size.width * 2.2;
      final band = Rect.fromLTWH(x - 90, 0, 180, size.height);
      canvas.save();
      canvas.translate(0, 0);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            transform: const GradientRotation(-0.35),
            colors: [
              Colors.white.withValues(alpha: 0),
              Colors.white.withValues(alpha: 0.07 * math.sin(k * math.pi)),
              Colors.white.withValues(alpha: 0),
            ],
          ).createShader(band),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.tilt != tilt || old.edge != edge;
}

/// "11% of cash free", or a warning when set-aside money exceeds cash.
class _FreeTag extends StatelessWidget {
  const _FreeTag({required this.shares});

  final _Shares shares;

  @override
  Widget build(BuildContext context) {
    final t = context.lt;
    final over = shares.over;
    final fg = over ? _Ob.warning : _Ob.ink;
    return Semantics(
      label: over ? 'More is set aside than you have in cash' : '${shares.freeLabel} of your cash is free to spend',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(over ? LucideIcons.triangleAlert : LucideIcons.sparkles, size: 12, color: fg),
            const SizedBox(width: 6),
            Text(over ? 'Over-committed' : '${shares.freeLabel} of cash is free', style: t.micro.w(700).c(fg)),
          ],
        ),
      ),
    );
  }
}

/// The cash bar plus its two figures. Tapping toggles the goals /
/// emergency split.
class _Allocation extends StatelessWidget {
  const _Allocation({required this.balance, required this.shares, required this.split, required this.onToggle});

  final BalanceSnapshot balance;
  final _Shares shares;
  final bool split;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final reduced = context.reduceMotion;
    final legend = split
        ? Row(
            key: const ValueKey('split'),
            children: [
              Expanded(
                child: _Stat(label: 'For goals', amount: balance.earmarkedGoals, dot: _Ob.goals),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Stat(
                  label: 'Emergency fund',
                  amount: balance.earmarkedEmergency,
                  dot: _Ob.emergency,
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
                child: _Stat(label: 'Cash · bank & wallet', amount: balance.cash),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _Stat(label: 'Set aside', amount: balance.earmarked, icon: LucideIcons.lock, end: true),
              ),
            ],
          );
    return Semantics(
      button: true,
      toggled: split,
      label: 'Split set-aside money into goals and emergencies',
      onTap: onToggle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onToggle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TweenAnimationBuilder<_Shares>(
              tween: _SharesTween(end: shares),
              duration: reduced ? Duration.zero : const Duration(milliseconds: 1400),
              curve: LuxeCurves.arrive,
              builder: (context, s, _) => TweenAnimationBuilder<double>(
                tween: Tween(end: split ? 1 : 0),
                duration: reduced ? Duration.zero : LuxeDurations.base,
                curve: LuxeCurves.glide,
                builder: (context, k, _) => SizedBox(
                  height: 10,
                  width: double.infinity,
                  child: CustomPaint(
                    painter: _BarPainter(shares: s, split: k),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: reduced ? Duration.zero : LuxeDurations.base,
              switchInCurve: LuxeCurves.arrive,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: legend,
            ),
          ],
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.shares, required this.split});

  final _Shares shares;
  final double split;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = 4.0;
    final top = (size.height - h) / 2;
    final track = RRect.fromLTRBR(0, top, w, top + h, const Radius.circular(2));
    canvas.drawRRect(track, Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.save();
    canvas.clipRRect(track);
    final freeW = shares.free * w;
    if (freeW > 0) {
      final r = Rect.fromLTWH(0, top, freeW, h);
      canvas.drawRect(
        r,
        Paint()
          ..shader = const LinearGradient(colors: [Color(0xFFF1D9A6), Color(0xFFD7B67A), Color(0xFFB08A4E)])
              .createShader(r),
      );
    }
    final gap = 3.0 * split;
    final locked = shares.over ? _Ob.warning.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.28);
    var x = freeW + (freeW > 0 ? 2 : 0);
    for (final (share, color) in [(shares.goals, _Ob.goals), (shares.emergency, _Ob.emergency)]) {
      final width = share * w;
      if (width <= 0) continue;
      final r = Rect.fromLTWH(x, top, math.max(0, width - gap), h);
      canvas.drawRect(r, Paint()..color = Color.lerp(locked, color, split)!);
      x += width;
    }
    canvas.restore();
    // A small diamond marks where free money ends.
    if (freeW > 0 && freeW < w) {
      final c = Offset(freeW, size.height / 2);
      final d = Path()
        ..moveTo(c.dx, c.dy - 5)
        ..lineTo(c.dx + 4, c.dy)
        ..lineTo(c.dx, c.dy + 5)
        ..lineTo(c.dx - 4, c.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = const Color(0xFFF1D9A6));
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) => old.shares != shares || old.split != split;
}

class _Stat extends StatelessWidget {
  const _Stat({
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
    final t = context.lt;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: end ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              if (icon != null) ...[Icon(icon, size: 11, color: _Ob.soft), const SizedBox(width: 5)],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: t.micro.w(700).c(_Ob.soft).copyWith(letterSpacing: 1.1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (end) ...[
                const SizedBox(width: 3),
                ExcludeSemantics(
                  child: Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 12, color: _Ob.soft),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          AmountText(
            amount,
            style: t.number.copyWith(fontSize: 17, color: _Ob.ink),
            decimals: DecimalDisplay.none,
            fit: true,
            textAlign: end ? TextAlign.end : null,
          ),
        ],
      ),
    );
  }
}

/// Explains how "available to spend" is derived from the ledger, as a
/// receipt-like equation.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    var i = 0;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool total = false, Color? color}) {
      return Reveal(
        index: i++,
        offset: 8,
        blur: 0,
        duration: LuxeDurations.base,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: total ? 10 : 7),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(label, style: total ? t.heading : t.bodySoft, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: AmountText(
                  amount,
                  sign: sign,
                  color: color,
                  fit: true,
                  textAlign: TextAlign.end,
                  style: total ? t.figure.copyWith(fontSize: 26) : t.number,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return LuxeSheet(
      eyebrow: 'Available to spend',
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is simply earmarked so you do not spend it by accident.',
      footer: LuxeButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: p.positive),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const LuxeHairline(vertical: 6),
          line('Cash · bank & wallet', balance.cash, total: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const LuxeHairline(vertical: 6),
          line('Available to spend', balance.available, total: true),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.goldSoft, borderRadius: BorderRadius.circular(16)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.info, size: 16, color: p.goldInk),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
                    style: t.caption.c(p.ink),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
