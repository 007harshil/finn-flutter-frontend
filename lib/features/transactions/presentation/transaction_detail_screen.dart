import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../core/money/money.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
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
    return LedgerPage(
      appBar: LedgerAppBar(
        title: 'Transaction',
        actions: [
          if (manual)
            LedgerIconButton(
              icon: LucideIcons.pencil,
              tooltip: 'Edit transaction',
              onPressed: () => context.push(AppRoutes.editTransaction(id)),
            ),
        ],
      ),
      storageKey: 'transaction-$id',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<Transaction?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 4),
            builder: (context, t) => t == null
                ? PageColumn(
                    top: Sp.xxl,
                    child: LedgerEmpty(
                      title: 'Transaction not found',
                      actionLabel: 'Back to activity',
                      onAction: () => context.go(AppRoutes.transactions),
                    ),
                  )
                : _Details(transaction: t),
          ),
        ),
      ],
    );
  }
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

  Future<void> _confirmDelete() async {
    final ok = await showFinnConfirm(
      context,
      title: 'Delete transaction?',
      message: 'Your balances will update. This cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (ok && mounted) await _delete();
  }

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
      TransactionOrigin.loanRepayment ||
      TransactionOrigin.loanDisbursement => AppRoutes.loan(ref),
      TransactionOrigin.subscription => AppRoutes.subscription(ref),
      TransactionOrigin.pendingSettlement => AppRoutes.pendingItem(ref),
      TransactionOrigin.manual => null,
    };
  }

  String _sourceName(TransactionOrigin o) => switch (o) {
    TransactionOrigin.loanRepayment ||
    TransactionOrigin.loanDisbursement => 'loan',
    TransactionOrigin.subscription => 'subscription',
    TransactionOrigin.pendingSettlement => 'pending payment',
    TransactionOrigin.manual => 'entry',
  };

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final c = context.ink;
    final type = context.type;
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final route = _sourceRoute(t);
    final edited =
        t.version > 1 ||
        t.updatedAt.isAfter(t.createdAt.add(const Duration(seconds: 1)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(
          top: Sp.xl,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CategoryMark(category: category, size: 44),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: type.heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Sp.xs),
                    Text(
                      t.isIncome ? 'Money in' : 'Money out',
                      style: type.label,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        PageColumn(
          top: Sp.lg,
          child: AmountText(
            t.signedAmount,
            sign: SignDisplay.always,
            fit: true,
            style: type.figureXL.copyWith(color: t.isIncome ? c.green : c.ink),
            semanticsLabel:
                '${t.isIncome ? 'Received' : 'Spent'} ${MoneyFormatter.spoken(t.amount)}',
          ),
        ),
        PageColumn(top: Sp.lg, child: _CategoryContext(transaction: t, name: category?.name ?? 'This category')),
        if (t.isLinked)
          PageColumn(
            top: Sp.xl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LedgerNote(
                  icon: LucideIcons.link2,
                  text: 'Created by ${t.origin.label}. Edit it from the ${_sourceName(t.origin)}.',
                ),
                if (route != null) ...[
                  const SizedBox(height: Sp.md),
                  LedgerButton(
                    label: 'Open ${_sourceName(t.origin)}',
                    variant: LedgerButtonVariant.secondary,
                    expand: true,
                    onPressed: () => context.push(route),
                  ),
                ],
              ],
            ),
          ),
        PageColumn(
          top: Sp.section,
          child: LedgerPanel(
            children: [
              LedgerFact(
                label: 'Category',
                text: category?.name ?? 'Deleted category',
              ),
              LedgerFact(
                label: 'Date',
                text:
                    '${DateFormats.weekdayDayMonth.format(t.date)} ${t.date.year}',
              ),
              LedgerFact(
                label: 'Account',
                text:
                    ref.watch(financeSnapshotProvider).value?.account(t.accountId)?.name ??
                    'Unknown account',
              ),
              if ((t.channel ?? '').isNotEmpty)
                LedgerFact(label: 'Channel', text: t.channel!),
              if ((t.counterparty ?? '').trim().isNotEmpty)
                LedgerFact(
                  label: t.isIncome ? 'Received from' : 'Paid to',
                  text: t.counterparty!,
                ),
              LedgerFact(label: 'Source', text: t.origin.label),
              LedgerFact(
                label: 'Recorded',
                text: DateFormats.timestamp.format(t.createdAt),
              ),
              if (edited)
                LedgerFact(
                  label: 'Last edited',
                  text: DateFormats.timestamp.format(t.updatedAt),
                ),
            ],
          ),
        ),
        if ((t.note ?? '').trim().isNotEmpty)
          PageColumn(
            top: Sp.lg,
            child: LedgerPanel(
              children: [
                LedgerFact(label: 'Note', text: t.note!, stacked: true),
              ],
            ),
          ),
        if (!t.isLinked)
          PageColumn(
            top: Sp.xxl,
            bottom: Sp.section,
            child: LedgerButton(
              label: 'Delete transaction',
              variant: LedgerButtonVariant.quiet,
              color: c.red,
              expand: true,
              loading: _deleting,
              onPressed: _confirmDelete,
            ),
          ),
      ],
    );
  }
}

/// Where this entry sits in its category: its share of the category's
/// month (ring) and the category's last six months (ruled columns).
class _CategoryContext extends ConsumerWidget {
  const _CategoryContext({required this.transaction, required this.name});

  final Transaction transaction;
  final String name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final t = context.type;
    final tx = transaction;
    final all = ref.watch(transactionsStreamProvider).value;
    if (all == null) return const SizedBox.shrink();
    final month = MonthKey.fromDate(tx.date);
    final months = [for (var i = 5; i >= 0; i--) month.shift(-i)];
    final totals = {for (final m in months) m: 0};
    for (final x in all) {
      if (x.categoryId != tx.categoryId || x.type != tx.type) continue;
      final m = MonthKey.fromDate(x.date);
      if (totals.containsKey(m)) totals[m] = totals[m]! + x.amount.paise;
    }
    final monthTotal = totals[month]!;
    if (monthTotal <= 0) return const SizedBox.shrink();
    final share = tx.amount.paise / monthTotal;
    final hidden = AmountVisibility.hiddenOf(context);
    return KhataPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KhataRing(
                value: share,
                size: 84,
                stroke: 9,
                color: tx.isIncome ? c.green : c.brand,
                center: Text(hidden ? '••' : '${(share * 100).round()}%', style: t.figure.copyWith(fontSize: 17)),
              ),
              const SizedBox(width: Sp.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Share of $name in ${DateFormats.monthName.format(month.start)}', style: t.label),
                    const SizedBox(height: 2),
                    AmountText(Money.fromPaise(monthTotal), style: t.figure, decimals: DecimalDisplay.none),
                    Text('in total that month', style: t.small),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Sp.md),
          KhataColumns(
            height: 56,
            semanticLabel: hidden ? null : '$name over the last six months',
            columns: [
              for (final m in months)
                KhataColumn(DateFormats.shortMonth.format(m.start), totals[m]!.toDouble(), highlight: m == month),
            ],
          ),
        ],
      ),
    );
  }
}
