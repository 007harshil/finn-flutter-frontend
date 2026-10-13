import 'package:finn/agent/agent_config.dart';
import 'package:finn/agent/execution/proposals.dart';
import 'package:finn/agent/history/agent_history.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/prompt/agent_prompt.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:finn/features/transactions/domain/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'agent_fakes.dart';

Future<AgentRig> rig(List<Object> script, {AgentConfig config = const AgentConfig()}) async =>
    AgentRig(await ActionHarness.create(), ScriptedProvider(script), config: config);

void main() {
  group('one model request per clear message', () {
    test('three operations: one plan call, one review, one backend round, a local summary', () async {
      final r = await rig([
        plan([
          {'op': 'income', 'amount': 5000, 'category': 'Salary', 'date': -1},
          {'op': 'pending', 'dir': 'collect', 'person': 'Utsav', 'amount': 300, 'kind': 'lent'},
          {'op': 'expense', 'amount': 5000, 'category': 'Fitness', 'note': 'protein powder'},
        ]),
      ]);
      const text = 'I received ₹5,000 as salary yesterday, gave ₹300 to Utsav which is still pending, and bought '
          'protein powder for ₹5,000';
      final result = await r.turn(text);

      // One model request, built from static instructions plus a small context.
      expect(r.provider.requests, hasLength(1));
      final req = r.provider.requests.single;
      expect(req.instructions, agentInstructions);
      expect(req.output, LlmOutputFormat.json);
      expect(req.tools, isEmpty);
      expect(req.messages, hasLength(2));
      expect(req.messages.first.content, contains('Today: Sat 2026-10-10.'));
      expect(req.messages.first.content, contains('Salary'));
      expect(req.messages.last.content, text);
      expect(result.usage.calls, 1);

      // One review card with all three, one preview and one execution call.
      expect(r.approvals, hasLength(1));
      expect(r.approvals.single.map((p) => p.descriptor.id), ['transactions.create', 'pending.create', 'transactions.create']);
      expect(r.gateway.previews, 1);
      expect(r.gateway.executions, 1);
      expect(result.actions.map((a) => a.status), everyElement(ActionResultStatus.completed));

      final s = await r.harness.snapshot();
      final salary = s.transactions.singleWhere((t) => t.type == TransactionType.income);
      expect((salary.amount, salary.categoryId, salary.date), (const Money.rupees(5000), 'cat_salary', DateTime(2026, 10, 9)));
      final protein = s.transactions.singleWhere((t) => t.note == 'protein powder');
      expect((protein.amount, protein.date, protein.type), (const Money.rupees(5000), DateTime(2026, 10, 10), TransactionType.expense));
      final debt = s.pending.single;
      expect((debt.counterparty, debt.direction, debt.kind, debt.originalAmount),
          ('Utsav', PendingDirection.owedToMe, PendingKind.lent, const Money.rupees(300)));

      // The reply is built from confirmed outcomes, not by the model.
      expect(result.reply, 'Salary of ₹5,000 added as income. Utsav owes you ₹300 (Lent money). '
          '₹5,000 on Fitness added as an expense.');

      // The history entry records what happened.
      final entry = r.history.entries.single;
      expect(entry.request, text);
      expect(entry.status, AgentRunStatus.completed);
      expect(entry.summary, '3 of 3 saved');
      expect(entry.operations.map((o) => o.status), ['saved', 'saved', 'saved']);
      expect(entry.operations.every((o) => o.recordIds.length == 1), isTrue);
    });

    test('several operations of the same type get their own steps', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 70, 'category': 'Groceries', 'note': 'vegetables'},
          {'op': 'expense', 'amount': 150, 'category': 'Groceries', 'note': 'milk'},
          {'op': 'expense', 'amount': 400, 'category': 'Transport', 'note': 'petrol', 'date': -1},
        ]),
      ]);
      final result = await r.turn('vegetables 70, milk 150 today and petrol 400 yesterday');
      expect(result.actions, hasLength(3));
      expect({for (final a in result.actions) a.proposal.stepId}, hasLength(3));
      expect(result.actions.every((a) => a.succeeded), isTrue);
      final s = await r.harness.snapshot();
      expect(s.transactions.firstWhere((t) => t.note == 'petrol').date, DateTime(2026, 10, 9));
      expect(r.provider.requests, hasLength(1));
    });

    test('a settlement is matched to the pending item locally, without a lookup call', () async {
      final r = await rig([
        plan([
          {'op': 'settle', 'person': 'Neha', 'amount': 850, 'note': 'office lunch'},
        ]),
      ]);
      final neha = await addPending(r.harness, counterparty: 'Neha Kapoor', rupees: 850, purpose: 'Office lunch');
      await addPending(r.harness, counterparty: 'Karan', rupees: 1200);
      final result = await r.turn('Neha paid me back the 850 for the office lunch');
      expect(r.provider.requests, hasLength(1));
      expect(result.actions.single.proposal.input.toJson()['pendingId'], neha.id);
      expect(result.reply, 'Received ₹850 from Neha Kapoor.');
      final s = await r.harness.snapshot();
      expect(s.pendingViews.firstWhere((v) => v.payment.id == neha.id).status, PendingStatus.settled);
    });

    test('a dependent op runs in a second wave with the id it needs, still one model call', () async {
      final r = await rig([
        plan([
          {'op': 'category', 'id': 'o1', 'name': 'Pets', 'type': 'expense'},
          {'op': 'expense', 'amount': 500, 'category': '@o1', 'note': 'dog food'},
        ]),
      ]);
      final result = await r.turn('create a category called Pets and add 500 for dog food in it');
      expect(r.provider.requests, hasLength(1));
      expect(r.approvals.map((a) => a.single.descriptor.id), ['categories.create', 'transactions.create']);
      expect(r.gateway.executions, 2);
      final s = await r.harness.snapshot();
      final pets = s.categories.singleWhere((c) => c.name == 'Pets');
      expect(s.transactions.single.categoryId, pets.id);
      expect(result.reply, 'Category "Pets" created. ₹500 on Pets added as an expense.');
      // Both waves belong to one history entry.
      expect(r.history.entries.single.operations, hasLength(2));
      expect(r.history.entries.single.status, AgentRunStatus.completed);
    });

    test('independent ops still run when a dependency is declined; the dependent one is skipped', () async {
      final r = await rig([
        plan([
          {'op': 'category', 'id': 'o1', 'name': 'Pets', 'type': 'expense'},
          {'op': 'expense', 'amount': 500, 'category': '@o1'},
          {'op': 'expense', 'amount': 90, 'category': 'Food & Dining', 'note': 'chai'},
        ]),
      ]);
      final result = await r.turn('new category Pets with 500 for dog food, and chai 90',
          approve: (p) async {
            r.approvals.add(p);
            return {for (final x in p) if (x.descriptor.id != 'categories.create') x.id};
          });
      expect(r.approvals, hasLength(1));
      expect(result.actions.map((a) => a.status),
          [ActionResultStatus.declined, ActionResultStatus.completed]);
      expect(result.reply, contains('Skipped: it needed a change that was not saved.'));
      expect((await r.harness.snapshot()).transactions.single.note, 'chai');
    });

    test('an existing category is reused instead of created again', () async {
      final r = await rig([
        plan([
          {'op': 'category', 'id': 'o1', 'name': 'groceries', 'type': 'expense'},
          {'op': 'expense', 'amount': 300, 'category': '@o1'},
        ]),
      ]);
      final result = await r.turn('make a groceries category and add 300 to it');
      expect(r.gateway.executions, 1);
      expect(result.actions.single.proposal.input.toJson()['categoryId'], 'cat_groceries');
      expect(result.actions.single.proposal.notes, contains('You already have a "Groceries" category, so I used it.'));
    });
  });

  group('clarification instead of guessing', () {
    test('several matching pending items: one question with options; the reply picks one without the model', () async {
      final r = await rig([
        plan([
          {'op': 'settle', 'person': 'Rahul', 'dir': 'owe'},
        ]),
      ]);
      final concert = await addPending(r.harness,
          counterparty: 'Rahul Verma', rupees: 2000, direction: PendingDirection.iOwe, purpose: 'Concert tickets');
      await addPending(r.harness,
          counterparty: 'Rahul Verma', rupees: 780, direction: PendingDirection.iOwe, purpose: 'Cab to airport');

      final first = await r.turn('I paid Rahul back');
      expect(first.actions, isEmpty);
      expect(r.approvals, isEmpty);
      expect(first.reply,
          'Which one with Rahul Verma: Concert tickets (₹2,000 you owe) or Cab to airport (₹780 you owe)?');

      final second = await r.turn('the concert one');
      expect(r.provider.requests, hasLength(1)); // resolved locally
      expect(second.actions.single.proposal.input.toJson(), containsPair('pendingId', concert.id));
      expect(second.actions.single.proposal.input.toJson(), containsPair('amount', '2000.00'));
      expect(second.reply, 'Paid Rahul Verma ₹2,000.');
      expect(r.history.entries.single.request, 'I paid Rahul back → the concert one');
    });

    test('a missing amount is asked for; a bare amount completes it locally', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'category': 'Groceries', 'note': 'groceries'},
        ], ask: 'How much did you spend on groceries?'),
      ]);
      final first = await r.turn('I bought groceries today');
      expect(first.reply, 'How much did you spend on groceries?');
      expect(first.actions, isEmpty);

      final second = await r.turn('₹350');
      expect(r.provider.requests, hasLength(1));
      expect(second.reply, '₹350 on Groceries added as an expense.');
    });

    test('clear ops proceed while the unclear one is asked about', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 300, 'category': 'Transport', 'note': 'uber'},
          {'op': 'expense', 'category': 'Education', 'note': 'books'},
        ], ask: 'How much were the books?'),
      ]);
      final result = await r.turn('spent 300 on uber and bought some books');
      expect(result.actions.single.succeeded, isTrue);
      expect(result.reply, '₹300 on Transport added as an expense.\nHow much were the books?');
      final next = await r.turn('450');
      expect(next.actions.single.proposal.input.toJson()['amount'], '450.00');
      expect(next.actions.single.proposal.input.toJson()['note'], 'books');
      expect(r.provider.requests, hasLength(1));
      expect((await r.harness.snapshot()).transactions, hasLength(2));
    });

    test('an answer the app cannot resolve goes to the model with the open question as context', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'category': 'Gifts & Donations', 'note': 'gift'},
        ], ask: 'How much was the gift?'),
        plan([
          {'op': 'expense', 'amount': 1200, 'category': 'Gifts & Donations', 'note': 'gift'},
          {'op': 'expense', 'amount': 300, 'category': 'Shopping', 'note': 'wrapping'},
        ]),
      ]);
      await r.turn('bought a gift');
      final result = await r.turn('it was for my sister, 1200 for the gift and 300 for wrapping paper');
      expect(r.provider.requests, hasLength(2));
      final context = r.provider.requests.last.messages.first.content!;
      expect(context, contains('Pending question you asked: "How much was the gift?"'));
      expect(context, contains('"op":"expense"'));
      expect(context, contains('Original message: "bought a gift"'));
      expect(result.actions, hasLength(2));
    });

    test('an op that depends on an unanswered question waits with it instead of being skipped', () async {
      final r = await rig([
        plan([
          {'op': 'category', 'id': 'o1', 'type': 'expense'},
          {'op': 'expense', 'amount': 500, 'category': '@o1', 'note': 'dog food'},
          {'op': 'expense', 'amount': 90, 'category': 'Food & Dining', 'note': 'chai'},
        ]),
        plan([
          {'op': 'category', 'id': 'o1', 'name': 'Pets', 'type': 'expense'},
          {'op': 'expense', 'amount': 500, 'category': '@o1', 'note': 'dog food'},
        ]),
      ]);
      final first = await r.turn('new category for 500 of dog food, and chai 90');
      expect(first.actions.single.proposal.input.toJson()['note'], 'chai');
      expect(first.reply, '₹90 on Food & Dining added as an expense.\nWhat should the new category be called?');
      expect(r.runner.memory.pending!.ops.map((o) => o.type), ['category', 'expense']);
      final second = await r.turn('call it Pets');
      expect(second.actions.map((a) => a.proposal.descriptor.id), ['categories.create', 'transactions.create']);
      expect((await r.harness.snapshot()).transactions, hasLength(2));
    });

    test('a reused category note sits on the change that uses it', () async {
      final r = await rig([
        plan([
          {'op': 'category', 'name': 'Groceries', 'type': 'expense'},
        ]),
      ]);
      final result = await r.turn('create a groceries category');
      expect(result.actions, isEmpty);
      expect(result.reply, 'You already have a "Groceries" category, so I used it.');
    });

    test('a generic person is asked about instead of saved as "friend"', () async {
      final r = await rig([
        plan([
          {'op': 'pending', 'dir': 'collect', 'person': 'friend', 'amount': 300},
        ]),
      ]);
      final result = await r.turn('gave 300 to a friend, still pending');
      expect(result.actions, isEmpty);
      expect(result.reply, 'Who is this with?');
    });
  });

  group('validation, failures and duplicates', () {
    test('unusable model output is retried once, then reported without changing anything', () async {
      final r = await rig([says('Sure! I will add that.'), says('{"ops": 5}')]);
      final result = await r.turn('spent 450 on lunch');
      expect(result.end, AgentTurnEnd.failed);
      expect(result.reply, 'I couldn\'t work out what to do. Please rephrase.');
      expect(r.provider.requests, hasLength(2));
      expect(r.approvals, isEmpty);
      expect(r.history.entries, isEmpty);
    });

    test('a retry after unusable output can still succeed', () async {
      final r = await rig([
        says('```json\n{"ops":[{"op":"expense"'),
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch'},
        ]),
      ]);
      final result = await r.turn('spent 450 on lunch');
      expect(result.actions.single.succeeded, isTrue);
      expect(result.usage.calls, 2);
    });

    test('unknown op types are refused and the rest of the plan proceeds', () async {
      final r = await rig([
        plan([
          {'op': 'transfer_money', 'amount': 500, 'to': 'Rahul'},
          {'op': 'expense', 'amount': 90, 'category': 'Food & Dining', 'note': 'chai'},
        ]),
      ]);
      final result = await r.turn('send 500 to Rahul and chai 90');
      expect(result.actions.single.succeeded, isTrue);
      expect(result.reply, contains('I can\'t do "transfer_money" yet.'));
    });

    test('a preview failure (validation by the backend) is reported, never shown for approval', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'date': 3},
        ]),
      ]);
      final result = await r.turn('lunch 450 in 3 days');
      expect(r.approvals, isEmpty);
      expect(result.actions, isEmpty);
      expect(result.reply, contains('Couldn\'t prepare "record a transaction"'));
      expect(result.reply, contains('future'));
    });

    test('partial success: each outcome is reported truthfully and history says partial', () async {
      final h = await ActionHarness.create();
      final r = AgentRig(
        h,
        ScriptedProvider([
          plan([
            {'op': 'expense', 'amount': 250, 'category': 'Transport', 'note': 'auto'},
            {'op': 'pending', 'dir': 'owe', 'person': 'Karan', 'amount': 1200, 'note': 'dinner'},
          ]),
        ]),
        dispatcher: RefusingDispatcher(h.dispatcher, 'pending.create', const AppFailure.conflict('Karan\'s item was changed elsewhere.')),
      );
      final result = await r.turn('auto 250 and I owe Karan 1200 for dinner');
      expect(result.actions.map((a) => a.status), [ActionResultStatus.completed, ActionResultStatus.failed]);
      expect(result.reply, '₹250 on Transport added as an expense. Not done: Owe ₹1,200 · dinner '
          '(Karan\'s item was changed elsewhere.).');
      expect(r.history.entries.single.status, AgentRunStatus.partial);
      expect(r.history.entries.single.summary, '1 of 2 saved, 1 not saved');
    });

    test('a lost reply is "not confirmed"; sending the same request again replays instead of writing twice', () async {
      final h = await ActionHarness.create();
      final flaky = FlakyDispatcher(h.dispatcher);
      final lunch = {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch'};
      final r = AgentRig(h, ScriptedProvider([plan([lunch]), plan([lunch])]), dispatcher: flaky);

      final first = await r.turn('spent 450 on lunch');
      expect(first.actions.single.status, ActionResultStatus.failed);
      expect(first.actions.single.outcomeUnknown, isTrue);
      final second = await r.turn('spent 450 on lunch');
      expect(second.actions.single.status, ActionResultStatus.alreadyDone);
      expect(second.actions.single.proposal.idempotencyKey, first.actions.single.proposal.idempotencyKey);
      expect((await h.snapshot()).transactions, hasLength(1));
      expect(flaky.attemptsByKey.values.single, 2);
    });

    test('a deliberate repeat in a later turn is a new write, flagged as a possible duplicate', () async {
      final lunch = {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch'};
      final r = await rig([plan([lunch]), plan([lunch])]);
      final first = await r.turn('spent 450 on lunch');
      final second = await r.turn('spent 450 on lunch again');
      expect(second.actions.single.proposal.idempotencyKey, isNot(first.actions.single.proposal.idempotencyKey));
      expect(second.actions.single.proposal.notes.single, contains('already recorded an identical entry'));
      expect((await r.harness.snapshot()).transactions, hasLength(2));
    });

    test('two identical ops in one message are both offered, with a note to exclude one', () async {
      final parking = {'op': 'expense', 'amount': 50, 'category': 'Transport', 'note': 'parking'};
      final r = await rig([plan([parking, parking])]);
      final result = await r.turn('paid 50 for parking twice');
      expect(result.actions, hasLength(2));
      expect(result.actions[0].proposal.stepId, isNot(result.actions[1].proposal.stepId));
      expect(result.actions[1].proposal.notes.single, startsWith('Same as another change'));
    });

    test('declining writes nothing and records a declined history entry', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining'},
        ]),
      ]);
      final result = await r.turn('spent 450 on lunch', approve: r.declineAll);
      expect(result.actions.single.status, ActionResultStatus.declined);
      expect(result.reply, 'Not done: Spent ₹450.');
      expect((await r.harness.snapshot()).transactions, isEmpty);
      expect(r.history.entries.single.status, AgentRunStatus.declined);
    });

    test('stopping during review runs nothing', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining'},
        ]),
      ]);
      final token = CancellationToken();
      final result = await r.turn('spent 450 on lunch', cancel: token, approve: (p) {
        token.cancel();
        return Future<Set<String>>.delayed(const Duration(seconds: 5), () => {p.single.id});
      });
      expect(result.end, AgentTurnEnd.cancelled);
      expect(result.actions.single.status, ActionResultStatus.cancelled);
      expect((await r.harness.snapshot()).transactions, isEmpty);
    });

    test('model outages are retried once, then reported', () async {
      const outage = LlmException(LlmErrorKind.unavailable, 'The assistant is unavailable right now.', retryable: true);
      final r = await rig([outage, outage]);
      final result = await r.turn('spent 450 on lunch');
      expect(result.end, AgentTurnEnd.failed);
      expect(result.reply, 'The assistant is unavailable right now.');
      expect(r.provider.requests, hasLength(2));
    });

    test('invented payment methods and shops are dropped', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 200, 'category': 'Food & Dining', 'note': 'coffee', 'method': 'cash', 'party': 'Starbucks'},
        ]),
      ]);
      final result = await r.turn('spent 200 on coffee');
      final input = result.actions.single.proposal.input.toJson();
      expect(input['paymentMethod'], isNull);
      expect(input['counterparty'], isNull);
    });

    test('a stated payment method and shop are kept', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 200, 'category': 'Food & Dining', 'method': 'upi', 'party': 'Starbucks'},
        ]),
      ]);
      final result = await r.turn('paid 200 at Starbucks via gpay');
      final input = result.actions.single.proposal.input.toJson();
      expect(input['paymentMethod'], 'upi');
      expect(input['counterparty'], 'Starbucks');
    });
  });

  group('answers without extra model calls', () {
    test('a data question is answered by the app from the one plan call', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining'},
          {'op': 'expense', 'amount': 120, 'category': 'Food & Dining', 'date': -1},
        ]),
        plan([
          {'op': 'q', 'metric': 'spent', 'category': 'Food & Dining', 'period': 'month'},
        ]),
      ]);
      await r.turn('lunch 450 and dinner 120 yesterday');
      final result = await r.turn('how much have I spent on food this month?');
      expect(r.provider.requests, hasLength(2));
      expect(result.reply, 'You spent ₹570 on Food & Dining this month (1 Oct–31 Oct), across 2 entries.');
      expect(r.history.entries, hasLength(1)); // questions are not history
    });

    test('history and balance questions need no model call at all', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch'},
        ]),
      ]);
      await r.turn('spent 450 on lunch');
      final history = await r.turn('what did I ask you to do today?');
      expect(history.reply, 'Here is what you asked me today:\n• today 09:00: "spent 450 on lunch" — 1 change saved.');
      final balance = await r.turn("what's my balance?");
      expect(balance.reply, startsWith('You have ₹99,550 available to spend'));
      expect(r.provider.requests, hasLength(1));
      expect(balance.usage.calls, 0);
    });

    test('the model sees neither records nor history', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'secret lunch'},
        ]),
        plan([
          {'op': 'expense', 'amount': 90, 'category': 'Food & Dining'},
        ]),
      ]);
      await addPending(r.harness, counterparty: 'Neha', rupees: 850);
      await r.turn('spent 450 on lunch');
      await r.turn('chai 90');
      final sent = r.provider.requests.last.messages.map((m) => m.content).join('\n');
      expect(sent, isNot(contains('Neha')));
      expect(sent, isNot(contains('pend_')));
      expect(sent, isNot(contains('tx_')));
      // Only the bounded follow-up context names the last change.
      expect(sent, contains('Recent (already saved; refer by #n): #1 ₹450 on Food & Dining added as an expense'));
    });
  });

  group('follow-ups', () {
    test('"make that 400" edits the change it refers to, keeping its other fields', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch'},
        ]),
        plan([
          {
            'op': 'edit',
            'target': '#1',
            'set': {'amount': 400},
          },
        ]),
      ]);
      await r.turn('spent 450 on lunch');
      final result = await r.turn('actually make that 400');
      expect(result.actions.single.proposal.descriptor.id, 'transactions.update');
      final tx = (await r.harness.snapshot()).transactions.single;
      expect((tx.amount, tx.categoryId, tx.note), (const Money.rupees(400), 'cat_food', 'lunch'));
      expect(r.provider.requests, hasLength(2));
    });

    test('"undo that" is explained, never executed', () async {
      final r = await rig([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food & Dining'},
        ]),
        plan([
          {'op': 'undo', 'target': '#1'},
        ]),
      ]);
      await r.turn('spent 450 on lunch');
      final result = await r.turn('undo that');
      expect(result.actions, isEmpty);
      expect(result.reply, startsWith('I can\'t delete records.'));
      expect((await r.harness.snapshot()).transactions, hasLength(1));
    });

    test('relative dates use the user\'s configured "today"', () async {
      final h = await ActionHarness.create();
      final r = AgentRig(h, ScriptedProvider([]));
      final provider = ScriptedProvider([
        plan([
          {'op': 'expense', 'amount': 100, 'category': 'Transport', 'date': -1},
        ]),
      ]);
      final runner = AgentRunner(
        provider: provider,
        gateway: r.gateway,
        registry: r.runner.registry,
        loadSnapshot: h.snapshot,
        conversationId: 'c_tz',
        // The server's zone is already on 11 Oct while the device says 10 Oct.
        userToday: () => DateTime(2026, 10, 11),
      );
      final result = await runner.runTurn('auto 100 yesterday', approve: r.approveAll);
      expect(provider.requests.single.messages.first.content, contains('Today: Sun 2026-10-11.'));
      expect(result.actions.single.proposal.input.toJson()['date'], '2026-10-10');
    });
  });
}
