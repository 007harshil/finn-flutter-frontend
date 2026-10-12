import '../execution/proposals.dart';

/// Progress of one agent turn, emitted while it runs (for the UI).
sealed class AgentEvent {
  const AgentEvent();
}

/// Waiting for the model.
final class AgentThinking extends AgentEvent {
  const AgentThinking();
}

/// A tool started running.
final class AgentToolStarted extends AgentEvent {
  const AgentToolStarted(this.toolName, this.label);
  final String toolName;
  final String label;
}

/// What the model said before handing its plan to the user for review.
final class AgentPlanReady extends AgentEvent {
  const AgentPlanReady(this.text);
  final String? text;
}

/// Waiting before retrying the model (rate limit or brief outage).
final class AgentWaiting extends AgentEvent {
  const AgentWaiting(this.label);
  final String label;
}

/// The user must approve or decline [proposals] before the turn continues.
final class AgentAwaitingApproval extends AgentEvent {
  const AgentAwaitingApproval(this.proposals);
  final List<ProposedAction> proposals;
}

/// Approved actions are being written.
final class AgentExecuting extends AgentEvent {
  const AgentExecuting(this.count);
  final int count;
}

/// Outcomes of actions from one approval round.
final class AgentActionsSettled extends AgentEvent {
  const AgentActionsSettled(this.records);
  final List<ActionRecord> records;
}
