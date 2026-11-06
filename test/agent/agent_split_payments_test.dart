// The agent and the money rules added with split payments: one payment
// paid from several accounts ("parts"), the no-overdraft rule turned into a
// follow-up question, and shared items only the person owed may close.

import 'package:finn/core/money/money.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:finn/features/accounts/application/account_actions.dart';
import 'package:finn/features/accounts/domain/money_account.dart';
import 'package:finn/features/pending/domain/pending_payment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'agent_fakes.dart';

void main() {
  group('a payment split across accounts', () {
    late AgentRig r;
    late MoneyAccount card;

    Future<void> setUpRig(List<Object> script) async {
      final h = await ActionHarness.create();
      await h.run(const SetAccountBalanceAction(), SetAccountBalanceInput(id: cashAccountId, balance: const Money.rupees(2000)));
      card = await h.run(
        const CreateAccountAction(),
        AccountInput(name: 'Debit card', kind: MoneyAccountKind.debitCard, openingBalance: const Money.rupees(4000)),
      );
      r = AgentRig(h, ScriptedProvider(script));
    }

    Future<Money> bal(String id) async => (await r.harness.snapshot()).balance.balanceOf(id)!;

    test('"the rest" part is filled in and the payment is one transaction', () async {
      await setUpRig([
        plan([
          {
            'op': 'expense',
            'amount': 5400,
            'category': 'Food & Dining',
            'note': 'dinner',
            'parts': [
              {'account': 'debit card', 'amount': 4000},
              {'account': 'cash'},
            ],
          },
        ]),
      ]);
      final result = await r.turn('dinner 5400, 4000 on the debit card and the rest in cash');
      final input = result.actions.single.proposal.input.toJson();
      expect(input['accountId'], card.id);
      expect(input['splits'], [
        {'accountId': card.id, 'amount': '4000.00'},
        {'accountId': cashAccountId, 'amount': '1400.00'},
      ]);
      expect(result.actions.single.succeeded, isTrue);
      expect(await bal(card.id), Money.zero);
      expect(await bal(cashAccountId), const Money.rupees(600));
      expect((await r.harness.snapshot()).transactions.where((t) => t.isSplit), hasLength(1));
    });

    test('parts that do not add up are asked about, nothing is saved', () async {
      await setUpRig([
        plan([
          {
            'op': 'expense',
            'amount': 5400,
            'category': 'Food & Dining',
            'parts': [
              {'account': 'debit card', 'amount': 4000},
              {'account': 'cash', 'amount': 1000},
            ],
          },
        ]),
      ]);
      final result = await r.turn('dinner 5400, 4000 on the debit card and 1000 cash');
      expect(result.actions, isEmpty);
      expect(result.reply, contains('add up to ₹5,000, not ₹5,400'));
    });

    test('an account that cannot cover it gets a question naming one that can; the answer saves locally', () async {
      await setUpRig([
        plan([
          {'op': 'expense', 'amount': 3000, 'category': 'Shopping', 'note': 'shoes', 'account': 'cash'},
        ]),
      ]);
      final asked = await r.turn('shoes 3000 in cash');
      expect(asked.actions, isEmpty);
      expect(asked.reply, contains('Not enough money in Cash.'));
      expect(asked.reply, contains('Which account should I use instead: Debit card?'));
      expect(asked.reply, isNot(contains('Split the payment across accounts.')));

      final saved = await r.turn('debit card');
      expect(r.provider.requests, hasLength(1), reason: 'the choice is applied without the model');
      expect(saved.actions.single.succeeded, isTrue);
      expect(saved.actions.single.proposal.input.toJson()['accountId'], card.id);
      expect(await bal(card.id), const Money.rupees(1000));
    });

    test('when only several accounts together cover it, the agent asks how to split', () async {
      await setUpRig([
        plan([
          {'op': 'expense', 'amount': 5400, 'category': 'Food & Dining', 'account': 'cash'},
        ]),
      ]);
      final asked = await r.turn('dinner 5400 in cash');
      expect(asked.actions, isEmpty);
      expect(asked.reply, contains('How should I split it across your accounts?'));
    });
  });

  group('shared items', () {
    test('a shared item the user owes is not settled by the agent; the person owed settles it', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final r = AgentRig(h, ScriptedProvider([
        plan([
          {'op': 'settle', 'person': 'Rahul', 'dir': 'owe', 'note': 'concert tickets'},
        ]),
      ]));
      final result = await r.turn('I paid Rahul back for the concert tickets');
      expect(result.actions, isEmpty);
      expect(result.reply, contains('Only Rahul Verma can settle it.'));
      final concert = (await h.snapshot()).pendingViews.firstWhere((v) => v.payment.purpose == 'Concert tickets');
      expect(concert.status, isNot(PendingStatus.settled));
    });

    test('a private item with the same person can still be settled', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final r = AgentRig(h, ScriptedProvider([
        plan([
          {'op': 'settle', 'person': 'Rahul', 'dir': 'owe', 'note': 'cab to airport', 'account': 'Axis'},
        ]),
      ]));
      final result = await r.turn('paid Rahul back for the cab to airport from Axis');
      expect(result.actions.single.succeeded, isTrue);
      final cab = (await h.snapshot()).pendingViews.firstWhere((v) => v.payment.purpose == 'Cab to airport');
      expect(cab.status, PendingStatus.settled);
    });
  });
}
