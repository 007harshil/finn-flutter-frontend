import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
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
      ],
    );
  }
}

/// The one number, then what is owned and owed beside it.
class _Hero extends StatelessWidget {
  const _Hero({required this.view});
  final NetWorthView view;

  /// Light group hues that read on the slab.
  static Color _slab(NetWorthGroup g) => switch (g) {
        NetWorthGroup.cash => Slab.cool,
        NetWorthGroup.assets => Slab.lilac,
        NetWorthGroup.receivables => Slab.warn,
        NetWorthGroup.liabilities => Slab.bad,
      };

  @override
  Widget build(BuildContext context) {
    final s = view.snapshot;
    final ratio = view.debtRatioBps;
    final hidden = AmountVisibility.hiddenOf(context);
    final own = s.totalAssets.paise;
    final owe = s.liabilities.paise;
    return BahiSlab(
      leading: LucideIcons.scale,
      label: 'Net worth',
      figure: SlabFigure(s.netWorth, color: s.netWorth.isNegative ? Slab.bad : null),
      stamp: SlabStamp(
        label: s.netWorth.isNegative ? 'In the red' : 'In the black',
        tone: s.netWorth.isNegative ? SlabTone.bad : SlabTone.good,
      ),
      // Debts against what you own.
      visual: SlabRing(
        value: own <= 0 ? 0 : owe / own,
        size: 96,
        color: Slab.bad,
        top: hidden || ratio == null ? '—' : formatBps(ratio, decimals: 0),
        bottom: 'owed',
      ),
      stats: [
        SlabStat.money(label: 'You own', amount: s.totalAssets),
        SlabStat.money(label: 'You owe', amount: s.liabilities, color: Slab.bad),
      ],
      footer: view.slices.isEmpty
          ? null
          : SlabBar(
              height: 10,
              parts: [for (final x in view.slices) (x.fraction, _slab(x.group))],
              semanticLabel: 'What you own by group',
            ),
    );
  }
}

/// One hue per group (share, not good or bad); debts stay red.
Color _sliceColor(LedgerColors c, NetWorthGroup g) => switch (g) {
  NetWorthGroup.cash => c.rain,
  NetWorthGroup.assets => c.lilac,
  NetWorthGroup.receivables => c.marigold,
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
    final b = snapshot.balance;
    return LedgerSection(
      title: 'Cash & bank',
      child: StatGrid(
        tiles: [
          StatTile.money(label: 'Total cash', amount: snapshot.cash, icon: LucideIcons.wallet, color: c.rain),
          if (b.earmarked.isPositive) ...[
            StatTile.money(label: 'For goals', amount: b.earmarkedGoals, icon: LucideIcons.target, color: c.lilac),
            StatTile.money(label: 'Emergency fund', amount: b.earmarkedEmergency, icon: LucideIcons.shield, color: c.jade),
            StatTile.money(
              label: 'Free to spend',
              amount: b.available,
              icon: LucideIcons.coins,
              color: b.available.isNegative ? c.red : c.ink,
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
