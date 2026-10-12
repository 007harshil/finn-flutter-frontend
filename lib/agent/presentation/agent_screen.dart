import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/di/core_providers.dart';
import '../../design_system/design_system.dart';
import '../application/agent_controller.dart';
import '../application/agent_providers.dart';
import 'widgets/approval_card.dart';
import 'widgets/chat_entries.dart';

/// Chat screen for the FiNN assistant. Talks only to [agentControllerProvider].
class AgentScreen extends ConsumerStatefulWidget {
  const AgentScreen({super.key});

  @override
  ConsumerState<AgentScreen> createState() => _AgentScreenState();
}

class _AgentScreenState extends ConsumerState<AgentScreen> {
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

  Future<void> _confirmStartOver() async {
    final ok = await showFinnConfirm(
      context,
      title: 'Start a new chat?',
      message: 'The conversation is cleared. Your records are not affected.',
      confirmLabel: 'Start over',
    );
    if (ok) ref.read(agentControllerProvider.notifier).startOver();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(agentControllerProvider);
    final controller = ref.read(agentControllerProvider.notifier);
    ref.listen(agentControllerProvider.select((s) => (s.entries.length, s.status)), (_, _) => _scrollToEnd());

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        title: const Text('Assistant'),
        actions: [
          if (state.entries.isNotEmpty)
            FinnIconButton(
              icon: LucideIcons.squarePen,
              tooltip: 'New chat',
              onPressed: state.busy ? null : _confirmStartOver,
            ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: SafeArea(
        top: false,
        child: !state.available
            ? const EmptyState(
                icon: LucideIcons.sparkles,
                title: 'Assistant unavailable',
                message: 'The assistant works when FiNN is connected to your account online. '
                    'Your records are still available everywhere else in the app.',
              )
            : ResponsiveCenter(
                child: Column(
                  children: [
                    Expanded(
                      child: state.entries.isEmpty && !state.busy
                          ? _Intro(examples: _examples, onPick: _send)
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
                                  ApprovalCard(
                                    proposals: state.proposals,
                                    onApprove: controller.approve,
                                    onDecline: controller.decline,
                                  )
                                else if (state.busy)
                                  AgentProgress(label: state.progress ?? 'Thinking…'),
                              ],
                            ),
                    ),
                    _Composer(
                      controller: _input,
                      focusNode: _focus,
                      busy: state.busy,
                      onSend: _send,
                      onStop: controller.stop,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.examples, required this.onPick});
  final List<String> examples;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    return ListView(
      padding: const EdgeInsets.all(Space.gutter),
      children: [
        const SizedBox(height: Space.x6),
        Icon(LucideIcons.sparkles, size: 36, color: c.primary),
        const SizedBox(height: Space.x3),
        Text('Tell FiNN what happened', style: t.title, textAlign: TextAlign.center),
        const SizedBox(height: Space.x2),
        Text(
          'Record expenses, settle what people owe, pay EMIs or add to goals in one message. '
          'You review every change before it is saved.',
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

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSend,
    required this.onStop,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSend;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.x2, Space.x2, Space.x2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: FinnTextField(
                controller: controller,
                focusNode: focusNode,
                hint: busy ? 'Working on it…' : 'Ask or tell FiNN…',
                minLines: 1,
                maxLines: 4,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                enabled: !busy,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: Space.x2),
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x1),
              child: busy
                  ? FinnIconButton(icon: LucideIcons.square, tooltip: 'Stop', variant: FinnIconButtonVariant.outline, onPressed: onStop)
                  : FinnIconButton(icon: LucideIcons.sendHorizontal, tooltip: 'Send', variant: FinnIconButtonVariant.filled, onPressed: onSend),
            ),
          ],
        ),
      ),
    );
  }
}
