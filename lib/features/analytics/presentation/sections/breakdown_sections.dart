import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../transactions/domain/transaction.dart';
import '../../application/analytics_providers.dart';
import '../insight_charts.dart';
import '../insight_widgets.dart';

/// Indent that lines row dividers up with the text after a 40pt well.
const double _rowIndent = Sp.lg + 40 + Sp.md + 2;

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

/// Categories: one bar of where the money went with a row per category
/// (tap a row to pick it out in the bar), and what changed compared with
/// the previous period.
List<Widget> categoriesSection(InsightsData data) => [
      if (data.categories.isEmpty)
        LedgerEmpty(
          icon: LucideIcons.chartPie,
          title: 'No spending in ${data.periodLabel}',
          message: 'Record an expense and see where your money goes.',
        )
      else
        _WhereItWent(data: data),
      _Changes(data: data),
    ];

class _WhereItWent extends StatefulWidget {
  const _WhereItWent({required this.data});
  final InsightsData data;

  @override
  State<_WhereItWent> createState() => _WhereItWentState();
}

class _WhereItWentState extends State<_WhereItWent> {
  static const _maxParts = 6;
  int? _selected;

  void _toggle(int i) => setState(() => _selected = _selected == i ? null : i);

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final c = context.ink;
    final t = context.type;
    final total = data.current.expense;
    final cats = data.categories;
    final top = cats.take(_maxParts).toList();
    final rest = cats.skip(_maxParts).toList();
    final restTotal = Money.sum(rest.map((x) => x.amount));
    final restShare = restTotal.ratioBps(total) ?? 0;
    final sel = _selected;

    Color partColor(int i, Color own) => sel == null || sel == i ? own : c.lineStrong;
    final names = [for (final s in top) s.name, if (restTotal.isPositive) 'Everything else'];
    final amounts = [for (final s in top) s.amount, if (restTotal.isPositive) restTotal];
    final shares = [for (final s in top) s.shareBps, if (restTotal.isPositive) restShare];
    final readout = sel == null || sel >= names.length
        ? data.categoryHeadline
        : '${names[sel]}: ${moneyText(context, amounts[sel])}, ${formatBps(shares[sel], decimals: 0)} of spending';

    return LedgerSection(
      title: 'Where it went',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(liveRegion: true, child: Text(readout, style: t.bodyStrong)),
          const SizedBox(height: Sp.md),
          LedgerStackBar(
            gapColor: c.paper,
            semanticLabel: 'Spending by category: '
                '${[for (var i = 0; i < names.length; i++) '${names[i]} ${formatBps(shares[i], decimals: 0)}'].join(', ')}',
            parts: [
              for (var i = 0; i < top.length; i++) BarPart(top[i].shareBps / 10000, partColor(i, rampColor(c, i))),
              if (restTotal.isPositive) BarPart(restShare / 10000, partColor(top.length, c.sunken)),
            ],
          ),
          const SizedBox(height: Sp.lg),
          LedgerPanel(
            dividerIndent: _rowIndent,
            children: [
              for (var i = 0; i < top.length; i++)
                _ShareRow(
                  leading: CategoryMark(category: top[i].category),
                  title: top[i].name,
                  subtitle: _changeText(top[i].previous, top[i].changeBps, i + 1),
                  amount: top[i].amount,
                  shareBps: top[i].shareBps,
                  swatch: rampColor(c, i),
                  selected: sel == i,
                  onTap: () => _toggle(i),
                ),
              if (restTotal.isPositive)
                _ShareRow(
                  leading: const IconWell(icon: LucideIcons.ellipsis),
                  title: 'Everything else',
                  subtitle: '${rest.length} more categories',
                  amount: restTotal,
                  shareBps: restShare,
                  swatch: c.sunken,
                  selected: sel == top.length,
                  onTap: () => _toggle(top.length),
                ),
            ],
          ),
          if (cats.length > 1) ...[
            const SizedBox(height: Sp.sm),
            Text('Top ${top.length} of ${cats.length} categories by amount. Tap one to pick it out.', style: t.small),
          ],
          HowCalculated(
            text: 'Each category\'s share = its spending ÷ total spending in the period. The change compares '
                'the same category with ${data.previousLabel}. Categories beyond the top $_maxParts are grouped as '
                '"Everything else".',
          ),
        ],
      ),
    );
  }

  static String _changeText(Money? prev, int? change, int rank) {
    if (prev == null) return 'Number $rank';
    if (prev.isZero) return 'New this period';
    if (change == null || change.abs() < 100) return 'About the same as before';
    return '${formatBps(change.abs(), decimals: 0)} ${change < 0 ? 'less' : 'more'} than before';
  }
}

/// A row in a share list: what it is, its amount, and its share with the
/// colour key of its part of the bar.
class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.shareBps,
    required this.swatch,
    this.selected = false,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Money amount;
  final int shareBps;
  final Color swatch;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final pct = formatBps(shareBps, decimals: 0);
    final row = LedgerRow(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: insightAmount(context, amount),
      trailingSub: Row(
        mainAxisSize: MainAxisSize.min,
        children: [InsightSwatch(color: swatch), const SizedBox(width: Sp.sm - 2), Text(pct, style: t.small)],
      ),
      semanticLabel: '$title, ${moneyText(context, amount)}, $pct${subtitle == null ? '' : ', $subtitle'}'
          '${selected ? '. Picked out' : ''}',
      onTap: onTap,
    );
    if (!selected) return row;
    return ColoredBox(color: context.ink.sunken, child: row);
  }
}

/// Diverging bars: which categories went up (right, ink) or down (left,
/// green) compared with the previous period.
class _Changes extends StatelessWidget {
  const _Changes({required this.data});
  final InsightsData data;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final changes = [
      for (final s in data.categories)
        if (s.previous != null && s.amount != s.previous) (s, s.amount - s.previous!),
    ]..sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    final list = changes.take(5).toList();
    final maxAbs = list.isEmpty ? 1.0 : list.first.$2.abs().toDouble();
    final up = Money.sum(changes.where((x) => x.$2.isPositive).map((x) => x.$2));
    final down = Money.sum(changes.where((x) => x.$2.isNegative).map((x) => x.$2.abs()));
    String m(Money x) => moneyText(context, x, compact: true);
    return InsightChartCard(
      heading: 'What changed',
      title: list.isEmpty ? 'Nothing to compare yet' : 'Biggest changes against ${data.previousLabel}',
      subtitle: list.isEmpty
          ? null
          : 'Right = spent more, left = spent less. Up ${m(up)} and down ${m(down)} overall.',
      child: list.isEmpty
          ? const InsightNoData(message: 'Once you have two periods of spending, changes show up here.')
          : Column(
              children: [
                for (final (s, delta) in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: Sp.sm - 2),
                    child: MergeSemantics(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(s.name, style: t.label.copyWith(color: c.ink), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                          const SizedBox(width: Sp.sm),
                          Expanded(child: _Diverging(value: delta.toDouble() / maxAbs)),
                          const SizedBox(width: Sp.sm),
                          SizedBox(
                            width: 68,
                            child: Text(
                              '${delta.isNegative ? '−' : '+'}${m(delta.abs())}',
                              textAlign: TextAlign.end,
                              style: t.labelStrong.copyWith(
                                color: delta.isNegative ? c.green : c.ink,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Diverging extends StatelessWidget {
  const _Diverging({required this.value});

  /// −1 … 1.
  final double value;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    return GrowIn(
      builder: (context, t) => SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, box) {
            final half = box.maxWidth / 2;
            final w = half * value.abs().clamp(0, 1) * t;
            return Stack(
              children: [
                Positioned(left: half - 0.5, top: 0, bottom: 0, child: Container(width: 1, color: c.lineStrong)),
                Positioned(
                  left: value < 0 ? half - w : half,
                  top: 3,
                  bottom: 3,
                  child: Container(
                    width: w,
                    decoration: BoxDecoration(
                      color: value < 0 ? c.green : c.ink,
                      borderRadius: value < 0
                          ? const BorderRadius.horizontal(left: Radius.circular(2))
                          : const BorderRadius.horizontal(right: Radius.circular(2)),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

IconData _methodIcon(PaymentMethod m) => switch (m) {
      PaymentMethod.upi => LucideIcons.smartphone,
      PaymentMethod.card => LucideIcons.creditCard,
      PaymentMethod.cash => LucideIcons.banknote,
      PaymentMethod.bankTransfer => LucideIcons.building2,
      PaymentMethod.wallet => LucideIcons.wallet,
      PaymentMethod.other => LucideIcons.circleDot,
    };

/// Payments: digital against cash, and the split across payment methods.
List<Widget> paymentsSection(BuildContext context, InsightsData data) {
  final c = context.ink;
  final t = context.type;
  final total = data.current.expense;
  final digital = data.digitalShareBps;
  if (digital == null || data.methods.isEmpty) {
    return [
      LedgerEmpty(
        icon: LucideIcons.creditCard,
        title: 'No payments in ${data.periodLabel}',
        message: 'Record expenses with a payment method to see how you pay.',
      ),
    ];
  }
  int share(Money m) => m.ratioBps(total) ?? 0;
  return [
    InsightLead(
      label: 'Paid digitally',
      value: Text(formatBps(digital, decimals: 0), style: t.figureXL),
      sentence: 'Cash covered ${formatBps(10000 - digital, decimals: 0)}. '
          'UPI, cards, bank transfers and wallets make up the rest.',
    ),
    LedgerSection(
      title: 'How you paid',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(data.methodHeadline, style: t.bodyStrong),
          const SizedBox(height: Sp.md),
          LedgerStackBar(
            gapColor: c.paper,
            semanticLabel: data.methods
                .map((m) => '${m.key.label} ${formatBps(share(m.value), decimals: 0)}')
                .join(', '),
            parts: [
              for (var i = 0; i < data.methods.length; i++)
                BarPart(share(data.methods[i].value) / 10000, rampColor(c, i)),
            ],
          ),
          const SizedBox(height: Sp.lg),
          LedgerPanel(
            dividerIndent: _rowIndent,
            children: [
              for (var i = 0; i < data.methods.length; i++)
                _ShareRow(
                  leading: IconWell(icon: _methodIcon(data.methods[i].key)),
                  title: data.methods[i].key.label,
                  subtitle: null,
                  amount: data.methods[i].value,
                  shareBps: share(data.methods[i].value),
                  swatch: rampColor(c, i),
                ),
            ],
          ),
          const HowCalculated(
            text: 'Share = spending through each payment method ÷ total spending. Expenses recorded without '
                'a method are counted as "Other".',
          ),
        ],
      ),
    ),
  ];
}
