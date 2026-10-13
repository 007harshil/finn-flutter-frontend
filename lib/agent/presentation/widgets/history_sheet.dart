import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/result/result.dart';
import '../../../design_system/design_system.dart';
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
    final c = context.colors;
    final t = context.text;
    return FinnSheetScaffold(
      title: 'Agent history',
      description: 'What you asked FiNN to do and what was saved. Kept for 180 days and never sent to the AI.',
      bodyPadding: const EdgeInsets.fromLTRB(0, Space.x2, 0, Space.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilterChipBar<AgentRunStatus?>(
            multiSelect: false,
            padding: const EdgeInsets.symmetric(horizontal: Space.x5),
            items: [
              const FilterChipItem(null, 'All'),
              for (final s in AgentRunStatus.values) FilterChipItem(s, s.label),
            ],
            selected: {_filter},
            onChanged: (v) {
              setState(() => _filter = v.firstOrNull);
              _load(reset: true);
            },
          ),
          const SizedBox(height: Space.x3),
          if (_error != null && _items.isEmpty)
            ErrorState(message: _error, onRetry: () => _load(reset: true))
          else if (_items.isEmpty && _loading)
            const Padding(padding: EdgeInsets.symmetric(horizontal: Space.x5), child: ListSkeleton())
          else if (_items.isEmpty)
            EmptyState(
              icon: LucideIcons.history,
              title: _filter == null ? 'Nothing here yet' : 'No ${_filter!.label.toLowerCase()} requests',
              message: 'Changes you ask the agent to make will appear here.',
            )
          else ...[
            for (final e in _items)
              _EntryTile(
                entry: e,
                expanded: _expanded.contains(e.id),
                onTap: () => setState(() => _expanded.contains(e.id) ? _expanded.remove(e.id) : _expanded.add(e.id)),
              ),
            if (_nextBefore != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, 0),
                child: FinnButton(
                  label: 'Show older',
                  variant: FinnButtonVariant.secondary,
                  loading: _loading,
                  onPressed: _load,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.x5, Space.x2, Space.x5, 0),
                child: Text(_error!, style: t.caption.copyWith(color: c.negative)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x5, Space.x4, Space.x5, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FinnButton(
                  label: 'Clear history',
                  icon: LucideIcons.trash2,
                  variant: FinnButtonVariant.ghost,
                  size: FinnButtonSize.sm,
                  onPressed: _clear,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.expanded, required this.onTap});

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
    final c = context.colors;
    final t = context.text;
    final (Color tone, IconData icon) = switch (entry.status) {
      AgentRunStatus.completed => (c.positive, LucideIcons.badgeCheck),
      AgentRunStatus.partial => (c.warning, LucideIcons.circleAlert),
      AgentRunStatus.failed => (c.negative, LucideIcons.circleX),
      AgentRunStatus.declined => (c.textTertiary, LucideIcons.circleSlash),
    };
    return Semantics(
      button: true,
      expanded: expanded,
      label: '${entry.request}. ${entry.status.label}. ${entry.summary}',
      excludeSemantics: !expanded,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x5, vertical: Space.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 18, color: tone)),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '"${entry.request}"',
                          maxLines: expanded ? 6 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.bodyStrong.copyWith(color: c.textPrimary),
                        ),
                        const SizedBox(height: Space.x1),
                        Text(
                          '${_when(entry.createdAt)} · ${entry.summary}',
                          style: t.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Icon(expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown, size: 18, color: c.textTertiary),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: Space.x2),
                for (final op in entry.operations) _OperationRow(op: op),
                for (final note in entry.notes)
                  Padding(
                    padding: const EdgeInsets.only(left: Space.x8, top: Space.x1),
                    child: Text(note, style: t.caption.copyWith(color: c.textSecondary)),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationRow extends StatelessWidget {
  const _OperationRow({required this.op});
  final AgentHistoryOperation op;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (Color tone, String label) = switch (op.status) {
      'saved' => (c.positive, 'Saved'),
      'alreadySaved' => (c.positive, 'Already saved'),
      'declined' => (c.textTertiary, 'Not approved'),
      'skipped' => (c.textTertiary, 'Skipped'),
      'changed' => (c.warning, 'Changed before saving'),
      _ => (c.negative, 'Failed'),
    };
    return Padding(
      padding: const EdgeInsets.only(left: Space.x8, top: Space.x1_5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(op.summary, style: t.body.copyWith(color: c.textPrimary))),
              const SizedBox(width: Space.x2),
              Text(label.toUpperCase(), style: t.micro.copyWith(color: tone, fontWeight: FontWeight.w800)),
            ],
          ),
          if (op.message case final m?) Text(m, style: t.caption.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
