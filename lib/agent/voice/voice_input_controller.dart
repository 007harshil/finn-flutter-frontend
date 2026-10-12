import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/result/result.dart';
import '../../data/remote/api_client.dart';
import '../../data/remote/api_config.dart';
import '../../data/remote/remote_providers.dart';
import 'speech_transcriber.dart';
import 'voice_capture.dart';

enum VoicePhase { idle, listening, transcribing }

/// A finished transcript. [seq] changes for every result so listeners can
/// react to two identical transcripts in a row.
@immutable
class VoiceTranscript {
  const VoiceTranscript(this.seq, this.text);
  final int seq;
  final String text;
}

@immutable
class VoiceInputState {
  const VoiceInputState({
    this.available = true,
    this.phase = VoicePhase.idle,
    this.levels = const [],
    this.elapsed = Duration.zero,
    this.transcript,
    this.error,
  });

  /// False when no transcriber is configured (local mode).
  final bool available;
  final VoicePhase phase;

  /// Recent input levels (0..1), oldest first, for the waveform.
  final List<double> levels;
  final Duration elapsed;
  final VoiceTranscript? transcript;

  /// User-facing message for the last failure, with its own sequence.
  final VoiceTranscript? error;

  bool get busy => phase != VoicePhase.idle;

  VoiceInputState copyWith({
    VoicePhase? phase,
    List<double>? levels,
    Duration? elapsed,
    VoiceTranscript? transcript,
    VoiceTranscript? error,
  }) =>
      VoiceInputState(
        available: available,
        phase: phase ?? this.phase,
        levels: levels ?? this.levels,
        elapsed: elapsed ?? this.elapsed,
        transcript: transcript ?? this.transcript,
        error: error ?? this.error,
      );
}

/// Limits for one voice request.
@immutable
class VoiceConfig {
  const VoiceConfig({
    this.maxDuration = const Duration(seconds: 60),
    this.minDuration = const Duration(milliseconds: 500),
    this.silenceToStop = const Duration(milliseconds: 1800),
    this.speechLevel = 0.42,
    this.waveformPoints = 28,
    this.requestTimeout = const Duration(seconds: 40),
  });

  /// Recording stops on its own after this long.
  final Duration maxDuration;

  /// Shorter clips are discarded (accidental taps).
  final Duration minDuration;

  /// After speech was heard, this much quiet ends the recording.
  final Duration silenceToStop;

  /// Level (0..1) treated as speech.
  final double speechLevel;
  final int waveformPoints;
  final Duration requestTimeout;
}

final voiceConfigProvider = Provider<VoiceConfig>((ref) => const VoiceConfig());

/// Creates the microphone recorder. Overridden in tests.
final voiceCaptureFactoryProvider = Provider<VoiceCapture Function()>((ref) => RecordVoiceCapture.new);

/// Speech-to-text, or null when the app is not connected to the FiNN API
/// (the provider key lives on the server).
final speechTranscriberProvider = Provider<SpeechTranscriber?>((ref) {
  final backend = ref.watch(remoteBackendProvider);
  if (backend == null) return null;
  final api = ApiClient(
    config: ApiConfig(apiUrl: backend.config.apiUrl, timeout: ref.watch(voiceConfigProvider).requestTimeout),
    auth: backend.auth,
  );
  return FinnRelayTranscriber(api);
});

final voiceInputProvider = NotifierProvider<VoiceInputController, VoiceInputState>(VoiceInputController.new);

/// Tap to talk: [start] records, [finish] (or silence, or the time limit)
/// stops and transcribes, [cancel] discards. Results arrive in
/// [VoiceInputState.transcript]; failures in [VoiceInputState.error].
class VoiceInputController extends Notifier<VoiceInputState> {
  VoiceCapture? _capture;
  StreamSubscription<double>? _levelSub;
  Timer? _ticker;
  DateTime? _startedAt;
  DateTime? _lastSpeech;
  bool _heardSpeech = false;
  int _seq = 0;

  /// Bumped on cancel so a late transcript from an abandoned clip is dropped.
  int _generation = 0;

  @override
  VoiceInputState build() {
    final transcriber = ref.watch(speechTranscriberProvider);
    ref.onDispose(_teardown);
    return VoiceInputState(available: transcriber != null);
  }

  VoiceConfig get _config => ref.read(voiceConfigProvider);

  Future<void> start() async {
    if (!state.available || state.busy) return;
    final capture = _capture ??= ref.read(voiceCaptureFactoryProvider)();
    state = state.copyWith(phase: VoicePhase.listening, levels: const [], elapsed: Duration.zero);
    try {
      if (!await capture.requestPermission()) {
        _fail('Microphone access is off. Allow it in system settings to talk to FiNN.');
        return;
      }
      if (!ref.mounted || state.phase != VoicePhase.listening) return;
      final levels = await capture.start();
      _startedAt = DateTime.now();
      _lastSpeech = null;
      _heardSpeech = false;
      _levelSub = levels.listen(_onLevel);
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
    } catch (e) {
      debugPrint('Voice capture failed to start: $e');
      await _stopCapture(discard: true);
      _fail('Could not start the microphone. Please try again.');
    }
  }

  /// Stops recording and transcribes what was said.
  Future<void> finish() async {
    if (state.phase != VoicePhase.listening) return;
    final generation = _generation;
    final clip = await _stopCapture();
    if (!ref.mounted || generation != _generation) return;
    if (clip == null || clip.duration < _config.minDuration) {
      state = state.copyWith(phase: VoicePhase.idle, levels: const []);
      return;
    }
    final transcriber = ref.read(speechTranscriberProvider);
    if (transcriber == null) {
      _fail('Voice input is unavailable right now.');
      return;
    }
    state = state.copyWith(phase: VoicePhase.transcribing);
    try {
      final text = await transcriber.transcribe(clip);
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(phase: VoicePhase.idle, levels: const [], transcript: VoiceTranscript(_seq++, text));
    } on AppFailure catch (f) {
      if (!ref.mounted || generation != _generation) return;
      _fail(f.message);
    } catch (e) {
      debugPrint('Transcription failed: $e');
      if (!ref.mounted || generation != _generation) return;
      _fail('Could not understand the recording. Please try again.');
    }
  }

  /// Discards the current recording or transcription.
  Future<void> cancel() async {
    if (!state.busy) return;
    _generation++;
    await _stopCapture(discard: true);
    if (ref.mounted) state = state.copyWith(phase: VoicePhase.idle, levels: const []);
  }

  void _onLevel(double level) {
    final points = _config.waveformPoints;
    final next = [...state.levels, level];
    state = state.copyWith(levels: next.length > points ? next.sublist(next.length - points) : next);
    if (level >= _config.speechLevel) {
      _heardSpeech = true;
      _lastSpeech = DateTime.now();
    }
  }

  void _tick() {
    final started = _startedAt;
    if (started == null || state.phase != VoicePhase.listening) return;
    final now = DateTime.now();
    final elapsed = now.difference(started);
    state = state.copyWith(elapsed: elapsed);
    final quietFor = _lastSpeech == null ? Duration.zero : now.difference(_lastSpeech!);
    if (elapsed >= _config.maxDuration || (_heardSpeech && quietFor >= _config.silenceToStop)) {
      unawaited(finish());
    }
  }

  Future<VoiceClip?> _stopCapture({bool discard = false}) async {
    _ticker?.cancel();
    _ticker = null;
    // Not awaited: nothing depends on the level stream closing first.
    unawaited(_levelSub?.cancel());
    _levelSub = null;
    _startedAt = null;
    final capture = _capture;
    if (capture == null) return null;
    try {
      if (discard) {
        await capture.cancel();
        return null;
      }
      return await capture.stop();
    } catch (e) {
      debugPrint('Voice capture failed to stop: $e');
      return null;
    }
  }

  void _fail(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: VoicePhase.idle, levels: const [], error: VoiceTranscript(_seq++, message));
  }

  void _teardown() {
    _generation++;
    _ticker?.cancel();
    _levelSub?.cancel();
    final capture = _capture;
    _capture = null;
    if (capture != null) unawaited(capture.dispose());
  }
}
