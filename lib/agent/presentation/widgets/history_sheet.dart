import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/result/result.dart';
import '../../../kit/kit.dart';
import '../../application/agent_providers.dart';
import '../../history/agent_history.dart';

/// Opens the agent history: what the user asked the agent to do and what
/// was actually saved, newest first, a page at a time.
Future<void> showAgentHistory(BuildContext context) =>
    showFinnSheet<void>(context, builder: (_) => const AgentHistorySheet());

class AgentHistorySheet extends ConsumerStatefulWidget {
  const AgentHistorySheet({super.key});

  static const pageSize = 20;

  @override
  ConsumerState<AgentHistorySheet> createState() => _AgentHistorySheetState();
}

class _AgentHistorySheetState extends ConsumerState<AgentHistorySheet> {
  final _items = <AgentHistoryEntry>[];
  final _expanded = <String>{};
  String? _nextBefore;
  AgentRunStatus? _filter;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref
          .read(agentHistoryProvider)
          .list(limit: AgentHistorySheet.pageSize, before: reset ? null : _nextBefore, status: _filter);
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _nextBefore = page.nextBefore;
      });
    } on AppFailure catch (f) {
      if (mounted) setState(() => _error = f.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Your history could not be loaded.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showFinnConfirm(
      context,
      title: 'Clear agent history?',
      message: 'This removes the list of what you asked the agent. Your saved records are not changed.',
      confirmLabel: 'Clear history',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(agentHistoryProvider).clear();
      if (mounted) await _load(reset: true);
    } on AppFailure catch (f) {
      if (mounted) FinnToast.error(context, f.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return FinnSheetScaffold(
      title: 'Agent history',
      description: 'What you asked FiNN to do and what was saved. Kept for 180 days and never sent to the AI.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerChoiceChips<AgentRunStatus?>(
            options: [const LedgerOption(null, 'All'), for (final s in AgentRunStatus.values) LedgerOption(s, s.label)],
            selected: _filter,
            onChanged: (v) {
              setState(() => _filter = v);
              _load(reset: true);
            },
          ),
          const SizedBox(height: Sp.lg),
          if (_error != null && _items.isEmpty)
            LedgerEmpty(
              icon: LucideIcons.cloudOff,
              title: 'Could not load history',
              message: _error!,
              actionLabel: 'Try again',
              onAction: () => _load(reset: true),
            )
          else if (_items.isEmpty && _loading)
            Semantics(
              label: 'Loading',
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++) ...[const LedgerSkeleton(height: 60), const SizedBox(height: Sp.sm)],
                ],
              ),
            )
          else if (_items.isEmpty)
            LedgerEmpty(
              icon: LucideIcons.history,
              title: _filter == null ? 'Nothing here yet' : 'No ${_filter!.label.toLowerCase()} requests',
              message: 'Changes you ask the agent to make will appear here.',
            )
          else ...[
            LedgerPanel(
              children: [
                for (final e in _items)
                  _EntryRow(
                    entry: e,
                    expanded: _expanded.contains(e.id),
                    onTap: () =>
                        setState(() => _expanded.contains(e.id) ? _expanded.remove(e.id) : _expanded.add(e.id)),
                  ),
              ],
            ),
            if (_nextBefore != null) ...[
              const SizedBox(height: Sp.md),
              LedgerButton(
                label: 'Show older',
                variant: LedgerButtonVariant.secondary,
                expand: true,
                loading: _loading,
                onPressed: _load,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Sp.sm),
              Text(_error!, style: t.label.copyWith(color: c.red)),
            ],
            const SizedBox(height: Sp.md),
            Align(
              alignment: Alignment.centerLeft,
              child: LedgerButton(
                label: 'Clear history',
                icon: LucideIcons.trash2,
                variant: LedgerButtonVariant.quiet,
                color: c.inkSoft,
                onPressed: _clear,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.expanded, required this.onTap});

  final AgentHistoryEntry entry;
  final bool expanded;
  final VoidCallback onTap;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _when(DateTime t) {
    final now = DateTime.now();
    final day = DateTime(t.year, t.month, t.day);
    final today = DateTime(now.year, now.month, now.day);
    final time = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    if (day == today) return 'Today $time';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday $time';
    return '${t.day} ${_months[t.month - 1]}${t.year == now.year ? '' : ' ${t.year}'} $time';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final (Color tone, IconData icon) = switch (entry.status) {
      AgentRunStatus.completed => (c.green, LucideIcons.circleCheck),
      AgentRunStatus.partial => (c.amber, LucideIcons.circleAlert),
      AgentRunStatus.failed => (c.red, LucideIcons.circleX),
      AgentRunStatus.declined => (c.inkSoft, LucideIcons.circleSlash),
    };
    final details = expanded && (entry.operations.isNotEmpty || entry.notes.isNotEmpty);
    return Semantics(
      expanded: expanded,
      child: LedgerRow(
        title: '"${entry.request}"',
        titleLines: expanded ? 6 : 2,
        subtitle: '${_when(entry.createdAt)} · ${entry.summary}',
        subtitleLines: expanded ? 3 : 1,
        leading: Icon(icon, size: 20, color: tone),
        trailing: Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: c.inkSoft),
        semanticLabel: expanded ? null : '${entry.request}. ${entry.status.label}. ${entry.summary}',
        onTap: onTap,
        below: details
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final op in entry.operations) _OperationLine(op: op),
                  for (final note in entry.notes)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.xs),
                      child: Text(note, style: t.label),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class _OperationLine extends StatelessWidget {
  const _OperationLine({required this.op});
  final AgentHistoryOperation op;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final (Color tone, String label) = switch (op.status) {
      'saved' => (c.green, 'Saved'),
      'alreadySaved' => (c.green, 'Already saved'),
      'declined' => (c.inkSoft, 'Declined'),
      'skipped' => (c.inkSoft, 'Skipped'),
      'changed' => (c.amber, 'Changed before saving'),
      _ => (c.red, 'Failed'),
    };
    return Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(op.summary, style: t.label.copyWith(color: c.ink)),
              ),
              const SizedBox(width: Sp.sm),
              Text(
                label,
                style: t.small.copyWith(color: tone, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (op.message case final m?) Text(m, style: t.small),
        ],
      ),
    );
  }
}
