import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'agent_guard.dart';

/// The model's structured reply: every operation it found in the message,
/// plus an optional clarification question or a plain reply.
///
/// Wire format (one JSON object, see `agentInstructions`):
/// ```json
/// {"ops":[{"op":"income","amount":5000,"category":"Salary","date":-1},
///         {"op":"pending","dir":"collect","person":"Utsav","amount":300}],
///  "ask":"...", "reply":"..."}
/// ```
/// Each op has a type (`op`), its own fields, and optionally an `id`
/// (`o1`, `o2`…) that later ops reference as `"@o1"` (e.g. a new category's
/// id). Ops are referenced inside the plan by [PlanOp.ref], which is the id
/// when given and `o<position>` otherwise, so every op has a stable ref.
@immutable
class AgentPlan {
  const AgentPlan({this.ops = const [], this.ask, this.reply});

  final List<PlanOp> ops;

  /// A clarification question for details the model could not resolve.
  final String? ask;

  /// Plain text when no op fits (greeting, advice, unsupported request).
  final String? reply;

  bool get isEmpty => ops.isEmpty && ask == null && reply == null;
}

@immutable
class PlanOp {
  const PlanOp({required this.ref, required this.type, required this.args});

  /// Stable reference within the plan (`o1`, `o2`…).
  final String ref;

  /// Op type, e.g. `expense` (see `opCatalog`).
  final String type;

  /// The op's fields as the model sent them, minus `op` and `id`. Untrusted.
  final Map<String, Object?> args;

  PlanOp copyWith({Map<String, Object?>? args}) => PlanOp(ref: ref, type: type, args: args ?? this.args);

  Map<String, Object?> toJson() => {'op': type, 'id': ref, ...args};
}

/// The model's reply could not be used as a plan.
class PlanFormatException implements Exception {
  const PlanFormatException(this.reason);
  final String reason;

  @override
  String toString() => 'PlanFormatException($reason)';
}

/// Parses and structurally validates the model's JSON plan.
///
/// Checked here: it is one JSON object; `ops` is a list of at most
/// [maxOps] objects with a string `op`; ids are unique `o<n>` values;
/// `@o<n>` references point to an earlier op. Unknown op types are kept so
/// the caller can report them as unsupported. Field values are validated
/// later, per op, against the real actions (`op_catalog.dart`).
abstract final class PlanParser {
  static const maxOps = 12;
  static const maxTextChars = 400;

  static AgentPlan parse(String? text) {
    if (text == null || text.trim().isEmpty) throw const PlanFormatException('empty reply');
    // Tolerate a fenced block even in JSON mode.
    final body = text.trim().replaceAll(RegExp(r'^```(?:json)?\s*|\s*```$'), '').trim();
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const PlanFormatException('not JSON');
    }
    if (decoded is! Map) throw const PlanFormatException('not a JSON object');

    final rawOps = decoded['ops'] ?? const [];
    if (rawOps is! List) throw const PlanFormatException('ops is not a list');
    if (rawOps.length > maxOps) throw const PlanFormatException('too many ops');

    final ops = <PlanOp>[];
    final seen = <String>{};
    for (var i = 0; i < rawOps.length; i++) {
      final raw = rawOps[i];
      if (raw is! Map) throw const PlanFormatException('an op is not an object');
      final type = raw['op'];
      if (type is! String || type.trim().isEmpty) throw const PlanFormatException('an op has no type');
      final id = raw['id'];
      final ref = id is String && RegExp(r'^o\d{1,2}$').hasMatch(id) ? id : 'o${i + 1}';
      if (!seen.add(ref)) throw PlanFormatException('duplicate op id $ref');
      // Keys starting with "_" are reserved for values the app fills in
      // (e.g. the record a clarification picked), never taken from the model.
      final args = <String, Object?>{
        for (final e in raw.entries)
          if (e.key != 'op' && e.key != 'id' && e.value != null && !e.key.toString().startsWith('_'))
            e.key.toString(): e.value,
      };
      for (final target in references(args)) {
        if (!seen.contains(target) || target == ref) throw PlanFormatException('$ref refers to unknown $target');
      }
      ops.add(PlanOp(ref: ref, type: type.trim(), args: args));
    }

    String? text_(Object? v) {
      if (v is! String) return null;
      final t = v.trim();
      if (t.isEmpty) return null;
      return t.length <= maxTextChars ? t : '${t.substring(0, maxTextChars - 1)}…';
    }

    final plan = AgentPlan(ops: ops, ask: text_(decoded['ask']), reply: text_(decoded['reply']));
    if (plan.isEmpty) throw const PlanFormatException('empty plan');
    // Output guardrail: a plan carrying code or secrets anywhere is dropped
    // for a refusal (nothing from it is shown or saved).
    final texts = [?plan.ask, ?plan.reply, for (final op in ops) ..._strings(op.args)];
    if (texts.any(AgentGuard.isUnsafeOutput)) return const AgentPlan(reply: AgentGuard.refusal);
    return plan;
  }

  static Iterable<String> _strings(Object? value) sync* {
    if (value is String) {
      yield value;
    } else if (value is Map) {
      for (final v in value.values) {
        yield* _strings(v);
      }
    } else if (value is List) {
      for (final v in value) {
        yield* _strings(v);
      }
    }
  }

  /// Op refs mentioned as `"@o<n>"` string values in [args] (top level).
  static Iterable<String> references(Map<String, Object?> args) sync* {
    for (final v in args.values) {
      if (v is String && RegExp(r'^@o\d{1,2}$').hasMatch(v.trim())) yield v.trim().substring(1);
    }
  }
}
