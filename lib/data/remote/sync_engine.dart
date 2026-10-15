import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/persistence/entity_collection.dart' show JsonMap;
import 'api_client.dart';

/// Collection names used by `GET /sync` (and action `changes`).
abstract final class SyncCollections {
  static const transactions = 'transactions';
  static const categories = 'categories';
  static const budgets = 'budgets';
  static const goals = 'goals';
  static const savingsMovements = 'savingsMovements';
  static const loans = 'loans';
  static const loanPayments = 'loanPayments';
  static const subscriptions = 'subscriptions';
  static const pending = 'pending';
  static const settlements = 'settlements';
  static const assets = 'assets';
  static const moneyAccounts = 'moneyAccounts';
  static const transfers = 'transfers';

  static const all = [
    transactions,
    categories,
    budgets,
    goals,
    savingsMovements,
    loans,
    loanPayments,
    subscriptions,
    pending,
    settlements,
    assets,
    moneyAccounts,
    transfers,
  ];
}

/// Single values delivered by `GET /sync` under `values`.
abstract final class SyncValues {
  static const profile = 'profile';
  static const emergencyPlan = 'emergencyPlan';
  static const preferences = 'preferences';
  static const alertInbox = 'alertInbox';
  static const me = 'me';

  static const all = [profile, emergencyPlan, preferences, alertInbox, me];
}

/// Mirror of the signed-in user's records, kept in step with the server.
///
/// * [sync] runs a full load (no cursor yet) or an incremental
///   `GET /sync?since=` and repeats while `hasMore`.
/// * Records are kept as DTO-shaped JSON keyed by id; repositories decode
///   them with the existing `XxxDto.fromJson`.
/// * The cache and cursor are persisted per user in SharedPreferences so
///   the app opens offline with the last data.
/// * [changes] emits the names of the collections/values that changed.
class SyncEngine {
  SyncEngine({required this.api, required this.prefs, this.pageLimit});

  final ApiClient api;
  final SharedPreferences prefs;

  /// Optional `limit` sent to `/sync`.
  final int? pageLimit;

  static const _storagePrefix = 'finn.remote.cache.';

  String? _userId;
  _SyncState _state = _SyncState.empty();
  final Map<String, int> _revisions = {};
  final _changes = StreamController<Set<String>>.broadcast();

  Future<void>? _running;
  bool _rerun = false;

  /// The user whose data is loaded, or null when closed.
  String? get userId => _userId;

  /// Cursor of the last applied sync page, or null before the first load.
  String? get cursor => _state.cursor;

  /// Whether at least one full load has completed for this user.
  bool get hasSynced => _state.cursor != null;

  /// Names of the collections and values that changed.
  Stream<Set<String>> get changes => _changes.stream;

  /// Increments whenever [name] changes (repositories cache by revision).
  int revisionOf(String name) => _revisions[name] ?? 0;

  /// Every record of [collection], in insertion order.
  Iterable<JsonMap> records(String collection) => _state.collections[collection]?.values ?? const [];

  JsonMap? record(String collection, String id) => _state.collections[collection]?[id];

  /// A single value (`profile`, `emergencyPlan`, `preferences`, `alertInbox`, `me`).
  JsonMap? value(String name) => _state.values[name];

  String _storageKey(String userId) => '$_storagePrefix$userId';

  /// Loads [userId]'s cached data (if any). Other users' data is never
  /// visible: switching users replaces everything in memory.
  Future<void> open(String userId) async {
    if (_userId == userId) return;
    _userId = userId;
    _state = _SyncState.empty();
    final raw = prefs.getString(_storageKey(userId));
    if (raw != null) {
      try {
        _state = _SyncState.fromJson(Map<String, Object?>.from(jsonDecode(raw) as Map));
      } catch (e) {
        debugPrint('Discarding unreadable offline cache: $e');
        _state = _SyncState.empty();
      }
    }
    _emit({...SyncCollections.all, ...SyncValues.all});
  }

  /// Forgets the in-memory data; with [clearPersisted] also deletes the
  /// offline cache of the current user (sign-out).
  Future<void> close({bool clearPersisted = true}) async {
    final id = _userId;
    _userId = null;
    _state = _SyncState.empty();
    _rerun = false;
    if (clearPersisted && id != null) await prefs.remove(_storageKey(id));
    _emit({...SyncCollections.all, ...SyncValues.all});
  }

  /// Fetches every change since the last cursor (a full load the first
  /// time). Concurrent calls share one run; a call made while a run is in
  /// progress schedules one more run afterwards.
  Future<void> sync() {
    if (_userId == null) return Future.value();
    if (_running != null) {
      _rerun = true;
      return _running!;
    }
    final run = _runLoop();
    _running = run;
    return run.whenComplete(() => _running = null);
  }

  Future<void> _runLoop() async {
    do {
      _rerun = false;
      await _syncOnce();
    } while (_rerun && _userId != null);
  }

  Future<void> _syncOnce() async {
    final user = _userId;
    final full = _state.cursor == null;
    // A full load is staged and swapped in at the end, so the UI never
    // flashes empty; incremental pages are applied as they arrive.
    final target = full ? _SyncState.empty() : _state;
    var since = _state.cursor;
    for (var guard = 0; guard < 10000; guard++) {
      final data = await api.get('/sync', query: {'since': ?since, if (pageLimit != null) 'limit': '$pageLimit'});
      if (_userId != user) return; // signed out / switched meanwhile
      if (data is! Map) throw StateError('Unexpected sync response');
      final page = Map<String, Object?>.from(data);
      final changed = _applyTo(target, page);
      final next = page['cursor']?.toString();
      if (next != null) target.cursor = next;
      if (!full) _commit(changed);
      if (page['hasMore'] != true || next == null || next == since) break;
      since = next;
    }
    if (full) {
      _state = target;
      _commit({...SyncCollections.all, ...SyncValues.all});
    }
  }

  /// Applies an action's `changes` payload (same shape as a sync page).
  ///
  /// The cursor is deliberately not advanced: changes made elsewhere (e.g. a
  /// counterparty's settlement) may sit between the local cursor and this
  /// payload. Callers follow up with [sync], which re-reads from the cursor.
  void applyChanges(Map<String, Object?> payload) {
    if (_userId == null) return;
    final changed = _applyTo(_state, payload);
    _commit(changed);
  }

  /// Replaces everything with a full payload (e.g. the `/import` response)
  /// and adopts its cursor.
  void replaceWith(Map<String, Object?> payload) {
    if (_userId == null) return;
    final next = _SyncState.empty();
    _applyTo(next, payload);
    next.cursor = payload['cursor']?.toString();
    _state = next;
    _commit({...SyncCollections.all, ...SyncValues.all});
  }

  /// Overwrites one value locally (e.g. the alert inbox returned by `PUT`).
  void setValue(String name, JsonMap value) {
    if (_userId == null) return;
    _state.values[name] = value;
    _commit({name});
  }

  Set<String> _applyTo(_SyncState target, Map<String, Object?> payload) {
    final changed = <String>{};
    final collections = payload['collections'];
    if (collections is Map) {
      for (final entry in collections.entries) {
        final name = entry.key.toString();
        final body = entry.value;
        if (body is! Map) continue;
        final map = target.collections.putIfAbsent(name, () => {});
        final upserted = body['upserted'];
        if (upserted is List) {
          for (final item in upserted) {
            if (item is! Map) continue;
            final json = Map<String, Object?>.from(item);
            final id = json['id'];
            if (id is! String) continue;
            map[id] = json;
            changed.add(name);
          }
        }
        final deleted = body['deleted'];
        if (deleted is List) {
          for (final id in deleted) {
            if (map.remove(id.toString()) != null) changed.add(name);
          }
        }
      }
    }
    final values = payload['values'];
    if (values is Map) {
      for (final entry in values.entries) {
        final v = entry.value;
        if (v is! Map) continue;
        target.values[entry.key.toString()] = Map<String, Object?>.from(v);
        changed.add(entry.key.toString());
      }
    }
    return changed;
  }

  void _commit(Set<String> changed) {
    if (changed.isNotEmpty) _emit(changed);
    unawaited(_persist());
  }

  void _emit(Set<String> changed) {
    for (final name in changed) {
      _revisions[name] = (_revisions[name] ?? 0) + 1;
    }
    if (!_changes.isClosed) _changes.add(changed);
  }

  Future<void> _persist() async {
    final id = _userId;
    if (id == null) return;
    try {
      await prefs.setString(_storageKey(id), jsonEncode(_state.toJson()));
    } catch (e) {
      debugPrint('Could not save the offline cache: $e');
    }
  }

  Future<void> dispose() => _changes.close();
}

class _SyncState {
  _SyncState(this.cursor, this.collections, this.values);

  factory _SyncState.empty() => _SyncState(null, {}, {});

  factory _SyncState.fromJson(Map<String, Object?> j) {
    final collections = <String, Map<String, JsonMap>>{};
    final rawCollections = j['collections'];
    if (rawCollections is Map) {
      for (final e in rawCollections.entries) {
        final list = e.value;
        if (list is! List) continue;
        collections[e.key.toString()] = {
          for (final item in list.whereType<Map>())
            if (item['id'] is String) item['id'] as String: Map<String, Object?>.from(item),
        };
      }
    }
    final values = <String, JsonMap>{};
    final rawValues = j['values'];
    if (rawValues is Map) {
      for (final e in rawValues.entries) {
        if (e.value is Map) values[e.key.toString()] = Map<String, Object?>.from(e.value as Map);
      }
    }
    return _SyncState(j['cursor'] as String?, collections, values);
  }

  String? cursor;
  final Map<String, Map<String, JsonMap>> collections;
  final Map<String, JsonMap> values;

  Map<String, Object?> toJson() => {
    'cursor': cursor,
    'collections': {for (final e in collections.entries) e.key: e.value.values.toList()},
    'values': values,
  };
}
