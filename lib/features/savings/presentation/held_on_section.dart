import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../accounts/presentation/widgets/account_picker_field.dart';
import '../../goals/domain/goal.dart';
import '../application/set_aside.dart';

/// "Held on": which accounts a goal or the emergency fund is set aside on,
/// from its movements. Hidden when the bucket holds nothing.
class HeldOnSection extends ConsumerWidget {
  const HeldOnSection({
    super.key,
    required this.type,
    required this.bucketId,
    required this.movements,
  });

  final SavingsBucketType type;
  final String bucketId;
  final List<SavingsMovement> movements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(todayProvider);
    final names = {
      for (final b in ref.watch(accountBalancesProvider).value ?? const [])
        b.account.id: b,
    };
    final held = holdingsOf(movements, type, bucketId, today);
    final rows = [
      for (final e in held.entries)
        if (e.value.isPositive) e,
    ]..sort((a, b) => b.value.compareTo(a.value));
    if (rows.isEmpty) return const SizedBox.shrink();
    return PageColumn(
      top: Sp.section,
      child: LedgerSection(
        title: 'Held on',
        child: LedgerPanel(
          children: [
            for (final e in rows)
              LedgerRow(
                key: ValueKey('held-on-${e.key ?? 'none'}'),
                leading: IconWell(
                  icon: names[e.key] == null
                      ? LucideIcons.wallet
                      : accountKindIcon(names[e.key]!.account.kind),
                ),
                title: e.key == null
                    ? 'No account'
                    : (names[e.key]?.account.name ?? 'Account'),
                trailing: AmountText(
                  e.value,
                  style: context.type.figureSmall,
                  decimals: DecimalDisplay.none,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
