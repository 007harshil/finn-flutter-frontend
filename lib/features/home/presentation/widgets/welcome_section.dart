import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/router/routes.dart';
import '../../../../design_system/luxe/luxe.dart';
import '../../application/home_overview.dart';

/// First-run welcome: one sentence of promise and the one action that
/// starts everything.
class WelcomeCard extends StatelessWidget {
  const WelcomeCard({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.luxe;
    final t = context.lt;
    return LuxeCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('A FRESH START', style: t.eyebrow.c(p.goldInk)),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Welcome to '),
                TextSpan(
                  text: 'FiNN',
                  style: TextStyle(fontStyle: FontStyle.italic, color: p.goldInk),
                ),
              ],
            ),
            style: t.title.copyWith(fontSize: 30, height: 1.1),
          ),
          const SizedBox(height: 10),
          Text(
            'Your calm, private command centre for money. Record your first transaction and everything else '
            'builds from there.',
            style: t.bodySoft,
          ),
          const SizedBox(height: 22),
          LuxeButton(
            label: 'Record first transaction',
            icon: LucideIcons.plus,
            expand: true,
            onPressed: () => context.push(AppRoutes.newTransaction()),
          ),
        ],
      ),
    );
  }
}

/// Getting-started checklist for new users, with a ring for progress.
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
    final p = context.luxe;
    final t = context.lt;
    final value = ref.watch(setupChecklistProvider);
    final list = value.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LuxeSectionHeader(
          title: 'Get set up',
          caption: list == null ? null : '${list.completed} of ${list.total} done · takes a few minutes',
          trailing: list == null
              ? null
              : LuxeRing(
                  value: list.completed / list.total,
                  color: p.gold,
                  size: 40,
                  stroke: 2.5,
                  child: Text('${list.completed}/${list.total}', style: t.micro.w(700).c(p.ink)),
                ),
        ),
        const SizedBox(height: 14),
        if (list == null)
          const LuxeShimmer(child: LuxeBone(height: 260, radius: LuxeSpace.rCard))
        else
          LuxeCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (i, step) in SetupStep.values.indexed) ...[
                  if (i > 0) const LuxeHairline(indent: 64, endIndent: 20),
                  Reveal(
                    index: i,
                    blur: 0,
                    offset: 10,
                    child: Squish(
                      key: ValueKey(step),
                      onTap: () => context.push(routeFor(step)),
                      scale: 0.985,
                      semanticLabel: list.isDone(step) ? '${step.title}, done' : step.title,
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: LuxeDurations.base,
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: list.isDone(step) ? p.positive : Colors.transparent,
                                border: Border.all(color: list.isDone(step) ? p.positive : p.lineStrong),
                              ),
                              child: list.isDone(step)
                                  ? Icon(LucideIcons.check, size: 15, color: p.canvas)
                                  : Center(child: Text('${i + 1}', style: t.micro.w(700).c(p.inkSoft))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    step.title,
                                    style: t.heading.copyWith(
                                      fontSize: 15,
                                      decoration: list.isDone(step) ? TextDecoration.lineThrough : null,
                                      decorationColor: p.inkMute,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    list.isDone(step) ? 'Done' : step.description,
                                    style: t.caption.c(list.isDone(step) ? p.positive : p.inkSoft),
                                  ),
                                ],
                              ),
                            ),
                            Icon(LucideIcons.chevronRight, size: 16, color: p.inkMute),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
