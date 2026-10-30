import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app/settings_store.dart';
import 'recognizer_loop.dart';
import 'offline_speech.dart';
import 'speech_detector.dart';

export 'recognizer_loop.dart' show Heard;

/// 把 AI 的话慢慢念出来。可使用内置离线模型或系统语音合成。
class Speaker {
  Speaker() {
    _tts.setCompletionHandler(_done);
    _tts.setCancelHandler(_done);
    _tts.setErrorHandler((_) => _done());
  }

  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _player = AudioPlayer();
  int _generation = 0;
  Completer<void>? _localDone;
  Completer<void>? _speaking;
  bool _ready = false;

  Future<void> _prepare(double rate) async {
    if (!_ready) {
      await _tts.setLanguage('zh-CN');
      await _tts.awaitSpeakCompletion(true);
      if (Platform.isIOS) {
        // 播放和录音共用一个音频会话。否则念完再开始听时，系统识别会因为会话被占用而失败。
        await _tts.setSharedInstance(true);
        await _tts
            .setIosAudioCategory(IosTextToSpeechAudioCategory.playAndRecord, [
              IosTextToSpeechAudioCategoryOptions.defaultToSpeaker,
              IosTextToSpeechAudioCategoryOptions.allowBluetooth,
              IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
            ], IosTextToSpeechAudioMode.spokenAudio);
      }
      _ready = true;
    }
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(1.05);
  }

  /// 念完才返回。
  Future<void> say(
    String text, {
    required double rate,
    bool local = false,
  }) async {
    await stop();
    if (text.trim().isEmpty) return;
    if (local) {
      final generation = _generation;
      final done = Completer<void>();
      _localDone = done;
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/teacher_${DateTime.now().microsecondsSinceEpoch}.wav';
      StreamSubscription<void>? completion;
      try {
        await OfflineSpeech.instance.synthesize(
          forSpeech(text),
          path,
          (rate / 0.5).clamp(0.5, 1.6),
        );
        if (generation != _generation) return;
        completion = _player.onPlayerComplete.listen((_) {
          if (!done.isCompleted) done.complete();
        });
        await _player.play(DeviceFileSource(path));
        await done.future.timeout(const Duration(minutes: 3));
      } finally {
        await completion?.cancel();
        if (generation == _generation) await _player.stop();
        final file = File(path);
        if (await file.exists()) await file.delete();
        if (identical(_localDone, done)) _localDone = null;
      }
      return;
    }
    await _prepare(rate);
    _speaking = Completer<void>();
    await _tts.speak(forSpeech(text));
    // 部分平台 awaitSpeakCompletion 不生效，靠回调兜底，最长等 2 分钟。
    await _speaking?.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {},
    );
  }

  Future<void> stop() async {
    _generation++;
    if (_localDone case final done? when !done.isCompleted) done.complete();
    await _player.stop();
    if (_ready) await _tts.stop();
    _done();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }

  void _done() {
    if (_speaking != null && !_speaking!.isCompleted) _speaking!.complete();
  }

  /// 去掉念出来会很奇怪的符号。
  static String forSpeech(String s) => s
      .replaceAll(RegExp(r'[*#>`_|]'), '')
      .replaceAll('+', '加')
      .replaceAll('×', '乘')
      .replaceAll('÷', '除以')
      .replaceAll('=', '等于');
}

/// 听孩子说话。按设置选用系统识别或云端转写。
///
/// 每次 listen 都是一个独立的“回合”，用编号区分。旧回合迟到的回调一律忽略，
/// 这样不会出现上一回合的结束信号把这一回合提前结束，或者两回合互相等待卡死的情况。
class Listener {
  final SpeechToText _stt = SpeechToText();
  final AudioRecorder _recorder = AudioRecorder();
  bool _sttReady = false;

  int _round = 0;
  Completer<Heard>? _pending;
  Timer? _guard;
  StreamSubscription<Uint8List>? _pcm;
  BytesBuilder? _audio;
  Future<void> _vadPending = Future.value();
  String? _vadSession;
  bool _heardSpeech = false;
  Timer? _recordLimit;
  String _partial = '';
  RecognizerLoop? _loop;

  /// 正在听时实时回传已识别的文字（系统识别才有）。
  void Function(String partial)? onPartial;
  void Function()? onProcessing;

  bool get isActive => _pending != null && !_pending!.isCompleted;

  Future<bool> systemAvailable() async {
    if (_sttReady) return true;
    try {
      _sttReady = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    } catch (_) {
      _sttReady = false;
    }
    return _sttReady;
  }

  Future<Heard> listen(SettingsStore s) async {
    await cancel();
    final round = ++_round;
    _pending = Completer<Heard>();
    _partial = '';
    // 不管发生什么，最多 70 秒一定结束，不会一直处于录音状态。
    _guard = Timer(const Duration(seconds: 70), () {
      if (s.asrMode == AsrMode.local || s.asrMode == AsrMode.cloud) {
        unawaited(_stopRecording(round));
      } else {
        _resolve(round, Heard(_partial));
      }
    });

    switch (s.asrMode) {
      case AsrMode.local:
        unawaited(_startRecordingSafely(round, s));
      case AsrMode.system:
        unawaited(_startSystem(round, s));
      case AsrMode.cloud:
        unawaited(_startRecordingSafely(round, s));
      case AsrMode.off:
        _resolve(round, const Heard(''));
    }
    return _pending!.future;
  }

  /// 孩子说完了。保证在 1.5 秒内结束，即使识别服务没有回应。
  Future<void> finish() async {
    final round = _round;
    if (!isActive || _stoppingRound == round) return;
    _loop?.finish();
    if (await _recorder.isRecording()) {
      unawaited(_stopRecording(round));
      return; // 转写需要等待结果，由 _stopRecording 负责结束
    }
    if (_loop == null) _resolve(round, Heard(_partial));
  }

  Future<void> cancel() async {
    final round = _round;
    _loop?.abort();
    _loop = null;
    _resolve(round, const Heard(''));
    try {
      if (_stt.isListening) await _stt.cancel();
    } catch (_) {}
    try {
      if (await _recorder.isRecording()) await _recorder.cancel();
    } catch (_) {}
    await _pcm?.cancel();
    _pcm = null;
    _recordLimit?.cancel();
    final session = _vadSession;
    _vadSession = null;
    _audio = null;
    if (session != null) unawaited(OfflineSpeech.instance.endVad(session));
  }

  // ---- 系统识别 ----

  Future<void> _startSystem(int round, SettingsStore s) async {
    if (!await systemAvailable()) {
      _resolve(
        round,
        const Heard('', error: '这台设备没有可用的语音识别。可以到设置里改用“内置离线”，或者点键盘打字。'),
      );
      return;
    }
    // 念完马上开始听时，识别服务可能还没释放，稍等一下。
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (round != _round || !isActive) return;
    _loop = RecognizerLoop(
      pause: Duration(seconds: s.pauseSeconds),
      startSession: () => _stt.listen(
        onResult: (r) {
          if (round == _round) {
            _loop?.onResult(r.recognizedWords, isFinal: r.finalResult);
          }
        },
        listenOptions: SpeechListenOptions(
          localeId: 'zh_CN',
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          // 不传 pauseFor：插件从开始录音就计时，孩子还在想就会被结束。停顿由 RecognizerLoop 判断。
          listenFor: const Duration(seconds: 60),
        ),
      ),
      stopSession: () => _stt.stop(),
      cancelSession: () => _stt.cancel(),
      onText: (text) {
        _partial = text;
        onPartial?.call(text);
      },
      onDone: (heard) {
        _partial = heard.text;
        _resolve(round, heard);
      },
    )..begin();
  }

  void _onError(dynamic e) => _loop?.onError((e.errorMsg as String?) ?? '$e');

  void _onStatus(String status) => _loop?.onStatus(status);

  // ---- 云端转写 ----

  SettingsStore? _recordSettings;

  Future<void> _startRecordingSafely(int round, SettingsStore s) async {
    try {
      await _startRecording(round, s);
    } catch (e) {
      final session = _vadSession;
      if (session != null) unawaited(OfflineSpeech.instance.endVad(session));
      _resolve(round, Heard('', error: '无法开始录音：$e'));
    }
  }

  Future<void> _startRecording(int round, SettingsStore s) async {
    if (s.asrMode == AsrMode.cloud &&
        (s.asrBaseUrl.trim().isEmpty ||
            s.asrKey.trim().isEmpty ||
            s.asrModel.trim().isEmpty)) {
      _resolve(
        round,
        const Heard('', error: '云端转写还没有设置好，请家长到设置里填写地址、模型和 key。'),
      );
      return;
    }
    if (!await _recorder.hasPermission()) {
      _resolve(round, const Heard('', error: '没有麦克风权限，请在系统设置里允许。'));
      return;
    }
    if (round != _round || !isActive) return;
    final session = DateTime.now().microsecondsSinceEpoch.toString();
    await OfflineSpeech.instance.startVad(session, s.pauseSeconds);
    if (round != _round || !isActive) {
      await OfflineSpeech.instance.endVad(session);
      return;
    }
    _recordSettings = s;
    _vadSession = session;
    _heardSpeech = false;
    _audio = BytesBuilder(copy: true);
    _vadPending = Future.value();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        noiseSuppress: true,
      ),
    );
    if (round != _round || !isActive) {
      await _recorder.cancel();
      await OfflineSpeech.instance.endVad(session);
      return;
    }
    _pcm = stream.listen(
      (bytes) {
        if (round != _round || !isActive) return;
        _audio?.add(bytes);
        _vadPending = _vadPending
            .then((_) async {
              if (round != _round || !isActive) return;
              final state = await OfflineSpeech.instance.detectSpeech(
                session,
                bytes,
              );
              if (round != _round || !isActive) return;
              if (state != 'waiting') _heardSpeech = true;
              if (state == 'finished') unawaited(_stopRecording(round));
            })
            .catchError((Object e) {
              if (round == _round && isActive) {
                _resolve(round, Heard('', error: '语音检测失败，请重新点话筒：$e'));
                unawaited(cancel());
              }
            });
      },
      onError: (Object e) {
        if (round == _round && isActive) {
          unawaited(_stopRecording(round));
        }
      },
    );
    // 安全上限：没人说过话时只结束等待，绝不转写、提交空白录音。
    _recordLimit = Timer(
      const Duration(seconds: 60),
      () => unawaited(_stopRecording(round)),
    );
  }

  int? _stoppingRound;

  Future<void> _stopRecording(int round) async {
    if (_stoppingRound == round || round != _round || !isActive) return;
    _stoppingRound = round;
    final s = _recordSettings;
    final session = _vadSession;
    final audio = _audio;
    try {
      await _pcm?.cancel();
      _pcm = null;
      _recordLimit?.cancel();
      await _recorder.stop();
      await _vadPending;
      if (session != null) await OfflineSpeech.instance.endVad(session);
      if (round != _round || !isActive) return;
      if (!_heardSpeech || audio == null || s == null) {
        _resolve(round, const Heard('', error: '没有听到说话，想好了再点话筒。'));
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/child_$session.wav';
      await File(path).writeAsBytes(pcm16Wav(audio.takeBytes()));
      if (round == _round && isActive) onProcessing?.call();
      try {
        final text = s.asrMode == AsrMode.local
            ? await OfflineSpeech.instance.transcribe(path)
            : await _transcribe(File(path), s);
        _resolve(
          round,
          Heard(text, error: text.isEmpty ? '没听清，点话筒再说一次。' : null),
        );
      } catch (e) {
        _resolve(round, Heard('', error: '没听清，可以再说一遍，或者打字。（$e）'));
      } finally {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    } catch (e) {
      _resolve(round, Heard('', error: '录音未能完成，请再试一次：$e'));
    } finally {
      if (_stoppingRound == round) _stoppingRound = null;
    }
  }

  static Future<String> _transcribe(File audio, SettingsStore s) async {
    final base = s.asrBaseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final req =
        http.MultipartRequest('POST', Uri.parse('$base/audio/transcriptions'))
          ..headers['Authorization'] = 'Bearer ${s.asrKey.trim()}'
          ..fields['model'] = s.asrModel.trim()
          ..fields['language'] = 'zh'
          ..files.add(
            await http.MultipartFile.fromPath(
              'file',
              audio.path,
              filename: 'audio.wav',
            ),
          );
    final res = await http.Response.fromStream(
      await req.send().timeout(const Duration(seconds: 60)),
    );
    final body = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) throw 'HTTP ${res.statusCode}';
    final data = jsonDecode(body);
    return (data is Map ? data['text'] as String? : null)?.trim() ?? '';
  }

  void _resolve(int round, Heard h) {
    if (round != _round) return;
    final p = _pending;
    if (p == null || p.isCompleted) return;
    _guard?.cancel();
    p.complete(h);
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
