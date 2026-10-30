import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../app/history_store.dart';
import '../app/prompt_library.dart';
import '../app/session_controller.dart';
import '../app/settings_store.dart';
import '../core/llm_client.dart';
import '../core/tutor_engine.dart';
import 'session_page.dart';

/// 家长准备材料：拍照、打字，或者两者都有。照片直接交给 AI 老师看。
class SetupPage extends StatefulWidget {
  const SetupPage({super.key, required this.settings, required this.entry});

  final SettingsStore settings;
  final PromptEntry entry;

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _content = TextEditingController();
  final _note = TextEditingController();
  final _photos = <({Uint8List bytes, String mime})>[];
  String? _error;
  bool _starting = false;

  static const _maxPhotos = 3;

  @override
  void dispose() {
    _content.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _addPhoto(ImageSource source) async {
    setState(() => _error = null);
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      final mime = file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      setState(() => _photos.add((bytes: bytes, mime: mime)));
    } catch (e) {
      setState(() => _error = '打不开${source == ImageSource.camera ? '相机' : '相册'}：$e');
    }
  }

  Future<void> _start() async {
    if (_content.text.trim().isEmpty && _photos.isEmpty) {
      setState(() => _error = '请拍一张照片，或者把题目打进来。');
      return;
    }
    if (!widget.settings.hasKey) {
      setState(() => _error = '请先到设置里填写 API key。');
      return;
    }
    setState(() => _starting = true);
    final images = [for (final p in _photos) ChatImage(base64Encode(p.bytes), mime: p.mime)];
    final history = HistoryStore();
    final created = await history.create(images);
    final prompt = await widget.entry.load();
    final engine = TutorEngine(
      client: LlmClient(images.isEmpty ? widget.settings.modelConfig : widget.settings.visionConfig),
      recorder: LlmClient(widget.settings.modelConfig),
      basePrompt: prompt,
      material: LessonMaterial(content: _content.text, images: images, note: _note.text),
    );
    final controller = SessionController(
      settings: widget.settings,
      engine: engine,
      title: widget.entry.title,
      history: history,
      archiveId: created.id,
      imagePaths: created.imagePaths,
    );
    if (!mounted) return;
    setState(() => _starting = false);
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SessionPage(controller: controller, title: widget.entry.title)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.entry.title)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('拍下题目、书页或身边的东西，也可以直接打字。', style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              SizedBox(
                height: 112,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(_photos[i].bytes, width: 112, height: 112, fit: BoxFit.cover),
                            ),
                            Positioned(
                              right: 2,
                              top: 2,
                              child: IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                iconSize: 18,
                                onPressed: () => setState(() => _photos.removeAt(i)),
                                icon: const Icon(Icons.close),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_photos.length < _maxPhotos) ...[
                      _AddTile(icon: Icons.photo_camera_outlined, label: '拍照', onTap: () => _addPhoto(ImageSource.camera)),
                      const SizedBox(width: 8),
                      _AddTile(icon: Icons.photo_library_outlined, label: '相册', onTap: () => _addPhoto(ImageSource.gallery)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _content,
                minLines: 3,
                maxLines: 10,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: _photos.isEmpty ? '题目或材料' : '文字（有照片可以不填）',
                  hintText: '例如：${widget.entry.example}',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _note,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: '补充说明（可不填）',
                  hintText: '例如：二年级；这道题他做错了',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: const Text('开始，把手机交给孩子'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              ),
              const SizedBox(height: 12),
              Text('照片和对话只保存在这台手机上。拍照时请避开孩子的脸和姓名。',
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        width: 112,
        height: 112,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
          color: scheme.surfaceContainerLow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [Icon(icon, size: 32, color: scheme.primary), const SizedBox(height: 6), Text(label)],
        ),
      ),
    );
  }
}
