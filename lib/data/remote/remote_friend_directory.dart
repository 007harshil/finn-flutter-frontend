import 'dart:async';

import '../../core/persistence/entity_collection.dart' show JsonMap;
import '../../core/result/result.dart';
import '../../domain/friend_directory.dart';
import '../../features/friends/domain/finn_id.dart';
import '../../features/friends/domain/friends.dart';
import '../../features/pending/domain/shared_pending.dart';
import 'api_client.dart';
import 'sync_engine.dart';

/// Friends over `/friends`, `/friends/requests` and `/users/lookup` (see
/// docs/FRIENDS.md). The server is the source of truth: every change
/// reloads `GET /friends`.
class RemoteFriendDirectory implements FriendDirectory {
  RemoteFriendDirectory(this.engine, this.api);

  final SyncEngine engine;
  final ApiClient api;
  final _changes = StreamController<FriendState>.broadcast();
  FriendState _state = const FriendState();

  @override
  FriendState get current {
    if (_state.me != null) return _state;
    final json = engine.value(SyncValues.me);
    if (json == null || json['id'] is! String) return _state;
    return FriendState(
      me: _userFrom(json),
      friends: _state.friends,
      incoming: _state.incoming,
      outgoing: _state.outgoing,
      loaded: _state.loaded,
    );
  }

  @override
  Stream<FriendState> watch() => _changes.stream;

  @override
  Future<void> refresh() async {
    final data = await api.get('/friends');
    if (data is! Map) return;
    final j = Map<String, Object?>.from(data);
    final me = j['me'];
    _state = FriendState(
      me: me is Map ? _userFrom(Map<String, Object?>.from(me)) : _state.me,
      friends: [for (final m in _maps(j['friends'])) ?_friendFrom(m)],
      incoming: [for (final m in _maps(j['incoming'])) ?_requestFrom(m)],
      outgoing: [for (final m in _maps(j['outgoing'])) ?_requestFrom(m)],
      loaded: true,
    );
    _changes.add(current);
  }

  String _validId(String finnId) {
    final id = FinnId.normalize(finnId);
    if (id == null) {
      throw const AppFailure.validation(FinnId.invalidMessage, fields: {'finnId': FinnId.invalidMessage});
    }
    return id;
  }

  @override
  Future<FriendLookup?> lookup(String finnId) async {
    final id = _validId(finnId);
    final data = await api.get('/users/lookup', query: {'finnId': FinnId.format(id)});
    final user = data is Map ? data['user'] : null;
    if (user is! Map) return null;
    final j = Map<String, Object?>.from(user);
    if (j['id'] is! String) return null;
    final relation = FriendRelation.values.where((r) => r.name == j['relation']).firstOrNull ?? FriendRelation.none;
    return FriendLookup(user: _userFrom(j), relation: relation, requestId: j['requestId'] as String?);
  }

  @override
  Future<FriendRelation> sendRequest(String finnId) async {
    final id = _validId(finnId);
    final data = await api.post('/friends/requests', body: {'finnId': id});
    await _reload();
    return data is Map && data['friend'] != null ? FriendRelation.friend : FriendRelation.outgoing;
  }

  @override
  Future<void> accept(String requestId) async {
    await api.post('/friends/requests/$requestId/accept');
    await _reload();
  }

  @override
  Future<void> reject(String requestId) async {
    await api.post('/friends/requests/$requestId/reject');
    await _reload();
  }

  @override
  Future<void> cancel(String requestId) async {
    await api.send('DELETE', '/friends/requests/$requestId');
    await _reload();
  }

  @override
  Future<void> removeFriend(String userId) async {
    await api.send('DELETE', '/friends/$userId');
    await _reload();
  }

  /// The change already happened on the server; a failed reload must not
  /// report it as failed.
  Future<void> _reload() async {
    try {
      await refresh();
    } catch (_) {}
  }

  static Iterable<JsonMap> _maps(Object? list) =>
      list is List ? list.whereType<Map>().map((m) => Map<String, Object?>.from(m)) : const [];

  static FinnUser _userFrom(JsonMap j) => FinnUser(
    id: j['id'] as String,
    name: (j['name'] as String?) ?? '',
    handle: (j['handle'] as String?) ?? '',
    phoneHint: j['phoneHint'] as String?,
    finnId: j['finnId'] as String?,
  );

  static Friend? _friendFrom(JsonMap j) {
    final user = j['user'];
    if (user is! Map || user['id'] is! String) return null;
    return Friend(
      user: _userFrom(Map<String, Object?>.from(user)),
      since: DateTime.tryParse('${j['since']}') ?? DateTime.now(),
    );
  }

  static FriendRequest? _requestFrom(JsonMap j) {
    final user = j['user'];
    if (j['id'] is! String || user is! Map || user['id'] is! String) return null;
    return FriendRequest(
      id: j['id'] as String,
      user: _userFrom(Map<String, Object?>.from(user)),
      createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    );
  }
}
