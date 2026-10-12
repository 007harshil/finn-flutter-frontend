import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../design_system/design_system.dart';
import '../../execution/proposals.dart';

/// Review card for the actions the assistant wants to take. Shows the
/// app's own preview of each action (the same text the forms' review sheet
/// shows). All are selected by default; one tap approves them together.
class ApprovalCard extends StatefulWidget {
  const ApprovalCard({super.key, required this.proposals, required this.onApprove, required this.onDecline});

  final List<ProposedAction> proposals;
  final ValueChanged<Set<String>> onApprove;
  final VoidCallback onDecline;

  @override
  State<ApprovalCard> createState() => _ApprovalCardState();
}

class _ApprovalCardState extends State<ApprovalCard> {
  late Set<String> _selected = {for (final p in widget.proposals) p.id};
  bool _submitted = false;

  @override
  void didUpdateWidget(ApprovalCard old) {
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
    final many = widget.proposals.length > 1;
    final count = _selected.length;
    return FinnCard(
      variant: FinnCardVariant.outlined,
      semanticLabel: 'Review proposed actions',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.shieldCheck, size: 18, color: c.primary),
              const SizedBox(width: Space.x2),
              Expanded(
                child: Text(many ? 'Review ${widget.proposals.length} actions' : 'Review this action',
                    style: t.sectionTitle),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          Text('Nothing is saved until you approve.', style: t.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.x3),
          for (final p in widget.proposals) ...[
            _ProposalTile(
              proposal: p,
              selectable: many,
              selected: _selected.contains(p.id),
              onChanged: _submitted
                  ? null
                  : (v) => setState(() => v ? _selected.add(p.id) : _selected.remove(p.id)),
            ),
            const SizedBox(height: Space.x3),
          ],
          Row(
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
                  label: !many ? 'Approve' : (count == widget.proposals.length ? 'Approve all' : 'Approve $count'),
                  icon: LucideIcons.check,
                  loading: _submitted,
                  onPressed: _submitted || count == 0 ? null : _approve,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({required this.proposal, required this.selectable, required this.selected, this.onChanged});

  final ProposedAction proposal;
  final bool selectable;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final preview = proposal.preview;
    final warnings = [...preview.warnings, ...proposal.notes];
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectable)
              Padding(
                padding: const EdgeInsets.only(right: Space.x2),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: selected,
                    onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
                    semanticLabel: 'Include ${preview.summary}',
                  ),
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preview.title, style: t.eyebrow),
                  const SizedBox(height: 2),
                  Text(preview.summary, style: t.bodyStrong),
                ],
              ),
            ),
            if (proposal.descriptor.movesMoney)
              StatusPill(label: 'Moves money', color: c.attention, icon: LucideIcons.arrowLeftRight),
          ],
        ),
        if (preview.lines.isNotEmpty) ...[
          const SizedBox(height: Space.x2),
          for (final l in preview.lines)
            KeyValueRow(label: l.label, value: l.value, valueColor: l.emphasis ? c.textPrimary : null),
        ],
        for (final w in warnings) ...[
          const SizedBox(height: Space.x2),
          InfoBanner(message: w, tone: FinnTone.warning),
        ],
        if (!proposal.descriptor.reversible) ...[
          const SizedBox(height: Space.x2),
          Text('This cannot be undone.', style: t.caption.copyWith(color: c.textSecondary)),
        ],
      ],
    );
    return AnimatedOpacity(
      opacity: selectable && !selected ? 0.55 : 1,
      duration: context.motion.fast,
      child: Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: body,
      ),
    );
  }
}
