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
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: Sp.xl)),
      ],
    );
  }
}

class _Total extends ConsumerWidget {
  const _Total();

  /// Light hues that read on the indigo slab, one per account.
  static const _hues = [Slab.warn, Slab.cool, Slab.lilac, Slab.good, Slab.bad, Slab.soft];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final b = ref.watch(balanceProvider).value;
    final owed = ref.watch(creditOwedProvider).value;
    if (b == null) return const SizedBox(height: 80);
    final hidden = AmountVisibility.hiddenOf(context);
    final all = ref.watch(accountBalancesProvider).value ?? const <AccountBalance>[];
    final held = [
      for (final x in all)
        if (!x.account.isArchived && x.balance.isPositive && !x.isLiability) x,
    ]..sort((x, y) => y.balance.paise.compareTo(x.balance.paise));
    final total = held.fold<int>(0, (sum, x) => sum + x.balance.paise);
    final open = all.where((x) => !x.account.isArchived).length;
    Color hue(int i) => _hues[i % _hues.length];
    return BahiSlab(
      leading: LucideIcons.wallet,
      label: 'Total money',
      figure: SlabFigure(b.cash),
      stats: [
        SlabStat.text(label: 'Accounts', text: '$open'),
        if (owed != null && owed.isPositive) SlabStat.money(label: 'Card owed', amount: owed, color: Slab.bad),
        SlabStat.money(label: 'Set aside', amount: b.earmarked),
      ],
      footer: held.length < 2 || total <= 0
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SlabBar(
                  height: 10,
                  parts: [for (var i = 0; i < held.length; i++) (held[i].balance.paise / total, hue(i))],
                  semanticLabel: 'Share of money by account',
                ),
                const SizedBox(height: Sp.sm + 2),
                Wrap(
                  spacing: Sp.lg,
                  runSpacing: Sp.xs,
                  children: [
                    for (var i = 0; i < held.length && i < 6; i++)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: hue(i), shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(
                            '${held[i].account.name} ${hidden ? '••' : '${(held[i].balance.paise * 100 / total).round()}%'}',
                            style: t.small.copyWith(color: Slab.soft),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
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
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = Sp.sm + 2;
          final w = (box.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [for (final b in items) SizedBox(width: items.length == 1 ? box.maxWidth : w, child: AccountCard(balance: b))],
          );
        },
      ),
    );
  }
}

/// A passbook card: kind icon, name, balance, and a bar for how much is set
/// aside (or, on a credit card, how much of the limit is used).
class AccountCard extends StatelessWidget {
  const AccountCard({super.key, required this.balance});

  final AccountBalance balance;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final a = balance.account;
    final hidden = AmountVisibility.hiddenOf(context);
    final bal = balance.balance.paise.abs();
    final left = balance.limitLeft;
    final double? share = a.isLiability
        ? (left == null || bal + left.paise <= 0 ? null : bal / (bal + left.paise))
        : (SetAsideLine.shows(balance) && bal > 0 ? (balance.earmarked.paise / bal) : null);
    final sub = [
      if (a.last4 != null) '····${a.last4}' else a.kind.label,
      ?limitLeftText(balance, short: true),
      if (a.isDefault) 'Default',
    ].join(' · ');
    return Semantics(
      key: ValueKey('account-row-${a.id}'),
      button: true,
      label: accountSemantics(balance, hidden: hidden),
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: Rad.rMd, side: BorderSide(color: a.isDefault ? c.marigold : c.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(AppRoutes.accountDetail(a.id)),
          child: Padding(
            padding: const EdgeInsets.all(Sp.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconWell(icon: accountIcon(a.kind), size: 32),
                    const SizedBox(width: Sp.sm),
                    Expanded(child: Text(a.name, style: t.labelStrong, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
                const SizedBox(height: Sp.md),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: AccountAmount(balance, style: t.figureL.copyWith(fontSize: 24), decimals: DecimalDisplay.none),
                ),
                Text(sub, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: Sp.sm),
                SizedBox(
                  width: double.infinity,
                  child: LedgerBar(
                  value: share ?? 0,
                  height: 5,
                  color: a.isLiability ? (share != null && share >= 0.85 ? c.saffron : c.rain) : c.marigold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
