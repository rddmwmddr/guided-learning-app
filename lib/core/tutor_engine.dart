import 'lesson_record.dart';
import 'llm_client.dart';

enum Speaker { child, parent, tutor }

class Turn {
  const Turn(this.speaker, this.text, {this.rawReply});

  final Speaker speaker;

  /// 给人看、给孩子听的部分。
  final String text;

  /// 模型的完整回复（含记录），只有 tutor 有。
  final String? rawReply;
}

/// 家长在开始前交代的内容：文字、照片，或者两者都有。
class LessonMaterial {
  const LessonMaterial({
    this.content = '',
    this.images = const [],
    this.note = '',
  });

  /// 题目、短文、绘本页的文字，或对实物的描述。
  final String content;

  /// 家长拍的照片。每一轮都会随材料一起交给老师，让老师自己看图。
  final List<ChatImage> images;

  /// 补充说明，例如孩子几年级、这道题他做错了。
  final String note;

  bool get isEmpty => content.trim().isEmpty && images.isEmpty;

  String _text({required bool forRecorder, String imageSummary = ''}) {
    final parts = <String>[
      if (content.trim().isNotEmpty) '学习材料：${content.trim()}',
      if (images.isNotEmpty)
        forRecorder
            ? (imageSummary.isNotEmpty
                  ? '照片内容：$imageSummary'
                  : '学习材料：家长拍了 ${images.length} 张照片（你看不到图，按对话内容判断）')
            : '学习材料见照片${images.length > 1 ? '（共 ${images.length} 张）' : ''}。',
      if (note.trim().isNotEmpty) '补充说明：${note.trim()}',
    ];
    return '（家长）${parts.join('\n')}';
  }

  ChatMessage toMessage() =>
      ChatMessage('user', _text(forRecorder: false), images: images);

  String toRecorderText([String imageSummary = '']) =>
      _text(forRecorder: true, imageSummary: imageSummary);
}

/// 应用附加在每份提示词之后的要求。
///
/// 提示词库里的提示词是给“粘贴到 App”用的。本应用多做了两件事：
/// 把话念给孩子听，以及在后台维护一份进度记录交还给模型，所以在这里补上相应的要求。
const appRules = '''
【在本应用里】以下是应用附加的要求。
- 你的话会被念给孩子听。只写要说出口的话，不写动作描写、括号里的说明、表情和给家长的备注。不替孩子或家长说话，不写旁白。
- 标着“（家长）”的话是旁边的家长说的，照家长的要求调整；其余的话都是孩子说的。
- 应用会在后台整理一份【进度记录】给你，你不用自己写。
【主线】每次提问前先看【进度记录】：问题要服务于“现在的小目标”，小目标要服务于“原题要解决的”。同一个小目标问了三轮还没有进展，就加一级提示或直接示范关键一步，然后进入下一个小目标，不要换着说法反复问同一件事。每隔三四轮，用一句话告诉孩子我们走到哪儿了，比如“我们已经知道……，现在只差……”。
【何时结束】孩子自己得出原题的答案、说出关键一步、再做对一道相近的小题，就收尾，不要接着出更多练习题，也不要回头把原题每一步再检查一遍。收尾时请孩子说说今天弄明白了什么，再用一句话告诉家长孩子自己完成了什么。收尾之后孩子再说再见，只简短回一句。
''';

/// 记录员：每轮老师说完话后，用一次不开思考的调用更新进度记录。
///
/// 实测让老师自己边教边写记录并不可靠：20 轮里有 12 轮漏写。
/// 拆成单独的一次调用后，记录一定会生成；它在孩子听老师说话时后台进行，不增加等待。
const recorderPrompt = '''
你是一位老师的助手，负责维护一次一对一辅导的进度记录。根据学习材料、上一份记录和最近的对话，写出新的记录。
只输出记录本身，格式固定，不要其他文字：
<记录>
原题要解决的：一句话
已经确认的：孩子自己说出或做到的关键点，用；隔开，没有就写无
现在的小目标：老师下一步要孩子弄清的一件事，以及它和原题的关系
卡点：没有就写无
提示级别：0 到 4
是否完成：是或否
</记录>
规则：
- “原题要解决的”一旦写下就不要改。
- “已经确认的”只写孩子自己说出或做到的；老师说出来的不算。最多保留最近 6 条最关键的，旧的可以合并。
- “现在的小目标”要能从老师最后一句话里看出来；它必须服务于原题。
- “提示级别”：0 是还没给提示，1 是提醒看哪里，2 是给方向，3 是举更简单的例子，4 是已经示范。换了新的小目标就回到 0。
- “是否完成”：孩子已经自己得出原题答案并做对一道相近的小题，或者老师已经收尾，写“是”。
''';

const describeImagePrompt =
    '这是家长拍的学习材料。请把图上的题目和文字原样写出来；图画部分用一两句话说清画了什么、各有多少。'
    '不要解答，不要提示，不要加任何说明。';

const defaultNudge = '（家长）请回到最开始的要求：一次只说一小步，等孩子回答；不要直接给答案。';
const wrapUpNudge = '（家长）时间差不多了，请用一两句话愉快地收尾：请孩子说说今天弄明白了什么，再用一句话告诉家长孩子自己完成了什么。';

class TutorEngine {
  TutorEngine({
    required this.client,
    required this.basePrompt,
    required this.material,
    LlmClient? recorder,
    this.windowMessages = 12,
    this.useRecord = true,
  }) : recorder = recorder ?? client;

  final LlmClient client;

  /// 更新记录用的客户端。默认与老师相同，调用时关闭思考。
  final LlmClient recorder;

  /// 提示词库中的某一份提示词全文。
  final String basePrompt;
  final LessonMaterial material;

  /// 只把最近这么多条对话原文交给模型，更早的靠记录承接。
  final int windowMessages;

  /// 关掉后退化为“把提示词粘贴进 App”的用法，仅用于对照测试。
  final bool useRecord;

  final List<Turn> history = [];
  LessonRecord record = const LessonRecord();

  /// 记录员连续失败的次数，便于排查。失败时沿用上一份记录。
  int missedRecords = 0;
  ModelCallInfo? lastTutorCall;

  Future<void>? _recording;

  /// 有照片时，让能看图的模型写一段照片内容，只给记录员用。
  /// 记录员看不到图，不然会把第一个小步骤误当成原题（实测出现过）。
  Future<String>? _imageSummary;

  bool get finished => record.finished;

  /// 恢复上下文，不调用模型、不重新发送开场白。
  void restore({required List<Turn> turns, required String progress}) {
    if (history.isNotEmpty) throw StateError('只能向空会话恢复记录');
    history.addAll(turns);
    final previous =
        LessonRecord.split(progress).record ?? LessonRecord.parse(progress);
    if (previous != null) {
      record = LessonRecord(
        goal: previous.goal,
        established: previous.established,
        currentStep: previous.currentStep,
        stuck: previous.stuck,
        hintLevel: previous.hintLevel,
      );
    }
  }

  Future<Turn> start() {
    if (useRecord && material.images.isNotEmpty) {
      _imageSummary = client
          .complete(
            [ChatMessage('user', describeImagePrompt, images: material.images)],
            thinking: false,
            maxTokens: 800,
          )
          .then((t) => t.trim())
          .catchError((Object _) => '');
    }
    return _ask();
  }

  Future<Turn> childSays(String text) {
    history.add(Turn(Speaker.child, text.trim()));
    return _ask();
  }

  Future<Turn> parentSays(String text) {
    history.add(
      Turn(Speaker.parent, text.startsWith('（家长）') ? text : '（家长）$text'),
    );
    return _ask();
  }

  /// 等后台的记录更新完成。界面在决定是否结束前会调用。
  Future<void> settled() => _recording ?? Future.value();

  /// 本轮请求要发给模型的全部消息。公开出来便于测试和排查。
  List<ChatMessage> buildMessages() {
    final system = StringBuffer(basePrompt.trim());
    if (useRecord) {
      system
        ..write('\n\n')
        ..write(appRules.trim());
      if (!record.isEmpty) {
        system
          ..write('\n\n【进度记录】\n')
          ..write(record.render());
      }
    }

    final messages = <ChatMessage>[
      ChatMessage('system', system.toString()),
      material.toMessage(),
    ];

    var turns = history;
    if (useRecord && history.length > windowMessages) {
      turns = history.sublist(history.length - windowMessages);
      // 窗口必须从孩子或家长说的话开始，保证 user/assistant 交替。
      while (turns.isNotEmpty && turns.first.speaker == Speaker.tutor) {
        turns = turns.sublist(1);
      }
      messages.add(const ChatMessage('assistant', '（前面的对话已省略，以【进度记录】为准。）'));
    }
    for (final t in turns) {
      messages.add(
        ChatMessage(t.speaker == Speaker.tutor ? 'assistant' : 'user', t.text),
      );
    }
    return _mergeAdjacent(messages);
  }

  Future<Turn> _ask() async {
    await settled();
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await client.complete(buildMessages());
      lastTutorCall = client.lastCall;
      // 模型偶尔还是会自己写记录或旁白，去掉不念。
      final spoken = cleanSpoken(LessonRecord.split(raw).spoken);
      if (spoken.isEmpty) continue;
      final turn = Turn(Speaker.tutor, spoken, rawReply: raw.trim());
      history.add(turn);
      if (useRecord) _recording = _updateRecord();
      return turn;
    }
    throw LlmException('老师这次没想好说什么，请再试一次。');
  }

  Future<void> _updateRecord() async {
    final recent = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    final dialog = recent
        .map(
          (t) => switch (t.speaker) {
            Speaker.tutor => '老师：${t.text}',
            Speaker.child => '孩子：${t.text}',
            Speaker.parent => t.text,
          },
        )
        .join('\n');
    final summary = await (_imageSummary ?? Future.value(''));
    final input = [
      material.toRecorderText(summary),
      '上一份记录：${record.isEmpty ? '无' : '\n${record.render()}'}',
      '最近的对话：\n$dialog',
    ].join('\n\n');
    try {
      final raw = await recorder.complete(
        [
          ChatMessage('system', recorderPrompt.trim()),
          ChatMessage('user', input),
        ],
        thinking: false,
        maxTokens: 800,
      );
      final parsed = LessonRecord.split(
        raw.contains(LessonRecord.openTag)
            ? raw
            : '${LessonRecord.openTag}$raw',
      ).record;
      if (parsed != null) {
        // 原题一旦确定就不再改，防止记录员把主线改丢。
        record = record.goal.isEmpty ? parsed : parsed.withGoal(record.goal);
        missedRecords = 0;
        return;
      }
    } catch (_) {
      // 记录失败不影响对话，沿用上一份。
    }
    missedRecords++;
  }

  /// 家长连续两次输入时会出现两条相邻的 user 消息，部分平台不接受，合并成一条。
  static List<ChatMessage> _mergeAdjacent(List<ChatMessage> input) {
    final out = <ChatMessage>[];
    for (final m in input) {
      if (out.isNotEmpty &&
          out.last.role == m.role &&
          m.role != 'system' &&
          !m.hasImages &&
          !out.last.hasImages) {
        out[out.length - 1] = ChatMessage(
          m.role,
          '${out.last.text}\n${m.text}',
        );
      } else {
        out.add(m);
      }
    }
    return out;
  }
}

/// 去掉不该念给孩子听的部分：括号里的旁白、给家长的话、格式符号。
///
/// 实测模型会自己编出“（家长旁白：……）”，或在对话中间插入“（给家长的话：……）”。
String cleanSpoken(String text) {
  var s = text.replaceAll(
    RegExp(r'[（(][^（()）]*?(家长|旁白|备注|动作|停顿)[^（()）]*?[)）]'),
    '',
  );
  s = s
      .replaceAll(RegExp(r'^\s*[-*#>]+\s*', multiLine: true), '')
      .replaceAll('**', '');
  return s.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}
