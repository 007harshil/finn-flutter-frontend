import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/core_providers.dart';
import '../../app/di/data_providers.dart';
import '../../app/router/routes.dart';
import '../../design_system/design_system.dart';
import '../application/agent_controller.dart';
import '../application/agent_mode.dart';
import '../application/agent_providers.dart';
import '../orchestration/agent_runner.dart';
import '../voice/voice_input_controller.dart';
import 'widgets/agent_logo.dart';
import 'widgets/agent_visualizer.dart';
import 'widgets/change_review.dart';
import 'widgets/history_sheet.dart';
import 'widgets/outcome_summary.dart';

/// Full-screen assistant (route `AppRoutes.assistant`, e.g. deep links).
/// The main entry point is agent mode from the navigation bar
/// ([AgentModePanel]); both host the same [AgentExperience].
class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AgentLight.midnight,
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
/// behind the immersive agent experience. Closing it resumes the app.
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

/// The immersive agent: a cinematic midnight stage with a living visualizer
/// that listens, thinks and acts, a conversation told as a transcript (not
/// chat bubbles), the review panel for proposed changes and a glass command
/// dock for voice and text. Always rendered in the dark palette.
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

  static final _darkTheme = FinnTheme.dark();

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

  /// Tapping the visualizer: speak when idle, finish when listening.
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
      final duration = context.motion.slow;
      // Reduced motion uses zero durations, which animateTo rejects.
      if (duration == Duration.zero) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: duration, curve: Curves2.emphasized);
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

    // Always the dark palette: the stage is a midnight scene.
    return Theme(
      data: _darkTheme,
      child: Builder(builder: (context) => _build(context, state, voice)),
    );
  }

  Widget _build(BuildContext context, AgentViewState state, VoiceInputState voice) {
    final presence = _presenceOf(state.status, voice.phase);
    final conversation = state.entries.isNotEmpty || state.busy;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: AgentAtmosphere(presence: presence, opaque: widget.opaque),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: Space.maxContentWidth),
                  child: Column(
                    children: [
                      _TopBar(
                        presence: presence,
                        statusLine: widget.statusLine,
                        closeTooltip: widget.closeTooltip,
                        onClose: widget.onClose,
                        onNewChat: state.entries.isEmpty ? null : () => confirmAgentStartOver(context, ref),
                        newChatEnabled: !state.busy,
                        onHistory: state.available ? () => showAgentHistory(context) : null,
                      ),
                      Expanded(
                        child: _Stage(
                          presence: presence,
                          conversation: conversation,
                          compactForKeyboard: keyboard > 0,
                          level: voice.levels.isEmpty ? 0 : voice.levels.last,
                          pulse: state.entries.whereType<AgentChatEntry>().length,
                          caption: _caption(state, voice, conversation),
                          onOrbTap: state.available ? _onOrbTap : null,
                          orbLabel: !voice.available
                              ? 'FiNN Agent'
                              : voice.phase == VoicePhase.listening
                              ? 'Done speaking'
                              : 'Speak to FiNN',
                          body: !state.available
                              ? const _Unavailable()
                              : conversation
                              ? _Transcript(
                                  state: state,
                                  seen: _seen,
                                  controller: _scroll,
                                  onRetry: _send,
                                  onOpen: _openRecord,
                                )
                              : _Welcome(examples: _examples, voice: voice.available, onPick: _send),
                        ),
                      ),
                      if (state.available)
                        _CommandDock(
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
        ],
      ),
    );
  }

  String _caption(AgentViewState state, VoiceInputState voice, bool conversation) {
    if (!state.available) return 'Offline';
    switch (voice.phase) {
      case VoicePhase.listening:
        final s = voice.elapsed.inSeconds;
        return 'Listening  ${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
      case VoicePhase.transcribing:
        return 'Catching every word…';
      case VoicePhase.idle:
        break;
    }
    return switch (state.status) {
      AgentStatus.thinking => state.progress ?? 'Thinking…',
      AgentStatus.awaitingApproval => 'Waiting for your approval',
      AgentStatus.executing => state.progress ?? 'Taking action…',
      AgentStatus.idle when conversation => 'Anything else?',
      AgentStatus.idle => voice.available ? 'Tap the orb and speak, or type below' : 'Type what happened below',
    };
  }
}

// ---------------------------------------------------------------------------
// Chrome
// ---------------------------------------------------------------------------

Color _presenceColor(AgentPresence p) => switch (p) {
  AgentPresence.idle => AgentLight.mint,
  AgentPresence.listening => AgentLight.cyan,
  AgentPresence.transcribing || AgentPresence.thinking => AgentLight.violet,
  AgentPresence.reviewing => Palette.amber400,
  AgentPresence.executing => AgentLight.mint,
};

/// Translucent glass surface used across the experience.
BoxDecoration _glass({double radius = Radii.xxl, double fill = 0.06, double edge = 0.10}) => BoxDecoration(
  color: Colors.white.withValues(alpha: fill),
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: Colors.white.withValues(alpha: edge)),
);

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.presence,
    required this.statusLine,
    required this.closeTooltip,
    required this.onClose,
    required this.onNewChat,
    required this.newChatEnabled,
    required this.onHistory,
  });

  final AgentPresence presence;
  final String statusLine;
  final String closeTooltip;
  final VoidCallback onClose;
  final VoidCallback? onNewChat;
  final bool newChatEnabled;

  /// Opens the agent history (null when the agent is unavailable).
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final dot = _presenceColor(presence);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.x3, 0),
      child: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x4, Space.x2),
              decoration: _glass(radius: Radii.full),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: context.motion.normal,
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: dot.withValues(alpha: 0.8), blurRadius: 8)],
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'FiNN Agent',
                          style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          statusLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.micro.copyWith(color: Colors.white.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (onHistory != null) ...[
            _GlassIconButton(icon: LucideIcons.history, tooltip: 'History', onPressed: onHistory),
            const SizedBox(width: Space.x2),
          ],
          AnimatedSwitcher(
            duration: context.motion.fast,
            child: onNewChat == null
                ? const SizedBox.shrink()
                : _GlassIconButton(
                    key: const ValueKey('new-chat'),
                    icon: LucideIcons.squarePen,
                    tooltip: 'New chat',
                    onPressed: newChatEnabled ? onNewChat : null,
                  ),
          ),
          const SizedBox(width: Space.x2),
          _GlassIconButton(icon: LucideIcons.x, tooltip: closeTooltip, onPressed: onClose),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onPressed,
          enabled: enabled,
          scale: 0.9,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: _glass(radius: Radii.full, fill: 0.08, edge: 0.12),
                child: Icon(icon, size: 18, color: Colors.white.withValues(alpha: enabled ? 0.9 : 0.35)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stage
// ---------------------------------------------------------------------------

/// Visualizer, live caption and the content below it. Before a conversation
/// the visualizer is a fixed hero above the welcome; once it starts, the
/// visualizer and caption become the first item of the transcript
/// ([_StageHeader]) so they scroll away with older messages instead of
/// holding a fixed band of the screen.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.presence,
    required this.conversation,
    required this.compactForKeyboard,
    required this.level,
    required this.pulse,
    required this.caption,
    required this.onOrbTap,
    required this.orbLabel,
    required this.body,
  });

  final AgentPresence presence;
  final bool conversation;
  final bool compactForKeyboard;
  final double level;
  final int pulse;
  final String caption;
  final VoidCallback? onOrbTap;
  final String orbLabel;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final motion = context.motion;
    return LayoutBuilder(
      builder: (context, box) {
        final hero = [280.0, box.maxWidth * 0.7, box.maxHeight * 0.4].reduce((a, b) => a < b ? a : b);
        final small = [136.0, box.maxHeight * 0.24].reduce((a, b) => a < b ? a : b);
        final header = _StageHeader(
          size: small,
          presence: presence,
          level: level,
          pulse: pulse,
          caption: caption,
          onOrbTap: onOrbTap,
          orbLabel: orbLabel,
        );
        return Column(
          children: [
            if (!conversation) ...[
              TweenAnimationBuilder<double>(
                tween: Tween(end: compactForKeyboard ? 0 : box.maxHeight * 0.04),
                duration: motion.slow,
                curve: Curves2.emphasized,
                builder: (context, gap, _) => SizedBox(height: gap),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(end: compactForKeyboard ? small : hero),
                duration: motion.slow,
                curve: Curves2.emphasized,
                builder: (context, size, _) => AgentVisualizer(
                  size: size,
                  presence: presence,
                  level: level,
                  pulse: pulse,
                  onTap: onOrbTap,
                  semanticLabel: orbLabel,
                ),
              ),
              _Caption(text: caption, presence: presence),
              const SizedBox(height: Space.x2),
            ],
            Expanded(
              child: AnimatedSwitcher(
                duration: motion.slow,
                switchInCurve: Curves2.emphasized,
                switchOutCurve: Curves2.standard,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a),
                    child: child,
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(conversation),
                  child: _StageHeaderScope(header: header, child: body),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Compact visualizer and live caption, shown at the top of the transcript.
class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.size,
    required this.presence,
    required this.level,
    required this.pulse,
    required this.caption,
    required this.onOrbTap,
    required this.orbLabel,
  });

  final double size;
  final AgentPresence presence;
  final double level;
  final int pulse;
  final String caption;
  final VoidCallback? onOrbTap;
  final String orbLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: AgentVisualizer(
            size: size,
            presence: presence,
            level: level,
            pulse: pulse,
            onTap: onOrbTap,
            semanticLabel: orbLabel,
          ),
        ),
        _Caption(text: caption, presence: presence),
      ],
    );
  }
}

/// Hands the stage header down to the transcript, which lists it first.
class _StageHeaderScope extends InheritedWidget {
  const _StageHeaderScope({required this.header, required super.child});

  final Widget header;

  static Widget? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_StageHeaderScope>()?.header;

  @override
  bool updateShouldNotify(_StageHeaderScope old) => true;
}

class _Caption extends StatelessWidget {
  const _Caption({required this.text, required this.presence});
  final String text;
  final AgentPresence presence;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    final active = presence != AgentPresence.idle;
    return Semantics(
      liveRegion: true,
      child: SizedBox(
        height: 22,
        child: AnimatedSwitcher(
          duration: context.motion.fast,
          child: Padding(
            key: ValueKey(text),
            padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
            child: active
                ? ShaderMask(
                    blendMode: BlendMode.srcIn,
                    shaderCallback: (r) =>
                        const LinearGradient(colors: [AgentLight.cyan, AgentLight.violet]).createShader(r),
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.label.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  )
                : Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.label.copyWith(color: Colors.white.withValues(alpha: 0.55)),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends ConsumerWidget {
  const _Welcome({required this.examples, required this.voice, required this.onPick});

  final List<(IconData, String)> examples;
  final bool voice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.text;
    final name = ref.watch(profileStreamProvider.select((v) => v.value?.displayName.trim()));
    final first = name == null || name.isEmpty ? null : name.split(RegExp(r'\s+')).first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x4),
      children: [
        StaggeredEntrance(
          index: 0,
          child: Text(
            first == null ? 'Hi there,' : 'Hi $first,',
            textAlign: TextAlign.center,
            style: t.pageTitle.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
          ),
        ),
        StaggeredEntrance(
          index: 1,
          child: ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (r) =>
                const LinearGradient(colors: [AgentLight.cyan, AgentLight.sky, AgentLight.violet]).createShader(r),
            child: Text(
              'Tell FiNN what happened',
              textAlign: TextAlign.center,
              style: t.pageTitle.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: Space.x2),
        StaggeredEntrance(
          index: 2,
          child: Text(
            'I record spending, settle what people owe, pay EMIs and move money to goals '
            '— in one go. You approve every change before it is saved.',
            textAlign: TextAlign.center,
            style: t.body.copyWith(color: Colors.white.withValues(alpha: 0.62), height: 1.45),
          ),
        ),
        const SizedBox(height: Space.x5),
        StaggeredEntrance(
          index: 3,
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: Space.x2,
            runSpacing: Space.x2,
            children: [
              for (final (icon, text) in examples) _Suggestion(icon: icon, text: text, onTap: () => onPick(text)),
            ],
          ),
        ),
        const SizedBox(height: Space.x5),
        StaggeredEntrance(
          index: 4,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(LucideIcons.shieldCheck, size: 13, color: AgentLight.mint.withValues(alpha: 0.8)),
              const SizedBox(width: Space.x1_5),
              Flexible(
                child: Text(
                  'Nothing is saved without your approval',
                  style: t.micro.copyWith(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.icon, required this.text, required this.onTap});

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      onTap: onTap,
      semanticLabel: 'Try: $text',
      scale: 0.95,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2_5),
        decoration: _glass(radius: Radii.full, fill: 0.07, edge: 0.12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AgentLight.cyan),
            const SizedBox(width: Space.x2),
            Flexible(
              child: Text(
                text,
                style: context.text.caption.copyWith(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        Container(
          padding: const EdgeInsets.all(Space.x5),
          decoration: _glass(),
          child: Column(
            children: [
              Icon(LucideIcons.cloudOff, size: 28, color: Colors.white.withValues(alpha: 0.7)),
              const SizedBox(height: Space.x3),
              Text('Assistant unavailable', style: t.title.copyWith(color: Colors.white)),
              const SizedBox(height: Space.x2),
              Text(
                'The assistant works when FiNN is connected to your account online. '
                'Your records are still available everywhere else in the app.',
                textAlign: TextAlign.center,
                style: t.body.copyWith(color: Colors.white.withValues(alpha: 0.62)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Transcript
// ---------------------------------------------------------------------------

class _Transcript extends ConsumerWidget {
  const _Transcript({
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(agentControllerProvider.notifier);
    final header = _StageHeaderScope.of(context);
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      // Older lines dissolve into the stage at the top.
      shaderCallback: (r) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.black, Colors.black],
        stops: [0, 0.06, 1],
      ).createShader(r),
      child: ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.x4),
        children: [
          if (header != null) ...[header, const SizedBox(height: Space.x4)],
          for (final e in state.entries) ...[
            switch (e) {
              UserChatEntry() => _UserLine(key: ValueKey(e.id), text: e.text),
              AgentChatEntry() => _AgentCard(
                key: ValueKey(e.id),
                entry: e,
                reveal: seen.add(e.id),
                onOpen: onOpen,
                onRetry: e.retryText != null && !state.busy && e == state.entries.last
                    ? () => onRetry(e.retryText!)
                    : null,
              ),
            },
            const SizedBox(height: Space.x4),
          ],
          if (state.plan != null && state.status != AgentStatus.idle) ...[
            _GlassNote(eyebrow: 'Plan', text: state.plan!),
            const SizedBox(height: Space.x3),
          ],
          if (state.status == AgentStatus.awaitingApproval && state.proposals.isNotEmpty)
            ChangeReviewPanel(proposals: state.proposals, onApprove: notifier.approve, onDecline: notifier.decline),
        ],
      ),
    );
  }
}

/// The user's words, set as a spoken line rather than a bubble.
class _UserLine extends StatelessWidget {
  const _UserLine({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return StaggeredEntrance(
      child: Padding(
        padding: const EdgeInsets.only(left: Space.x8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('YOU', style: t.eyebrow.copyWith(color: Colors.white.withValues(alpha: 0.4))),
            const SizedBox(height: Space.x1),
            SelectableText(
              text,
              textAlign: TextAlign.right,
              style: t.title.copyWith(
                color: Colors.white.withValues(alpha: 0.92),
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The agent's answer: a luminous glass card with what it did.
class _AgentCard extends StatelessWidget {
  const _AgentCard({super.key, required this.entry, required this.reveal, required this.onOpen, this.onRetry});

  final AgentChatEntry entry;
  final bool reveal;
  final ValueChanged<String> onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final (String? badge, Color badgeColor) = switch (entry.end) {
      AgentTurnEnd.failed => ('Could not finish', c.negative),
      AgentTurnEnd.cancelled => ('Stopped', Colors.white.withValues(alpha: 0.55)),
      AgentTurnEnd.limitReached => ('Paused', c.warning),
      AgentTurnEnd.completed => (null, Colors.transparent),
    };
    return StaggeredEntrance(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xxl),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AgentLight.cyan.withValues(alpha: 0.38),
              AgentLight.violet.withValues(alpha: 0.12),
              AgentLight.violet.withValues(alpha: 0.30),
            ],
          ),
          boxShadow: [
            BoxShadow(color: AgentLight.indigo.withValues(alpha: 0.18), blurRadius: 28, offset: const Offset(0, 10)),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(1),
          padding: const EdgeInsets.all(Space.x4),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1330).withValues(alpha: 0.86),
            borderRadius: BorderRadius.circular(Radii.xxl - 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const FinnAgentMark(size: 20),
                  const SizedBox(width: Space.x2),
                  Text(
                    'FiNN',
                    style: t.label.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (badge != null)
                    Row(
                      children: [
                        Icon(
                          entry.end == AgentTurnEnd.failed ? LucideIcons.circleAlert : LucideIcons.circlePause,
                          size: 14,
                          color: badgeColor,
                        ),
                        const SizedBox(width: Space.x1),
                        Text(
                          badge,
                          style: t.micro.copyWith(color: badgeColor, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: Space.x2),
              _RevealText(
                text: entry.text,
                animate: reveal,
                style: t.body.copyWith(color: Colors.white.withValues(alpha: 0.92), height: 1.5),
              ),
              if (entry.actions.isNotEmpty) ...[
                const SizedBox(height: Space.x3),
                OutcomeSummary(actions: entry.actions, onOpen: onOpen),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: Space.x3),
                FinnButton(
                  label: 'Try again',
                  icon: LucideIcons.rotateCcw,
                  size: FinnButtonSize.sm,
                  variant: FinnButtonVariant.outline,
                  onPressed: onRetry,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassNote extends StatelessWidget {
  const _GlassNote({required this.eyebrow, required this.text});
  final String eyebrow;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.text;
    return StaggeredEntrance(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.x4),
        decoration: _glass(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(LucideIcons.route, size: 14, color: AgentLight.cyan),
                const SizedBox(width: Space.x1_5),
                Text(eyebrow.toUpperCase(), style: t.eyebrow.copyWith(color: AgentLight.cyan)),
              ],
            ),
            const SizedBox(height: Space.x2),
            SelectableText(text, style: t.body.copyWith(color: Colors.white.withValues(alpha: 0.9), height: 1.5)),
          ],
        ),
      ),
    );
  }
}

/// Reveals a fresh reply word by word, like it is being spoken. Older
/// replies and reduced motion show the full text at once.
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
      if (context.reduceMotion) {
        _c.value = 1;
      } else if (!_c.isAnimating) {
        // About 28 ms per character, capped so long answers never drag.
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
              // The rest keeps its space so the card never jumps in size.
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
// Command dock
// ---------------------------------------------------------------------------

/// Glass capsule for text and voice. It morphs into a live voice ribbon
/// while listening and a progress line while transcribing.
class _CommandDock extends StatelessWidget {
  const _CommandDock({
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
    final t = context.text;
    final listening = voice.phase == VoicePhase.listening;

    final Widget content = switch (voice.phase) {
      VoicePhase.listening => Row(
        key: const ValueKey('listening'),
        children: [
          _DockButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Semantics(
              liveRegion: true,
              label: 'Listening. Tap done when you finish speaking.',
              child: CustomPaint(
                size: const Size.fromHeight(40),
                painter: _VoiceRibbonPainter(levels: voice.levels),
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          _DockButton(icon: LucideIcons.check, tooltip: 'Done speaking', onPressed: onFinishVoice, primary: true),
        ],
      ),
      VoicePhase.transcribing => Row(
        key: const ValueKey('transcribing'),
        children: [
          _DockButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancelVoice),
          const SizedBox(width: Space.x3),
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AgentLight.cyan),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                'Turning your voice into text…',
                style: t.body.copyWith(color: Colors.white.withValues(alpha: 0.7)),
              ),
            ),
          ),
        ],
      ),
      VoicePhase.idle => Row(
        key: const ValueKey('compose'),
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: Space.x2),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.x3),
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
                cursorColor: AgentLight.cyan,
                style: t.body.copyWith(color: Colors.white),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  counterText: '',
                  hintText: busy ? 'Working on it…' : 'Ask or tell FiNN…',
                  hintStyle: t.body.copyWith(color: Colors.white.withValues(alpha: 0.42)),
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          if (busy)
            _DockButton(icon: LucideIcons.square, tooltip: 'Stop', onPressed: onStop)
          else
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final speak = voice.available && value.text.trim().isEmpty;
                return AnimatedSwitcher(
                  duration: context.motion.fast,
                  transitionBuilder: (child, a) => ScaleTransition(
                    scale: a,
                    child: FadeTransition(opacity: a, child: child),
                  ),
                  child: speak
                      ? _DockButton(
                          key: const ValueKey('speak'),
                          icon: LucideIcons.mic,
                          tooltip: 'Speak',
                          onPressed: onSpeak,
                          primary: true,
                        )
                      : _DockButton(
                          key: const ValueKey('send'),
                          icon: LucideIcons.arrowUp,
                          tooltip: 'Send',
                          onPressed: onSend,
                          primary: true,
                        ),
                );
              },
            ),
        ],
      ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.gutter, Space.x3),
      child: AnimatedContainer(
        duration: context.motion.normal,
        curve: Curves2.standard,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xxxl),
          gradient: LinearGradient(
            colors: [
              AgentLight.cyan.withValues(alpha: listening ? 0.85 : 0.45),
              AgentLight.indigo.withValues(alpha: listening ? 0.6 : 0.25),
              AgentLight.violet.withValues(alpha: listening ? 0.85 : 0.45),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: (listening ? AgentLight.cyan : AgentLight.indigo).withValues(alpha: listening ? 0.35 : 0.18),
              blurRadius: listening ? 32 : 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(1.2),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: const EdgeInsets.fromLTRB(Space.x2, Space.x1_5, Space.x1_5, Space.x1_5),
          decoration: BoxDecoration(
            color: const Color(0xFF070E26).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(Radii.xxxl - 1.2),
          ),
          child: AnimatedSwitcher(duration: context.motion.fast, child: content),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onPressed,
          scale: 0.88,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: primary
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [AgentLight.cyan, AgentLight.indigo, AgentLight.violet],
                        ),
                        boxShadow: [BoxShadow(color: AgentLight.cyan.withValues(alpha: 0.35), blurRadius: 14)],
                      )
                    : BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                      ),
                child: Icon(icon, size: 20, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mirrored, glowing voice ribbon from recent input levels, newest at the
/// centre so speech appears to flow out from both sides.
class _VoiceRibbonPainter extends CustomPainter {
  const _VoiceRibbonPainter({required this.levels});

  final List<double> levels;

  static const _half = 16;

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.width / 2;
    final gap = mid / _half;
    final barWidth = (gap * 0.5).clamp(2.0, 4.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _half; i++) {
      final li = levels.length - 1 - i;
      final level = li >= 0 ? levels[li].clamp(0.0, 1.0) : 0.0;
      final h = 3 + (size.height - 3) * level * (1 - i / (_half * 1.6));
      final color = Color.lerp(AgentLight.cyan, AgentLight.violet, i / _half)!;
      paint
        ..strokeWidth = barWidth
        ..color = color.withValues(alpha: 0.95 - i / (_half * 1.4));
      for (final x in [mid - gap * (i + 0.5), mid + gap * (i + 0.5)]) {
        canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_VoiceRibbonPainter old) => old.levels != levels;
}
