import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../kit/kit.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';

/// What one proposed change does, built from the app's own preview (never
/// the model's words), as rows for a [LedgerPanel]: a head with module,
/// summary and the amount as a figure, then one [LedgerFact] per detail and
/// before → after effect, and any warnings.
///
/// [tag] sits at the end of the head's first line (e.g. "Try 2"),
/// [trailing] at the end of the summary (e.g. a saved mark).
List<Widget> changeDetailRows(BuildContext context, ProposedAction proposal, {Widget? tag, Widget? trailing}) {
  const arrow = ' → ';
  final preview = proposal.preview;
  final warnings = [...preview.warnings, ...proposal.notes];

  PreviewLine? amount;
  final details = <PreviewLine>[];
  for (final l in preview.lines) {
    if (amount == null && l.label == 'Amount') {
      amount = l;
    } else {
      details.add(l);
    }
  }

  return [
    _ChangeHead(proposal: proposal, amount: amount?.value, tag: tag, trailing: trailing),
    for (final l in details)
      if (l.value.contains(arrow))
        _EffectFact(label: l.label, before: l.value.split(arrow).first, after: l.value.split(arrow).last)
      else
        LedgerFact(
          label: l.label,
          value: Text(
            l.value,
            textAlign: TextAlign.end,
            style: l.emphasis ? context.type.bodyStrong : context.type.body,
          ),
        ),
    if (warnings.isNotEmpty)
      Padding(
        padding: const EdgeInsets.all(Sp.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < warnings.length; i++) ...[
              if (i > 0) const SizedBox(height: Sp.sm),
              LedgerNote(text: warnings[i], icon: LucideIcons.triangleAlert, tone: NoteTone.caution),
            ],
          ],
        ),
      ),
  ];
}

class _ChangeHead extends StatelessWidget {
  const _ChangeHead({required this.proposal, required this.amount, this.tag, this.trailing});

  final ProposedAction proposal;
  final String? amount;
  final Widget? tag;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final visual = actionVisualFor(proposal.descriptor.id);
    final d = proposal.descriptor;
    final a = amount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.lg, Sp.lg, Sp.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(visual.icon, size: 16, color: c.inkSoft),
              const SizedBox(width: Sp.sm),
              Expanded(child: Text('${visual.module} · ${visual.verb}', style: t.label)),
              ?tag,
            ],
          ),
          const SizedBox(height: Sp.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(proposal.preview.summary, style: t.bodyStrong)),
              if (trailing != null) ...[const SizedBox(width: Sp.sm), trailing!],
            ],
          ),
          if (a != null) ...[const SizedBox(height: Sp.sm), Text(a, style: t.figureL)],
          if (d.movesMoney || !d.reversible) ...[
            const SizedBox(height: Sp.sm),
            Wrap(
              spacing: Sp.lg,
              runSpacing: Sp.xs,
              children: [
                if (d.movesMoney) _Flag(icon: LucideIcons.arrowLeftRight, label: 'Moves money', color: c.inkSoft),
                if (!d.reversible) _Flag(icon: LucideIcons.lock, label: 'Cannot be undone', color: c.amber),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Flag extends StatelessWidget {
  const _Flag({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: Sp.xs + 2),
        Text(label, style: context.type.small.copyWith(color: color)),
      ],
    );
  }
}

/// "Available to spend  ₹10,000 → ₹9,550" as one fact row.
class _EffectFact extends StatelessWidget {
  const _EffectFact({required this.label, required this.before, required this.after});

  final String label;
  final String before;
  final String after;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Semantics(
      label: '$label changes from $before to $after',
      excludeSemantics: true,
      child: LedgerFact(
        label: label,
        value: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Sp.xs + 2,
          children: [
            Text(
              before,
              style: t.figureSmall.copyWith(decoration: TextDecoration.lineThrough, decorationColor: c.inkSoft),
            ),
            Icon(LucideIcons.arrowRight, size: 14, color: c.inkSoft),
            Text(after, style: t.figure),
          ],
        ),
      ),
    );
  }
}
