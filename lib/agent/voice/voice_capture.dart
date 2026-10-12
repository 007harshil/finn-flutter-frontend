import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';

/// A finished recording, ready to transcribe.
@immutable
class VoiceClip {
  const VoiceClip({required this.bytes, required this.mimeType, required this.duration});

  final Uint8List bytes;
  final String mimeType;
  final Duration duration;
}

/// Microphone access for voice requests. One instance records one clip at a
/// time. Implementations must never keep audio after [stop]/[cancel].
abstract interface class VoiceCapture {
  /// Asks for microphone permission when needed. False when denied.
  Future<bool> requestPermission();

  /// Starts recording. The stream emits the input level (0 = silence,
  /// 1 = loud) a few times per second until [stop] or [cancel].
  Future<Stream<double>> start();

  /// Stops and returns the clip, or null when nothing was recorded.
  Future<VoiceClip?> stop();

  /// Stops and discards the recording.
  Future<void> cancel();

  Future<void> dispose();
}

/// Records 16 kHz mono 16-bit PCM (what Whisper uses internally, so no
/// quality is lost to compression) and wraps it as WAV in memory. Streaming
/// keeps it identical on Android, iOS and web: no temp files.
class RecordVoiceCapture implements VoiceCapture {
  RecordVoiceCapture({AudioRecorder? recorder}) : _recorder = recorder ?? AudioRecorder();

  static const sampleRate = 16000;

  final AudioRecorder _recorder;
  final _pcm = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _sub;
  StreamController<double>? _levels;

  @override
  Future<bool> requestPermission() => _recorder.hasPermission();

  @override
  Future<Stream<double>> start() async {
    await _reset();
    final levels = _levels = StreamController<double>.broadcast();
    final audio = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ));
    _sub = audio.listen((chunk) {
      _pcm.add(chunk);
      if (!levels.isClosed) levels.add(pcm16Level(chunk));
    });
    return levels.stream;
  }

  @override
  Future<VoiceClip?> stop() async {
    await _recorder.stop();
    await _sub?.cancel();
    _sub = null;
    await _levels?.close();
    final pcm = _pcm.takeBytes();
    if (pcm.isEmpty) return null;
    return VoiceClip(
      bytes: wavFromPcm16(pcm, sampleRate: sampleRate),
      mimeType: 'audio/wav',
      duration: Duration(microseconds: pcm.length ~/ 2 * 1000000 ~/ sampleRate),
    );
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
    await _reset();
  }

  Future<void> _reset() async {
    await _sub?.cancel();
    _sub = null;
    await _levels?.close();
    _levels = null;
    _pcm.clear();
  }

  @override
  Future<void> dispose() async {
    await _reset();
    await _recorder.dispose();
  }
}

/// Input level of a little-endian 16-bit PCM chunk, mapped from
/// -50..0 dBFS onto 0..1.
double pcm16Level(Uint8List chunk) {
  final n = chunk.length ~/ 2;
  if (n == 0) return 0;
  final data = ByteData.sublistView(chunk);
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final v = data.getInt16(i * 2, Endian.little) / 32768;
    sum += v * v;
  }
  final rms = math.sqrt(sum / n);
  if (rms <= 0) return 0;
  final db = 20 * math.log(rms) / math.ln10;
  return ((db + 50) / 50).clamp(0.0, 1.0);
}

/// Wraps mono 16-bit little-endian PCM in a WAV (RIFF) header.
Uint8List wavFromPcm16(Uint8List pcm, {required int sampleRate, int channels = 1}) {
  const bits = 16;
  final byteRate = sampleRate * channels * bits ~/ 8;
  final header = ByteData(44)
    ..setUint32(0, 0x52494646) // "RIFF"
    ..setUint32(4, 36 + pcm.length, Endian.little)
    ..setUint32(8, 0x57415645) // "WAVE"
    ..setUint32(12, 0x666d7420) // "fmt "
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, byteRate, Endian.little)
    ..setUint16(32, channels * bits ~/ 8, Endian.little)
    ..setUint16(34, bits, Endian.little)
    ..setUint32(36, 0x64617461) // "data"
    ..setUint32(40, pcm.length, Endian.little);
  return (BytesBuilder(copy: false)
        ..add(header.buffer.asUint8List())
        ..add(pcm))
      .takeBytes();
}
