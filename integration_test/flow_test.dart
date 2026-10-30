// 端到端走一遍：首次确认 → 填 key → 选学科 → 填材料 → 孩子打字回答 → 老师回应。
// 接真实模型，需要传入 key：
//   flutter test integration_test/flow_test.dart -d macos \
//     --dart-define=BASE_URL=https://openrouter.ai/api/v1 --dart-define=MODEL=deepseek/deepseek-v4.1-flash \
//     --dart-define=THINKING_STYLE=openrouter --dart-define=API_KEY=sk-...
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:manmanxiang/app/settings_store.dart';
import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';
import 'package:manmanxiang/main.dart';
import 'package:manmanxiang/ui/transcript_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

const apiKey = String.fromEnvironment('API_KEY');
const baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://api.deepseek.com');
const model = String.fromEnvironment('MODEL', defaultValue: 'deepseek-flash');
const pause = bool.fromEnvironment('PAUSE');
const thinkingStyle = String.fromEnvironment('THINKING_STYLE', defaultValue: 'deepseek');

Future<void> waitFor(WidgetTester t, Finder f, {int seconds = 120}) async {
  final end = DateTime.now().add(Duration(seconds: seconds));
  while (DateTime.now().isBefore(end)) {
    await t.pump(const Duration(milliseconds: 500));
    if (f.evaluate().isNotEmpty) return;
  }
  throw TestFailure('等了 $seconds 秒仍没出现：$f');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('完整走一遍', (t) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsStore.load();
    await settings.wipe();
    await t.pumpWidget(ManmanxiangApp(settings: settings));
    await t.pumpAndSettle();

    // 1. 首次确认：四项都勾上才能继续
    expect(find.text('我已确认，开始使用'), findsOneWidget);
    for (final box in find.byType(Checkbox).evaluate().toList()) {
      await t.tap(find.byWidget(box.widget));
    }
    await t.pump();
    await t.tap(find.text('我已确认，开始使用'));
    await t.pumpAndSettle();
    expect(find.text('今天学什么？'), findsOneWidget);
    expect(find.text('还没有填写 API key'), findsOneWidget);

    // 2. 填 key（直接写入设置，等同于家长在设置页填写）
    settings
      ..apiKey = apiKey
      ..baseUrl = baseUrl
      ..model = model
      ..thinkingStyle = ThinkingStyle.values.byName(thinkingStyle)
      ..asrMode = AsrMode.off
      ..speechRate = 0.8;
    await settings.save();
    await t.pumpAndSettle();
    expect(find.text('还没有填写 API key'), findsNothing);

    // 3. 选小学数学，填材料
    await t.tap(find.text('小学数学'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, '小明有35张贴纸，送给同学18张，又买来12张，现在小明有多少张贴纸？');
    await t.tap(find.text('开始，把手机交给孩子'));
    await t.pump();

    // 4. 等老师开口
    await waitFor(t, find.textContaining('想好了就打字回答'));
    final first = find.byWidgetPredicate((w) => w is Text && (w.data?.contains('？') ?? false));
    expect(first, findsWidgets);

    // 5. 孩子打字回答一个错的
    await t.enterText(find.byType(TextField).last, '35减18等于23');
    await t.tap(find.byIcon(Icons.send).last);
    await t.pump();
    await waitFor(t, find.textContaining('老师在想'), seconds: 10);
    await waitFor(t, find.textContaining('想好了就打字回答'));

    if (pause) await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 8)));
    // 6. 对话气泡里能看到全部历史；老师没把 23 说成对
    expect(find.text('35减18等于23'), findsOneWidget);
    final bubbles = find.byType(Bubble);
    final texts = [
      for (final e in bubbles.evaluate())
        if ((e.widget as Bubble).turn.speaker == Speaker.tutor) (e.widget as Bubble).turn.text,
    ];
    // ignore: avoid_print
    print('老师说的话：\n${texts.join('\n')}');
    expect(texts.length, greaterThanOrEqualTo(2));

    // 7. 家长面板能看到进度记录
    await t.tap(find.text('家长'));
    await t.pumpAndSettle();
    expect(find.text('学习进度（AI 整理，孩子看不到）'), findsOneWidget);
    expect(find.textContaining('要解决的'), findsOneWidget);
    if (pause) await t.runAsync(() => Future<void>.delayed(const Duration(seconds: 6)));
    await t.tapAt(const Offset(10, 10));
    await t.pumpAndSettle();

    // 8. 回首页后，对话记录里有这次学习
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('对话记录'));
    await t.pumpAndSettle();
    expect(find.textContaining('小学数学'), findsWidgets);
    expect(texts.last.contains('23') && texts.last.contains('对了'), isFalse, reason: '不该把错答案说成对');
    expect(texts.join().contains('（家长'), isFalse);
  });
}
