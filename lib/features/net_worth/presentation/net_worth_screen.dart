import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/net_worth_view.dart';
import '../domain/net_worth.dart';

/// Net worth: what you own minus what you owe, with a transparent breakdown.
class NetWorthScreen extends ConsumerWidget {
  const NetWorthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<NetWorthView>(
      value: ref.watch(netWorthViewProvider),
      loading: Scaffold(
        backgroundColor: context.ink.paper,
        appBar: const LedgerAppBar(title: 'Net worth'),
        body: const LedgerPageSkeleton(),
      ),
      errorTitle: 'Could not load your net worth',
      builder: (context, view) => _Body(view: view),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    return LedgerPage(
      storageKey: 'net-worth',
      appBar: LedgerAppBar(
        title: 'Net worth',
        actions: [
          LedgerIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add asset',
            onPressed: () => context.push(AppRoutes.newAsset),
          ),
        ],
      ),
      slivers: [
        PageBlock(top: Sp.lg, child: _Hero(view: view)),
        if (view.slices.isNotEmpty) PageBlock(top: Sp.section, child: _Composition(view: view)),
        PageBlock(top: Sp.section, child: _CashSection(snapshot: view.snapshot)),
        PageBlock(top: Sp.section, child: _AssetsSection(view: view)),
        if (view.receivables.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: _LinesSection(title: 'Owed to you', lines: view.receivables, liability: false),
          ),
        PageBlock(
          top: Sp.section,
          child: _LinesSection(title: 'What you owe', lines: view.liabilities, liability: true),
        ),
        const PageBlock(
          top: Sp.section,
          child: LedgerNote(
            text: 'Cash is counted once. It already includes money set aside for goals and your emergency fund. '
                'Asset values are your own estimates; update them when they change.',
          ),
        ),
      ],
    );
  }
}

/// The one number, then what is owned and owed beside it.
class _Hero extends StatelessWidget {
  const _Hero({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final s = view.snapshot;
    final ratio = view.debtRatioBps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('What you own minus what you owe', style: t.label),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(s.netWorth, style: t.figureXL, decimals: DecimalDisplay.none, fit: true, animateOnMount: true),
        const SizedBox(height: Sp.lg),
        Row(
          children: [
            Expanded(
              child: LedgerStat(
                label: 'You own',
                value: AmountText(s.totalAssets, style: t.figure, decimals: DecimalDisplay.none, fit: true),
              ),
            ),
            const SizedBox(width: Sp.lg),
            Expanded(
              child: LedgerStat(
                label: 'You owe',
                value: AmountText(s.liabilities, style: t.figure, decimals: DecimalDisplay.none, fit: true),
              ),
            ),
          ],
        ),
        if (ratio != null && s.liabilities.isPositive) ...[
          const SizedBox(height: Sp.md),
          Text('Debts are ${formatBps(ratio, decimals: 0)} of what you own', style: t.label),
        ],
      ],
    );
  }
}

/// Neutral ink steps: the bar shows share, not good or bad.
Color _sliceColor(LedgerColors c, NetWorthGroup g) => switch (g) {
  NetWorthGroup.cash => c.ink,
  NetWorthGroup.assets => c.inkSoft,
  NetWorthGroup.receivables => c.inkFaint,
  NetWorthGroup.liabilities => c.red,
};

class _Composition extends StatelessWidget {
  const _Composition({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return LedgerSection(
      title: 'What you own',
      child: LedgerPanel(
        padding: const EdgeInsets.all(Sp.lg),
        children: [
          LedgerStackBar(
            height: 10,
            parts: [for (final s in view.slices) BarPart(s.fraction, _sliceColor(c, s.group))],
          ),
          const SizedBox(height: Sp.md),
          for (final s in view.slices)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Sp.xs),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: _sliceColor(c, s.group), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: Sp.sm),
                    Expanded(child: Text(s.label, style: t.body)),
                    Text('${(s.fraction * 100).round()}%', style: t.small),
                    const SizedBox(width: Sp.md),
                    AmountText(s.amount, style: t.figureSmall.copyWith(color: c.ink), decimals: DecimalDisplay.none),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CashSection extends StatelessWidget {
  const _CashSection({required this.snapshot});
  final NetWorthSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final b = snapshot.balance;
    AmountText amt(Money money, {Color? color}) =>
        AmountText(money, style: t.figure, decimals: DecimalDisplay.none, color: color);
    return LedgerSection(
      title: 'Cash & bank',
      child: LedgerPanel(
        children: [
          LedgerFact(label: 'Total cash', value: amt(snapshot.cash)),
          if (b.earmarked.isPositive) ...[
            LedgerFact(label: 'Set aside for goals', value: amt(b.earmarkedGoals)),
            LedgerFact(label: 'Emergency fund', value: amt(b.earmarkedEmergency)),
            LedgerFact(
              label: 'Free to spend',
              value: amt(b.available, color: b.available.isNegative ? c.red : null),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssetsSection extends StatelessWidget {
  const _AssetsSection({required this.view});
  final NetWorthView view;

  @override
  Widget build(BuildContext context) {
    if (view.assets.isEmpty) {
      return LedgerSection(
        title: 'Assets',
        child: LedgerEmpty(
          icon: LucideIcons.landmark,
          title: 'No assets added yet',
          message: 'Add investments, gold, property or deposits to see your full net worth.',
          actionLabel: 'Add asset',
          onAction: () => context.push(AppRoutes.newAsset),
        ),
      );
    }
    return LedgerSection(
      title: 'Assets',
      count: view.assets.length,
      actionLabel: 'Add',
      onAction: () => context.push(AppRoutes.newAsset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view.staleCount > 0) ...[
            LedgerNote(
              icon: LucideIcons.clock,
              tone: NoteTone.caution,
              text: view.staleCount == 1
                  ? '1 value is more than 6 months old. Tap it to update.'
                  : '${view.staleCount} values are more than 6 months old. Tap one to update.',
            ),
            const SizedBox(height: Sp.md),
          ],
          LedgerPanel(
            dividerIndent: Sp.lg + 40 + Sp.md + 2,
            children: [for (final r in view.assets) _AssetTile(key: ValueKey(r.asset.id), row: r)],
          ),
        ],
      ),
    );
  }
}

class _AssetTile extends StatelessWidget {
  const _AssetTile({super.key, required this.row});
  final AssetRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final a = row.asset;
    final valued = 'valued ${DateFormats.dayMonthYear.format(a.valuedOn)}';
    return LedgerRow(
      leading: IconWell(icon: CategoryIcons.of(a.type.iconKey)),
      title: a.name,
      subtitle: row.stale ? '${a.type.label}, $valued, update value' : '${a.type.label}, $valued',
      subtitleColor: row.stale ? c.amber : null,
      subtitleLines: 2,
      trailing: AmountText(a.value, style: t.figure, decimals: DecimalDisplay.none),
      trailingSub: Text('${formatBps(row.shareBps, decimals: 0)} of assets', style: t.small),
      semanticLabel: '${a.name}, ${a.type.label}, ${AmountText.spokenLabel(a.value)}, $valued'
          '${row.stale ? ', needs a new value' : ''}, Edit',
      onTap: () => context.push(AppRoutes.editAsset(a.id)),
    );
  }
}

class _LinesSection extends StatelessWidget {
  const _LinesSection({required this.title, required this.lines, required this.liability});

  final String title;
  final List<NetWorthLine> lines;
  final bool liability;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return LedgerSection(
      title: title,
      child: lines.isEmpty
          ? const LedgerNote(icon: LucideIcons.circleCheck, text: 'Nothing owed right now.')
          : LedgerPanel(
              children: [
                for (final line in lines)
                  LedgerRow(
                    key: ValueKey('${line.label}-${line.recordId}'),
                    title: line.label,
                    titleLines: 2,
                    subtitle: line.detail,
                    trailing: AmountText(
                      liability ? -line.amount : line.amount,
                      style: t.figure,
                      decimals: DecimalDisplay.none,
                    ),
                    chevron: true,
                    onTap: () {
                      final id = line.recordId;
                      context.push(id != null ? AppRoutes.loan(id) : AppRoutes.pending);
                    },
                  ),
              ],
            ),
    );
  }
}
