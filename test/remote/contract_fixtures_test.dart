// Verifies the remote layer against real server output recorded by
// finn-backend (docs/contract/fixtures.json, copied to fixtures/).

import 'dart:convert';
import 'dart:io';

import 'package:finn/actions/action.dart';
import 'package:finn/actions/action_registry.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/ids/id_generator.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/data/dto/dtos.dart';
import 'package:finn/data/remote/remote_dispatcher.dart';
import 'package:finn/data/remote/remote_repositories.dart';
import 'package:finn/data/remote/remote_session_scope.dart';
import 'package:finn/data/remote/sync_engine.dart';
import 'package:finn/features/settings/domain/app_settings.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_fakes.dart';

final Map<String, Object?> fixtures = Map<String, Object?>.from(
  jsonDecode(File('test/remote/fixtures/server_contract.json').readAsStringSync()) as Map,
);

List<Map<String, Object?>> get actionCalls =>
    [for (final a in fixtures['actions']! as List) Map<String, Object?>.from(a as Map)];

Map<String, Object?> httpFixture(String name) =>
    Map<String, Object?>.from((fixtures['http']! as Map)[name] as Map);

/// The fixture's response body and status.
http.Response responseOf(String name) {
  final f = httpFixture(name);
  return http.Response(jsonEncode(f['body']), f['status']! as int, headers: {'content-type': 'application/json'});
}

/// The `data` payload of a successful fixture.
Map<String, Object?> dataOf(String name) =>
    Map<String, Object?>.from((httpFixture(name)['body']! as Map)['data'] as Map);

Future<SyncEngine> engineWith(String userId, {http.Client? client}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final engine = SyncEngine(api: apiWith(client ?? MockClient((_) async => ok(null))), prefs: prefs);
  await engine.open(userId);
  return engine;
}

void main() {
  final registry = ActionRegistry(allActions);

  test('fixtures cover every registered action', () {
    final ids = actionCalls.map((a) => a['actionId']).toSet();
    expect(ids, allActions.map((a) => a.descriptor.id).toSet());
  });

  test('every action result decodes into the action output type', () {
    for (final call in actionCalls) {
      final id = call['actionId']! as String;
      final decoder = actionResultDecoders[id];
      expect(decoder, isNotNull, reason: id);
      final Object? value;
      try {
        value = decoder!(call['result']);
      } catch (e) {
        fail('$id result did not decode: $e\n${jsonEncode(call['result'])}');
      }
      expect(value, isNotNull, reason: id);
    }
  });

  test('every action input the server accepted decodes with the client action', () {
    for (final call in actionCalls) {
      final id = call['actionId']! as String;
      final result = registry.decode(id, Map<String, Object?>.from(call['input']! as Map));
      if (result case Err(:final failure)) {
        fail('$id input rejected by the client: ${failure.message} ${failure.fieldErrors}\n${jsonEncode(call['input'])}');
      }
    }
  });

  test('syncAlice populates every repository', () async {
    final engine = await engineWith('alice', client: MockClient((_) async => responseOf('syncAlice')));
    await engine.sync();
    final data = dataOf('syncAlice');
    expect(engine.cursor, data['cursor']);

    final repos = buildRemoteRepositories(engine, apiWith(MockClient((_) async => ok(null))));
    final collections = Map<String, Object?>.from(data['collections']! as Map);
    Future<int> countOf(String name) async => switch (name) {
          SyncCollections.transactions => (await repos.transactions.getAll()).length,
          SyncCollections.categories => (await repos.categories.getAll()).length,
          SyncCollections.budgets => (await repos.budgets.getAll()).length,
          SyncCollections.goals => (await repos.goals.getAll()).length,
          SyncCollections.savingsMovements => (await repos.savingsMovements.getAll()).length,
          SyncCollections.loans => (await repos.loans.getAll()).length,
          SyncCollections.loanPayments => (await repos.loanPayments.getAll()).length,
          SyncCollections.subscriptions => (await repos.subscriptions.getAll()).length,
          SyncCollections.pending => (await repos.pending.getAll()).length,
          SyncCollections.settlements => (await repos.settlements.getAll()).length,
          SyncCollections.assets => (await repos.assets.getAll()).length,
          _ => throw StateError('Unknown collection $name'),
        };
    for (final entry in collections.entries) {
      final upserted = ((entry.value! as Map)['upserted'] as List).length;
      // Every record decodes (unreadable records would be skipped).
      expect(await countOf(entry.key), upserted, reason: entry.key);
    }
    expect(repos.profile.current?.displayName, 'Alice');
    expect(repos.users.me.handle, '@alice');
    final snapshot = await repos.loadSnapshot(FixedClock(DateTime(2026, 10, 10, 9)), monthStartDay: 1);
    expect(snapshot.transactions, isNotEmpty);
  });

  test("syncBob exposes the mirrored shared item and both settlements", () async {
    final engine = await engineWith('bob', client: MockClient((_) async => responseOf('syncBob')));
    await engine.sync();
    final repos = buildRemoteRepositories(engine, apiWith(MockClient((_) async => ok(null))));

    final mirrored = await repos.pending.getById('mir_shr_1');
    expect(mirrored, isNotNull);
    expect(mirrored!.link?.createdByMe, isFalse);
    expect(mirrored.link?.handle, '@alice');
    final settlementIds = (await repos.settlements.getAll()).where((s) => s.pendingId == 'mir_shr_1').map((s) => s.id);
    expect(settlementIds, containsAll(['mir_set_3', 'set_4']));
    expect(repos.users.known(mirrored.link!.userId)?.handle, '@alice');
    expect(repos.users.me.name, 'Bob');
  });

  test('the import response replaces the cache like a full load', () async {
    final engine = await engineWith('alice');
    engine.replaceWith(dataOf('import'));
    expect(engine.cursor, dataOf('import')['cursor']);
    final repos = buildRemoteRepositories(engine, apiWith(MockClient((_) async => ok(null))));
    expect((await repos.transactions.getAll()).map((t) => t.id), contains('tx_a'));
  });

  group('action envelopes through RemoteOperationDispatcher', () {
    Future<RemoteOperationDispatcher> dispatcherFor(String fixture) async {
      final client = MockClient((req) async => req.url.path == '/api/v1/sync' ? ok(page(cursor: '1')) : responseOf(fixture));
      final api = apiWith(client);
      final engine = await engineWith('alice', client: client);
      final repos = buildRemoteRepositories(engine, api);
      final clock = FixedClock(DateTime(2026, 10, 10, 9));
      return RemoteOperationDispatcher(
        environment: ActionEnvironment(
          repos: repos,
          clock: clock,
          ids: SequentialIdGenerator(),
          loadSnapshot: () => repos.loadSnapshot(clock, monthStartDay: 1),
        ),
        api: api,
        engine: engine,
      );
    }

    ActionInput inputFor(String actionId) {
      final call = actionCalls.firstWhere((c) => c['actionId'] == actionId);
      return (registry.decode(actionId, Map<String, Object?>.from(call['input']! as Map)) as Ok<ActionInput>).value;
    }

    test('needsConfirmation', () async {
      final dispatcher = await dispatcherFor('actionNeedsConfirmation');
      final action = registry.lookup('transactions.delete')!;
      final outcome = await dispatcher.dispatch(action, inputFor('transactions.delete'), idempotencyKey: 'ui_contract_1');
      expect(outcome, isA<ActionNeedsConfirmation<Object?>>());
      final preview = (outcome as ActionNeedsConfirmation<Object?>).preview;
      expect(preview.title, 'Delete transaction?');
      expect(preview.fingerprint, isNotEmpty);
      expect(preview.lines.any((l) => l.emphasis), isTrue);
      expect(preview.warnings, isNotEmpty);
    });

    test('completed', () async {
      final dispatcher = await dispatcherFor('actionCompleted');
      final action = registry.lookup('transactions.create')!;
      final outcome = await dispatcher.dispatch(action, inputFor('transactions.create'), idempotencyKey: 'ui_contract_2');
      expect(outcome, isA<ActionCompleted<Object?>>());
      final done = outcome as ActionCompleted<Object?>;
      expect(done.value, isA<Transaction>());
      expect((done.value! as Transaction).id, 'tx_10');
      expect(done.preview.summary, isNotEmpty);
      expect(dispatcher.engine.record(SyncCollections.transactions, 'tx_10'), isNotNull);
    });

    test('validation error', () async {
      final dispatcher = await dispatcherFor('actionValidationError');
      final action = registry.lookup('transactions.create')!;
      final outcome = await dispatcher.dispatch(action, inputFor('transactions.create'), idempotencyKey: 'ui_contract_3');
      final failure = (outcome as ActionRejected<Object?>).failure;
      expect(failure.code, FailureCode.validation);
      expect(failure.fieldErrors, {'amount': 'Enter an amount greater than zero'});
      expect(failure.retryable, isFalse);
    });
  });

  test('actionsList covers the client catalogue (ids and field names)', () {
    final served = [for (final a in dataOf('actionsList')['actions']! as List) Map<String, Object?>.from(a as Map)];
    expect(served.map((a) => a['id']).toSet(), allActions.map((a) => a.descriptor.id).toSet());
    for (final a in served) {
      final local = registry.lookup(a['id']! as String)!.descriptor;
      final names = [for (final f in a['fields']! as List) (f as Map)['name']];
      // The server may describe optional inputs the local descriptor omits;
      // every field the client describes must be known to the server.
      expect(names.toSet().containsAll(local.fields.map((f) => f.name)), isTrue, reason: a['id'] as String);
    }
  });

  test('audit, users search, me, preferences and alert inbox decode', () async {
    final audit = await fetchRemoteAudit(apiWith(MockClient((_) async => responseOf('audit'))));
    expect(audit, isNotEmpty);
    expect(audit.first.actionId, 'transactions.create');
    expect(audit.first.succeeded, isTrue);

    final engine = await engineWith('alice');
    final directory = RemoteUserDirectory(engine, apiWith(MockClient((_) async => responseOf('usersSearch'))));
    final found = await directory.search('bo');
    expect(found.single.handle, '@bob');
    expect(directory.known(found.single.id)?.name, 'Bob');

    final me = dataOf('me');
    expect(ProfileDto.fromJson(Map<String, Object?>.from(me['profile']! as Map))?.displayName, 'Alice');
    expect((me['user']! as Map)['handle'], '@alice');

    final prefs = dataOf('preferences');
    final settings = withServerPreferences(const AppSettings(monthStartDay: 7), prefs);
    expect(settings.monthStartDay, prefs['monthStartDay']);
    // The PATCH body only ever carries keys the strict server schema knows.
    expect(prefs.keys.toSet().containsAll(serverPreferencesOf(settings).keys), isTrue);

    final inbox = AlertInboxDto.fromJson(dataOf('alertsInbox'));
    expect(inbox.readKeys, isEmpty);
  });

  test('restoring dismissed alerts sends restore keys', () async {
    late Map<String, Object?> sent;
    final engine = await engineWith('alice');
    engine.setValue(SyncValues.alertInbox, {'read': ['a1'], 'dismissed': ['a1', 'a2']});
    final repo = RemoteAlertInboxRepository(engine, apiWith(MockClient((req) async {
      sent = Map<String, Object?>.from(jsonDecode(req.body) as Map);
      return ok({'read': ['a1'], 'dismissed': <String>[]});
    })));
    await repo.set(repo.current.copyWith(dismissedKeys: {}));
    expect(sent, {'read': <Object?>[], 'dismissed': <Object?>[], 'restore': unorderedEquals(['a1', 'a2'])});
    expect(repo.current.dismissedKeys, isEmpty);
  });

  test('ApiClient unwraps the real envelopes', () async {
    final api = apiWith(MockClient((_) async => responseOf('preferences')));
    expect(await api.get('/preferences'), dataOf('preferences'));
  });
}
