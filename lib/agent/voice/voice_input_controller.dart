import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'speech_recognizer.dart';

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
    this.words = '',
    this.transcript,
    this.error,
  });

  /// False once the device turned out to have no speech recognition.
  final bool available;
  final VoicePhase phase;

  /// Recent input levels (0..1), oldest first, for the waveform.
  final List<double> levels;
  final Duration elapsed;

  /// Live words heard so far while listening.
  final String words;
  final VoiceTranscript? transcript;

  /// User-facing message for the last failure, with its own sequence.
  final VoiceTranscript? error;

  bool get busy => phase != VoicePhase.idle;

  VoiceInputState copyWith({
    bool? available,
    VoicePhase? phase,
    List<double>? levels,
    Duration? elapsed,
    String? words,
    VoiceTranscript? transcript,
    VoiceTranscript? error,
  }) => VoiceInputState(
    available: available ?? this.available,
    phase: phase ?? this.phase,
    levels: levels ?? this.levels,
    elapsed: elapsed ?? this.elapsed,
    words: words ?? this.words,
    transcript: transcript ?? this.transcript,
    error: error ?? this.error,
  );
}

/// Tuning for one voice request.
@immutable
class VoiceConfig {
  const VoiceConfig({
    this.restartDelay = const Duration(milliseconds: 250),
    this.finalizeTimeout = const Duration(seconds: 3),
    this.maxFailedSessions = 3,
    this.waveformPoints = 28,
  });

  /// Pause before listening again after the platform ended a session.
  final Duration restartDelay;

  /// How long Done waits for the recognizer's final words.
  final Duration finalizeTimeout;

  /// Sessions in a row that may fail (not counting silence) before the
  /// microphone gives up and reports an error.
  final int maxFailedSessions;
  final int waveformPoints;
}

final voiceConfigProvider = Provider<VoiceConfig>((ref) => const VoiceConfig());

/// On-device speech-to-text. Overridden in tests.
final speechRecognizerProvider = Provider<SpeechRecognizer>((ref) => DeviceSpeechRecognizer());

final voiceInputProvider = NotifierProvider<VoiceInputController, VoiceInputState>(VoiceInputController.new);

/// Error codes that only mean nobody spoke during a session.
const _silenceErrors = {'error_no_match', 'error_speech_timeout'};

/// Error codes after which listening cannot continue.
const _fatalErrors = {'error_permission', 'error_insufficient_permissions', 'error_language_not_supported'};

/// Tap to talk: [start] listens until the user taps [finish] (which sends
/// the words) or [cancel] (which drops them). It never stops on its own:
/// when the platform ends a session after a pause, a new one starts and the
/// words carry over. Results arrive in [VoiceInputState.transcript];
/// failures in [VoiceInputState.error].
class VoiceInputController extends Notifier<VoiceInputState> {
  late SpeechRecognizer _recognizer;
  Timer? _ticker;
  Timer? _restart;
  DateTime? _startedAt;
  int _seq = 0;

  /// Words from sessions that already ended, and from the open one.
  String _kept = '';
  String _live = '';
  int _failedSessions = 0;
  bool _sessionOpen = false;

  /// Completes when the session that [finish] stopped has ended.
  Completer<void>? _finalized;

  /// Bumped whenever listening ends, so callbacks from an old session are
  /// ignored.
  int _generation = 0;

  @override
  VoiceInputState build() {
    _recognizer = ref.watch(speechRecognizerProvider);
    ref.onDispose(_teardown);
    return const VoiceInputState();
  }

  VoiceConfig get _config => ref.read(voiceConfigProvider);
  String get _words => [_kept, _live].where((s) => s.isNotEmpty).join(' ');

  Future<void> start() async {
    if (!state.available || state.busy) return;
    final generation = ++_generation;
    _kept = '';
    _live = '';
    _failedSessions = 0;
    state = state.copyWith(phase: VoicePhase.listening, levels: const [], elapsed: Duration.zero, words: '');
    try {
      final readiness = await _recognizer.prepare();
      if (!ref.mounted || generation != _generation) return;
      switch (readiness) {
        case SpeechReadiness.denied:
          _fail('Microphone access is off. Allow it in system settings to talk to FiNN.');
          return;
        case SpeechReadiness.unavailable:
          state = state.copyWith(available: false);
          _fail('Speech recognition is not available on this device.');
          return;
        case SpeechReadiness.ready:
          break;
      }
      _startedAt = DateTime.now();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
      await _listen(generation);
    } catch (e) {
      debugPrint('Voice input failed to start: $e');
      await _end(cancel: true);
      _fail('Could not start the microphone. Please try again.');
    }
  }

  /// Stops listening and sends what was said.
  Future<void> finish() async {
    if (state.phase != VoicePhase.listening) return;
    final generation = _generation;
    _restart?.cancel();
    _ticker?.cancel();
    state = state.copyWith(phase: VoicePhase.transcribing);
    if (_sessionOpen) {
      final finalized = _finalized = Completer<void>();
      try {
        await _recognizer.stop();
        await finalized.future.timeout(_config.finalizeTimeout, onTimeout: () {});
      } catch (e) {
        debugPrint('Voice input failed to stop: $e');
      }
    }
    if (!ref.mounted || generation != _generation) return;
    final text = _words.trim();
    _generation++;
    _reset();
    state = text.isEmpty
        ? state.copyWith(phase: VoicePhase.idle, levels: const [], words: '')
        : state.copyWith(phase: VoicePhase.idle, levels: const [], words: '', transcript: VoiceTranscript(_seq++, text));
  }

  /// Stops listening and drops what was heard.
  Future<void> cancel() async {
    if (!state.busy) return;
    await _end(cancel: true);
    if (ref.mounted) state = state.copyWith(phase: VoicePhase.idle, levels: const [], words: '');
  }

  Future<void> _listen(int generation) async {
    _live = '';
    _sessionOpen = true;
    await _recognizer.listen(
      SpeechSessionListener(
        onWords: (words, isFinal) {
          if (generation != _generation) return;
          _live = words.trim();
          if (_live.isNotEmpty) _failedSessions = 0;
          if (ref.mounted) state = state.copyWith(words: _words);
        },
        onLevel: (level) {
          if (generation != _generation || !ref.mounted) return;
          final points = _config.waveformPoints;
          final next = [...state.levels, level];
          state = state.copyWith(levels: next.length > points ? next.sublist(next.length - points) : next);
        },
        onEnded: (error) => _onSessionEnded(generation, error),
      ),
    );
  }

  void _onSessionEnded(int generation, String? error) {
    if (generation != _generation || !ref.mounted) return;
    _sessionOpen = false;
    if (_live.isNotEmpty) _kept = _words;
    _live = '';
    final finalized = _finalized;
    if (finalized != null) {
      if (!finalized.isCompleted) finalized.complete();
      return;
    }
    if (state.phase != VoicePhase.listening) return;
    if (error != null && _fatalErrors.contains(error)) {
      unawaited(_end(cancel: true));
      _fail('Microphone access is off. Allow it in system settings to talk to FiNN.');
      return;
    }
    if (error != null && !_silenceErrors.contains(error) && ++_failedSessions >= _config.maxFailedSessions) {
      debugPrint('Voice input gave up after $error');
      unawaited(_end(cancel: true));
      _fail('Could not hear you. Please check your connection and try again.');
      return;
    }
    // The platform stopped after a pause; keep listening until the user ends it.
    _restart?.cancel();
    _restart = Timer(_config.restartDelay, () async {
      if (generation != _generation || state.phase != VoicePhase.listening) return;
      try {
        await _listen(generation);
      } catch (e) {
        debugPrint('Voice input failed to resume: $e');
        await _end(cancel: true);
        _fail('The microphone stopped. Please try again.');
      }
    });
  }

  void _tick() {
    final started = _startedAt;
    if (started == null || state.phase != VoicePhase.listening) return;
    state = state.copyWith(elapsed: DateTime.now().difference(started));
  }

  Future<void> _end({bool cancel = false}) async {
    _generation++;
    _reset();
    if (!cancel) return;
    try {
      await _recognizer.cancel();
    } catch (e) {
      debugPrint('Voice input failed to cancel: $e');
    }
  }

  void _reset() {
    _ticker?.cancel();
    _ticker = null;
    _restart?.cancel();
    _restart = null;
    _startedAt = null;
    _finalized = null;
    _sessionOpen = false;
    _kept = '';
    _live = '';
  }

  void _fail(String message) {
    if (!ref.mounted) return;
    state = state.copyWith(phase: VoicePhase.idle, levels: const [], words: '', error: VoiceTranscript(_seq++, message));
  }

  void _teardown() {
    final listening = _sessionOpen || _restart != null;
    _generation++;
    _reset();
    if (listening) unawaited(_recognizer.cancel().catchError((Object _) {}));
  }
}
