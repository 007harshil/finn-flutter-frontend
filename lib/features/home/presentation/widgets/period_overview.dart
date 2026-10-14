import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart' show AmountText, AmountVisibility;
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../transactions/domain/transaction.dart';
import '../../../../ui/ui.dart';

final DateFormat _monthLabel = DateFormat('MMMM yyyy');

/// Money in vs money out for one month, on one shared scale, and what was
/// kept. Arrows (or a sideways swipe) step through the last three years;
/// each figure opens its transactions.
class PeriodOverview extends ConsumerStatefulWidget {
  const PeriodOverview({super.key});

  @override
  ConsumerState<PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends ConsumerState<PeriodOverview> {
  MonthKey? _month;

  void _go(MonthKey to, MonthKey min, MonthKey max) {
    if (to < min || to > max) return;
    if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.selectionClick();
    setState(() => _month = to);
  }

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final today = ref.watch(todayProvider);
    final current = today.monthKey;
    final min = current.shift(-35);
    var month = _month ?? current;
    if (month > current) month = current;
    final isCurrent = month == current;
    void go(MonthKey to) => _go(to, min, current);

    return UiSection(
      title: isCurrent ? 'This month' : _monthLabel.format(month.start),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Step(
            icon: LucideIcons.chevronLeft,
            tooltip: 'Previous month',
            onPressed: month > min ? () => go(month.previous) : null,
          ),
          _Step(
            icon: LucideIcons.chevronRight,
            tooltip: 'Next month',
            onPressed: isCurrent ? null : () => go(month.next),
          ),
        ],
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -200) go(month.next);
          if (v > 200) go(month.previous);
        },
        child: UiPanel(
          child: AsyncView<PeriodSummary>(
            value: ref.watch(monthSummaryProvider(month)),
            loading: const Padding(padding: EdgeInsets.all(UiSpace.lg), child: UiPlaceholder(height: 104)),
            builder: (context, s) => AnimatedSwitcher(
              duration: UiMotion.of(context).normal,
              child: _Flow(key: ValueKey(month), summary: s, month: month, isCurrent: isCurrent, colors: c),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final tap = onPressed;
    if (tap == null) {
      return Semantics(
        button: true,
        enabled: false,
        label: tooltip,
        excludeSemantics: true,
        child: SizedBox.square(
          dimension: UiSpace.touch,
          child: Icon(icon, size: 18, color: c.hairline),
        ),
      );
    }
    return UiIconButton(icon: icon, tooltip: tooltip, size: 18, color: c.inkSoft, onPressed: tap);
  }
}

class _Flow extends StatelessWidget {
  const _Flow({super.key, required this.summary, required this.month, required this.isCurrent, required this.colors});

  final PeriodSummary summary;
  final MonthKey month;
  final bool isCurrent;
  final UiColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final income = summary.income;
    final expense = summary.expense;
    final top = income.paise > expense.paise ? income.paise : expense.paise;
    double share(Money m) => top <= 0 ? 0 : m.paise / top;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Figure(
                label: 'Income',
                amount: income,
                share: share(income),
                bar: c.positive,
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
              ),
            ),
            Container(width: 1, height: 56, color: c.hairline),
            Expanded(
              child: _Figure(
                label: 'Spent',
                amount: expense,
                share: share(expense),
                bar: c.ink,
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
              ),
            ),
          ],
        ),
        const UiRule(indent: UiSpace.lg),
        _Result(summary: summary, isCurrent: isCurrent),
      ],
    );
  }
}

/// Label, figure and a bar on the shared scale. Opens the transactions.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.amount,
    required this.share,
    required this.bar,
    required this.onTap,
  });

  final String label;
  final Money amount;
  final double share;
  final Color bar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final m = UiMotion.of(context);
    return Semantics(
      button: true,
      hint: 'Opens these transactions',
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(UiSpace.lg, 14, UiSpace.lg, UiSpace.lg),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: t.small),
                const SizedBox(height: UiSpace.xs),
                AmountText(amount, style: t.figure, decimals: DecimalDisplay.none, fit: true),
                const SizedBox(height: 10),
                ExcludeSemantics(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: share.clamp(0.0, 1.0)),
                    duration: m.settle,
                    curve: UiMotion.ease,
                    builder: (context, v, _) => Container(
                      height: 4,
                      decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(2)),
                      alignment: AlignmentDirectional.centerStart,
                      child: FractionallySizedBox(
                        widthFactor: v,
                        heightFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: bar, borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Kept ₹12,000 · 24% of income", or "Overspent ₹3,000".
class _Result extends StatelessWidget {
  const _Result({required this.summary, required this.isCurrent});

  final PeriodSummary summary;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final net = summary.net;
    final hidden = AmountVisibility.hiddenOf(context);
    Widget wrap(Widget child) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: UiSpace.lg, vertical: 14),
      child: child,
    );
    if (summary.income.isZero && summary.expense.isZero) {
      return wrap(Text(isCurrent ? 'Nothing recorded yet' : 'Nothing recorded', style: t.label));
    }
    final kept = !net.isNegative;
    final color = kept ? c.positive : c.negative;
    final income = summary.income;
    final pct = income.isPositive && kept && !hidden ? (net.paise / income.paise * 100).round() : null;
    return wrap(
      MergeSemantics(
        child: Row(
          children: [
            Icon(kept ? LucideIcons.arrowDownToLine : LucideIcons.triangleAlert, size: 16, color: color),
            const SizedBox(width: UiSpace.sm),
            Text(kept ? 'Kept' : 'Overspent', style: t.label.copyWith(color: c.ink)),
            if (pct != null) ...[const SizedBox(width: 6), Text('· $pct% of income', style: t.small)],
            const SizedBox(width: UiSpace.sm),
            Expanded(
              child: AmountText(
                net.abs(),
                style: t.figureSmall.copyWith(color: color),
                decimals: DecimalDisplay.none,
                fit: true,
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
