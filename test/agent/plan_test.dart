import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/orchestration/agent_memory.dart';
import 'package:finn/agent/orchestration/local_intents.dart';
import 'package:finn/agent/plan/agent_plan.dart';
import 'package:finn/agent/plan/op_catalog.dart';
import 'package:finn/agent/plan/resolvers.dart';
import 'package:finn/agent/prompt/agent_prompt.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/core/money/money.dart';
import 'package:finn/core/result/result.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';

void main() {
  group('PlanParser', () {
    test('parses ops with stable refs, ask and reply', () {
      final plan = PlanParser.parse(
        '{"ops":[{"op":"category","id":"o1","name":"Pets","type":"expense"},'
        '{"op":"expense","amount":500,"category":"@o1","note":null}],"ask":" ok? ","reply":""}',
      );
      expect(plan.ops.map((o) => (o.ref, o.type)), [('o1', 'category'), ('o2', 'expense')]);
      expect(plan.ops[1].args, {'amount': 500, 'category': '@o1'}); // nulls dropped
      expect(plan.ask, 'ok?');
      expect(plan.reply, isNull);
    });

    test('tolerates a fenced block', () {
      expect(PlanParser.parse('```json\n{"reply":"Hi!"}\n```').reply, 'Hi!');
    });

    test('rejects unusable output', () {
      for (final bad in [
        null,
        '',
        'Sure, done!',
        '[1,2]',
        '{"ops":5}',
        '{"ops":[1]}',
        '{"ops":[{"amount":5}]}',
        '{"ops":[]}',
        '{"ops":[{"op":"expense","category":"@o2"},{"op":"category","id":"o2"}]}', // forward reference
        '{"ops":[{"op":"a","id":"o1"},{"op":"b","id":"o1"}]}',
        '{"ops":[${List.filled(13, '{"op":"expense"}').join(',')}]}',
      ]) {
        expect(() => PlanParser.parse(bad), throwsA(isA<PlanFormatException>()), reason: '$bad');
      }
    });

    test('never takes app-reserved "_" fields from the model', () {
      final plan = PlanParser.parse('{"ops":[{"op":"settle","person":"Rahul","_id":"pend_x"}]}');
      expect(plan.ops.single.args, {'person': 'Rahul'});
    });
  });

  group('resolvers', () {
    test('amounts: numbers, Indian suffixes, symbols; nothing else', () {
      Money? m(Object? v) => AgentAmount.parse(v);
      expect(m(5000), const Money.rupees(5000));
      expect(m('₹5,000'), const Money.rupees(5000));
      expect(m('2k'), const Money.rupees(2000));
      expect(m('1.5L'), const Money.rupees(150000));
      expect(m('1.2 lakh'), const Money.rupees(120000));
      expect(m('1 crore'), const Money.rupees(10000000));
      expect(m('Rs. 99.5'), const Money.fromPaise(9950));
      expect(m(null), isNull);
      for (final bad in [0, -5, 'lots', '5 bucks extra', double.nan]) {
        expect(() => m(bad), throwsA(isA<FieldProblem>()), reason: '$bad');
      }
      expect(AgentAmount.only('350'), const Money.rupees(350));
      expect(AgentAmount.only('it was 2.5k'), const Money.rupees(2500));
      expect(AgentAmount.only('300 and 200'), isNull);
      expect(AgentAmount.only('the concert one'), isNull);
    });

    test('dates: offsets, words and ISO relative to today', () {
      final today = DateTime(2026, 10, 1);
      expect(AgentDate.resolve(-1, today), DateTime(2026, 9, 30));
      expect(AgentDate.resolve('-2', today), DateTime(2026, 9, 29));
      expect(AgentDate.resolve('yesterday', today), DateTime(2026, 9, 30));
      expect(AgentDate.resolve('2026-02-28', today), DateTime(2026, 2, 28));
      expect(AgentDate.resolve(null, today), isNull);
      for (final bad in ['2026-02-30', 'next friday', 1.5, 99999]) {
        expect(() => AgentDate.resolve(bad, today), throwsA(isA<FieldProblem>()), reason: '$bad');
      }
    });

    test('channels only when the user named one', () {
      expect(AgentChannel.resolve('upi', 'paid via gpay'), 'UPI');
      expect(AgentChannel.resolve('neft', 'sent by NEFT'), 'NEFT');
      expect(AgentChannel.resolve('upi', 'spent 200 on coffee'), isNull);
      expect(AgentChannel.resolve('imps', 'paid by upi'), isNull);
      expect(AgentChannel.resolve('wire', 'sent a wire to Ravi'), 'wire');
    });

    test('names match like a person would, never by guessing', () {
      final goals = ['Japan cherry blossom trip', 'MacBook Pro', 'Masters abroad fund'];
      expect(matchByName('Japan trip', goals, (g) => [g]), isA<Matched<String>>());
      expect((matchByName('macbook', goals, (g) => [g]) as Matched<String>).value, 'MacBook Pro');
      expect(matchByName('car', goals, (g) => [g]), isA<NoMatch<String>>());
      final people = ['Rahul Verma', 'Rahul Shah'];
      expect((matchByName('Rahul', people, (p) => [p]) as Ambiguous<String>).candidates, people);
      expect((matchByName('rahul verma', people, (p) => [p]) as Matched<String>).value, 'Rahul Verma');
    });

    test('grounding: a name must appear in what the user said', () {
      expect(grounded('Utsav', 'gave 300 to utsav'), isTrue);
      expect(grounded('Starbucks', 'spent 200 on coffee'), isFalse);
      expect(grounded('Neha Kapoor', 'neha paid me'), isTrue);
    });
  });

  group('op catalog', () {
    test('every op type is described in the instructions and vice versa', () {
      final described = RegExp(r'^([a-z_]+) \{', multiLine: true).allMatches(agentInstructions).map((m) => m.group(1)!).toSet()
        ..add('fund_take'); // shares a line with fund_add
      expect(described, opCatalog.keys.toSet());
    });

    test('every action an op can produce is registered and none is a delete', () {
      final registry = ActionRegistry(allActions);
      for (final spec in opCatalog.values) {
        for (final id in spec.actionIds) {
          expect(registry.lookup(id), isNotNull, reason: id);
          expect(id.endsWith('.delete'), isFalse);
        }
      }
    });

    test('static instructions are long enough to cache and contain no per-request data', () {
      // ~4 characters per token: comfortably over the 1,024-token minimum.
      expect(agentInstructions.length, greaterThan(5000));
      expect(agentInstructions, isNot(contains('Today:')));
      expect(agentInstructions, isNot(contains('cat_')));
    });

    test('each op type compiles to input its action accepts', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final s = await h.snapshot();
      final registry = ActionRegistry(allActions);
      final memory = AgentMemory()
        ..remember([RecentOp(actionId: 'transactions.create', summary: 'lunch', recordId: s.transactions.firstWhere((t) => !t.isLinked).id)]);
      final samples = <String, Map<String, Object?>>{
        'expense': {'amount': 450, 'category': 'Food & Dining', 'account': 'Cash'},
        'income': {'amount': '15k', 'category': 'Freelance', 'party': 'Acme', 'account': 'Cash'},
        'pending': {'dir': 'owe', 'person': 'Rohan', 'amount': 2000, 'kind': 'borrowed'},
        'settle': {'person': 'Neha', 'account': 'Cash'},
        'write_off': {'person': 'Ananya'},
        'split': {'total': 1800, 'people': ['Aman', 'Riya']},
        'edit': {'target': '#1', 'set': {'amount': 400}},
        'category': {'name': 'Pets', 'type': 'expense'},
        'budget': {'category': 'Shopping', 'limit': 5000},
        'budget_pause': {'category': 'Travel', 'paused': true},
        'loan_pay': {'loan': 'car loan', 'account': 'Cash'},
        'loan': {'name': 'Bike', 'lender': 'SBI', 'dir': 'borrowed', 'principal': 100000, 'rate': 10.5, 'start': 0, 'first_due': '2026-11-05', 'emis': 12},
        'sub_paid': {'name': 'netflix', 'account': 'Cash'},
        'sub_status': {'name': 'spotify', 'status': 'paused'},
        'sub_skip': {'name': 'youtube'},
        'subscription': {'name': 'Swiggy One', 'amount': 99, 'category': 'Subscriptions', 'every': 'monthly', 'next': '2026-11-01'},
        'goal': {'name': 'Goa', 'target': '50k', 'by': '2027-03-01'},
        'goal_add': {'goal': 'Japan trip', 'amount': 2000, 'account': 'SBI'},
        'goal_take': {'goal': 'macbook', 'amount': 500},
        'fund_add': {'amount': 1000, 'account': 'SBI'},
        'fund_take': {'amount': 500},
      };
      final text = 'gpay Aman Riya Rohan Neha Ananya Acme SBI cash';
      for (final e in samples.entries) {
        final out = compileOp(
          PlanOp(ref: 'o1', type: e.key, args: e.value),
          OpContext(snapshot: s, today: s.today, userText: text, memory: memory),
        );
        expect(out, isA<OpAction>(), reason: '${e.key}: $out ${out is OpRejected ? out.reason : out is OpQuestion ? out.question : ''}');
        final a = out as OpAction;
        expect(opCatalog[e.key]!.actionIds, contains(a.actionId));
        expect(() => registry.lookup(a.actionId)!.decode(a.input), returnsNormally, reason: e.key);
        final preview = await h.dispatcher.preview(registry.lookup(a.actionId)!, registry.lookup(a.actionId)!.decode(a.input));
        expect(preview.isOk, isTrue, reason: '${e.key}: $preview');
      }
    });

    test('missing essentials become questions, unknown records rejections', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final s = await h.snapshot();
      OpOutcome c(String type, Map<String, Object?> args, {String text = ''}) => compileOp(
        PlanOp(ref: 'o1', type: type, args: args),
        OpContext(snapshot: s, today: s.today, userText: text, memory: AgentMemory()),
      );
      expect((c('expense', {'category': 'Groceries', 'note': 'veggies'}) as OpQuestion).field, 'amount');
      expect((c('expense', {'amount': 'a lot'}) as OpQuestion).question, startsWith('The amount is not clear.'));
      expect((c('pending', {'dir': 'collect', 'amount': 300}) as OpQuestion).question, 'Who is this with?');
      expect((c('pending', {'person': 'Amit', 'amount': 300}, text: 'amit') as OpQuestion).field, 'dir');
      final rahul = c('settle', {'person': 'Rahul'}) as OpQuestion;
      expect(rahul.options, hasLength(2));
      expect(c('settle', {'person': 'Rahul', 'amount': 780, 'account': 'Cash'}, text: 'cash'), isA<OpAction>()); // narrowed by amount
      expect(c('settle', {'person': 'Rahul', 'note': 'concert', 'account': 'Cash'}, text: 'cash'), isA<OpAction>()); // narrowed by purpose
      expect((c('settle', {'person': 'Zed'}) as OpRejected).reason, 'There is no open pending payment with Zed.');
      expect((c('settle', {'person': 'Neha', 'amount': 99999}) as OpRejected).reason, contains('Only ₹850'));
      expect((c('goal_add', {'goal': 'yacht', 'amount': 5}) as OpRejected).reason, 'You don\'t have a goal called "yacht".');
      expect(c('loan_pay', {}), isA<OpQuestion>()); // several open loans
      expect(c('edit', {'target': '#1', 'set': {'amount': 1}}), isA<OpRejected>()); // nothing recent
      expect(c('teleport', {}), isA<OpRejected>());
    });

    test('a money movement without an account asks which one; savings never offer a credit card', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final s = await h.snapshot();
      OpOutcome c(String type, Map<String, Object?> args, {String text = ''}) => compileOp(
        PlanOp(ref: 'o1', type: type, args: args),
        OpContext(snapshot: s, today: s.today, userText: text, memory: AgentMemory()),
      );
      final names = [for (final a in s.activeAccounts) a.name];
      final credit = s.activeAccounts.firstWhere((a) => a.isLiability);

      final spend = c('expense', {'amount': 450, 'category': 'Food & Dining'}) as OpQuestion;
      expect(spend.field, 'account');
      expect(spend.options.map((o) => o.label), names);
      expect(spend.question, startsWith('Which account did you pay from: ${names.first}, '));

      final fund = c('fund_add', {'amount': 5000}) as OpQuestion;
      expect(fund.field, 'account');
      expect(fund.question, startsWith('Which account should I set this aside on: '));
      expect(fund.options.map((o) => o.value), isNot(contains(credit.id)));

      final onCard = c('fund_add', {'amount': 5000, 'account': credit.name}, text: credit.name) as OpQuestion;
      expect(onCard.question, startsWith('${credit.name} is a credit card, which cannot hold savings.'));
      final unknown = c('goal_add', {'goal': 'Japan trip', 'amount': 500, 'account': 'Kotak'}, text: 'kotak') as OpQuestion;
      expect(unknown.question, startsWith('You have no "Kotak" account. Which account should I set this aside on'));

      expect((c('fund_add', {'amount': 500, 'account': 'Cash'}, text: 'from cash') as OpAction).input['accountId'], 'acc_cash');
      expect(c('fund_take', {'amount': 500}), isA<OpAction>()); // released from where it is held
    });

    test('a refused change becomes a question when one answer can fix it', () async {
      final h = await ActionHarness.create(scenario: DataScenario.demo);
      final s = await h.snapshot();
      final ctx = OpContext(snapshot: s, today: s.today, userText: '', memory: AgentMemory());
      const fund = PlanOp(ref: 'o1', type: 'fund_add', args: {'amount': 5000});
      final short = refusalQuestion(
        fund,
        const AppFailure.validation('Only ₹200 in Cash is free to set aside.', fields: {'amount': 'Only ₹200 in Cash is free to set aside.'}),
        ctx,
        failedAccountId: 'acc_cash',
      )!;
      expect(short.field, 'account');
      expect(short.question, startsWith('Only ₹200 in Cash is free to set aside. Which account should I set it aside on instead: '));
      expect(short.question, endsWith('Or tell me a smaller amount.'));
      expect(short.options.map((o) => o.value), isNot(contains('acc_cash')));

      final tooMuch = refusalQuestion(
        const PlanOp(ref: 'o1', type: 'fund_take', args: {'amount': 9000}),
        const AppFailure.validation('That is more than is set aside.', fields: {'amount': 'That is more than is set aside.'}),
        ctx,
      )!;
      expect((tooMuch.field, tooMuch.question), ('amount', 'That is more than is set aside. How much should it be?'));

      expect(refusalQuestion(fund, const AppFailure(FailureCode.unknown, 'Something went wrong.'), ctx), isNull);
    });

    test('an unknown category name falls back to "Other" with a note', () async {
      final h = await ActionHarness.create();
      final s = await h.snapshot();
      final out = compileOp(
        const PlanOp(ref: 'o1', type: 'expense', args: {'amount': 10, 'category': 'Spaceships'}),
        OpContext(snapshot: s, today: s.today, userText: '', memory: AgentMemory()),
      ) as OpAction;
      expect(out.input['categoryId'], 'cat_sys_other_out');
      expect(out.notes.single, 'No "Spaceships" category, so it goes under Other Expense.');
    });
  });

  group('LocalIntents', () {
    test('history and balance questions are recognised narrowly', () {
      final m = AgentMemory();
      expect(LocalIntents.match('What did I ask you to do yesterday?', m), isA<HistoryIntent>());
      expect((LocalIntents.match('show my agent history', m) as HistoryIntent).period, isNull);
      expect(LocalIntents.match('what have you saved this week', m), isA<HistoryIntent>());
      expect(LocalIntents.match("what's my balance?", m), isA<BalanceIntent>());
      expect(LocalIntents.match('how much money do I have left', m), isA<BalanceIntent>());
      // New instructions always go to the model.
      expect(LocalIntents.match('show my history', m), isA<HistoryIntent>());
      for (final t in [
        'add 500 to my balance',
        'spent 200, what is my balance',
        'history book 300',
        'balance transfer fee 99',
        'show my spending history for food',
        'show my recent changes to the rent budget',
      ]) {
        expect(LocalIntents.match(t, m), isNull, reason: t);
      }
    });

    test('a reply to an open question is completed locally only when it is unambiguous', () {
      final m = AgentMemory()
        ..pending = const PendingClarification(
          question: 'Which one?',
          originalText: 'I paid Rahul back',
          ops: [PlanOp(ref: 'o1', type: 'settle', args: {'person': 'Rahul'})],
          opRef: 'o1',
          field: '_id',
          options: [
            ClarifyOption(label: 'Concert tickets (₹2,000 you owe)', value: 'p1', amount: Money.rupees(2000)),
            ClarifyOption(label: 'Cab to airport (₹780 you owe)', value: 'p2', amount: Money.rupees(780)),
          ],
        );
      String? pick(String t) => (LocalIntents.match(t, m) as ClarificationAnswer?)?.ops.single.args['_id'] as String?;
      expect(pick('2'), 'p2');
      expect(pick('the first one'), 'p1');
      expect(pick('the 780 one'), 'p2');
      expect(pick('concert'), 'p1');
      expect(pick('the cab to the airport one please'), 'p2');
      expect(pick('neither, it was the hotel booking from last month in Goa'), isNull);
    });

    test('an account answer matches its name, bank or kind and completes every op that asked', () {
      final m = AgentMemory()
        ..pending = const PendingClarification(
          question: 'Which account did you pay from: Cash or HDFC Salary?',
          originalText: 'lunch 450 and cab 200',
          ops: [
            PlanOp(ref: 'o1', type: 'expense', args: {'amount': 450}),
            PlanOp(ref: 'o2', type: 'expense', args: {'amount': 200}),
          ],
          opRef: 'o1',
          alsoRefs: ['o2'],
          field: 'account',
          options: [
            ClarifyOption(label: 'Cash', value: 'acc_cash', aliases: ['Cash']),
            ClarifyOption(label: 'HDFC Salary', value: 'acc_hdfc', aliases: ['HDFC Salary', 'HDFC', 'Bank account']),
          ],
        );
      List<Object?>? pick(String t) =>
          (LocalIntents.match(t, m) as ClarificationAnswer?)?.ops.map((o) => o.args['account']).toList();
      expect(pick('cash'), ['acc_cash', 'acc_cash']);
      expect(pick('hdfc'), ['acc_hdfc', 'acc_hdfc']);
      expect(pick('bank account'), ['acc_hdfc', 'acc_hdfc']);
      expect(pick('2'), ['acc_hdfc', 'acc_hdfc']);
    });
  });
}
