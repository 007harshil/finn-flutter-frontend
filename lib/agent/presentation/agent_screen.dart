import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/core_providers.dart';
import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../design_system/design_system.dart' show FinnToast, showFinnConfirm;
import '../../ui/ui.dart';
import '../application/agent_controller.dart';
import '../application/agent_mode.dart';
import '../application/agent_providers.dart';
import '../orchestration/agent_runner.dart';
import '../voice/voice_input_controller.dart';
import 'widgets/action_deck_view.dart';
import 'widgets/agent_logo.dart';
import 'widgets/agent_progress.dart';
import 'widgets/history_sheet.dart';

/// Full-screen assistant (route `AppRoutes.assistant`, e.g. deep links).
/// The main entry point is agent mode from the navigation bar
/// ([AgentModePanel]); both host the same [AgentExperience].
class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UiColors.of(context).page,
      body: AgentExperience(
        opaque: true,
        statusLine: 'Your finance agent',
        closeTooltip: 'Close',
        onClose: () => context.canPop() ? context.pop() : context.go(AppRoutes.home),
      ),
    );
  }
}

/// Agent mode over the app: the app stays visible, blurred and paused,
/// behind the agent. Closing it resumes the app.
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

/// The agent: a quiet page with the FiNN orb to speak, a few examples to
/// start from, the conversation as a plain transcript with a review panel
/// for every proposed change, and one composer for text and voice.
///
/// Talks only to [agentControllerProvider] and [voiceInputProvider].
class AgentExperience extends ConsumerStatefulWidget {
  const AgentExperience({
    super.key,
    required this.onClose,
    required this.statusLine,
    required this.closeTooltip,
    this.opaque = false,
  });

  final VoidCallback onClose;
  final String statusLine;
  final String closeTooltip;

  /// Solid background (full-screen route) instead of a veil over the app.
  final bool opaque;

  @override
  ConsumerState<AgentExperience> createState() => _AgentExperienceState();
}

class _AgentExperienceState extends ConsumerState<AgentExperience> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  /// Entries already on screen when the experience opened: only newer
  /// replies get the reveal animation.
  late final Set<String> _seen = {for (final e in ref.read(agentControllerProvider).entries) e.id};

  static const _examples = [
    (LucideIcons.utensils, 'Spent ₹450 on lunch today via UPI'),
    (LucideIcons.handCoins, 'Rahul paid me back 2,000'),
    (LucideIcons.chartPie, 'What did I spend on food this month?'),
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
      final duration = UiMotion.of(context).enter;
      // Reduced motion uses zero durations, which animateTo rejects.
      if (duration == Duration.zero) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: duration, curve: UiMotion.ease);
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

    final c = UiColors.of(context);
    final conversation = state.entries.isNotEmpty || state.busy;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      color: widget.opaque ? c.page : c.page.withValues(alpha: 0.94),
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: SafeArea(
          child: UiColumnWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TopBar(
                  statusLine: widget.statusLine,
                  closeTooltip: widget.closeTooltip,
                  onClose: widget.onClose,
                  onNewChat: state.entries.isEmpty || state.busy ? null : () => confirmAgentStartOver(context, ref),
                  onHistory: state.available ? () => showAgentHistory(context) : null,
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: UiMotion.of(context).normal,
                    child: !state.available
                        ? const _Unavailable()
                        : conversation
                        ? _Transcript(
                            key: const ValueKey('transcript'),
                            state: state,
                            seen: _seen,
                            controller: _scroll,
                            onRetry: _send,
                            onOpen: _openRecord,
                          )
                        : _Welcome(
                            key: const ValueKey('welcome'),
                            examples: _examples,
                            voice: voice,
                            compact: keyboard > 0,
                            onOrbTap: _onOrbTap,
                            onPick: _send,
                          ),
                  ),
                ),
                if (state.available)
                  _Composer(
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
    );
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

/// FiNN mark, name and where the agent runs; history, new chat and close.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.statusLine,
    required this.closeTooltip,
    required this.onClose,
    required this.onNewChat,
    required this.onHistory,
  });

  final String statusLine;
  final String closeTooltip;
  final VoidCallback onClose;
  final VoidCallback? onNewChat;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final t = UiType.of(context);
    final history = onHistory;
    final newChat = onNewChat;
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.xs, UiSpace.gutter - UiSpace.md, 0),
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            const FinnAgentMark(size: 28),
            const SizedBox(width: UiSpace.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(header: true, child: Text('FiNN Agent', style: t.section)),
                  Text(statusLine, style: t.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (history != null) UiIconButton(icon: LucideIcons.history, tooltip: 'History', size: 20, onPressed: history),
            if (newChat != null)
              UiIconButton(
                key: const ValueKey('new-chat'),
                icon: LucideIcons.squarePen,
                tooltip: 'New chat',
                size: 20,
                onPressed: newChat,
              ),
            UiIconButton(icon: LucideIcons.x, tooltip: closeTooltip, onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Welcome
// ---------------------------------------------------------------------------

/// Before the first message: the orb (tap to speak), one line of what FiNN
/// does, and three examples that send themselves.
class _Welcome extends ConsumerWidget {
  const _Welcome({
    super.key,
    required this.examples,
    required this.voice,
    required this.compact,
    required this.onOrbTap,
    required this.onPick,
  });

  final List<(IconData, String)> examples;
  final VoiceInputState voice;

  /// The keyboard is up: a smaller orb keeps the examples in view.
  final bool compact;
  final VoidCallback onOrbTap;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = UiType.of(context);
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final first = name == null || name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
    final listening = voice.phase == VoicePhase.listening;
    final caption = switch (voice.phase) {
      VoicePhase.listening =>
        'Listening  ${voice.elapsed.inSeconds ~/ 60}:${(voice.elapsed.inSeconds % 60).toString().padLeft(2, '0')}',
      VoicePhase.transcribing => 'Turning your voice into text…',
      VoicePhase.idle => voice.available ? 'Tap the orb and speak, or type below' : 'Type what happened below',
    };
    final orbLabel = !voice.available ? 'FiNN Agent' : (listening ? 'Done speaking' : 'Speak to FiNN');
    final level = voice.levels.isEmpty ? 0.0 : voice.levels.last.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: UiSpace.gutter),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: UiSpace.lg),
              Center(
                child: Semantics(
                  button: true,
                  label: orbLabel,
                  excludeSemantics: true,
                  child: GestureDetector(
                    onTap: onOrbTap,
                    child: AnimatedScale(
                      scale: listening ? 1 + level * 0.12 : 1,
                      duration: UiMotion.of(context).quick,
                      child: AgentOrb(size: compact ? 56 : 80, listening: listening, active: listening),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: UiSpace.xl),
              UiReveal(
                index: 0,
                child: Column(
                  children: [
                    Text(
                      first == null ? 'Hi there' : 'Hi $first',
                      style: t.label,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: UiSpace.xs),
                    Semantics(
                      header: true,
                      child: Text('Tell FiNN what happened', style: t.title, textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: UiSpace.xs),
                    Semantics(
                      liveRegion: true,
                      child: Text(caption, style: t.label, textAlign: TextAlign.center),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: UiSpace.section),
              UiReveal(
                index: 1,
                child: UiPanelList(
                  ruleIndent: 60,
                  children: [
                    for (final (icon, text) in examples)
                      UiListRow(
                        leading: UiMark(icon: icon, size: 32),
                        title: text,
                        semanticLabel: 'Try: $text',
                        chevron: false,
                        trailing: Icon(LucideIcons.arrowUpRight, size: 16, color: UiColors.of(context).inkFaint),
                        onTap: () => onPick(text),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: UiSpace.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SingleChildScrollView(
        child: UiEmpty(
          icon: LucideIcons.cloudOff,
          title: 'Assistant unavailable',
          message: 'FiNN Agent works when the app is connected to your account online.',
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript
// ---------------------------------------------------------------------------

class _Transcript extends ConsumerWidget {
  const _Transcript({
    super.key,
    required this.state,
    required this.seen,
    required this.controller,
    required this.onRetry,
    required this.onOpen,
  });

  final AgentViewState state;
  final Set<String> seen;
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
      AgentStatus.thinking when progress == AgentRunner.waitingLabel => progress,
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
      padding: const EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.lg, UiSpace.gutter, UiSpace.lg),
      children: [
        for (final e in state.entries)
          ...switch (e) {
            UserChatEntry() => <Widget>[
              _UserLine(key: ValueKey(e.id), text: e.text),
              const SizedBox(height: UiSpace.lg),
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
                const SizedBox(height: UiSpace.lg),
              ],
            ],
            // With a deck, the reply only adds what the cards do not say.
            AgentChatEntry(:final turn) when state.decks.containsKey(turn) && e.message.trim().isEmpty => const <Widget>[],
            AgentChatEntry(:final turn) => <Widget>[
              _AgentReply(
                key: ValueKey(e.id),
                entry: e,
                text: state.decks.containsKey(turn) ? e.message : e.text,
                reveal: seen.add(e.id),
                onRetry: e.retryText != null && !state.busy && e == state.entries.last
                    ? () => onRetry(e.retryText!)
                    : null,
              ),
              const SizedBox(height: UiSpace.lg),
            ],
          },
        if (state.plan != null && state.status != AgentStatus.idle) UiNotice(icon: LucideIcons.route, text: state.plan!),
        if (work != null) AgentWorkingLine(label: work),
      ],
    );
  }
}

/// The user's words, right-aligned on a soft fill.
class _UserLine extends StatelessWidget {
  const _UserLine({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: LayoutBuilder(
        builder: (context, box) => ConstrainedBox(
          constraints: BoxConstraints(maxWidth: math.min(box.maxWidth * 0.82, 420)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(18)),
            child: SelectableText(text, style: t.body.copyWith(fontWeight: FontWeight.w400)),
          ),
        ),
      ),
    );
  }
}

/// FiNN's words as plain text beside its mark, with how the turn ended
/// when it did not complete, and Try again for a failed turn.
class _AgentReply extends StatelessWidget {
  const _AgentReply({super.key, required this.entry, required this.text, required this.reveal, this.onRetry});

  final AgentChatEntry entry;
  final String text;
  final bool reveal;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final (IconData, String, Color)? badge = switch (entry.end) {
      AgentTurnEnd.failed => (LucideIcons.circleAlert, 'Could not finish', c.negative),
      AgentTurnEnd.cancelled => (LucideIcons.circleStop, 'Stopped', c.inkSoft),
      AgentTurnEnd.limitReached => (LucideIcons.circlePause, 'Paused', c.warning),
      AgentTurnEnd.completed => null,
    };
    final retry = onRetry;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.only(top: 1), child: FinnAgentMark(size: 22)),
        const SizedBox(width: UiSpace.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badge case (final icon, final label, final color)) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 4),
                    Text(label, style: t.small.copyWith(color: color, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: UiSpace.xs),
              ],
              _RevealText(
                text: text,
                animate: reveal,
                style: t.body.copyWith(fontWeight: FontWeight.w400, height: 1.45),
              ),
              if (retry != null) ...[
                const SizedBox(height: UiSpace.xs),
                UiChipButton(label: 'Try again', trailingIcon: LucideIcons.rotateCcw, onTap: retry),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Reveals a reply left to right once (about 28 ms a character); the rest
/// keeps its space so nothing jumps. Old replies and reduced motion show
/// the whole text at once.
class _RevealText extends StatefulWidget {
  const _RevealText({required this.text, required this.animate, required this.style});

  final String text;
  final bool animate;
  final TextStyle style;

  @override
  State<_RevealText> createState() => _RevealTextState();
}

class _RevealTextState extends State<_RevealText> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, value: widget.animate ? 0 : 1);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value < 1) {
      if (UiMotion.of(context).reduced) {
        _c.value = 1;
      } else if (!_c.isAnimating) {
        _c.duration = Duration(milliseconds: (widget.text.length * 28).clamp(300, 1600));
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.value >= 1) return SelectableText(widget.text, style: widget.style);
        final shown = (widget.text.length * Curves.easeOut.transform(_c.value)).round();
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: widget.text.substring(0, shown)),
              TextSpan(
                text: widget.text.substring(shown),
                style: const TextStyle(color: Colors.transparent),
              ),
            ],
          ),
          style: widget.style,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Composer
// ---------------------------------------------------------------------------

/// One rounded field for typing, with the mic (or send, or stop) at its
/// end; while listening it becomes a level meter with cancel and done.
class _Composer extends StatelessWidget {
  const _Composer({
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
    final c = UiColors.of(context);
    final t = UiType.of(context);
    final Widget content = switch (voice.phase) {
      VoicePhase.listening => Row(
        key: const ValueKey('listening'),
        children: [
          UiIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: 'Listening. Tap done when you finish speaking.',
              child: CustomPaint(
                size: const Size.fromHeight(32),
                painter: _LevelsPainter(levels: voice.levels, color: c.ink),
              ),
            ),
          ),
          _SendButton(icon: LucideIcons.check, tooltip: 'Done speaking', onPressed: onFinishVoice),
        ],
      ),
      VoicePhase.transcribing => Row(
        key: const ValueKey('transcribing'),
        children: [
          UiIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          const SizedBox(width: UiSpace.xs),
          const AgentSpinner(),
          const SizedBox(width: UiSpace.md),
          Expanded(
            child: Semantics(liveRegion: true, child: Text('Turning your voice into text…', style: t.label)),
          ),
        ],
      ),
      VoicePhase.idle => Row(
        key: const ValueKey('compose'),
        children: [
          const SizedBox(width: UiSpace.lg),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
                cursorColor: c.ink,
                style: t.body.copyWith(fontWeight: FontWeight.w400),
                decoration: InputDecoration(
                  isCollapsed: true,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  counterText: '',
                  hintText: busy ? 'Working on it…' : 'Ask or tell FiNN…',
                  hintStyle: t.body.copyWith(color: c.inkSoft, fontWeight: FontWeight.w400),
                ),
              ),
            ),
          ),
          if (busy)
            UiIconButton(icon: LucideIcons.square, tooltip: 'Stop', size: 18, onPressed: onStop)
          else
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final speak = voice.available && value.text.trim().isEmpty;
                return speak
                    ? UiIconButton(key: const ValueKey('speak'), icon: LucideIcons.mic, tooltip: 'Speak', onPressed: onSpeak)
                    : _SendButton(key: const ValueKey('send'), icon: LucideIcons.arrowUp, tooltip: 'Send', onPressed: onSend);
              },
            ),
          const SizedBox(width: UiSpace.xs),
        ],
      ),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(UiSpace.gutter, UiSpace.sm, UiSpace.gutter, UiSpace.md),
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.hairline),
        ),
        child: AnimatedSwitcher(duration: UiMotion.of(context).quick, child: content),
      ),
    );
  }
}

/// Ink circle with a page-coloured icon: the composer's main action.
class _SendButton extends StatelessWidget {
  const _SendButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = UiColors.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onPressed,
          radius: 22,
          child: SizedBox.square(
            dimension: UiSpace.touch,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: c.page),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrored bars of recent mic levels, newest in the middle.
class _LevelsPainter extends CustomPainter {
  _LevelsPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const bars = 24;
    final gap = size.width / bars;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    for (var i = 0; i < bars; i++) {
      final fromCentre = (i - (bars - 1) / 2).abs().round();
      final idx = levels.length - 1 - fromCentre;
      final v = idx >= 0 && idx < levels.length ? levels[idx].clamp(0.0, 1.0) : 0.0;
      final h = math.max(3.0, v * size.height);
      final x = gap * (i + 0.5);
      canvas.drawLine(Offset(x, mid - h / 2), Offset(x, mid + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_LevelsPainter old) => old.levels != levels || old.color != color;
}
