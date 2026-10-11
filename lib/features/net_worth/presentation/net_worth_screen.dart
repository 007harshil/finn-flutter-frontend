import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/net_worth_view.dart';
import '../domain/net_worth.dart';

/// Net worth: what you own minus what you owe, with a transparent breakdown.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Net worth'),
        actions: [
          FinnIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add asset',
            onPressed: () => context.push(AppRoutes.newAsset),
          ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: AsyncView<NetWorthView>(
        value: ref.watch(netWorthViewProvider),
        loading: const _Skeleton(),
        errorTitle: 'Could not load your net worth',
        builder: (context, view) => _Body(view: view),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) => const SkeletonPulse(
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(),
          child: ResponsiveCenter(
          padding: EdgeInsets.all(Space.gutter),
          child: Column(
            children: [
              CardSkeleton(height: 200, radius: Radii.xxxl),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 150),
              SizedBox(height: Space.x4),
              CardSkeleton(height: 260),
            ],
          ),
        ),
        ),
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      _Hero(view: view),
      if (view.slices.isNotEmpty) _Composition(view: view),
      _CashCard(snapshot: view.snapshot),
      _AssetsSection(view: view),
      if (view.receivables.isNotEmpty)
        _LinesSection(
          title: 'Owed to you',
          subtitle: 'Money others are expected to pay back',
          icon: LucideIcons.handCoins,
          lines: view.receivables,
          liability: false,
        ),
      _LinesSection(
        title: 'What you owe',
        subtitle: 'Outstanding loan principal and pending dues',
        icon: LucideIcons.creditCard,
        lines: view.liabilities,
        liability: true,
      ),
      const InfoBanner(
        tone: FinnTone.info,
        title: 'How this is worked out',
        message: 'Cash is counted once — it already includes money set aside for goals and your emergency fund. '
            'Asset values are your own estimates; update them when they change.',
      ),
    ];
    return CustomScrollView(
      key: const PageStorageKey('net-worth'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10),
          sliver: SliverList.separated(
            itemCount: sections.length,
            separatorBuilder: (_, _) => const SizedBox(height: Space.x5),
            itemBuilder: (context, i) => ResponsiveCenter(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: StaggeredEntrance(index: i, child: sections[i]),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

class _Hero extends StatelessWidget {
  const _Hero({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final s = view.snapshot;
    final white70 = Colors.white.withValues(alpha: 0.72);
    final ratio = view.debtRatioBps;
    return GradientHeroCard(
      watermark: LucideIcons.scale,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NET WORTH', style: t.eyebrow.copyWith(color: white70)),
          const SizedBox(height: Space.x1),
          AnimatedAmount(
            s.netWorth,
            style: t.amountHero.copyWith(color: Colors.white),
            decimals: DecimalDisplay.none,
            fit: true,
          ),
          const SizedBox(height: Space.x1),
          Text('What you own minus what you owe', style: t.caption.copyWith(color: white70)),
          const SizedBox(height: Space.x4),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.16)),
          const SizedBox(height: Space.x4),
          Row(
            children: [
              Expanded(
                child: _HeroStat(label: 'You own', icon: LucideIcons.trendingUp, amount: s.totalAssets),
              ),
              Expanded(
                child: _HeroStat(label: 'You owe', icon: LucideIcons.trendingDown, amount: s.liabilities),
              ),
            ],
          ),
          if (ratio != null && s.liabilities.isPositive) ...[
            const SizedBox(height: Space.x3),
            Text(
              'Debts are ${formatBps(ratio, decimals: 0)} of what you own',
              style: t.caption.copyWith(color: white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.label, required this.icon, required this.amount});
  final String label;
  final IconData icon;
  final Money amount;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: Space.x1),
              Text(label, style: t.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(height: Space.x0_5),
          AmountText(
            amount,
            style: t.amountSmall.copyWith(color: Colors.white),
            decimals: DecimalDisplay.none,
            fit: true,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Composition
// ---------------------------------------------------------------------------

Color _sliceColor(FinnColors c, NetWorthGroup g) => switch (g) {
      NetWorthGroup.cash => c.primary,
      NetWorthGroup.assets => c.positive,
      NetWorthGroup.receivables => c.info,
      NetWorthGroup.liabilities => c.negative,
    };

class _Composition extends StatelessWidget {
  const _Composition({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return FinnCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('What you own', style: t.title),
          const SizedBox(height: Space.x3),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: Radii.rFull,
              child: SizedBox(
                height: 12,
                child: Row(
                  children: [
                    for (var i = 0; i < view.slices.length; i++) ...[
                      if (i > 0) SizedBox(width: 2, child: ColoredBox(color: c.surface)),
                      Expanded(
                        flex: (view.slices[i].fraction * 1000).round().clamp(1, 1000),
                        child: ColoredBox(color: _sliceColor(c, view.slices[i].group)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.x3),
          for (final s in view.slices)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.x1),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _sliceColor(c, s.group), borderRadius: Radii.rSm),
                    ),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(s.label, style: t.body)),
                    Text('${(s.fraction * 100).round()}%', style: t.caption),
                    const SizedBox(width: Space.x3),
                    AmountText(s.amount, style: t.amountSmall, decimals: DecimalDisplay.none),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cash
// ---------------------------------------------------------------------------

class _CashCard extends StatelessWidget {
  const _CashCard({required this.snapshot});
  final NetWorthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final b = snapshot.balance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: LucideIcons.wallet,
          title: 'Cash & bank',
          tileColor: c.primary,
          subtitle: 'Tracked in FiNN from your transactions',
        ),
        const SizedBox(height: Space.x3),
        FinnCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Total cash', style: t.bodyStrong)),
                  AmountText(snapshot.cash, style: t.amountMedium, decimals: DecimalDisplay.none),
                ],
              ),
              if (b.earmarked.isPositive) ...[
                const SizedBox(height: Space.x2),
                const FinnDivider(),
                KeyValueRow(
                  label: 'Set aside for goals',
                  valueWidget: AmountText(b.earmarkedGoals, style: t.amountSmall, decimals: DecimalDisplay.none),
                ),
                KeyValueRow(
                  label: 'Emergency fund',
                  valueWidget: AmountText(b.earmarkedEmergency, style: t.amountSmall, decimals: DecimalDisplay.none),
                ),
                KeyValueRow(
                  label: 'Free to spend',
                  valueWidget: AmountText(
                    b.available,
                    style: t.amountSmall,
                    decimals: DecimalDisplay.none,
                    color: b.available.isNegative ? c.negative : null,
                  ),
                ),
                Text('These are parts of your cash, not added on top.', style: t.caption),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Assets
// ---------------------------------------------------------------------------

class _AssetsSection extends StatelessWidget {
  const _AssetsSection({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: LucideIcons.landmark,
          title: 'Assets',
          tileColor: c.accentNetWorth,
          subtitle: view.assets.isEmpty ? null : 'Your estimates · ${view.snapshot.assets.format(decimals: DecimalDisplay.none)}',
          trailing: view.assets.isEmpty
              ? null
              : TextButton.icon(
                  onPressed: () => context.push(AppRoutes.newAsset),
                  icon: const Icon(LucideIcons.plus, size: 16),
                  label: const Text('Add'),
                ),
        ),
        const SizedBox(height: Space.x3),
        if (view.assets.isEmpty)
          EmptyState(
            icon: LucideIcons.landmark,
            title: 'No assets added yet',
            message: 'Add investments, gold, property or deposits to see your full net worth.',
            actionLabel: 'Add asset',
            actionIcon: LucideIcons.plus,
            onAction: () => context.push(AppRoutes.newAsset),
          )
        else ...[
          if (view.staleCount > 0) ...[
            InfoBanner(
              tone: FinnTone.warning,
              message: view.staleCount == 1
                  ? '1 value is more than 6 months old. Tap it to update.'
                  : '${view.staleCount} values are more than 6 months old. Tap one to update.',
            ),
            const SizedBox(height: Space.x3),
          ],
          FinnCard(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Column(
              children: [
                for (var i = 0; i < view.assets.length; i++) ...[
                  if (i > 0) const FinnDivider(indent: Space.x4 + 40 + Space.x3),
                  _AssetTile(key: ValueKey(view.assets[i].asset.id), row: view.assets[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({super.key, required this.row});
  final AssetRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final a = row.asset;
    return Semantics(
      button: true,
      hint: 'Edit',
      child: InkWell(
        onTap: () => context.push(AppRoutes.editAsset(a.id)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2_5),
            child: Row(
              children: [
                CategoryIconTile(
                  icon: CategoryIcons.of(a.type.iconKey),
                  colorIndex: a.type.index,
                  size: 40,
                  radius: Radii.lg,
                ),
                const SizedBox(width: Space.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: Space.x0_5),
                      Text(
                        '${a.type.label} · valued ${DateFormats.dayMonthYear.format(a.valuedOn)}',
                        style: t.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (row.stale) ...[
                        const SizedBox(height: Space.x1),
                        StatusPill(label: 'Update value', color: c.attention, icon: LucideIcons.clock),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    AmountText(a.value, style: t.amountSmall, decimals: DecimalDisplay.none),
                    Text('${formatBps(row.shareBps, decimals: 0)} of assets', style: t.micro),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receivables & liabilities
// ---------------------------------------------------------------------------

class _LinesSection extends StatelessWidget {
  const _LinesSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.lines,
    required this.liability,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<NetWorthLine> lines;
  final bool liability;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          icon: icon,
          title: title,
          tileColor: liability ? c.negative : c.info,
          subtitle: subtitle,
        ),
        const SizedBox(height: Space.x3),
        if (lines.isEmpty)
          FinnCard(
            variant: FinnCardVariant.muted,
            child: Row(
              children: [
                Icon(LucideIcons.circleCheck, size: 18, color: c.positive),
                const SizedBox(width: Space.x2),
                Expanded(child: Text('Nothing owed right now.', style: t.body)),
              ],
            ),
          )
        else
          FinnCard(
            padding: const EdgeInsets.symmetric(vertical: Space.x1),
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) const FinnDivider(indent: Space.x4),
                  _LineTile(
                    key: ValueKey('${lines[i].label}-${lines[i].recordId}'),
                    line: lines[i],
                    liability: liability,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({super.key, required this.line, required this.liability});
  final NetWorthLine line;
  final bool liability;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final id = line.recordId;
    final route = id != null ? AppRoutes.loan(id) : AppRoutes.pending;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => context.push(route),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2_5),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(line.label, style: t.bodyStrong, maxLines: 2, overflow: TextOverflow.ellipsis),
                      if (line.detail != null) Text(line.detail!, style: t.caption),
                    ],
                  ),
                ),
                const SizedBox(width: Space.x2),
                AmountText(
                  liability ? -line.amount : line.amount,
                  style: t.amountSmall,
                  decimals: DecimalDisplay.none,
                  color: liability ? c.negative : null,
                ),
                const SizedBox(width: Space.x1),
                Icon(LucideIcons.chevronRight, size: 16, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
