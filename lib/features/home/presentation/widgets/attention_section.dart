import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../alerts/domain/alert.dart';
import '../../../alerts/presentation/alert_card.dart' show alertRoute;
import '../../application/upcoming.dart';

/// The most urgent alerts as plain rows. Hidden when nothing needs the
/// user: an empty "all clear" block would only push useful things down.
class AttentionSection extends ConsumerWidget {
  const AttentionSection({super.key});

  static const maxShown = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(activeAlertsProvider).value;
    if (alerts == null || alerts.isEmpty) return const SizedBox.shrink();
    final c = context.ink;
    return Padding(
      padding: const EdgeInsets.only(top: Sp.section),
      child: LedgerSection(
        title: 'Needs attention',
        count: alerts.length,
        actionLabel: alerts.length > maxShown ? 'See all' : null,
        onAction: () => context.push(AppRoutes.alerts),
        child: LedgerPanel(
          dividerIndent: Sp.lg + 40 + Sp.md + 2,
          children: [
            for (final a in alerts.take(maxShown))
              LedgerRow(
                key: ValueKey(a.key),
                leading: IconWell(
                  icon: _icon(a.severity),
                  color: switch (a.severity) {
                    AlertSeverity.critical => c.red,
                    AlertSeverity.warning => c.amber,
                    AlertSeverity.positive => c.green,
                    AlertSeverity.info => c.ink,
                  },
                  background: switch (a.severity) {
                    AlertSeverity.critical => c.redSoft,
                    AlertSeverity.warning => c.amberSoft,
                    AlertSeverity.positive => c.greenSoft,
                    AlertSeverity.info => null,
                  },
                ),
                title: a.title,
                subtitle: a.message,
                semanticLabel: '${a.severity.label}: ${a.title}. ${a.message}',
                titleLines: 2,
                subtitleLines: 2,
                chevron: true,
                onTap: () => context.push(alertRoute(a)),
              ),
          ],
        ),
      ),
    );
  }

  static IconData _icon(AlertSeverity s) => switch (s) {
    AlertSeverity.critical => LucideIcons.circleAlert,
    AlertSeverity.warning => LucideIcons.clock,
    AlertSeverity.info => LucideIcons.info,
    AlertSeverity.positive => LucideIcons.check,
  };
}

/// EMIs, repayments and subscriptions due in the next 7 days (overdue
/// ones first), with the total to keep ready. Hidden when nothing is due.
class UpcomingSection extends ConsumerStatefulWidget {
  const UpcomingSection({super.key});

  static const visibleRows = 4;

  static String routeFor(UpcomingItem i) => switch (i.kind) {
    UpcomingKind.loanPayment || UpcomingKind.loanReceipt => AppRoutes.loan(i.recordId),
    UpcomingKind.subscription => AppRoutes.subscription(i.recordId),
  };

  @override
  ConsumerState<UpcomingSection> createState() => _UpcomingSectionState();
}

class _UpcomingSectionState extends ConsumerState<UpcomingSection> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(upcomingCommitmentsProvider).value;
    if (o == null || o.items.isEmpty) return const SizedBox.shrink();
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final shown = _all ? o.items : o.items.take(UpcomingSection.visibleRows).toList();
    final more = o.items.length - shown.length;
    final n = o.outflowCount;
    String money(Money m) => hidden ? MoneyFormatter.masked : MoneyFormatter.format(m, decimals: DecimalDisplay.none);
    final summary = [
      if (n > 0) 'Keep ${money(o.toArrange)} ready for $n ${n == 1 ? 'payment' : 'payments'}.',
      if (o.expectedIn.isPositive) '${money(o.expectedIn)} expected in.',
    ].join(' ');

    return Padding(
      padding: const EdgeInsets.only(top: Sp.section),
      child: LedgerSection(
        title: 'Next 7 days',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (summary.isNotEmpty) ...[
              Text(summary, style: t.label),
              const SizedBox(height: Sp.md),
            ],
            LedgerPanel(
              dividerIndent: Sp.lg + 40 + Sp.md + 2,
              children: [
                for (final i in shown)
                  LedgerRow(
                    key: ValueKey('${i.kind.name}_${i.recordId}_${i.date.millisecondsSinceEpoch}'),
                    leading: IconWell(
                      icon: i.kind == UpcomingKind.subscription ? LucideIcons.repeat : LucideIcons.landmark,
                      color: i.isOverdue ? c.red : null,
                      background: i.isOverdue ? c.redSoft : null,
                    ),
                    title: i.title,
                    subtitle: '${i.kind.label}, ${_due(i.daysUntil)}',
                    subtitleColor: i.isOverdue ? c.red : null,
                    trailing: AmountText(
                      i.isInflow ? i.amount : -i.amount,
                      style: t.figure.copyWith(color: i.isInflow ? c.green : c.ink),
                      sign: i.isInflow ? SignDisplay.always : SignDisplay.never,
                      decimals: DecimalDisplay.none,
                    ),
                    onTap: () => context.push(UpcomingSection.routeFor(i)),
                  ),
                if (more > 0)
                  LedgerRow(
                    title: 'Show $more more',
                    leading: const IconWell(icon: LucideIcons.chevronDown),
                    onTap: () => setState(() => _all = true),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _due(int days) => switch (days) {
    < -1 => '${-days} days overdue',
    -1 => '1 day overdue',
    0 => 'due today',
    1 => 'due tomorrow',
    _ => 'in $days days',
  };
}
