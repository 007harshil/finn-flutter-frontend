import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// "Split 4 ways, equally, with you".
String pendingSplitCaption(PendingSplitView s) =>
    'Split ${s.people} ways, ${s.methodLabel.toLowerCase()}${s.split.includesMe ? ', with you' : ''}';

/// Top of a split bill in the list: the bill, how it was split, and what
/// is still open across everyone. Its people follow as nested rows.
class PendingSplitHeader extends StatelessWidget {
  const PendingSplitHeader({super.key, required this.split, required this.shown, required this.onTap});

  final PendingSplitView split;

  /// People shown under the current filter.
  final int shown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = split;
    final dir = s.direction;
    final open = s.activeCount > 0;
    final paid = '${s.settledCount} of ${s.members.length} settled';
    final caption = shown < s.members.length ? '${pendingSplitCaption(s)}, $shown shown' : pendingSplitCaption(s);
    final side = open ? pendingSideLabel(dir) : 'bill total';
    return LedgerRow(
      key: ValueKey('split-${s.split.id}'),
      leading: const IconWell(icon: LucideIcons.users),
      title: s.purpose,
      subtitle: '$paid, split ${s.people} ways',
      trailing: AmountText(
        open ? s.outstanding : s.total,
        style: t.figure.copyWith(color: pendingAmountColor(context, dir, active: open)),
      ),
      trailingSub: Text(side, style: t.small),
      semanticLabel: '${s.purpose}. $caption. ${pendingSpoken(context, s.outstanding)} '
          '${dir.isOwe ? 'to pay' : 'to get'}. $paid',
      onTap: onTap,
    );
  }
}

/// On an item's detail: the bill it is part of, the user's own share, and
/// everyone else in it. Tapping another person opens their item.
class PendingSplitSection extends StatelessWidget {
  const PendingSplitSection({super.key, required this.split, required this.currentId});

  final PendingSplitView split;

  /// The item being viewed.
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final s = split;
    final dir = s.direction;
    final others = s.total - s.split.myShare;
    final share = others.isPositive ? (s.settled.ratioBps(others) ?? 0).clamp(0, 10000) / 10000 : 0.0;
    return LedgerSection(
      key: const ValueKey('pending-split-card'),
      title: 'Split between ${s.people} people',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: LedgerStat(label: 'Bill total', value: AmountText(s.total, style: t.figure))),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerStat(
                  label: 'Your share',
                  value: s.split.includesMe
                      ? AmountText(s.split.myShare, style: t.figure)
                      : Text('Not in it', style: t.figure.copyWith(color: c.inkSoft)),
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: LedgerStat(
                  label: dir.isOwe ? 'Left to pay' : 'Left to get',
                  value: AmountText(s.outstanding, style: t.figure.copyWith(color: pendingAmountColor(context, dir))),
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.lg),
          LedgerBar(value: share, semanticLabel: '${(share * 100).round()}% settled across the split'),
          const SizedBox(height: Sp.sm),
          Text(
            '${s.settledCount} of ${s.members.length} people settled, ${pendingMoney(context, s.settled)} back so far',
            style: t.label,
          ),
          const SizedBox(height: Sp.lg),
          LedgerPanel(
            dividerIndent: Sp.lg + 40 + Sp.md + 2,
            children: [
              if (s.split.includesMe)
                LedgerRow(
                  leading: const IconWell(icon: LucideIcons.user),
                  title: 'You',
                  subtitle: 'Your own share, not owed',
                  trailing: AmountText(s.split.myShare, style: t.figure.copyWith(color: c.inkSoft)),
                ),
              for (final m in s.members) _member(context, m, dir),
            ],
          ),
          const SizedBox(height: Sp.sm),
          Text('Each person settles their own part.', style: t.label),
        ],
      ),
    );
  }

  Widget _member(BuildContext context, PendingView m, PendingDirection dir) {
    final t = context.type;
    final current = m.payment.id == currentId;
    final part = m.payment.split!.partLabel;
    final String? note = current
        ? 'This item'
        : switch (m.status) {
            PendingStatus.settled => 'settled',
            PendingStatus.cancelled => 'written off',
            _ => null,
          };
    return LedgerRow(
      key: ValueKey('split-member:${m.payment.id}'),
      leading: PendingInitials(name: m.payment.counterparty, shared: m.payment.isShared),
      title: m.payment.counterparty,
      subtitle: m.status == PendingStatus.partiallySettled ? '$part, ${m.settledBps ~/ 100}% settled' : part,
      trailing: AmountText(
        m.status.isActive ? m.outstanding : m.payment.originalAmount,
        style: t.figure.copyWith(color: pendingAmountColor(context, dir, active: m.status.isActive)),
      ),
      trailingSub: note == null ? null : Text(note, style: t.small),
      chevron: !current,
      onTap: current ? null : () => context.push(AppRoutes.pendingItem(m.payment.id)),
    );
  }
}
