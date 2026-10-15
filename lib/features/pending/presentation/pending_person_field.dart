import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../kit/kit.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Who the item is with. Typing searches FiNN users (debounced, so the
/// directory is asked once the user pauses). Picking a FiNN user shares the
/// item with them — it then shows in their account too (double entry).
/// Any other name keeps the item private.
class PendingPersonField extends ConsumerStatefulWidget {
  const PendingPersonField({
    super.key,
    required this.controller,
    required this.linked,
    required this.onLinked,
    required this.label,
    required this.direction,
    this.recentNames = const [],
    this.locked = false,
    this.errorText,
    this.debounce = const Duration(milliseconds: 350),
  });

  final TextEditingController controller;
  final FinnUser? linked;
  final ValueChanged<FinnUser?> onLinked;
  final String label;
  final PendingDirection direction;

  /// Names used before, offered while the field is empty.
  final List<String> recentNames;

  /// Shared items keep their person.
  final bool locked;
  final String? errorText;
  final Duration debounce;

  @override
  ConsumerState<PendingPersonField> createState() => _PendingPersonFieldState();
}

class _PendingPersonFieldState extends ConsumerState<PendingPersonField> {
  Timer? _timer;
  String _query = '';
  bool _searching = false;
  List<FinnUser> _results = const [];

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    final q = text.trim();
    setState(() {
      _query = q;
      _searching = q.length >= 2;
      if (q.length < 2) _results = const [];
    });
    if (q.length < 2) return;
    _timer = Timer(widget.debounce, () => _search(q));
  }

  Future<void> _search(String q) async {
    final users = ref.read(userDirectoryProvider);
    final found = await users.search(q);
    // Ignore answers to a query the user has already typed past.
    if (!mounted || q != _query) return;
    setState(() {
      _results = found;
      _searching = false;
    });
  }

  void _pick(FinnUser u) {
    HapticFeedback.selectionClick();
    _timer?.cancel();
    widget.controller.text = u.name;
    setState(() {
      _query = '';
      _results = const [];
      _searching = false;
    });
    FocusScope.of(context).unfocus();
    widget.onLinked(u);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final linked = widget.linked;
    return MotionAnimatedSize(
      child: linked != null
          ? LedgerField(
              label: widget.label,
              child: _LinkedCard(
                user: linked,
                direction: widget.direction,
                onUnlink: widget.locked
                    ? null
                    : () {
                        widget.onLinked(null);
                        _changed(widget.controller.text);
                      },
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LedgerTextField(
                  label: widget.label,
                  hint: 'Name or @handle',
                  controller: widget.controller,
                  prefixIcon: LucideIcons.search,
                  errorText: widget.errorText,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onChanged: _changed,
                ),
                if (_query.length >= 2) ...[
                  const SizedBox(height: Sp.sm),
                  _Results(
                    query: _query,
                    searching: _searching,
                    results: _results,
                    onPick: _pick,
                  ),
                ] else if (_query.isEmpty && widget.recentNames.isNotEmpty) ...[
                  const SizedBox(height: Sp.sm),
                  Wrap(
                    spacing: Sp.sm,
                    runSpacing: Sp.sm,
                    children: [
                      for (final n in widget.recentNames)
                        LedgerChip(
                          label: n,
                          icon: LucideIcons.history,
                          onTap: () {
                            widget.controller.text = n;
                            _changed(n);
                          },
                        ),
                    ],
                  ),
                ] else if (_query.isEmpty) ...[
                  const SizedBox(height: Sp.xs + 2),
                  Text(
                    'Pick a FiNN user to share it, or type any name to keep it private.',
                    style: t.small,
                  ),
                ],
              ],
            ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.query,
    required this.searching,
    required this.results,
    required this.onPick,
  });

  final String query;
  final bool searching;
  final List<FinnUser> results;
  final ValueChanged<FinnUser> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    if (searching) {
      return Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.inkSoft),
          ),
          const SizedBox(width: Sp.sm),
          Expanded(child: Text('Searching FiNN for "$query"…', style: t.small)),
        ],
      );
    }
    if (results.isEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.lock, size: 14, color: c.inkSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text(
              'No FiNN user matches. "$query" stays private to you.',
              style: t.small,
            ),
          ),
        ],
      );
    }
    return LedgerPanel(
      dividerIndent: Sp.lg + 36 + Sp.md,
      children: [
        for (var i = 0; i < results.length && i < 5; i++)
          _UserTile(
            key: ValueKey('finn-user:${results[i].id}'),
            user: results[i],
            onTap: () => onPick(results[i]),
          ),
      ],
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({super.key, required this.user, required this.onTap});

  final FinnUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Semantics(
      button: true,
      label: '${user.name}, ${user.handle}, on FiNN. Share with them',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.lg,
              vertical: Sp.sm,
            ),
            child: Row(
              children: [
                PendingInitials(name: user.name, size: 36),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: t.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        [user.handle, ?user.phoneHint].join(' · '),
                        style: t.small,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Sp.sm),
                Icon(LucideIcons.link2, size: 16, color: c.inkSoft),
                const SizedBox(width: Sp.xs),
                Text('On FiNN', style: t.small),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LinkedCard extends StatelessWidget {
  const _LinkedCard({
    required this.user,
    required this.direction,
    required this.onUnlink,
  });

  final FinnUser user;
  final PendingDirection direction;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final first = user.name.split(' ').first;
    return Container(
      key: const ValueKey('pending-linked-user'),
      padding: const EdgeInsets.fromLTRB(Sp.md + 2, Sp.sm, Sp.xs, Sp.sm),
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rMd),
      child: Row(
        children: [
          PendingInitials(name: user.name, shared: true, size: 40),
          const SizedBox(width: Sp.md + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${user.name} · ${user.handle}',
                  style: t.bodyStrong,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  direction.isOwe
                      ? 'Shared: it also shows in $first’s FiNN as money you owe them.'
                      : 'Shared: it also shows in $first’s FiNN as money they owe you.',
                  style: t.small,
                ),
              ],
            ),
          ),
          if (onUnlink != null)
            LedgerIconButton(
              icon: LucideIcons.x,
              tooltip: 'Do not share with ${user.name}',
              onPressed: onUnlink,
            )
          else
            Padding(
              padding: const EdgeInsets.all(Sp.md),
              child: Icon(LucideIcons.lock, size: 16, color: c.inkSoft),
            ),
        ],
      ),
    );
  }
}
