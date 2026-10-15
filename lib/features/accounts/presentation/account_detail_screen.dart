import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../../shared/presentation/async_view.dart';
import '../../../shared/presentation/transaction_row.dart';
import '../../transactions/domain/transaction.dart';
import '../application/account_actions.dart';
import '../domain/money_account.dart';
import '../domain/transfer.dart';
import 'transfer_form_sheet.dart';
import 'widgets/account_ui.dart';

enum _Menu { edit, correct, makeDefault, archive, delete }

/// One account: its balance, details and the movements that hit it.
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  final _key = newIdempotencyKey();

  Future<void> _menu(AccountBalance b) async {
    final a = b.account;
    final choice = await showFinnActionMenu<_Menu>(
      context,
      title: a.name,
      items: [
        const FinnMenuItem(
          value: _Menu.edit,
          label: 'Edit details',
          icon: LucideIcons.pencil,
        ),
        FinnMenuItem(
          value: _Menu.correct,
          label: a.isLiability ? 'Correct amount owed' : 'Correct balance',
          icon: LucideIcons.scale,
        ),
        if (!a.isDefault && !a.isArchived)
          const FinnMenuItem(
            value: _Menu.makeDefault,
            label: 'Set as default',
            icon: LucideIcons.star,
          ),
        FinnMenuItem(
          value: _Menu.archive,
          label: a.isArchived ? 'Unarchive' : 'Archive',
          icon: a.isArchived ? LucideIcons.archiveRestore : LucideIcons.archive,
        ),
        const FinnMenuItem(
          value: _Menu.delete,
          label: 'Delete',
          icon: LucideIcons.trash2,
          destructive: true,
        ),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _Menu.edit:
        context.push(AppRoutes.editAccount(a.id));
      case _Menu.correct:
        context.push(AppRoutes.correctAccountBalance(a.id));
      case _Menu.makeDefault:
        await runAction(
          context,
          ref,
          action: const SetDefaultAccountAction(),
          input: AccountIdInput(id: a.id),
          idempotencyKey: '$_key-default-${a.version}',
          successTitle: '${a.name} is now the default',
        );
      case _Menu.archive:
        await runAction(
          context,
          ref,
          action: const ArchiveAccountAction(),
          input: ArchiveAccountInput(id: a.id, archived: !a.isArchived),
          idempotencyKey: '$_key-archive-${a.version}',
          successTitle: a.isArchived
              ? 'Account unarchived'
              : 'Account archived',
          successSubtitle: a.name,
        );
      case _Menu.delete:
        final done = await runAction(
          context,
          ref,
          action: const DeleteAccountAction(),
          input: AccountIdInput(id: a.id),
          idempotencyKey: '$_key-delete-${a.version}',
          successTitle: 'Account deleted',
          successSubtitle: a.name,
        );
        if (done != null && mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.accounts);
          }
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(accountBalanceProvider(widget.id));
    final b = value.value;
    return LedgerPage(
      appBar: LedgerAppBar(
        title: b?.account.name ?? 'Account',
        actions: [
          if (b != null)
            LedgerIconButton(
              icon: LucideIcons.ellipsisVertical,
              tooltip: 'More actions',
              onPressed: () => _menu(b),
            ),
        ],
      ),
      storageKey: 'account-${widget.id}',
      slivers: [
        SliverToBoxAdapter(
          child: AsyncView<AccountBalance?>(
            value: value,
            loading: const LedgerPageSkeleton(rows: 3),
            builder: (context, b) => b == null
                ? PageColumn(
                    top: Sp.xxl,
                    child: LedgerEmpty(
                      title: 'This account no longer exists',
                      message: 'It may have been deleted.',
                      actionLabel: 'Back to accounts',
                      onAction: () => context.go(AppRoutes.accounts),
                    ),
                  )
                : _Body(balance: b),
          ),
        ),
      ],
    );
  }
}

/// A transaction or a transfer, for the merged movement list.
class _Movement {
  _Movement.tx(Transaction this.tx)
    : transfer = null,
      date = tx.date,
      created = tx.createdAt;
  _Movement.transfer(Transfer this.transfer)
    : tx = null,
      date = transfer.date,
      created = transfer.createdAt;

  final Transaction? tx;
  final Transfer? transfer;
  final DateTime date;
  final DateTime created;
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.balance});
  final AccountBalance balance;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  static const _page = 20;
  int _shown = _page;

  List<_Movement> _movements() {
    final id = widget.balance.account.id;
    final txs =
        ref.watch(sortedTransactionsProvider).value ?? const <Transaction>[];
    final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
    final all = <_Movement>[
      for (final t in txs)
        if (t.accountId == id) _Movement.tx(t),
      for (final t in transfers)
        if (t.fromAccountId == id || t.toAccountId == id) _Movement.transfer(t),
    ];
    all.sort((a, b) {
      final c = b.date.compareTo(a.date);
      return c != 0 ? c : b.created.compareTo(a.created);
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.balance;
    final a = b.account;
    final all = _movements();
    final visible = all.take(_shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageColumn(
          top: Sp.xl,
          child: _Hero(balance: b),
        ),
        if (a.isArchived)
          const PageColumn(
            top: Sp.lg,
            child: LedgerNote(
              icon: LucideIcons.archive,
              text:
                  'Archived. It keeps its history but is hidden from pickers.',
            ),
          ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: 'Details',
            child: LedgerPanel(children: _facts(context, b)),
          ),
        ),
        PageColumn(
          top: Sp.section,
          child: LedgerSection(
            title: 'Movements',
            count: all.isEmpty ? null : all.length,
            child: all.isEmpty
                ? const LedgerNote(
                    text: 'Nothing recorded on this account yet.',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LedgerPanel(
                        children: [
                          for (final m in visible)
                            if (m.tx != null)
                              TransactionRow(
                                key: ValueKey('tx-${m.tx!.id}'),
                                transaction: m.tx!,
                                showDate: true,
                              )
                            else
                              _TransferRow(
                                key: ValueKey('tr-${m.transfer!.id}'),
                                transfer: m.transfer!,
                                accountId: a.id,
                              ),
                        ],
                      ),
                      if (all.length > _shown) ...[
                        const SizedBox(height: Sp.sm),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: LedgerButton(
                            label: 'Show more',
                            icon: LucideIcons.chevronDown,
                            variant: LedgerButtonVariant.quiet,
                            small: true,
                            onPressed: () => setState(() => _shown += _page),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        const SizedBox(height: Sp.xl),
      ],
    );
  }

  List<Widget> _facts(BuildContext context, AccountBalance b) {
    final a = b.account;
    final t = context.type;
    final ink = context.ink.ink;
    Widget fact(String label, String text) =>
        LedgerFact(label: label, text: text);
    return [
      fact('Kind', a.kind.label),
      if (a.institution != null) fact('Institution', a.institution!),
      if (a.last4 != null) fact('Card', '····${a.last4}'),
      LedgerFact(
        label: a.isLiability
            ? 'Owed on ${DateFormats.dayMonthYear.format(a.openingDate)}'
            : 'Opening balance',
        value: AmountText(a.opening, style: t.figureSmall.copyWith(color: ink)),
      ),
      if (!a.isLiability)
        fact('Tracked since', DateFormats.dayMonthYear.format(a.openingDate)),
      if (a.creditLimit != null)
        LedgerFact(
          label: 'Credit limit',
          value: AmountText(
            a.creditLimit!,
            style: t.figureSmall.copyWith(color: ink),
          ),
        ),
      if (a.isDefault) fact('Default', 'Used for new entries'),
      if (a.note != null) fact('Note', a.note!),
    ];
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.balance});
  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.ink;
    final a = balance.account;
    final limit = limitLeftText(balance);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(a.isLiability ? 'Amount owed' : 'Balance', style: t.label),
        const SizedBox(height: Sp.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: AccountAmount(balance, style: t.figureXL),
        ),
        const SizedBox(height: Sp.sm),
        Text(
          [accountSubtitle(a), if (a.isDefault) 'Default'].join(' · '),
          style: t.label,
        ),
        if (limit != null) ...[
          const SizedBox(height: Sp.xs),
          Text(
            limit,
            style: t.label.copyWith(
              color: balance.limitLeft!.isNegative ? c.red : c.inkSoft,
            ),
          ),
        ],
        const SizedBox(height: Sp.lg),
        Row(
          children: [
            LedgerButton(
              label: 'Transfer',
              icon: LucideIcons.arrowLeftRight,
              variant: LedgerButtonVariant.secondary,
              small: true,
              onPressed: a.isArchived
                  ? null
                  : () => showTransferSheet(
                      context,
                      fromAccountId: a.isLiability ? null : a.id,
                      toAccountId: a.isLiability ? a.id : null,
                    ),
            ),
          ],
        ),
      ],
    );
  }
}

/// A transfer on this account: neutral (not income or spending), named by
/// where the money went or came from.
class _TransferRow extends ConsumerWidget {
  const _TransferRow({
    super.key,
    required this.transfer,
    required this.accountId,
  });

  final Transfer transfer;
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final out = transfer.fromAccountId == accountId;
    final otherId = out ? transfer.toAccountId : transfer.fromAccountId;
    final other = ref
        .watch(moneyAccountsProvider)
        .value
        ?.where((a) => a.id == otherId)
        .firstOrNull;
    final name = other?.name ?? 'Account';
    final title = out ? 'To $name' : 'From $name';
    final sub = [
      DateFormatsX.short(transfer.date),
      'Transfer',
      if (transfer.channel != null) transfer.channel!,
    ].join(', ');
    final amount = out ? -transfer.amount : transfer.amount;
    final hidden = AmountVisibility.hiddenOf(context);
    return LedgerRow(
      leading: const IconWell(icon: LucideIcons.arrowLeftRight, size: 40),
      title: title,
      subtitle: sub,
      trailing: AmountText(amount, sign: SignDisplay.always, style: t.figure),
      semanticLabel:
          '$title, transfer, ${hidden ? 'amount hidden' : MoneyFormatter.spoken(transfer.amount)}',
      onTap: () => showTransferSheet(context, existing: transfer),
    );
  }
}
