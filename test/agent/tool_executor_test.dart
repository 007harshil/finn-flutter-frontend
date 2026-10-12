import 'dart:convert';

import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/execution/tool_executor.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/tools/agent_tool.dart';
import 'package:finn/agent/tools/tool_groups.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/features/pending/application/pending_actions.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'agent_fakes.dart';

void main() {
  late ActionHarness h;
  late AgentRig rig;

  setUp(() async {
    h = await ActionHarness.create();
    rig = AgentRig(h, ScriptedProvider([]));
  });

  /// One model step (tool results) without settling the queue.
  Future<List<Map<String, Object?>>> step(List<LlmToolCall> calls, {bool newTurn = true}) async {
    if (newTurn) rig.executor.beginTurn();
    final e = await rig.executor.executeStep(calls);
    expect(e.results, hasLength(calls.length), reason: 'one result per call');
    return [for (final m in e.results) Map<String, Object?>.from(jsonDecode(m.content!) as Map)];
  }

  /// A step followed by the review card.
  Future<(List<Map<String, Object?>>, List<ActionRecord>)> stepAndSettle(
    List<LlmToolCall> calls, {
    ApprovalHandler? approve,
  }) async {
    final results = await step(calls);
    final records = await rig.executor.settleQueue(approve: approve ?? rig.approveAll);
    return (results, records);
  }

  Map<String, Object?> expense({String amount = '500', String category = 'cat_food'}) => {
        'type': 'expense',
        'amount': amount,
        'categoryId': category,
        'date': '2026-10-10',
        'paymentMethod': 'upi',
      };

  group('toolbox', () {
    test('never exposes deletes and every tool has an object schema', () {
      for (final t in rig.toolbox.tools) {
        expect(t.name, matches(RegExp(r'^[a-zA-Z0-9_-]{1,64}$')));
        expect(t.parameters['type'], 'object');
        if (t is ActionTool) expect(t.descriptor.id.endsWith('.delete'), isFalse, reason: t.name);
      }
    });

    test('action schemas list required fields from the descriptor', () {
      final schema = rig.toolbox.lookup('settle_pending_payment')!.parameters;
      expect(schema['required'], containsAll(['pendingId', 'amount', 'date']));
    });

    test('hidden fields are not offered', () {
      final props = rig.toolbox.lookup('add_pending_payment')!.parameters['properties']! as Map;
      expect(props.containsKey('linkedUserId'), isFalse);
    });

    test('only core tools are offered until a group is needed', () {
      final names = rig.selection.offered(rig.toolbox.tools).map((t) => t.name).toSet();
      expect(names, containsAll(['record_transaction', 'settle_pending_payment', 'find_records', 'load_tools']));
      expect(names, isNot(contains('record_loan_payment')));
      expect(names.length, lessThanOrEqualTo(10));

      rig.selection.enableFor('Paid my car loan EMI and topped up the Japan goal');
      final more = rig.selection.offered(rig.toolbox.tools).map((t) => t.name).toSet();
      expect(more, containsAll(['record_loan_payment', 'contribute_to_goal']));
    });

    test('load_tools switches on groups for later steps', () async {
      final r = await step([toolCall('load_tools', {'groups': ['subscriptions', 'bogus']})]);
      expect(r.single['loaded'], ['subscriptions']);
      expect(rig.selection.enabled, contains(ToolGroup.subscriptions));
    });
  });

  group('argument handling', () {
    test('unknown tool and malformed JSON become error results, nothing is queued', () async {
      final r = await step([
        toolCall('drop_database', {}),
        const LlmToolCall(id: 'bad', name: 'record_transaction', arguments: '{not json'),
        const LlmToolCall(id: 'list', name: 'record_transaction', arguments: '[1,2]'),
      ]);
      expect(r[0]['error'], containsPair('code', 'unknownTool'));
      expect(r[1]['error'], containsPair('code', 'invalidArguments'));
      expect(r[2]['error'], containsPair('code', 'invalidArguments'));
      expect(rig.executor.hasQueued, isFalse);
    });

    test('invalid values are rejected by the action decoder with field errors', () async {
      final r = await step([toolCall('record_transaction', expense(amount: 'lots'))]);
      final error = r.single['error']! as Map;
      expect(error['code'], 'validation');
      expect((error['fields']! as Map).keys, contains('amount'));
    });

    test('wrong-typed values that break a decoder become an error result', () async {
      final r = await step([
        toolCall('split_bill', {
          'direction': 'owedToMe',
          'total': '900',
          'purpose': 'Dinner',
          'createdDate': '2026-10-09',
          'method': 'equally',
          'people': [5, 'x'],
        }),
      ]);
      expect((r.single['error']! as Map)['code'], anyOf('invalidArguments', 'validation'));
    });

    test('business validation runs in the preview (future date)', () async {
      final r = await step([toolCall('record_transaction', {...expense(), 'date': '2026-12-01'})]);
      expect(r.single['error'], containsPair('code', 'validation'));
    });

    test('undeclared fields are dropped before decoding', () async {
      final (_, records) = await stepAndSettle([
        toolCall('add_pending_payment', {
          'counterparty': 'Rahul',
          'direction': 'owedToMe',
          'amount': '800',
          'purpose': 'Movie',
          'createdDate': '2026-10-09',
          'linkedUserId': 'usr_someone_else',
          'version': 99,
        }),
      ]);
      expect(records.single.status, ActionResultStatus.completed);
      expect((await h.snapshot()).pending.single.link, isNull);
    });
  });

  group('queue, approval and execution', () {
    test('a valid action is queued, not executed, until approved', () async {
      final r = await step([toolCall('record_transaction', expense())]);
      expect(r.single['status'], 'queuedForApproval');
      expect((await h.snapshot()).transactions, isEmpty);

      final records = await rig.executor.settleQueue(approve: rig.approveAll);
      expect(rig.approvals.single.single.preview.summary, contains('500'));
      expect(records.single.status, ActionResultStatus.completed);
      expect(records.single.recordId, isA<String>());
      expect((await h.snapshot()).transactions.single.amount, const Money.rupees(500));
      expect(h.dispatcher.audit.entries.single.channel.name, 'agent');
    });

    test('actions queued across steps are reviewed on one card', () async {
      rig.executor.beginTurn();
      await rig.executor.executeStep([toolCall('record_transaction', expense(amount: '100'))]);
      await rig.executor.executeStep([toolCall('record_transaction', expense(amount: '200'))]);
      final records = await rig.executor.settleQueue(approve: (p) async {
        rig.approvals.add(p);
        return {p.last.id};
      });
      expect(rig.approvals.single, hasLength(2));
      expect(records.map((a) => a.status), [ActionResultStatus.declined, ActionResultStatus.completed]);
      expect((await h.snapshot()).transactions.single.amount, const Money.rupees(200));
    });

    test('a declined action writes nothing', () async {
      final (_, records) = await stepAndSettle([toolCall('record_transaction', expense())], approve: rig.declineAll);
      expect(records.single.status, ActionResultStatus.declined);
      expect((await h.snapshot()).transactions, isEmpty);
      expect(outcomesMessage(records), contains('"status":"declined"'));
    });

    test('identical calls in one turn are queued once', () async {
      final r = await step([
        toolCall('record_transaction', expense()),
        toolCall('record_transaction', expense()),
      ]);
      expect(r[1]['status'], 'duplicateCall');
      await rig.executor.settleQueue(approve: rig.approveAll);
      expect((await h.snapshot()).transactions, hasLength(1));
    });

    test('repeating a completed request in the same turn is not executed again', () async {
      await stepAndSettle([toolCall('record_transaction', expense())]);
      final again = await step([toolCall('record_transaction', expense())], newTurn: false);
      expect(again.single['status'], 'alreadyHandled');
      expect(rig.executor.hasQueued, isFalse);
    });

    test('an identical request in a later turn is flagged and gets a new key', () async {
      await stepAndSettle([toolCall('record_transaction', expense())]);
      await stepAndSettle([toolCall('record_transaction', expense())]);
      final second = rig.approvals.last.single;
      expect(second.notes.single, contains('identical'));
      expect(second.idempotencyKey, isNot(rig.approvals.first.single.idempotencyKey));
      expect((await h.snapshot()).transactions, hasLength(2));
    });

    test('a record changed after review is not written (stale approval)', () async {
      final p = await addPending(h, counterparty: 'Rahul', rupees: 1000);
      final (_, records) = await stepAndSettle(
        [toolCall('settle_pending_payment', {'pendingId': p.id, 'amount': '400', 'date': '2026-10-10'})],
        approve: (proposals) async {
          await h.run(const SettlePendingAction(), SettlePendingInput(
            pendingId: p.id,
            amount: const Money.rupees(100),
            date: DateTime(2026, 10, 10),
          ));
          return {for (final x in proposals) x.id};
        },
      );
      expect(records.single.status, ActionResultStatus.needsReapproval);
      expect((await h.snapshot()).pendingView(p.id)!.settled, const Money.rupees(100));
    });

    test('a lost reply is reported as unknown and a repeat reuses the key (no double write)', () async {
      final flaky = FlakyDispatcher(h.dispatcher);
      rig = AgentRig(h, ScriptedProvider([]), dispatcher: flaky);
      final (_, first) = await stepAndSettle([toolCall('record_transaction', expense())]);
      expect(first.single.status, ActionResultStatus.failed);
      expect(first.single.outcomeUnknown, isTrue);
      expect(outcomesMessage(first), contains('outcomeUnknown'));

      final (_, retry) = await stepAndSettle([toolCall('record_transaction', expense())]);
      expect(rig.approvals.last.single.idempotencyKey, rig.approvals.first.single.idempotencyKey);
      expect(retry.single.status, ActionResultStatus.alreadyDone);
      expect((await h.snapshot()).transactions, hasLength(1));
    });

    test('stopping while waiting for approval runs nothing', () async {
      final token = CancellationToken();
      await step([toolCall('record_transaction', expense())]);
      final records = await rig.executor.settleQueue(
        approve: (p) {
          token.cancel();
          return Future<Set<String>>.delayed(const Duration(seconds: 5), () => {p.single.id});
        },
        cancel: token,
      );
      expect(records.single.status, ActionResultStatus.cancelled);
      expect((await h.snapshot()).transactions, isEmpty);
    });

    test('calls beyond the per-step limit are refused', () async {
      rig.executor.beginTurn();
      final e = await rig.executor.executeStep(
        [for (var i = 0; i < 3; i++) toolCall('get_financial_overview', {})],
        limit: 2,
      );
      final last = jsonDecode(e.results.last.content!) as Map;
      expect(last['error'], containsPair('code', 'tooManyCalls'));
      expect(e.results.first.toolName, 'get_financial_overview');
    });
  });

  group('read tools', () {
    test('find_records resolves a unique pending item by name', () async {
      final p = await addPending(h, counterparty: 'Rahul Sharma', rupees: 1200);
      final r = (await step([toolCall('find_records', {'kind': 'pending', 'query': 'rahul'})])).single;
      expect(r['match'], 'unique');
      expect(((r['items']! as List).single as Map)['id'], p.id);
      expect(((r['items']! as List).single as Map)['outstanding'], '1200.00');
    });

    test('find_records reports ambiguity instead of choosing', () async {
      await addPending(h, counterparty: 'Rahul', rupees: 500, purpose: 'Lunch');
      await addPending(h, counterparty: 'Rahul', rupees: 900, purpose: 'Cab');
      final r = (await step([toolCall('find_records', {'kind': 'pending', 'query': 'Rahul'})])).single;
      expect(r['match'], 'multiple');
      expect(r['items'], hasLength(2));
    });

    test('find_records filters by direction and reports none', () async {
      await addPending(h, counterparty: 'Priya', rupees: 300, direction: PendingDirection.iOwe);
      final r = (await step([
        toolCall('find_records', {'kind': 'pending', 'query': 'Priya', 'direction': 'owedToMe'}),
      ])).single;
      expect(r['match'], 'none');
    });

    test('search_transactions totals matches and validates ranges', () async {
      await stepAndSettle([
        toolCall('record_transaction', expense(amount: '120')),
        toolCall('record_transaction', expense(amount: '80', category: 'cat_transport')),
      ]);
      final r = await step([
        toolCall('search_transactions', {'categoryId': 'cat_food', 'from': '2026-10-01', 'to': '2026-10-31'}),
        toolCall('search_transactions', {'from': '2026-10-31', 'to': '2026-10-01'}),
      ]);
      expect(r[0]['totalExpense'], '120.00');
      expect(r[0]['matchCount'], 1);
      expect(r[1]['error'], containsPair('code', 'validation'));
    });

    test('get_financial_overview reports balances as decimal rupees', () async {
      final r = (await step([toolCall('get_financial_overview', {})])).single;
      expect((r['balance']! as Map)['cash'], '100000.00');
    });
  });
}
