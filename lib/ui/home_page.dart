import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/prompt_library.dart';
import '../app/settings_store.dart';
import 'history_page.dart';
import 'settings_page.dart';
import 'setup_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('慢慢想'),
        actions: [
          IconButton(
            tooltip: '对话记录',
            icon: const Icon(Icons.history),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryPage(settings: settings),
              ),
            ),
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsPage(settings: settings),
              ),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!settings.hasKey)
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.key_outlined),
                      title: const Text('还没有填写 API key'),
                      subtitle: const Text(
                        '家长需要先到设置里填写自己的模型平台 key。推荐 DeepSeek 官方，开启深度思考。',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsPage(settings: settings),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                  child: Text('今天学什么？', style: theme.textTheme.titleLarge),
                ),
                for (final entry in promptLibrary)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: entry.preschool
                            ? theme.colorScheme.tertiaryContainer
                            : theme.colorScheme.primaryContainer,
                        child: Icon(
                          entry.preschool
                              ? Icons.child_care
                              : Icons.school_outlined,
                        ),
                      ),
                      title: Text(
                        entry.title,
                        style: theme.textTheme.titleMedium,
                      ),
                      subtitle: Text(entry.audience),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SetupPage(settings: settings, entry: entry),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () async {
                    try {
                      final opened = await launchUrl(
                        Uri.parse(
                          'https://github.com/rddmwmddr/guided-learning-prompts/',
                        ),
                        mode: LaunchMode.externalApplication,
                      );
                      if (opened || !context.mounted) return;
                    } catch (_) {
                      if (!context.mounted) return;
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('暂时无法打开浏览器，请稍后再试。')),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('提示词来源：引导式学习提示词库'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
