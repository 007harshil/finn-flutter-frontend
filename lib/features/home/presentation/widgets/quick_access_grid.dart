import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/luxe/luxe.dart';

/// Entry points to every money module as a quiet bento of paper tiles.
///
/// Tiles carry a name, a fine-line icon and a one-word hint, never figures:
/// the detail lives one tap away, which keeps Home quick to scan.
///
/// ```
/// ┌────────┬───────┐
/// │ Loans  │Pending│
/// │ (tall) ├───────┤
/// │        │ Fund  │
/// ├──────┬─┴───────┤
/// │Goals │Timeline │
/// ├──────┴─────────┤
/// │ Insights  ▂▅▃▇ │
/// └────────────────┘
/// ```
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({super.key});

  static const _gap = 12.0;

  @override
  Widget build(BuildContext context) {
    final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.8);
    final short = 128.0 * scale;
    final wide = 128.0 * scale;
    final banner = 112.0 * scale;

    final loans = _Spec('Loans & EMIs', 'Repayments', LucideIcons.landmark, () => context.push(AppRoutes.loans));
    final pending = _Spec(
      'Pending payments',
      'Owe & owed',
      LucideIcons.handCoins,
      () => context.push(AppRoutes.pending),
    );
    final emergency = _Spec(
      'Emergency fund',
      'Safety net',
      LucideIcons.shieldCheck,
      () => context.push(AppRoutes.emergencyFund),
    );
    final goals = _Spec('Goals', 'Savings', LucideIcons.target, () => context.go(AppRoutes.goals));
    final timeline = _Spec('Timeline', 'Money story', LucideIcons.history, () => context.push(AppRoutes.timeline));
    final insights = _Spec(
      'Insights',
      'Patterns & trends',
      LucideIcons.chartColumnIncreasing,
      () => context.push(AppRoutes.analytics),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LuxeSectionHeader(title: 'Your money', caption: 'Every module, one tap away'),
        const SizedBox(height: 14),
        SizedBox(
          height: short * 2 + _gap,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: _Tile(spec: loans, index: 0, tall: true)),
              const SizedBox(width: _gap),
              Expanded(
                flex: 9,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _Tile(spec: pending, index: 1)),
                    const SizedBox(height: _gap),
                    Expanded(child: _Tile(spec: emergency, index: 2)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: _gap),
        SizedBox(
          height: wide,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 2, child: _Tile(spec: goals, index: 3)),
              const SizedBox(width: _gap),
              Expanded(flex: 3, child: _Tile(spec: timeline, index: 4)),
            ],
          ),
        ),
        const SizedBox(height: _gap),
        SizedBox(
          height: banner,
          child: _Tile(spec: insights, index: 5, art: true),
        ),
      ],
    );
  }
}

class _Spec {
  const _Spec(this.title, this.hint, this.icon, this.onTap);
  final String title;
  final String hint;
  final IconData icon;
  final VoidCallback onTap;
}

class _Tile extends StatelessWidget {
  _Tile({required this.spec, required this.index, this.tall = false, this.art = false})
    : super(key: ValueKey('quick-tile:${spec.title}'));

  final _Spec spec;
  final int index;
  final bool tall;
  final bool art;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = spec;
    final tile = DecoratedBox(
      decoration: BoxDecoration(
        color: tall ? p.obsidian : p.paper,
        gradient: tall ? p.obsidianGradient : null,
        borderRadius: BorderRadius.circular(LuxeSpace.rTile),
        border: Border.all(color: tall ? p.obsidianEdge : p.line),
        boxShadow: p.lift,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(LuxeSpace.rTile),
        child: Stack(
          children: [
            if (tall) Positioned.fill(child: CustomPaint(painter: _ArcsPainter(const Color(0xFFD7B67A)))),
            if (art)
              PositionedDirectional(
                end: 18,
                top: 18,
                bottom: 18,
                width: math.min(150, MediaQuery.sizeOf(context).width * 0.36),
                child: _InsightsArt(color: p.gold, faint: p.sunk, delay: LuxeDurations.stagger * index),
              ),
            Padding(
              padding: EdgeInsets.all(tall ? 18 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: tall ? 42 : 34,
                        height: tall ? 42 : 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: tall ? const Color(0x55D7B67A) : p.lineStrong),
                        ),
                        child: Icon(s.icon, size: tall ? 19 : 16, color: tall ? const Color(0xFFE9CF98) : p.ink),
                      ),
                      const Spacer(),
                      if (!art)
                        Icon(LucideIcons.arrowUpRight, size: 16, color: tall ? const Color(0xFFB9AF9F) : p.inkMute),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: t.title.copyWith(
                      fontSize: tall ? 26 : 19,
                      height: 1.05,
                      color: tall ? const Color(0xFFF6F1E7) : p.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.caption.c(tall ? const Color(0xFFB9AF9F) : p.inkSoft),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Reveal(
      index: index,
      scale: 0.94,
      blur: 4,
      child: Squish(
        onTap: s.onTap,
        scale: 0.96,
        semanticLabel: s.title,
        semanticHint: s.hint,
        excludeSemantics: true,
        child: tile,
      ),
    );
  }
}

/// Fine engraved arcs on the dark loans tile.
class _ArcsPainter extends CustomPainter {
  _ArcsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = color.withValues(alpha: 0.12);
    final c = Offset(size.width * 1.05, size.height * 0.92);
    for (var i = 1; i <= 9; i++) {
      canvas.drawCircle(c, i * 18.0, paint);
    }
  }

  @override
  bool shouldRepaint(_ArcsPainter old) => old.color != color;
}

/// A week of spending as bars rising one after another, with a trend line
/// traced over them: what Insights is about, without figures.
class _InsightsArt extends StatelessWidget {
  const _InsightsArt({required this.color, required this.faint, required this.delay});

  final Color color;
  final Color faint;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DrawIn(
        value: 1,
        delay: delay + const Duration(milliseconds: 300),
        duration: const Duration(milliseconds: 1500),
        builder: (context, v) => CustomPaint(
          painter: _ArtPainter(progress: v, color: color, faint: faint),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter({required this.progress, required this.color, required this.faint});

  final double progress;
  final Color color;
  final Color faint;

  static const _bars = [0.42, 0.68, 0.36, 0.86, 0.55, 0.74, 0.5];

  @override
  void paint(Canvas canvas, Size size) {
    final n = _bars.length;
    const gap = 7.0;
    final w = (size.width - gap * (n - 1)) / n;
    final tops = <Offset>[];
    for (var i = 0; i < n; i++) {
      final local = ((progress * (n + 2) - i) / 3).clamp(0.0, 1.0);
      final h = size.height * _bars[i] * Curves.easeOutBack.transform(local);
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(x, size.height - h, w, h),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = i == 3 ? color : faint,
      );
      tops.add(Offset(x + w / 2, size.height - h - 6));
    }
    if (progress > 0.4) {
      final path = Path()..moveTo(tops.first.dx, tops.first.dy);
      for (var i = 1; i < tops.length; i++) {
        final a = tops[i - 1];
        final b = tops[i];
        final mx = (a.dx + b.dx) / 2;
        path.cubicTo(mx, a.dy, mx, b.dy, b.dx, b.dy);
      }
      final reveal = ((progress - 0.4) / 0.6).clamp(0.0, 1.0);
      for (final m in path.computeMetrics()) {
        canvas.drawPath(
          m.extractPath(0, m.length * reveal),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..strokeCap = StrokeCap.round
            ..color = color,
        );
      }
      if (reveal >= 1) canvas.drawCircle(tops.last, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.progress != progress || old.color != color || old.faint != faint;
}
