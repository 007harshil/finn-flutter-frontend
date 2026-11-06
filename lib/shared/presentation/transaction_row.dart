import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../core/money/money_format.dart';
import '../../features/transactions/domain/transaction.dart';
import '../../kit/kit.dart';

/// One transaction in a list: category mark, what it was, and the signed
/// amount (income green, spending ink). Sits inside a panel. Rebuilds
/// only when this transaction or its category changes (the category is
/// selected individually).
class TransactionRow extends ConsumerWidget {
  const TransactionRow({super.key, required this.transaction, this.onTap, this.showDate = false, this.forAccount});

  final Transaction transaction;

  /// Defaults to opening the transaction.
  final VoidCallback? onTap;

  /// Show the date in the subtitle (for lists not grouped by date).
  final bool showDate;

  /// In an account's list: show only the part of a split payment that
  /// moved through this account.
  final String? forAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transaction;
    final c = context.ink;
    final type = context.type;
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final date = showDate ? DateFormatsX.short(t.date) : null;
    final part = t.isSplit && forAccount != null ? t.amountOn(forAccount!) : t.amount;
    final subtitle = [
      if (t.displayTitle != null && category != null) category.name,
      if (t.isSplit)
        forAccount != null
            ? 'Part of ${AmountVisibility.hiddenOf(context) ? MoneyFormatter.masked : AmountText.formatted(t.amount)}'
            : 'Split · ${t.legs.length} accounts',
      ?date,
    ].join(', ');
    final amount = t.isIncome ? part : -part;
    final spoken = AmountVisibility.hiddenOf(context) ? 'amount hidden' : MoneyFormatter.spoken(part);
    return LedgerRow(
      leading: CategoryMark(category: category),
      title: title,
      subtitle: subtitle.isEmpty ? null : subtitle,
      trailing: AmountText(
        amount,
        sign: SignDisplay.always,
        style: type.figure.copyWith(color: t.isIncome ? c.green : c.ink),
      ),
      semanticLabel: '$title, ${t.type.label}, $spoken${date == null ? '' : ', $date'}',
      onTap: onTap ?? () => context.push(AppRoutes.transaction(t.id)),
    );
  }
}

/// Small date helpers for rows.
abstract final class DateFormatsX {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String short(DateTime d) => '${d.day} ${_months[d.month - 1]}';
}
