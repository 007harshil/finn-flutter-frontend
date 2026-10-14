import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
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
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Categories')),
      body: AsyncView(
        value: groups,
        loading: const Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: SkeletonPulse(child: ListSkeleton(count: 8, rowHeight: 76, padding: EdgeInsets.zero)),
        ),
        builder: (context, data) => _body(context, data),
      ),
    );
  }

  Widget _body(BuildContext context, Map<TransactionType, CategoryGroup> data) {
    final t = context.text;
    final c = context.colors;
    final group = data[_type]!;
    return CustomScrollView(
      key: const PageStorageKey('categories-list'),
      slivers: [
        SliverToBoxAdapter(
          child: ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedTabs<TransactionType>(
                  items: [
                    SegmentItem(TransactionType.expense, 'Expense',
                        count: data[TransactionType.expense]!.active.length),
                    SegmentItem(TransactionType.income, 'Income', count: data[TransactionType.income]!.active.length),
                  ],
                  selected: _type,
                  onChanged: (v) => setState(() => _type = v),
                ),
                const SizedBox(height: Space.x4),
                FinnButton(
                  label: 'New ${_type.label.toLowerCase()} category',
                  icon: LucideIcons.plus,
                  expand: true,
                  onPressed: () => context.push(AppRoutes.newCategory(type: _type)),
                ),
                const SizedBox(height: Space.x3),
                Text(
                  _type == TransactionType.expense
                      ? 'Mark essentials like rent and groceries — they shape your emergency-fund suggestion.'
                      : 'Income categories help you see where your money comes from.',
                  style: t.caption,
                ),
                const SizedBox(height: Space.x3),
              ],
            ),
          ),
        ),
        if (group.active.isEmpty)
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              padding: const EdgeInsets.all(Space.gutter),
              child: EmptyState(
                icon: LucideIcons.tags,
                title: 'No ${_type.label.toLowerCase()} categories',
                message: 'Create one to start organising your ${_type.label.toLowerCase()}.',
              ),
            ),
          )
        else
          SliverList.builder(
            itemCount: group.active.length,
            itemBuilder: (context, i) => ResponsiveCenter(
              key: ValueKey(group.active[i].id),
              padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
              child: _CategoryRow(category: group.active[i]),
            ),
          ),
        if (group.archived.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.x2),
              child: Semantics(
                button: true,
                expanded: _showArchived,
                label: 'Archived categories, ${group.archived.length}',
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: Radii.rLg,
                  onTap: () => setState(() => _showArchived = !_showArchived),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: Dimens.minTouch),
                    child: Row(
                      children: [
                        Icon(LucideIcons.archive, size: 16, color: c.textSecondary),
                        const SizedBox(width: Space.x2),
                        Expanded(child: Text('ARCHIVED (${group.archived.length})', style: t.eyebrow)),
                        Icon(_showArchived ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                            size: 18, color: c.textSecondary),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_showArchived)
            SliverList.builder(
              itemCount: group.archived.length,
              itemBuilder: (context, i) => ResponsiveCenter(
                key: ValueKey(group.archived[i].id),
                padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
                child: Opacity(opacity: 0.7, child: _CategoryRow(category: group.archived[i])),
              ),
            ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: Space.x10)),
      ],
    );
  }
}

class _CategoryRow extends ConsumerWidget {
  const _CategoryRow({required this.category});

  final TransactionCategory category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final cat = category;
    final count = ref.watch(categoryMonthCountsProvider.select((m) => m[cat.id] ?? 0));
    final usage = count == 0 ? 'Not used this month' : '$count this month';
    return FinnCard(
      padding: const EdgeInsets.all(Space.x3),
      semanticLabel: [
        cat.name,
        if (cat.isEssential) 'essential',
        if (cat.isSystem) 'system category',
        if (cat.isArchived) 'archived',
        usage,
        'Edit',
      ].join(', '),
      onTap: () => context.push(AppRoutes.editCategory(cat.id)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CategoryAvatar(category: cat, size: 44),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cat.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (cat.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(cat.description, style: t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: Space.x1_5),
                Wrap(
                  spacing: Space.x1_5,
                  runSpacing: Space.x1,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(usage, style: t.micro.copyWith(color: c.textSecondary)),
                    if (cat.isEssential) StatusPill(label: 'Essential', color: c.positive, icon: LucideIcons.shieldCheck),
                    if (cat.isSystem) StatusPill(label: 'System', color: c.textSecondary, icon: LucideIcons.lock),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.x2),
          Padding(
            padding: const EdgeInsets.only(top: Space.x3),
            child: Icon(LucideIcons.chevronRight, size: 18, color: c.textTertiary),
          ),
        ],
      ),
    );
  }
}
