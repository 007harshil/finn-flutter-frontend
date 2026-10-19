import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/data_providers.dart';
import '../../../core/result/result.dart';
import '../../../kit/kit.dart';
import '../../pending/domain/shared_pending.dart';
import '../../pending/presentation/pending_ui.dart';
import '../domain/finn_id.dart';
import '../domain/friends.dart';

/// Your FiNN ID, adding friends by their FiNN ID, requests and the friend
/// list. Sharing a pending item needs a friend.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _input = TextEditingController();
  FriendLookup? _found;
  String? _error;
  bool _finding = false;
  bool _busy = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load({bool toast = false}) async {
    try {
      await ref.read(friendDirectoryProvider).refresh();
      if (mounted && _loadError != null) setState(() => _loadError = null);
    } on AppFailure catch (f) {
      if (!mounted) return;
      if (toast) FinnToast.error(context, f.message);
      setState(() => _loadError = f.message);
    }
  }

  Future<void> _find({bool keepError = false}) async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      setState(() {
        _found = null;
        _error = 'Enter a FiNN ID, like K7Q2-M9XD.';
      });
      return;
    }
    setState(() {
      _finding = true;
      if (!keepError) _error = null;
    });
    try {
      final result = await ref.read(friendDirectoryProvider).lookup(text);
      if (!mounted) return;
      setState(() {
        _found = result;
        _error = result == null ? 'No FiNN user has that ID.' : null;
      });
    } on AppFailure catch (f) {
      if (!mounted) return;
      setState(() {
        _found = null;
        _error = f.fieldErrors['finnId'] ?? f.message;
      });
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  /// Runs one change, toasts the outcome and refreshes the lookup result.
  Future<void> _act(Future<String> Function() change) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final message = await change();
      if (!mounted) return;
      FinnToast.success(context, message);
    } on AppFailure catch (f) {
      if (!mounted) return;
      FinnToast.error(context, f.fieldErrors['finnId'] ?? f.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted && _found != null) await _find(keepError: true);
  }

  Future<void> _send(FinnUser user) => _act(() async {
    final result = await ref
        .read(friendDirectoryProvider)
        .sendRequest(user.finnId ?? _input.text);
    return result == FriendRelation.friend
        ? 'You and ${user.name} are now friends'
        : 'Request sent to ${user.name}';
  });

  Future<void> _accept(FriendRequest r) => _act(() async {
    await ref.read(friendDirectoryProvider).accept(r.id);
    return 'You and ${r.user.name} are now friends';
  });

  Future<void> _reject(FriendRequest r) => _act(() async {
    await ref.read(friendDirectoryProvider).reject(r.id);
    return 'Request declined';
  });

  Future<void> _cancel(FriendRequest r) => _act(() async {
    await ref.read(friendDirectoryProvider).cancel(r.id);
    return 'Request cancelled';
  });

  Future<void> _remove(Friend f) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Remove ${f.user.name}?',
      message:
          'You will not be able to share new items with them until you are friends again. '
          'Items you already share stay as they are.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _act(() async {
      await ref.read(friendDirectoryProvider).removeFriend(f.user.id);
      return '${f.user.name} removed';
    });
  }

  Future<void> _block(FinnUser user) async {
    final ok = await showFinnConfirm(
      context,
      title: 'Block ${user.name}?',
      message:
          'They will not be able to send you friend requests or find you by your FiNN ID, '
          'and you will no longer be friends. They are not told. Items you already share stay as they are.',
      confirmLabel: 'Block',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _act(() async {
      await ref.read(friendDirectoryProvider).block(user.id);
      return '${user.name} blocked';
    });
  }

  Future<void> _unblock(Friend b) => _act(() async {
    await ref.read(friendDirectoryProvider).unblock(b.user.id);
    return '${b.user.name} unblocked';
  });

  @override
  Widget build(BuildContext context) {
    final state =
        ref.watch(friendStateProvider).value ??
        ref.read(friendDirectoryProvider).current;
    final found = _found;
    return RefreshIndicator(
      onRefresh: () => _load(toast: true),
      child: LedgerPage(
        storageKey: 'friends',
        appBar: LedgerAppBar(
          title: 'Friends',
          actions: [
            LedgerIconButton(
              icon: LucideIcons.refreshCw,
              tooltip: 'Refresh',
              onPressed: () => _load(toast: true),
            ),
          ],
        ),
        slivers: [
          if (_loadError != null && !state.loaded)
            PageBlock(
              top: Sp.lg,
              child: LedgerNote(
                text: _loadError!,
                icon: LucideIcons.wifiOff,
                tone: NoteTone.caution,
              ),
            ),
          PageBlock(
            top: Sp.lg,
            child: _MyId(me: state.me),
          ),
          PageBlock(
            top: Sp.section,
            child: LedgerSection(
              title: 'Add a friend',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LedgerTextField(
                    key: const ValueKey('friend-id-input'),
                    label: 'Their FiNN ID',
                    hint: 'K7Q2-M9XD',
                    controller: _input,
                    errorText: _error,
                    prefixIcon: LucideIcons.hash,
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _find(),
                    onChanged: (_) {
                      if (_error != null || _found != null) {
                        setState(() {
                          _error = null;
                          _found = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: Sp.md),
                  LedgerButton(
                    key: const ValueKey('friend-find'),
                    label: 'Find',
                    icon: LucideIcons.search,
                    variant: LedgerButtonVariant.secondary,
                    loading: _finding,
                    onPressed: _finding ? null : _find,
                  ),
                  if (found != null) ...[
                    const SizedBox(height: Sp.md),
                    LedgerPanel(
                      key: const ValueKey('friend-lookup-result'),
                      dividerIndent: _indent,
                      children: [_resultRow(found, state)],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (state.incoming.isNotEmpty || state.outgoing.isNotEmpty)
            PageBlock(
              top: Sp.section,
              child: LedgerSection(
                title: 'Requests',
                count: state.incoming.length + state.outgoing.length,
                child: LedgerPanel(
                  dividerIndent: _indent,
                  children: [
                    for (final r in state.incoming) _incomingRow(r),
                    for (final r in state.outgoing) _outgoingRow(r),
                  ],
                ),
              ),
            ),
          PageBlock(
            top: Sp.section,
            bottom: Sp.xl,
            child: LedgerSection(
              title: 'Friends',
              count: state.friends.isEmpty ? null : state.friends.length,
              child: state.friends.isEmpty
                  ? const LedgerEmpty(
                      icon: LucideIcons.users,
                      title: 'No friends yet',
                      message: 'Share your FiNN ID, or add a friend with theirs. You can share pending items only with friends.',
                    )
                  : LedgerPanel(
                      dividerIndent: _indent,
                      children: [
                        for (final f in state.friends)
                          LedgerRow(
                            key: ValueKey('friend:${f.user.id}'),
                            leading: PendingInitials(
                              name: f.user.name,
                              size: 36,
                            ),
                            title: f.user.name,
                            subtitle: _idOf(f.user),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LedgerIconButton(
                                  icon: LucideIcons.userMinus,
                                  tooltip: 'Remove ${f.user.name}',
                                  onPressed: _busy ? null : () => _remove(f),
                                ),
                                LedgerIconButton(
                                  key: ValueKey('friend-block:${f.user.id}'),
                                  icon: LucideIcons.ban,
                                  tooltip: 'Block ${f.user.name}',
                                  onPressed: _busy ? null : () => _block(f.user),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          if (state.blocked.isNotEmpty)
            PageBlock(
              bottom: Sp.xl,
              child: LedgerSection(
                title: 'Blocked',
                count: state.blocked.length,
                child: LedgerPanel(
                  dividerIndent: _indent,
                  children: [
                    for (final b in state.blocked)
                      LedgerRow(
                        key: ValueKey('blocked:${b.user.id}'),
                        leading: PendingInitials(name: b.user.name, size: 36),
                        title: b.user.name,
                        subtitle: _idOf(b.user),
                        trailing: LedgerButton(
                          key: ValueKey('unblock:${b.user.id}'),
                          label: 'Unblock',
                          variant: LedgerButtonVariant.quiet,
                          small: true,
                          onPressed: _busy ? null : () => _unblock(b),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _resultRow(FriendLookup r, FriendState state) {
    final user = r.user;
    FriendRequest requestOf(List<FriendRequest> list) =>
        list.where((x) => x.id == r.requestId).firstOrNull ??
        FriendRequest(
          id: r.requestId ?? '',
          user: user,
          createdAt: DateTime.now(),
        );
    final (String? status, Widget? actions) = switch (r.relation) {
      FriendRelation.self => ('That is you', null),
      FriendRelation.friend => ('Already friends', null),
      FriendRelation.none => (
        null,
        LedgerButton(
          key: const ValueKey('friend-send'),
          label: 'Send request',
          icon: LucideIcons.userPlus,
          small: true,
          onPressed: _busy ? null : () => _send(user),
        ),
      ),
      FriendRelation.outgoing => (
        'Requested',
        LedgerButton(
          key: const ValueKey('friend-cancel'),
          label: 'Cancel request',
          variant: LedgerButtonVariant.secondary,
          small: true,
          onPressed: _busy || r.requestId == null
              ? null
              : () => _cancel(requestOf(state.outgoing)),
        ),
      ),
      FriendRelation.incoming => (
        'Wants to be your friend',
        _acceptReject(requestOf(state.incoming)),
      ),
      FriendRelation.blocked => ('Blocked', null),
    };
    return LedgerRow(
      leading: PendingInitials(name: user.name, size: 36),
      title: user.name,
      subtitle: [?_idOf(user), ?status].join(' · '),
      below: actions == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: Sp.sm),
              child: actions,
            ),
    );
  }

  Widget _acceptReject(FriendRequest r) => Wrap(
    spacing: Sp.sm,
    runSpacing: Sp.sm,
    children: [
      LedgerButton(
        key: ValueKey('friend-accept:${r.id}'),
        label: 'Accept',
        icon: LucideIcons.check,
        small: true,
        onPressed: _busy ? null : () => _accept(r),
      ),
      LedgerButton(
        key: ValueKey('friend-reject:${r.id}'),
        label: 'Reject',
        variant: LedgerButtonVariant.secondary,
        small: true,
        onPressed: _busy ? null : () => _reject(r),
      ),
      LedgerButton(
        key: ValueKey('friend-block-request:${r.id}'),
        label: 'Block',
        variant: LedgerButtonVariant.quiet,
        color: context.ink.red,
        small: true,
        onPressed: _busy ? null : () => _block(r.user),
      ),
    ],
  );

  Widget _incomingRow(FriendRequest r) => LedgerRow(
    key: ValueKey('incoming:${r.id}'),
    leading: PendingInitials(name: r.user.name, size: 36),
    title: r.user.name,
    subtitle: [?_idOf(r.user), 'Wants to be your friend'].join(' · '),
    below: Padding(
      padding: const EdgeInsets.only(top: Sp.sm),
      child: _acceptReject(r),
    ),
  );

  Widget _outgoingRow(FriendRequest r) => LedgerRow(
    key: ValueKey('outgoing:${r.id}'),
    leading: PendingInitials(name: r.user.name, size: 36),
    title: r.user.name,
    subtitle: [?_idOf(r.user), 'Waiting for them'].join(' · '),
    trailing: LedgerButton(
      label: 'Cancel',
      variant: LedgerButtonVariant.quiet,
      small: true,
      onPressed: _busy ? null : () => _cancel(r),
    ),
  );

  static String? _idOf(FinnUser u) =>
      u.finnId == null ? null : FinnId.format(u.finnId!);
}

/// Aligns row hairlines with the text (16 pad + 36 avatar + 12 gap).
const double _indent = Sp.lg + 36 + Sp.md;

/// The signed-in user's FiNN ID with a copy button.
class _MyId extends StatelessWidget {
  const _MyId({required this.me});

  final FinnUser? me;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return LedgerSection(
      title: 'Your FiNN ID',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FinnIdCard(finnId: me?.finnId),
          const SizedBox(height: Sp.sm),
          Text(
            'Share this ID so friends can add you. People can find you only with it.',
            style: t.small,
          ),
        ],
      ),
    );
  }
}

/// A FiNN ID in large spaced figures, with a copy button.
class FinnIdCard extends StatelessWidget {
  const FinnIdCard({super.key, required this.finnId});

  final String? finnId;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final id = finnId;
    final shown = id == null ? '····-····' : FinnId.format(id);
    return Container(
      padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.sm, Sp.md),
      decoration: BoxDecoration(color: c.sunken, borderRadius: Rad.rMd),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: 'Your FiNN ID is ${shown.split('').join(' ')}',
              excludeSemantics: true,
              child: Text(
                shown,
                key: const ValueKey('my-finn-id'),
                style: t.figureL.copyWith(
                  letterSpacing: 3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
                maxLines: 1,
              ),
            ),
          ),
          LedgerIconButton(
            key: const ValueKey('copy-finn-id'),
            icon: LucideIcons.copy,
            tooltip: 'Copy FiNN ID',
            onPressed: id == null
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: FinnId.format(id)),
                    );
                    if (context.mounted)
                      FinnToast.success(context, 'FiNN ID copied');
                  },
          ),
        ],
      ),
    );
  }
}
