import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'speech_detector.dart';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// 模型随应用安装。FFI 推理在独立 isolate 中运行，避免阻塞界面和录音。
class OfflineSpeech {
  OfflineSpeech._();
  static final instance = OfflineSpeech._();
  Future<SendPort>? _worker;
  final Map<int, Completer<String>> _pending = {};
  int _nextId = 0;

  Future<SendPort> _start() async {
    final root = Directory(
      '${(await getApplicationSupportDirectory()).path}/speech-v1',
    );
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final asset in manifest.listAssets().where(
      (p) => p.startsWith('assets/speech/'),
    )) {
      final target = File(
        '${root.path}/${asset.substring('assets/speech/'.length)}',
      );
      if (await target.exists()) continue;
      await target.parent.create(recursive: true);
      final bytes = await rootBundle.load(asset);
      final temp = File('${target.path}.tmp');
      await temp.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
      await temp.rename(target.path);
    }
    final ready = Completer<SendPort>();
    final responses = ReceivePort();
    responses.listen((dynamic message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is List) {
        final completer = _pending.remove(message[0]);
        if (message[1] == true) {
          completer?.complete(message[2] as String);
        } else {
          completer?.completeError(StateError(message[2] as String));
        }
      }
    });
    await Isolate.spawn(_speechWorker, [root.path, responses.sendPort]);
    return ready.future;
  }

  Future<String> _request(
    String kind,
    Object input, {
    String output = '',
    double speed = 1,
  }) async {
    final worker = await (_worker ??= _start().catchError((Object e) {
      _worker = null;
      throw e;
    }));
    final id = ++_nextId;
    final result = Completer<String>();
    _pending[id] = result;
    worker.send([id, kind, input, output, speed]);
    return result.future;
  }

  Future<String> startVad(String session, int pauseSeconds) =>
      _request('vadStart', session, speed: pauseSeconds.toDouble());
  Future<String> detectSpeech(String session, Uint8List pcm) =>
      _request('vad', pcm, output: session);
  Future<String> endVad(String session) => _request('vadEnd', session);

  Future<String> transcribe(String wav) => _request('asr', wav);
  Future<String> synthesize(String text, String output, double speed) =>
      _request('tts', text, output: output, speed: speed);
}

void _speechWorker(List<dynamic> args) {
  final root = args[0] as String;
  final responses = args[1] as SendPort;
  final requests = ReceivePort();
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineTts? tts;
  bool initialized = false;
  SpeechDetector? detector;
  String? vadSession;
  responses.send(requests.sendPort);
  requests.listen((dynamic request) {
    final r = request as List;
    try {
      if (!initialized) {
        sherpa.initBindings();
        initialized = true;
      }
      String result;
      if (r[1] == 'vadStart') {
        detector?.dispose();
        detector = null;
        vadSession = r[2] as String;
        detector = SpeechDetector('$root/vad/silero_vad.onnx', r[4] as double);
        result = 'ready';
      } else if (r[1] == 'vad') {
        result = vadSession == r[3] && detector != null
            ? detector!.accept(r[2] as Uint8List)
            : 'waiting';
      } else if (r[1] == 'vadEnd') {
        if (vadSession == r[2]) {
          detector?.dispose();
          detector = null;
          vadSession = null;
        }
        result = 'done';
      } else if (r[1] == 'asr') {
        recognizer ??= sherpa.OfflineRecognizer(
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
        final wave = sherpa.readWave(r[2] as String);
        if (wave.samples.isEmpty) throw StateError('录音内容为空');
        final stream = recognizer!.createStream();
        try {
          stream.acceptWaveform(
            samples: wave.samples,
            sampleRate: wave.sampleRate,
          );
          recognizer!.decode(stream);
          result = recognizer!.getResult(stream).text.trim();
        } finally {
          stream.free();
        }
      } else {
        tts ??= sherpa.OfflineTts(
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
            ruleFsts:
                '$root/tts/phone.fst,$root/tts/date.fst,$root/tts/number.fst',
            maxNumSentences: 1,
          ),
        );
        final audio = tts!.generate(
          text: r[2] as String,
          sid: 0,
          speed: r[4] as double,
        );
        if (audio.samples.isEmpty ||
            !sherpa.writeWave(
              filename: r[3] as String,
              samples: audio.samples,
              sampleRate: audio.sampleRate,
            )) {
          throw StateError('没有生成可播放的语音');
        }
        result = r[3] as String;
      }
      responses.send([r[0], true, result]);
    } catch (e) {
      responses.send([r[0], false, e.toString()]);
    }
  });
}
