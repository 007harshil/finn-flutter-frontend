import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/async_view.dart';
import '../domain/money_account.dart';
import 'transfer_form_sheet.dart';
import 'widgets/account_ui.dart';

/// Every place money lives: total money first, then accounts by kind, with
/// credit cards (amount owed, not money) kept apart.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(accountBalancesProvider);
    return AsyncView<List<AccountBalance>>(
      value: balances,
      loading: Scaffold(
        backgroundColor: context.ink.paper,
        appBar: const LedgerAppBar(title: 'Accounts'),
        body: const LedgerPageSkeleton(),
      ),
      errorTitle: 'Could not load your accounts',
      builder: (context, list) => _Body(balances: list),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.balances});
  final List<AccountBalance> balances;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _showArchived = false;

  List<AccountBalance> _of(bool Function(MoneyAccountKind k) test) => [
    for (final b in widget.balances)
      if (!b.account.isArchived && test(b.account.kind)) b,
  ];

  @override
  Widget build(BuildContext context) {
    final cash = _of((k) => k == MoneyAccountKind.cash);
    final banks = _of((k) => k == MoneyAccountKind.bank);
    final cards = _of((k) => k.isCard && !k.isLiability);
    final credit = _of((k) => k.isLiability);
    final archived = [
      for (final b in widget.balances)
        if (b.account.isArchived) b,
    ];
    return LedgerPage(
      storageKey: 'accounts',
      appBar: LedgerAppBar(
        title: 'Accounts',
        actions: [
          LedgerIconButton(
            icon: LucideIcons.arrowLeftRight,
            tooltip: 'Transfer',
            onPressed: () => showTransferSheet(context),
          ),
          LedgerIconButton(
            icon: LucideIcons.plus,
            tooltip: 'Add account',
            onPressed: () => context.push(AppRoutes.newAccount),
          ),
        ],
      ),
      slivers: [
        const PageBlock(top: Sp.lg, child: _Total()),
        if (cash.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: _Group(title: 'Cash', items: cash),
          ),
        if (banks.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: _Group(title: 'Bank accounts', items: banks),
          ),
        if (cards.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: _Group(title: 'Cards', items: cards),
          ),
        if (credit.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: _Group(title: 'Credit cards', items: credit),
          ),
        if (archived.isNotEmpty)
          PageBlock(
            top: Sp.section,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LedgerSection(
                  title: 'Archived',
                  count: archived.length,
                  actionLabel: _showArchived ? 'Hide' : 'Show',
                  onAction: () =>
                      setState(() => _showArchived = !_showArchived),
                  child: _showArchived
                      ? LedgerPanel(
                          children: [
                            for (final b in archived) AccountRow(balance: b),
                          ],
                        )
                      : const LedgerNote(
                          text: 'Archived accounts keep their history but are hidden from pickers.',
                        ),
                ),
              ],
            ),
          ),
        const PageBlock(
          top: Sp.section,
          bottom: Sp.xl,
          child: LedgerNote(
            text:
                'Total money adds up your cash, bank accounts and cards. A credit card shows what you owe; '
                'it is paid from another account and never counts as money.',
          ),
        ),
      ],
    );
  }
}

class _Total extends ConsumerWidget {
  const _Total();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final c = context.ink;
    final b = ref.watch(balanceProvider).value;
    final owed = ref.watch(creditOwedProvider).value;
    if (b == null) return const SizedBox(height: 80);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Total money', style: t.label),
        const SizedBox(height: Sp.xs),
        AnimatedAmount(
          b.cash,
          style: t.figureXL,
          decimals: DecimalDisplay.none,
          fit: true,
          animateOnMount: true,
        ),
        if (owed != null && owed.isPositive) ...[
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Text('Credit card owed  ', style: t.label),
              AmountText(
                owed,
                style: t.figureSmall.copyWith(color: c.red),
                decimals: DecimalDisplay.none,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.items});
  final String title;
  final List<AccountBalance> items;

  @override
  Widget build(BuildContext context) {
    return LedgerSection(
      title: title,
      count: items.length,
      child: LedgerPanel(
        dividerIndent: Sp.lg + 36 + Sp.md + 2,
        children: [for (final b in items) AccountRow(balance: b)],
      ),
    );
  }
}
