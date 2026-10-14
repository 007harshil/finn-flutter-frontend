import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../design_system/design_system.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';

/// One headline number of a review ("2 Move money").
class ImpactTile extends StatelessWidget {
  const ImpactTile({super.key, required this.value, required this.label, required this.icon, required this.color});

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2_5, vertical: Space.x2),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: c.isDark ? 0.6 : 0.85),
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: Space.x1_5),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: t.bodyStrong),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.micro.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What one proposed change does, built from the app's own preview (never
/// the model's words): module and kind, the headline amount, the preview's
/// details, before → after effects, risk pills and warnings. [trailing] sits
/// at the end of the title row (e.g. a status mark).
class ChangeDetails extends StatelessWidget {
  const ChangeDetails({super.key, required this.proposal, this.accent, this.trailing});

  final ProposedAction proposal;

  /// Overrides the module colour of the eyebrow (regenerated changes).
  final Color? accent;
  final Widget? trailing;

  static const _arrow = ' → ';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final preview = proposal.preview;
    final visual = actionVisualFor(proposal.descriptor.id, c);
    final warnings = [...preview.warnings, ...proposal.notes];

    PreviewLine? amount;
    final details = <PreviewLine>[];
    final effects = <PreviewLine>[];
    for (final l in preview.lines) {
      if (amount == null && l.label == 'Amount') {
        amount = l;
      } else if (l.value.contains(_arrow)) {
        effects.add(l);
      } else {
        details.add(l);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ActionIconBadge(visual: visual),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${visual.module.toUpperCase()} · ${visual.verb.toUpperCase()}',
                      style: t.eyebrow.copyWith(color: accent ?? visual.color)),
                  const SizedBox(height: 2),
                  Text(preview.summary, style: t.bodyStrong),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
        if (amount != null) ...[
          const SizedBox(height: Space.x2),
          Text(amount.value, style: t.amountMedium),
        ],
        if (details.isNotEmpty) ...[
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x1_5,
            runSpacing: Space.x1_5,
            children: [for (final l in details) _DetailChip(line: l)],
          ),
        ],
        for (final e in effects) ...[
          const SizedBox(height: Space.x2),
          _EffectRow(label: e.label, before: e.value.split(_arrow).first, after: e.value.split(_arrow).last),
        ],
        if (proposal.descriptor.movesMoney || !proposal.descriptor.reversible) ...[
          const SizedBox(height: Space.x2),
          Wrap(
            spacing: Space.x1_5,
            runSpacing: Space.x1_5,
            children: [
              if (proposal.descriptor.movesMoney)
                StatusPill(label: 'Moves money', color: c.attention, icon: LucideIcons.arrowLeftRight),
              if (!proposal.descriptor.reversible)
                StatusPill(label: 'Cannot be undone', color: c.negative, icon: LucideIcons.lock),
            ],
          ),
        ],
        for (final w in warnings) ...[
          const SizedBox(height: Space.x2),
          InfoBanner(message: w, tone: FinnTone.warning),
        ],
      ],
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.line});
  final PreviewLine line;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      child: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${line.label}  ', style: t.micro.copyWith(color: c.textSecondary)),
          TextSpan(
            text: line.value,
            style: t.caption.copyWith(color: c.textPrimary, fontWeight: line.emphasis ? FontWeight.w800 : FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

/// "Available to spend  ₹10,000 → ₹9,550" as a before/after strip.
class _EffectRow extends StatelessWidget {
  const _EffectRow({required this.label, required this.before, required this.after});

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      label: '$label changes from $before to $after',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: t.micro.copyWith(color: c.textSecondary)),
            const SizedBox(height: 2),
            Row(
              children: [
                Flexible(
                  child: Text(before,
                      style: t.caption.copyWith(color: c.textTertiary, decoration: TextDecoration.lineThrough)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x2),
                  child: Icon(LucideIcons.arrowRight, size: 14, color: c.textSecondary),
                ),
                Flexible(child: Text(after, style: t.bodyStrong)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
