// 本机验证模型与原生库兼容：dart run tool/offline_speech_smoke.dart /path/to/sherpa_onnx_macos/macos
import 'dart:io';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

void main(List<String> args) {
  sherpa.initBindings(args.single);
  final root = '${Directory.current.path}/assets/speech';
  final tts = sherpa.OfflineTts(
    sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: '$root/tts/model.onnx',
          lexicon: '$root/tts/lexicon.txt',
          tokens: '$root/tts/tokens.txt',
        ),
        numThreads: 2,
        debug: false,
      ),
      ruleFsts: '$root/tts/phone.fst,$root/tts/date.fst,$root/tts/number.fst',
    ),
  );
  final recognizer = sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(
          model: '$root/asr/model.int8.onnx',
        ),
        tokens: '$root/asr/tokens.txt',
        numThreads: 2,
        debug: false,
      ),
    ),
  );
  final clock = Stopwatch()..start();
  try {
    final audio = tts.generate(
      text: '我们先来想一想，三十五减去十八等于多少？',
      sid: 0,
      speed: 0.84,
    );
    if (audio.samples.isEmpty) throw StateError('TTS 没有生成声音');
    print(
      'TTS: ${audio.samples.length} samples, ${audio.sampleRate} Hz, ${clock.elapsedMilliseconds} ms',
    );
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
      recognizer.decode(stream);
      final result = recognizer.getResult(stream).text;
      print('STT: $result (${clock.elapsedMilliseconds} ms total)');
      if (!result.contains('三十五') || !result.contains('十八'))
        throw StateError('中文离线回环识别失败');
    } finally {
      stream.free();
    }
  } finally {
    tts.free();
    recognizer.free();
  }
}
