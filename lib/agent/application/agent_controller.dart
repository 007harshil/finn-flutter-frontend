import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/action.dart';
import '../../app/di/action_providers.dart';
import '../../core/ids/id_generator.dart';
import '../../features/auth/application/auth_controller.dart';
import '../execution/proposals.dart';
import '../execution/tool_executor.dart';
import '../llm/llm_provider.dart';
import '../orchestration/agent_events.dart';
import '../orchestration/agent_runner.dart';
import '../orchestration/conversation.dart';
import '../tools/agent_tool.dart';
import '../tools/tool_groups.dart';
import 'agent_providers.dart';

enum AgentStatus { idle, thinking, awaitingApproval, executing }

/// One entry of the visible chat.
@immutable
sealed class ChatEntry {
  const ChatEntry(this.id);
  final String id;
}

final class UserChatEntry extends ChatEntry {
  const UserChatEntry(super.id, this.text);
  final String text;
}

final class AgentChatEntry extends ChatEntry {
  const AgentChatEntry(super.id, {required this.text, required this.end, this.actions = const [], this.retryText});
  final String text;
  final AgentTurnEnd end;

  /// Confirmed outcomes of every action proposed in this turn.
  final List<ActionRecord> actions;

  /// Set when the turn failed before anything was changed and can be resent.
  final String? retryText;
}

@immutable
class AgentViewState {
  const AgentViewState({
    this.available = true,
    this.entries = const [],
    this.status = AgentStatus.idle,
    this.progress,
    this.proposals = const [],
    this.plan,
  });

  /// False when no model provider is configured (local mode).
  final bool available;
  final List<ChatEntry> entries;
  final AgentStatus status;

  /// What the agent is doing right now, e.g. "Looking up your records".
  final String? progress;

  /// Actions waiting for approval (only while [status] is awaitingApproval).
  final List<ProposedAction> proposals;

  /// What the assistant said about its plan, shown above the review card.
  final String? plan;

  bool get busy => status != AgentStatus.idle;

  AgentViewState copyWith({
    List<ChatEntry>? entries,
    AgentStatus? status,
    String? Function()? progress,
    List<ProposedAction>? proposals,
    String? Function()? plan,
  }) =>
      AgentViewState(
        available: available,
        entries: entries ?? this.entries,
        status: status ?? this.status,
        progress: progress == null ? this.progress : progress(),
        proposals: proposals ?? this.proposals,
        plan: plan == null ? this.plan : plan(),
      );
}

/// The small, stable interface the UI uses: [send], [approve], [decline],
/// [stop], [startOver]. Conversation state lives for the app session (it is
/// in memory only and cleared on sign-out); pending approvals are never
/// persisted, so an interrupted session can never execute anything.
class AgentController extends Notifier<AgentViewState> {
  AgentRunner? _runner;
  CancellationToken? _cancel;
  Completer<Set<String>>? _approval;
  int _seq = 0;

  /// Bumped whenever the conversation is reset, so a turn that finishes
  /// afterwards cannot write into the new session's state.
  int _generation = 0;

  @override
  AgentViewState build() {
    final provider = ref.watch(llmProviderProvider);
    // A different (or no) signed-in user starts a fresh conversation.
    ref.watch(authControllerProvider.select((s) => s?.email));
    ref.onDispose(_abort);
    _generation++;
    _runner = null;
    return AgentViewState(available: provider != null);
  }

  AgentRunner _runnerFor(LlmProvider provider) => _runner ??= () {
        final env = ref.read(actionEnvironmentProvider);
        final config = ref.read(agentConfigProvider);
        final toolbox = ref.read(agentToolboxProvider);
        final conversationId = RandomIdGenerator().next('c');
        final selection = ToolSelection();
        return AgentRunner(
          selection: selection,
          provider: provider,
          toolbox: toolbox,
          loadSnapshot: env.loadSnapshot,
          conversation: Conversation(id: conversationId),
          config: config,
          executor: ToolExecutor(
            toolbox: toolbox,
            dispatcher: ref.read(actionDispatcherProvider),
            context: ToolContext(loadSnapshot: env.loadSnapshot, selection: selection),
            sessionId: conversationId,
            channel: ActionChannel.agent,
            maxCallsPerStep: config.maxToolCallsPerStep,
          ),
        );
      }();

  /// Sends a request. Ignored while a turn is running (no duplicate
  /// submissions).
  Future<void> send(String text) async {
    final provider = ref.read(llmProviderProvider);
    final trimmed = text.trim();
    if (provider == null || state.busy || trimmed.isEmpty) return;

    final generation = _generation;
    final token = _cancel = CancellationToken();
    state = state.copyWith(
      entries: [...state.entries, UserChatEntry('u${_seq++}', trimmed)],
      status: AgentStatus.thinking,
      progress: () => null,
    );

    AgentTurnResult result;
    try {
      result = await _runnerFor(provider).runTurn(
        trimmed,
        approve: (p) => generation == _generation ? _requestApproval(p) : Future.value(const <String>{}),
        onEvent: (e) {
          if (generation == _generation) _onEvent(e);
        },
        cancel: token,
      );
    } catch (e, st) {
      debugPrint('Agent turn crashed: $e\n$st');
      result = const AgentTurnResult(end: AgentTurnEnd.failed, reply: 'Something went wrong. Please try again.');
    }
    if (!ref.mounted || generation != _generation) return;
    _approval = null;
    _cancel = null;
    final canRetry = result.end == AgentTurnEnd.failed && result.actions.isEmpty && (result.error?.retryable ?? true);
    state = state.copyWith(
      entries: [
        ...state.entries,
        AgentChatEntry('a${_seq++}',
            text: result.reply, end: result.end, actions: result.actions, retryText: canRetry ? trimmed : null),
      ],
      status: AgentStatus.idle,
      progress: () => null,
      proposals: const [],
      plan: () => null,
    );
  }

  /// Approves the proposals with [ids]; the others are declined.
  void approve(Set<String> ids) {
    final c = _approval;
    if (c == null || c.isCompleted) return;
    _approval = null;
    state = state.copyWith(status: AgentStatus.executing, proposals: const [], progress: () => 'Saving');
    c.complete(ids);
  }

  /// Declines every pending proposal.
  void decline() => approve(const {});

  /// Stops the current turn. Approved actions already sent still finish
  /// and are reported truthfully.
  void stop() {
    _cancel?.cancel();
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(const {});
    _approval = null;
  }

  /// Clears the conversation (only when idle).
  void startOver() {
    if (state.busy) return;
    _generation++;
    _runner = null;
    state = AgentViewState(available: state.available);
  }

  Future<Set<String>> _requestApproval(List<ProposedAction> proposals) {
    final c = _approval = Completer<Set<String>>();
    state = state.copyWith(status: AgentStatus.awaitingApproval, proposals: proposals, progress: () => null);
    return c.future;
  }

  void _onEvent(AgentEvent e) {
    if (!ref.mounted) return;
    switch (e) {
      case AgentThinking():
        state = state.copyWith(status: AgentStatus.thinking, progress: () => null);
      case AgentToolStarted(:final label) || AgentWaiting(:final label):
        state = state.copyWith(progress: () => label);
      case AgentPlanReady(:final text):
        state = state.copyWith(plan: () => text);
      case AgentExecuting():
        state = state.copyWith(status: AgentStatus.executing, progress: () => 'Saving');
      case AgentAwaitingApproval() || AgentActionsSettled():
        break; // handled by _requestApproval / the final result
    }
  }

  void _abort() {
    _cancel?.cancel();
    final c = _approval;
    if (c != null && !c.isCompleted) c.complete(const {});
  }
}
