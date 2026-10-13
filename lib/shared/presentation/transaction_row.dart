import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../core/money/money_format.dart';
import '../../design_system/design_system.dart' show AmountText;
import '../../ui/ui.dart';
import '../../features/transactions/domain/transaction.dart';
import 'category_icons.dart';

/// One transaction in a list (a row of a kit panel): category mark, title,
/// quiet detail line and the signed amount. Income reads green; spending
/// stays ink. Rebuilds only when this transaction or its category changes.
class TransactionRow extends ConsumerWidget {
  const TransactionRow({super.key, required this.transaction, this.onTap, this.showDate = false});

  final Transaction transaction;
  final VoidCallback? onTap;

  /// Show the date in the subtitle (for lists not grouped by date).
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final c = UiColors.of(context);
    final type = UiType.of(context);
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final subtitle = <String>[
      if (t.displayTitle != null && category != null) category.name,
      if (showDate) DateFormatsX.short(t.date),
      if (t.paymentMethod != null) t.paymentMethod!.label,
    ].join(' · ');
    final mark = UiMark(icon: CategoryIcons.of(category?.iconKey), color: t.isIncome ? c.positive : null);
    return UiListRow(
      leading: t.isLinked
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                mark,
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
                    child: Icon(LucideIcons.link2, size: 11, color: c.inkSoft),
                  ),
                ),
              ],
            )
          : mark,
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      semanticLabel: '$title, ${t.type.label}, ${MoneyFormatter.spoken(t.amount)}',
      chevron: false,
      trailing: AmountText(
        t.isIncome ? t.amount : -t.amount,
        sign: t.isIncome ? SignDisplay.always : SignDisplay.auto,
        style: type.figureSmall.copyWith(color: t.isIncome ? c.positive : c.ink),
      ),
      onTap: onTap ?? () => context.push(AppRoutes.transaction(t.id)),
    );
  }
}

/// Small date helpers for rows.
abstract final class DateFormatsX {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String short(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}
