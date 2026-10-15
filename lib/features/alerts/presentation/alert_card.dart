import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../domain/alert.dart';

/// Deep link for the record an alert points to.
String alertRoute(FinancialAlert a) {
  final id = a.recordId;
  return switch (a.target) {
    AlertTarget.loan => id == null ? AppRoutes.loans : AppRoutes.loan(id),
    AlertTarget.pending =>
      id == null ? AppRoutes.pending : AppRoutes.pendingItem(id),
    AlertTarget.subscription =>
      id == null ? AppRoutes.subscriptions : AppRoutes.subscription(id),
    AlertTarget.budget => id == null ? AppRoutes.budgets : AppRoutes.budget(id),
    AlertTarget.emergencyFund => AppRoutes.emergencyFund,
    AlertTarget.goal => id == null ? AppRoutes.goals : AppRoutes.goal(id),
    AlertTarget.transactions => AppRoutes.transactions,
  };
}

/// Severity colours: red urgent, amber soon, green good news, ink for FYI.
extension AlertSeverityStyle on AlertSeverity {
  Color color(LedgerColors c) => switch (this) {
    AlertSeverity.critical => c.red,
    AlertSeverity.warning => c.amber,
    AlertSeverity.info => c.inkSoft,
    AlertSeverity.positive => c.green,
  };
}

/// One alert: what is happening, why, the key figure and one next step.
/// The whole card opens [alertRoute].
class AlertCard extends StatelessWidget {
  const AlertCard({super.key, required this.alert, this.unread = false});

  final FinancialAlert alert;

  /// Shows a small "New" marker.
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final a = alert;
    final hidden = AmountVisibility.hiddenOf(context);
    final fig = _figure(a, c, hidden);
    final bar = _bar(a.visual, c);
    final severity = a.severity.color(c);

    return Semantics(
      container: true,
      button: true,
      onTap: () => context.push(alertRoute(a)),
      label: hidden
          ? '${a.severity.label}. ${a.type.label}. ${a.actionLabel}.'
          : '${a.severity.label}. ${a.title}. ${a.message} ${a.actionLabel}.',
      child: ExcludeSemantics(
        child: Material(
          color: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: Rad.rLg,
            side: BorderSide(color: c.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => context.push(alertRoute(a)),
            child: Padding(
              padding: const EdgeInsets.all(Sp.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(top: 6, right: Sp.sm),
                        decoration: BoxDecoration(
                          color: severity,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          a.title,
                          style: t.bodyStrong,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (fig != null) ...[
                        const SizedBox(width: Sp.md),
                        Text(
                          fig.text,
                          style: t.figure.copyWith(color: fig.color ?? c.ink),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: Sp.xs),
                  Padding(
                    padding: const EdgeInsets.only(left: Sp.lg),
                    child: Text(
                      a.message,
                      style: t.label,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (bar != null) ...[
                    const SizedBox(height: Sp.md),
                    Padding(
                      padding: const EdgeInsets.only(left: Sp.lg),
                      child: bar,
                    ),
                  ],
                  const SizedBox(height: Sp.md),
                  Padding(
                    padding: const EdgeInsets.only(left: Sp.lg),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            a.actionLabel,
                            style: t.labelStrong,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Sp.xs),
                        Icon(LucideIcons.arrowRight, size: 14, color: c.ink),
                        const Spacer(),
                        if (unread)
                          Text(
                            'New',
                            style: t.labelStrong.copyWith(color: c.green),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget? _bar(AlertVisual? v, LedgerColors c) => switch (v) {
    BudgetVisual() => LedgerBar(
      value: v.fraction.clamp(0.0, 1.0),
      color: v.isOver ? c.red : c.amber,
    ),
    SafetyNetVisual(isConfigured: true) => LedgerBar(value: v.fraction),
    GoalVisual(isReached: false, isBehind: false) => LedgerBar(
      value: v.fraction,
    ),
    _ => null,
  };

  /// The one number that matters, in words short enough for a trailing slot.
  static ({String text, Color? color})? _figure(
    FinancialAlert a,
    LedgerColors c,
    bool hidden,
  ) {
    String m(Money v) => hidden ? MoneyFormatter.masked : v.whole;
    final v = a.visual;
    return switch (v) {
      DueVisual() when a.amount != null => (
        text: m(a.amount!),
        color: v.isLate ? c.red : null,
      ),
      AgedVisual() when a.amount != null => (text: m(a.amount!), color: null),
      BudgetVisual() =>
        v.isOver
            ? (text: '${m(v.spent - v.limit)} over', color: c.red)
            : (text: '${(v.fraction * 100).round()}% used', color: null),
      SafetyNetVisual(isConfigured: true) => (
        text:
            '${(v.coverageMonths ?? 0).toStringAsFixed(1)} of ${v.targetMonths} mo',
        color: null,
      ),
      GoalVisual(isReached: true) => (text: 'Reached', color: c.green),
      GoalVisual(isBehind: true) => (
        text: '${m(v.requiredMonthly!)}/mo',
        color: null,
      ),
      GoalVisual() => (text: '${(v.fraction * 100).round()}%', color: null),
      CashFlowVisual() => (text: '${m(v.gap)} over', color: c.red),
      _ => a.amount == null ? null : (text: m(a.amount!), color: null),
    };
  }
}
