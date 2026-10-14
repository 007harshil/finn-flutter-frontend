import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../kit/kit.dart';
import '../../application/home_overview.dart';

/// First-run block: one sentence about FiNN and the one action that
/// starts everything.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Welcome to FiNN', style: t.heading),
        const SizedBox(height: Sp.xs),
        Text(
          'Record your first income or expense. Balances, budgets and goals build from there.',
          style: t.label,
        ),
        const SizedBox(height: Sp.lg),
        LedgerButton(
          label: 'Record first transaction',
          icon: LucideIcons.plus,
          expand: true,
          onPressed: () => context.push(AppRoutes.newTransaction()),
        ),
      ],
    );
  }
}

/// "Get set up": four optional steps, each opening its form.
class SetupChecklistSection extends ConsumerWidget {
  const SetupChecklistSection({super.key});

  static String routeFor(SetupStep step) => switch (step) {
    SetupStep.profile => AppRoutes.profile,
    SetupStep.emergencyFund => AppRoutes.emergencyPlan,
    SetupStep.goal => AppRoutes.newGoal,
    SetupStep.budget => AppRoutes.newBudget,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final list = ref.watch(setupChecklistProvider).value;
    if (list == null) return const LedgerSkeleton(height: 260, radius: Rad.lg);
    return LedgerSection(
      title: 'Get set up',
      trailing: Text('${list.completed} of ${list.total} done', style: context.type.label),
      child: LedgerPanel(
        dividerIndent: Sp.lg + 40 + Sp.md + 2,
        children: [
          for (final step in SetupStep.values)
            LedgerRow(
              key: ValueKey(step),
              leading: list.done.contains(step)
                  ? IconWell(icon: LucideIcons.check, color: c.green, background: c.greenSoft)
                  : const IconWell(icon: LucideIcons.circle),
              title: step.title,
              subtitle: list.done.contains(step) ? 'Done' : step.description,
              subtitleColor: list.done.contains(step) ? c.green : null,
              semanticLabel: list.done.contains(step) ? '${step.title}, done' : step.title,
              titleLines: 2,
              subtitleLines: 2,
              chevron: true,
              onTap: () => context.push(routeFor(step)),
            ),
        ],
      ),
    );
  }
}
