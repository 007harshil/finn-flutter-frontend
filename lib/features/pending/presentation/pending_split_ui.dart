import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart' show AmountText;
import '../../../ui/ui.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// "Split 4 ways · Equally · with you".
String pendingSplitCaption(PendingSplitView s) =>
    'Split ${s.people} ways · ${s.methodLabel}${s.split.includesMe ? ' · with you' : ''}';

/// Top row of a split in the list: the bill, how it was split, and what is
/// still open across everyone.
class PendingSplitHeader extends StatelessWidget {
  const PendingSplitHeader({super.key, required this.split, required this.shown, required this.onTap});

  final PendingSplitView split;

  /// People shown under the current filter.
  final int shown;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = split;
    final open = s.activeCount > 0;
    final caption = shown < s.members.length ? '${pendingSplitCaption(s)} · $shown shown' : pendingSplitCaption(s);
    return UiListRow(
      key: ValueKey('split-${s.split.id}'),
      leading: const UiMark(icon: LucideIcons.users),
      title: s.purpose,
      subtitle: caption,
      semanticLabel:
          '${s.purpose}. $caption. ${MoneyFormatter.spoken(s.outstanding)} '
          '${s.direction.isOwe ? 'to pay' : 'to collect'}. ${s.settledCount} of ${s.members.length} settled',
      trailing: AmountText(
        open ? s.outstanding : s.total,
        decimals: DecimalDisplay.none,
        style: t.figureSmall.copyWith(color: open ? null : c.inkSoft),
      ),
      onTap: onTap,
    );
  }
}

/// On an item's detail: the bill it belongs to (total, the user's share,
/// what is left) and everyone in it. Tapping another person opens theirs.
class PendingSplitCard extends StatelessWidget {
  const PendingSplitCard({super.key, required this.split, required this.currentId});

  final PendingSplitView split;

  /// The item being viewed.
  final String currentId;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final s = split;
    final dir = s.direction;
    return UiPanelList(
      key: const ValueKey('pending-split-card'),
      ruleIndent: 64,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(UiSpace.lg, UiSpace.md, UiSpace.lg, UiSpace.md),
          child: Row(
            children: [
              Expanded(
                child: UiStat(
                  label: 'Bill',
                  value: AmountText(s.total, style: t.figureSmall),
                ),
              ),
              Expanded(
                child: UiStat(
                  label: 'Your share',
                  value: s.split.includesMe
                      ? AmountText(s.split.myShare, style: t.figureSmall)
                      : Text('None', style: t.figureSmall.copyWith(color: c.inkSoft)),
                ),
              ),
              Expanded(
                child: UiStat(
                  end: true,
                  label: dir.isOwe ? 'Left to pay' : 'Left to collect',
                  value: AmountText(s.outstanding, style: t.figureSmall),
                ),
              ),
            ],
          ),
        ),
        for (final m in s.members)
          Builder(
            key: ValueKey('split-member:${m.payment.id}'),
            builder: (context) {
              final current = m.payment.id == currentId;
              final status = pendingStatus(c, m);
              return UiListRow(
                leading: UiInitials(name: m.payment.counterparty),
                title: current ? '${m.payment.counterparty} · this item' : m.payment.counterparty,
                subtitle: '${m.payment.split!.partLabel} · ${status.label}',
                trailing: AmountText(
                  m.status.isActive ? m.outstanding : m.payment.originalAmount,
                  style: t.figureSmall.copyWith(color: m.status.isActive ? null : c.inkSoft),
                ),
                onTap: current ? null : () => context.push(AppRoutes.pendingItem(m.payment.id)),
              );
            },
          ),
      ],
    );
  }
}
