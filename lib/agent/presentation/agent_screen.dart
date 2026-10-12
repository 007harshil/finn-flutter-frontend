import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/core_providers.dart';
import '../../design_system/design_system.dart';
import '../application/agent_controller.dart';
import '../application/agent_mode.dart';
import '../application/agent_providers.dart';
import '../voice/voice_input_controller.dart';
import 'widgets/agent_logo.dart';
import 'widgets/change_review.dart';
import 'widgets/chat_entries.dart';
import 'widgets/voice_composer.dart';

/// Full-screen assistant (route `AppRoutes.assistant`, e.g. deep links).
/// The main entry point is agent mode from the navigation bar
/// ([AgentModePanel]); both host the same [AgentConsole].
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final state = ref.watch(agentControllerProvider);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Row(mainAxisSize: MainAxisSize.min, children: [
          FinnAgentMark(size: 26),
          SizedBox(width: Space.x2),
          Text('FiNN Agent'),
        ]),
        actions: [
          if (state.entries.isNotEmpty)
            FinnIconButton(
              icon: LucideIcons.squarePen,
              tooltip: 'New chat',
              onPressed: state.busy ? null : () => confirmAgentStartOver(context, ref),
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: const SafeArea(top: false, child: AgentConsole()),
    );
  }
}

/// The agent panel shown over the app while agent mode is on.
class AgentModePanel extends ConsumerWidget {
  const AgentModePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.text;
    final state = ref.watch(agentControllerProvider);
    return Material(
      color: c.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(Radii.xxxl),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.xxxl),
          border: Border.all(color: c.agentMid.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x4, Space.x3, Space.x2, Space.x2),
              child: Row(
                children: [
                  const FinnAgentMark(size: 34),
                  const SizedBox(width: Space.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('FiNN Agent', style: t.sectionTitle),
                        Row(children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(color: c.positive, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: Space.x1_5),
                          Flexible(
                            child: Text(
                              'Agent mode on · the app is paused',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: t.caption.copyWith(color: c.textSecondary),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  if (state.entries.isNotEmpty)
                    FinnIconButton(
                      icon: LucideIcons.squarePen,
                      tooltip: 'New chat',
                      onPressed: state.busy ? null : () => confirmAgentStartOver(context, ref),
                    ),
                  FinnIconButton(
                    icon: LucideIcons.x,
                    tooltip: 'Close agent mode',
                    onPressed: () => ref.read(agentModeProvider.notifier).close(),
                  ),
                ],
              ),
            ),
            FinnDivider(),
            const Expanded(child: AgentConsole()),
          ],
        ),
      ),
    );
  }
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

/// Conversation, review panel and composer (text + voice). Talks only to
/// [agentControllerProvider] and [voiceInputProvider].
class AgentConsole extends ConsumerStatefulWidget {
  const AgentConsole({super.key});

  @override
  ConsumerState<AgentConsole> createState() => _AgentConsoleState();
}

class _AgentConsoleState extends ConsumerState<AgentConsole> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();

  static const _examples = [
    'Spent ₹450 on lunch today via UPI',
    'Rahul paid me back 2,000',
    'How much did I spend on food this month?',
  ];

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final value = (text ?? _input.text).trim();
    final state = ref.read(agentControllerProvider);
    if (value.isEmpty || state.busy) return;
    if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.lightImpact();
    _input.clear();
    ref.read(agentControllerProvider.notifier).send(value);
    _scrollToEnd();
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

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      final duration = context.motion.normal;
      // Reduced motion uses zero durations, which animateTo rejects.
      if (duration == Duration.zero) {
        _scroll.jumpTo(end);
      } else {
        _scroll.animateTo(end, duration: duration, curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(agentControllerProvider);
    final controller = ref.read(agentControllerProvider.notifier);
    final voiceAvailable = ref.watch(voiceInputProvider.select((s) => s.available));
    ref.listen(agentControllerProvider.select((s) => (s.entries.length, s.status)), (_, _) => _scrollToEnd());
    ref.listen<VoiceTranscript?>(voiceInputProvider.select((s) => s.transcript), _onTranscript);
    ref.listen(voiceInputProvider.select((s) => s.error), (previous, next) {
      if (next != null && next.seq != previous?.seq) FinnToast.error(context, next.text);
    });

    if (!state.available) {
      return const EmptyState(
        icon: LucideIcons.cloudOff,
        title: 'Assistant unavailable',
        message: 'The assistant works when FiNN is connected to your account online. '
            'Your records are still available everywhere else in the app.',
      );
    }

    return ResponsiveCenter(
      child: Column(
        children: [
          Expanded(
            child: state.entries.isEmpty && !state.busy
                ? _Intro(examples: _examples, voice: voiceAvailable, onPick: _send)
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x3, Space.gutter, Space.x4),
                    children: [
                      for (final e in state.entries) ...[
                        switch (e) {
                          UserChatEntry() => UserBubble(key: ValueKey(e.id), entry: e),
                          AgentChatEntry() => AgentBubble(
                              key: ValueKey(e.id),
                              entry: e,
                              onRetry: e.retryText != null && !state.busy && e == state.entries.last
                                  ? () => _send(e.retryText)
                                  : null,
                            ),
                        },
                        const SizedBox(height: Space.x3),
                      ],
                      if (state.plan != null && state.status != AgentStatus.idle) ...[
                        AgentPlanBubble(text: state.plan!),
                        const SizedBox(height: Space.x3),
                      ],
                      if (state.status == AgentStatus.awaitingApproval && state.proposals.isNotEmpty)
                        ChangeReviewPanel(
                          proposals: state.proposals,
                          onApprove: controller.approve,
                          onDecline: controller.decline,
                        )
                      else if (state.busy)
                        AgentProgress(label: state.progress ?? 'Thinking…'),
                    ],
                  ),
          ),
          VoiceComposer(
            controller: _input,
            focusNode: _focus,
            busy: state.busy,
            onSend: _send,
            onStop: controller.stop,
          ),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.voice, required this.onPick});
  final List<String> examples;
  final bool voice;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.x4),
        const Center(child: AgentOrb(size: 72, active: true)),
        const SizedBox(height: Space.x4),
        Text('Tell FiNN what happened', style: t.title, textAlign: TextAlign.center),
        const SizedBox(height: Space.x2),
        Text(
          '${voice ? 'Speak or type. ' : ''}Record expenses, settle what people owe, pay EMIs or add to goals '
          'in one message. You review every change before it is saved.',
          style: t.body.copyWith(color: c.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.x5),
        for (final e in examples) ...[
          FinnCard(
            variant: FinnCardVariant.muted,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            onTap: () => onPick(e),
            semanticLabel: 'Try: $e',
            child: Row(children: [
              Expanded(child: Text(e, style: t.body)),
              Icon(LucideIcons.arrowUpRight, size: 16, color: c.textTertiary),
            ]),
          ),
          const SizedBox(height: Space.x2),
        ],
      ],
    );
  }
}
