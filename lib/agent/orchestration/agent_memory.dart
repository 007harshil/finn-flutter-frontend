import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/money/money.dart';
import '../plan/agent_plan.dart';

/// A change saved in this conversation, so follow-ups such as "make that
/// 400" or "undo that" can name it (`#1` = the newest).
@immutable
class RecentOp {
  const RecentOp({required this.actionId, required this.summary, this.recordId});
  final String actionId;
  final String summary;
  final String? recordId;
}

/// One choice offered in a clarification question ("which Rahul item?").
@immutable
class ClarifyOption {
  const ClarifyOption({required this.label, required this.value, this.amount});

  /// Shown to the user, e.g. "Concert tickets (₹2,000)".
  final String label;

  /// Filled into the op when chosen (e.g. the pending item's id).
  final String value;
  final Money? amount;
}

/// A question the agent asked, with the unfinished ops it belongs to. The
/// user's answer completes them: locally when it is a bare amount or picks
/// an option, otherwise with one model call that sees this context.
@immutable
class PendingClarification {
  const PendingClarification({
    required this.question,
    required this.originalText,
    required this.ops,
    this.opRef,
    this.field,
    this.options = const [],
  });

  final String question;
  final String originalText;

  /// The unfinished ops (as the model planned them).
  final List<PlanOp> ops;

  /// The op the question is about and the field the answer fills, when the
  /// question is about one field of one op.
  final String? opRef;
  final String? field;
  final List<ClarifyOption> options;
}

/// The agent's bounded conversational context. It is not a transcript:
/// only the last few saved changes (by reference) and an open question are
/// kept, and only they are sent to the model. Agent history (what was done
/// in earlier sessions) is separate and never sent.
class AgentMemory {
  static const maxRecent = 5;

  final List<RecentOp> _recent = [];
  PendingClarification? pending;

  /// Newest first.
  List<RecentOp> get recent => List.unmodifiable(_recent);

  void remember(Iterable<RecentOp> ops) {
    _recent.insertAll(0, ops.toList().reversed);
    if (_recent.length > maxRecent) _recent.removeRange(maxRecent, _recent.length);
  }

  /// The recent change [target] refers to: `#2`, `2`, `last` or `that`.
  RecentOp? resolve(Object? target) {
    if (_recent.isEmpty) return null;
    final t = target?.toString().trim().toLowerCase() ?? '';
    if (t.isEmpty || t == 'last' || t == 'that' || t == 'it') return _recent.first;
    final n = int.tryParse(t.startsWith('#') ? t.substring(1) : t);
    if (n == null || n < 1 || n > _recent.length) return null;
    return _recent[n - 1];
  }

  void clear() {
    _recent.clear();
    pending = null;
  }

  static String _clip(String s, int max) => s.length <= max ? s : '${s.substring(0, max - 1)}…';

  /// Follow-up context for the model, or null when there is none. The open
  /// question is left out when [withPending] is false (a redo of one change).
  String? contextText({bool withPending = true}) {
    final lines = <String>[
      if (_recent.isNotEmpty)
        'Recent (already saved; refer by #n): ${[for (var i = 0; i < _recent.length; i++) '#${i + 1} ${_clip(_recent[i].summary, 80)}'].join(' | ')}',
      if (pending case final p? when withPending) ...[
        'Pending question you asked: "${_clip(p.question, 200)}"',
        'Unfinished ops: ${_clip(jsonEncode([for (final o in p.ops) o.toJson()]), 600)}',
        'Original message: "${_clip(p.originalText, 300)}"',
      ],
    ];
    return lines.isEmpty ? null : lines.join('\n');
  }
}
