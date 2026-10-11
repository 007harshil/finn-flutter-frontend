import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../application/home_overview.dart';
import 'home_common.dart';

/// First-run welcome with the primary call to action.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return GradientHeroCard(
      watermark: LucideIcons.sparkles,
      padding: const EdgeInsets.all(Space.x6),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: const Icon(LucideIcons.wallet, size: 26, color: Colors.white),
          ),
          const SizedBox(height: Space.x4),
          Text(
            'Welcome to FiNN',
            style: t.title.copyWith(color: Colors.white, fontSize: 22),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x1_5),
          Text(
            'Your calm, private command centre for money. Record your first transaction and everything else builds from there.',
            style: t.body.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.x5),
          FinnButton(
            label: 'Record first transaction',
            icon: LucideIcons.plus,
            variant: FinnButtonVariant.secondary,
            size: FinnButtonSize.lg,
            expand: true,
            onPressed: () => context.push(AppRoutes.newTransaction()),
          ),
        ],
      ),
    );
  }
}

/// Getting-started checklist for new users.
class SetupChecklistSection extends ConsumerWidget {
  const SetupChecklistSection({super.key});

  static String routeFor(SetupStep s) => switch (s) {
    SetupStep.profile => AppRoutes.profile,
    SetupStep.emergencyFund => AppRoutes.emergencyPlan,
    SetupStep.goal => AppRoutes.newGoal,
    SetupStep.budget => AppRoutes.newBudget,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final value = ref.watch(setupChecklistProvider);
    final done = value.value;
    return HomeSection(
      icon: LucideIcons.listChecks,
      title: 'Get set up',
      subtitle: done == null ? null : '${done.completed} of ${done.total} done · takes a few minutes',
      tileColor: c.accentTransactions,
      child: AsyncView<SetupChecklist>(
        value: value,
        loading: const SkeletonPulse(child: CardSkeleton(height: 240)),
        builder: (context, list) => HomeListCard(
          children: [
            for (final step in SetupStep.values)
              HomeRow(
                key: ValueKey(step),
                onTap: () => context.push(routeFor(step)),
                semanticLabel: list.isDone(step) ? '${step.title}, done' : step.title,
                leading: Icon(
                  list.isDone(step) ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: 22,
                  color: list.isDone(step) ? c.positive : c.textTertiary,
                ),
                title: step.title,
                subtitle: list.isDone(step) ? 'Done' : step.description,
                subtitleColor: list.isDone(step) ? c.positive : null,
                showChevron: true,
              ),
          ],
        ),
      ),
    );
  }
}
