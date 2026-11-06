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
import '../../../shared/presentation/category_icons.dart';
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
    final category = ref.watch(categoryProvider(t.categoryId));
    final title = t.displayTitle ?? category?.name ?? 'Transaction';
    final route = _sourceRoute(t);
    final edited =
        t.version > 1 ||
        t.updatedAt.isAfter(t.createdAt.add(const Duration(seconds: 1)));

    final snapshot = ref.watch(financeSnapshotProvider).value;
    String nameOf(String id) => snapshot?.account(id)?.name ?? 'Unknown account';
    final account = t.isSplit ? '${t.legs.length} accounts' : nameOf(t.accountId);
    final who = (t.counterparty ?? '').trim();
    final note = (t.note ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(
          top: Sp.lg,
          child: Semantics(
            container: true,
            label: '$title. ${t.isIncome ? 'Received' : 'Spent'} ${MoneyFormatter.spoken(t.amount)}',
            child: BahiSlab(
              leading: category == null ? LucideIcons.tag : CategoryIcons.of(category.iconKey),
              label: t.isIncome ? 'Money in' : 'Money out',
              figure: SlabFigure(t.signedAmount, sign: SignDisplay.always, color: t.isIncome ? Slab.good : null),
              caption: title,
              stats: [
                SlabStat.text(label: 'Date', text: DateFormats.dayMonthYear.format(t.date)),
                SlabStat.text(label: t.isSplit ? 'Split' : 'Account', text: account),
              ],
              footer: t.isSplit ? _SplitLegs(transaction: t, nameOf: nameOf) : null,
            ),
          ),
        ),
        PageColumn(
          top: Sp.lg,
          child: FactTags(
            tags: [
              category?.name ?? 'Deleted category',
              if (who.isNotEmpty) '${t.isIncome ? 'From' : 'To'} $who',
              if ((t.channel ?? '').isNotEmpty) t.channel!,
              t.origin.label,
              'Recorded ${DateFormats.timestamp.format(t.createdAt)}',
              if (edited) 'Edited ${DateFormats.timestamp.format(t.updatedAt)}',
            ],
            highlight: {category?.name ?? ''},
          ),
        ),
        if (note.isNotEmpty) PageColumn(top: Sp.md, child: LedgerNote(icon: LucideIcons.stickyNote, text: note)),
        PageColumn(top: Sp.lg, child: _CategoryContext(transaction: t, name: category?.name ?? 'This category')),
        if (t.isLinked)
          PageColumn(
            top: Sp.lg,
            child: LedgerButton(
              label: route == null ? 'From ${t.origin.label}' : 'Open ${_sourceName(t.origin)}',
              icon: LucideIcons.link2,
              variant: LedgerButtonVariant.secondary,
              expand: true,
              onPressed: route == null ? null : () => context.push(route),
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

/// A payment split across accounts: one bar with each account's part, then
/// each account with its amount.
class _SplitLegs extends StatelessWidget {
  const _SplitLegs({required this.transaction, required this.nameOf});

  final Transaction transaction;
  final String Function(String id) nameOf;

  static const _colors = [Slab.cool, Slab.warn, Slab.lilac, Slab.good, Slab.bad];

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final legs = transaction.legs;
    final total = transaction.amount.paise;
    Color colorOf(int i) => _colors[i % _colors.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SlabBar(
          key: const ValueKey('tx-split-bar'),
          parts: [for (var i = 0; i < legs.length; i++) (legs[i].amount.paise / total, colorOf(i))],
          semanticLabel: [for (final l in legs) '${nameOf(l.accountId)} ${MoneyFormatter.spoken(l.amount)}'].join(', '),
        ),
        const SizedBox(height: Sp.sm),
        for (var i = 0; i < legs.length; i++)
          Padding(
            key: ValueKey('tx-split-leg:${legs[i].accountId}'),
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: colorOf(i), shape: BoxShape.circle),
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: Text(
                    nameOf(legs[i].accountId),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.small.copyWith(color: Slab.soft),
                  ),
                ),
                AmountText(legs[i].amount, style: t.small.copyWith(color: Slab.ink, fontWeight: FontWeight.w600)),
              ],
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
    return MonsoonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KhataRing(
                value: share,
                size: 84,
                stroke: 9,
                color: tx.isIncome ? c.green : c.rain,
                center: Text(hidden ? '••' : '${(share * 100).round()}%', style: t.figure.copyWith(fontSize: 17)),
              ),
              const SizedBox(width: Sp.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$name · ${DateFormats.monthName.format(month.start)}', style: t.label),
                    const SizedBox(height: 2),
                    AmountText(Money.fromPaise(monthTotal), style: t.figureL.copyWith(fontSize: 26), decimals: DecimalDisplay.none),
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
