import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../finance/finance_snapshot.dart';
import '../../budgets/domain/budget.dart';
import '../../emergency_fund/domain/emergency_fund.dart';
import '../../pending/domain/pending_payment.dart';
import '../../settings/domain/app_settings.dart';
import '../../subscriptions/domain/subscription.dart';
import 'alert.dart';

/// Generates the "What needs attention" list from a [FinanceSnapshot].
///
/// All alert logic lives here (never in screens). Output is deterministic
/// for a given snapshot + settings, sorted by severity, then due date.
class AlertEngine {
  const AlertEngine();

  List<FinancialAlert> generate(FinanceSnapshot s, AppSettings settings) {
    final out = <FinancialAlert>[];
    void add(FinancialAlert a) {
      if (settings.isAlertEnabled(a.type)) out.add(a);
    }

    final today = s.today;
    String fmt(Money m) => m.format(decimals: DecimalDisplay.none);
    String when(DateTime d) => DateFormats.dueIn(d, today);

    // Loans: overdue and upcoming instalments.
    for (final l in s.loanStates) {
      final next = l.nextDue;
      if (next == null || l.loan.status.name == 'closed') continue;
      final days = daysBetween(today, next.dueDate);
      final borrowed = l.loan.isBorrowed;
      final what = l.loan.isAmortizing ? 'EMI' : 'Interest';
      if (days < 0) {
        add(
          FinancialAlert(
            key: 'loan_overdue:${l.loan.id}:${next.number}',
            type: AlertType.emiOverdue,
            severity: borrowed ? AlertSeverity.critical : AlertSeverity.warning,
            title: borrowed
                ? '$what of ${fmt(next.payment)} is overdue'
                : '${l.loan.counterparty} has not paid ${fmt(next.payment)}',
            message: '${l.loan.name} · ${l.loan.counterparty} — ${when(next.dueDate)}.',
            reason: borrowed
                ? 'Late payments can attract penalties and affect your credit score.'
                : 'Following up early keeps the arrangement on track.',
            actionLabel: borrowed ? 'Record payment' : 'Record receipt',
            target: AlertTarget.loan,
            recordId: l.loan.id,
            dueDate: next.dueDate,
            amount: next.payment,
            dismissible: false,
            visual: DueVisual(
              outgoing: borrowed,
              party: borrowed ? DueParty.bank : DueParty.person,
              counterparty: l.loan.counterparty,
              daysUntil: days,
            ),
          ),
        );
      } else if (days <= settings.emiReminderDays) {
        add(
          FinancialAlert(
            key: 'loan_due:${l.loan.id}:${next.number}',
            type: AlertType.emiDue,
            severity: AlertSeverity.warning,
            title: borrowed
                ? '$what of ${fmt(next.payment)} ${when(next.dueDate)}'
                : 'Repayment from ${l.loan.counterparty} ${when(next.dueDate)}',
            message:
                '${l.loan.name} · ${l.loan.counterparty}. '
                '${fmt(next.interest)} interest + ${fmt(next.principal)} principal.',
            reason: borrowed
                ? 'Keep ${fmt(next.payment)} available so the payment goes through.'
                : 'Expect ${fmt(next.payment)} to come in.',
            actionLabel: 'View loan',
            target: AlertTarget.loan,
            recordId: l.loan.id,
            dueDate: next.dueDate,
            amount: next.payment,
            visual: DueVisual(
              outgoing: borrowed,
              party: borrowed ? DueParty.bank : DueParty.person,
              counterparty: l.loan.counterparty,
              daysUntil: days,
            ),
          ),
        );
      }
    }

    // Pending obligations: informative only, never "late". An item shows up
    // once it has been open longer than PendingView.longPendingDays.
    for (final p in s.pendingViews) {
      if (!p.isLongPending) continue;
      final owe = p.payment.direction == PendingDirection.iOwe;
      final who = p.payment.counterparty;
      add(
        FinancialAlert(
          key: 'pending_aged:${p.payment.id}',
          type: owe ? AlertType.pendingOwed : AlertType.collectOwed,
          severity: AlertSeverity.info,
          title: owe ? 'You owe $who ${fmt(p.outstanding)}' : '$who owes you ${fmt(p.outstanding)}',
          message: owe
              ? 'You have not paid $who back yet. ${p.daysOpen} days have passed · ${p.payment.purpose}.'
              : '$who has not returned your money. ${p.daysOpen} days have passed · ${p.payment.purpose}.',
          reason: owe
              ? 'There is no deadline. Settle it when you can.'
              : 'There is no deadline. The longest-waiting items are the ones to ask about first.',
          actionLabel: owe ? 'Settle now' : 'View details',
          target: AlertTarget.pending,
          recordId: p.payment.id,
          amount: p.outstanding,
          visual: AgedVisual(counterparty: who, daysOpen: p.daysOpen, outgoing: owe),
        ),
      );
    }

    // Subscriptions: overdue (expected but not marked paid) and renewals.
    for (final sub in s.subscriptions) {
      if (!sub.isActive) continue;
      final state = FinanceSnapshot.subscriptionCalc.dueState(sub, today, soonDays: settings.subscriptionReminderDays);
      if (state == DueState.overdue) {
        add(
          FinancialAlert(
            key: 'sub_overdue:${sub.id}:${J2.d(sub.nextDueDate)}',
            type: AlertType.subscriptionOverdue,
            severity: AlertSeverity.warning,
            title: '${sub.name} payment not recorded',
            message: '${fmt(sub.amount)} was ${when(sub.nextDueDate)}.',
            reason: 'Mark it paid if it was charged, or skip this cycle, so your balance stays accurate.',
            actionLabel: 'Review',
            target: AlertTarget.subscription,
            recordId: sub.id,
            dueDate: sub.nextDueDate,
            amount: sub.amount,
            visual: DueVisual(
              outgoing: true,
              party: DueParty.service,
              counterparty: sub.name,
              daysUntil: daysBetween(today, sub.nextDueDate),
              recurring: true,
            ),
          ),
        );
      } else if (state == DueState.dueToday || state == DueState.dueSoon) {
        add(
          FinancialAlert(
            key: 'sub_due:${sub.id}:${J2.d(sub.nextDueDate)}',
            type: AlertType.subscriptionRenewal,
            severity: AlertSeverity.info,
            title: '${sub.name} renews ${_inDays(daysBetween(today, sub.nextDueDate))}',
            message: '${fmt(sub.amount)} · ${sub.frequency.label}.',
            reason: 'Still using it? Pause or cancel before it charges.',
            actionLabel: 'Manage',
            target: AlertTarget.subscription,
            recordId: sub.id,
            dueDate: sub.nextDueDate,
            amount: sub.amount,
            visual: DueVisual(
              outgoing: true,
              party: DueParty.service,
              counterparty: sub.name,
              daysUntil: daysBetween(today, sub.nextDueDate),
              recurring: true,
            ),
          ),
        );
      }
    }

    // Budgets.
    for (final u in s.budgetUsages) {
      if (u.health != BudgetHealth.breached && u.health != BudgetHealth.warning) continue;
      if (u.period.end.isBefore(today)) continue;
      final name = s.category(u.budget.categoryId)?.name ?? 'A budget';
      final breached = u.health == BudgetHealth.breached;
      add(
        FinancialAlert(
          key: 'budget:${u.budget.id}:${J2.d(u.period.start)}:${breached ? 'b' : 'w'}',
          type: breached ? AlertType.budgetBreached : AlertType.budgetNearLimit,
          severity: breached ? AlertSeverity.critical : AlertSeverity.warning,
          title: breached
              ? '$name is over budget by ${fmt(u.remaining.abs())}'
              : '$name has used ${formatBps(u.utilizationBps, decimals: 0)} of its budget',
          message:
              '${fmt(u.spent)} of ${fmt(u.budget.limit)} spent · ${daysBetween(today, u.period.end) + 1} days left in the period.',
          reason: breached
              ? 'Further spending here eats into money meant for other plans.'
              : 'Slowing down now keeps the rest of the period comfortable.',
          actionLabel: 'View budget',
          target: AlertTarget.budget,
          recordId: u.budget.id,
          dueDate: u.period.end,
          amount: u.spent,
          visual: BudgetVisual(
            category: name,
            spent: u.spent,
            limit: u.budget.limit,
            daysLeft: daysBetween(today, u.period.end) + 1,
          ),
        ),
      );
    }

    // Emergency fund.
    final ef = s.emergency;
    if (ef.level == EmergencyFundLevel.notConfigured) {
      if (!s.isFreshUser) {
        add(
          const FinancialAlert(
            key: 'ef_not_set',
            visual: SafetyNetVisual(),
            type: AlertType.emergencyFundNotSet,
            severity: AlertSeverity.info,
            title: 'Set up your emergency fund',
            message: 'Decide how many months of essential expenses you want protected.',
            reason: 'A safety buffer keeps a surprise bill from becoming debt.',
            actionLabel: 'Set up',
            target: AlertTarget.emergencyFund,
          ),
        );
      }
    } else if (ef.coverageTenths != null && ef.coverageTenths! < settings.lowEmergencyCoverageMonths * 10) {
      add(
        FinancialAlert(
          key: 'ef_low:${today.monthKey}',
          type: AlertType.emergencyFundLow,
          severity: ef.level == EmergencyFundLevel.critical ? AlertSeverity.warning : AlertSeverity.info,
          title: 'Emergency fund covers ${ef.coverageMonths!.toStringAsFixed(1)} months',
          message: '${fmt(ef.saved)} saved of ${fmt(ef.target)} target · ${fmt(ef.remaining)} to go.',
          reason: 'Your target is ${ef.plan!.targetMonths} months of essentials. Small regular top-ups get you there.',
          actionLabel: 'Add to fund',
          target: AlertTarget.emergencyFund,
          visual: SafetyNetVisual(
            saved: ef.saved,
            target: ef.target,
            coverageMonths: ef.coverageMonths,
            targetMonths: ef.plan!.targetMonths,
          ),
        ),
      );
    }

    // Goals: milestones and schedule risk.
    for (final g in s.goalProgress) {
      if (g.goal.status.name != 'active') continue;
      if (g.isAchieved) {
        add(
          FinancialAlert(
            key: 'goal_done:${g.goal.id}',
            type: AlertType.goalMilestone,
            severity: AlertSeverity.positive,
            title: '${g.goal.name} is fully funded',
            message: '${fmt(g.saved)} saved — target reached.',
            reason: 'Nice work. The money stays earmarked until you use or release it.',
            actionLabel: 'View goal',
            target: AlertTarget.goal,
            recordId: g.goal.id,
            visual: GoalVisual(name: g.goal.name, saved: g.saved, target: g.goal.target),
          ),
        );
      } else if (g.onTrack == false &&
          g.goal.targetDate != null &&
          g.requiredMonthly != null &&
          daysBetween(today, g.goal.targetDate!) <= 365) {
        add(
          FinancialAlert(
            key: 'goal_risk:${g.goal.id}:${today.monthKey}',
            type: AlertType.goalAtRisk,
            severity: AlertSeverity.info,
            title: '${g.goal.name} may miss its date',
            message:
                'About ${fmt(g.requiredMonthly!)} a month is needed to finish by '
                '${DateFormats.monthYear.format(g.goal.targetDate!)}.',
            reason: 'Adjusting the amount or date now keeps the plan realistic.',
            actionLabel: 'Review goal',
            target: AlertTarget.goal,
            recordId: g.goal.id,
            dueDate: g.goal.targetDate,
            visual: GoalVisual(
              name: g.goal.name,
              saved: g.saved,
              target: g.goal.target,
              requiredMonthly: g.requiredMonthly,
              targetDate: g.goal.targetDate,
            ),
          ),
        );
      } else if (g.progressBps >= 7500) {
        add(
          FinancialAlert(
            key: 'goal_75:${g.goal.id}',
            type: AlertType.goalMilestone,
            severity: AlertSeverity.positive,
            title: '${g.goal.name} is ${formatBps(g.progressBps, decimals: 0)} funded',
            message: '${fmt(g.remaining)} left to reach ${fmt(g.goal.target)}.',
            reason: 'You are in the final stretch.',
            actionLabel: 'Contribute',
            target: AlertTarget.goal,
            recordId: g.goal.id,
            visual: GoalVisual(name: g.goal.name, saved: g.saved, target: g.goal.target),
          ),
        );
      }
    }

    // Month-to-date deficit.
    final month = s.monthSummary(s.currentMonth);
    if (month.income.isPositive && month.expense > month.income) {
      add(
        FinancialAlert(
          key: 'deficit:${s.currentMonth}',
          type: AlertType.monthlyDeficit,
          severity: AlertSeverity.warning,
          title: 'Spending is ${fmt(month.expense - month.income)} above income this month',
          message: '${fmt(month.expense)} spent vs ${fmt(month.income)} received so far.',
          reason: 'Running a deficit draws down your savings.',
          actionLabel: 'See spending',
          target: AlertTarget.transactions,
          visual: CashFlowVisual(income: month.income, expense: month.expense),
        ),
      );
    }

    out.sort((a, b) {
      final c = a.severity.rank.compareTo(b.severity.rank);
      if (c != 0) return c;
      final ad = a.dueDate, bd = b.dueDate;
      if (ad != null && bd != null) {
        final dc = ad.compareTo(bd);
        if (dc != 0) return dc;
        return a.key.compareTo(b.key); // total order: independent of input order
      }
      if (ad != null) return -1;
      if (bd != null) return 1;
      return a.key.compareTo(b.key);
    });
    return out;
  }
}

String _inDays(int d) => d <= 0
    ? 'today'
    : d == 1
    ? 'tomorrow'
    : 'in $d days';

/// Small date-key helper for alert keys.
abstract final class J2 {
  static String d(DateTime d) => DateFormats.iso.format(d);
}
