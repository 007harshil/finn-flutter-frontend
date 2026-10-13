import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/router/routes.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart' show AmountText;
import '../../../shared/presentation/category_icons.dart';
import '../../../ui/ui.dart';
import '../application/goal_view.dart';
import '../domain/goal.dart';
import 'savings_widgets.dart';

/// Pace of a goal as colour + icon; calm paces stay ink.
extension GoalPaceUi on GoalPace {
  Color color(UiColors c) => switch (this) {
    GoalPace.behind => c.warning,
    GoalPace.onTrack || GoalPace.done => c.positive,
    GoalPace.noPlan || GoalPace.archived => c.inkSoft,
  };

  IconData get icon => switch (this) {
    GoalPace.behind => LucideIcons.clock,
    GoalPace.onTrack => LucideIcons.circleCheck,
    GoalPace.noPlan => LucideIcons.circleDashed,
    GoalPace.done => LucideIcons.partyPopper,
    GoalPace.archived => LucideIcons.archive,
  };

  String countLabel(int n) => switch (this) {
    GoalPace.behind => '$n behind',
    GoalPace.onTrack => '$n on track',
    GoalPace.noPlan => '$n without a plan',
    GoalPace.done => '$n done',
    GoalPace.archived => '$n archived',
  };
}

String formatPct(double share) => '${(share * 100).round()}%';

/// One goal as a row of a kit panel: category mark, name and what is
/// saved, a thin bar of the target, one line on what is left and when,
/// and a one-tap "add money" for goals still being funded.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.progress, required this.today, this.onLongPress});

  final GoalProgress progress;
  final DateTime today;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final g = progress;
    final pace = goalPaceOf(g);
    final archived = g.goal.status == GoalStatus.archived;
    final fundable = g.goal.status == GoalStatus.active && !g.isAchieved;
    final date = g.goal.targetDate;
    final hint = [
      if (g.isAchieved) 'Target reached' else '${savingsMoney(context, g.remaining)} to go',
      if (date != null && !g.isAchieved) 'by ${DateFormats.shortMonthYear.format(date)}',
    ].join(' · ');
    final attention = pace == GoalPace.behind;
    final long = onLongPress;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label:
                '${g.goal.name}. ${savingsMoney(context, g.saved)} saved of ${savingsMoney(context, g.goal.target)}, '
                '${formatPct(g.progress)}. ${pace.label}. $hint.',
            excludeSemantics: true,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                context.push(AppRoutes.goal(g.goal.id));
              },
              onLongPress: long == null
                  ? null
                  : () {
                      HapticFeedback.mediumImpact();
                      long();
                    },
              child: Padding(
                padding: EdgeInsets.fromLTRB(UiSpace.lg, 14, fundable ? 0 : UiSpace.lg, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Opacity(
                      opacity: archived ? 0.5 : 1,
                      child: UiMark(
                        icon: CategoryIcons.of(g.goal.category.iconKey),
                        color: g.isAchieved ? c.positive : null,
                      ),
                    ),
                    const SizedBox(width: UiSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  g.goal.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.body.copyWith(color: archived ? c.inkSoft : null),
                                ),
                              ),
                              const SizedBox(width: UiSpace.sm),
                              AmountText(g.saved, style: t.figureSmall, decimals: DecimalDisplay.none),
                            ],
                          ),
                          const SizedBox(height: UiSpace.sm),
                          UiProgress(value: g.progress, color: g.isAchieved ? c.positive : c.goals, height: 4),
                          const SizedBox(height: UiSpace.sm),
                          Row(
                            children: [
                              if (attention) ...[
                                Icon(pace.icon, size: 13, color: pace.color(c)),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  hint,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: t.small.copyWith(color: attention ? pace.color(c) : null),
                                ),
                              ),
                              const SizedBox(width: UiSpace.sm),
                              Text(formatPct(g.progress), style: t.small),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (fundable)
          Padding(
            padding: const EdgeInsets.only(right: UiSpace.xs),
            child: UiIconButton(
              key: ValueKey('goal-add:${g.goal.id}'),
              icon: LucideIcons.plus,
              size: 20,
              tooltip: 'Add money to ${g.goal.name}',
              onPressed: () => context.push(AppRoutes.goalContribute(g.goal.id)),
            ),
          ),
      ],
    );
  }
}

/// One contribution or withdrawal as a read-only row.
class SavingsMovementRow extends StatelessWidget {
  const SavingsMovementRow({super.key, required this.movement});

  final SavingsMovement movement;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final m = movement;
    final added = m.kind == SavingsMovementKind.contribution;
    final note = m.note?.trim();
    return UiListRow(
      leading: UiMark(icon: added ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight, size: 32),
      title: added ? 'Added' : 'Withdrew',
      subtitle: [DateFormats.dayMonthYear.format(m.date), if (note != null && note.isNotEmpty) note].join(' · '),
      trailing: AmountText(
        m.signedAmount,
        sign: SignDisplay.always,
        style: t.figureSmall.copyWith(color: added ? c.positive : null),
      ),
      onTap: null,
    );
  }
}
