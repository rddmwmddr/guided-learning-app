import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../app/prompt_library.dart';
import '../app/session_controller.dart';
import '../app/settings_store.dart';
import '../core/llm_client.dart';
import '../core/tutor_engine.dart';
import 'session_page.dart';

import '../app/history_store.dart';
import 'transcript_view.dart';

/// 对话记录：只保存在本机。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, this.store, this.settings});

  final HistoryStore? store;
  final SettingsStore? settings;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  late final HistoryStore _store = widget.store ?? HistoryStore();
  late Future<List<SessionArchive>> _items = _store.list();

  void _reload() => setState(() => _items = _store.list());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话记录'),
        actions: [
          IconButton(
            tooltip: '全部删除',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              if (await _confirm(context, '删除全部对话记录和照片？')) {
                await _store.deleteAll();
                _reload();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<SessionArchive>>(
        future: _items,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) return const Center(child: Text('还没有对话记录。'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = items[i];
              final rounds = a.turns
                  .where((t) => t.speaker.name == 'child')
                  .length;
              return ListTile(
                title: Text('${a.title} · ${_date(a.startedAt)}'),
                subtitle: Text(
                  '${a.preview}\n孩子回答了 $rounds 次${a.finished ? ' · 已完成' : ''}',
                ),
                isThreeLine: true,
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _Detail(
                        archive: a,
                        store: _store,
                        settings: widget.settings,
                      ),
                    ),
                  );
                  _reload();
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _Detail extends StatefulWidget {
  const _Detail({required this.archive, required this.store, this.settings});

  final SessionArchive archive;
  final HistoryStore store;
  final SettingsStore? settings;

  @override
  State<_Detail> createState() => _DetailState();
}

class _DetailState extends State<_Detail> {
  SessionArchive get archive => widget.archive;
  HistoryStore get store => widget.store;
  bool _opening = false;
  String? _error;

  Future<void> _resume() async {
    final settings = widget.settings!;
    if (!settings.hasKey) {
      setState(() => _error = '请先到设置里填写 API key。');
      return;
    }
    setState(() {
      _opening = true;
      _error = null;
    });
    SessionController? controller;
    try {
      var prompt = archive.basePrompt;
      if (prompt.isEmpty) {
        final entries = promptLibrary.where((e) => e.title == archive.title);
        if (entries.isEmpty) throw StateError('找不到这次学习使用的提示词');
        prompt = await entries.first.load();
      }
      final images = <ChatImage>[];
      for (final path in archive.imagePaths) {
        final file = File(path);
        if (!await file.exists()) throw StateError('原来的学习照片已丢失，暂时无法恢复这次学习');
        images.add(
          ChatImage(
            base64Encode(await file.readAsBytes()),
            mime: path.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
          ),
        );
      }
      final engine = TutorEngine(
        client: LlmClient(
          images.isEmpty ? settings.modelConfig : settings.visionConfig,
        ),
        recorder: LlmClient(settings.modelConfig),
        basePrompt: prompt,
        material: LessonMaterial(
          content: archive.content,
          images: images,
          note: archive.note,
        ),
      )..restore(turns: archive.turns, progress: archive.record);
      controller = SessionController(
        settings: settings,
        engine: engine,
        title: archive.title,
        history: store,
        archiveId: archive.id,
        imagePaths: archive.imagePaths,
        originalStartedAt: archive.startedAt,
      );
      if (!mounted) {
        controller.dispose();
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SessionPage(controller: controller!, title: archive.title),
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      controller?.dispose();
      if (mounted) setState(() => _error = '无法继续：$e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${archive.title} · ${_date(archive.startedAt)}'),
        actions: [
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await _confirm(context, '删除这次对话？')) {
                await store.delete(archive.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (widget.settings != null) ...[
                FilledButton.icon(
                  onPressed: _opening ? null : _resume,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_opening ? '正在恢复…' : '继续学习'),
                ),
                const SizedBox(height: 8),
                const Text('接着原来的材料和对话继续，记录会保存到这次学习中。'),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                const SizedBox(height: 12),
              ],
              MaterialCard(
                content: archive.content,
                imagePaths: archive.imagePaths,
                note: archive.note,
              ),
              if (archive.record.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('学习进度', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        RecordView(text: archive.record),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              for (final t in archive.turns) Bubble(turn: t),
            ],
          ),
        ),
      ),
    );
  }
}

String _date(DateTime d) =>
    '${d.month}月${d.day}日 ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

Future<bool> _confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ) ??
    false;
