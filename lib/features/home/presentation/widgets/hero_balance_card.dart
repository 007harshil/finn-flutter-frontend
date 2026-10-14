import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart'
    show FinnButton, FinnDivider, FinnSheetScaffold, InfoBanner, KeyValueRow;
import '../../../../finance/ledger.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/async_view.dart';

/// "Available to spend": the one number Home exists for, set straight on
/// the page. Under it, a bar of your cash with the set-aside part in a
/// lighter tone, and the two amounts that explain the gap. Tapping
/// "Set aside" splits it into goals and emergency fund; tapping the number
/// opens the full maths.
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<BalanceSnapshot>(
      value: ref.watch(balanceProvider),
      loading: const _BalanceSkeleton(),
      builder: (context, b) => _Balance(balance: b),
    );
  }
}

class _Balance extends StatefulWidget {
  const _Balance({required this.balance});

  final BalanceSnapshot balance;

  @override
  State<_Balance> createState() => _BalanceState();
}

class _BalanceState extends State<_Balance> {
  bool _split = false;

  void _toggle() {
    HapticFeedback.selectionClick();
    setState(() => _split = !_split);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final b = widget.balance;
    final hidden = AmountVisibility.hiddenOf(context);
    final over = b.available.isNegative;
    // The bar is cash. When more is set aside than there is cash, the
    // set-aside parts fill it and the overage is called out in words.
    final base = over ? b.earmarked.paise : b.cash.paise;
    double share(Money m) => base <= 0 ? 0 : (m.paise / base).clamp(0.0, 1.0);
    final free = over ? 0.0 : share(b.available);
    final parts = _split
        ? [BarPart(free, c.ink), BarPart(share(b.earmarkedGoals), c.green), BarPart(share(b.earmarkedEmergency), c.inkSoft)]
        : [BarPart(free, c.ink), BarPart(share(b.earmarked), c.lineStrong)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          label: 'Available to spend. Double tap for how it adds up.',
          child: InkWell(
            borderRadius: Rad.rMd,
            onTap: () => showFinnSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: b)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Available to spend', style: t.label),
                    const SizedBox(width: Sp.xs + 2),
                    Icon(LucideIcons.info, size: 15, color: c.inkSoft),
                  ],
                ),
                const SizedBox(height: Sp.xs),
                AnimatedAmount(
                  b.available,
                  style: t.figureXL.copyWith(color: over && !hidden ? c.red : c.ink),
                  decimals: DecimalDisplay.none,
                  fit: true,
                  animateOnMount: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Sp.lg),
        LedgerStackBar(
          parts: parts,
          gapColor: c.paper,
          semanticLabel: hidden ? null : '${(free * 100).round()} percent of your cash is free to spend',
        ),
        const SizedBox(height: Sp.md),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _split
              ? [
                  Expanded(child: _Legend(label: 'For goals', amount: b.earmarkedGoals, dot: c.green, onTap: _toggle)),
                  const SizedBox(width: Sp.lg),
                  Expanded(
                    child: _Legend(
                      label: 'Emergency fund',
                      amount: b.earmarkedEmergency,
                      dot: c.inkSoft,
                      end: true,
                      onTap: _toggle,
                      toggle: LucideIcons.chevronUp,
                    ),
                  ),
                ]
              : [
                  Expanded(child: _Legend(label: 'Cash', amount: b.cash, dot: c.ink)),
                  const SizedBox(width: Sp.lg),
                  Expanded(
                    child: _Legend(
                      label: 'Set aside',
                      amount: b.earmarked,
                      dot: c.lineStrong,
                      end: true,
                      onTap: b.earmarked.isPositive ? _toggle : null,
                      toggle: b.earmarked.isPositive ? LucideIcons.chevronDown : null,
                    ),
                  ),
                ],
        ),
        if (over && !hidden) ...[
          const SizedBox(height: Sp.md),
          LedgerNote(
            tone: NoteTone.alert,
            icon: LucideIcons.triangleAlert,
            text: '${MoneyFormatter.format(-b.available, decimals: DecimalDisplay.none)} more is set aside than you have in cash.',
          ),
        ],
      ],
    );
  }
}

/// Dot, label and amount under the bar. Tappable ones toggle the split.
class _Legend extends StatelessWidget {
  const _Legend({
    required this.label,
    required this.amount,
    required this.dot,
    this.end = false,
    this.onTap,
    this.toggle,
  });

  final String label;
  final Money amount;
  final Color dot;
  final bool end;
  final VoidCallback? onTap;
  final IconData? toggle;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final ic = toggle;
    final body = Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: Sp.xs + 2),
            Flexible(child: Text(label, style: t.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (ic != null) ...[const SizedBox(width: 2), Icon(ic, size: 15, color: c.inkSoft)],
          ],
        ),
        const SizedBox(height: 2),
        AmountText(
          amount,
          style: t.figure.copyWith(fontSize: 17),
          decimals: DecimalDisplay.none,
          fit: true,
          textAlign: end ? TextAlign.end : null,
        ),
      ],
    );
    final tap = onTap;
    if (tap == null) return MergeSemantics(child: body);
    return Semantics(
      button: true,
      hint: 'Splits set-aside money into goals and emergency fund',
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: tap, child: body),
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LedgerSkeleton(width: 120, height: 14),
        SizedBox(height: Sp.sm),
        LedgerSkeleton(width: 220, height: 42),
        SizedBox(height: Sp.lg),
        LedgerSkeleton(height: 8, radius: 4),
        SizedBox(height: Sp.md),
        LedgerSkeleton(width: 160, height: 36),
      ],
    );
  }
}

/// Explains how "available to spend" is derived from the ledger.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool strong = false, Color? color}) {
      return KeyValueRow(
        label: label,
        valueWidget: AmountText(amount, sign: sign, color: color, style: strong ? t.figure : t.figureSmall.copyWith(color: c.ink)),
      );
    }

    return FinnSheetScaffold(
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is earmarked so you do not spend it by accident.',
      footer: FinnButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: c.green),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const FinnDivider(),
          line('Cash', balance.cash, strong: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const FinnDivider(),
          line('Available to spend', balance.available, strong: true),
          const SizedBox(height: Sp.lg),
          const InfoBanner(
            message: 'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
          ),
        ],
      ),
    );
  }
}
