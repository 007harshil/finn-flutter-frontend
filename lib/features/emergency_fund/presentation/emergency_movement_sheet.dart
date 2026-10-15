import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../goals/presentation/savings_widgets.dart';
import '../application/emergency_actions.dart';

/// Add money to (or withdraw from) the emergency fund. An internal
/// allocation: not income, not an expense.
class EmergencyMovementSheet extends ConsumerWidget {
  const EmergencyMovementSheet({super.key, this.withdraw = false});

  final bool withdraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(emergencyStatusProvider);
    if (!value.hasValue) {
      return FinnSheetScaffold(
        title: withdraw ? 'Withdraw' : 'Add money',
        child: value.hasError
            ? const LedgerEmpty(
                title: 'Could not load your emergency fund',
                message: 'Please try again.',
              )
            : const SavingsMovementSkeleton(),
      );
    }
    final s = value.requireValue;
    return SavingsMovementForm(
      withdraw: withdraw,
      potName: 'emergency fund',
      saved: s.saved,
      target: s.target,
      disabledReason: withdraw && !s.saved.isPositive
          ? 'Nothing is saved in your emergency fund yet.'
          : null,
      onSubmit: (draft, key, onErrors) async {
        final target = s.target;
        final completes =
            !withdraw &&
            target.isPositive &&
            s.saved < target &&
            s.saved + draft.amount >= target;
        final result = await runAction(
          context,
          ref,
          action: withdraw
              ? const EmergencyFundMovementAction.withdraw()
              : const EmergencyFundMovementAction.contribute(),
          input: EmergencyFundMovementInput(
            amount: draft.amount,
            date: draft.date,
            note: draft.note,
          ),
          idempotencyKey: key,
          celebrate: !withdraw,
          successTitle: withdraw
              ? 'Moved ${draft.amount.format()} back to available'
              : (completes
                    ? 'Emergency fund fully funded!'
                    : 'Added ${draft.amount.format()}'),
          successSubtitle: withdraw
              ? 'You can top up your safety net later.'
              : (completes
                    ? 'Your safety net is complete.'
                    : 'Set aside for emergencies'),
          onFieldErrors: onErrors,
        );
        return result != null;
      },
    );
  }
}
