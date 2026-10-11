import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../design_system/design_system.dart';
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
    final t = context.text;
    final linked = widget.linked;
    return MotionAnimatedSize(
      child: linked != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PendingFieldLabel(widget.label),
                _LinkedCard(
                  user: linked,
                  direction: widget.direction,
                  onUnlink: widget.locked
                      ? null
                      : () {
                          widget.onLinked(null);
                          _changed(widget.controller.text);
                        },
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FinnTextField(
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
                  const SizedBox(height: Space.x2),
                  _Results(
                    query: _query,
                    searching: _searching,
                    results: _results,
                    onPick: _pick,
                  ),
                ] else if (_query.isEmpty && widget.recentNames.isNotEmpty) ...[
                  const SizedBox(height: Space.x2),
                  Wrap(
                    spacing: Space.x2,
                    runSpacing: Space.x1,
                    children: [
                      for (final n in widget.recentNames)
                        ActionChip(
                          avatar: const Icon(LucideIcons.history, size: 14),
                          label: Text(n),
                          onPressed: () {
                            widget.controller.text = n;
                            _changed(n);
                          },
                        ),
                    ],
                  ),
                ] else if (_query.isEmpty) ...[
                  const SizedBox(height: Space.x1_5),
                  Text('Search a FiNN user to share this with them, or type any name to keep it private.',
                      style: t.micro),
                ],
              ],
            ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query, required this.searching, required this.results, required this.onPick});

  final String query;
  final bool searching;
  final List<FinnUser> results;
  final ValueChanged<FinnUser> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    if (searching) {
      return Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.textTertiary),
          ),
          const SizedBox(width: Space.x2),
          Text('Searching FiNN for "$query"…', style: t.caption),
        ],
      );
    }
    if (results.isEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.lock, size: 13, color: c.textTertiary),
          const SizedBox(width: Space.x1_5),
          Expanded(
            child: Text('No FiNN user matches. "$query" will be a private item only you see.', style: t.caption),
          ),
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: Radii.rLg,
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          for (var i = 0; i < results.length && i < 5; i++) ...[
            if (i > 0) const FinnDivider(indent: Space.x3 + 36 + Space.x3),
            _UserTile(key: ValueKey('finn-user:${results[i].id}'), user: results[i], onTap: () => onPick(results[i])),
          ],
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({super.key, required this.user, required this.onTap});

  final FinnUser user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return Semantics(
      button: true,
      label: '${user.name}, ${user.handle}, on FiNN. Share with them',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
          child: Row(
            children: [
              PendingAvatar(name: user.name, color: c.info, size: 36),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [user.handle, ?user.phoneHint].join(' · '),
                      style: t.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              StatusPill(label: 'On FiNN', color: c.info, icon: LucideIcons.link2),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkedCard extends StatelessWidget {
  const _LinkedCard({required this.user, required this.direction, required this.onUnlink});

  final FinnUser user;
  final PendingDirection direction;
  final VoidCallback? onUnlink;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final first = user.name.split(' ').first;
    return Container(
      key: const ValueKey('pending-linked-user'),
      padding: const EdgeInsets.fromLTRB(Space.x3, Space.x3, Space.x1, Space.x3),
      decoration: BoxDecoration(
        color: c.infoSoft,
        borderRadius: Radii.rLg,
        border: Border.all(color: c.info.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          PendingAvatar(name: user.name, color: c.info, size: 40),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${user.name} · ${user.handle}', style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  direction.isOwe
                      ? 'Shared: it also shows in $first’s FiNN as money you owe them.'
                      : 'Shared: it also shows in $first’s FiNN as money they owe you.',
                  style: t.caption,
                ),
              ],
            ),
          ),
          if (onUnlink != null)
            FinnIconButton(icon: LucideIcons.x, tooltip: 'Do not share with ${user.name}', onPressed: onUnlink)
          else
            Padding(
              padding: const EdgeInsets.all(Space.x2),
              child: Icon(LucideIcons.lock, size: 16, color: c.textTertiary),
            ),
        ],
      ),
    );
  }
}
