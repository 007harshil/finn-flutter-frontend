import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/time/dates.dart';
import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../../transactions/domain/transaction.dart';
import '../domain/category.dart';
import 'category_providers.dart';

/// Manage income and expense categories: create, edit, archive.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  TransactionType _type = TransactionType.expense;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(categoryGroupsProvider);
    return AsyncView(
      value: groups,
      loading: Scaffold(
        backgroundColor: context.ink.paper,
        appBar: const LedgerAppBar(title: 'Categories'),
        body: const LedgerPageSkeleton(),
      ),
      builder: (context, data) => _body(context, data),
    );
  }

  Widget _body(BuildContext context, Map<TransactionType, CategoryGroup> data) {
    final group = data[_type]!;
    final noun = _type.label.toLowerCase();
    // Panels share one divider inset: well (40) + gap.
    const indent = Khata.textX;
    Widget panel(List<TransactionCategory> list, {bool dim = false}) => LedgerPanel(
      dividerIndent: indent,
      children: [
        for (final cat in list)
          dim
              ? Opacity(opacity: 0.7, child: _CategoryRow(key: ValueKey(cat.id), category: cat))
              : _CategoryRow(key: ValueKey(cat.id), category: cat),
      ],
    );
    return LedgerPage(
      storageKey: 'categories-list',
      appBar: LedgerAppBar(
        title: 'Categories',
        actions: [
          LedgerButton(
            label: 'New $noun category',
            icon: LucideIcons.plus,
            small: true,
            onPressed: () => context.push(AppRoutes.newCategory(type: _type)),
          ),
        ],
      ),
      slivers: [
        PageBlock(
          top: Sp.sm,
          child: LedgerSegmented<TransactionType>(
            selected: _type,
            onChanged: (v) => setState(() => _type = v),
            segments: [
              LedgerSegment(TransactionType.expense, 'Expense', count: data[TransactionType.expense]!.active.length),
              LedgerSegment(TransactionType.income, 'Income', count: data[TransactionType.income]!.active.length),
            ],
          ),
        ),
        PageBlock(top: Sp.lg, child: _MonthShare(type: _type)),
        if (group.active.isEmpty)
          PageBlock(
            top: Sp.xl,
            child: LedgerEmpty(
              icon: LucideIcons.tags,
              title: 'No $noun categories',
            ),
          )
        else
          PageBlock(top: Sp.lg, child: panel(group.active)),
        if (group.archived.isNotEmpty) ...[
          PageBlock(
            top: Sp.section,
            child: LedgerSection(
              title: 'Archived',
              count: group.archived.length,
              actionLabel: _showArchived ? 'Hide' : 'Show',
              onAction: () => setState(() => _showArchived = !_showArchived),
              child: _showArchived ? panel(group.archived, dim: true) : const SizedBox.shrink(),
            ),
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({super.key, required this.category});

  final TransactionCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = category;
    final count = ref.watch(categoryMonthCountsProvider.select((m) => m[cat.id] ?? 0));
    final usage = count == 0 ? 'Not used this month' : '$count this month';
    return LedgerRow(
      leading: CategoryMark(category: cat),
      title: cat.name,
      subtitle: [
        if (cat.isEssential) 'Essential',
        if (cat.isSystem) 'System',
        usage,
      ].join(' · '),
      chevron: true,
      semanticLabel: [
        cat.name,
        if (cat.isEssential) 'essential',
        if (cat.isSystem) 'system category',
        if (cat.isArchived) 'archived',
        usage,
        'Edit',
      ].join(', '),
      onTap: () => context.push(AppRoutes.editCategory(cat.id)),
    );
  }
}

/// This month's money by category as a donut, with the top five as keys.
class _MonthShare extends ConsumerWidget {
  const _MonthShare({required this.type});

  final TransactionType type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final all = ref.watch(transactionsStreamProvider).value;
    final cats = ref.watch(categoriesByIdProvider).value ?? const {};
    if (all == null) return const SizedBox.shrink();
    final month = MonthKey.fromDate(ref.watch(todayProvider));
    final by = <String, int>{};
    for (final x in all) {
      if (x.type != type || MonthKey.fromDate(x.date) != month) continue;
      by[x.categoryId] = (by[x.categoryId] ?? 0) + x.amount.paise;
    }
    final total = by.values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();
    final top = by.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(5).toList();
    final rest = total - shown.fold<int>(0, (a, e) => a + e.value);
    Color hue(String id) => cats[id] == null ? c.inkSoft : c.tint(cats[id]!.colorIndex).$1;
    final hidden = AmountVisibility.hiddenOf(context);
    return KhataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KhataDonut(
                size: 100,
                stroke: 14,
                parts: [
                  for (final e in shown) BarPart(e.value.toDouble(), hue(e.key)),
                  if (rest > 0) BarPart(rest.toDouble(), c.lineStrong),
                ],
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('${by.length}', style: t.figure.copyWith(fontSize: 20)),
                    Text('used', style: t.small),
                  ],
                ),
              ),
              const SizedBox(width: Sp.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type == TransactionType.expense ? 'Spent this month' : 'Earned this month', style: t.label),
                    const SizedBox(height: 2),
                    AmountText(Money.fromPaise(total), style: t.figureL, decimals: DecimalDisplay.none, fit: true),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          for (final e in shown)
            KhataKey(
              color: hue(e.key),
              label: '${cats[e.key]?.name ?? 'Deleted category'} · ${hidden ? '••' : '${(e.value * 100 / total).round()}%'}',
              value: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
