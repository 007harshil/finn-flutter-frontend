import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/core_providers.dart';
import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../kit/kit.dart';
import '../application/agent_controller.dart';
import '../application/agent_mode.dart';
import '../application/agent_providers.dart';
import '../orchestration/agent_runner.dart';
import '../voice/voice_input_controller.dart';
import 'widgets/action_deck_view.dart';
import 'widgets/agent_logo.dart';
import 'widgets/agent_visualizer.dart';
import 'widgets/agent_working.dart';
import 'widgets/history_sheet.dart';
import 'widgets/report_reply_sheet.dart';

/// Full-screen assistant (route `AppRoutes.assistant`, e.g. deep links).
/// The main entry point is agent mode from the navigation bar
/// ([AgentModePanel]); both host the same [AgentExperience].
class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ink.paper,
      body: AgentExperience(
        statusLine: 'Your finance agent',
        closeTooltip: 'Close',
        onClose: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
      ),
    );
  }
}

/// Agent mode over the app: a full paper surface above the paused app.
/// Closing it resumes the app.
class AgentModePanel extends ConsumerWidget {
  const AgentModePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => AgentExperience(
    statusLine: 'Agent mode · app paused',
    closeTooltip: 'Close agent mode',
    onClose: () => ref.read(agentModeProvider.notifier).close(),
  );
}

Future<void> confirmAgentStartOver(BuildContext context, WidgetRef ref) async {
  final ok = await showFinnConfirm(
    context,
    title: 'Start a new chat?',
    message: 'The conversation is cleared. Your records are not affected.',
    confirmLabel: 'Start over',
  );
  if (ok) ref.read(agentControllerProvider.notifier).startOver();
}

AgentPresence _presenceOf(AgentStatus status, VoicePhase voice) => switch (voice) {
  VoicePhase.listening => AgentPresence.listening,
  VoicePhase.transcribing => AgentPresence.transcribing,
  VoicePhase.idle => switch (status) {
    AgentStatus.idle => AgentPresence.idle,
    AgentStatus.thinking => AgentPresence.thinking,
    AgentStatus.awaitingApproval => AgentPresence.reviewing,
    AgentStatus.executing => AgentPresence.executing,
  },
};

/// The agent on a calm paper surface: a top bar with the live status, the
/// conversation as a transcript of user and agent turns with the review
/// deck for proposed changes, and an input bar for text and voice.
///
/// Talks only to [agentControllerProvider] and [voiceInputProvider].
class AgentExperience extends ConsumerStatefulWidget {
  const AgentExperience({super.key, required this.onClose, required this.statusLine, required this.closeTooltip});

  final VoidCallback onClose;
  final String statusLine;
  final String closeTooltip;

  @override
  ConsumerState<AgentExperience> createState() => _AgentExperienceState();
}

class _AgentExperienceState extends ConsumerState<AgentExperience> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  static const _examples = [
    (LucideIcons.utensils, 'Spent ₹450 on lunch today via UPI'),
    (LucideIcons.handCoins, 'Rahul paid me back 2,000'),
    (LucideIcons.chartPie, 'How much did I spend on food this month?'),
    (LucideIcons.shieldCheck, 'Add ₹5,000 to my emergency fund'),
  ];

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _haptics => ref.read(settingsProvider).hapticsEnabled;

  void _send([String? text]) {
    final value = (text ?? _input.text).trim();
    final state = ref.read(agentControllerProvider);
    if (value.isEmpty || state.busy) return;
    if (_haptics) HapticFeedback.lightImpact();
    _input.clear();
    _focus.unfocus();
    ref.read(agentControllerProvider.notifier).send(value);
    _scrollToEnd();
  }

  void _startVoice() {
    if (ref.read(agentControllerProvider).busy) return;
    if (_haptics) HapticFeedback.mediumImpact();
    _focus.unfocus();
    ref.read(voiceInputProvider.notifier).start();
  }

  /// Tapping the orb: speak when idle, finish when listening.
  void _onOrbTap() {
    final voice = ref.read(voiceInputProvider);
    if (!voice.available) {
      _focus.requestFocus();
      return;
    }
    switch (voice.phase) {
      case VoicePhase.idle:
        _startVoice();
      case VoicePhase.listening:
        if (_haptics) HapticFeedback.lightImpact();
        ref.read(voiceInputProvider.notifier).finish();
      case VoicePhase.transcribing:
        break;
    }
  }

  void _onTranscript(VoiceTranscript? previous, VoiceTranscript? next) {
    if (next == null || next.seq == previous?.seq) return;
    final text = next.text.trim();
    if (text.isEmpty) {
      FinnToast.info(context, "Didn't catch that", subtitle: 'Try again a little closer to the mic.');
      return;
    }
    final typed = _input.text.trim();
    if (typed.isNotEmpty || ref.read(agentControllerProvider).busy) {
      // Never send over something the user typed: add to it instead.
      _input.text = typed.isEmpty ? text : '$typed $text';
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
      return;
    }
    _send(text);
  }

  /// Leaves the agent and shows a saved record.
  void _openRecord(String route) {
    final router = GoRouter.of(context);
    if (_haptics) HapticFeedback.selectionClick();
    widget.onClose();
    router.go(route);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      final duration = context.motion.normal;
      // Reduced motion uses zero durations, which animateTo rejects.
      if (duration == Duration.zero) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: duration, curve: context.motion.standard);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final voice = ref.watch(voiceInputProvider);
    ref.listen(agentControllerProvider.select((s) => (s.entries.length, s.status)), (previous, next) {
      _scrollToEnd();
      // A fresh reply lands with a soft tap.
      if (previous != null && next.$1 > previous.$1 && next.$2 == AgentStatus.idle && _haptics) {
        HapticFeedback.selectionClick();
      }
    });
    ref.listen<VoiceTranscript?>(voiceInputProvider.select((s) => s.transcript), _onTranscript);
    ref.listen(voiceInputProvider.select((s) => s.error), (previous, next) {
      if (next != null && next.seq != previous?.seq) FinnToast.error(context, next.text);
    });

    final c = context.ink;
    final presence = _presenceOf(state.status, voice.phase);
    final conversation = state.entries.isNotEmpty || state.busy;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    final Widget body = !state.available
        ? const _Unavailable()
        : conversation
        ? _Transcript(state: state, controller: _scroll, onRetry: _send, onOpen: _openRecord)
        : _Welcome(
            examples: _examples,
            pulse: state.entries.whereType<AgentChatEntry>().length,
            onOrbTap: _onOrbTap,
            orbLabel: !voice.available
                ? 'FiNN Agent'
                : voice.phase == VoicePhase.listening
                ? 'Done speaking'
                : 'Speak to FiNN',
            onPick: _send,
          );

    return Material(
      color: c.paper,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Sp.maxWidth),
              child: Column(
                children: [
                  _TopBar(
                    status: presence == AgentPresence.idle ? widget.statusLine : _caption(state, voice),
                    closeTooltip: widget.closeTooltip,
                    onClose: widget.onClose,
                    onNewChat: state.entries.isEmpty ? null : () => confirmAgentStartOver(context, ref),
                    newChatEnabled: !state.busy,
                    onHistory: state.available ? () => showAgentHistory(context) : null,
                  ),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: context.motion.normal,
                      child: KeyedSubtree(key: ValueKey((state.available, conversation)), child: body),
                    ),
                  ),
                  if (state.available)
                    _InputBar(
                      controller: _input,
                      focusNode: _focus,
                      busy: state.busy,
                      voice: voice,
                      onSend: _send,
                      onSpeak: _startVoice,
                      onStop: ref.read(agentControllerProvider.notifier).stop,
                      onCancelVoice: ref.read(voiceInputProvider.notifier).cancel,
                      onFinishVoice: ref.read(voiceInputProvider.notifier).finish,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _caption(AgentViewState state, VoiceInputState voice) {
    switch (voice.phase) {
      case VoicePhase.listening:
        return 'Listening';
      case VoicePhase.transcribing:
        return 'Turning your voice into text';
      case VoicePhase.idle:
        break;
    }
    return switch (state.status) {
      AgentStatus.thinking => 'Working on it',
      AgentStatus.awaitingApproval => 'Waiting for your approval',
      AgentStatus.executing => 'Saving',
      AgentStatus.idle => widget.statusLine,
    };
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.closeTooltip,
    required this.onClose,
    required this.onNewChat,
    required this.newChatEnabled,
    required this.onHistory,
  });

  final String status;
  final String closeTooltip;
  final VoidCallback onClose;
  final VoidCallback? onNewChat;
  final bool newChatEnabled;

  /// Opens the agent history (null when the agent is unavailable).
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.sm, Sp.sm),
      child: Row(
        children: [
          const FinnAgentMark(size: 28),
          const SizedBox(width: Sp.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(header: true, child: Text('FiNN Agent', style: t.labelStrong)),
                Semantics(
                  liveRegion: true,
                  child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.small),
                ),
              ],
            ),
          ),
          if (onHistory != null) LedgerIconButton(icon: LucideIcons.history, tooltip: 'History', onPressed: onHistory),
          if (onNewChat != null)
            LedgerIconButton(
              key: const ValueKey('new-chat'),
              icon: LucideIcons.squarePen,
              tooltip: 'New chat',
              onPressed: newChatEnabled ? onNewChat : null,
            ),
          LedgerIconButton(icon: LucideIcons.x, tooltip: closeTooltip, onPressed: onClose),
        ],
      ),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome({
    required this.examples,
    required this.pulse,
    required this.onOrbTap,
    required this.orbLabel,
    required this.onPick,
  });

  final List<(IconData, String)> examples;
  final int pulse;
  final VoidCallback onOrbTap;
  final String orbLabel;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final first = name == null || name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.xl, Sp.gutter, Sp.xl),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: AgentVisualizer(
            size: 56,
            presence: AgentPresence.idle,
            pulse: pulse,
            onTap: onOrbTap,
            semanticLabel: orbLabel,
          ),
        ),
        const SizedBox(height: Sp.lg),
        Text(first == null ? 'Hi there,' : 'Hi $first,', style: t.heading.copyWith(color: context.ink.inkSoft)),
        const SizedBox(height: Sp.xs),
        Semantics(header: true, child: Text('Tell FiNN what happened', style: t.title)),
        const SizedBox(height: Sp.sm),
        Text(
          'I record spending, settle what people owe, pay EMIs and move money to goals in one go. '
          'You approve every change before it is saved.',
          style: t.label,
        ),
        const SizedBox(height: Sp.sm),
        Text(
          'Replies are generated by AI and can be wrong. Tap the flag on a reply to report it.',
          style: t.small.copyWith(color: context.ink.inkSoft),
        ),
        const SizedBox(height: Sp.section),
        LedgerSection(
          title: 'Try saying',
          child: LedgerPanel(
            dividerIndent: Sp.lg + 40 + Sp.md + 2,
            children: [
              for (final (icon, text) in examples)
                LedgerRow(
                  leading: IconWell(icon: icon),
                  title: text,
                  titleLines: 2,
                  semanticLabel: 'Try: $text',
                  onTap: () => onPick(text),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(Sp.gutter),
      children: const [
        LedgerEmpty(
          icon: LucideIcons.cloudOff,
          title: 'Assistant unavailable',
          message:
              'The assistant works when FiNN is connected to your account online. '
              'Your records are still available everywhere else in the app.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript
// ---------------------------------------------------------------------------

class _Transcript extends ConsumerWidget {
  const _Transcript({required this.state, required this.controller, required this.onRetry, required this.onOpen});

  final AgentViewState state;
  final ScrollController controller;
  final ValueChanged<String> onRetry;

  /// Opens a saved record's screen.
  final ValueChanged<String> onOpen;

  /// What to say at the end of the transcript while the agent works, or
  /// null while the user is up (reviewing) or a single card shows its own
  /// progress.
  static String? _work(AgentViewState state) {
    if (state.redoing != null) return null;
    final progress = state.progress;
    return switch (state.status) {
      AgentStatus.idle || AgentStatus.awaitingApproval => null,
      AgentStatus.thinking when progress == null => 'Understanding your request…',
      AgentStatus.thinking when progress == AgentRunner.waitingLabel => progress!,
      AgentStatus.thinking => '$progress…',
      AgentStatus.executing when progress == 'Wrapping up' => 'Noting what you declined…',
      AgentStatus.executing => 'Saving what you approved…',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(agentControllerProvider.notifier);
    final work = _work(state);
    // The deck the running turn works on.
    final redoing = state.redoing;
    final activeTurn = !state.busy
        ? null
        : redoing != null
        ? state.decks.values.where((d) => d.slots.any((s) => s.key == redoing)).firstOrNull?.turnId
        : state.entries.whereType<UserChatEntry>().lastOrNull?.id;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.xl, Sp.gutter, Sp.xl),
      children: [
        for (final e in state.entries)
          ...switch (e) {
            UserChatEntry() => <Widget>[
              _UserTurn(key: ValueKey(e.id), text: e.text),
              const SizedBox(height: Sp.xl),
              if (state.decks[e.id] case final deck?) ...[
                ActionDeckView(
                  key: ValueKey('deck-${e.id}'),
                  deck: deck,
                  reviewing: state.reviewing,
                  active: activeTurn == e.id,
                  executing: state.status == AgentStatus.executing,
                  busy: state.busy,
                  onDecide: notifier.decide,
                  onDecideRest: notifier.decideRest,
                  onRetry: (slot) => notifier.retry(e.id, slot),
                  onOpen: onOpen,
                ),
                const SizedBox(height: Sp.xl),
              ],
            ],
            // With a deck, the reply only adds what the cards do not say;
            // the proposals themselves can still be reported.
            AgentChatEntry(:final turn) when state.decks.containsKey(turn) && e.message.trim().isEmpty => <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: _ReportButton(onPressed: () => _report(context, state, e)),
              ),
              const SizedBox(height: Sp.md),
            ],
            AgentChatEntry(:final turn) => <Widget>[
              _AgentTurn(
                key: ValueKey(e.id),
                entry: e,
                text: state.decks.containsKey(turn) ? e.message : e.text,
                onRetry: e.retryText != null && !state.busy && e == state.entries.last
                    ? () => onRetry(e.retryText!)
                    : null,
                onReport: () => _report(context, state, e),
              ),
              const SizedBox(height: Sp.xl),
            ],
          },
        if (state.plan != null && state.status != AgentStatus.idle) ...[
          LedgerNote(text: state.plan!, icon: LucideIcons.route),
          const SizedBox(height: Sp.md),
        ],
        if (work != null) AgentWorking(label: work),
      ],
    );
  }
}

/// Opens the report sheet for [entry] with the request that produced it.
void _report(BuildContext context, AgentViewState state, AgentChatEntry entry) {
  final request = state.entries.whereType<UserChatEntry>().where((u) => u.id == entry.turn).firstOrNull?.text;
  final cards = state.decks[entry.turn]?.slots.map((s) => s.current.proposal.preview.title).join('\n');
  final reply = entry.text.trim().isNotEmpty ? entry.text : (cards ?? '');
  showReportReplySheet(context, reply: reply.isEmpty ? '(empty reply)' : reply, request: request);
}

/// Small flag button that reports an assistant reply (Play AI-generated
/// content policy: users can flag replies without leaving the app).
class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Report this reply',
      visualDensity: VisualDensity.compact,
      iconSize: 16,
      color: context.ink.inkFaint,
      onPressed: onPressed,
      icon: const Icon(LucideIcons.flag),
    );
  }
}

/// The user's words: right-aligned on a sunken block.
class _UserTurn extends StatelessWidget {
  const _UserTurn({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: FractionallySizedBox(
        widthFactor: 0.85,
        alignment: Alignment.centerRight,
        child: Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            label: 'You',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Sp.lg, vertical: Sp.md),
              decoration: BoxDecoration(color: context.ink.sunken, borderRadius: Rad.rLg),
              child: SelectableText(text, style: context.type.body),
            ),
          ),
        ),
      ),
    );
  }
}

/// The agent's answer: the mark, its name and the reply as plain text.
class _AgentTurn extends StatelessWidget {
  const _AgentTurn({super.key, required this.entry, required this.text, this.onRetry, this.onReport});

  final AgentChatEntry entry;

  /// What to say (the reply, or only what the turn's deck does not show).
  final String text;
  final VoidCallback? onRetry;
  final VoidCallback? onReport;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;
    final (String? badge, Color badgeColor) = switch (entry.end) {
      AgentTurnEnd.failed => ('Could not finish', c.red),
      AgentTurnEnd.cancelled => ('Stopped', c.inkSoft),
      AgentTurnEnd.limitReached => ('Paused', c.amber),
      AgentTurnEnd.completed => (null, c.inkSoft),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 2), child: FinnAgentMark(size: 24)),
        const SizedBox(width: Sp.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        text: 'FiNN',
                        children: [
                          if (badge != null)
                            TextSpan(
                              text: '  ·  $badge',
                              style: t.small.copyWith(color: badgeColor),
                            ),
                        ],
                      ),
                      style: t.labelStrong,
                    ),
                  ),
                  if (onReport != null) _ReportButton(onPressed: onReport!),
                ],
              ),
              const SizedBox(height: Sp.xs),
              SelectableText(text, style: t.body),
              if (onRetry != null) ...[
                const SizedBox(height: Sp.md),
                LedgerButton(
                  label: 'Try again',
                  icon: LucideIcons.rotateCcw,
                  variant: LedgerButtonVariant.secondary,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

/// Text field with mic and send. While listening it shows the live input
/// level and Done; while transcribing, a quiet progress line.
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.voice,
    required this.onSend,
    required this.onSpeak,
    required this.onStop,
    required this.onCancelVoice,
    required this.onFinishVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoiceInputState voice;
  final VoidCallback onSend;
  final VoidCallback onSpeak;
  final VoidCallback onStop;
  final VoidCallback onCancelVoice;
  final VoidCallback onFinishVoice;

  @override
  Widget build(BuildContext context) {
    final c = context.ink;
    final t = context.type;

    final Widget content = switch (voice.phase) {
      VoicePhase.listening => Row(
        key: const ValueKey('listening'),
        children: [
          LedgerIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: 'Listening. Tap done when you finish speaking.',
              excludeSemantics: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CustomPaint(
                    size: Size.fromHeight(voice.words.isEmpty ? 32 : 20),
                    painter: _LevelPainter(levels: voice.levels, color: c.ink, track: c.lineStrong),
                  ),
                  // The words heard so far, newest kept in view.
                  if (voice.words.isNotEmpty)
                    Text(
                      _tail(voice.words),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      style: t.label.copyWith(color: c.inkSoft),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Sp.sm),
          Text(_clock(voice.elapsed), style: t.figureSmall),
          const SizedBox(width: Sp.sm),
          LedgerIconButton(icon: LucideIcons.check, tooltip: 'Done speaking', selected: true, onPressed: onFinishVoice),
        ],
      ),
      VoicePhase.transcribing => Row(
        key: const ValueKey('transcribing'),
        children: [
          LedgerIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          const SizedBox(width: Sp.sm),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Turning your voice into text…', style: t.label),
                  const SizedBox(height: Sp.sm),
                  const AgentProgressLine(),
                ],
              ),
            ),
          ),
          const SizedBox(width: Sp.md),
        ],
      ),
      VoicePhase.idle => Row(
        key: const ValueKey('compose'),
        children: [
          const SizedBox(width: Sp.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.md),
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !busy,
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                cursorColor: c.ink,
                style: t.body,
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  counterText: '',
                  hintText: busy ? 'Working on it…' : 'Ask or tell FiNN',
                  hintStyle: t.body.copyWith(color: c.inkSoft),
                ),
              ),
            ),
          ),
          const SizedBox(width: Sp.xs),
          if (busy)
            LedgerIconButton(icon: LucideIcons.square, tooltip: 'Stop', onPressed: onStop)
          else ...[
            if (voice.available) LedgerIconButton(icon: LucideIcons.mic, tooltip: 'Speak', onPressed: onSpeak),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final ready = value.text.trim().isNotEmpty;
                return LedgerIconButton(
                  icon: LucideIcons.arrowUp,
                  tooltip: 'Send',
                  selected: ready,
                  // Sending empty text is a no-op; the fill shows when it is ready.
                  onPressed: onSend,
                );
              },
            ),
          ],
        ],
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.gutter, Sp.sm, Sp.gutter, Sp.md),
      child: AnimatedContainer(
        duration: context.motion.fast,
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.all(Sp.xs),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: Rad.rLg,
          border: Border.all(color: voice.phase == VoicePhase.listening ? c.ink : c.lineStrong),
        ),
        child: AnimatedSwitcher(duration: context.motion.fast, child: content),
      ),
    );
  }

  static String _tail(String words, {int max = 48}) =>
      words.length <= max ? words : '…${words.substring(words.length - max).trimLeft()}';

  static String _clock(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}

/// Recent microphone levels as thin bars, newest on the right.
class _LevelPainter extends CustomPainter {
  const _LevelPainter({required this.levels, required this.color, required this.track});

  final List<double> levels;
  final Color color;
  final Color track;

  static const _bars = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / _bars;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = (gap * 0.45).clamp(2.0, 3.0);
    final mid = size.height / 2;
    for (var i = 0; i < _bars; i++) {
      final li = levels.length - _bars + i;
      final level = li >= 0 ? levels[li].clamp(0.0, 1.0) : 0.0;
      final h = 2 + (size.height - 2) * level;
      final x = gap * (i + 0.5);
      paint.color = level > 0.02 ? color : track;
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelPainter old) => old.levels != levels || old.color != color;
}
