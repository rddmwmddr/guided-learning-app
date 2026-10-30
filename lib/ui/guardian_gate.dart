import 'package:flutter/material.dart';

import '../app/settings_store.dart';

/// 首次打开时给家长看的说明。必须由家长确认后才能使用。
///
/// 依据：面向中小学的生成式 AI 使用指南写明“小学阶段禁止学生独自使用开放式内容生成功能”；
/// 各大模型平台的用户协议也要求未成年人在监护人同意和陪同下使用。
class GuardianGate extends StatefulWidget {
  const GuardianGate({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<GuardianGate> createState() => _GuardianGateState();
}

class _GuardianGateState extends State<GuardianGate> {
  final _checks = List<bool>.filled(4, false);

  static const _items = [
    '我是孩子的家长或监护人，孩子使用时我会在旁边。',
    '我会用自己的 API key，费用由我在模型平台上支付。这个应用没有服务器，不收集任何信息。',
    'AI 会出错。孩子的结论和课本、老师不一致时，以课本和老师为准。',
    '我会控制时长：学前一次 10 分钟左右，小学一次不超过 20–30 分钟。',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _checks.every((c) => c);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 16),
                Text('慢慢想', style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('一步一步陪孩子自己想，而不是替孩子想。', style: theme.textTheme.titleMedium),
                const SizedBox(height: 24),
                Text(
                  '这是一个给家长用的工具：家长准备好题目或材料，孩子用说话的方式和 AI 老师一问一答。'
                  'AI 老师一次只问一小步，不直接给答案。',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Text('开始之前，请家长确认：', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                for (var i = 0; i < _items.length; i++)
                  CheckboxListTile(
                    value: _checks[i],
                    onChanged: (v) => setState(() => _checks[i] = v ?? false),
                    title: Text(_items[i]),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: ready ? widget.settings.confirmGuardian : null,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  child: const Text('我已确认，开始使用'),
                ),
                const SizedBox(height: 16),
                Text(
                  '对话内容只在本机和你选择的模型平台之间传输。请不要输入孩子的姓名、学校、住址；拍照时避开孩子的脸。',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
