import 'dart:async';
import 'dart:typed_data';

import 'package:finn/agent/agent.dart';
import 'package:finn/agent/voice/voice_capture.dart' show wavFromPcm16, pcm16Level;
import 'package:finn/core/result/result.dart';
import 'package:finn/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';
import 'agent_fakes.dart';

class FakeCapture implements VoiceCapture {
  FakeCapture({this.permitted = true, this.clipLength = const Duration(seconds: 2)});

  final bool permitted;
  final Duration clipLength;
  final levels = StreamController<double>.broadcast();
  int starts = 0;
  int stops = 0;
  int cancels = 0;

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<Stream<double>> start() async {
    starts++;
    return levels.stream;
  }

  @override
  Future<VoiceClip?> stop() async {
    stops++;
    return VoiceClip(bytes: Uint8List(64), mimeType: 'audio/wav', duration: clipLength);
  }

  @override
  Future<void> cancel() async => cancels++;

  @override
  Future<void> dispose() async {}
}

class FakeTranscriber implements SpeechTranscriber {
  FakeTranscriber(this.reply);

  /// A String transcript, an [AppFailure] to throw, or a Completer to wait on.
  final Object reply;
  final clips = <VoiceClip>[];

  @override
  Future<String> transcribe(VoiceClip clip) async {
    clips.add(clip);
    final r = reply;
    if (r is AppFailure) throw r;
    if (r is Completer<String>) return r.future;
    return r as String;
  }
}

void main() {
  group('audio helpers', () {
    test('wavFromPcm16 writes a valid 16 kHz mono header', () {
      final pcm = Uint8List(320);
      final wav = wavFromPcm16(pcm, sampleRate: 16000);
      final h = ByteData.sublistView(wav);
      expect(wav.length, 44 + 320);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(h.getUint32(4, Endian.little), 36 + 320);
      expect(h.getUint16(22, Endian.little), 1, reason: 'mono');
      expect(h.getUint32(24, Endian.little), 16000);
      expect(h.getUint32(28, Endian.little), 32000, reason: 'byte rate');
      expect(h.getUint16(34, Endian.little), 16);
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      expect(h.getUint32(40, Endian.little), 320);
    });

    test('pcm16Level maps silence to 0 and full scale to 1', () {
      expect(pcm16Level(Uint8List(200)), 0);
      final loud = ByteData(200);
      for (var i = 0; i < 100; i++) {
        loud.setInt16(i * 2, i.isEven ? 32767 : -32768, Endian.little);
      }
      expect(pcm16Level(loud.buffer.asUint8List()), closeTo(1, 0.01));
    });
  });

  group('VoiceInputController', () {
    ProviderContainer containerWith(FakeCapture capture, SpeechTranscriber? transcriber) {
      final container = ProviderContainer(overrides: [
        voiceCaptureFactoryProvider.overrideWithValue(() => capture),
        speechTranscriberProvider.overrideWithValue(transcriber),
      ]);
      addTearDown(container.dispose);
      return container;
    }

    test('is unavailable without a transcriber (local mode)', () async {
      final capture = FakeCapture();
      final container = containerWith(capture, null);
      expect(container.read(voiceInputProvider).available, isFalse);
      await container.read(voiceInputProvider.notifier).start();
      expect(capture.starts, 0);
    });

    test('records, shows levels and publishes the transcript', () async {
      final capture = FakeCapture();
      final transcriber = FakeTranscriber('spent 450 on lunch');
      final container = containerWith(capture, transcriber);
      final voice = container.read(voiceInputProvider.notifier);

      await voice.start();
      expect(container.read(voiceInputProvider).phase, VoicePhase.listening);
      capture.levels
        ..add(0.2)
        ..add(0.8);
      await pumpEventQueue();
      expect(container.read(voiceInputProvider).levels, [0.2, 0.8]);

      await voice.finish();
      final state = container.read(voiceInputProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.transcript?.text, 'spent 450 on lunch');
      expect(transcriber.clips.single.mimeType, 'audio/wav');
      expect(capture.stops, 1);
    });

    test('denied permission reports an error and never records', () async {
      final capture = FakeCapture(permitted: false);
      final container = containerWith(capture, FakeTranscriber('x'));
      await container.read(voiceInputProvider.notifier).start();
      final state = container.read(voiceInputProvider);
      expect(state.phase, VoicePhase.idle);
      expect(state.error?.text, contains('Microphone access is off'));
      expect(capture.starts, 0);
    });

    test('a very short clip is discarded without transcribing', () async {
      final capture = FakeCapture(clipLength: const Duration(milliseconds: 200));
      final transcriber = FakeTranscriber('x');
      final container = containerWith(capture, transcriber);
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      await voice.finish();
      expect(transcriber.clips, isEmpty);
      expect(container.read(voiceInputProvider).transcript, isNull);
    });

    test('transcription failures surface the server message', () async {
      final capture = FakeCapture();
      final container = containerWith(
        capture,
        FakeTranscriber(const AppFailure(FailureCode.unavailable, "You're sending requests too quickly.", retryable: true)),
      );
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      await voice.finish();
      expect(container.read(voiceInputProvider).error?.text, "You're sending requests too quickly.");
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
    });

    test('cancel while transcribing drops the late transcript', () async {
      final capture = FakeCapture();
      final pending = Completer<String>();
      final container = containerWith(capture, FakeTranscriber(pending));
      final voice = container.read(voiceInputProvider.notifier);
      await voice.start();
      final finishing = voice.finish();
      await pumpEventQueue();
      expect(container.read(voiceInputProvider).phase, VoicePhase.transcribing);
      await voice.cancel();
      pending.complete('too late');
      await finishing;
      expect(container.read(voiceInputProvider).transcript, isNull);
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
    });

    test('closing agent mode cancels an open microphone', () async {
      final capture = FakeCapture();
      final env = await TestEnv.create();
      final container = ProviderContainer(overrides: [
        ...env.overrides,
        voiceCaptureFactoryProvider.overrideWithValue(() => capture),
        speechTranscriberProvider.overrideWithValue(FakeTranscriber('x')),
      ]);
      addTearDown(container.dispose);
      container.read(agentModeProvider.notifier).open();
      await container.read(voiceInputProvider.notifier).start();
      container.read(agentModeProvider.notifier).close();
      await pumpEventQueue();
      expect(container.read(agentModeProvider), isFalse);
      expect(capture.cancels, 1);
      expect(container.read(voiceInputProvider).phase, VoicePhase.idle);
    });
  });

  testWidgets('a spoken request is sent to the agent and reviewed visually', (tester) async {
    final env = await TestEnv.create();
    final capture = FakeCapture();
    final provider = ScriptedProvider([
      callsTools([
        toolCall('record_transaction', {
          'type': 'expense',
          'amount': '450',
          'categoryId': 'cat_food',
          'date': '2026-10-10',
          'paymentMethod': 'upi',
        }),
      ]),
      says('I will record ₹450 for lunch.'),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        ...env.overrides,
        llmProviderProvider.overrideWithValue(provider),
        voiceCaptureFactoryProvider.overrideWithValue(() => capture),
        speechTranscriberProvider.overrideWithValue(FakeTranscriber('Spent 450 on lunch')),
      ],
      child: MaterialApp(
        theme: FinnTheme.light(),
        home: const MotionScope(reduceMotion: true, child: AgentScreen()),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byTooltip('Speak'));
    await tester.pump();
    expect(find.byTooltip('Done speaking'), findsOneWidget);

    await tester.tap(find.byTooltip('Done speaking'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    final sent = ProviderScope.containerOf(tester.element(find.byType(AgentScreen))).read(agentControllerProvider).entries;
    expect((sent.single as UserChatEntry).text, 'Spent 450 on lunch', reason: 'transcript sent as the user message');
    expect(find.text('Review this change'), findsOneWidget);
    expect(find.text('Nothing is saved until you approve.'), findsOneWidget);
    expect(find.text('MOVES MONEY'), findsWidgets);

    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Change saved'), findsOneWidget);
    expect(find.text('SAVED'), findsOneWidget);
  });
}
