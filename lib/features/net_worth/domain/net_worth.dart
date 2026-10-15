import 'package:flutter/foundation.dart';

import '../../../core/money/money.dart';
import '../../../finance/ledger.dart';
import '../../loans/domain/loan_calculator.dart';
import '../../pending/domain/pending_payment.dart';
import 'asset.dart';

enum NetWorthGroup { cash, assets, receivables, liabilities }

@immutable
class NetWorthLine {
  const NetWorthLine({
    required this.group,
    required this.label,
    required this.amount,
    this.detail,
    this.recordId,
  });

  final NetWorthGroup group;
  final String label;

  /// Positive for assets/receivables/cash, positive magnitude for liabilities.
  final Money amount;
  final String? detail;
  final String? recordId;
}

/// Net worth with a transparent breakdown.
///
/// * Cash is counted once (it already includes earmarked goal and
///   emergency savings — those are shown as a split, not added).
/// * Receivables = money owed to the user (pending + lent loans).
/// * Liabilities = outstanding principal on borrowed loans + pending dues
///   + amounts owed on credit cards (never part of cash).
@immutable
class NetWorthSnapshot {
  const NetWorthSnapshot({
    required this.balance,
    required this.lines,
  });

  final BalanceSnapshot balance;
  final List<NetWorthLine> lines;

  Money _sum(NetWorthGroup g) => Money.sum(lines.where((l) => l.group == g).map((l) => l.amount));

  Money get cash => _sum(NetWorthGroup.cash);
  Money get assets => _sum(NetWorthGroup.assets);
  Money get receivables => _sum(NetWorthGroup.receivables);
  Money get liabilities => _sum(NetWorthGroup.liabilities);
  Money get totalAssets => cash + assets + receivables;
  Money get netWorth => totalAssets - liabilities;

  @override
  bool operator ==(Object other) =>
      other is NetWorthSnapshot &&
      other.balance == balance &&
      other.netWorth == netWorth &&
      other.lines.length == lines.length;

  @override
  int get hashCode => Object.hash(balance, netWorth, lines.length);
}

class NetWorthCalculator {
  const NetWorthCalculator();

  NetWorthSnapshot compute({
    required BalanceSnapshot balance,
    required List<Asset> assets,
    required List<LoanState> loans,
    required List<PendingView> pending,
  }) {
    final lines = <NetWorthLine>[
      NetWorthLine(
        group: NetWorthGroup.cash,
        label: 'Cash & bank (tracked)',
        amount: balance.cash,
        detail: balance.earmarked.isPositive ? 'Includes earmarked savings' : null,
      ),
      for (final a in assets)
        NetWorthLine(group: NetWorthGroup.assets, label: a.name, amount: a.value, detail: a.type.label, recordId: a.id),
    ];
    for (final l in loans) {
      if (l.outstanding.isZero) continue;
      lines.add(NetWorthLine(
        group: l.loan.isBorrowed ? NetWorthGroup.liabilities : NetWorthGroup.receivables,
        label: '${l.loan.name} · ${l.loan.counterparty}',
        amount: l.outstanding,
        detail: 'Outstanding principal',
        recordId: l.loan.id,
      ));
    }
    if (!balance.creditOwed.isZero) {
      lines.add(NetWorthLine(
        group: balance.creditOwed.isPositive ? NetWorthGroup.liabilities : NetWorthGroup.assets,
        label: balance.creditOwed.isPositive ? 'Credit card owed' : 'Credit card credit balance',
        amount: balance.creditOwed.isPositive ? balance.creditOwed : -balance.creditOwed,
        detail: 'Owed on credit cards',
      ));
    }
    final owe = Money.sum(pending.where((p) => p.payment.direction == PendingDirection.iOwe).map((p) => p.outstanding));
    final collect =
        Money.sum(pending.where((p) => p.payment.direction == PendingDirection.owedToMe).map((p) => p.outstanding));
    if (collect.isPositive) {
      lines.add(NetWorthLine(group: NetWorthGroup.receivables, label: 'Pending to collect', amount: collect));
    }
    if (owe.isPositive) {
      lines.add(NetWorthLine(group: NetWorthGroup.liabilities, label: 'Pending to pay', amount: owe));
    }
    return NetWorthSnapshot(balance: balance, lines: lines);
  }
}
