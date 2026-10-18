import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/di/core_providers.dart';
import '../../../app/di/data_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../kit/kit.dart';
import '../../../shared/presentation/action_runner.dart';
import '../../savings/application/set_aside.dart';
import '../application/goal_actions.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

/// Add money to (or withdraw from) a savings goal.
class GoalMovementSheet extends ConsumerWidget {
  const GoalMovementSheet({
    super.key,
    required this.goalId,
    this.withdraw = false,
  });

  final String goalId;
  final bool withdraw;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(goalProgressProvider(goalId));
    if (!value.hasValue) {
      return FinnSheetScaffold(
        title: withdraw ? 'Withdraw' : 'Add money',
        child: value.hasError
            ? const LedgerEmpty(
                title: 'Could not load this goal',
                message: 'Please try again.',
              )
            : const SavingsMovementSkeleton(),
      );
    }
    final g = value.requireValue;
    if (g == null) {
      return const FinnSheetScaffold(
        title: 'Goal not found',
        child: LedgerEmpty(
          title: 'This goal no longer exists',
          message: 'It may have been deleted.',
        ),
      );
    }
    return SavingsMovementForm(
      withdraw: withdraw,
      potName: g.goal.name,
      held: withdraw
          ? holdingsOf(g.movements, SavingsBucketType.goal, goalId, ref.watch(todayProvider))
          : null,
      saved: g.saved,
      target: g.goal.target,
      disabledReason: g.goal.status == GoalStatus.archived
          ? 'This goal is archived. Restore it to add or withdraw money.'
          : (withdraw && !g.saved.isPositive
                ? 'Nothing is saved in this goal yet.'
                : null),
      onSubmit: (draft, key, onErrors) async {
        final input = GoalMovementInput(
          goalId: goalId,
          amount: draft.amount,
          date: draft.date,
          accountId: draft.accountId,
          note: draft.note,
        );
        final completes =
            !withdraw &&
            !g.isAchieved &&
            g.saved + draft.amount >= g.goal.target;
        final result = await runAction(
          context,
          ref,
          action: withdraw
              ? const GoalMovementAction.withdraw()
              : const GoalMovementAction.contribute(),
          input: input,
          idempotencyKey: key,
          celebrate: !withdraw,
          successTitle: withdraw
              ? 'Moved ${draft.amount.format()} back to available'
              : (completes
                    ? 'Goal reached!'
                    : 'Added ${draft.amount.format()}'),
          successSubtitle: withdraw
              ? null
              : (completes
                    ? '${g.goal.name} is fully funded.'
                    : 'Set aside for ${g.goal.name}'),
          onFieldErrors: onErrors,
        );
        return result != null;
      },
    );
  }
}
