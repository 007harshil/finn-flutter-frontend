import 'dart:convert';

import 'package:finn/data/remote/remote_repositories.dart';
import 'package:finn/data/remote/sync_engine.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_fakes.dart';

/// Serves sync pages keyed by the `since` query parameter ('' = full load).
class FakeSyncServer {
  final Map<String, Map<String, Object?>> pages = {};
  final List<String?> requests = [];

  MockClient get client => MockClient((req) async {
        expect(req.url.path, '/api/v1/sync');
        final since = req.url.queryParameters['since'];
        requests.add(since);
        final body = pages[since ?? ''];
        if (body == null) return http.Response('missing page', 500);
        return ok(body);
      });
}

void main() {
  late SharedPreferences prefs;
  late FakeSyncServer server;
  late SyncEngine engine;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    server = FakeSyncServer();
    engine = SyncEngine(api: apiWith(server.client), prefs: prefs);
  });

  test('full load follows hasMore pages, then incremental sync applies upserts and tombstones', () async {
    server.pages[''] = page(cursor: '10', hasMore: true, collections: {
      'transactions': {'upserted': [txJson('tx_1'), txJson('tx_2')], 'deleted': []},
    }, values: {
      'profile': {'exists': false},
      'emergencyPlan': {'configured': false},
      'alertInbox': {'read': [], 'dismissed': []},
      'me': {'id': 'u1', 'name': 'Aarav', 'handle': '@aarav', 'phoneHint': null},
    });
    server.pages['10'] = page(cursor: '12', collections: {
      'transactions': {'upserted': [txJson('tx_3')], 'deleted': []},
    });

    await engine.open('user-a');
    expect(engine.hasSynced, isFalse);
    await engine.sync();

    expect(server.requests, [null, '10']);
    expect(engine.cursor, '12');
    expect(engine.records(SyncCollections.transactions).map((j) => j['id']), ['tx_1', 'tx_2', 'tx_3']);
    expect(engine.value(SyncValues.me)?['handle'], '@aarav');

    server.pages['12'] = page(cursor: '15', collections: {
      'transactions': {'upserted': [txJson('tx_2', paise: 99900, version: 2)], 'deleted': ['tx_1']},
    });
    await engine.sync();

    expect(server.requests.last, '12');
    expect(engine.cursor, '15');
    final repo = RemoteTransactionRepository(engine);
    final txs = await repo.getAll();
    expect(txs.map((t) => t.id), ['tx_2', 'tx_3']);
    expect(txs.first.amount.paise, 99900);
    expect(txs.first.version, 2);
  });

  test('persists the cache and cursor per user and restores them offline', () async {
    server.pages[''] = page(cursor: '5', collections: {
      'transactions': {'upserted': [txJson('tx_1')], 'deleted': []},
    });
    await engine.open('user-a');
    await engine.sync();
    await Future<void>.delayed(Duration.zero);

    final stored = jsonDecode(prefs.getString('finn.remote.cache.user-a')!) as Map;
    expect(stored['cursor'], '5');

    // A new engine (app restart, no network) opens with the cached data.
    final offline = SyncEngine(
      api: apiWith(MockClient((_) async => throw http.ClientException('offline'))),
      prefs: prefs,
    );
    await offline.open('user-a');
    expect(offline.cursor, '5');
    expect(offline.records(SyncCollections.transactions).single['id'], 'tx_1');

    // Another user never sees it.
    await offline.open('user-b');
    expect(offline.records(SyncCollections.transactions), isEmpty);
    expect(offline.cursor, isNull);

    // Sign-out clears the persisted cache of the signed-in user.
    await offline.open('user-a');
    await offline.close();
    expect(prefs.getString('finn.remote.cache.user-a'), isNull);
    expect(offline.records(SyncCollections.transactions), isEmpty);
  });

  test('applyChanges updates caches and streams without advancing the cursor', () async {
    server.pages[''] = page(cursor: '20', collections: {
      'transactions': {'upserted': [txJson('tx_1')], 'deleted': []},
    });
    await engine.open('user-a');
    await engine.sync();

    final repo = RemoteTransactionRepository(engine);
    final emitted = <List<Transaction>>[];
    final sub = repo.watchAll().listen(emitted.add);
    await Future<void>.delayed(Duration.zero);
    expect(emitted.single.map((t) => t.id), ['tx_1']);

    engine.applyChanges(page(cursor: '25', collections: {
      'transactions': {'upserted': [txJson('tx_9')], 'deleted': ['tx_1']},
    }, values: {
      'alertInbox': {'read': ['a1'], 'dismissed': []},
    }));
    await Future<void>.delayed(Duration.zero);

    expect(emitted.last.map((t) => t.id), ['tx_9']);
    expect(engine.cursor, '20');
    expect(RemoteAlertInboxRepository(engine, apiWith(server.client)).current.readKeys, {'a1'});
    await sub.cancel();
  });

  test('value repositories hydrate synchronously from the cache with safe fallbacks', () async {
    await engine.open('user-a');
    final repos = buildRemoteRepositories(engine, apiWith(server.client));
    expect(repos.profile.current, isNull);
    expect(repos.emergencyPlan.current, isNull);
    expect(repos.alertInbox.current.readKeys, isEmpty);

    engine.applyChanges(page(cursor: '1', values: {
      'profile': {
        'exists': true,
        'displayName': 'Aarav',
        'openingPaise': 2500000,
        'openingDate': '2026-04-01',
        'monthlyIncomeEstimatePaise': null,
      },
    }));
    expect(repos.profile.current?.displayName, 'Aarav');
    expect(repos.profile.current?.openingBalance.paise, 2500000);
  });

  test('direct collection writes are refused while connected', () async {
    await engine.open('user-a');
    final repo = RemoteTransactionRepository(engine);
    expect(repo.delete('tx_1'), throwsA(same(remoteDirectWriteFailure)));
    final shared = RemoteSharedLedgerRepository();
    await shared.delete('x'); // no-op: the server mirrors shared items
    expect(await shared.getAll(), isEmpty);
  });
}
