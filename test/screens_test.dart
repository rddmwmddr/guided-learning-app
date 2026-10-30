// 渲染主要界面并保存成图片，检查布局有没有溢出。不是自动化回归测试，只在需要看界面时运行：
//   flutter test test/screens_test.dart --update-goldens
@Tags(['screens'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/app/prompt_library.dart';
import 'package:manmanxiang/app/session_controller.dart';
import 'package:manmanxiang/app/settings_store.dart';
import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';
import 'package:manmanxiang/ui/guardian_gate.dart';
import 'package:manmanxiang/ui/home_page.dart';
import 'package:manmanxiang/ui/session_page.dart';
import 'package:manmanxiang/ui/history_page.dart';
import 'package:manmanxiang/ui/settings_page.dart';
import 'package:manmanxiang/ui/setup_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeClient extends LlmClient {
  FakeClient(this.reply) : super(const ModelConfig(baseUrl: 'x', apiKey: 'k', model: 'm'));
  final String reply;
  @override
  Future<String> complete(List<ChatMessage> messages, {bool? thinking, int maxTokens = 4000}) async => reply;
}

Future<void> loadFonts() async {
  const path = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
  if (!File(path).existsSync()) return;
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader('Roboto')..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
  final icons = File('${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l2 = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.view(icons.readAsBytesSync().buffer)));
    await l2.load();
  }
}

Widget wrap(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F8F6B)), useMaterial3: true),
      home: child,
    );

class _Seq extends LlmClient {
  _Seq(this.replies) : super(const ModelConfig(baseUrl: 'x', apiKey: 'k', model: 'm'));
  final List<String> replies;
  @override
  Future<String> complete(List<ChatMessage> messages, {bool? thinking, int maxTokens = 4000}) async => replies.removeAt(0);
}

void main() {
  late SettingsStore settings;

  setUpAll(loadFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage_mock();
    settings = await SettingsStore.load();
  });

  Future<void> shoot(WidgetTester tester, Widget w, String name) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    await tester.pumpWidget(wrap(w));
    await tester.pump(const Duration(milliseconds: 300));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/$name.png'));
  }

  testWidgets('首次确认', (t) => shoot(t, GuardianGate(settings: settings), '1_guardian'));
  testWidgets('首页', (t) => shoot(t, HomePage(settings: settings), '2_home'));
  testWidgets('家长准备', (t) => shoot(t, SetupPage(settings: settings, entry: promptLibrary.first), '3_setup'));
  testWidgets('设置', (t) => shoot(t, SettingsPage(settings: settings), '5_settings'));

  testWidgets('学习中', (t) async {
    // 语音插件在测试里没有实现，全部假装成功。
    for (final ch in ['flutter_tts', 'plugin.csdcorp.com/speech_to_text', 'com.llfbandit.record/messages']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(ch), (call) async => call.method == 'initialize' ? false : 1);
    }
    settings.asrMode = AsrMode.off;
    final replies = [
      '你好呀，我们一起来看这道贴纸的题。小明一开始有多少张贴纸？',
      '对，一开始是35张。送给同学18张以后，贴纸是变多了还是变少了？',
      '你算得挺快。那这个23，你是怎么算出来的，跟我说说？',
    ];
    final engine = TutorEngine(
      client: _Seq(replies),
      recorder: FakeClient('<记录>\n原题要解决的：算出小明现在有多少张贴纸\n已经确认的：一开始有35张\n现在的小目标：检查35减18\n卡点：无\n提示级别：1\n是否完成：否\n</记录>'),
      basePrompt: 'p',
      material: const LessonMaterial(content: '小明有35张贴纸，送给同学18张，又买来12张，现在小明有多少张贴纸？'),
    );
    final c = SessionController(settings: settings, engine: engine, title: '小学数学');
    await t.runAsync(() async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      await t.pumpWidget(wrap(SessionPage(controller: c, title: '小学数学')));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await c.childSays('35张');
      await c.childSays('35减18等于23');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await t.pump(const Duration(milliseconds: 400));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('screens/4_session.png'));
  });

  testWidgets('对话记录', (t) => shoot(t, const HistoryPage(), '6_history'));
}

// flutter_secure_storage 在测试环境没有平台实现，读写会抛异常；SettingsStore 已经兜底，这里什么都不用做。
// ignore: non_constant_identifier_names
void FlutterSecureStorage_mock() {}
