import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../components/buttons.dart';
import '../motion/motion.dart';
import 'vault_controls.dart';
import 'vault_motion.dart';
import 'vault_route.dart';
import 'vault_sheet.dart';
import 'vault_tokens.dart';

/// A centred confirmation card. Resolves true only on confirm.
///
/// The emblem lands first and sends out one soft ring (cause → effect: this
/// needs your attention); the decision is stacked with the committing action
/// on top, within thumb reach, and the escape directly beneath it.
Future<bool> showVaultConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
  Widget? details,
}) async {
  final ok = await showVaultDialog<bool>(
    context,
    builder: (context) {
      final p = context.vault;
      final t = context.vt;
      final tone = destructive ? p.negative : p.accentInk;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: VaultHalo(
                color: tone,
                child: VaultEmblem(
                  icon: icon ?? (destructive ? LucideIcons.triangleAlert : LucideIcons.circleHelp),
                  color: tone,
                  size: 58,
                ),
              ),
            ),
            const SizedBox(height: 22),
            VaultRise(
              delay: const Duration(milliseconds: 90),
              child: Semantics(
                header: true,
                child: Text(title, textAlign: TextAlign.center, style: t.dialogTitle),
              ),
            ),
            const SizedBox(height: 10),
            VaultRise(
              delay: const Duration(milliseconds: 140),
              child: Text(message, textAlign: TextAlign.center, style: t.bodySoft),
            ),
            if (details != null) ...[
              const SizedBox(height: 18),
              VaultRise(delay: const Duration(milliseconds: 180), child: details),
            ],
            const SizedBox(height: 28),
            VaultRise(
              delay: const Duration(milliseconds: 200),
              child: FinnButton(
                label: confirmLabel,
                variant: destructive ? FinnButtonVariant.destructive : FinnButtonVariant.primary,
                expand: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ),
            const SizedBox(height: 6),
            VaultRise(
              delay: const Duration(milliseconds: 240),
              child: FinnButton(
                label: cancelLabel,
                variant: FinnButtonVariant.ghost,
                expand: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}

/// Lands its child on a spring and emits a single expanding ring.
class VaultHalo extends StatefulWidget {
  const VaultHalo({super.key, required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  State<VaultHalo> createState() => _VaultHaloState();
}

class _VaultHaloState extends State<VaultHalo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    context.reduceMotion ? _c.value = 1 : _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final v = _c.value;
        final land = VaultMotion.pop.transform(math.min(1, v / 0.45));
        final ring = Curves.easeOutCubic.transform(((v - 0.25) / 0.75).clamp(0.0, 1.0));
        return SizedBox(
          width: 84,
          height: 84,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (ring > 0 && ring < 1)
                Container(
                  width: 58 + 26 * ring,
                  height: 58 + 26 * ring,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color.withValues(alpha: 0.35 * (1 - ring)), width: 1.5),
                  ),
                ),
              Transform.scale(scale: 0.6 + 0.4 * land, child: Opacity(opacity: land.clamp(0.0, 1.0), child: child)),
            ],
          ),
        );
      },
    );
  }
}

/// One row of [showVaultMenu].
@immutable
class VaultMenuEntry<T> {
  const VaultMenuEntry({
    required this.value,
    required this.label,
    this.icon,
    this.hint,
    this.destructive = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final String? hint;
  final bool destructive;
  final bool enabled;
}

/// Contextual actions as a floating sheet. Regular actions sit together in
/// one group; destructive ones are set apart below a gap so they are never
/// hit by accident.
Future<T?> showVaultMenu<T>(
  BuildContext context, {
  String? title,
  String? eyebrow,
  required List<VaultMenuEntry<T>> items,
}) {
  return showVaultSheet<T>(
    context,
    builder: (context) {
      final regular = [for (final i in items) if (!i.destructive) i];
      final danger = [for (final i in items) if (i.destructive) i];
      var index = 0;
      Widget group(List<VaultMenuEntry<T>> entries) => VaultGroup(
        children: [for (final e in entries) VaultRise(index: index++, offset: 10, child: _MenuRow<T>(entry: e))],
      );
      return VaultSheet(
        title: title,
        eyebrow: eyebrow,
        showClose: title != null,
        bodyPadding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (regular.isNotEmpty) group(regular),
            if (regular.isNotEmpty && danger.isNotEmpty) const SizedBox(height: 12),
            if (danger.isNotEmpty) group(danger),
          ],
        ),
      );
    },
  );
}

class _MenuRow<T> extends StatelessWidget {
  const _MenuRow({required this.entry});

  final VaultMenuEntry<T> entry;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final fg = entry.destructive ? p.negative : p.ink;
    final icon = entry.icon;
    return Opacity(
      opacity: entry.enabled ? 1 : 0.4,
      child: VaultPress(
        key: ValueKey('vault-menu:${entry.value}'),
        onTap: entry.enabled ? () => Navigator.of(context).pop(entry.value) : null,
        scale: 0.98,
        semanticLabel: entry.label,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: entry.destructive ? p.tint(p.negative, 0.1) : p.surface,
                    ),
                    child: Icon(icon, size: 17, color: fg),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(entry.label, style: t.heading.vc(fg)),
                      if (entry.hint != null) ...[
                        const SizedBox(height: 2),
                        Text(entry.hint!, style: t.caption),
                      ],
                    ],
                  ),
                ),
                Icon(LucideIcons.chevronRight, size: 16, color: p.inkFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of a [VaultReceipt].
@immutable
class VaultReceiptLine {
  const VaultReceiptLine(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;
}

/// "What will happen" as a receipt: a paper slip with a perforated edge,
/// the consequential figure set large, and every other line quiet.
class VaultReceipt extends StatelessWidget {
  const VaultReceipt({super.key, required this.lines});

  final List<VaultReceiptLine> lines;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    final t = context.vt;
    final hero = [for (final l in lines) if (l.emphasis) l];
    final rest = [for (final l in lines) if (!l.emphasis) l];
    return ClipPath(
      clipper: const _PerforatedClipper(),
      child: Container(
        color: p.well,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final h in hero) ...[
              Text(h.label.toUpperCase(), style: t.eyebrow),
              const SizedBox(height: 6),
              VaultRise(
                scale: 0.96,
                child: Text(h.value, style: t.hero.copyWith(fontSize: 40)),
              ),
              const SizedBox(height: 12),
            ],
            if (hero.isNotEmpty && rest.isNotEmpty) const _DashedRule(),
            for (var i = 0; i < rest.length; i++)
              VaultRise(
                index: i,
                offset: 8,
                child: VaultFact(label: rest[i].label, value: rest[i].value),
              ),
          ],
        ),
      ),
    );
  }
}

class _DashedRule extends StatelessWidget {
  const _DashedRule();

  @override
  Widget build(BuildContext context) {
    final c = context.vault.hairlineStrong;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) {
          final n = (box.maxWidth / 9).floor();
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [for (var i = 0; i < n; i++) Container(width: 4, height: 1.2, color: c)],
          );
        },
      ),
    );
  }
}

/// Rounded slip whose bottom edge is a row of half-circle bites.
class _PerforatedClipper extends CustomClipper<Path> {
  const _PerforatedClipper();

  @override
  Path getClip(Size size) {
    const r = 18.0;
    const bite = 5.0;
    final path = Path()
      ..moveTo(0, r)
      ..quadraticBezierTo(0, 0, r, 0)
      ..lineTo(size.width - r, 0)
      ..quadraticBezierTo(size.width, 0, size.width, r)
      ..lineTo(size.width, size.height - bite);
    final n = math.max(6, (size.width / 16).floor());
    final step = size.width / n;
    for (var i = n; i > 0; i--) {
      final x = i * step;
      path.arcToPoint(Offset(x - step, size.height - bite), radius: Radius.circular(step / 2), clockwise: true);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_PerforatedClipper oldClipper) => false;
}

/// A soft, finite success mark for inline confirmations inside sheets.
class VaultCheck extends StatelessWidget {
  const VaultCheck({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.vault;
    return VaultHalo(color: p.positive, child: VaultEmblem(icon: LucideIcons.check, color: p.positive, size: size, filled: true));
  }
}
