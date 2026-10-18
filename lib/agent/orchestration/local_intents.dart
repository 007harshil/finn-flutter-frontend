import '../plan/agent_guard.dart';
import '../plan/agent_plan.dart';
import '../plan/resolvers.dart';
import 'agent_memory.dart';

/// Requests the app answers without a model call. Matching is deliberately
/// narrow (high precision): anything that could also be a new instruction
/// goes to the model.
sealed class LocalIntent {
  const LocalIntent();
}

/// "What did I ask you to do yesterday?", "show my agent history".
final class HistoryIntent extends LocalIntent {
  const HistoryIntent(this.period);
  final String? period;
}

/// A request outside FiNN's scope (code, app internals, secrets, attempts
/// to override the agent's rules): refused without a model call.
final class OutOfScopeIntent extends LocalIntent {
  const OutOfScopeIntent();
}

/// "What's my balance?"
final class BalanceIntent extends LocalIntent {
  const BalanceIntent();
}

/// The reply completes the open clarification: [ops] are the unfinished ops
/// with the answer filled in.
final class ClarificationAnswer extends LocalIntent {
  const ClarificationAnswer(this.ops);
  final List<PlanOp> ops;
}

abstract final class LocalIntents {
  static final _history = [
    RegExp(r'\b(agent|assistant|chat)\s+history\b'),
    // Bare "show my history" only: "show my spending history" is a data question.
    RegExp(r'^(show|open|see|view)( me)?( my)? history\??$'),
    RegExp(r"\bwhat (did|have) i (ask|asked|tell|told) you\b"),
    RegExp(r"\bwhat (did|have) you (do|done|record|recorded|save|saved|change|changed)\b"),
    RegExp(r'\b(show|list)\b.*\b(previous|past|recent|earlier|last)\b.*\b(requests|commands)\b'),
  ];

  static final _balance = RegExp(
    r"^(what'?s|what is|whats|show|tell me|check)?\s*(me\s+)?(my\s+)?(current\s+|available\s+|total\s+)?(balance|available balance|money left|cash in hand)\s*(now|today|please)?\s*\??$|^how much (money )?(do i have|have i got|is left)( left)?( now| today)?\s*\??$",
  );

  static String? _period(String t) {
    if (t.contains('yesterday')) return 'yesterday';
    if (t.contains('today')) return 'today';
    if (t.contains('week')) return 'week';
    if (t.contains('month')) return 'month';
    return null;
  }

  static LocalIntent? match(String text, AgentMemory memory) {
    if (AgentGuard.isOutOfScope(text)) return const OutOfScopeIntent();
    final t = text.trim().toLowerCase();
    final pending = memory.pending;
    if (pending != null) {
      final answer = _answer(t, pending);
      if (answer != null) return answer;
    }
    // Questions only: a message with an amount is treated as a new request.
    final hasNumber = RegExp(r'\d').hasMatch(t);
    if (!hasNumber && _history.any((r) => r.hasMatch(t))) return HistoryIntent(_period(t));
    if (!hasNumber && _balance.hasMatch(t)) return const BalanceIntent();
    return null;
  }

  static const _ordinals = {'first': 1, '1st': 1, 'second': 2, '2nd': 2, 'third': 3, '3rd': 3, 'fourth': 4, '4th': 4};

  /// Completes [p] from a short reply: an option chosen by number, amount
  /// or words, or a bare amount for a missing amount. Null when the reply is
  /// anything else (it then goes to the model with the open question).
  static ClarificationAnswer? _answer(String t, PendingClarification p) {
    final op = p.ops.where((o) => o.ref == p.opRef).firstOrNull;
    if (op == null || p.field == null) return null;
    if (t.split(RegExp(r'\s+')).length > 8) return null;
    String? value;
    if (p.options.isNotEmpty) {
      final digits = RegExp(r'^\D*(\d+)\D*$').firstMatch(t);
      final n = digits != null && t.length <= 12 ? int.tryParse(digits.group(1)!) : null;
      final ordinal = _ordinals.entries.where((e) => RegExp('\\b${e.key}\\b').hasMatch(t)).firstOrNull?.value;
      final index = ordinal ?? (n != null && n >= 1 && n <= p.options.length ? n : null);
      if (index != null) {
        value = p.options[index - 1].value;
      } else if (t.contains('last') && !t.contains('last week') && !t.contains('last month')) {
        value = p.options.last.value;
      } else {
        final amount = AgentAmount.only(t);
        final byAmount = amount == null ? const <ClarifyOption>[] : [for (final o in p.options) if (o.amount == amount) o];
        if (byAmount.length == 1) {
          value = byAmount.single.value;
        } else {
          final m = matchByName(t, p.options, (o) => [o.label, ...o.aliases]);
          if (m is Matched<ClarifyOption>) value = m.value.value;
        }
      }
    } else if (p.field == 'amount') {
      final amount = AgentAmount.only(t);
      if (amount != null) value = amount.toDecimalString();
    }
    if (value == null) return null;
    return ClarificationAnswer([
      for (final o in p.ops)
        if (o.ref == op.ref || p.alsoRefs.contains(o.ref)) o.copyWith(args: {...o.args, p.field!: value}) else o,
    ]);
  }
}
