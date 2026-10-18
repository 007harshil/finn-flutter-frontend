import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../app/router/routes.dart';
import '../../../kit/kit.dart';
import '../domain/pending_payment.dart';
import 'pending_ui.dart';

/// Who the item is with. Only friends can be linked: the field offers them
/// as chips while empty and filters them by name as the user types. Picking
/// a friend shares the item with them — it then shows in their account too
/// (double entry). Any other name keeps the item private.
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

  @override
  ConsumerState<PendingPersonField> createState() => _PendingPersonFieldState();
}

class _PendingPersonFieldState extends ConsumerState<PendingPersonField> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Make sure the friend list is current (remote); failures leave the
    // last known list in place.
    final directory = ref.read(friendDirectoryProvider);
    if (!directory.current.loaded) {
      directory.refresh().then((_) {}, onError: (Object _) {});
    }
  }

  void _changed(String text) => setState(() => _query = text.trim());

  void _pick(FinnUser u) {
    HapticFeedback.selectionClick();
    widget.controller.text = u.name;
    setState(() => _query = '');
    FocusScope.of(context).unfocus();
    widget.onLinked(u);
  }

  List<FinnUser> _friends() {
    final state = ref.watch(friendStateProvider).value ?? ref.read(friendDirectoryProvider).current;
    return [for (final f in state.friends) f.user];
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final linked = widget.linked;
    if (linked != null) {
      return MotionAnimatedSize(
        child: LedgerField(
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
        ),
      );
    }
    final friends = _friends();
    final q = _query.toLowerCase();
    final matches = [
      for (final u in friends)
        if (u.name.toLowerCase().contains(q)) u,
    ];
    return MotionAnimatedSize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LedgerTextField(
            label: widget.label,
            hint: 'Name, or pick a friend',
            controller: widget.controller,
            prefixIcon: LucideIcons.userRound,
            errorText: widget.errorText,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onChanged: _changed,
          ),
          if (_query.isNotEmpty) ...[
            const SizedBox(height: Sp.sm),
            _Results(query: _query, results: matches, onPick: _pick),
          ] else ...[
            if (friends.isNotEmpty) ...[
              const SizedBox(height: Sp.sm),
              Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final u in friends)
                    LedgerChip(
                      key: ValueKey('finn-user:${u.id}'),
                      label: u.name,
                      icon: LucideIcons.link2,
                      onTap: () => _pick(u),
                    ),
                ],
              ),
            ] else ...[
              const SizedBox(height: Sp.sm),
              _NoFriends(onOpen: () => context.push(AppRoutes.friends)),
            ],
            if (widget.recentNames.isNotEmpty) ...[
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
            ] else if (friends.isNotEmpty) ...[
              const SizedBox(height: Sp.xs + 2),
              Text('Pick a friend to share it, or type any name to keep it private.', style: t.small),
            ],
          ],
        ],
      ),
    );
  }
}

class _NoFriends extends StatelessWidget {
  const _NoFriends({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Row(
      key: const ValueKey('pending-no-friends'),
      children: [
        Icon(LucideIcons.users, size: 14, color: c.inkSoft),
        const SizedBox(width: Sp.sm),
        Expanded(child: Text('Only friends can be linked. Add friends with their FiNN ID.', style: t.small)),
        LedgerButton(
          key: const ValueKey('pending-open-friends'),
          label: 'Add friends',
          variant: LedgerButtonVariant.quiet,
          small: true,
          onPressed: onOpen,
        ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.query, required this.results, required this.onPick});

  final String query;
  final List<FinnUser> results;
  final ValueChanged<FinnUser> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    if (results.isEmpty) {
      return Row(
        children: [
          Icon(LucideIcons.lock, size: 14, color: c.inkSoft),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Text('No friend matches. "$query" stays private to you.', style: t.small),
          ),
        ],
      );
    }
    return LedgerPanel(
      dividerIndent: Sp.lg + 36 + Sp.md,
      children: [
        for (var i = 0; i < results.length && i < 5; i++)
          _UserTile(key: ValueKey('finn-user:${results[i].id}'), user: results[i], onTap: () => onPick(results[i])),
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
      label: '${user.name}, your friend on FiNN. Share with them',
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
                        user.contactLabel,
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
                Text('Friend', style: t.small),
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
                  '${user.name} · ${user.contactLabel}',
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
