import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../app/di/core_providers.dart';
import '../../../../app/di/data_providers.dart';
import '../../../../app/router/routes.dart';
import '../../../../core/money/money_format.dart';
import '../../../../core/time/dates.dart';
import '../../../../design_system/design_system.dart';
import '../../../../shared/presentation/async_view.dart';
import '../../../timeline/domain/timeline.dart';
import 'home_common.dart';

/// Plain-language summary of the current month.
class NarrativeSection extends ConsumerWidget {
  const NarrativeSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final month = ref.watch(todayProvider.select((d) => d.monthKey));
    return HomeSection(
      icon: LucideIcons.bookOpen,
      title: 'Your month so far',
      tileColor: c.accentAnalytics,
      child: AsyncView<List<String>>(
        value: ref.watch(monthlyNarrativeProvider(month)),
        loading: const SkeletonPulse(child: CardSkeleton(height: 132)),
        builder: (context, lines) => HomeListCard(
          footer: HomeCardLink(label: 'Read your monthly story', onTap: () => context.push(AppRoutes.timeline)),
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.x4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: Space.x2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: DotSeparator(size: 5, spacing: 0, color: c.accentAnalytics),
                        ),
                        const SizedBox(width: Space.x2_5),
                        Expanded(child: Text(lines[i], style: t.body)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The latest few moments from this month's story.
class RecentStorySection extends ConsumerWidget {
  const RecentStorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final month = ref.watch(todayProvider.select((d) => d.monthKey));
    return HomeSection(
      icon: LucideIcons.history,
      title: 'Recent moments',
      tileColor: c.accentGoals,
      actionLabel: 'Timeline',
      onAction: () => context.push(AppRoutes.timeline),
      child: AsyncView<StoryChapter>(
        value: ref.watch(storyChapterProvider(month)),
        loading: const SkeletonPulse(child: CardSkeleton(height: 200)),
        builder: (context, chapter) {
          final events = chapter.events.take(4).toList();
          if (events.isEmpty) {
            return HomeNoteCard(
              icon: LucideIcons.bookOpen,
              title: 'No key moments yet',
              message: 'Income, larger spends, loan payments and savings will appear here as your month unfolds.',
            );
          }
          return HomeListCard(
            children: [for (final e in events) _MomentRow(key: ValueKey(e.id), event: e)],
          );
        },
      ),
    );
  }
}

class _MomentRow extends StatelessWidget {
  const _MomentRow({super.key, required this.event});

  final TimelineEvent event;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final e = event;
    final route = e.route;
    return HomeRow(
      onTap: () => context.push(route ?? AppRoutes.timeline),
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surfaceMuted, shape: BoxShape.circle),
        child: ExcludeSemantics(child: Text(e.emoji, style: const TextStyle(fontSize: 18))),
      ),
      title: e.title,
      subtitle: '${DateFormats.dayMonth.format(e.date)} · ${e.kind.label}',
      trailing: AmountText(
        e.isInflow ? e.amount : -e.amount,
        sign: SignDisplay.always,
        decimals: DecimalDisplay.none,
        color: e.isInflow ? c.positive : c.textPrimary,
        style: context.text.amountSmall,
      ),
    );
  }
}
