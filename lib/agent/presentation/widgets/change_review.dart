import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../ui/ui.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';

/// What one proposed change does, built from the app's own preview (never
/// the model's words): module and kind, the summary, the headline amount,
/// the details as label/value lines, before → after effects, risks and
/// warnings. [trailing] sits at the end of the title row (e.g. a status).
class ChangeDetails extends StatelessWidget {
  const ChangeDetails({super.key, required this.proposal, this.trailing});

  final ProposedAction proposal;
  final Widget? trailing;

  static const _arrow = ' → ';

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final preview = proposal.preview;
    final visual = actionVisualFor(proposal.descriptor.id);
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
    final risks = <(IconData, String, Color)>[
      if (proposal.descriptor.movesMoney) (LucideIcons.arrowLeftRight, 'Moves money', c.inkSoft),
      if (!proposal.descriptor.reversible) (LucideIcons.lock, 'Cannot be undone', c.negative),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UiMark(icon: visual.icon),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${visual.module} · ${visual.verb}', style: t.small),
                  const SizedBox(height: 2),
                  Text(preview.summary, style: t.body),
                  if (amount != null && !preview.summary.contains(amount.value)) ...[
                    const SizedBox(height: UiSpace.xs),
                    Text(amount.value, style: t.figure),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: UiSpace.sm), trailing!],
          ],
        ),
        if (details.isNotEmpty || effects.isNotEmpty) ...[
          const SizedBox(height: UiSpace.md),
          for (final l in details) _Line(label: l.label, value: Text(l.value, style: _value(t, l.emphasis), textAlign: TextAlign.end)),
          for (final e in effects)
            Semantics(
              label: '${e.label} changes from ${e.value.split(_arrow).first} to ${e.value.split(_arrow).last}',
              excludeSemantics: true,
              child: _Line(
                label: e.label,
                value: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: e.value.split(_arrow).first,
                        style: t.label.copyWith(decoration: TextDecoration.lineThrough),
                      ),
                      const TextSpan(text: '  →  '),
                      TextSpan(text: e.value.split(_arrow).last, style: _value(t, true)),
                    ],
                  ),
                  style: t.label,
                  textAlign: TextAlign.end,
                ),
              ),
            ),
        ],
        if (risks.isNotEmpty) ...[
          const SizedBox(height: UiSpace.sm),
          Wrap(
            spacing: UiSpace.lg,
            runSpacing: UiSpace.xs,
            children: [
              for (final (icon, label, color) in risks)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 6),
                    Text(label, style: t.small.copyWith(color: color)),
                  ],
                ),
            ],
          ),
        ],
        for (final w in warnings) UiNotice(icon: LucideIcons.triangleAlert, text: w, color: c.warning),
      ],
    );
  }

  static TextStyle _value(UiType t, bool emphasis) =>
      t.label.copyWith(color: t.body.color, fontWeight: emphasis ? FontWeight.w600 : FontWeight.w500);
}

/// "Category ............ Food & Dining".
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.small),
          const SizedBox(width: UiSpace.md),
          Expanded(
            child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
          ),
        ],
      ),
    );
  }
}
