import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../design_system/luxe/luxe.dart';
import '../../../finance/finance_snapshot.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';

/// Presentation helpers for [LoanDirection]: every direction has an icon
/// and a plain-language label, never colour alone.
extension LoanDirectionUi on LoanDirection {
  bool get isBorrowed => this == LoanDirection.borrowed;

  IconData get icon => isBorrowed ? LucideIcons.landmark : LucideIcons.handCoins;

  Color color(FinnColors c) => isBorrowed ? c.negative : c.positive;

  Color soft(FinnColors c) => isBorrowed ? c.negativeSoft : c.positiveSoft;

  /// Luxe tone: what you owe reads warm-red, what comes back reads green.
  Color tone(LuxePalette p) => isBorrowed ? p.negative : p.positive;

  /// Short pill label.
  String get pill => isBorrowed ? 'Borrowed · I repay' : 'Lent · I receive';

  /// "You owe HDFC Bank" / "Karan owes you".
  String sentence(String who) => isBorrowed ? 'You owe $who' : '$who owes you';

  /// Verb for a repayment in this direction.
  String get repaidVerb => isBorrowed ? 'Repaid' : 'Received';
}

/// Everything the loans screen shows, derived once per snapshot.
@immutable
class LoansOverview {
  const LoansOverview({
    required this.today,
    required this.borrowedOutstanding,
    required this.lentOutstanding,
    required this.dueIn30Days,
    required this.dueIn30DaysCount,
    required this.overdueCount,
    required this.active,
    required this.closed,
  });

  factory LoansOverview.of(FinanceSnapshot s) {
    final active = s.loanStates.where((l) => !l.isClosed).toList()
      ..sort((a, b) {
        final ad = a.nextDue?.dueDate;
        final bd = b.nextDue?.dueDate;
        if (ad == null && bd == null) return a.loan.name.compareTo(b.loan.name);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
    final closed = s.loanStates.where((l) => l.isClosed).toList()
      ..sort((a, b) => b.loan.updatedAt.compareTo(a.loan.updatedAt));
    final horizon = s.today.add(const Duration(days: 30));
    final dueSoon = [
      for (final l in active)
        if (l.loan.isBorrowed && l.nextDue != null && !l.nextDue!.dueDate.isAfter(horizon)) l.nextDue!.payment,
    ];
    return LoansOverview(
      today: s.today,
      borrowedOutstanding: Money.sum(active.where((l) => l.loan.isBorrowed).map((l) => l.outstanding)),
      lentOutstanding: Money.sum(active.where((l) => !l.loan.isBorrowed).map((l) => l.outstanding)),
      dueIn30Days: Money.sum(dueSoon),
      dueIn30DaysCount: dueSoon.length,
      overdueCount: active.where((l) => l.isOverdue).length,
      active: active,
      closed: closed,
    );
  }

  final DateTime today;

  /// Outstanding principal on active borrowed loans.
  final Money borrowedOutstanding;

  /// Outstanding principal on active lent loans.
  final Money lentOutstanding;

  /// Next scheduled instalment of each borrowed loan due within 30 days
  /// (projected, not yet paid).
  final Money dueIn30Days;
  final int dueIn30DaysCount;
  final int overdueCount;
  final List<LoanState> active;
  final List<LoanState> closed;

  bool get isEmpty => active.isEmpty && closed.isEmpty;

  /// Share of borrowed principal already repaid across active loans (0..1).
  double get borrowedRepaidShare {
    final borrowed = active.where((l) => l.loan.isBorrowed);
    final principal = Money.sum(borrowed.map((l) => l.loan.principal));
    final repaid = Money.sum(borrowed.map((l) => l.principalRepaid));
    return ((repaid.ratioBps(principal) ?? 0) / 10000).clamp(0.0, 1.0);
  }
}

final loansOverviewProvider = Provider<AsyncValue<LoansOverview>>(
  (ref) => ref.watch(financeSnapshotProvider).whenData(LoansOverview.of),
);

/// Status of a loan's next due item: label, colour and icon together.
({String label, Color color, IconData icon}) loanDueLabel(BuildContext context, LoanState s) {
  final p = context.luxe;
  if (s.isClosed) {
    return (label: s.loan.isBorrowed ? 'Repaid' : 'Fully received', color: p.positive, icon: LucideIcons.circleCheck);
  }
  final days = s.daysUntilNextDue;
  if (days == null) return (label: 'Nothing scheduled', color: p.inkMute, icon: LucideIcons.calendar);
  if (days < 0) {
    final n = s.overdueCount;
    return (
      label: n > 1 ? '$n overdue' : 'Overdue · ${-days} ${-days == 1 ? 'day' : 'days'}',
      color: s.loan.isBorrowed ? p.negative : p.warning,
      icon: LucideIcons.triangleAlert,
    );
  }
  if (days == 0) return (label: 'Due today', color: p.warning, icon: LucideIcons.bell);
  if (days == 1) return (label: 'Due tomorrow', color: p.warning, icon: LucideIcons.clock);
  if (days <= 7) return (label: 'in $days days', color: p.goldInk, icon: LucideIcons.clock);
  return (label: 'in $days days', color: p.inkMute, icon: LucideIcons.calendar);
}

/// Amount for inline copy; masked when balances are hidden.
String maskedAmount(BuildContext context, Money amount) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(amount);

/// Name of a scheduled payment: "EMI", "Interest" or "Final payment"
/// (interest-only loans repay the principal in their final row).
String loanDueName(Loan loan, ScheduleRow row) =>
    loan.isAmortizing ? 'EMI' : (row.isFinal ? 'Final payment' : 'Interest');

/// Direction pill (icon + label).
class LoanDirectionPill extends StatelessWidget {
  const LoanDirectionPill({super.key, required this.direction, this.onGradient = false});

  final LoanDirection direction;
  final bool onGradient;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    return LuxeStatus(label: direction.pill, color: onGradient ? p.gold : direction.tone(p), icon: direction.icon);
  }
}

/// One loan in the list: who and what, what is left, a repayment line that
/// draws in, the next due item, and — when a payment is due within a week —
/// a one-tap way to record it.
class LoanCard extends StatelessWidget {
  const LoanCard({super.key, required this.state, required this.onTap, this.onPay});

  final LoanState state;
  final VoidCallback onTap;

  /// Shown when a payment is due soon or overdue.
  final VoidCallback? onPay;

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    final s = state;
    final l = s.loan;
    final due = loanDueLabel(context, s);
    final next = s.nextDue;
    final closed = s.isClosed;
    final subtitle = closed
        ? '${l.counterparty} · ${l.structure.label}'
        : (next == null
              ? '${l.counterparty} · ${l.rate.label} p.a.'
              : '${l.counterparty} · ${loanDueName(l, next)} ${maskedAmount(context, next.payment)}');
    final pct = s.repaidBps ~/ 100;
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      radius: LuxeSpace.rTile + 2,
      onTap: onTap,
      semanticLabel:
          '${l.name}, ${l.direction.sentence(l.counterparty)}, '
          'outstanding ${AmountText.spokenLabel(s.outstanding)}, ${due.label}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LuxeIconDisc(icon: l.direction.icon, color: closed ? p.inkMute : l.direction.tone(p), size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.heading),
                    const SizedBox(height: 3),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.caption),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  LuxeAmount(
                    s.outstanding,
                    fit: false,
                    style: t.figure.copyWith(fontSize: 24, color: closed ? p.inkMute : p.ink),
                  ),
                  Text(closed ? 'settled' : 'left', style: t.micro),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          LuxeProgressLine(value: s.repaidBps / 10000, color: closed ? p.positive : p.gold, height: 5),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '$pct% ${l.direction.repaidVerb.toLowerCase()} of ${maskedAmount(context, l.principal)}',
                  style: t.micro,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              LuxeStatus(label: due.label, color: due.color, icon: due.icon),
            ],
          ),
          if (onPay != null && next != null) ...[
            const LuxeHairline(vertical: 14),
            Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: '${loanDueName(l, next)} #${next.number} ', style: t.label.w(700).c(p.ink)),
                        TextSpan(text: '${DateFormats.dueIn(next.dueDate, s.today)} · not yet recorded'),
                      ],
                    ),
                    style: t.caption,
                    maxLines: 2,
                  ),
                ),
                const SizedBox(width: 10),
                LuxeButton(
                  label: l.isBorrowed ? 'Record payment' : 'Record receipt',
                  icon: LucideIcons.check,
                  compact: true,
                  variant: s.isOverdue ? LuxeButtonVariant.gold : LuxeButtonVariant.ink,
                  onPressed: onPay,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Label above a non-text form control.
class LoanFieldLabel extends StatelessWidget {
  const LoanFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Space.x1_5),
    child: Text(text, style: context.text.label),
  );
}

/// Single-select payment method chips.
class LoanMethodChips extends StatelessWidget {
  const LoanMethodChips({super.key, required this.selected, required this.onChanged});

  final PaymentMethod? selected;
  final ValueChanged<PaymentMethod> onChanged;

  static const _icons = {
    PaymentMethod.upi: LucideIcons.smartphone,
    PaymentMethod.card: LucideIcons.creditCard,
    PaymentMethod.cash: LucideIcons.banknote,
    PaymentMethod.bankTransfer: LucideIcons.landmark,
    PaymentMethod.wallet: LucideIcons.wallet,
    PaymentMethod.other: LucideIcons.circleDot,
  };

  @override
  Widget build(BuildContext context) => FilterChipBar<PaymentMethod>(
    padding: EdgeInsets.zero,
    multiSelect: false,
    items: [for (final m in PaymentMethod.values) FilterChipItem(m, m.label, icon: _icons[m])],
    selected: {?selected},
    onChanged: (s) => onChanged(s.first),
  );
}

/// A switch row inside an outlined card, with an explanation underneath.
class LoanSwitchCard extends StatelessWidget {
  const LoanSwitchCard({
    super.key,
    required this.title,
    required this.message,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String message;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return FinnCard(
      variant: FinnCardVariant.outlined,
      padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x2, Space.x2),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.bodyStrong),
                  const SizedBox(height: 2),
                  Text(message, style: t.caption),
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
