import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../core/money/money_format.dart';
import '../../../../kit/kit.dart';
import '../../../../shared/presentation/transaction_row.dart' show DateFormatsX;
import '../../domain/transfer.dart';
import '../transfer_form_sheet.dart';

/// A transfer in a list: "SBI → Cash", the amount in plain ink (it is
/// neither money in nor money out). Tap opens the transfer to edit.
class TransferRow extends ConsumerWidget {
  const TransferRow({
    super.key,
    required this.transfer,
    this.showDate = false,
    this.onTap,
  });

  final Transfer transfer;
  final bool showDate;

  /// Defaults to opening the edit sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = transfer;
    final c = context.ink;
    final type = context.type;
    final snapshot = ref.watch(financeSnapshotProvider).value;
    final from = snapshot?.account(t.fromAccountId)?.name ?? 'Account';
    final to = snapshot?.account(t.toAccountId)?.name ?? 'Account';
    final title = '$from → $to';
    final subtitle = [
      'Transfer',
      if ((t.channel ?? '').isNotEmpty) t.channel!,
      if (showDate) DateFormatsX.short(t.date),
    ].join(' · ');
    final spoken = AmountVisibility.hiddenOf(context)
        ? 'amount hidden'
        : MoneyFormatter.spoken(t.amount);
    return LedgerRow(
      leading: IconWell(icon: LucideIcons.arrowLeftRight, color: c.inkSoft),
      title: title,
      subtitle: subtitle,
      trailing: AmountText(
        t.amount,
        style: type.figure.copyWith(color: c.inkSoft),
      ),
      semanticLabel: 'Transfer from $from to $to, $spoken',
      onTap: onTap ?? () => showTransferSheet(context, existing: t),
    );
  }
}
