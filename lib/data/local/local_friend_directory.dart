import 'dart:async';

import '../../core/result/result.dart';
import '../../domain/friend_directory.dart';
import '../../features/friends/domain/finn_id.dart';
import '../../features/friends/domain/friends.dart';
import '../../features/pending/domain/shared_pending.dart';
import '../mock/finn_users.dart';
import 'local_data_store.dart';

const _maxOutgoing = 50;

/// In-memory friends over [mockFinnUsers]. Lookup is by exact FiNN ID only.
/// Not persisted: a restart returns to the seeded network.
class LocalFriendDirectory implements FriendDirectory {
  LocalFriendDirectory(this._profile) {
    final since = DateTime(2026, 9, 1);
    _friends = [
      for (final id in mockFriendIds) Friend(user: _byId(id), since: since),
    ];
    _incoming = [
      for (final id in mockIncomingRequestIds)
        FriendRequest(id: 'req_${_nextRequest++}', user: _byId(id), createdAt: DateTime(2026, 10, 15)),
    ];
  }

  final LocalProfileRepository _profile;
  final _changes = StreamController<FriendState>.broadcast();
  late List<Friend> _friends;
  late List<FriendRequest> _incoming;
  final List<FriendRequest> _outgoing = [];
  int _nextRequest = 1;

  static FinnUser _byId(String id) => mockFinnUsers.firstWhere((u) => u.id == id);

  FinnUser get _me => mockMe(_profile.current?.displayName);

  @override
  FriendState get current => FriendState(
    me: _me,
    friends: List.unmodifiable(_friends),
    incoming: List.unmodifiable(_incoming),
    outgoing: List.unmodifiable(_outgoing),
    loaded: true,
  );

  @override
  Stream<FriendState> watch() => _changes.stream;

  void _emit() => _changes.add(current);

  @override
  Future<void> refresh() async => _emit();

  FinnUser? _findByFinnId(String id) {
    if (id == mockMyFinnId) return _me;
    return mockFinnUsers.where((u) => u.finnId == id).firstOrNull;
  }

  static String _normalised(String finnId) {
    final id = FinnId.normalize(finnId);
    if (id == null) {
      throw const AppFailure.validation(FinnId.invalidMessage, fields: {'finnId': FinnId.invalidMessage});
    }
    return id;
  }

  FriendLookup _lookupOf(FinnUser user) {
    if (user.id == mockMyUserId) return FriendLookup(user: user, relation: FriendRelation.self);
    if (_friends.any((f) => f.user.id == user.id)) {
      return FriendLookup(user: user, relation: FriendRelation.friend);
    }
    final out = _outgoing.where((r) => r.user.id == user.id).firstOrNull;
    if (out != null) return FriendLookup(user: user, relation: FriendRelation.outgoing, requestId: out.id);
    final inc = _incoming.where((r) => r.user.id == user.id).firstOrNull;
    if (inc != null) return FriendLookup(user: user, relation: FriendRelation.incoming, requestId: inc.id);
    return FriendLookup(user: user, relation: FriendRelation.none);
  }

  @override
  Future<FriendLookup?> lookup(String finnId) async {
    final user = _findByFinnId(_normalised(finnId));
    return user == null ? null : _lookupOf(user);
  }

  @override
  Future<FriendRelation> sendRequest(String finnId) async {
    final id = _normalised(finnId);
    final user = _findByFinnId(id);
    const field = 'finnId';
    AppFailure failure(FailureCode code, String message) =>
        AppFailure(code, message, fieldErrors: {field: message});
    if (user == null) throw failure(FailureCode.notFound, 'No FiNN user has that ID.');
    final relation = _lookupOf(user);
    switch (relation.relation) {
      case FriendRelation.self:
        throw failure(FailureCode.validation, 'That is your own FiNN ID.');
      case FriendRelation.friend:
        throw failure(FailureCode.conflict, 'You are already friends.');
      case FriendRelation.outgoing:
        throw failure(FailureCode.conflict, 'You already sent a request. Wait for them to accept it.');
      case FriendRelation.incoming:
        await accept(relation.requestId!);
        return FriendRelation.friend;
      case FriendRelation.none:
        break;
    }
    if (_outgoing.length >= _maxOutgoing) {
      throw failure(FailureCode.validation, 'You have too many pending requests. Cancel some first.');
    }
    _outgoing.insert(0, FriendRequest(id: 'req_${_nextRequest++}', user: user, createdAt: DateTime.now()));
    _emit();
    return FriendRelation.outgoing;
  }

  FriendRequest _take(List<FriendRequest> list, String id) {
    final i = list.indexWhere((r) => r.id == id);
    if (i < 0) throw const AppFailure.notFound('This request no longer exists.');
    return list.removeAt(i);
  }

  @override
  Future<void> accept(String requestId) async {
    final r = _take(_incoming, requestId);
    _friends = [..._friends, Friend(user: r.user, since: DateTime.now())]
      ..sort((a, b) => a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase()));
    _emit();
  }

  @override
  Future<void> reject(String requestId) async {
    _take(_incoming, requestId);
    _emit();
  }

  @override
  Future<void> cancel(String requestId) async {
    _take(_outgoing, requestId);
    _emit();
  }

  @override
  Future<void> removeFriend(String userId) async {
    _friends = [
      for (final f in _friends)
        if (f.user.id != userId) f,
    ];
    _emit();
  }
}
