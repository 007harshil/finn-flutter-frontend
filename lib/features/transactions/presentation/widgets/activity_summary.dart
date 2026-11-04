import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../categories/domain/category.dart';
import '../../application/transaction_filter.dart';
import '../../domain/transaction.dart';
import 'activity_filter_sheet.dart' show amountRangeLabel, originLabel;

/// Most categories named in the "where it went" bar; the rest are "other".
const int _barCategories = 4;

/// Money in and money out for the period without the type filter, so the
/// two figures stay put while they are used to pick a type. Null when no
/// type is chosen (the feed's own totals are then the same thing).
final _untypedFlowProvider = Provider<(Money, Money)?>((ref) {
  final f = ref.watch(transactionFilterProvider);
  if (f.type == null) return null;
  final txs = ref.watch(sortedTransactionsProvider).value;
  final cats = ref.watch(categoriesByIdProvider).value;
  if (txs == null || cats == null) return null;
  final open = f.copyWith(type: () => null);
  final range = f.range;
  var income = 0;
  var expense = 0;
  for (final t in txs) {
    if (!range.contains(t.date) || !t.countsInCashFlowAnalytics) continue;
    if (!TransactionQuery.passes(t, open, cats)) continue;
    if (t.isIncome) {
      income += t.amount.paise;
    } else {
      expense += t.amount.paise;
    }
  }
  return (Money.fromPaise(income), Money.fromPaise(expense));
});

/// The top of Activity: money in and money out (which double as the
/// income / spending switch), one sentence on how the period went, where
/// the money went, and the filters that are on.
class ActivitySummary extends ConsumerWidget {
  const ActivitySummary({super.key, required this.feed});

  final TransactionFeed feed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = feed.filter;
    final cats =
        ref.watch(categoriesByIdProvider).value ??
        const <String, TransactionCategory>{};
    final untyped = ref.watch(_untypedFlowProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final income = untyped?.$1 ?? feed.income;
    final expense = untyped?.$2 ?? feed.expense;
    void pick(TransactionType type) =>
        notifier.setType(f.type == type ? null : type, categories: cats);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlowTabs(
          income: income,
          expense: expense,
          selected: f.type,
          onPick: pick,
        ),
        if (!feed.isEmpty) ...[
          const SizedBox(height: Sp.md),
          _StoryLine(feed: feed),
        ],
        _WhereItWent(feed: feed, cats: cats),
        _ActiveFilters(
          filter: f,
          cats: cats,
          legendIds: _WhereItWent.legendIds(feed),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Money in / money out
// ---------------------------------------------------------------------------

/// Two Bahi cards that read like tabs: tap one to list only that type, tap
/// it again for everything. The chosen one carries an indigo edge.
class _FlowTabs extends StatelessWidget {
  const _FlowTabs({
    required this.income,
    required this.expense,
    required this.selected,
    required this.onPick,
  });

  final Money income;
  final Money expense;
  final TransactionType? selected;
  final ValueChanged<TransactionType> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _FlowTab(
              key: const ValueKey('activity-type:income'),
              label: 'Money in',
              selected: selected == TransactionType.income,
              dimmed: selected == TransactionType.expense,
              amount: AmountText(
                income,
                sign: income.isZero ? SignDisplay.auto : SignDisplay.always,
                decimals: DecimalDisplay.none,
                fit: true,
                style: t.figureL.copyWith(
                  fontSize: 26,
                  color: income.isZero ? c.ink : c.green,
                ),
              ),
              spoken: income,
              onTap: () => onPick(TransactionType.income),
            ),
          ),
          const SizedBox(width: Sp.md),
          Expanded(
            child: _FlowTab(
              key: const ValueKey('activity-type:expense'),
              label: 'Money out',
              selected: selected == TransactionType.expense,
              dimmed: selected == TransactionType.income,
              amount: AmountText(
                expense,
                decimals: DecimalDisplay.none,
                fit: true,
                style: t.figureL.copyWith(fontSize: 26),
              ),
              spoken: expense,
              onTap: () => onPick(TransactionType.expense),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowTab extends StatelessWidget {
  const _FlowTab({
    super.key,
    required this.label,
    required this.amount,
    required this.spoken,
    required this.selected,
    required this.dimmed,
    required this.onTap,
  });

  final String label;
  final Widget amount;
  final Money spoken;
  final bool selected;

  /// The other type is chosen, so these transactions are not listed.
  final bool dimmed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final motion = context.motion;
    final hidden = AmountVisibility.hiddenOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label:
          '$label, ${hidden ? 'amount hidden' : AmountText.spokenLabel(spoken)}',
      hint: selected
          ? 'Showing only these. Double tap to show everything'
          : 'Double tap to show only these',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: motion.fast,
        curve: motion.standard,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Rad.rMd,
          border: Border.all(color: selected ? c.brand : c.line, width: selected ? 2 : 1),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: Rad.rMd,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: AnimatedOpacity(
              opacity: dimmed ? 0.45 : 1,
              duration: motion.fast,
              child: Padding(
                padding: EdgeInsets.fromLTRB(Sp.md, Sp.sm + (selected ? 1 : 2), Sp.md, Sp.sm + (selected ? 1 : 2)),
                child: LedgerStat(label: label, value: amount),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One sentence
// ---------------------------------------------------------------------------

enum _Outcome { kept, overspent, spent, earned, quiet }

/// "Kept ₹56,731, 45% of what came in". Without the amount when balances
/// are hidden ("Kept 45% of what came in").
class _StoryLine extends StatelessWidget {
  const _StoryLine({required this.feed});

  final TransactionFeed feed;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final hidden = AmountVisibility.hiddenOf(context);
    final inc = feed.income;
    final exp = feed.expense;
    final incomeMode = feed.filter.type == TransactionType.income;

    final _Outcome outcome;
    final Money amount;
    String? tail;
    if (incomeMode || (exp.isZero && inc.isPositive)) {
      outcome = _Outcome.earned;
      amount = inc;
      final n = feed.incomeByCategory.length;
      if (n > 1) tail = 'from $n sources';
    } else if (inc.isZero && exp.isZero) {
      outcome = _Outcome.quiet;
      amount = Money.zero;
    } else if (inc.isZero) {
      outcome = _Outcome.spent;
      amount = exp;
      final n = feed.expenseByCategory.length;
      if (n > 1) tail = 'across $n categories';
    } else {
      final pct = (exp.paise * 100 / inc.paise).round();
      if (exp > inc) {
        outcome = _Outcome.overspent;
        amount = exp - inc;
        tail = 'spent $pct% of what came in';
      } else {
        outcome = _Outcome.kept;
        amount = inc - exp;
        tail = '${100 - pct}% of what came in';
      }
    }

    final lead = switch (outcome) {
      _Outcome.kept => 'Kept',
      _Outcome.overspent => 'Overspent',
      _Outcome.spent => 'Spent',
      _Outcome.earned => 'Earned',
      _Outcome.quiet => 'No money moved',
    };
    final figure = outcome == _Outcome.quiet || hidden
        ? null
        : MoneyFormatter.format(amount, decimals: DecimalDisplay.none);
    // A comma only after a figure; "from"/"across" read on without one.
    final joinsWithComma =
        outcome == _Outcome.kept || outcome == _Outcome.overspent;
    final rest = tail == null
        ? ''
        : '${figure != null && joinsWithComma ? ',' : ''} $tail';
    final strong = t.bodyStrong.copyWith(
      color: outcome == _Outcome.overspent ? c.red : c.ink,
    );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: figure == null ? lead : '$lead $figure',
            style: strong,
          ),
          TextSpan(text: rest),
        ],
      ),
      style: t.body.copyWith(color: c.inkSoft),
    );
  }
}

// ---------------------------------------------------------------------------
// Where it went
// ---------------------------------------------------------------------------

/// Monsoon category bars for the biggest categories, each in its own hue
/// with its amount; tapping one filters the list to it.
class _WhereItWent extends ConsumerWidget {
  const _WhereItWent({required this.feed, required this.cats});

  final TransactionFeed feed;
  final Map<String, TransactionCategory> cats;

  /// Categories the legend below the bar already lists (and marks selected
  /// when filtered), so the filter chips do not repeat them.
  static Set<String> legendIds(TransactionFeed feed) {
    final f = feed.filter;
    final incomeMode =
        f.type == TransactionType.income ||
        (feed.expense.isZero && feed.income.isPositive);
    final shares = incomeMode ? feed.incomeByCategory : feed.expenseByCategory;
    if (shares.fold<int>(0, (sum, s) => sum + s.amount.paise) <= 0) {
      return const {};
    }
    return {for (final s in shares.take(_barCategories)) s.categoryId};
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final f = feed.filter;
    final incomeMode =
        f.type == TransactionType.income ||
        (feed.expense.isZero && feed.income.isPositive);
    final shares = incomeMode ? feed.incomeByCategory : feed.expenseByCategory;
    final total = shares.fold<int>(0, (sum, s) => sum + s.amount.paise);
    if (total <= 0) return const SizedBox.shrink();

    final top = shares.take(_barCategories).toList();
    final rest = total - top.fold<int>(0, (sum, s) => sum + s.amount.paise);
    int pct(int paise) => (paise * 100 / total).round();
    String name(String id) => cats[id]?.name ?? 'Deleted category';
    // Each category keeps the colour of its icon well, so the bar, legend
    // and rows below read as one key.
    Color hue(String id) {
      final cat = cats[id];
      return cat == null ? c.inkSoft : c.tint(cat.colorIndex).$1;
    }

    final spoken = [
      for (final s in top)
        '${name(s.categoryId)} ${pct(s.amount.paise)} percent',
      if (rest > 0) 'other ${pct(rest)} percent',
    ].join(', ');
    final title = incomeMode ? 'Where it came from' : 'Where it went';

    final hidden = AmountVisibility.hiddenOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: Sp.lg),
      child: MonsoonCard(
        padding: const EdgeInsets.fromLTRB(Sp.sm + 2, Sp.md, Sp.sm + 2, Sp.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(title, style: t.labelStrong, semanticsLabel: '$title: $spoken'),
            ),
            const SizedBox(height: Sp.xs),
            MonsoonBars(
              bars: [
                for (final s in top)
                  MonsoonBar(
                    name(s.categoryId),
                    s.amount.paise.toDouble(),
                    hue(s.categoryId),
                    key: ValueKey('pulse-legend:${s.categoryId}'),
                    selected: f.categoryIds.contains(s.categoryId),
                    semanticLabel: '${name(s.categoryId)}, ${pct(s.amount.paise)} percent. '
                        '${f.categoryIds.contains(s.categoryId) ? 'Filtered. Double tap to remove' : 'Double tap to show only this'}',
                    trailing: Text.rich(
                      TextSpan(children: [
                        if (!hidden)
                          TextSpan(
                            text: MoneyFormatter.format(s.amount, decimals: DecimalDisplay.none),
                            style: t.figureSmall.copyWith(color: c.ink),
                          ),
                        TextSpan(text: '  ${pct(s.amount.paise)}%', style: t.small),
                      ]),
                    ),
                    onTap: () => ref.read(transactionFilterProvider.notifier).toggleCategory(s.categoryId),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters that are on
// ---------------------------------------------------------------------------

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({
    required this.filter,
    required this.cats,
    required this.legendIds,
  });

  final TransactionFilter filter;
  final Map<String, TransactionCategory> cats;
  final Set<String> legendIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = filter;
    final notifier = ref.read(transactionFilterProvider.notifier);
    String catName(String id) => cats[id]?.name ?? 'Deleted category';

    final hiddenCats = f.categoryIds.difference(legendIds);
    final chips = <(String, String, VoidCallback)>[
      if (f.amount != null)
        ('amount', amountRangeLabel(f.amount), () => notifier.setAmount(null)),
      if (hiddenCats.isEmpty)
        ...const <(String, String, VoidCallback)>[]
      else if (f.categoryIds.length <= 2)
        for (final id in hiddenCats)
          ('cat:$id', catName(id), () => notifier.toggleCategory(id))
      else
        (
          'cats',
          '${f.categoryIds.length} categories',
          () => notifier.setCategories(const {}),
        ),
      if (f.accountIds.length == 1)
        (
          'accounts',
          ref.read(financeSnapshotProvider).value?.account(f.accountIds.single)?.name ?? 'Account',
          () => notifier.setAccounts(const {}),
        )
      else if (f.accountIds.length > 1)
        (
          'accounts',
          '${f.accountIds.length} accounts',
          () => notifier.setAccounts(const {}),
        ),
      if (f.channels.length == 1)
        ('channels', f.channels.single, () => notifier.setChannels(const {}))
      else if (f.channels.length > 1)
        ('channels', '${f.channels.length} channels', () => notifier.setChannels(const {})),
      if (f.origins.length == 1)
        (
          'origins',
          originLabel(f.origins.single),
          () => notifier.setOrigins(const {}),
        )
      else if (f.origins.length > 1)
        (
          'origins',
          '${f.origins.length} sources',
          () => notifier.setOrigins(const {}),
        ),
    ];
    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: Sp.lg),
      child: Wrap(
        spacing: Sp.sm,
        runSpacing: Sp.sm,
        children: [
          for (final (key, label, onRemove) in chips)
            LedgerChip(
              key: ValueKey('active-filter:$key'),
              label: label,
              removable: true,
              semanticLabel: '$label filter. Remove',
              onTap: onRemove,
            ),
        ],
      ),
    );
  }
}
