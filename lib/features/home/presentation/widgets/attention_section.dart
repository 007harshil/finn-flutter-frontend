import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart' show AmountText;
import '../../../../ui/ui.dart';
import '../../../alerts/domain/alert.dart';
import '../../../alerts/presentation/alert_card.dart' show alertRoute;
import '../../application/upcoming.dart';

/// The few alerts that matter most, as plain rows. Hidden when there is
/// nothing to act on: the bell in the header still leads to every alert.
class AttentionSection extends ConsumerWidget {
  const AttentionSection({super.key});

  static const maxShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(activeAlertsProvider).value;
    if (alerts == null || alerts.isEmpty) return const SizedBox.shrink();
    final shown = alerts.take(maxShown).toList();
    return UiSection(
      title: 'Needs attention',
      action: alerts.length > maxShown ? 'See all ${alerts.length}' : 'See all',
      onAction: () => context.push(AppRoutes.alerts),
      child: UiPanel(
        child: Column(
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const UiRule(indent: 64),
              _AlertRow(key: ValueKey(shown[i].key), alert: shown[i]),
            ],
          ],
        ),
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({super.key, required this.alert});

  final FinancialAlert alert;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final a = alert;
    // Icon shape and the label carry severity too, never colour alone.
    final (icon, color) = switch (a.severity) {
      AlertSeverity.critical => (LucideIcons.circleAlert, c.negative),
      AlertSeverity.warning => (LucideIcons.clock, c.warning),
      AlertSeverity.info => (LucideIcons.info, c.info),
      AlertSeverity.positive => (LucideIcons.circleCheck, c.positive),
    };
    return UiListRow(
      leading: UiMark(icon: icon, color: color),
      title: a.title,
      subtitle: a.severity.label,
      subtitleColor: color,
      semanticLabel: '${a.severity.label}: ${a.title}',
      onTap: () => context.push(alertRoute(a)),
    );
  }
}

/// EMIs and subscriptions due in the next [UpcomingWindow.days] days with
/// the total going out. Shows the soonest few; the rest unfold in place.
/// Hidden when nothing is due.
class UpcomingSection extends ConsumerStatefulWidget {
  const UpcomingSection({super.key});

  static const collapsedRows = 3;

  static String routeFor(UpcomingItem i) => switch (i.kind) {
    UpcomingKind.loanPayment || UpcomingKind.loanReceipt => AppRoutes.loan(i.recordId),
    UpcomingKind.subscription => AppRoutes.subscription(i.recordId),
  };

  @override
  ConsumerState<UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends ConsumerState<UpcomingSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(upcomingCommitmentsProvider).value;
    if (o == null || o.items.isEmpty) return const SizedBox.shrink();
    final t = UiType.of(context);
    final extra = o.items.length - UpcomingSection.collapsedRows;
    final shown = _expanded || extra <= 0 ? o.items : o.items.take(UpcomingSection.collapsedRows).toList();
    return UiSection(
      title: 'Next ${UpcomingWindow.days} days',
      trailing: o.toArrange.isPositive
          ? Padding(
              padding: const EdgeInsets.only(right: UiSpace.sm),
              child: MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AmountText(o.toArrange, style: t.label, decimals: DecimalDisplay.none),
                    Text(' due', style: t.label),
                  ],
                ),
              ),
            )
          : null,
      child: UiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < shown.length; i++) ...[
              if (i > 0) const UiRule(indent: 64),
              _UpcomingRow(
                key: ValueKey('${shown[i].kind.name}_${shown[i].recordId}_${shown[i].date}'),
                item: shown[i],
              ),
            ],
            if (extra > 0) ...[
              const UiRule(indent: UiSpace.lg),
              UiTextButton(
                label: _expanded ? 'Show less' : 'Show $extra more',
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({super.key, required this.item});

  final UpcomingItem item;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final i = item;
    final icon = switch (i.kind) {
      UpcomingKind.loanPayment || UpcomingKind.loanReceipt => LucideIcons.landmark,
      UpcomingKind.subscription => LucideIcons.repeat,
    };
    return UiListRow(
      leading: UiMark(icon: icon),
      title: i.title,
      subtitle: homeDue(i.daysUntil),
      subtitleColor: i.isOverdue ? c.negative : null,
      trailing: AmountText(
        i.isInflow ? i.amount : -i.amount,
        sign: SignDisplay.always,
        decimals: DecimalDisplay.none,
        style: t.figureSmall.copyWith(color: i.isInflow ? c.positive : c.ink),
      ),
      onTap: () => context.push(UpcomingSection.routeFor(i)),
    );
  }
}

/// "Today", "Tomorrow", "In 3 days", "2 days late".
String homeDue(int days) {
  if (days < -1) return '${-days} days late';
  if (days == -1) return '1 day late';
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return 'In $days days';
}
