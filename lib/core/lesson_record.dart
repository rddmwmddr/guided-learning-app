/// 一次学习的进度记录。
///
/// 长对话里模型会“忘了为什么要问这个问题”。解决办法是让模型每轮都在回复末尾
/// 写一段孩子看不到的记录，App 把最新一份记录在下一轮重新交给模型，
/// 同时只保留最近几轮原文。这样不管聊多少轮，模型手上始终有：原题要解决什么、
/// 孩子已经弄清了什么、这一步在弄清什么。
class LessonRecord {
  const LessonRecord({
    this.goal = '',
    this.established = const [],
    this.currentStep = '',
    this.stuck = '',
    this.hintLevel = 0,
    this.finished = false,
  });

  /// 原题要解决的（一句话，整个过程不变）。
  final String goal;

  /// 孩子自己说出或做到的关键点。
  final List<String> established;

  /// 现在的小目标，以及它和原题的关系。
  final String currentStep;

  /// 卡在哪里；没有为空。
  final String stuck;

  /// 当前提示级别，0 表示还没给提示，4 表示已经示范。
  final int hintLevel;

  /// 模型认为这次学习已经完成。
  final bool finished;

  LessonRecord withGoal(String value) => LessonRecord(
        goal: value,
        established: established,
        currentStep: currentStep,
        stuck: stuck,
        hintLevel: hintLevel,
        finished: finished,
      );

  bool get isEmpty => goal.isEmpty && established.isEmpty && currentStep.isEmpty;

  static const openTag = '<记录>';
  static const closeTag = '</记录>';

  /// 从模型回复里拆出“给孩子的话”和“记录”。
  ///
  /// 模型偶尔漏写结束标签，或者把记录写成别的样子；拆不出来时保留上一份记录，
  /// 不让一次格式错误毁掉整条主线。
  static ({String spoken, LessonRecord? record}) split(String reply) {
    final start = reply.indexOf(openTag);
    if (start < 0) return (spoken: reply.trim(), record: null);
    final end = reply.indexOf(closeTag, start);
    final body = reply.substring(start + openTag.length, end < 0 ? reply.length : end);
    final spoken = reply.substring(0, start).trim();
    return (spoken: spoken, record: parse(body));
  }

  static LessonRecord? parse(String body) {
    String field(String name) {
      final m = RegExp('^\\s*$name\\s*[:：]\\s*(.*)\$', multiLine: true).firstMatch(body);
      return m?.group(1)?.trim() ?? '';
    }

    final goal = field('原题要解决的');
    final step = field('现在的小目标');
    if (goal.isEmpty && step.isEmpty) return null;

    final establishedRaw = field('已经确认的');
    var established = establishedRaw
        .split(RegExp(r'[；;。]|\s{2,}'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != '无' && e != '暂无')
        .toList();
    // 记录越长越容易被模型照抄成流水账，只保留最近 6 条。
    if (established.length > 6) established = established.sublist(established.length - 6);

    final stuck = field('卡点');
    final level = int.tryParse(RegExp(r'\d').firstMatch(field('提示级别'))?.group(0) ?? '') ?? 0;
    final finishedRaw = field('是否完成');

    return LessonRecord(
      goal: goal,
      established: established,
      currentStep: step,
      stuck: (stuck == '无' || stuck == '暂无') ? '' : stuck,
      hintLevel: level.clamp(0, 4),
      finished: finishedRaw.startsWith('是'),
    );
  }

  /// 交回给模型的文本。格式与模型写记录时一致，便于它接着写。
  String render() => [
        openTag,
        '原题要解决的：$goal',
        '已经确认的：${established.isEmpty ? '无' : established.join('；')}',
        '现在的小目标：$currentStep',
        '卡点：${stuck.isEmpty ? '无' : stuck}',
        '提示级别：$hintLevel',
        '是否完成：${finished ? '是' : '否'}',
        closeTag,
      ].join('\n');
}
