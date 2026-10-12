import 'dart:convert';

import 'package:finn/agent/agent_config.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/orchestration/agent_events.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/prompt/system_prompt.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/features/categories/domain/category.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:finn/finance/finance_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'agent_fakes.dart';

void main() {
  late ActionHarness h;

  setUp(() async => h = await ActionHarness.create());

  Map<String, Object?> lunch({String amount = '450'}) => {
        'type': 'expense',
        'amount': amount,
        'categoryId': 'cat_food',
        'date': '2026-10-10',
        'paymentMethod': 'upi',
      };

  /// The outcome message recorded in the conversation, if any.
  String? lastAppMessageIn(AgentRig rig) => rig.runner.conversation.messages
      .where((m) => m.role == LlmRole.user && m.content!.startsWith('[FiNN app message'))
      .lastOrNull
      ?.content;

  /// The app's outcome message the model received last, if any.
  String? lastAppMessage(LlmRequest r) =>
      r.messages.where((m) => m.role == LlmRole.user && m.content!.startsWith('[FiNN app message')).lastOrNull?.content;

  test('multi-action request with sequential calls: one review card, real outcomes reported', () async {
    final rahul = await addPending(h, counterparty: 'Rahul', rupees: 2000);
    final provider = ScriptedProvider([
      // One call per step, as gpt-oss models do.
      callsTools([toolCall('record_transaction', lunch(), id: 'c_tx')]),
      callsTools([toolCall('find_records', {'kind': 'pending', 'query': 'Rahul'}, id: 'c_find')]),
      (LlmRequest r) {
        expect(toolResultsIn(r)['c_tx']!['status'], 'queuedForApproval');
        final found = toolResultsIn(r)['c_find']!;
        final id = ((found['items']! as List).single as Map)['id']! as String;
        return callsTools([
          toolCall('settle_pending_payment', {'pendingId': id, 'amount': '2000', 'date': '2026-10-10'}, id: 'c_settle'),
        ]);
      },
      says('I will record the ₹450 lunch and settle Rahul\'s ₹2,000.'),
    ]);
    final rig = AgentRig(h, provider);
    final events = <String>[];

    final result = await rig.runner.runTurn(
      'Spent 450 on lunch via UPI and Rahul paid back the 2000 he owed',
      approve: rig.approveAll,
      onEvent: (e) => events.add(e.runtimeType.toString()),
    );

    expect(result.end, AgentTurnEnd.completed);
    // The report is built from confirmed outcomes, without another model call.
    expect(result.reply, '₹450 on Food & Dining added as an expense. Received ₹2,000 from Rahul.');
    expect(provider.requests, hasLength(4));
    expect(lastAppMessageIn(rig), contains('"status":"completed"'));
    expect(result.actions.map((a) => a.status), everyElement(ActionResultStatus.completed));
    expect(rig.approvals, hasLength(1), reason: 'one review card for the whole plan');
    expect(rig.approvals.single, hasLength(2));
    expect(events, contains('AgentPlanReady'));
    final s = await h.snapshot();
    expect(s.pendingView(rahul.id)!.outstanding, Money.zero);
    expect(s.transactions.where((t) => t.categoryId == 'cat_food').single.amount, const Money.rupees(450));
    expect(provider.requests.first.instructions, contains('2026-10-10'));
    expect(provider.requests.first.instructions, contains('cat_food'));
  });

  test('a batched plan goes straight to review: one model call for a four-task message', () async {
    Map<String, Object?> item(String tool, Map<String, Object?> args) => {'tool': tool, 'arguments': args};
    final provider = ScriptedProvider([
      callsTools([
        toolCall('queue_actions', {
          'actions': [
            item('record_transaction', {...lunch(amount: '70'), 'categoryId': 'cat_groceries', 'note': 'Vegetables'}),
            item('record_transaction', {...lunch(amount: '150'), 'categoryId': 'cat_groceries', 'note': 'Milk'}),
            item('record_transaction', {...lunch(amount: '400'), 'categoryId': 'cat_transport', 'note': 'Petrol'}),
            item('add_subscription', {
              'name': 'Netflix Premium',
              'amount': '179',
              'frequency': 'monthly',
              'categoryId': 'cat_subscriptions',
              'startDate': '2026-10-09',
              'nextDueDate': '2026-11-09',
              'autoRenews': true,
            }),
          ],
          'done': true,
        }),
      ]),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Bought vegetables for 70, milk for 150, petrol for 400 and added Netflix premium '
        '179 yesterday');

    expect(provider.requests, hasLength(1), reason: 'no closing model call');
    expect(rig.approvals, hasLength(1));
    expect(rig.approvals.single, hasLength(4));
    expect(result.end, AgentTurnEnd.completed);
    expect(result.actions.map((a) => a.status), everyElement(ActionResultStatus.completed));
    expect(result.reply, startsWith('₹70 on Groceries added as an expense. ₹150 on Groceries added as an expense. ₹400 on Transport added as an expense. '));
    final s = await h.snapshot();
    expect(s.transactions, hasLength(3));
    expect(s.subscriptions.single.name, 'Netflix Premium');
    // The conversation stays well formed for the next turn.
    final roles = rig.runner.conversation.messages.map((m) => m.role).toList();
    expect(roles, [LlmRole.user, LlmRole.assistant, LlmRole.tool, LlmRole.user, LlmRole.assistant]);
    expect(lastAppMessageIn(rig), contains('"status":"completed"'));
  });

  test('a failed batch item is fixed in the next step and everything is reviewed on one card', () async {
    Map<String, Object?> item(Map<String, Object?> args) => {'tool': 'record_transaction', 'arguments': args};
    final provider = ScriptedProvider([
      callsTools([
        toolCall('queue_actions', {
          'actions': [item(lunch(amount: '70')), item({...lunch(amount: '150'), 'date': '2026-12-01'})],
          'done': true,
        }, id: 'c_batch'),
      ]),
      (LlmRequest r) {
        final items = (toolResultsIn(r)['c_batch']!['results']! as List).cast<Map>();
        expect(items[1]['error'], containsPair('code', 'validation'));
        return callsTools([
          toolCall('queue_actions', {
            'actions': [item(lunch(amount: '150'))],
            'done': true,
          }),
        ]);
      },
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 70 and 150 on food');
    expect(provider.requests, hasLength(2));
    expect(rig.approvals.single, hasLength(2));
    expect(result.reply, '₹70 on Food & Dining added as an expense. ₹150 on Food & Dining added as an expense.');
  });

  test('a tool call written as JSON text is recovered and handled like a real call', () async {
    final args = {
      'actions': [
        {'tool': 'record_transaction', 'arguments': lunch(amount: '70')},
      ],
      'done': true,
    };
    final provider = ScriptedProvider([says('```json\n${jsonEncode({'queue_actions': args})}\n```')]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 70 on food');
    expect(provider.requests, hasLength(1));
    expect(rig.approvals.single, hasLength(1));
    expect(result.reply, '₹70 on Food & Dining added as an expense.');

    const offered = {'queue_actions', 'record_transaction'};
    final named = AgentRunner.recoverToolCallText(
        says(jsonEncode({'name': 'record_transaction', 'arguments': lunch()})), offered, 3);
    expect(named.toolCalls.single.name, 'record_transaction');
    expect(named.toolCalls.single.id, 'recovered_3');
    // Ordinary text, unknown tools and non-object arguments stay text.
    for (final text in ['Done!', '{"delete_everything": {}}', '{"queue_actions": "x"}', '{"a": 1, "b": 2}', '{oops']) {
      final r = AgentRunner.recoverToolCallText(says(text), offered, 0);
      expect(r.toolCalls, isEmpty, reason: text);
      expect(r.text, text);
    }
  });

  test('nothing is written before the user approves', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('record_transaction', lunch())]),
      says('Recording ₹450 for lunch.'),
    ]);
    final rig = AgentRig(h, provider);
    await rig.turn('Spent 450 on lunch', approve: (p) async {
      expect((await h.snapshot()).transactions, isEmpty);
      return const {};
    });
    expect((await h.snapshot()).transactions, isEmpty);
  });

  test('ambiguous person: the model asks instead of acting', () async {
    await addPending(h, counterparty: 'Rahul', rupees: 500, purpose: 'Lunch');
    await addPending(h, counterparty: 'Rahul', rupees: 900, purpose: 'Cab');
    final provider = ScriptedProvider([
      callsTools([toolCall('find_records', {'kind': 'pending', 'query': 'Rahul'}, id: 'f')]),
      (LlmRequest r) {
        expect(toolResultsIn(r)['f']!['match'], 'multiple');
        return says('Rahul has two open items: Lunch (₹500) and Cab (₹900). Which one did he pay?');
      },
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Rahul paid me back');
    expect(result.end, AgentTurnEnd.completed);
    expect(result.actions, isEmpty);
    expect(rig.approvals, isEmpty);
  });

  test('partial approval: each item reported with its real status', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('record_transaction', lunch(amount: '300'))]),
      callsTools([toolCall('record_transaction', lunch(amount: '700'))]),
      says('Two expenses to review.'),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Add 300 and 700 food expenses', approve: (p) async {
      rig.approvals.add(p);
      return {p.first.id};
    });
    expect(result.actions.map((a) => a.status), [ActionResultStatus.completed, ActionResultStatus.declined]);
    expect(result.reply, '₹300 on Food & Dining added as an expense. Not done: Spent ₹700.');
    expect((await h.snapshot()).transactions.single.amount, const Money.rupees(300));
  });

  test('a dependent follow-up gets its own review after the first outcome', () async {
    final provider = ScriptedProvider([
      callsTools([
        toolCall('create_category', {
          'name': 'Pets',
          'type': 'expense',
          'iconKey': 'tag',
          'colorIndex': 3,
          'isEssential': false,
        }),
      ]),
      says('First I will create the Pets category. [continue]'),
      (LlmRequest r) {
        final outcome = lastAppMessage(r)!;
        final id = RegExp(r'"recordId":"([^"]+)"').firstMatch(outcome)!.group(1)!;
        return callsTools([toolCall('record_transaction', {...lunch(amount: '600'), 'categoryId': id})]);
      },
      says('Now the ₹600 expense.'),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Add a Pets category and record 600 for dog food in it');
    expect(rig.approvals, hasLength(2));
    expect(result.actions.every((a) => a.succeeded), isTrue);
    expect((await h.snapshot()).transactions.single.amount, const Money.rupees(600));
  });

  test('an item that needed a record from the same plan is finished after approval, without [continue]', () async {
    final pets = {'name': 'Pets', 'type': 'expense', 'iconKey': 'tag', 'colorIndex': 3, 'isEssential': false};
    final provider = ScriptedProvider([
      // The model guesses a placeholder id for the category it is creating.
      callsTools([
        toolCall('queue_actions', {
          'actions': [
            {'tool': 'create_category', 'arguments': pets},
            {
              'tool': 'record_transaction',
              'arguments': {...lunch(amount: '500'), 'categoryId': '<catId>'},
            },
          ],
          'done': true,
        }),
      ]),
      // ...and then forgets [continue].
      says('I queued the category. What is the new category id?'),
      (LlmRequest r) {
        final outcome = lastAppMessage(r)!;
        expect(outcome, contains('still missing'));
        final id = RegExp(r'"recordId":"([^"]+)"').firstMatch(outcome)!.group(1)!;
        return callsTools([
          toolCall('queue_actions', {
            'actions': [
              {
                'tool': 'record_transaction',
                'arguments': {...lunch(amount: '500'), 'categoryId': id},
              },
            ],
            'done': true,
          }),
        ]);
      },
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Create a Pets category and record 500 for dog food in it');
    expect(provider.requests, hasLength(3));
    expect(rig.approvals.map((a) => a.length), [1, 1]);
    expect(result.end, AgentTurnEnd.completed);
    expect(result.actions.every((a) => a.succeeded), isTrue);
    expect((await h.snapshot()).transactions.single.amount, const Money.rupees(500));
  });

  test('auto-continue happens at most once per turn', () async {
    final provider = ScriptedProvider([
      callsTools([
        toolCall('queue_actions', {
          'actions': [
            {'tool': 'record_transaction', 'arguments': lunch(amount: '70')},
            {'tool': 'record_transaction', 'arguments': {...lunch(), 'date': '2026-12-01'}},
          ],
          'done': true,
        }),
      ]),
      says('When was the second one?'),
      callsTools([toolCall('record_transaction', lunch(amount: '90'))]),
      says('Queued the ₹90 too. I still need the date of the ₹450 one.'),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 70 and 450 on food');
    expect(provider.requests, hasLength(4));
    expect(rig.approvals, hasLength(2));
    expect(result.end, AgentTurnEnd.completed);
  });

  test('an invalid action is fed back so the model can correct itself', () async {
    final rahul = await addPending(h, counterparty: 'Rahul', rupees: 500);
    final provider = ScriptedProvider([
      callsTools([
        toolCall('settle_pending_payment', {'pendingId': rahul.id, 'amount': '5000', 'date': '2026-10-10'}, id: 's'),
      ]),
      (LlmRequest r) {
        final error = toolResultsIn(r)['s']!['error']! as Map;
        expect(error['message'], contains('outstanding'));
        return says('Only ₹500 is outstanding from Rahul. Should I settle ₹500?');
      },
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Rahul paid 5000');
    expect(result.actions, isEmpty);
    expect(rig.approvals, isEmpty);
  });

  test('the model cannot run deletes even if it invents the tool', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('delete_transaction', {'id': 'tx_1'}, id: 'd')]),
      (LlmRequest r) {
        expect((toolResultsIn(r)['d']!['error']! as Map)['code'], 'unknownTool');
        return says('I cannot delete records. You can delete it from the transaction screen.');
      },
    ]);
    expect((await AgentRig(h, provider).turn('Delete my last transaction')).end, AgentTurnEnd.completed);
  });

  test('requests offer only relevant tool groups, and load_tools adds more', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('load_tools', {'groups': ['subscriptions']})]),
      says('Done looking.'),
    ]);
    final rig = AgentRig(h, provider);
    await rig.turn('Spent 450 on lunch');
    final first = provider.requests.first.tools.map((t) => t.name).toSet();
    final second = provider.requests.last.tools.map((t) => t.name).toSet();
    expect(first, isNot(contains('mark_subscription_paid')));
    expect(second, contains('mark_subscription_paid'));
  });

  test('transient provider failure is retried once; a second failure fails the turn and rolls back', () async {
    const outage = LlmException(LlmErrorKind.unavailable, 'The assistant is unavailable right now.', retryable: true);
    final provider = ScriptedProvider([outage, outage]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 100 on tea');
    expect(provider.requests, hasLength(2));
    expect(result.end, AgentTurnEnd.failed);
    expect(rig.runner.conversation.isEmpty, isTrue);
  });

  test('rate limits are waited out quietly within the turn budget; a long one is reported', () async {
    const limited =
        LlmException(LlmErrorKind.rateLimited, 'Busy.', retryable: true, retryAfter: Duration(milliseconds: 10));
    final provider = ScriptedProvider([limited, limited, limited, limited, says('Hello!')]);
    final rig = AgentRig(h, provider);
    final labels = <String>[];
    final ok = await rig.runner.runTurn('hi', approve: rig.approveAll, onEvent: (e) {
      if (e is AgentWaiting) labels.add(e.label);
    });
    expect(ok.reply, 'Hello!');
    expect(labels, List.filled(4, AgentRunner.waitingLabel));
    expect(labels.join(), isNot(contains(RegExp('busy|retry', caseSensitive: false))));

    final spent = ScriptedProvider([limited, limited, limited, says('Never reached')]);
    final tight = AgentRig(h, spent, config: const AgentConfig(rateLimitWaitBudget: Duration(milliseconds: 25)));
    final out = await tight.turn('hi');
    expect(out.error?.kind, LlmErrorKind.rateLimited, reason: 'budget spent after two waits');
    expect(spent.requests, hasLength(3));

    final slow = ScriptedProvider([
      const LlmException(LlmErrorKind.rateLimited, 'Please wait a moment.', retryable: true, retryAfter: Duration(minutes: 2)),
    ]);
    final result = await AgentRig(h, slow).turn('hi');
    expect(slow.requests, hasLength(1));
    expect(result.error?.kind, LlmErrorKind.rateLimited);
  });

  test('failure after planning still lets the user review what was prepared', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('record_transaction', lunch())]),
      const LlmException(LlmErrorKind.rejected, 'The assistant could not process this request.'),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 450 on lunch');
    expect(result.end, AgentTurnEnd.failed);
    expect(rig.approvals, hasLength(1));
    expect(result.actions.single.status, ActionResultStatus.completed);
    expect(result.reply, contains('₹450 on Food & Dining added as an expense.'));
  });

  test('tool loop limit forces a final answer without tools', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('get_financial_overview', {})]),
      callsTools([toolCall('get_financial_overview', {})]),
      says('Your available balance is ₹1,00,000.'),
    ]);
    final rig = AgentRig(h, provider, config: const AgentConfig(maxModelCallsPerTurn: 3));
    final result = await rig.turn('What is my balance?');
    expect(result.end, AgentTurnEnd.completed);
    expect(provider.requests.last.toolChoice, LlmToolChoice.none);
  });

  test('at the step limit, queued actions are still reviewed and summarised factually', () async {
    final provider = ScriptedProvider([
      callsTools([toolCall('record_transaction', lunch())]),
      callsTools([toolCall('get_financial_overview', {})]),
    ]);
    final rig = AgentRig(h, provider, config: const AgentConfig(maxModelCallsPerTurn: 2));
    final result = await rig.turn('Spent 450 on lunch');
    expect(result.end, AgentTurnEnd.limitReached);
    expect(rig.approvals, hasLength(1));
    expect(result.reply, contains('added as an expense.'));
  });

  test('stopping during approval ends the turn without writing', () async {
    final token = CancellationToken();
    final provider = ScriptedProvider([
      callsTools([toolCall('record_transaction', lunch())]),
      says('Recording lunch.'),
    ]);
    final rig = AgentRig(h, provider);
    final result = await rig.turn('Spent 450 on lunch', cancel: token, approve: (p) {
      token.cancel();
      return Future<Set<String>>.delayed(const Duration(seconds: 5), () => {p.single.id});
    });
    expect(result.end, AgentTurnEnd.cancelled);
    expect(result.actions.single.status, ActionResultStatus.cancelled);
    expect((await h.snapshot()).transactions, isEmpty);
  });

  test('conversation context carries over between turns', () async {
    final provider = ScriptedProvider([says('How much was it?'), says('Noted.')]);
    final rig = AgentRig(h, provider);
    await rig.turn('I bought groceries');
    await rig.turn('800');
    final users = provider.requests.last.messages.where((m) => m.role == LlmRole.user).map((m) => m.content);
    expect(users, ['I bought groceries', '800']);
  });

  test('instructions stay under the relay limit with many categories', () async {
    final s = await h.snapshot();
    final many = FinanceSnapshot(
      today: s.today, monthStartDay: 1, profile: s.profile,
      categories: [
        for (var i = 0; i < 400; i++)
          TransactionCategory(
              id: 'cat_custom_$i', name: 'A rather long custom category name $i', type: TransactionType.expense,
              iconKey: 'tag', colorIndex: 0),
      ],
      transactions: const [], budgets: const [], goals: const [], savingsMovements: const [], emergencyPlan: null,
      loans: const [], loanPayments: const [], subscriptions: const [], pending: const [], settlements: const [],
      assets: const [],
    );
    expect(AgentInstructions.build(many).length, lessThan(20000));
  });

  test('over-long input is refused without calling the model', () async {
    final provider = ScriptedProvider([]);
    final result = await AgentRig(h, provider).turn('x' * 5000);
    expect(result.end, AgentTurnEnd.failed);
    expect(provider.requests, isEmpty);
  });
}
