import 'dart:async';
import 'dart:convert';

import '../result/result.dart';
import '../data/crud_repository.dart';
import 'persistence_driver.dart';

export '../data/crud_repository.dart';

typedef JsonMap = Map<String, Object?>;

/// In-memory, JSON-persisted collection backing the mock repositories.
///
/// * Items are kept in insertion order in a map keyed by id.
/// * `watchAll` returns a cached unmodifiable list so listeners can rely on
///   identity checks to skip work.
/// * Persistence is debounced; [flush] forces a write.
class EntityCollection<T> implements CrudRepository<T> {
  EntityCollection({
    required this.storageKey,
    required this.idOf,
    required this.encode,
    required this.decode,
    required this._driver,
    MockBehavior? behavior,
  }) : behavior = behavior ?? MockBehavior();

  final String storageKey;
  final String Function(T) idOf;
  final JsonMap Function(T) encode;
  final T Function(JsonMap) decode;
  final PersistenceDriver _driver;
  final MockBehavior behavior;

  final Map<String, T> _items = {};
  final _controller = StreamController<List<T>>.broadcast();
  List<T>? _snapshot;
  Timer? _persistTimer;

  List<T> get current => _snapshot ??= List<T>.unmodifiable(_items.values);

  /// Loads persisted data. Returns false when nothing was stored.
  Future<bool> load() async {
    final raw = await _driver.read(storageKey);
    if (raw == null) return false;
    final list = (jsonDecode(raw) as List).cast<Map<String, Object?>>();
    _items
      ..clear()
      ..addEntries(
        list.map((j) {
          final item = decode(j);
          return MapEntry(idOf(item), item);
        }),
      );
    _changed(persist: false);
    return true;
  }

  /// Replaces all items (used for seeding and restore).
  void seed(Iterable<T> items, {bool persist = true}) {
    _items
      ..clear()
      ..addEntries(items.map((i) => MapEntry(idOf(i), i)));
    _changed(persist: persist);
  }

  Future<void> _simulate({required bool write}) async {
    if (behavior.latency > Duration.zero) await Future<void>.delayed(behavior.latency);
    if (write && behavior.failWrites) {
      throw const AppFailure.unavailable('Could not save right now. Please try again.');
    }
    if (!write && behavior.failReads) {
      throw const AppFailure.unavailable('Could not load your data. Please try again.');
    }
  }

  @override
  Stream<List<T>> watchAll() async* {
    await _simulate(write: false);
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<List<T>> getAll() async {
    await _simulate(write: false);
    return current;
  }

  @override
  Future<T?> getById(String id) async {
    await _simulate(write: false);
    return _items[id];
  }

  /// Synchronous lookup for calculations that already hold a snapshot.
  T? peek(String id) => _items[id];

  @override
  Future<void> save(T item) async {
    await _simulate(write: true);
    _items[idOf(item)] = item;
    _changed();
  }

  @override
  Future<void> saveAll(Iterable<T> items) async {
    await _simulate(write: true);
    for (final i in items) {
      _items[idOf(i)] = i;
    }
    _changed();
  }

  @override
  Future<void> delete(String id) async {
    await _simulate(write: true);
    if (_items.remove(id) != null) _changed();
  }

  void _changed({bool persist = true}) {
    _snapshot = null;
    _controller.add(current);
    if (persist) {
      _persistTimer?.cancel();
      _persistTimer = Timer(const Duration(milliseconds: 250), flush);
    }
  }

  Future<void> flush() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    await _driver.write(storageKey, jsonEncode(current.map(encode).toList()));
  }

  Future<void> dispose() async {
    if (_persistTimer != null) await flush();
    await _controller.close();
  }
}

/// A single persisted value (profile, emergency-fund plan, alert inbox).
class ValueStore<T> {
  ValueStore({
    required this.storageKey,
    required this.encode,
    required this.decode,
    required this._driver,
    required T initial,
    MockBehavior? behavior,
  }) : _value = initial,
       behavior = behavior ?? MockBehavior();

  final String storageKey;
  final JsonMap Function(T) encode;
  final T Function(JsonMap) decode;
  final PersistenceDriver _driver;
  final MockBehavior behavior;
  T _value;
  final _controller = StreamController<T>.broadcast();

  T get value => _value;

  Future<bool> load() async {
    final raw = await _driver.read(storageKey);
    if (raw == null) return false;
    _value = decode(jsonDecode(raw) as Map<String, Object?>);
    _controller.add(_value);
    return true;
  }

  Stream<T> watch() async* {
    if (behavior.latency > Duration.zero) await Future<void>.delayed(behavior.latency);
    if (behavior.failReads) {
      throw const AppFailure.unavailable('Could not load your data. Please try again.');
    }
    yield _value;
    yield* _controller.stream;
  }

  Future<void> set(T value, {bool simulate = true}) async {
    if (simulate) {
      if (behavior.latency > Duration.zero) await Future<void>.delayed(behavior.latency);
      if (behavior.failWrites) {
        throw const AppFailure.unavailable('Could not save right now. Please try again.');
      }
    }
    _value = value;
    _controller.add(value);
    await _driver.write(storageKey, jsonEncode(encode(value)));
  }

  Future<void> dispose() => _controller.close();
}
