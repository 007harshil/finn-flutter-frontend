// Shared helpers for the opt-in live agent benchmark (real OpenAI calls).
//
// Run with:  FINN_LIVE=1 flutter test test/agent/live/
// The key is read from ../finn-backend/.env.local (OPENAI_API_KEY) and never
// printed. Without FINN_LIVE=1 every live test is skipped.

import 'dart:convert';
import 'dart:io';

import 'package:finn/actions/action.dart';
import 'package:finn/actions/dispatcher.dart';
import 'package:finn/agent/llm/llm_provider.dart';
import 'package:finn/agent/llm/llm_transport.dart';
import 'package:finn/core/result/result.dart';
import 'package:http/http.dart' as http;

/// Null when live tests are off (the reason to skip).
String? get liveSkipReason => Platform.environment['FINN_LIVE'] == '1' ? null : 'Set FINN_LIVE=1 to call OpenAI';

String _env(String name) {
  final file = File('../finn-backend/.env.local');
  if (!file.existsSync()) throw StateError('finn-backend/.env.local not found');
  for (final line in file.readAsLinesSync()) {
    final i = line.indexOf('=');
    if (i > 0 && line.substring(0, i).trim() == name) return line.substring(i + 1).trim();
  }
  throw StateError('$name missing in .env.local');
}

/// One upstream model call.
class CallMetric {
  CallMetric({
    required this.model,
    required this.ms,
    required this.input,
    required this.cached,
    required this.cacheWrite,
    required this.output,
    required this.reasoning,
  });
  final String model;
  final int ms;
  final int input;
  final int cached;
  final int cacheWrite;
  final int output;
  final int reasoning;

  Map<String, Object?> toJson() => {
    'model': model,
    'ms': ms,
    'input': input,
    'cached': cached,
    'cacheWrite': cacheWrite,
    'output': output,
    'reasoning': reasoning,
  };
}

/// USD per 1M tokens: input, cached input, cache write, output.
const prices = <String, List<double>>{
  'gpt-6-luna': [0.10, 0.01, 0.125, 0.50],
  'gpt-5-nano': [0.05, 0.005, 0.05, 0.40],
  'gpt-4.1-nano': [0.10, 0.025, 0.10, 0.40],
  'gpt-5.6-luna': [0.20, 0.02, 0.25, 1.20],
};

double costOf(Iterable<CallMetric> calls) {
  var usd = 0.0;
  for (final c in calls) {
    final p = prices[c.model] ?? prices['gpt-6-luna']!;
    final plain = c.input - c.cached - c.cacheWrite;
    usd += (plain * p[0] + c.cached * p[1] + c.cacheWrite * p[2] + c.output * p[3]) / 1e6;
  }
  return usd;
}

/// Posts provider-format bodies straight to OpenAI, applying what the FiNN
/// relay applies (model, reasoning effort, output cap, safety identifier),
/// and returns the relay's trimmed reply shape.
class OpenAiLiveTransport implements LlmTransport {
  OpenAiLiveTransport({
    this.model = 'gpt-6-luna',
    this.reasoningEffort = 'none',
    this.maxOutputTokens = 2048,
    this.explicitCache = true,
  });

  final String model;

  /// Like the relay's default `OPENAI_PROMPT_CACHE=explicit`: the system
  /// message is the only cache breakpoint. (The baseline ran before the
  /// relay had this, with implicit caching.)
  final bool explicitCache;

  /// `off` = not sent.
  final String reasoningEffort;
  final int maxOutputTokens;
  final List<CallMetric> calls = [];
  final List<Map<String, Object?>> bodies = [];
  final _client = http.Client();
  late final String _key = _env('OPENAI_API_KEY');

  @override
  Future<Map<String, Object?>> post(Map<String, Object?> body) async {
    final requested = body['max_completion_tokens'];
    final messages = (body['messages'] as List).cast<Map<String, Object?>>();
    final upstream = <String, Object?>{
      'model': model,
      ...body,
      if (explicitCache) ...{
        'prompt_cache_options': {'mode': 'explicit'},
        'messages': [
          for (var i = 0; i < messages.length; i++)
            i == 0 && messages[i]['role'] == 'system'
                ? {
                    'role': 'system',
                    'content': [
                      {
                        'type': 'text',
                        'text': messages[i]['content'],
                        'prompt_cache_breakpoint': {'mode': 'explicit'},
                      },
                    ],
                  }
                : messages[i],
        ],
      },
      'max_completion_tokens': requested is int && requested < maxOutputTokens ? requested : maxOutputTokens,
      'safety_identifier': 'finn-live-benchmark',
      if (reasoningEffort != 'off') 'reasoning_effort': reasoningEffort,
    };
    bodies.add(upstream);
    final started = DateTime.now();
    final res = await _client.post(
      Uri.parse('https://api.openai.com/v1/chat/completions'),
      headers: {'authorization': 'Bearer $_key', 'content-type': 'application/json'},
      body: jsonEncode(upstream),
    );
    final ms = DateTime.now().difference(started).inMilliseconds;
    if (res.statusCode != 200) {
      throw LlmException(LlmErrorKind.rejected, 'OpenAI ${res.statusCode}: ${res.body}');
    }
    final json = jsonDecode(res.body) as Map<String, Object?>;
    final usage = (json['usage'] as Map?) ?? const {};
    final inDetails = (usage['prompt_tokens_details'] as Map?) ?? const {};
    final outDetails = (usage['completion_tokens_details'] as Map?) ?? const {};
    int n(Object? v) => v is num ? v.toInt() : 0;
    calls.add(CallMetric(
      model: model,
      ms: ms,
      input: n(usage['prompt_tokens']),
      cached: n(inDetails['cached_tokens']),
      cacheWrite: n(inDetails['cache_write_tokens']),
      output: n(usage['completion_tokens']),
      reasoning: n(outDetails['reasoning_tokens']),
    ));
    final choice = (json['choices'] as List).first as Map;
    final message = choice['message'] as Map;
    return {
      'id': json['id'],
      'finish_reason': choice['finish_reason'],
      'message': {
        'content': message['content'],
        'refusal': message['refusal'],
        'tool_calls': [
          for (final c in (message['tool_calls'] as List? ?? const []))
            {
              'id': (c as Map)['id'],
              'type': 'function',
              'function': {'name': (c['function'] as Map)['name'], 'arguments': c['function']['arguments']},
            },
        ],
      },
      'usage': {
        'prompt_tokens': n(usage['prompt_tokens']),
        'completion_tokens': n(usage['completion_tokens']),
        'total_tokens': n(usage['total_tokens']),
        'cached_tokens': n(inDetails['cached_tokens']),
        'reasoning_tokens': n(outDetails['reasoning_tokens']),
      },
    };
  }
}

/// Counts what would be FiNN API requests in remote mode: one per preview
/// (`POST /actions/{id}/preview`) and one per write (`POST /actions/{id}`).
class CountingDispatcher extends OperationDispatcher {
  CountingDispatcher(this.inner) : super(environment: inner.environment);
  final OperationDispatcher inner;
  int previews = 0;
  int writes = 0;
  int completed = 0;

  @override
  Future<Result<ActionPreview>> preview<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    ActionChannel channel = ActionChannel.ui,
  }) {
    previews++;
    return inner.preview(action, input, channel: channel);
  }

  @override
  Future<ActionOutcome<O>> dispatch<I extends ActionInput, O>(
    FinancialAction<I, O> action,
    I input, {
    required String idempotencyKey,
    ActionConfirmation? confirmation,
    ActionChannel channel = ActionChannel.ui,
  }) async {
    writes++;
    final out = await inner.dispatch(
      action,
      input,
      idempotencyKey: idempotencyKey,
      confirmation: confirmation,
      channel: channel,
    );
    if (out is ActionCompleted<O>) completed++;
    return out;
  }
}

/// An executed (approved and saved) operation, for checking accuracy.
typedef SavedOp = ({String actionId, Map<String, Object?> input});

/// One expected operation: action id plus fields that must match.
class Expect {
  const Expect(this.actionId, this.fields);
  final String actionId;
  final Map<String, Object?> fields;

  bool matches(SavedOp op) {
    if (op.actionId != actionId) return false;
    for (final e in fields.entries) {
      final v = op.input[e.key];
      final want = e.value;
      if (want is Set) {
        if (!want.contains(v)) return false;
      } else if (want is RegExp) {
        if (v is! String || !want.hasMatch(v)) return false;
      } else if (want is num) {
        final got = v is num ? v : num.tryParse('$v');
        if (got == null || (got - want).abs() > 0.001) return false;
      } else if (v != want) {
        return false;
      }
    }
    return true;
  }
}

/// True when [saved] is exactly the expected multiset of operations.
bool opsMatch(List<SavedOp> saved, List<Expect> expected) {
  if (saved.length != expected.length) return false;
  final left = List.of(saved);
  for (final e in expected) {
    final i = left.indexWhere(e.matches);
    if (i < 0) return false;
    left.removeAt(i);
  }
  return true;
}

/// A benchmark scenario: one or more user turns, then the expected saved
/// operations (empty plus [expectQuestion] for clarifications).
class Scenario {
  const Scenario(this.id, this.turns, this.expected, {this.expectQuestion = false, this.answerContains});
  final String id;
  final List<String> turns;
  final List<Expect> expected;

  /// The last turn must end with a question and save nothing.
  final bool expectQuestion;

  /// For read-only questions: the reply must contain this text.
  final String? answerContains;
}

/// Representative FiNN requests over the `demo` data (today: Sat 10 Oct 2026).
final scenarios = <Scenario>[
  Scenario('three_ops', [
    'I received ₹5,000 as salary yesterday, gave ₹300 to Utsav which is still pending, and bought protein powder for ₹5,000',
  ], [
    const Expect('transactions.create', {'type': 'income', 'amount': 5000, 'categoryId': 'cat_salary', 'date': '2026-10-09'}),
    const Expect('pending.create', {'direction': 'owedToMe', 'amount': 300, 'counterparty': 'Utsav'}),
    Expect('transactions.create', {
      'type': 'expense',
      'amount': 5000,
      'categoryId': {'cat_health', 'cat_fitness', 'cat_shopping'},
      'date': '2026-10-10',
    }),
  ]),
  Scenario('single_expense', ['spent 450 on lunch'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 450, 'categoryId': 'cat_food', 'date': '2026-10-10'}),
  ]),
  Scenario('same_op_x3', ['bought vegetables for 70 and milk for 150 today, and filled petrol for 400 yesterday'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 70, 'categoryId': 'cat_groceries', 'date': '2026-10-10'}),
    const Expect('transactions.create', {'type': 'expense', 'amount': 150, 'categoryId': 'cat_groceries', 'date': '2026-10-10'}),
    const Expect('transactions.create', {'type': 'expense', 'amount': 400, 'categoryId': 'cat_transport', 'date': '2026-10-09'}),
  ]),
  Scenario('settle_lookup', ['Neha paid me back the 850 for the office lunch'], [
    const Expect('pending.settle', {'pendingId': 'pend_seed_297', 'amount': 850}),
  ]),
  Scenario('mixed_settle_expense', ['spent 250 on an auto and Karan paid back the 1200 for the team dinner'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 250, 'categoryId': 'cat_transport'}),
    const Expect('pending.settle', {'pendingId': 'pend_seed_305', 'amount': 1200}),
  ]),
  Scenario('ambiguous_person', ['I paid Rahul back'], const [], expectQuestion: true),
  Scenario('missing_amount', ['I bought groceries today'], const [], expectQuestion: true),
  Scenario('dependent_category', ['create a category called Pets and add 500 for dog food in it'], [
    const Expect('categories.create', {'name': 'Pets', 'type': 'expense'}),
    Expect('transactions.create', {'type': 'expense', 'amount': 500, 'categoryId': RegExp(r'.+')}),
  ]),
  Scenario('goal_contribution', ['add 2000 to my Japan trip goal'], [
    const Expect('goals.contribute', {'goalId': 'goal_seed_japan', 'amount': 2000}),
  ]),
  Scenario('relative_date', ['paid the 1200 electricity bill the day before yesterday'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 1200, 'categoryId': 'cat_utilities', 'date': '2026-10-08'}),
  ]),
  Scenario('income_party', ['got a 15k freelance payment from Acme'], [
    Expect('transactions.create', {'type': 'income', 'amount': 15000, 'categoryId': 'cat_freelance', 'counterparty': RegExp('Acme')}),
  ]),
  Scenario('question_spend', ['how much have I spent on food this month?'], const [], answerContains: '₹'),
  Scenario('follow_up_edit', ['spent 450 on lunch', 'actually make that 400'], [
    const Expect('transactions.create', {'type': 'expense', 'amount': 450, 'categoryId': 'cat_food'}),
    const Expect('transactions.update', {'amount': 400, 'categoryId': 'cat_food'}),
  ]),
];

/// Writes [report] next to the benchmark docs.
void writeReport(String name, Map<String, Object?> report) {
  final dir = Directory('docs/agent-benchmarks')..createSync(recursive: true);
  File('${dir.path}/$name.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
}
