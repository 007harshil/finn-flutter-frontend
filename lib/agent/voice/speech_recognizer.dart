import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

enum SpeechReadiness {
  ready,

  /// Microphone or speech permission was refused.
  denied,

  /// The device has no speech recognition service.
  unavailable,
}

/// Callbacks for one recognition session.
@immutable
class SpeechSessionListener {
  const SpeechSessionListener({
    required this.onWords,
    required this.onLevel,
    required this.onEnded,
  });

  /// Words heard so far in this session. [isFinal] marks the session's
  /// last result.
  final void Function(String words, bool isFinal) onWords;

  /// Input level, 0 (silence) to 1 (loud).
  final void Function(double level) onLevel;

  /// The session ended on its own: after a pause on Android, a platform
  /// time limit, or an error code such as `error_no_match` (null when
  /// it ended cleanly).
  final void Function(String? error) onEnded;
}

/// Speech-to-text on the device. Platforms end a session on their own
/// after a pause in speech, so a caller that wants to keep listening starts
/// the next session from [SpeechSessionListener.onEnded].
abstract interface class SpeechRecognizer {
  /// Prepares the recognizer and asks for microphone permission.
  Future<SpeechReadiness> prepare();

  /// Starts one session. Requires [prepare] to have returned ready.
  Future<void> listen(SpeechSessionListener listener);

  /// Ends the session and delivers its final words.
  Future<void> stop();

  /// Ends the session and drops what was heard.
  Future<void> cancel();
}

/// [SpeechRecognizer] over the `speech_to_text` package: the platform's own
/// recognizer (Android SpeechRecognizer, Apple Speech, the browser's Web
/// Speech API). Free, no API key, and no audio passes through FiNN servers.
class DeviceSpeechRecognizer implements SpeechRecognizer {
  DeviceSpeechRecognizer({SpeechToText? speech}) : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;
  SpeechSessionListener? _listener;
  bool _ready = false;

  // Platforms report levels on different dB scales, so the range adapts to
  // what this device has reported.
  double _lowDb = double.infinity;
  double _highDb = double.negativeInfinity;

  @override
  Future<SpeechReadiness> prepare() async {
    if (_ready) return SpeechReadiness.ready;
    _ready = await _speech.initialize(onStatus: _onStatus, onError: _onError);
    if (_ready) return SpeechReadiness.ready;
    return await _speech.hasPermission ? SpeechReadiness.unavailable : SpeechReadiness.denied;
  }

  @override
  Future<void> listen(SpeechSessionListener listener) async {
    _listener = listener;
    await _speech.listen(
      onResult: _onResult,
      onSoundLevelChange: _onSoundLevel,
      listenOptions: SpeechListenOptions(
        listenMode: ListenMode.dictation,
        partialResults: true,
        // Upper bounds where a platform honours them (iOS, web). Stopping is
        // the user's call; Android still ends after a pause and is restarted.
        listenFor: const Duration(minutes: 30),
        pauseFor: const Duration(minutes: 30),
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() async {
    _listener = null;
    await _speech.cancel();
  }

  void _onResult(SpeechRecognitionResult result) {
    _listener?.onWords(result.recognizedWords, result.finalResult);
  }

  void _onSoundLevel(double db) {
    _lowDb = math.min(_lowDb, db);
    _highDb = math.max(_highDb, db);
    final span = math.max(_highDb - _lowDb, 12);
    _listener?.onLevel(((db - _lowDb) / span).clamp(0.0, 1.0));
  }

  void _onStatus(String status) {
    if (status != SpeechToText.doneStatus) return;
    final listener = _listener;
    _listener = null;
    listener?.onEnded(null);
  }

  void _onError(SpeechRecognitionError error) {
    final listener = _listener;
    _listener = null;
    listener?.onEnded(error.errorMsg);
  }
}
