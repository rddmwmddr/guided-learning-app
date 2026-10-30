import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/llm_client.dart';
import '../core/tutor_engine.dart';

/// 一次学习的存档。只保存在本机，不上传。
class SessionArchive {
  SessionArchive({
    required this.id,
    required this.title,
    required this.startedAt,
    required this.content,
    required this.note,
    required this.imagePaths,
    required this.turns,
    required this.record,
    required this.finished,
    this.basePrompt = '',
  });

  final String id;
  final String title;
  final DateTime startedAt;
  final String content;
  final String note;
  final List<String> imagePaths;
  final List<Turn> turns;
  final String record;
  final bool finished;

  /// 保留当时使用的教学提示词，让恢复后的教学方式保持一致。
  final String basePrompt;

  String get preview {
    final text = content.trim().isNotEmpty
        ? content.trim()
        : (imagePaths.isNotEmpty ? '（照片）' : '');
    return text.length > 40 ? '${text.substring(0, 40)}…' : text;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'startedAt': startedAt.toIso8601String(),
    'content': content,
    'note': note,
    'imagePaths': imagePaths,
    'turns': [
      for (final t in turns) {'speaker': t.speaker.name, 'text': t.text},
    ],
    'record': record,
    'finished': finished,
    'basePrompt': basePrompt,
  };

  static SessionArchive fromJson(Map<String, dynamic> j) => SessionArchive(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    startedAt:
        DateTime.tryParse(j['startedAt'] as String? ?? '') ?? DateTime.now(),
    content: j['content'] as String? ?? '',
    note: j['note'] as String? ?? '',
    imagePaths: [
      for (final p in (j['imagePaths'] as List? ?? const [])) p as String,
    ],
    turns: [
      for (final t in (j['turns'] as List? ?? const []))
        Turn(
          Speaker.values.byName((t as Map)['speaker'] as String),
          t['text'] as String,
        ),
    ],
    record: j['record'] as String? ?? '',
    finished: j['finished'] as bool? ?? false,
    basePrompt: j['basePrompt'] as String? ?? '',
  );
}

class HistoryStore {
  Future<void> _saving = Future.value();
  Future<Directory> _root() async {
    final dir = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/sessions',
    );
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir;
  }

  /// 开始一次学习时调用：建目录、存照片，返回存档编号。
  Future<({String id, List<String> imagePaths})> create(
    List<ChatImage> images,
  ) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final dir = Directory('${(await _root()).path}/$id')
      ..createSync(recursive: true);
    final paths = <String>[];
    for (var i = 0; i < images.length; i++) {
      final ext = images[i].mime.endsWith('png') ? 'png' : 'jpg';
      final f = File('${dir.path}/img_$i.$ext')
        ..writeAsBytesSync(base64Decode(images[i].base64));
      paths.add(f.path);
    }
    return (id: id, imagePaths: paths);
  }

  Future<void> save(SessionArchive a) {
    final json = jsonEncode(a.toJson());
    final next = _saving.catchError((Object _) {}).then((_) async {
      final dir = Directory('${(await _root()).path}/${a.id}')
        ..createSync(recursive: true);
      final temp = File('${dir.path}/session.json.tmp');
      await temp.writeAsString(json, flush: true);
      await temp.rename('${dir.path}/session.json');
    });
    _saving = next;
    return next;
  }

  Future<List<SessionArchive>> list() async {
    final root = await _root();
    final out = <SessionArchive>[];
    for (final d in root.listSync().whereType<Directory>()) {
      final f = File('${d.path}/session.json');
      if (!f.existsSync()) continue;
      try {
        final a = SessionArchive.fromJson(
          jsonDecode(await f.readAsString()) as Map<String, dynamic>,
        );
        if (a.turns.isNotEmpty) out.add(a);
      } catch (_) {}
    }
    out.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return out;
  }

  Future<void> delete(String id) async {
    final d = Directory('${(await _root()).path}/$id');
    if (d.existsSync()) d.deleteSync(recursive: true);
  }

  Future<void> deleteAll() async {
    final root = await _root();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
