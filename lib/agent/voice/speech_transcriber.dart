import 'dart:convert';

import '../../core/result/result.dart';
import '../../data/remote/api_client.dart';
import 'voice_capture.dart';

/// Turns a recorded clip into text.
abstract interface class SpeechTranscriber {
  /// The transcript, or '' when no speech was heard. Throws [AppFailure].
  Future<String> transcribe(VoiceClip clip);
}

/// Transcription through the FiNN API (`POST /api/v1/agent/transcriptions`),
/// which forwards to Groq Whisper (`whisper-large-v3`) with the server-held
/// key. Audio is sent once and never stored.
class FinnRelayTranscriber implements SpeechTranscriber {
  FinnRelayTranscriber(this.api, {this.path = '/agent/transcriptions', this.language});

  final ApiClient api;
  final String path;

  /// Optional ISO-639-1 hint; null lets Whisper detect the language.
  final String? language;

  @override
  Future<String> transcribe(VoiceClip clip) async {
    final data = await api.post(path, body: {
      'audio': base64Encode(clip.bytes),
      'mimeType': clip.mimeType,
      'language': ?language,
    });
    if (data is Map && data['text'] is String) return (data['text'] as String).trim();
    throw const AppFailure(FailureCode.unknown, 'Could not read the transcript. Please try again.', retryable: true);
  }
}
