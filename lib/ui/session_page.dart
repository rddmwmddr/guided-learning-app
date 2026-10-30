import 'package:flutter/material.dart';

import '../app/session_controller.dart';
import '../app/settings_store.dart';
import '../core/tutor_engine.dart';
import 'transcript_view.dart';
import 'transcript_scroller.dart';

/// 学习页：上面是对话气泡，最新一句老师的话放大；下面是话筒。家长的操作收在“家长”按钮里。
class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.controller, required this.title});

  final SessionController controller;
  final String title;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  final _typed = TextEditingController();
  bool _typing = false;

  SessionController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _typing = c.settings.asrMode == AsrMode.off;
    c.begin();
  }

  @override
  void dispose() {
    _typed.dispose();
    c.dispose();
    super.dispose();
  }

  void _sendTyped() {
    final text = _typed.text.trim();
    if (text.isEmpty) return;
    _typed.clear();
    c.childSays(text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final lastTutorIndex = c.turns.lastIndexWhere(
          (t) => t.speaker == Speaker.tutor,
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [
              TextButton.icon(
                onPressed: () => _openParentPanel(context),
                icon: const Icon(Icons.supervisor_account_outlined),
                label: const Text('家长'),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                  children: [
                    if (c.timeUp && c.phase != Phase.finished)
                      _Banner(
                        text: '已经学了 ${c.settings.sessionMinutes} 分钟啦，可以休息一下。',
                        action: '请老师收尾',
                        onTap: c.wrapUp,
                      ),
                    Expanded(
                      child: TranscriptScroller(
                        children: [
                          MaterialCard(
                            content: c.engine.material.content,
                            imagePaths: c.imagePaths,
                            dense: true,
                          ),
                          const SizedBox(height: 8),
                          for (var i = 0; i < c.turns.length; i++)
                            Bubble(
                              turn: c.turns[i],
                              emphasize:
                                  i == lastTutorIndex &&
                                  c.phase != Phase.finished,
                            ),
                          if (c.phase == Phase.thinking)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          if (c.phase == Phase.listening &&
                              c.partial.isNotEmpty)
                            Bubble(turn: Turn(Speaker.child, '${c.partial}…')),
                          if (c.phase == Phase.finished)
                            _Finished(onContinue: c.continueLesson),
                        ],
                      ),
                    ),
                    if (c.error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          c.error!,
                          style: TextStyle(color: theme.colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (c.phase != Phase.finished) _controls(theme),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _controls(ThemeData theme) {
    if (c.phase == Phase.error) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: c.retry,
          icon: const Icon(Icons.refresh),
          label: const Text('再试一次'),
        ),
      );
    }
    final busy = c.phase == Phase.thinking || c.transcribing;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: '再说一遍',
                iconSize: 26,
                onPressed: busy ? null : c.repeat,
                icon: const Icon(Icons.replay),
              ),
              const SizedBox(width: 20),
              if (!_typing)
                _MicButton(
                  phase: c.phase,
                  onTap: busy ? null : c.toggleListening,
                ),
              if (_typing)
                Expanded(
                  child: TextField(
                    controller: _typed,
                    enabled: !busy,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _sendTyped(),
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: '在这里打字回答',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: busy ? null : _sendTyped,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 20),
              IconButton.filledTonal(
                tooltip: _typing ? '改用说话' : '改用打字',
                iconSize: 26,
                onPressed: c.settings.asrMode == AsrMode.off
                    ? null
                    : () async {
                        if (c.phase == Phase.listening) {
                          await c.toggleListening();
                        }
                        setState(() => _typing = !_typing);
                      },
                icon: Icon(_typing ? Icons.mic_none : Icons.keyboard_outlined),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openParentPanel(BuildContext context) {
    final input = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (context, scroll) => ListenableBuilder(
            listenable: c,
            builder: (context, _) => ListView(
              key: const Key('parentPanel'),
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                Text('家长操作', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('内容由 AI 生成，可能出错'),
                const SizedBox(height: 4),
                const Text('尽量不插话。AI 跑偏时再用下面的按钮。'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        c.nudge();
                      },
                      icon: const Icon(Icons.u_turn_left),
                      label: const Text('拉回：一步一步来，别给答案'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () {
                        Navigator.pop(context);
                        c.wrapUp();
                      },
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('请老师收尾'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: input,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    hintText: '对老师说一句，例如“他其实还没学过借位”',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: () {
                        final t = input.text.trim();
                        if (t.isEmpty) return;
                        Navigator.pop(context);
                        c.parentSays(t);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (c.engine.lastTutorCall case final info?) ...[
                  Text('最近一次老师回答：${info.summary}'),
                  Text(
                    '请求耗时 ${(info.elapsed.inMilliseconds / 1000).toStringAsFixed(1)} 秒',
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  '学习进度（AI 整理，孩子看不到）',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                RecordView(
                  text: c.engine.record.isEmpty ? '' : c.engine.record.render(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 进度记录的可读版本。
class RecordView extends StatelessWidget {
  const RecordView({super.key, required this.text});

  /// LessonRecord.render() 的结果。
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const Text('还没有整理出进度。');
    const labels = {
      '原题要解决的': '要解决的',
      '已经确认的': '孩子自己弄清的',
      '现在的小目标': '现在这一步',
      '卡点': '卡在',
      '提示级别': '提示到第几级（0–4）',
    };
    final rows = <Widget>[];
    for (final line in text.split('\n')) {
      final i = line.indexOf('：');
      if (i < 0) continue;
      final k = line.substring(0, i), v = line.substring(i + 1);
      final label = labels[k];
      if (label == null || (k == '卡点' && v == '无')) continue;
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label：',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: v),
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows);
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.phase, required this.onTap});

  final Phase phase;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listening = phase == Phase.listening;
    return SizedBox(
      width: 84,
      height: 84,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          shape: const CircleBorder(),
          backgroundColor: listening ? scheme.error : scheme.primary,
          padding: EdgeInsets.zero,
        ),
        child: Icon(listening ? Icons.stop_rounded : Icons.mic, size: 40),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    required this.action,
    required this.onTap,
  });

  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: Text(text),
        trailing: TextButton(onPressed: onTap, child: Text(action)),
      ),
    );
  }
}

class _Finished extends StatelessWidget {
  const _Finished({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(
            Icons.emoji_events_outlined,
            size: 56,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Text('今天就到这里', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('这次的对话已经保存在“对话记录”里。'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(onPressed: onContinue, child: const Text('还想接着学')),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('回到首页'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
