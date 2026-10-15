import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../kit/kit.dart';
import '../../../accounts/domain/money_account.dart';
import '../../../accounts/presentation/widgets/account_ui.dart';

/// Where the money is: one quiet row per active account (kind and last 4,
/// balance; credit cards show what is owed). Hidden until accounts load.
class HomeAccountsSection extends ConsumerWidget {
  const HomeAccountsSection({super.key});

  static const maxShown = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(accountBalancesProvider).value;
    if (all == null) return const SizedBox.shrink();
    final active = [
      for (final b in all)
        if (!b.account.isArchived) b,
    ];
    if (active.isEmpty) return const SizedBox.shrink();
    final shown = active.take(maxShown).toList();
    return Padding(
      padding: const EdgeInsets.only(top: Sp.section),
      child: LedgerSection(
        title: 'Accounts',
        count: active.length,
        actionLabel: 'Manage',
        onAction: () => context.push(AppRoutes.accounts),
        child: LedgerPanel(
          dividerIndent: Sp.lg + 36 + Sp.md + 2,
          children: [for (final AccountBalance b in shown) AccountRow(balance: b)],
        ),
      ),
    );
  }
}
