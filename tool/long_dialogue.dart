// 长对话对照实验：同一个模拟孩子，分别用“粘贴提示词”和“本应用的进度记录”两种方式对话，
// 比较 20 轮之后 AI 还记不记得在解决什么。
//
// 用法（需要 OpenRouter key）：
//   OPENROUTER_API_KEY=sk-or-... dart run tool/long_dialogue.dart --mode record --scenario math-g2 --turns 20
//   --mode paste  对照组：不加记录、不截断，等同于把提示词粘贴进 App
//
// 结果写到 tool/out/（不提交）。这是给维护者用的，家长不需要。
import 'dart:io';

import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';

const scenarios = {
  'math-g2': (
    prompt: '小学-数学.md',
    material: LessonMaterial(
      content: '小明有35张贴纸，送给同学18张，又买来12张，现在小明有多少张贴纸？',
      note: '二年级，他总是做错，想让他自己弄明白',
    ),
    child: '二年级，7 岁，反应比较慢。退位减法不熟：35 减 18 会算成 23，借位要被提醒好几次才明白。'
        '注意力不集中，每隔几轮会答非所问或者说“我忘了刚才问的啥”。会说一次“你直接告诉我吧”。'
        '弄懂一步后，下一步又容易忘记上一步算出的数。',
  ),
  'math-g5': (
    prompt: '小学-数学.md',
    material: LessonMaterial(
      content: '把一根3米长的绳子平均剪成4段，每段长几分之几米？每段占全长的几分之几？孩子两个空都写的是3/4。',
      note: '五年级，孩子做错了，想让他自己分清两问',
    ),
    child: '五年级，11 岁。分不清“每段长多少米”和“每段占全长几分之几”，很固执，说了好几次“反正就是3除以4”。'
        '需要画图或具体例子才肯改，改过一次后过几轮又会混。偶尔会走神问别的。',
  ),
  'sci-g3': (
    prompt: '小学-科学.md',
    material: LessonMaterial(
      note: '三年级',
      content: '把冰块放进玻璃杯，过一会儿杯子外面出现了小水珠。小水珠是从哪里来的？',
    ),
    child: '三年级，9 岁。坚信水是从杯子里渗出来的。家里有杯子和冰箱，可以动手试，但会把观察结果说得含糊。'
        '要有能对比的证据才改变想法；改变后还会问“那空气里为什么有水”。',
  ),
};

String childSystem(String persona) => '你在一项测试中扮演一个中国孩子，和一位 AI 老师对话。只输出孩子说的话，不加引号、动作描写或解释。\n'
    '孩子：$persona\n'
    '说话像真实的孩子：很短、口语、偶尔不完整。不要比这个年龄更聪明。AI 一次问好几个问题时，只回答其中一个或答得含糊。'
    '不要主动说出正确答案，除非 AI 的引导确实让这个年龄的孩子能想到。';

Future<void> main(List<String> args) async {
  String arg(String name, String fallback) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
  }

  final key = Platform.environment['OPENROUTER_API_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('请设置 OPENROUTER_API_KEY');
    exit(1);
  }
  final mode = arg('mode', 'record');
  final id = arg('scenario', 'math-g2');
  final turns = int.parse(arg('turns', '20'));
  final model = arg('model', 'deepseek/deepseek-v4.1-flash');
  final sc = scenarios[id]!;

  final tutor = LlmClient(ModelConfig(
    baseUrl: 'https://openrouter.ai/api/v1',
    apiKey: key,
    model: model,
    thinking: true,
    thinkingStyle: ThinkingStyle.openrouter,
  ));
  final kid = LlmClient(ModelConfig(
    baseUrl: 'https://openrouter.ai/api/v1',
    apiKey: key,
    model: arg('sim', 'xiaomi/mimo-v2.6-pro'),
    thinking: false,
    thinkingStyle: ThinkingStyle.openrouter,
  ));

  final prompt = File('assets/prompts/${sc.prompt}').readAsStringSync();
  final engine = TutorEngine(client: tutor, basePrompt: prompt, material: sc.material, useRecord: mode == 'record');

  final out = StringBuffer('# $id · $mode · $model\n\n材料：${sc.material.content}\n\n');
  var t = await engine.start();
  for (var i = 1; i <= turns; i++) {
    out.writeln('**AI $i**：${t.text}\n');
    if (mode == 'record') await engine.settled();
    if (mode == 'record' && engine.missedRecords > 0) out.writeln('> ⚠️ 记录员本轮失败，沿用上一份\n');
    if (mode == 'record') out.writeln('> 记录：${engine.record.currentStep}｜确认：${engine.record.established.join('；')}｜提示级别 ${engine.record.hintLevel}\n');
    stdout.writeln('[$i] ${t.text}');
    if (engine.finished || i == turns) break;

    final view = <ChatMessage>[ChatMessage('system', childSystem(sc.child))];
    for (final h in engine.history) {
      if (h.speaker == Speaker.tutor) view.add(ChatMessage('user', h.text));
      if (h.speaker == Speaker.child) view.add(ChatMessage('assistant', h.text));
    }
    final said = (await kid.complete(view, maxTokens: 200)).trim();
    out.writeln('**孩子**：$said\n');
    stdout.writeln('    孩子：$said');
    t = await engine.childSays(said);
  }
  out.writeln('\n结束：${engine.finished ? '模型标记完成' : '到达轮数上限'}');

  Directory('tool/out').createSync(recursive: true);
  final path = 'tool/out/${id}__${mode}__${DateTime.now().millisecondsSinceEpoch}.md';
  File(path).writeAsStringSync(out.toString());
  stdout.writeln('\n记录：$path');
  tutor.close();
  kid.close();
}
