import 'package:finn/agent/orchestration/agent_trace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../actions/action_harness.dart';
import 'agent_fakes.dart';

void main() {
  test('a turn with changes records every stage in order, the user wait apart', () async {
    final r = AgentRig(
      await ActionHarness.create(),
      ScriptedProvider([
        plan([
          {'op': 'expense', 'amount': 450, 'category': 'Food', 'note': 'lunch'},
        ]),
      ]),
    );
    await r.turn('spent 450 on lunch');
    final trace = r.runner.lastTrace;

    expect(trace.laps.map((l) => l.$1), [
      'snapshot',
      'localIntents',
      'prompt',
      'model',
      'parse',
      'compile',
      'prepare',
      'preview',
      AgentTrace.approval,
      'execute',
      'reply',
    ]);
    expect(trace.facts['modelCalls'], 1);
    expect(trace.facts['previewSteps'], 1);
    expect(trace.facts['executedSteps'], 1);
    expect(trace.facts['ops'], 1);
    expect(trace.facts['instructionChars'], greaterThan(1000));
    expect(trace.untilReview, isNotNull);
    expect(trace.agentTime, lessThanOrEqualTo(trace.laps.fold<int>(0, (s, l) => s + l.$2)));
  });

  test('a local answer needs no model stage', () async {
    final r = AgentRig(await ActionHarness.create(), ScriptedProvider(const []));
    await r.turn("what's my balance?");
    final stages = r.runner.lastTrace.laps.map((l) => l.$1);
    expect(stages, ['snapshot', 'localIntents']);
    expect(r.runner.lastTrace.untilReview, isNull);
  });

  test('the log line holds stage names, durations and counts only', () {
    final t = AgentTrace()
      ..lap('model')
      ..lap(AgentTrace.approval)
      ..lap('execute')
      ..fact('inputTokens', 1700);
    final line = t.describe();
    expect(line, startsWith('agent.trace agent='));
    expect(line, contains('untilReview='));
    expect(line, contains('model='));
    expect(line, contains('execute='));
    expect(line, contains('inputTokens=1700'));
    expect(line, isNot(contains('approval=')));
  });
}
