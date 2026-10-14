import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/money/money.dart';
import '../../../design_system/luxe/luxe.dart';
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
    final p = context.luxe;
    final t = context.lt;
    final s = split;
    final dir = s.direction;
    final open = s.activeCount > 0;
    final tone = open ? dir.tone(p) : p.inkMute;
    final paid = '${s.settledCount} of ${s.members.length} settled';
    final caption = shown < s.members.length ? '${pendingSplitCaption(s)} · $shown shown' : pendingSplitCaption(s);
    return Semantics(
      button: true,
      header: true,
      label:
          '${s.purpose}. $caption. ${MoneyFormatter.spoken(s.outstanding)} '
          '${dir.isOwe ? 'to pay' : 'to collect'}. $paid',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('split-${s.split.id}'),
          onTap: onTap,
          splashColor: p.gold.withValues(alpha: 0.08),
          child: Container(
            color: p.canvas.withValues(alpha: 0.5),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                LuxeIconDisc(icon: LucideIcons.users, color: tone, size: 42),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.purpose,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.heading.copyWith(fontSize: 15),
                      ),
                      Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    LuxeAmount(open ? s.outstanding : s.total, fit: false, style: t.number.copyWith(color: tone)),
                    Text(open ? paid : 'Bill total', style: t.micro),
                  ],
                ),
              ],
            ),
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
    final p = context.luxe;
    final t = context.lt;
    final s = split;
    final dir = s.direction;
    final others = s.total - s.split.myShare;
    final bps = others.isPositive ? (s.settled.ratioBps(others) ?? 0).clamp(0, 10000) : 0;
    Widget money(Money m, {Color? color}) =>
        LuxeAmount(m, fit: false, style: t.number.copyWith(fontSize: 14, color: color));
    return LuxeCard(
      key: const ValueKey('pending-split-card'),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: LucideIcons.users, color: p.goldInk, size: 36),
              const SizedBox(width: 12),
              Expanded(child: Text('Split bill · ${s.people} people', style: t.heading)),
              LuxeStatus(label: s.methodLabel, color: p.inkSoft),
            ],
          ),
          const SizedBox(height: 16),
          LuxeFigureRow(
            children: [
              LuxeFigure(label: 'Bill total', child: money(s.total)),
              LuxeFigure(
                label: 'Your share',
                child: s.split.includesMe ? money(s.split.myShare) : Text('Not in it', style: t.label.c(p.inkSoft)),
              ),
              LuxeFigure(
                label: dir.isOwe ? 'Left to pay' : 'Left to collect',
                child: money(s.outstanding, color: dir.tone(p)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(
            label: 'Settled across the split',
            value: '${bps ~/ 100}%',
            child: LuxeProgressLine(value: bps / 10000, color: p.positive, height: 5),
          ),
          const SizedBox(height: 4),
          Text(
            '${s.settledCount} of ${s.members.length} people settled · ${s.settled.format()} back so far',
            style: t.micro,
          ),
          const SizedBox(height: 10),
          if (s.split.includesMe)
            _MemberRow(
              name: 'You',
              detail: 'Your own share · not owed',
              amount: money(s.split.myShare, color: p.inkSoft),
              avatar: PendingAvatar(name: 'Me', color: p.inkSoft, size: 34),
            ),
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
                  ? money(m.outstanding, color: dir.tone(p))
                  : LuxeStatus(
                      label: m.status.label,
                      color: m.status == PendingStatus.settled ? p.positive : p.inkMute,
                      icon: m.status == PendingStatus.settled ? LucideIcons.check : LucideIcons.ban,
                    ),
              avatar: PendingAvatar(
                name: m.payment.counterparty,
                color: m.status.isActive ? dir.tone(p) : p.inkMute,
                progress: m.settledBps / 10000,
                size: 34,
              ),
              onTap: m.payment.id == currentId ? null : () => context.push(AppRoutes.pendingItem(m.payment.id)),
            ),
          const SizedBox(height: 8),
          Text(
            'Each person settles on their own. Open someone to settle, remind or edit just their part.',
            style: t.micro,
          ),
        ],
      ),
    );
  }
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
    final p = context.luxe;
    final t = context.lt;
    final row = Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: current
          ? BoxDecoration(color: p.goldSoft.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(14))
          : null,
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.label.w(700).c(p.ink)),
                    ),
                    if (shared) ...[const SizedBox(width: 6), Icon(LucideIcons.link2, size: 12, color: p.info)],
                    if (current) ...[const SizedBox(width: 8), LuxeStatus(label: 'This item', color: p.goldInk)],
                  ],
                ),
                Text(detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: 8),
          amount,
          if (onTap != null) ...[const SizedBox(width: 4), Icon(LucideIcons.chevronRight, size: 15, color: p.inkMute)],
        ],
      ),
    );
    if (onTap == null) return row;
    return Squish(onTap: onTap, scale: 0.98, child: row);
  }
}
