import 'package:finn/agent/agent.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'agent_fakes.dart';

/// Scripted recognizer: the test plays the platform's role by calling
/// [say], [level] and [endSession].
class FakeRecognizer implements SpeechRecognizer {
  FakeRecognizer({this.readiness = SpeechReadiness.ready, this.onStop});

  final SpeechReadiness readiness;

  /// Words the platform delivers as final when the user taps Done.
  final String? onStop;
  SpeechSessionListener? _listener;
  int sessions = 0;
  int stops = 0;
  int cancels = 0;

  bool get open => _listener != null;

  @override
  Future<SpeechReadiness> prepare() async => readiness;

  @override
  Future<void> listen(SpeechSessionListener listener) async {
    sessions++;
    _listener = listener;
  }

  void say(String words, {bool isFinal = false}) => _listener!.onWords(words, isFinal);
  void level(double value) => _listener!.onLevel(value);

  /// The platform ends the session on its own (after a pause, or an error).
  void endSession([String? error]) {
    final l = _listener;
    _listener = null;
    l!.onEnded(error);
  }

  @override
  Future<void> stop() async {
    stops++;
    final l = _listener;
    if (l == null) return;
    if (onStop != null) l.onWords(onStop!, true);
    _listener = null;
    l.onEnded(null);
  }

  @override
  Future<void> cancel() async {
    cancels++;
    _listener = null;
  }
}

const _fastConfig = VoiceConfig(
  restartDelay: Duration(milliseconds: 1),
  finalizeTimeout: Duration(milliseconds: 50),
);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  group('VoiceInputController', () {
    ProviderContainer containerWith(FakeRecognizer recognizer) {
      final container = ProviderContainer(
        overrides: [
          speechRecognizerProvider.overrideWithValue(recognizer),
          voiceConfigProvider.overrideWithValue(_fastConfig),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('listens, shows levels and live words, then publishes the transcript', () async {
      final recognizer = FakeRecognizer(onStop: 'spent 450 on lunch');
      final container = containerWith(recognizer);
      final voice = container.read(voiceInputProvider.notifier);

      await voice.start();
      expect(container.read(voiceInputProvider).phase, VoicePhase.listening);
      recognizer
        ..level(0.2)
        ..level(0.8)
        ..say('spent 450');
      expect(container.read(voiceInputProvider).levels, [0.2, 0.8]);
      expect(container.read(voiceInputProvider).words, 'spent 450');

      await voice.finish();
      final state = container.read(voiceInputProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.transcript?.text, 'spent 450 on lunch');
      expect(state.words, isEmpty);
      expect(recognizer.stops, 1);
    });

    test('keeps listening after the platform ends a session, until Done', () async {
      final recognizer = FakeRecognizer();
      final container = containerWith(recognizer);
      final voice = container.read(voiceInputProvider.notifier);

      await voice.start();
      recognizer.say('spent 450 on lunch', isFinal: true);
      recognizer.endSession();
      await _settle();
      // Silence ends the next sessions with an error; the mic still stays on.
      recognizer.endSession('error_speech_timeout');
      await _settle();
      recognizer.endSession('error_no_match');
      await _settle();
      expect(recognizer.sessions, 4);
      expect(recognizer.open, isTrue);
      expect(container.read(voiceInputProvider).phase, VoicePhase.listening);

      recognizer.say('in cash');
      expect(container.read(voiceInputProvider).words, 'spent 450 on lunch in cash');
      await voice.finish();
      expect(container.read(voiceInputProvider).transcript?.text, 'spent 450 on lunch in cash');
      await _settle();
      expect(recognizer.sessions, 4, reason: 'no restart after Done');
    });

    test('Done between sessions sends the words without waiting', () async {
      final recognizer = FakeRecognizer();
      final container = containerWith(recognizer);
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      recognizer.say('coffee 120', isFinal: true);
      recognizer.endSession();
      await voice.finish();
      expect(container.read(voiceInputProvider).transcript?.text, 'coffee 120');
      await _settle();
      expect(recognizer.sessions, 1);
    });

    test('denied permission reports an error and never listens', () async {
      final recognizer = FakeRecognizer(readiness: SpeechReadiness.denied);
      final container = containerWith(recognizer);
      await container.read(voiceInputProvider.notifier).start();
      final state = container.read(voiceInputProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.error?.text, contains('Microphone access is off'));
      expect(recognizer.sessions, 0);
    });

    test('a device without speech recognition turns voice off', () async {
      final recognizer = FakeRecognizer(readiness: SpeechReadiness.unavailable);
      final container = containerWith(recognizer);
      await container.read(voiceInputProvider.notifier).start();
      final state = container.read(voiceInputProvider);
      expect(state.available, isFalse);
      expect(state.error?.text, contains('not available'));
    });

    test('nothing heard publishes no transcript', () async {
      final recognizer = FakeRecognizer();
      final container = containerWith(recognizer);
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      await voice.finish();
      expect(container.read(voiceInputProvider).transcript, isNull);
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
    });

    test('repeated real failures stop the microphone with a message', () async {
      final recognizer = FakeRecognizer();
      final container = containerWith(recognizer);
      await container.read(voiceInputProvider.notifier).start();
      for (var i = 0; i < 3; i++) {
        recognizer.endSession('error_network');
        await _settle();
      }
      final state = container.read(voiceInputProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.error?.text, contains('Could not hear you'));
      expect(recognizer.cancels, 1);
    });

    test('cancel drops the words and stops listening', () async {
      final recognizer = FakeRecognizer();
      final container = containerWith(recognizer);
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      recognizer.say('never mind');
      await voice.cancel();
      expect(container.read(voiceInputProvider).transcript, isNull);
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
      expect(recognizer.cancels, 1);
      expect(recognizer.open, isFalse);
    });

    test('closing agent mode cancels an open microphone', () async {
      final recognizer = FakeRecognizer();
      final env = await TestEnv.create();
      final container = ProviderContainer(
        overrides: [
          ...env.overrides,
          speechRecognizerProvider.overrideWithValue(recognizer),
          voiceConfigProvider.overrideWithValue(_fastConfig),
        ],
      );
      addTearDown(container.dispose);
      container.read(agentModeProvider.notifier).open();
      await container.read(voiceInputProvider.notifier).start();
      container.read(agentModeProvider.notifier).close();
      await pumpEventQueue();
      expect(container.read(agentModeProvider), isFalse);
      expect(recognizer.cancels, 1);
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
    });
  });

  testWidgets('a spoken request is sent to the agent and reviewed visually', (tester) async {
    final env = await TestEnv.create();
    final recognizer = FakeRecognizer(onStop: 'Spent 450 on lunch in cash');
    final provider = ScriptedProvider([
      plan([
        {'op': 'expense', 'amount': 450, 'category': 'Food & Dining', 'note': 'lunch', 'account': 'Cash'},
      ]),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...env.overrides,
          llmProviderProvider.overrideWithValue(provider),
          speechRecognizerProvider.overrideWithValue(recognizer),
        ],
        child: MaterialApp(
          theme: FinnTheme.light(),
          home: const MotionScope(reduceMotion: true, child: AgentScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Speak'));
    await tester.pump();
    expect(find.byTooltip('Done speaking'), findsOneWidget);
    recognizer.say('Spent 450');
    await tester.pump();
    expect(find.text('Spent 450'), findsOneWidget, reason: 'live words while listening');

    await tester.tap(find.byTooltip('Done speaking'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final sent = ProviderScope.containerOf(tester.element(find.byType(AgentScreen)))
        .read(agentControllerProvider)
        .entries;
    expect((sent.single as UserChatEntry).text, 'Spent 450 on lunch in cash', reason: 'transcript sent as the user message');
    expect(find.text('Review this change'), findsOneWidget);
    expect(find.text('Nothing is saved until you approve.'), findsOneWidget);
    expect(find.text('Moves money'), findsWidgets);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Change saved'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
  });
}
