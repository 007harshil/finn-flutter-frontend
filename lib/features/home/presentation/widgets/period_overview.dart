import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../finance/ledger.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../transactions/domain/transaction.dart';
import 'home_common.dart';

/// Month selector driving the income and spent figures.
class PeriodOverview extends ConsumerStatefulWidget {
  const PeriodOverview({super.key});

  @override
  ConsumerState<PeriodOverview> createState() => _PeriodOverviewState();
}

class _PeriodOverviewState extends ConsumerState<PeriodOverview> {
  MonthKey? _month;

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(todayProvider.select((d) => d.monthKey));
    var month = _month ?? current;
    if (month > current) month = current;
    return HomeSection(
      icon: LucideIcons.chartColumn,
      title: 'Cash flow',
      subtitle: 'Recorded income and spending',
      tileColor: context.colors.accentTransactions,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MonthSwitcher(
            month: month,
            max: current,
            min: current.shift(-35),
            onChanged: (m) => setState(() => _month = m),
          ),
          const SizedBox(height: Space.x3),
          _MonthFigures(month: month),
        ],
      ),
    );
  }
}

class _MonthFigures extends ConsumerWidget {
  const _MonthFigures({required this.month});

  final MonthKey month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncView<PeriodSummary>(
      value: ref.watch(monthSummaryProvider(month)),
      loading: const SkeletonPulse(
        child: Row(
          children: [
            Expanded(child: CardSkeleton(height: 104)),
            SizedBox(width: Space.x3),
            Expanded(child: CardSkeleton(height: 104)),
          ],
        ),
      ),
      builder: (context, s) {
        final c = context.colors;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(
                label: 'Income',
                icon: LucideIcons.arrowDownLeft,
                accent: c.positive,
                value: AmountText(s.income, decimals: DecimalDisplay.none, color: c.positive, fit: true),
                caption: 'Received',
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.income, month: month)),
              ),
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: StatTile(
                label: 'Spent',
                icon: LucideIcons.arrowUpRight,
                accent: c.negative,
                value: AmountText(s.expense, decimals: DecimalDisplay.none, fit: true),
                caption: 'Paid out',
                onTap: () => context.push(AppRoutes.transactionsFiltered(type: TransactionType.expense, month: month)),
              ),
            ),
          ],
        );
      },
    );
  }
}
