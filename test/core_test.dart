import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/core/lesson_record.dart';
import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';

class FakeClient extends LlmClient {
  FakeClient(this.replies) : super(const ModelConfig(baseUrl: 'x', apiKey: 'k', model: 'm'));

  final List<String> replies;
  final List<List<ChatMessage>> calls = [];

  @override
  Future<String> complete(List<ChatMessage> messages, {bool? thinking, int maxTokens = 4000}) async {
    calls.add(messages);
    return replies.removeAt(0);
  }
}

const sampleRecord = '''<记录>
原题要解决的：算出小明现在有多少张贴纸
已经确认的：一开始有35张；送出去要减
现在的小目标：算35减18，这是原题第一步
卡点：无
提示级别：1
是否完成：否
</记录>''';

void main() {
  group('LessonRecord', () {
    test('拆出说的话和记录', () {
      final parts = LessonRecord.split('那你算算看？\n$sampleRecord');
      expect(parts.spoken, '那你算算看？');
      expect(parts.record!.goal, '算出小明现在有多少张贴纸');
      expect(parts.record!.established, ['一开始有35张', '送出去要减']);
      expect(parts.record!.hintLevel, 1);
      expect(parts.record!.finished, isFalse);
    });

    test('没有记录时原样返回', () {
      final parts = LessonRecord.split('你好呀');
      expect(parts.spoken, '你好呀');
      expect(parts.record, isNull);
    });

    test('已确认的只保留最近 6 条', () {
      final r = LessonRecord.parse('原题要解决的：x\n已经确认的：1；2；3；4；5；6；7；8\n现在的小目标：y')!;
      expect(r.established, ['3', '4', '5', '6', '7', '8']);
    });

    test('render 后能再解析回来', () {
      final r = LessonRecord.split(sampleRecord).record!;
      final again = LessonRecord.split(r.render()).record!;
      expect(again.goal, r.goal);
      expect(again.currentStep, r.currentStep);
    });
  });

  group('cleanSpoken', () {
    test('去掉旁白和给家长的话', () {
      expect(cleanSpoken('你怎么看出来的？\n（家长旁白：孩子说“四段里的一段”。）\n那第一问呢？'), '你怎么看出来的？\n\n那第一问呢？');
      expect(cleanSpoken('很好。（给家长的话：孩子掌握了借位。）'), '很好。');
    });

    test('保留正常的括号内容', () {
      expect(cleanSpoken('三个十（也就是三十）'), '三个十（也就是三十）');
    });
  });

  group('LessonMaterial', () {
    test('带照片时老师收到图片，记录员只收到文字说明', () {
      const m = LessonMaterial(images: [ChatImage('AAAA')], note: '二年级');
      final msg = m.toMessage();
      expect(msg.hasImages, isTrue);
      final json = msg.toJson();
      expect((json['content'] as List).length, 2);
      expect(m.toRecorderText(), contains('拍了 1 张照片'));
      expect(m.toRecorderText(), contains('二年级'));
    });
  });

  group('TutorEngine', () {
    const material = LessonMaterial(content: '35-18+12=?', note: '二年级');

    test('记录员更新记录，并在下一轮交给老师', () async {
      final tutor = FakeClient(['小明一开始有多少张？', '那送出去以后呢？']);
      final recorder = FakeClient([sampleRecord]);
      final engine = TutorEngine(client: tutor, recorder: recorder, basePrompt: '提示词', material: material);

      await engine.start();
      await engine.settled();
      expect(engine.record.currentStep, contains('35减18'));

      await engine.childSays('35张');
      final system = tutor.calls.last.first.text;
      expect(system, contains('【进度记录】'));
      expect(system, contains('算35减18'));
    });

    test('原题一旦确定，记录员不能改掉', () async {
      final tutor = FakeClient(['a', 'b']);
      final recorder = FakeClient([sampleRecord, sampleRecord.replaceAll('算出小明现在有多少张贴纸', '算别的')]);
      final engine = TutorEngine(client: tutor, recorder: recorder, basePrompt: 'p', material: material);
      await engine.start();
      await engine.settled();
      await engine.childSays('x');
      await engine.settled();
      expect(engine.record.goal, '算出小明现在有多少张贴纸');
    });

    test('长对话只保留最近的原文，并保证从孩子的话开始', () async {
      final tutor = FakeClient(List.generate(20, (i) => '问题$i'));
      final recorder = FakeClient(List.generate(20, (_) => sampleRecord));
      final engine = TutorEngine(client: tutor, recorder: recorder, basePrompt: 'p', material: material, windowMessages: 6);
      await engine.start();
      for (var i = 0; i < 8; i++) {
        await engine.childSays('回答$i');
      }
      final msgs = engine.buildMessages();
      final roles = msgs.map((m) => m.role).toList();
      expect(roles.where((r) => r == 'assistant' || r == 'user').length, lessThanOrEqualTo(9));
      for (var i = 1; i < roles.length; i++) {
        expect(roles[i] == roles[i - 1] && roles[i] != 'system', isFalse, reason: '相邻两条不能同一角色：$roles');
      }
    });

    test('记录员失败不影响对话', () async {
      final tutor = FakeClient(['你好']);
      final recorder = FakeClient(['乱七八糟']);
      final engine = TutorEngine(client: tutor, recorder: recorder, basePrompt: 'p', material: material);
      final t = await engine.start();
      await engine.settled();
      expect(t.text, '你好');
      expect(engine.missedRecords, 1);
    });
  });
}
