import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/category_icons.dart';
import '../application/transaction_actions.dart';
import '../domain/transaction.dart';

/// Full details of one transaction. Manual entries can be edited or
/// deleted; linked entries point back to the record that created them.
class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(transactionByIdProvider(id));
    final tx = value.value;
    final manual = tx != null && !tx.isLinked;
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        title: const Text('Transaction'),
        actions: [
          if (manual)
            Padding(
              padding: const EdgeInsets.only(right: Space.x2),
              child: FinnIconButton(
                icon: LucideIcons.pencil,
                tooltip: 'Edit transaction',
                onPressed: () => context.push(AppRoutes.editTransaction(id)),
              ),
            ),
        ],
      ),
      body: AsyncView(
        value: value,
        loading: const Padding(
          padding: EdgeInsets.all(Space.gutter),
          child: SkeletonPulse(
            child: Column(
              children: [
                CardSkeleton(height: 168),
                SizedBox(height: Space.x4),
                CardSkeleton(height: 260),
              ],
            ),
          ),
        ),
        builder: (context, t) => t == null ? const _NotFound() : _Details(transaction: t),
      ),
    );
  }
}

class _NotFound extends StatelessWidget {
  const _NotFound();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.x6),
      child: EmptyState(
        icon: LucideIcons.searchX,
        title: 'Transaction not found',
        message: 'It may have been deleted or changed from another screen.',
        actionLabel: 'Back to activity',
        onAction: () => context.go(AppRoutes.transactions),
      ),
    ),
  );
}

class _Details extends ConsumerStatefulWidget {
  const _Details({required this.transaction});

  final Transaction transaction;

  @override
  ConsumerState<_Details> createState() => _DetailsState();
}

class _DetailsState extends ConsumerState<_Details> {
  final String _deleteKey = newIdempotencyKey();
  bool _deleting = false;

  Future<void> _delete() async {
    if (_deleting) return;
    setState(() => _deleting = true);
    final deleted = await runAction(
      context,
      ref,
      action: const DeleteTransactionAction(),
      input: DeleteTransactionInput(id: widget.transaction.id),
      idempotencyKey: _deleteKey,
      successTitle: 'Transaction deleted',
      successSubtitle: 'Your balances have been updated.',
    );
    if (!mounted) return;
    if (deleted == null) {
      setState(() => _deleting = false);
      return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.transactions);
    }
  }

  String? _sourceRoute(Transaction t) {
    final ref = t.originRefId;
    if (ref == null) return null;
    return switch (t.origin) {
      TransactionOrigin.loanRepayment || TransactionOrigin.loanDisbursement => AppRoutes.loan(ref),
      TransactionOrigin.subscription => AppRoutes.subscription(ref),
      TransactionOrigin.pendingSettlement => AppRoutes.pendingItem(ref),
      TransactionOrigin.manual => null,
    };
  }

  String _sourceName(TransactionOrigin o) => switch (o) {
    TransactionOrigin.loanRepayment || TransactionOrigin.loanDisbursement => 'loan',
    TransactionOrigin.subscription => 'subscription',
    TransactionOrigin.pendingSettlement => 'pending payment',
    TransactionOrigin.manual => 'entry',
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final c = context.colors;
    final text = context.text;
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final accent = t.isIncome ? c.positive : c.negative;
    final route = _sourceRoute(t);
    final edited = t.version > 1 || t.updatedAt.isAfter(t.createdAt.add(const Duration(seconds: 1)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10),
      children: [
        ResponsiveCenter(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StaggeredEntrance(
                child: FinnCard(
                  padding: const EdgeInsets.all(Space.x5),
                  child: Column(
                    children: [
                      CategoryAvatar(category: category, size: 56),
                      const SizedBox(height: Space.x3),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: text.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: Space.x2),
                      AmountText(
                        t.signedAmount,
                        sign: SignDisplay.always,
                        fit: true,
                        style: text.amountHero.copyWith(color: accent),
                        semanticsLabel: '${t.isIncome ? 'Received' : 'Spent'} ${MoneyFormatter.spoken(t.amount)}',
                      ),
                      const SizedBox(height: Space.x3),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: Space.x2,
                        runSpacing: Space.x2,
                        children: [
                          StatusPill(
                            label: t.isIncome ? 'Money in' : 'Money out',
                            color: accent,
                            icon: t.isIncome ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
                          ),
                          StatusPill(label: 'Completed', color: c.textSecondary, icon: LucideIcons.circleCheck),
                          if (t.isLinked) StatusPill(label: 'Linked', color: c.info, icon: LucideIcons.link2),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (t.isLinked) ...[
                const SizedBox(height: Space.x4),
                StaggeredEntrance(
                  index: 1,
                  child: InfoBanner(
                    title: 'Created by ${t.origin.label}',
                    message:
                        'To keep your balances accurate, change or reverse this from the '
                        '${_sourceName(t.origin)} that created it.',
                    icon: LucideIcons.link2,
                    actionLabel: route == null ? null : 'Open ${_sourceName(t.origin)}',
                    onAction: route == null ? null : () => context.push(route),
                  ),
                ),
              ],
              const SizedBox(height: Space.x4),
              StaggeredEntrance(
                index: 2,
                child: FinnCard(
                  padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
                  child: Column(
                    children: [
                      KeyValueRow(label: 'Category', value: category?.name ?? 'Deleted category'),
                      const FinnDivider(),
                      KeyValueRow(label: 'Date', value: '${DateFormats.weekdayDayMonth.format(t.date)} ${t.date.year}'),
                      if (t.paymentMethod != null) ...[
                        const FinnDivider(),
                        KeyValueRow(label: t.isIncome ? 'Received via' : 'Paid via', value: t.paymentMethod!.label),
                      ],
                      if ((t.counterparty ?? '').trim().isNotEmpty) ...[
                        const FinnDivider(),
                        KeyValueRow(label: t.isIncome ? 'Received from' : 'Paid to', value: t.counterparty!),
                      ],
                      const FinnDivider(),
                      KeyValueRow(label: 'Source', value: t.origin.label),
                      const FinnDivider(),
                      KeyValueRow(label: 'Recorded', value: DateFormats.timestamp.format(t.createdAt)),
                      if (edited) ...[
                        const FinnDivider(),
                        KeyValueRow(label: 'Last edited', value: DateFormats.timestamp.format(t.updatedAt)),
                      ],
                    ],
                  ),
                ),
              ),
              if ((t.note ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: Space.x4),
                StaggeredEntrance(
                  index: 3,
                  child: FinnCard(
                    variant: FinnCardVariant.muted,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(LucideIcons.stickyNote, size: 18, color: c.textSecondary),
                        const SizedBox(width: Space.x3),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('NOTE', style: text.eyebrow),
                              const SizedBox(height: Space.x1),
                              Text(t.note!, style: text.body),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (!t.isLinked) ...[
                const SizedBox(height: Space.x6),
                FinnButton(
                  label: 'Edit transaction',
                  icon: LucideIcons.pencil,
                  variant: FinnButtonVariant.secondary,
                  expand: true,
                  onPressed: _deleting ? null : () => context.push(AppRoutes.editTransaction(t.id)),
                ),
                const SizedBox(height: Space.x3),
                FinnButton(
                  label: 'Delete transaction',
                  icon: LucideIcons.trash2,
                  variant: FinnButtonVariant.destructive,
                  expand: true,
                  loading: _deleting,
                  onPressed: _delete,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
