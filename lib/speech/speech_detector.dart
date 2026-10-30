import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 16 kHz 单声道 PCM16 的本地语音活动检测。必须先初始化 sherpa bindings。
class SpeechDetector {
  SpeechDetector(String model, double pauseSeconds)
    : _vad = sherpa.VoiceActivityDetector(
        config: sherpa.VadModelConfig(
          sileroVad: sherpa.SileroVadModelConfig(
            model: model,
            minSilenceDuration: pauseSeconds,
            minSpeechDuration: 0.25,
            maxSpeechDuration: 65,
          ),
          numThreads: 1,
          debug: false,
        ),
        bufferSizeInSeconds: 75,
      );

  final sherpa.VoiceActivityDetector _vad;
  int? _lastByte;
  bool heardSpeech = false;

  /// waiting：没开口；speech：曾经开口；finished：开口后连续静音到点。
  String accept(Uint8List bytes) {
    final data = _lastByte == null
        ? bytes
        : (Uint8List(bytes.length + 1)
            ..[0] = _lastByte!
            ..setRange(1, bytes.length + 1, bytes));
    _lastByte = data.length.isOdd ? data.last : null;
    final raw = ByteData.sublistView(data);
    final samples = Float32List(data.length ~/ 2);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = raw.getInt16(i * 2, Endian.little) / 32768;
    }
    if (samples.isNotEmpty) _vad.acceptWaveform(samples);
    heardSpeech |= _vad.isDetected() || !_vad.isEmpty();
    if (!_vad.isEmpty()) {
      while (!_vad.isEmpty()) {
        _vad.pop();
      }
      return 'finished';
    }
    return heardSpeech ? 'speech' : 'waiting';
  }

  void dispose() => _vad.free();
}

/// 将录音流封装为标准 WAV，供本地或云端转写；不会丢失开头或句中停顿。
Uint8List pcm16Wav(Uint8List pcm) {
  final result = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(result);
  void ascii(int offset, String value) =>
      result.setRange(offset, offset + value.length, value.codeUnits);
  ascii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, 16000, Endian.little);
  header.setUint32(28, 32000, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  result.setRange(44, result.length, pcm);
  return result;
}
