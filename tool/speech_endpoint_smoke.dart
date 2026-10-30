// dart run tool/speech_endpoint_smoke.dart /path/to/sherpa_onnx_macos/macos /path/to/16k-mandarin.wav
import 'dart:io';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../lib/speech/speech_detector.dart';

void main(List<String> args) {
  sherpa.initBindings(args[0]);
  final model = '${Directory.current.path}/assets/speech/vad/silero_vad.onnx';
  final wave = sherpa.readWave(args[1]);
  if (wave.sampleRate != 16000) throw StateError('sample must be 16k');
  final pcm = Uint8List(wave.samples.length * 2);
  final bytes = ByteData.sublistView(pcm);
  for (var i = 0; i < wave.samples.length; i++) {
    bytes.setInt16(
      i * 2,
      (wave.samples[i] * 32767).round().clamp(-32768, 32767),
      Endian.little,
    );
  }
  bool feed(SpeechDetector detector, Uint8List data) {
    var finished = false;
    for (var i = 0; i < data.length; i += 1024) {
      if (detector.accept(
            Uint8List.sublistView(data, i, (i + 1024).clamp(0, data.length)),
          ) ==
          'finished')
        finished = true;
    }
    return finished;
  }

  void check(bool value, String label) {
    if (!value) throw StateError(label);
    print('PASS $label');
  }

  var detector = SpeechDetector(model, 4);
  try {
    check(
      !feed(detector, Uint8List(32000 * 20)) && !detector.heardSpeech,
      '20 seconds silence never submits',
    );
    final noise = Uint8List(3200); // 100 ms 高音量脉冲不是一句话。
    final n = ByteData.sublistView(noise);
    for (var i = 0; i < noise.length ~/ 2; i++) {
      n.setInt16(i * 2, i.isEven ? 16000 : -16000, Endian.little);
    }
    check(
      !feed(detector, noise) &&
          !feed(detector, Uint8List(32000 * 5)) &&
          !detector.heardSpeech,
      'brief noise never submits',
    );
  } finally {
    detector.dispose();
  }
  detector = SpeechDetector(model, 4);
  try {
    feed(detector, pcm);
    check(detector.heardSpeech, 'real Mandarin speech detected');
    check(!feed(detector, Uint8List(32000)), 'short pause does not submit');
    feed(detector, pcm);
    check(!feed(detector, Uint8List(32000)), 'speaking again resets silence');
    check(
      feed(detector, Uint8List(32000 * 4)),
      'speech followed by configured silence submits',
    );
  } finally {
    detector.dispose();
  }
  final file = File('${Directory.systemTemp.path}/guided-pcm-check.wav');
  try {
    file.writeAsBytesSync(pcm16Wav(pcm));
    final decoded = sherpa.readWave(file.path);
    check(
      decoded.sampleRate == 16000 &&
          decoded.samples.length == wave.samples.length,
      'recording stream WAV is readable without losing samples',
    );
  } finally {
    file.deleteSync();
  }
}
