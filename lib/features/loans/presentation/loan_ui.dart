import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../design_system/design_system.dart';
import '../../../kit/kit.dart' hide AmountText, AnimatedAmount, AmountVisibility, BottomClearanceX, MotionAnimatedSize, MotionX, Motion;
import '../../../finance/finance_snapshot.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/loan.dart';
import '../domain/loan_calculator.dart';

/// Presentation helpers for [LoanDirection]: every direction has an icon
/// and a plain-language label, never colour alone.
extension LoanDirectionUi on LoanDirection {
  bool get isBorrowed => this == LoanDirection.borrowed;

  IconData get icon => isBorrowed ? LucideIcons.landmark : LucideIcons.handCoins;

  // Used by the (not yet migrated) loan sheets.
  Color color(FinnColors c) => isBorrowed ? c.negative : c.positive;

  Color soft(FinnColors c) => isBorrowed ? c.negativeSoft : c.positiveSoft;

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
}

final loansOverviewProvider = Provider<AsyncValue<LoansOverview>>(
  (ref) => ref.watch(financeSnapshotProvider).whenData(LoansOverview.of),
);

/// Where a loan's next payment stands: a short sentence, and red only when
/// a payment is overdue.
({String label, Color? color, bool overdue}) loanDueStatus(BuildContext context, LoanState s) {
  final c = context.ink;
  if (s.isClosed) return (label: s.loan.isBorrowed ? 'Repaid' : 'Fully received', color: c.green, overdue: false);
  final days = s.daysUntilNextDue;
  if (days == null) return (label: 'Nothing scheduled', color: null, overdue: false);
  if (days < 0) {
    final n = s.overdueCount;
    return (
      label: n > 1 ? '$n payments overdue' : 'Overdue by ${-days} ${-days == 1 ? 'day' : 'days'}',
      color: c.red,
      overdue: true,
    );
  }
  if (days == 0) return (label: 'Due today', color: null, overdue: false);
  if (days == 1) return (label: 'Due tomorrow', color: null, overdue: false);
  return (label: 'Due in $days days', color: null, overdue: false);
}

/// Amount for inline copy; masked when balances are hidden.
String maskedAmount(BuildContext context, Money amount) =>
    AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(amount);

/// Name of a scheduled payment: "EMI", "Interest" or "Final payment"
/// (interest-only loans repay the principal in their final row).
String loanDueName(Loan loan, ScheduleRow row) =>
    loan.isAmortizing ? 'EMI' : (row.isFinal ? 'Final payment' : 'Interest');

/// Direction pill (icon + label), used by the loan sheets.
class LoanDirectionPill extends StatelessWidget {
  const LoanDirectionPill({super.key, required this.direction});

  final LoanDirection direction;

  @override
  Widget build(BuildContext context) =>
      StatusPill(label: direction.pill, color: direction.color(context.colors), icon: direction.icon);
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
