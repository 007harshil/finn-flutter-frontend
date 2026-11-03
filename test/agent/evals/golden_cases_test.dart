// Offline checks of the golden eval set: it is well formed, names only real
// actions, pages and reply kinds, keeps its mix of cases, and every case
// the app must answer without the model passes with no model call. The
// model-graded run is test/agent/live/golden_eval_test.dart.

import 'package:finn/actions/action_registry.dart';
import 'package:finn/agent/answers/app_pages.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/app/di/action_catalog.dart';
import 'package:finn/data/local/local_data_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../actions/action_harness.dart';
import '../agent_fakes.dart';
import 'golden.dart';

void main() {
  final set = GoldenSet.load();

  test('the set is well formed', () {
    final ids = set.cases.map((c) => c.id).toList();
    expect(ids.toSet(), hasLength(ids.length), reason: 'unique ids');
    expect(set.thresholds.keys.toSet(), goldenKinds);
    final actions = {for (final d in ActionRegistry(allActions).descriptors) d.id};
    final routes = {for (final p in agentPages.values) p.route};
    for (final c in set.cases) {
      expect(goldenKinds, contains(c.kind), reason: c.id);
      expect(c.turns, isNotEmpty, reason: c.id);
      expect(c.expect, isNotEmpty, reason: c.id);
      for (final o in [...?c.ops, ...?c.opsAnyOf?.expand((l) => l)]) {
        expect(actions.containsAll(o.actions), isTrue, reason: '${c.id}: ${o.actions}');
      }
      for (final r in c.replies) {
        expect(replyText(r), isNotNull, reason: '${c.id}: reply kind $r');
      }
      if (c.expect['navigate'] case final String route) {
        expect(routes.contains(route) || routes.any((r) => route.startsWith('$r/')), isTrue, reason: '${c.id}: $route');
      }
    }
  });

  test('the mix follows the eval plan (about 60 / 30 / 10)', () {
    int count(String kind) => set.cases.where((c) => c.kind == kind).length;
    final n = set.cases.length;
    expect(n, greaterThanOrEqualTo(60));
    expect(count('normal') / n, inInclusiveRange(0.45, 0.65));
    expect((count('edge') + count('hinglish')) / n, inInclusiveRange(0.2, 0.4));
    expect(count('adversarial') / n, greaterThanOrEqualTo(0.1));
  });

  for (final c in set.cases.where((c) => c.local)) {
    test('local case ${c.id} passes without the model', () async {
      final r = AgentRig(await ActionHarness.create(scenario: DataScenario.demo), ScriptedProvider(const []));
      final saved = <({String actionId, Map<String, Object?> input})>[];
      AgentTurnResult? last;
      for (final t in c.turns) {
        last = await r.turn(t);
        for (final a in last.actions) {
          if (a.succeeded) saved.add((actionId: a.proposal.descriptor.id, input: a.proposal.input.toJson()));
        }
      }
      expect(grade(c, GoldenRun(saved, last!, r.provider.requests.length)), isNull);
    });
  }
}
