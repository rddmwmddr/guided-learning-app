import 'dart:io';

import 'package:flutter/material.dart';

import '../core/tutor_engine.dart';

/// 对话气泡。学习页和对话记录页共用。
class Bubble extends StatelessWidget {
  const Bubble({super.key, required this.turn, this.emphasize = false});

  final Turn turn;

  /// 最新一句老师的话放大显示，方便孩子看。
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (align, color, label) = switch (turn.speaker) {
      Speaker.tutor => (Alignment.centerLeft, scheme.secondaryContainer, '老师'),
      Speaker.child => (Alignment.centerRight, scheme.primaryContainer, '孩子'),
      Speaker.parent => (Alignment.center, scheme.tertiaryContainer, '家长'),
    };
    final text = turn.speaker == Speaker.parent ? turn.text.replaceFirst('（家长）', '') : turn.text;
    final style = emphasize
        ? theme.textTheme.headlineSmall?.copyWith(height: 1.5)
        : theme.textTheme.bodyLarge?.copyWith(height: 1.5);
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * (emphasize ? 0.92 : 0.8)),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: emphasize ? 14 : 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: turn.speaker == Speaker.parent ? 0.6 : 1),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (turn.speaker == Speaker.parent)
                Text(label, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onTertiaryContainer)),
              Text(text, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// 学习材料：照片缩略图 + 文字。点照片可以放大。
class MaterialCard extends StatelessWidget {
  const MaterialCard({super.key, required this.content, required this.imagePaths, this.note = '', this.dense = false});

  final String content;
  final List<String> imagePaths;
  final String note;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePaths.isNotEmpty)
              SizedBox(
                height: dense ? 64 : 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: imagePaths.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => Dialog(
                        child: InteractiveViewer(child: Image.file(File(imagePaths[i]))),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(imagePaths[i]), fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
                    ),
                  ),
                ),
              ),
            if (imagePaths.isNotEmpty && content.trim().isNotEmpty) const SizedBox(height: 8),
            if (content.trim().isNotEmpty)
              Text(content.trim(), maxLines: dense ? 2 : null, overflow: dense ? TextOverflow.ellipsis : null, style: theme.textTheme.bodyMedium),
            if (note.trim().isNotEmpty && !dense) ...[
              const SizedBox(height: 6),
              Text('补充说明：${note.trim()}', style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
