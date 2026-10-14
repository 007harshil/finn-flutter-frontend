import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../ui/ui.dart';
import '../../application/home_overview.dart';

/// First run: one primary action, then the short setup checklist.
class GetStartedSection extends ConsumerWidget {
  const GetStartedSection({super.key});

  static String routeFor(SetupStep s) => switch (s) {
    SetupStep.profile => AppRoutes.profile,
    SetupStep.emergencyFund => AppRoutes.emergencyPlan,
    SetupStep.goal => AppRoutes.newGoal,
    SetupStep.budget => AppRoutes.newBudget,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final list = ref.watch(setupChecklistProvider).value;
    return UiSection(
      title: 'Get started',
      trailing: list == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(right: UiSpace.sm),
              child: Text('${list.completed} of ${list.total}', style: t.label),
            ),
      child: UiPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(UiSpace.lg),
              child: UiPrimaryButton(
                label: 'Add first transaction',
                icon: LucideIcons.plus,
                onPressed: () => context.push(AppRoutes.newTransaction()),
              ),
            ),
            for (final step in SetupStep.values) ...[
              const UiRule(),
              UiListRow(
                key: ValueKey(step),
                leading: Icon(
                  list?.isDone(step) ?? false ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 22,
                  color: list?.isDone(step) ?? false ? c.positive : c.inkFaint,
                ),
                title: step.title,
                subtitle: list?.isDone(step) ?? false ? 'Done' : null,
                subtitleColor: c.positive,
                semanticLabel: list?.isDone(step) ?? false ? '${step.title}, done' : step.title,
                onTap: () => context.push(routeFor(step)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
