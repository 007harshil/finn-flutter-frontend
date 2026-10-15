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
import '../../../kit/kit.dart';

/// Audit trail of every operation run through the action dispatcher.
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(auditEntriesProvider);
    return LedgerPage(
      storageKey: 'activity-log',
      appBar: const LedgerAppBar(title: 'Activity log'),
      slivers: switch (entries) {
        AsyncValue(:final value?) => _body(context, ref, value),
        AsyncValue(hasError: true) => const [
          PageBlock(
            top: Sp.xl,
            child: LedgerEmpty(
              title: 'Could not load activity',
              message: 'Please go back and try again.',
            ),
          ),
        ],
        _ => const [SliverToBoxAdapter(child: LedgerPageSkeleton(rows: 6))],
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

List<Widget> _body(BuildContext context, WidgetRef ref, List<AuditEntry> entries) {
  if (entries.isEmpty) {
    return const [
      PageBlock(
        top: Sp.xl,
        child: LedgerEmpty(
          icon: LucideIcons.history,
          title: 'No activity yet',
          message:
              'Changes you make, like adding a transaction or paying an EMI, are listed here while the app is open.',
        ),
      ),
    ];
  }
  final today = ref.watch(todayProvider);
  final days = <String, List<(int, AuditEntry)>>{};
  for (var i = 0; i < entries.length; i++) {
    days.putIfAbsent(_dayLabel(entries[i].at, today), () => []).add((i, entries[i]));
  }
  final failed = entries.where((e) => !e.succeeded).length;
  return [
    PageBlock(
      top: Sp.sm,
      child: LedgerNote(
        text:
            '${entries.length} change${entries.length == 1 ? '' : 's'} this session'
            '${failed > 0 ? ', $failed not completed' : ''}. Kept only while the app is open.',
      ),
    ),
    for (final day in days.entries)
      PageBlock(
        key: ValueKey('day-${day.key}'),
        top: Sp.section,
        child: LedgerSection(
          title: day.key,
          child: LedgerPanel(
            children: [
              for (final (i, e) in day.value)
                _EntryRow(
                  key: ValueKey('${e.actionId}-${e.at.microsecondsSinceEpoch}-$i'),
                  entry: e,
                ),
            ],
          ),
        ),
      ),
    const SliverToBoxAdapter(child: SizedBox(height: Sp.xl)),
  ];
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({super.key, required this.entry});
  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.ink;
    final descriptor = ref.watch(actionRegistryProvider).lookup(entry.actionId)?.descriptor;
    final hidden = AmountVisibility.hiddenOf(context);
    final ok = entry.succeeded;
    var summary = entry.summary;
    if (hidden) summary = summary.replaceAll(RegExp(r'[−+-]?₹[\d,]+(\.\d+)?'), MoneyFormatter.masked);
    final meta = [
      descriptor?.title ?? entry.actionId,
      _channelLabel(entry.channel),
      DateFormat('h:mm a').format(entry.at),
      if (ok && entry.confirmedBy != null) 'Reviewed before saving',
    ].join(' · ');
    final failure = !ok && entry.failure != null ? 'Not completed: ${entry.failure}' : null;
    return LedgerRow(
      leading: IconWell(
        icon: ok ? LucideIcons.check : LucideIcons.x,
        color: ok ? null : c.red,
        background: ok ? null : c.redSoft,
      ),
      title: summary,
      titleLines: 2,
      subtitle: failure ?? meta,
      subtitleColor: failure == null ? null : c.red,
      subtitleLines: 2,
    );
  }
}
