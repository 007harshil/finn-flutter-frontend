import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../design_system/design_system.dart';
import '../../execution/proposals.dart';
import 'action_visuals.dart';
import 'agent_logo.dart';

/// Visual review of every change the agent wants to make, built from the
/// app's own previews (never the model's words). Nothing is written until
/// the user approves; each change can be excluded on its own.
class ChangeReviewPanel extends StatefulWidget {
  const ChangeReviewPanel({super.key, required this.proposals, required this.onApprove, required this.onDecline});

  final List<ProposedAction> proposals;
  final ValueChanged<Set<String>> onApprove;
  final VoidCallback onDecline;

  @override
  State<ChangeReviewPanel> createState() => _ChangeReviewPanelState();
}

class _ChangeReviewPanelState extends State<ChangeReviewPanel> {
  late Set<String> _selected = {for (final p in widget.proposals) p.id};
  bool _submitted = false;

  @override
  void didUpdateWidget(ChangeReviewPanel old) {
    super.didUpdateWidget(old);
    if (old.proposals != widget.proposals) {
      _selected = {for (final p in widget.proposals) p.id};
      _submitted = false;
    }
  }

  void _approve() {
    if (_submitted) return;
    setState(() => _submitted = true);
    widget.onApprove(Set.of(_selected));
  }

  void _decline() {
    if (_submitted) return;
    setState(() => _submitted = true);
    widget.onDecline();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final proposals = widget.proposals;
    final many = proposals.length > 1;
    final count = _selected.length;
    final movesMoney = proposals.where((p) => p.descriptor.movesMoney).length;
    final permanent = proposals.where((p) => !p.descriptor.reversible).length;
    final modules = {for (final p in proposals) actionVisualFor(p.descriptor.id, c).module}.length;

    return Semantics(
      container: true,
      label: 'Review proposed changes',
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.xxl),
          border: Border.all(color: c.agentMid.withValues(alpha: 0.45), width: 1.2),
          boxShadow: c.isDark ? Elevation.sm : Elevation.md,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header band in the agent's colours.
            Container(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x4, Space.x4, Space.x3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.agentStart.withValues(alpha: 0.16), c.agentEnd.withValues(alpha: 0.10)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const FinnAgentMark(size: 32),
                      const SizedBox(width: Space.x3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(many ? 'Review ${proposals.length} changes' : 'Review this change',
                                style: t.sectionTitle),
                            Text('Nothing is saved until you approve.',
                                style: t.caption.copyWith(color: c.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.x3),
                  Row(
                    children: [
                      Expanded(child: _ImpactTile(value: '${proposals.length}', label: many ? 'Changes' : 'Change', icon: LucideIcons.listChecks, color: c.agentEnd)),
                      const SizedBox(width: Space.x2),
                      Expanded(child: _ImpactTile(value: '$movesMoney', label: 'Move money', icon: LucideIcons.indianRupee, color: c.attention)),
                      const SizedBox(width: Space.x2),
                      Expanded(
                        child: permanent > 0
                            ? _ImpactTile(value: '$permanent', label: 'Permanent', icon: LucideIcons.lock, color: c.negative)
                            : _ImpactTile(value: '$modules', label: modules == 1 ? 'Area' : 'Areas', icon: LucideIcons.layers, color: c.agentStart),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, 0),
              child: Column(
                children: [
                  for (var i = 0; i < proposals.length; i++) ...[
                    StaggeredEntrance(
                      index: i,
                      child: _ChangeCard(
                        proposal: proposals[i],
                        index: i + 1,
                        selectable: many,
                        selected: _selected.contains(proposals[i].id),
                        onChanged: _submitted
                            ? null
                            : (v) => setState(() => v ? _selected.add(proposals[i].id) : _selected.remove(proposals[i].id)),
                      ),
                    ),
                    const SizedBox(height: Space.x2),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x1, Space.x3, Space.x3),
              child: Row(
                children: [
                  Expanded(
                    child: FinnButton(
                      label: many ? 'Decline all' : 'Decline',
                      variant: FinnButtonVariant.outline,
                      onPressed: _submitted ? null : _decline,
                    ),
                  ),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: FinnButton(
                      label: !many ? 'Approve' : (count == proposals.length ? 'Approve all' : 'Approve $count'),
                      icon: LucideIcons.check,
                      loading: _submitted,
                      onPressed: _submitted || count == 0 ? null : _approve,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImpactTile extends StatelessWidget {
  const _ImpactTile({required this.value, required this.label, required this.icon, required this.color});

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

/// One proposed change: module, what happens, the headline amount, the
/// preview's details and before → after effects.
class _ChangeCard extends StatelessWidget {
  const _ChangeCard({
    required this.proposal,
    required this.index,
    required this.selectable,
    required this.selected,
    this.onChanged,
  });

  final ProposedAction proposal;
  final int index;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onChanged;

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

    final card = AnimatedContainer(
      duration: context.motion.fast,
      padding: const EdgeInsets.all(Space.x3),
      decoration: BoxDecoration(
        color: c.surfaceMuted.withValues(alpha: selectable && !selected ? 0.4 : 1),
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: selectable && selected ? visual.color.withValues(alpha: 0.5) : c.border),
      ),
      child: Column(
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
                        style: t.eyebrow.copyWith(color: visual.color)),
                    const SizedBox(height: 2),
                    Text(preview.summary, style: t.bodyStrong),
                  ],
                ),
              ),
              if (selectable)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Checkbox(
                    value: selected,
                    onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                    semanticLabel: 'Include ${preview.summary}',
                  ),
                ),
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
      ),
    );

    if (!selectable || onChanged == null) return card;
    return PressableScale(onTap: () => onChanged!(!selected), scale: 0.98, child: card);
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
