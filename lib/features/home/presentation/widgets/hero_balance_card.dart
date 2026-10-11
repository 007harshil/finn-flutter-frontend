import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../design_system/design_system.dart';
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';

/// "Available to spend" hero with cash and earmarked money explained.
class HeroBalanceCard extends ConsumerWidget {
  const HeroBalanceCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<BalanceSnapshot>(
      value: ref.watch(balanceProvider),
      loading: const SkeletonPulse(child: CardSkeleton(height: 196, radius: Radii.xxxl)),
      builder: (context, b) => _HeroContent(balance: b),
    );
  }
}

class _HeroContent extends StatelessWidget {
  const _HeroContent({required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    const soft = Colors.white70;
    return GradientHeroCard(
      watermark: LucideIcons.wallet,
      semanticLabel: 'Available to spend. Double tap for the full breakdown.',
      onTap: () => showFinnSheet<void>(context, builder: (_) => BalanceBreakdownSheet(balance: balance)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('AVAILABLE TO SPEND', style: t.eyebrow.copyWith(color: soft)),
              ),
              const Icon(LucideIcons.info, size: 16, color: soft),
            ],
          ),
          const SizedBox(height: Space.x2),
          AnimatedAmount(
            balance.available,
            style: t.amountHero.copyWith(color: Colors.white),
            decimals: DecimalDisplay.none,
            fit: true,
          ),
          const SizedBox(height: Space.x1),
          Text('Your cash, minus money set aside for goals and emergencies.', style: t.caption.copyWith(color: soft)),
          const SizedBox(height: Space.x4),
          Container(height: 1, color: Colors.white12),
          const SizedBox(height: Space.x3),
          Row(
            children: [
              Expanded(
                child: _HeroStat(label: 'Cash · bank & wallet', amount: balance.cash),
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: _HeroStat(label: 'Set aside', amount: balance.earmarked, icon: LucideIcons.lock),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.amount, this.icon});

  final String label;
  final Money amount;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    const soft = Colors.white70;
    final ic = icon;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (ic != null) ...[Icon(ic, size: 11, color: soft), const SizedBox(width: Space.x1)],
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  style: t.micro.copyWith(color: soft, fontWeight: FontWeight.w800),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.x1),
          AmountText(
            amount,
            style: t.amountMedium.copyWith(color: Colors.white),
            decimals: DecimalDisplay.none,
            fit: true,
          ),
        ],
      ),
    );
  }
}

/// Explains how "available to spend" is derived from the ledger.
class BalanceBreakdownSheet extends StatelessWidget {
  const BalanceBreakdownSheet({super.key, required this.balance});

  final BalanceSnapshot balance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    Widget line(String label, Money amount, {SignDisplay sign = SignDisplay.auto, bool strong = false, Color? color}) {
      return KeyValueRow(
        label: label,
        valueWidget: AmountText(amount, sign: sign, color: color, style: strong ? t.amountMedium : t.amountSmall),
      );
    }

    return FinnSheetScaffold(
      title: 'How your balance adds up',
      description: 'Set-aside money is still yours. It is simply earmarked so you do not spend it by accident.',
      footer: FinnButton(label: 'Got it', expand: true, onPressed: () => Navigator.of(context).maybePop()),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          line('Opening balance', balance.openingBalance),
          line('Money in', balance.totalInflow, sign: SignDisplay.always, color: c.positive),
          line('Money out', -balance.totalOutflow, sign: SignDisplay.always),
          const FinnDivider(),
          line('Cash · bank & wallet', balance.cash, strong: true),
          line('Set aside for goals', -balance.earmarkedGoals, sign: SignDisplay.always),
          line('Set aside for emergencies', -balance.earmarkedEmergency, sign: SignDisplay.always),
          const FinnDivider(),
          line('Available to spend', balance.available, strong: true),
          const SizedBox(height: Space.x4),
          const InfoBanner(
            message:
                'Upcoming EMIs, subscriptions and pending payments are not deducted until you record them as paid.',
          ),
        ],
      ),
    );
  }
}
