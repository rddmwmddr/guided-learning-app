import 'dart:async';

/// 一次“听孩子说话”的结果。
class Heard {
  const Heard(this.text, {this.error});

  final String text;
  final String? error;

  bool get isEmpty => text.trim().isEmpty;
}

/// 用系统语音识别听完孩子的一次回答。
///
/// 系统识别服务不适合直接用来听孩子说话：安卓上静音几秒它就自己结束，想问题的孩子还没开口
/// 录音就停了。所以由这里掌握结束时机：
/// - 孩子开口之前一直等，识别服务中途结束就重启，直到 [maxListen]；
/// - 开口之后，安静满 [pause] 才算说完，中间断开也会接着听，文字累积起来；
/// - 点停止立刻结束；
/// - 连续几次刚启动就结束，说明这台手机的识别服务用不了，把错误码告诉家长，不再重试。
class RecognizerLoop {
  RecognizerLoop({
    required this.startSession,
    required this.stopSession,
    required this.cancelSession,
    required this.onText,
    required this.onDone,
    required this.pause,
    this.maxListen = const Duration(seconds: 60),
    this.restartDelay = const Duration(milliseconds: 400),
    this.quickFail = const Duration(seconds: 1),
    this.maxQuickFails = 3,
    this.stopGrace = const Duration(milliseconds: 1500),
    this.endWatchdog = const Duration(seconds: 3),
  });

  final Future<void> Function() startSession;
  final Future<void> Function() stopSession;
  final Future<void> Function() cancelSession;
  final void Function(String text) onText;
  final void Function(Heard heard) onDone;
  final Duration pause;
  final Duration maxListen;
  final Duration restartDelay;
  final Duration quickFail;
  final int maxQuickFails;
  final Duration stopGrace;
  final Duration endWatchdog;

  String _committed = '';
  String _current = '';
  bool _live = false;
  bool _finishing = false;
  bool _done = false;
  int _quickFails = 0;
  String _lastCode = '';
  DateTime _startedAt = DateTime.now();
  Timer? _silence, _max, _restart, _watchdog, _grace;

  String get text => [_committed, _current].where((s) => s.isNotEmpty).join('，');

  void begin() {
    _max = Timer(maxListen, () => _complete(emptyError: '没有听到声音。想好了再点话筒说，也可以点键盘打字。'));
    unawaited(_start());
  }

  Future<void> _start() async {
    if (_done || _finishing) return;
    _live = true;
    _startedAt = DateTime.now();
    try {
      await startSession();
    } catch (e) {
      _lastCode = '$e';
      _endSession();
    }
  }

  void onResult(String words, {required bool isFinal}) {
    if (_done) return;
    _current = words.trim();
    if (text.isNotEmpty) {
      onText(text);
      _silence?.cancel();
      _silence = Timer(pause, finish);
    }
    if (!isFinal) return;
    if (_current.isNotEmpty) {
      _committed = text;
      _current = '';
    }
    if (_finishing) {
      _complete();
    } else {
      _endSession();
    }
  }

  void onError(String code) {
    if (_done) return;
    _lastCode = code;
    if (_finishing) return _complete();
    if (_retryable.contains(code)) return _endSession();
    _complete(emptyError: _describe(code));
  }

  void onStatus(String status) {
    if (_done || !_live) return;
    if (status == 'done' || status == 'doneNoResult') {
      if (_finishing) return _complete();
      _endSession();
    } else if (status == 'notListening') {
      // 结果可能还在路上；等不到结束信号就当这一段结束了。
      _watchdog?.cancel();
      _watchdog = Timer(endWatchdog, _endSession);
    }
  }

  /// 说完了：点了停止，或者开口后安静够久。
  void finish() {
    if (_done || _finishing) return;
    _finishing = true;
    if (!_live) return _complete();
    unawaited(_safely(stopSession));
    _grace = Timer(stopGrace, _complete);
  }

  void abort() {
    _current = '';
    _committed = '';
    _complete();
  }

  void _endSession() {
    if (_done || !_live) return;
    _live = false;
    _watchdog?.cancel();
    if (_finishing) return _complete();

    final quick = DateTime.now().difference(_startedAt) < quickFail;
    _quickFails = quick ? _quickFails + 1 : 0;
    if (_quickFails >= maxQuickFails) {
      final code = _lastCode.isEmpty ? '无错误码' : _lastCode;
      return _complete(emptyError: '这台手机的语音识别用不了（$code）。请到设置里改用“云端转写”，或者点键盘打字。');
    }
    _restart?.cancel();
    _restart = Timer(restartDelay, () async {
      await _safely(cancelSession);
      await _start();
    });
  }

  void _complete({String? emptyError}) {
    if (_done) return;
    _done = true;
    _live = false;
    for (final t in [_silence, _max, _restart, _watchdog, _grace]) {
      t?.cancel();
    }
    unawaited(_safely(cancelSession));
    final result = text;
    onDone(Heard(result, error: result.isEmpty ? emptyError : null));
  }

  static Future<void> _safely(Future<void> Function() f) async {
    try {
      await f();
    } catch (_) {}
  }

  /// 这些错误只说明这一段没听到或服务暂时忙，重启就好。
  static const _retryable = {
    'error_no_match',
    'error_speech_timeout',
    'error_busy',
    'error_client',
    'error_server_disconnected',
  };

  static String _describe(String code) {
    final reason = switch (code) {
      'error_permission' => '没有麦克风权限，请在系统设置里允许',
      'error_network' || 'error_network_timeout' => '语音识别需要联网，但连不上它的服务',
      'error_language_not_supported' || 'error_language_unavailable' => '这台手机的语音识别不支持中文',
      'error_audio_error' => '麦克风被占用或者打不开',
      _ => '语音识别出错',
    };
    return '$reason（$code）。可以到设置里改用“云端转写”，或者点键盘打字。';
  }
}
