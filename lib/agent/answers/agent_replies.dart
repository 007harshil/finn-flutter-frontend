import '../plan/agent_guard.dart';
import 'app_guide.dart';

/// What the model may answer when no op fits. The model only picks a kind
/// (and, for [help], a page); every word the user sees is written here.
/// So an off-topic answer ("who is the president of India?", a poem, a
/// maths result) can never reach the screen, even when the model ignores its
/// instructions: there is no free text to show.
enum AgentReplyKind {
  greeting,
  thanks,

  /// How to use FiNN, optionally about one page (`topic`).
  help,

  /// Investment, tax or legal advice was asked for.
  advice,

  /// Anything outside the user's FiNN money records.
  scope,

  /// A FiNN request no op can do (deleting, editing the profile…).
  unsupported,

  /// The model wrote prose instead of a kind (an older prompt, a provider
  /// refusal or a format slip). Never shown as written.
  unclear,
}

abstract final class AgentReplies {
  static const greeting = "Hi! Tell me what you spent, received, lent or owe, and I'll record it once you approve.";
  static const thanks = "You're welcome. Anything else to record?";
  static const advice =
      "I can't give investment, tax or legal advice. I can show what your records say, like what you spent, saved or owe.";
  static const unsupported =
      "I can't do that from here. I can record expenses, income, debts, transfers, budgets, goals, loans and subscriptions, and answer questions about them.";
  static const unclear =
      "I didn't quite get that. Tell me what you spent, received, lent or owe, or ask about your budgets and goals.";

  /// The kind the model named in `reply`. Prose is never trusted: the
  /// server's refusal maps to [AgentReplyKind.scope], anything else to
  /// [AgentReplyKind.unclear].
  static AgentReplyKind kindOf(String raw) {
    final t = raw.trim().toLowerCase();
    for (final k in AgentReplyKind.values) {
      if (k != AgentReplyKind.unclear && k.name == t) return k;
    }
    if (raw.trim() == AgentGuard.refusal || t.startsWith('i can only help with your finn')) return AgentReplyKind.scope;
    return AgentReplyKind.unclear;
  }

  /// The text shown for [kind]. [topic] is a page key (see `app_pages.dart`).
  static String text(AgentReplyKind kind, {String? topic}) => switch (kind) {
    AgentReplyKind.greeting => greeting,
    AgentReplyKind.thanks => thanks,
    AgentReplyKind.help => agentGuideTopics[topic] ?? agentGuideText,
    AgentReplyKind.advice => advice,
    AgentReplyKind.scope => AgentGuard.refusal,
    AgentReplyKind.unsupported => unsupported,
    AgentReplyKind.unclear => unclear,
  };
}
