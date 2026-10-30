import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/llm_client.dart';
import '../core/tutor_engine.dart';
import '../speech/speech_io.dart' as io;
import 'history_store.dart';
import 'settings_store.dart';

enum Phase {
  /// 老师在想。
  thinking,

  /// 老师在说话。
  speaking,

  /// 在听孩子说话。
  listening,

  /// 等孩子开口（没有自动听，或者没听清）。
  waiting,

  /// 这次学习结束了。
  finished,

  /// 出错了，可以重试。
  error,
}

/// 一次学习的回合制流程：老师想 → 念给孩子听 → 听孩子说 → 再交给老师。
class SessionController extends ChangeNotifier {
  SessionController({
    required this.settings,
    required this.engine,
    required this.title,
    this.history,
    this.archiveId,
    this.imagePaths = const [],
    DateTime? originalStartedAt,
  }) : startedAt = originalStartedAt ?? DateTime.now(),
       _speaker = io.Speaker(),
       _listener = io.Listener() {
    _listener.onPartial = (text) {
      partial = text;
      notifyListeners();
    };
    _listener.onProcessing = () {
      if (!_disposed && phase == Phase.listening) {
        transcribing = true;
        notifyListeners();
      }
    };
    _clock = Timer.periodic(const Duration(seconds: 15), (_) => _checkTime());
  }

  final SettingsStore settings;
  final TutorEngine engine;
  final String title;

  /// 本机存档。为空时不保存（测试用）。
  final HistoryStore? history;
  final String? archiveId;
  final List<String> imagePaths;
  final io.Speaker _speaker;
  final io.Listener _listener;
  late final Timer _clock;
  final DateTime startedAt;
  final DateTime _activeSince = DateTime.now();

  Phase phase = Phase.thinking;
  String? error;

  /// 正在听时识别到的文字。
  String partial = '';
  bool transcribing = false;

  /// 到了建议时长，提醒家长。
  bool timeUp = false;

  /// 已经自动请老师收尾过一次。
  bool _wrapUpSent = false;

  bool _disposed = false;
  int _tutorTurnsAtResume = 0;

  /// 超过这么多轮还没结束，自动请老师收尾。实测孩子已经学会后，模型仍可能反复复查。
  static const maxTutorTurns = 18;

  List<Turn> get turns => engine.history;

  Future<void> begin() async {
    if (engine.history.isEmpty) {
      await _run(engine.start);
    } else {
      // 回到上次停下的位置，等孩子回答；不重复开场，也不自动花费 API 额度。
      _tutorTurnsAtResume = engine.history
          .where((t) => t.speaker == Speaker.tutor)
          .length;
      if (engine.history.last.speaker != Speaker.tutor) {
        _fail('上次老师还没来得及回答，可以点“重试”接着聊。');
      } else {
        _set(Phase.waiting);
      }
    }
  }

  /// 孩子打字或说完的话。
  Future<void> childSays(String text) async {
    if (text.trim().isEmpty || phase == Phase.thinking) return;
    await _stopAudio();
    await _run(() => engine.childSays(text));
  }

  /// 家长插话：可以是自由输入，也可以是“拉回”“收尾”。
  Future<void> parentSays(String text) async {
    if (text.trim().isEmpty || phase == Phase.thinking) return;
    await _stopAudio();
    await _run(() => engine.parentSays(text));
  }

  Future<void> nudge() => parentSays(defaultNudge);

  Future<void> wrapUp() {
    _wrapUpSent = true;
    return parentSays(wrapUpNudge);
  }

  /// 再念一遍老师刚才的话。
  Future<void> repeat() async {
    final last = engine.history.lastWhere(
      (t) => t.speaker == Speaker.tutor,
      orElse: () => const Turn(Speaker.tutor, ''),
    );
    if (last.text.isEmpty) return;
    await _listener.cancel();
    await _speakThenListen(last.text);
  }

  /// 点麦克风：没在听就开始听，在听就算说完。
  Future<void> toggleListening() async {
    if (phase == Phase.listening) {
      await _listener.finish();
    } else if (phase == Phase.waiting || phase == Phase.speaking) {
      await _speaker.stop();
      await _listen();
    }
  }

  Future<void> retry() async {
    final lastSpeaker = engine.history.isEmpty
        ? null
        : engine.history.last.speaker;
    if (lastSpeaker == Speaker.tutor) {
      _set(Phase.waiting);
    } else if (engine.history.isEmpty) {
      await begin();
    } else {
      // 最后一句是孩子或家长说的，老师还没回答：重新请老师回答。
      final last = engine.history.removeLast();
      await _run(
        () => last.speaker == Speaker.parent
            ? engine.parentSays(last.text)
            : engine.childSays(last.text),
      );
    }
  }

  Future<void> _run(Future<Turn> Function() ask) async {
    _set(Phase.thinking);
    error = null;
    try {
      final response = ask();
      unawaited(_archive());
      final turn = await response;
      unawaited(_archive());
      if (_disposed) return;
      await _speakThenListen(turn.text);
    } on LlmException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('出了点问题：$e');
    }
  }

  Future<void> _speakThenListen(String text) async {
    _set(Phase.speaking);
    await _speaker.say(
      text,
      rate: settings.speechRate,
      local: settings.localTts,
    );
    if (_disposed || phase != Phase.speaking) return;

    // 念完再看记录。老师开始收尾后，再给孩子一次回应的机会，下一轮就结束。
    await engine.settled();
    if (_closing < 0 && (engine.finished || _wrapUpSent)) {
      _closing = 0;
    } else if (_closing >= 0) {
      _closing++;
    }
    if (_closing >= 1) {
      _set(Phase.finished);
      unawaited(_archive());
      return;
    }
    final tutorTurns = engine.history
        .where((t) => t.speaker == Speaker.tutor)
        .length;
    if (!_wrapUpSent && tutorTurns - _tutorTurnsAtResume >= maxTutorTurns) {
      unawaited(wrapUp());
      return;
    }
    if (settings.autoListen && settings.asrMode != AsrMode.off) {
      await _listen();
    } else {
      _set(Phase.waiting);
    }
  }

  /// -1 表示还没开始收尾；0 表示老师刚收尾，等孩子最后说一句；1 表示结束。
  int _closing = -1;

  /// 家长觉得还没学完，取消收尾，接着学。
  Future<void> continueLesson() async {
    _closing = -1;
    _wrapUpSent = false;
    await parentSays('（家长）孩子还想接着学，请继续，从刚才的地方往下走。');
  }

  Future<void> _listen() async {
    partial = '';
    transcribing = false;
    error = null;
    _set(Phase.listening);
    final heard = await _listener.listen(settings);
    if (_disposed || phase != Phase.listening) return;
    if (heard.isEmpty) {
      error = heard.error;
      _set(Phase.waiting);
      return;
    }
    await _run(() => engine.childSays(heard.text));
  }

  Future<void> _archive() async {
    final h = history, id = archiveId;
    if (h == null || id == null) return;
    await engine.settled();
    try {
      await h.save(
        SessionArchive(
          id: id,
          title: title,
          startedAt: startedAt,
          content: engine.material.content,
          note: engine.material.note,
          imagePaths: imagePaths,
          turns: List.of(engine.history),
          record: engine.record.isEmpty ? '' : engine.record.render(),
          finished: phase == Phase.finished || engine.finished,
          basePrompt: engine.basePrompt,
        ),
      );
    } catch (_) {
      // 存档失败不影响学习。
    }
  }

  void _checkTime() {
    if (timeUp || _disposed) return;
    if (DateTime.now().difference(_activeSince).inMinutes >=
        settings.sessionMinutes) {
      timeUp = true;
      notifyListeners();
    }
  }

  Future<void> _stopAudio() async {
    await _speaker.stop();
    await _listener.cancel();
  }

  void _fail(String message) {
    error = message;
    _set(Phase.error);
  }

  void _set(Phase p) {
    if (_disposed) return;
    phase = p;
    if (p != Phase.listening) transcribing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _clock.cancel();
    _speaker.dispose();
    _listener.dispose();
    engine.client.close();
    if (!identical(engine.recorder, engine.client)) engine.recorder.close();
    super.dispose();
  }
}
