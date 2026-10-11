import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../alerts/presentation/alert_visuals.dart' show MaybeAnimate;
import 'home_common.dart';

/// Entry points to the money modules as a bento grid of unequal tiles.
///
/// Tiles carry only a name, an icon and a one-word hint, never figures:
/// the detail lives one tap away on each module's own screen, which keeps
/// Home quick to scan.
///
/// Layout (order: loans, pending, emergency fund, goals, timeline):
/// ```
/// ┌────────┬───────┐
/// │ Loans  │Pending│
/// │ (tall) ├───────┤
/// │        │ Fund  │
/// ├──────┬─┴───────┤
/// │Goals │Timeline │
/// └──────┴─────────┘
/// ```
class QuickAccessGrid extends StatelessWidget {
  const QuickAccessGrid({super.key});

  static const _gap = Space.x3;
  static const _shortHeight = 124.0;
  static const _wideHeight = 132.0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Grow the fixed tile heights with the user's text size so labels
    // never clip.
    final scale = (MediaQuery.textScalerOf(context).scale(16) / 16).clamp(1.0, 1.8);
    final short = _shortHeight * scale;
    final wide = _wideHeight * scale;

    final loans = _TileSpec(
      title: 'Loans & EMIs',
      hint: 'Repayments',
      icon: LucideIcons.landmark,
      color: c.accentLoans,
      onTap: () => context.push(AppRoutes.loans),
    );
    final pending = _TileSpec(
      title: 'Pending payments',
      hint: 'Owe & owed',
      icon: LucideIcons.handCoins,
      color: c.accentPending,
      onTap: () => context.push(AppRoutes.pending),
    );
    final emergency = _TileSpec(
      title: 'Emergency fund',
      hint: 'Safety net',
      icon: LucideIcons.shieldCheck,
      color: c.accentEmergency,
      onTap: () => context.push(AppRoutes.emergencyFund),
    );
    final goals = _TileSpec(
      title: 'Goals',
      hint: 'Savings',
      icon: LucideIcons.target,
      color: c.accentGoals,
      onTap: () => context.go(AppRoutes.goals),
    );
    final timeline = _TileSpec(
      title: 'Timeline',
      hint: 'Money story',
      icon: LucideIcons.history,
      color: c.accentNetWorth,
      onTap: () => context.push(AppRoutes.timeline),
    );

    return HomeSection(
      icon: LucideIcons.layoutGrid,
      title: 'Your money',
      tileColor: c.accentTransactions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: short * 2 + _gap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 11,
                  child: _QuickTile(spec: loans, index: 0, size: _TileSize.tall),
                ),
                const SizedBox(width: _gap),
                Expanded(
                  flex: 9,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _QuickTile(spec: pending, index: 1)),
                      const SizedBox(height: _gap),
                      Expanded(child: _QuickTile(spec: emergency, index: 2)),
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
                Expanded(flex: 2, child: _QuickTile(spec: goals, index: 3)),
                const SizedBox(width: _gap),
                Expanded(
                  flex: 3,
                  child: _QuickTile(spec: timeline, index: 4, size: _TileSize.wide),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileSpec {
  const _TileSpec({
    required this.title,
    required this.hint,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String hint;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

enum _TileSize { regular, tall, wide }

/// One bento tile: tinted surface, icon badge, oversized watermark icon,
/// name and hint. Pops in staggered, shimmers once, squishes on press.
class _QuickTile extends StatefulWidget {
  _QuickTile({required this.spec, required this.index, this.size = _TileSize.regular})
    : super(key: ValueKey('quick-tile:${spec.title}'));

  final _TileSpec spec;
  final int index;
  final _TileSize size;

  @override
  State<_QuickTile> createState() => _QuickTileState();
}

class _QuickTileState extends State<_QuickTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final s = widget.spec;
    final tall = widget.size == _TileSize.tall;
    final delay = 80.ms * widget.index;
    final badgeSize = tall ? 48.0 : 36.0;
    final watermark = tall ? 132.0 : 92.0;

    final tile = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: Radii.rXxl,
        border: Border.all(color: s.color.withValues(alpha: c.isDark ? 0.32 : 0.18)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(s.color.withValues(alpha: c.isDark ? 0.22 : 0.14), c.surface),
            Color.alphaBlend(s.color.withValues(alpha: c.isDark ? 0.06 : 0.03), c.surface),
          ],
        ),
        boxShadow: c.isDark ? Elevation.none : Elevation.sm,
      ),
      child: ClipRRect(
        borderRadius: Radii.rXxl,
        child: Stack(
          children: [
            // Oversized, faint icon bleeding off the corner for texture.
            PositionedDirectional(
              end: -watermark * 0.22,
              bottom: -watermark * 0.22,
              child:
                  Icon(
                    s.icon,
                    size: watermark,
                    color: s.color.withValues(alpha: c.isDark ? 0.14 : 0.10),
                  ).maybeAnimate(
                    context,
                    (a) => a
                        .fadeIn(delay: delay + 200.ms, duration: 500.ms)
                        .rotate(
                          begin: -0.06,
                          end: 0,
                          delay: delay + 200.ms,
                          duration: 700.ms,
                          curve: Curves.easeOutBack,
                        ),
                  ),
            ),
            Padding(
              padding: EdgeInsets.all(tall ? Space.x4 : Space.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: badgeSize,
                        height: badgeSize,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.color,
                          borderRadius: BorderRadius.circular(badgeSize * 0.32),
                          boxShadow: [
                            BoxShadow(
                              color: s.color.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(s.icon, size: badgeSize * 0.5, color: Colors.white),
                      ).maybeAnimate(
                        context,
                        (a) => a.scale(
                          begin: const Offset(0.4, 0.4),
                          end: const Offset(1, 1),
                          delay: delay + 120.ms,
                          duration: 600.ms,
                          curve: Curves.elasticOut,
                        ),
                      ),
                      const Spacer(),
                      Icon(LucideIcons.arrowUpRight, size: 18, color: s.color),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    s.title,
                    style: (tall ? t.title : t.bodyStrong).copyWith(color: c.textPrimary, height: 1.15),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Space.x0_5),
                  Text(s.hint, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final interactive = Semantics(
      button: true,
      label: s.title,
      hint: s.hint,
      excludeSemantics: true,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1,
        duration: context.motion.fast,
        curve: Curves.easeOut,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: Radii.rXxl,
            splashColor: s.color.withValues(alpha: 0.12),
            highlightColor: s.color.withValues(alpha: 0.06),
            onHighlightChanged: (v) => setState(() => _pressed = v),
            onTap: s.onTap,
            child: tile,
          ),
        ),
      ),
    );

    return interactive.maybeAnimate(
      context,
      (a) => a
          .fadeIn(delay: delay, duration: 360.ms)
          .scale(
            begin: const Offset(0.88, 0.88),
            end: const Offset(1, 1),
            delay: delay,
            duration: 520.ms,
            curve: Curves.easeOutBack,
          )
          .slideY(begin: 0.12, end: 0, delay: delay, duration: 520.ms, curve: Curves.easeOutCubic)
          .then(delay: 120.ms)
          .shimmer(
            duration: 900.ms,
            color: Colors.white.withValues(alpha: c.isDark ? 0.10 : 0.35),
          ),
    );
  }
}
