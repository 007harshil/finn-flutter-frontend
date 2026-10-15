import 'dart:convert';

import 'package:finn/agent/execution/plan_gateway.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/features/transactions/application/transaction_actions.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../remote/remote_fakes.dart';

PlanStep step(String id, int rupees) => PlanStep(
  stepId: id,
  action: const CreateTransactionAction(),
  input: TransactionInput(
    type: TransactionType.expense,
    amount: Money.rupees(rupees),
    categoryId: 'cat_food',
    date: DateTime(2026, 10, 10),
  ),
  label: 'Spent ₹$rupees',
);

Map<String, Object?> preview(String fp) => {
  'actionId': 'transactions.create',
  'title': 'Add expense',
  'summary': 'Spent ₹1',
  'lines': const [],
  'warnings': const [],
  'fingerprint': fp,
  'requiresConfirmation': true,
};

void main() {
  group('RemotePlanGateway', () {
    test('previews every step in one request and maps ready / invalid', () async {
      final bodies = <Map<String, Object?>>[];
      final gateway = RemotePlanGateway(apiWith(MockClient((req) async {
        expect(req.url.path, '/api/v1/plans/preview');
        bodies.add(jsonDecode(req.body) as Map<String, Object?>);
        return ok({
          'steps': [
            {'stepId': 'a', 'actionId': 'transactions.create', 'status': 'ready', 'preview': preview('fp_a')},
            {
              'stepId': 'b',
              'actionId': 'transactions.create',
              'status': 'invalid',
              'failure': {'code': 'validation', 'message': 'The date cannot be in the future.'},
            },
          ],
        });
      })));
      final out = await gateway.preview('agent.c_1', [step('a', 450), step('b', 90)]);
      expect(bodies, hasLength(1));
      expect(bodies.single['planId'], 'agent.c_1');
      expect(bodies.single['channel'], 'agent');
      expect((bodies.single['steps'] as List).first, {
        'stepId': 'a',
        'actionId': 'transactions.create',
        'input': {
          'type': 'expense',
          'amount': '450.00',
          'categoryId': 'cat_food',
          'date': '2026-10-10',
          'accountId': null,
          'channel': null,
          'counterparty': null,
          'note': null,
        },
      });
      expect(out[0].preview!.fingerprint, 'fp_a');
      expect(out[1].failure!.message, 'The date cannot be in the future.');
    });

    test('executes approved steps in one request with the history entry, and maps every outcome', () async {
      late Map<String, Object?> body;
      final gateway = RemotePlanGateway(apiWith(MockClient((req) async {
        expect(req.url.path, '/api/v1/plans/execute');
        body = jsonDecode(req.body) as Map<String, Object?>;
        return ok({
          'steps': [
            {'stepId': 'a', 'status': 'succeeded', 'result': {'id': 'tx_1'}, 'replayed': false},
            {'stepId': 'b', 'status': 'succeeded', 'result': {'id': 'tx_2'}, 'replayed': true},
            {'stepId': 'c', 'status': 'failed', 'failure': {'code': 'conflict', 'message': 'Changed elsewhere.'}},
            {'stepId': 'd', 'status': 'notApproved', 'failure': {'code': 'staleData', 'message': 'Details changed.'}},
            {'stepId': 'e', 'status': 'notApproved'},
            {'stepId': 'f', 'status': 'skipped'},
          ],
          'history': {'id': 'run_1', 'status': 'partial', 'summary': '2 of 6 saved'},
        });
      })));
      final out = await gateway.execute(
        'agent.c_1',
        [for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) step(id, 10)],
        approved: {'a': 'fp_a', 'b': 'fp_b', 'c': 'fp_c', 'd': 'fp_d', 'f': 'fp_f'},
        history: const HistoryWrite(runId: 'run_1', request: 'lunch 10 …', notes: ['No goal named "yacht".']),
      );
      expect(body['approvedFingerprints'], ['fp_a', 'fp_b', 'fp_c', 'fp_d', 'fp_f']);
      expect(body['stopOnFailure'], false);
      expect(body['history'], {
        'runId': 'run_1',
        'request': 'lunch 10 …',
        'notes': ['No goal named "yacht".'],
        'labels': {for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) id: 'Spent ₹10'},
      });
      expect(out.map((r) => r.status), [
        ActionResultStatus.completed,
        ActionResultStatus.alreadyDone,
        ActionResultStatus.failed,
        ActionResultStatus.needsReapproval,
        ActionResultStatus.declined,
        ActionResultStatus.skipped,
      ]);
      expect(out[0].recordId, 'tx_1');
      expect(out[2].message, 'Changed elsewhere.');
      expect(out[2].outcomeUnknown, isFalse); // the server confirmed the failure
    });

    test('a dropped connection is retried once with the same request (idempotent replay)', () async {
      final seen = <String>[];
      final gateway = RemotePlanGateway(apiWith(MockClient((req) async {
        seen.add(req.body);
        if (seen.length == 1) throw http.ClientException('connection reset');
        return ok({
          'steps': [
            {'stepId': 'a', 'status': 'succeeded', 'result': {'id': 'tx_1'}, 'replayed': true},
          ],
        });
      })));
      final out = await gateway.execute('agent.c_1', [step('a', 10)], approved: {'a': 'fp'});
      expect(seen, hasLength(2));
      expect(seen[0], seen[1]);
      expect(out.single.status, ActionResultStatus.alreadyDone);
    });

    test('when the retry fails too, approved steps are "not confirmed" (never claimed saved)', () async {
      final gateway = RemotePlanGateway(apiWith(MockClient((_) async => throw http.ClientException('offline'))));
      final out = await gateway.execute('agent.c_1', [step('a', 10), step('b', 20)], approved: {'a': 'fp'});
      expect(out[0].status, ActionResultStatus.failed);
      expect(out[0].outcomeUnknown, isTrue);
      expect(out[1].status, ActionResultStatus.declined);
    });
  });

  group('agent history', () {
    test('lists pages with filters from GET /agent/history', () async {
      late Uri seen;
      final repo = RemoteAgentHistoryRepository(apiWith(MockClient((req) async {
        seen = req.url;
        return ok({
          'items': [
            {
              'id': 'run_1',
              'request': 'lunch 450',
              'status': 'partial',
              'summary': '1 of 2 saved, 1 not saved',
              'createdAt': '2026-10-10T03:30:00.000Z',
              'operations': [
                {'ref': 'a', 'actionId': 'transactions.create', 'summary': 'Spent ₹450', 'status': 'saved', 'recordIds': ['tx_1']},
                {'ref': 'b', 'actionId': 'pending.create', 'summary': 'Owe ₹1,200', 'status': 'failed', 'recordIds': [], 'message': 'No.'},
              ],
              'notes': [],
            },
          ],
          'nextBefore': '41',
        });
      })));
      final page = await repo.list(limit: 10, before: '50', status: AgentRunStatus.partial);
      expect(seen.path, '/api/v1/agent/history');
      expect(seen.queryParameters, {'limit': '10', 'before': '50', 'status': 'partial'});
      expect(page.nextBefore, '41');
      final e = page.items.single;
      expect((e.status, e.operations.first.saved, e.operations.last.message), (AgentRunStatus.partial, true, 'No.'));
    });

    test('clear sends DELETE', () async {
      late http.Request seen;
      final repo = RemoteAgentHistoryRepository(apiWith(MockClient((req) async {
        seen = req;
        return ok({'deleted': 3});
      })));
      await repo.clear();
      expect((seen.method, seen.url.path), ('DELETE', '/api/v1/agent/history'));
    });

    test('answers "what did I ask you" from stored outcomes, by period', () {
      final now = DateTime(2026, 10, 10, 18);
      AgentHistoryEntry e(String request, DateTime at, String summary) =>
          AgentHistoryEntry(id: request, request: request, status: AgentRunStatus.completed, summary: summary, createdAt: at);
      final entries = [
        e('lunch 450', DateTime(2026, 10, 10, 13, 5), '1 change saved'),
        e('salary 5000, gave 300 to Utsav, protein 5000', DateTime(2026, 10, 9, 21), '3 of 3 saved'),
      ];
      expect(historyAnswer(entries, period: 'today', now: now),
          'Here is what you asked me today:\n• today 13:05: "lunch 450" — 1 change saved.');
      expect(historyAnswer(entries, period: 'yesterday', now: now), contains('yesterday 21:00'));
      expect(historyAnswer(entries, now: now).split('\n'), hasLength(3));
      expect(historyAnswer(const [], period: 'week', now: now), 'You haven\'t asked me to change anything this week.');
    });

    test('in-memory history merges a second wave into the same entry', () {
      final store = InMemoryAgentHistory();
      AgentHistoryOperation op(String ref, String status) =>
          AgentHistoryOperation(ref: ref, actionId: 'x', summary: ref, status: status);
      store.record(AgentHistoryEntry(
          id: 'r', request: 'first', status: AgentRunStatus.completed, summary: '', createdAt: DateTime(2026), operations: [op('a', 'saved')]));
      store.record(AgentHistoryEntry(
          id: 'r', request: 'ignored', status: AgentRunStatus.failed, summary: '', createdAt: DateTime(2026), operations: [op('b', 'failed')]));
      final e = store.entries.single;
      expect((e.request, e.status, e.summary), ('first', AgentRunStatus.partial, '1 of 2 saved, 1 not saved'));
    });
  });
}
