import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../core/money/money_format.dart';
import '../../design_system/design_system.dart';
import '../../features/transactions/domain/transaction.dart';
import 'category_icons.dart';

/// One transaction in a list. Rebuilds only when this transaction or its
/// category changes (category is selected individually).
class TransactionRow extends ConsumerWidget {
  const TransactionRow({super.key, required this.transaction, this.onTap, this.showDate = false});

  final Transaction transaction;
  final VoidCallback? onTap;

  /// Show the date in the subtitle (for lists not grouped by date).
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final c = context.colors;
    final text = context.text;
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final subtitleParts = <String>[
      if (t.displayTitle != null && category != null) category.name,
      if (showDate) DateFormatsX.short(t.date),
      if (t.paymentMethod != null) t.paymentMethod!.label,
    ];
    final amount = t.isIncome ? t.amount : -t.amount;
    return Semantics(
      button: true,
      label: '$title, ${t.type.label}, ${MoneyFormatter.spoken(t.amount)}',
      excludeSemantics: true,
      child: PressableScale(
        scale: 0.985,
        onTap: onTap ?? () => context.push(AppRoutes.transaction(t.id)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2_5, horizontal: Space.x1),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CategoryAvatar(category: category, size: 40),
                  if (t.isLinked)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                        child: Icon(LucideIcons.link2, size: 11, color: c.textSecondary),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyStrong),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(subtitleParts.join(' · '),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: text.caption),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Space.x3),
              AmountText(
                amount,
                sign: SignDisplay.always,
                style: text.amountMedium.copyWith(color: t.isIncome ? c.positive : c.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small date helpers for rows.
abstract final class DateFormatsX {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String short(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}
