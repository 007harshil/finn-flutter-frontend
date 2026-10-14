import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../actions/action.dart';
import '../../../actions/audit_log.dart';
import '../../../app/di/action_providers.dart';
import '../../../app/di/core_providers.dart';
import '../../../core/money/money_format.dart';
import '../../../core/time/dates.dart';
import '../../../design_system/design_system.dart';

/// Audit trail of every operation run through the action dispatcher.
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditEntriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: switch (entries) {
        AsyncValue(:final value?) => _Body(entries: value),
        AsyncValue(hasError: true) => const Center(
            child: Padding(
              padding: EdgeInsets.all(Space.x6),
              child: ErrorState(title: 'Could not load activity', message: 'Please go back and try again.'),
            ),
          ),
        _ => const SkeletonPulse(child: ListSkeleton(count: 6)),
      },
    );
  }
}

String _channelLabel(ActionChannel c) => switch (c) {
      ActionChannel.ui => 'You',
      ActionChannel.agent => 'Assistant',
      ActionChannel.voice => 'Voice',
      ActionChannel.import => 'Import',
      ActionChannel.system => 'FiNN',
    };

String _dayLabel(DateTime d, DateTime today) {
  final day = d.dateOnly;
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return DateFormats.weekdayDayMonth.format(day);
}

class _Body extends ConsumerWidget {
  const _Body({required this.entries});
  final List<AuditEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.gutter),
          child: EmptyState(
            icon: LucideIcons.history,
            title: 'No activity yet',
            message: 'Changes you make — adding a transaction, paying an EMI, updating a goal — '
                'are listed here while the app is open.',
          ),
        ),
      );
    }
    final today = ref.watch(todayProvider);
    final items = <Object>[];
    String? lastDay;
    for (final e in entries) {
      final label = _dayLabel(e.at, today);
      if (label != lastDay) {
        items.add(label);
        lastDay = label;
      }
      items.add(e);
    }
    final failed = entries.where((e) => !e.succeeded).length;
    return ListView.builder(
      key: const PageStorageKey('activity-log'),
      padding: EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x10 + context.safeBottom),
      itemCount: items.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return ResponsiveCenter(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
            child: InfoBanner(
              tone: FinnTone.info,
              message: '${entries.length} change${entries.length == 1 ? '' : 's'} this session'
                  '${failed > 0 ? ', $failed not completed' : ''}. '
                  'The log is kept only while the app is open.',
            ),
          );
        }
        final item = items[i - 1];
        if (item is String) {
          return ResponsiveCenter(
            key: ValueKey('day-$item'),
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x4, Space.gutter, Space.x2),
            child: Semantics(header: true, child: Text(item.toUpperCase(), style: context.text.sectionTitle)),
          );
        }
        final e = item as AuditEntry;
        return ResponsiveCenter(
          key: ValueKey('${e.actionId}-${e.at.microsecondsSinceEpoch}-$i'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x2),
          child: _EntryTile(entry: e),
        );
      },
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final descriptor = ref.watch(actionRegistryProvider).lookup(entry.actionId)?.descriptor;
    final hidden = AmountVisibility.hiddenOf(context);
    final ok = entry.succeeded;
    final tone = ok ? FinnTone.positive : FinnTone.negative;
    var summary = entry.summary;
    if (hidden) summary = summary.replaceAll(RegExp(r'[−+-]?₹[\d,]+(\.\d+)?'), MoneyFormatter.masked);
    final meta = [
      descriptor?.title ?? entry.actionId,
      _channelLabel(entry.channel),
      DateFormat('h:mm a').format(entry.at),
    ].join(' · ');
    return FinnCard(
      padding: const EdgeInsets.all(Space.x3 + 2),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: ok ? LucideIcons.circleCheck : LucideIcons.circleX,
              background: tone.soft(c),
              foreground: tone.color(c),
              size: 32,
              radius: Radii.md,
              iconSize: 16,
            ),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(summary, style: t.bodyStrong),
                  const SizedBox(height: Space.x0_5),
                  Text(meta, style: t.caption),
                  if (!ok && entry.failure != null) ...[
                    const SizedBox(height: Space.x1),
                    Text('Not completed: ${entry.failure}', style: t.caption.copyWith(color: c.negative)),
                  ],
                  if (ok && entry.confirmedBy != null) ...[
                    const SizedBox(height: Space.x1_5),
                    StatusPill(label: 'Reviewed before saving', color: c.info, icon: LucideIcons.shieldCheck),
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
