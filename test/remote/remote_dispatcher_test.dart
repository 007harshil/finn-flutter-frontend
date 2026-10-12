import 'dart:convert';

import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/ids/id_generator.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/core/time/clock.dart';
import 'package:finn/data/remote/remote_dispatcher.dart';
import 'package:finn/data/remote/remote_repositories.dart';
import 'package:finn/data/remote/sync_engine.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remote_fakes.dart';

Map<String, Object?> previewJson(String actionId, {bool requiresConfirmation = true}) => {
  'actionId': actionId,
  'title': 'Add expense?',
  'summary': 'Record ₹125 expense',
  'lines': [
    {'label': 'Amount', 'value': '₹125', 'emphasis': true},
  ],
  'warnings': ['This is over budget.'],
  'fingerprint': 'abc123.def',
  'requiresConfirmation': requiresConfirmation,
};

void main() {
  late List<http.Request> requests;
  late SyncEngine engine;
  late RemoteOperationDispatcher dispatcher;
  late http.Response Function(http.Request req) respond;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    requests = [];
    final client = MockClient((req) async {
      requests.add(req);
      if (req.url.path == '/api/v1/sync') return ok(page(cursor: '1'));
      return respond(req);
    });
    final api = apiWith(client);
    engine = SyncEngine(api: api, prefs: prefs);
    await engine.open('user-a');
    final repos = buildRemoteRepositories(engine, api);
    final clock = FixedClock(DateTime(2026, 10, 10, 9));
    dispatcher = RemoteOperationDispatcher(
      environment: ActionEnvironment(
        repos: repos,
        clock: clock,
        ids: SequentialIdGenerator(),
        loadSnapshot: () => repos.loadSnapshot(clock, monthStartDay: 1),
      ),
      api: api,
      engine: engine,
    );
  });

  final input = TransactionInput(
    type: TransactionType.expense,
    amount: Money.rupees(125),
    categoryId: 'cat_food',
    date: DateTime(2026, 10, 10),
  );

  List<http.Request> actionRequests() => requests.where((r) => r.url.path != '/api/v1/sync').toList();

  test('needsConfirmation → review → confirmed dispatch completes and applies changes', () async {
    respond = (req) {
      final body = jsonDecode(req.body) as Map;
      if (body['confirmation'] == null) {
        return ok({
          'status': 'needsConfirmation',
          'actionId': 'transactions.create',
          'preview': previewJson('transactions.create'),
        });
      }
      return ok({
        'status': 'completed',
        'actionId': 'transactions.create',
        'result': txJson('tx_new'),
        'preview': previewJson('transactions.create'),
        'replayed': false,
        'changes': page(
          cursor: '42',
          collections: {
            'transactions': {
              'upserted': [txJson('tx_new')],
              'deleted': [],
            },
          },
        ),
      });
    };

    final first = await dispatcher.dispatch(const CreateTransactionAction(), input, idempotencyKey: 'ui_key_0001');
    expect(first, isA<ActionNeedsConfirmation<Transaction>>());
    final preview = (first as ActionNeedsConfirmation<Transaction>).preview;
    expect(preview.fingerprint, 'abc123.def');
    expect(preview.lines.single.emphasis, isTrue);
    expect(preview.warnings, ['This is over budget.']);

    final second = await dispatcher.dispatch(
      const CreateTransactionAction(),
      input,
      idempotencyKey: 'ui_key_0001',
      confirmation: ActionConfirmation(preview.fingerprint),
    );
    expect(second, isA<ActionCompleted<Transaction>>());
    final done = second as ActionCompleted<Transaction>;
    expect(done.value.id, 'tx_new');
    expect(done.value.amount, Money.rupees(125));
    expect(done.replayed, isFalse);

    final calls = actionRequests();
    expect(calls.map((r) => r.url.path), everyElement('/api/v1/actions/transactions.create'));
    expect(calls.map((r) => r.headers['Idempotency-Key']), everyElement('ui_key_0001'));
    final confirmed = jsonDecode(calls.last.body) as Map;
    expect(confirmed['confirmation'], {'fingerprint': 'abc123.def', 'confirmedBy': 'user'});
    expect(confirmed['channel'], 'ui');
    expect((confirmed['input'] as Map)['amount'], '125.00');

    // The `changes` payload is in the cache immediately.
    expect(engine.record(SyncCollections.transactions, 'tx_new'), isNotNull);
  });

  test('error envelopes become ActionRejected with the same code and field errors', () async {
    respond = (_) =>
        errorResponse(422, 'validation', 'Choose a category.', fields: {'categoryId': 'Choose a category.'});
    final outcome = await dispatcher.dispatch(const CreateTransactionAction(), input, idempotencyKey: 'ui_key_0002');
    expect(outcome, isA<ActionRejected<Transaction>>());
    final failure = (outcome as ActionRejected<Transaction>).failure;
    expect(failure.code, FailureCode.validation);
    expect(failure.fieldErrors, {'categoryId': 'Choose a category.'});
  });

  test('preview posts the input and decodes the server preview', () async {
    respond = (req) {
      expect(req.url.path, '/api/v1/actions/transactions.create/preview');
      return ok({'preview': previewJson('transactions.create', requiresConfirmation: false)});
    };
    final result = await dispatcher.preview(const CreateTransactionAction(), input);
    final preview = (result as Ok<ActionPreview>).value;
    expect(preview.summary, 'Record ₹125 expense');
    expect(preview.requiresConfirmation, isFalse);
  });

  test('list outputs (pending.split) decode into typed records', () async {
    final value = actionResultDecoders['pending.split']!([pendingJson('pd_1'), pendingJson('pd_2')]);
    expect(value, isA<List<PendingPayment>>());
    expect((value as List<PendingPayment>).map((p) => p.id), ['pd_1', 'pd_2']);
  });

  test('every registered action has a result decoder', () {
    expect(actionResultDecoders.keys.toSet(), allActions.map((a) => a.descriptor.id).toSet());
  });

  test('a concurrent duplicate with the same key is rejected locally', () async {
    respond = (_) => ok({
      'status': 'completed',
      'actionId': 'pending.cancel',
      'result': pendingJson('pd_1'),
      'preview': previewJson('pending.cancel'),
      'replayed': false,
    });
    final a = dispatcher.dispatch(
      const CancelPendingAction(),
      const PendingIdInput(id: 'pd_1'),
      idempotencyKey: 'ui_key_0003',
    );
    final b = dispatcher.dispatch(
      const CancelPendingAction(),
      const PendingIdInput(id: 'pd_1'),
      idempotencyKey: 'ui_key_0003',
    );
    expect(await b, isA<ActionRejected<PendingPayment>>());
    expect(await a, isA<ActionCompleted<PendingPayment>>());
  });
}
