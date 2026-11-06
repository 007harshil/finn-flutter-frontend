// The golden eval set (golden_cases.json): loading and grading, shared by
// the offline check (golden_cases_test.dart) and the live run
// (test/agent/live/golden_eval_test.dart).

import 'dart:convert';
import 'dart:io';

import 'package:finn/agent/answers/agent_replies.dart';
import 'package:finn/agent/answers/app_guide.dart';
import 'package:finn/agent/orchestration/agent_runner.dart';
import 'package:finn/agent/plan/agent_guard.dart';

const goldenKinds = {'normal', 'edge', 'hinglish', 'adversarial'};

class GoldenOp {
  GoldenOp(this.actions, this.fields);
  final Set<String> actions;
  final Map<String, Object?> fields;

  factory GoldenOp.fromJson(Map<String, Object?> j) => GoldenOp(
    {...switch (j['action']) { final List<Object?> l => l.cast<String>(), final Object? a => [a! as String] }},
    Map<String, Object?>.from(j['fields']! as Map),
  );

  bool matches(({String actionId, Map<String, Object?> input}) op) {
    if (!actions.contains(op.actionId)) return false;
    for (final e in fields.entries) {
      final got = op.input[e.key];
      final want = e.value;
      if (want is List) {
        if (!want.contains(got)) return false;
      } else if (want is Map && want['count'] is int) {
        if (got is! List || got.length != want['count']) return false;
      } else if (want is Map && want['re'] is String) {
        if (got is! String || !RegExp(want['re']! as String).hasMatch(got)) return false;
      } else if (want is num) {
        final n = got is num ? got : num.tryParse('$got');
        if (n == null || (n - want).abs() > 0.001) return false;
      } else if (got != want) {
        return false;
      }
    }
    return true;
  }
}

class GoldenCase {
  GoldenCase(this.json)
    : id = json['id']! as String,
      kind = json['kind']! as String,
      turns = (json['turns']! as List).cast<String>(),
      expect = Map<String, Object?>.from(json['expect']! as Map);

  final Map<String, Object?> json;
  final String id;
  final String kind;
  final List<String> turns;
  final Map<String, Object?> expect;

  /// Must be answered without any model call (local intent or input guard).
  bool get local => json['local'] == true;

  List<GoldenOp>? get ops => _opsOf(expect['ops'] as List?);

  /// Acceptable alternatives (`opsAnyOf`), when more than one outcome is right.
  List<List<GoldenOp>>? get opsAnyOf => (expect['opsAnyOf'] as List?)?.map((l) => _opsOf(l as List)!).toList();

  static List<GoldenOp>? _opsOf(List? list) =>
      list?.map((o) => GoldenOp.fromJson(Map<String, Object?>.from(o as Map))).toList();
  List<String> get replies => ((expect['reply'] as List?) ?? const []).cast<String>();
  List<String> get mustNotContain => ((expect['mustNotContain'] as List?) ?? const []).cast<String>();
}

class GoldenSet {
  GoldenSet(this.cases, this.thresholds);
  final List<GoldenCase> cases;
  final Map<String, double> thresholds;

  static GoldenSet load() {
    final j = jsonDecode(File('test/agent/evals/golden_cases.json').readAsStringSync()) as Map<String, Object?>;
    return GoldenSet(
      [for (final c in j['cases']! as List) GoldenCase(Map<String, Object?>.from(c as Map))],
      {for (final e in (j['thresholds']! as Map).entries) e.key as String: (e.value as num).toDouble()},
    );
  }
}

/// The fixed text of a reply kind named in the set (`help:<topic>` for a page).
String? replyText(String kind) {
  if (kind.startsWith('help:')) return agentGuideTopics[kind.substring(5)];
  final k = AgentReplyKind.values.where((v) => v.name == kind).firstOrNull;
  return k == null ? null : AgentReplies.text(k);
}

/// Fixed answers that count as a refusal.
final refusals = {AgentGuard.refusal, AgentReplies.unclear, AgentReplies.unsupported, AgentReplies.advice};

/// What one case did: every saved op, the last turn's result and model calls.
class GoldenRun {
  GoldenRun(this.saved, this.last, this.modelCalls);
  final List<({String actionId, Map<String, Object?> input})> saved;
  final AgentTurnResult last;
  final int modelCalls;
}

/// Null when [run] meets every expectation of [c], else why not.
String? grade(GoldenCase c, GoldenRun run) {
  final reply = run.last.reply;
  final e = c.expect;
  if (c.opsAnyOf case final options?) {
    final misses = [for (final o in options) ?_opsMiss(o, run)];
    if (misses.length == options.length) return 'no acceptable outcome: ${misses.join(' | ')}';
  } else if (c.ops case final ops?) {
    if (_opsMiss(ops, run) case final miss?) return miss;
  } else if (run.saved.isNotEmpty) {
    return 'saved ${_ops(run)}, expected nothing';
  }
  if (e['question'] == true && !reply.contains('?')) return 'expected a question, got "$reply"';
  if (c.replies.isNotEmpty && !c.replies.map(replyText).contains(reply)) return 'reply "$reply" is not one of ${c.replies}';
  if (e['refuse'] == true && !refusals.contains(reply)) return 'expected a refusal, got "$reply"';
  if (e['answer'] case final String want when !reply.contains(want)) return 'answer lacks "$want": "$reply"';
  if (e['navigate'] case final String route when run.last.navigation?.route != route) {
    return 'navigated to ${run.last.navigation?.route}, expected $route';
  }
  for (final bad in c.mustNotContain) {
    if (reply.contains(bad)) return 'reply contains "$bad"';
  }
  if (c.local && run.modelCalls > 0) return 'expected no model call, made ${run.modelCalls}';
  return null;
}

/// Null when [run] saved exactly the multiset [ops], else why not.
String? _opsMiss(List<GoldenOp> ops, GoldenRun run) {
  final left = List.of(run.saved);
  if (left.length != ops.length) return 'saved ${left.length} ops, expected ${ops.length}: ${_ops(run)}';
  for (final o in ops) {
    final i = left.indexWhere(o.matches);
    if (i < 0) return 'no saved op matches ${o.actions} ${o.fields}: ${_ops(run)}';
    left.removeAt(i);
  }
  return null;
}

String _ops(GoldenRun run) => [for (final o in run.saved) '${o.actionId} ${o.input}'].join('; ');
