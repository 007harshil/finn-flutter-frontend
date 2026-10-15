import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
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
    const indent = Sp.lg + 40 + Sp.md + 2;
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
        if (_type == TransactionType.expense)
          const PageBlock(
            top: Sp.lg,
            child: LedgerNote(
              text: 'Mark essentials like rent and groceries. They shape your emergency-fund suggestion.',
            ),
          ),
        if (group.active.isEmpty)
          PageBlock(
            top: Sp.xl,
            child: LedgerEmpty(
              icon: LucideIcons.tags,
              title: 'No $noun categories',
              message: 'Create one to start organising your $noun.',
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
