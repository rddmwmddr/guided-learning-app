// 检查“照片直接交给老师”是否可用：老师能否看懂图，并且不直接给答案。
//   OPENROUTER_API_KEY=... dart run tool/image_check.dart 图片路径
import 'dart:convert';
import 'dart:io';

import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';

Future<void> main(List<String> args) async {
  final key = Platform.environment['OPENROUTER_API_KEY'] ?? '';
  final client = LlmClient(ModelConfig(
    baseUrl: 'https://openrouter.ai/api/v1',
    apiKey: key,
    model: args.length > 1 ? args[1] : 'deepseek/deepseek-v4.1-flash',
    thinkingStyle: ThinkingStyle.openrouter,
  ));
  final engine = TutorEngine(
    client: client,
    basePrompt: File('assets/prompts/小学-数学.md').readAsStringSync(),
    material: LessonMaterial(images: [ChatImage(base64Encode(File(args.first).readAsBytesSync()))]),
  );
  var t = await engine.start();
  stdout.writeln('老师：${t.text}');
  for (final kid in ['苹果有7个', '梨有4个吧', '用加法？7加4等于11']) {
    stdout.writeln('孩子：$kid');
    t = await engine.childSays(kid);
    stdout.writeln('老师：${t.text}');
  }
  await engine.settled();
  stdout.writeln('\n记录：\n${engine.record.render()}');
  client.close();
}
