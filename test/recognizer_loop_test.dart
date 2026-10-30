import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/speech/recognizer_loop.dart';

/// 用很短的时间跑真实定时器，模拟安卓识别服务的行为。
class Rig {
  Rig({Duration pause = const Duration(milliseconds: 150)}) {
    loop = RecognizerLoop(
      pause: pause,
      maxListen: const Duration(milliseconds: 800),
      restartDelay: const Duration(milliseconds: 10),
      quickFail: const Duration(milliseconds: 30),
      stopGrace: const Duration(milliseconds: 60),
      endWatchdog: const Duration(milliseconds: 40),
      startSession: () async => starts++,
      stopSession: () async => stops++,
      cancelSession: () async {},
      onText: (t) => texts.add(t),
      onDone: (h) => heard = h,
    );
  }

  late final RecognizerLoop loop;
  int starts = 0, stops = 0;
  final texts = <String>[];
  Heard? heard;
}

Future<void> wait(int ms) => Future.delayed(Duration(milliseconds: ms));

void main() {
  test('孩子还没开口时，服务因静音结束：继续听，不结束', () async {
    final r = Rig()..loop.begin();
    await wait(50);
    r.loop.onError('error_speech_timeout');
    await wait(60);
    r.loop.onStatus('done');
    await wait(60);
    expect(r.heard, isNull);
    expect(r.starts, greaterThanOrEqualTo(2));
    r.loop.abort();
  });

  test('开口后安静够久才算说完，中途断开的文字累积起来', () async {
    final r = Rig()..loop.begin();
    await wait(50);
    r.loop.onResult('三十五', isFinal: true);
    await wait(50);
    expect(r.heard, isNull, reason: '第一段结束后还在等孩子接着说');
    r.loop.onResult('减十八', isFinal: false);
    await wait(100);
    expect(r.heard, isNull);
    await wait(150);
    r.loop.onResult('减十八', isFinal: true);
    expect(r.heard?.text, '三十五，减十八');
  });

  test('点停止：有结果马上结束；等不到结果也会结束', () async {
    final r = Rig()..loop.begin();
    await wait(50);
    r.loop.onResult('二十三', isFinal: false);
    r.loop.finish();
    expect(r.stops, 1);
    r.loop.onResult('二十三', isFinal: true);
    expect(r.heard?.text, '二十三');

    final r2 = Rig()..loop.begin();
    await wait(50);
    r2.loop.onResult('七', isFinal: false);
    r2.loop.finish();
    await wait(100);
    expect(r2.heard?.text, '七');
  });

  test('连续刚启动就结束：停止重试，并给出错误码', () async {
    final r = Rig()..loop.begin();
    for (var i = 0; i < 3 && r.heard == null; i++) {
      await wait(1);
      r.loop.onError('error_client');
      await wait(15);
    }
    expect(r.heard?.isEmpty, isTrue);
    expect(r.heard?.error, contains('error_client'));
  });

  test('致命错误马上告诉家长', () async {
    final r = Rig()..loop.begin();
    await wait(50);
    r.loop.onError('error_language_unavailable');
    expect(r.heard?.error, contains('不支持中文'));
  });

  test('一直没人说话，到上限结束并提示', () async {
    final r = Rig()..loop.begin();
    await wait(850);
    expect(r.heard?.isEmpty, isTrue);
    expect(r.heard?.error, contains('没有听到'));
  });

  test('启动抛异常也不会卡死', () async {
    late Heard h;
    var n = 0;
    RecognizerLoop(
      pause: const Duration(milliseconds: 50),
      restartDelay: const Duration(milliseconds: 5),
      quickFail: const Duration(milliseconds: 500),
      startSession: () async {
        n++;
        throw 'listen_failed';
      },
      stopSession: () async {},
      cancelSession: () async {},
      onText: (_) {},
      onDone: (x) => h = x,
    ).begin();
    await wait(100);
    expect(n, 3);
    expect(h.error, contains('listen_failed'));
  });
}
