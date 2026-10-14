import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// "Split 4 ways · Equally · with you".
String pendingSplitCaption(PendingSplitView s) =>
    'Split ${s.people} ways · ${s.methodLabel}${s.split.includesMe ? ' · with you' : ''}';

/// Top of a split card in the list: the bill, how it was split, and what
/// is still open across everyone.
class PendingSplitHeader extends StatelessWidget {
  const PendingSplitHeader({super.key, required this.split, required this.shown, required this.onTap});

  final PendingSplitView split;

  /// People shown under the current filter.
  final int shown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final s = split;
    final dir = s.direction;
    final open = s.activeCount > 0;
    final tone = open ? dir.color(c) : c.textSecondary;
    final paid = '${s.settledCount} of ${s.members.length} settled';
    final caption = shown < s.members.length ? '${pendingSplitCaption(s)} · $shown shown' : pendingSplitCaption(s);
    return Semantics(
      button: true,
      header: true,
      label: '${s.purpose}. $caption. ${MoneyFormatter.spoken(s.outstanding)} '
          '${dir.isOwe ? 'to pay' : 'to collect'}. $paid',
      excludeSemantics: true,
      child: InkWell(
        key: ValueKey('split-${s.split.id}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x3, Space.x2_5),
          child: Row(
            children: [
              IconTile(
                icon: LucideIcons.users,
                background: open ? dir.soft(c) : c.surfaceMuted,
                foreground: tone,
                size: 32,
                radius: Radii.md,
                iconSize: 16,
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.purpose, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyStrong),
                    Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
                  ],
                ),
              ),
              const SizedBox(width: Space.x2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AmountText(open ? s.outstanding : s.total, style: t.amountSmall.copyWith(color: tone)),
                  Text(open ? paid : 'Bill total', style: t.micro),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// On an item's detail: the bill it is part of, the user's own share, and
/// everyone else in it. Tapping another person opens their item.
class PendingSplitCard extends StatelessWidget {
  const PendingSplitCard({super.key, required this.split, required this.currentId});

  final PendingSplitView split;

  /// The item being viewed.
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final s = split;
    final dir = s.direction;
    final others = s.total - s.split.myShare;
    final bps = others.isPositive ? (s.settled.ratioBps(others) ?? 0).clamp(0, 10000) : 0;
    return FinnCard(
      key: const ValueKey('pending-split-card'),
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x4, Space.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(LucideIcons.users, size: 16, color: c.accentPending),
              const SizedBox(width: Space.x2),
              Expanded(child: Text('Split bill · ${s.people} people', style: t.bodyStrong)),
              StatusPill(label: s.methodLabel, color: c.textSecondary),
            ],
          ),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(child: _Stat(label: 'BILL TOTAL', value: AmountText(s.total, style: t.amountSmall))),
              Expanded(
                child: _Stat(
                  label: 'YOUR SHARE',
                  value: s.split.includesMe
                      ? AmountText(s.split.myShare, style: t.amountSmall)
                      : Text('Not in it', style: t.bodyStrong.copyWith(color: c.textSecondary)),
                ),
              ),
              Expanded(
                child: _Stat(
                  label: dir.isOwe ? 'LEFT TO PAY' : 'LEFT TO COLLECT',
                  value: AmountText(s.outstanding, style: t.amountSmall.copyWith(color: dir.color(c))),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x3),
          ClipRRect(
            borderRadius: Radii.rFull,
            child: LinearProgressIndicator(
              value: bps / 10000,
              minHeight: 6,
              backgroundColor: c.surfaceMuted,
              color: c.positive,
              semanticsLabel: 'Settled across the split',
              semanticsValue: '${bps ~/ 100}%',
            ),
          ),
          const SizedBox(height: Space.x1),
          Text('${s.settledCount} of ${s.members.length} people settled · ${s.settled.format()} back so far',
              style: t.micro),
          const SizedBox(height: Space.x2),
          if (s.split.includesMe) ...[
            _MemberRow(
              name: 'You',
              detail: 'Your own share · not owed',
              amount: AmountText(s.split.myShare, style: t.amountSmall.copyWith(color: c.textSecondary)),
              avatar: PendingAvatar(name: 'Me', color: c.textSecondary, size: 32),
            ),
          ],
          for (final m in s.members)
            _MemberRow(
              key: ValueKey('split-member:${m.payment.id}'),
              name: m.payment.counterparty,
              detail: m.status == PendingStatus.partiallySettled
                  ? '${m.payment.split!.partLabel} · ${m.settledBps ~/ 100}% settled'
                  : m.payment.split!.partLabel,
              shared: m.payment.isShared,
              current: m.payment.id == currentId,
              amount: m.status.isActive
                  ? AmountText(m.outstanding, style: t.amountSmall.copyWith(color: dir.color(c)))
                  : StatusPill(
                      label: m.status.label,
                      color: m.status == PendingStatus.settled ? c.positive : c.textSecondary,
                      icon: m.status == PendingStatus.settled ? LucideIcons.check : LucideIcons.ban,
                    ),
              avatar: PendingAvatar(
                name: m.payment.counterparty,
                color: m.status.isActive ? dir.color(c) : c.textSecondary,
                progress: m.settledBps / 10000,
                size: 32,
              ),
              onTap: m.payment.id == currentId ? null : () => context.push(AppRoutes.pendingItem(m.payment.id)),
            ),
          const SizedBox(height: Space.x1),
          Text('Each person settles on their own. Open someone to settle, remind or edit just their part.',
              style: t.micro),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.eyebrow, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: value),
        ],
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    super.key,
    required this.name,
    required this.detail,
    required this.amount,
    required this.avatar,
    this.shared = false,
    this.current = false,
    this.onTap,
  });

  final String name;
  final String detail;
  final Widget amount;
  final Widget avatar;
  final bool shared;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x1_5, horizontal: Space.x1),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.body.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (shared) ...[
                      const SizedBox(width: Space.x1),
                      Icon(LucideIcons.link2, size: 12, color: c.info),
                    ],
                    if (current) ...[
                      const SizedBox(width: Space.x1_5),
                      StatusPill(label: 'This item', color: c.info),
                    ],
                  ],
                ),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          amount,
          if (onTap != null) ...[
            const SizedBox(width: Space.x1),
            Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(borderRadius: Radii.rMd, onTap: onTap, child: row);
  }
}
