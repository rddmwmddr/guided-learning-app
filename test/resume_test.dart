import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/app/history_store.dart';
import 'package:manmanxiang/core/llm_client.dart';
import 'package:manmanxiang/core/tutor_engine.dart';

class _Client extends LlmClient {
  _Client() : super(const ModelConfig(baseUrl: 'x', apiKey: 'k', model: 'm'));
  List<ChatMessage>? received;
  @override
  Future<String> complete(
    List<ChatMessage> messages, {
    bool? thinking,
    int maxTokens = 4000,
  }) async {
    received = messages;
    return '那剩下多少呢？';
  }
}

void main() {
  test('旧存档兼容，继续回答时恢复材料、角色和进度且取消完成状态', () async {
    final archive = SessionArchive.fromJson({
      'id': 'old',
      'title': '小学数学',
      'content': '35-18=?',
      'note': '二年级',
      'turns': [
        {'speaker': 'tutor', 'text': '先有多少张？'},
        {'speaker': 'child', 'text': '35张'},
        {'speaker': 'parent', 'text': '（家长）慢一点'},
        {'speaker': 'tutor', 'text': '送走多少张？'},
      ],
      'record': '<记录>\n原题要解决的：35减18\n已经确认的：开始有35张\n现在的小目标：用减法\n是否完成：是\n</记录>',
      'finished': true,
    });
    expect(archive.basePrompt, isEmpty);
    final client = _Client();
    final engine = TutorEngine(
      client: client,
      basePrompt: '原来的提示词',
      material: LessonMaterial(content: archive.content, note: archive.note),
    )..restore(turns: archive.turns, progress: archive.record);
    expect(client.received, isNull);
    expect(engine.history.length, 4);
    expect(engine.finished, isFalse);
    expect(engine.record.established, ['开始有35张']);
    await engine.childSays('送走18张');
    await engine.settled();
    final sent = client.received!;
    // 记录员另有调用；教学上下文可以独立检查。
    final messages = engine.buildMessages();
    expect(messages.first.text, contains('原来的提示词'));
    expect(messages.first.text, contains('35减18'));
    expect(messages[1].text, contains('35-18=?'));
    expect(
      messages.any((m) => m.role == 'assistant' && m.text == '送走多少张？'),
      isTrue,
    );
    expect(messages.any((m) => m.text.contains('送走18张')), isTrue);
    expect(sent, isNotEmpty);
    expect(archive.turns.length, 4); // 新回答不能修改旧存档对象。
    client.close();
  });

  test('新存档保留提示词、同一编号和照片路径', () {
    final archive = SessionArchive(
      id: 'same-id',
      title: '小学科学',
      startedAt: DateTime(2026, 10, 30),
      content: '',
      note: '杯子外的水珠',
      imagePaths: ['/local/photo.png'],
      turns: const [Turn(Speaker.tutor, '你看到了什么？')],
      record: '',
      finished: false,
      basePrompt: '本次教学提示词',
    );
    final restored = SessionArchive.fromJson(archive.toJson());
    expect(restored.id, archive.id);
    expect(restored.basePrompt, archive.basePrompt);
    expect(restored.startedAt, archive.startedAt);
    expect(restored.imagePaths, archive.imagePaths);
    expect(restored.turns.single.text, archive.turns.single.text);
  });

  test('不允许向已有的对话重复恢复', () {
    final client = _Client();
    final engine = TutorEngine(
      client: client,
      basePrompt: '',
      material: const LessonMaterial(),
    )..restore(turns: const [Turn(Speaker.child, '1')], progress: '');
    expect(() => engine.restore(turns: [], progress: ''), throwsStateError);
    client.close();
  });
}
