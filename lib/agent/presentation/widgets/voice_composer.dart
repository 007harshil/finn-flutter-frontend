import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/di/core_providers.dart';
import '../../../design_system/design_system.dart';
import '../../voice/voice_input_controller.dart';

/// Message composer with a microphone. While listening it turns into a live
/// waveform with cancel / done; while transcribing it shows progress.
class VoiceComposer extends ConsumerWidget {
  const VoiceComposer({
    super.key,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final voice = ref.watch(voiceInputProvider);
    final voiceCtl = ref.read(voiceInputProvider.notifier);

    final Widget content = switch (voice.phase) {
      VoicePhase.listening => _ListeningBar(
          key: const ValueKey('listening'),
          levels: voice.levels,
          elapsed: voice.elapsed,
          onCancel: voiceCtl.cancel,
          onDone: voiceCtl.finish,
        ),
      VoicePhase.transcribing => _TranscribingBar(key: const ValueKey('transcribing'), onCancel: voiceCtl.cancel),
      VoicePhase.idle => Row(
          key: const ValueKey('compose'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (voice.available)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.x1, right: Space.x1),
                child: FinnIconButton(
                  icon: LucideIcons.mic,
                  tooltip: 'Speak',
                  variant: FinnIconButtonVariant.outline,
                  onPressed: busy
                      ? null
                      : () {
                          if (ref.read(settingsProvider).hapticsEnabled) HapticFeedback.mediumImpact();
                          focusNode.unfocus();
                          voiceCtl.start();
                        },
                ),
              ),
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
    };

    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.border))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
        child: AnimatedSwitcher(duration: context.motion.fast, child: content),
      ),
    );
  }
}

class _ListeningBar extends StatelessWidget {
  const _ListeningBar({
    super.key,
    required this.levels,
    required this.elapsed,
    required this.onCancel,
    required this.onDone,
  });

  final List<double> levels;
  final Duration elapsed;
  final VoidCallback onCancel;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.text;
    final seconds = elapsed.inSeconds;
    final clock = '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Semantics(
      liveRegion: true,
      label: 'Listening. Tap done when you finish speaking.',
      child: Row(
        children: [
          FinnIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancel),
          const SizedBox(width: Space.x1),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.full),
                gradient: LinearGradient(
                  colors: [c.agentStart.withValues(alpha: 0.14), c.agentEnd.withValues(alpha: 0.14)],
                ),
                border: Border.all(color: c.agentMid.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: c.negative, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Space.x2),
                  Expanded(
                    child: CustomPaint(
                      size: const Size.fromHeight(28),
                      painter: _WaveformPainter(levels: levels, start: c.agentStart, end: c.agentEnd),
                    ),
                  ),
                  const SizedBox(width: Space.x2),
                  Text(clock, style: t.caption.copyWith(color: c.textSecondary, fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.x2),
          FinnIconButton(icon: LucideIcons.check, tooltip: 'Done speaking', variant: FinnIconButtonVariant.filled, onPressed: onDone),
        ],
      ),
    );
  }
}

class _TranscribingBar extends StatelessWidget {
  const _TranscribingBar({super.key, required this.onCancel});
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'Transcribing',
      child: Row(
        children: [
          FinnIconButton(icon: LucideIcons.x, tooltip: 'Cancel voice', onPressed: onCancel),
          const SizedBox(width: Space.x2),
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.agentMid)),
          const SizedBox(width: Space.x2),
          Expanded(child: Text('Turning your voice into text…', style: context.text.caption.copyWith(color: c.textSecondary))),
        ],
      ),
    );
  }
}

/// Bars for recent input levels, newest on the right.
class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.levels, required this.start, required this.end});

  final List<double> levels;
  final Color start;
  final Color end;

  static const _bars = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = size.width / _bars;
    final barWidth = (gap * 0.55).clamp(2.0, 5.0);
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < _bars; i++) {
      final li = levels.length - _bars + i;
      final level = li >= 0 ? levels[li] : 0.0;
      final h = 3 + (size.height - 3) * level;
      final x = gap * (i + 0.5);
      paint
        ..color = Color.lerp(start, end, i / _bars)!
        ..strokeWidth = barWidth;
      canvas.drawLine(Offset(x, size.height / 2 - h / 2), Offset(x, size.height / 2 + h / 2), paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.levels != levels || old.start != start || old.end != end;
}
