import 'package:flutter/material.dart';

import '../app/settings_store.dart';
import '../core/llm_client.dart';
import '../speech/speech_io.dart' as speech;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.settings});

  final SettingsStore settings;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  SettingsStore get s => widget.settings;

  late final _key = TextEditingController(text: s.apiKey);
  late final _baseUrl = TextEditingController(text: s.baseUrl);
  late final _model = TextEditingController(text: s.model);
  late final _vision = TextEditingController(text: s.visionModel);
  late final _asrUrl = TextEditingController(text: s.asrBaseUrl);
  late final _asrModel = TextEditingController(text: s.asrModel);
  late final _asrKey = TextEditingController(text: s.asrKey);
  bool _showKey = false;
  String? _testResult;
  bool _testing = false;
  speech.Speaker? _voiceSpeaker;
  speech.Listener? _voiceListener;
  String? _speechBusy;
  String? _speechResult;

  Future<void> _checkSpeech(bool microphone) async {
    setState(() {
      _speechBusy = microphone ? 'mic' : 'speaker';
      _speechResult = null;
    });
    try {
      if (microphone) {
        final heard = await (_voiceListener ??= speech.Listener()).listen(s);
        if (mounted) {
          setState(
            () => _speechResult =
                heard.error ??
                (heard.text.isEmpty ? '没有听到内容。' : '听到：${heard.text}'),
          );
        }
      } else {
        await (_voiceSpeaker ??= speech.Speaker()).say(
          '你好，我们一步一步慢慢想。',
          rate: s.speechRate,
          local: s.localTts,
        );
        if (mounted) setState(() => _speechResult = '朗读完成。');
      }
    } catch (e) {
      if (mounted) setState(() => _speechResult = '语音测试失败：$e');
    } finally {
      if (mounted) setState(() => _speechBusy = null);
    }
  }

  @override
  void dispose() {
    _voiceSpeaker?.dispose();
    _voiceListener?.dispose();
    for (final c in [
      _key,
      _baseUrl,
      _model,
      _vision,
      _asrUrl,
      _asrModel,
      _asrKey,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    s
      ..apiKey = _key.text
      ..baseUrl = _baseUrl.text
      ..model = _model.text
      ..visionModel = _vision.text
      ..asrBaseUrl = _asrUrl.text
      ..asrModel = _asrModel.text
      ..asrKey = _asrKey.text;
    await s.save();
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = LlmClient(s.modelConfig);
    try {
      final reply = await client.complete([
        const ChatMessage('user', '只回答两个字：可以'),
      ], maxTokens: 4000);
      if (mounted) {
        setState(
          () => _testResult = '连接成功：$reply\n${client.lastCall?.summary ?? ''}',
        );
      }
    } on LlmException catch (e) {
      if (mounted) setState(() => _testResult = e.message);
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      onPopInvokedWithResult: (_, _) => _save(),
      child: Scaffold(
        appBar: AppBar(title: const Text('设置（家长）')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('AI 老师', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                const Text('推荐 DeepSeek 官方，并开启深度思考。实测关闭思考后更容易直接给答案、把错的说成对的。'),
                const SizedBox(height: 12),
                SegmentedButton<ModelPreset>(
                  segments: [
                    for (final p in ModelPreset.values)
                      ButtonSegment(value: p, label: Text(p.label)),
                  ],
                  selected: {s.preset},
                  onSelectionChanged: (v) async {
                    await s.applyPreset(v.first);
                    setState(() {
                      _baseUrl.text = s.baseUrl;
                      _model.text = s.model;
                    });
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _key,
                  obscureText: !_showKey,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: 'API key',
                    helperText: s.preset == ModelPreset.deepseek
                        ? '在 platform.deepseek.com 申请并充值，几块钱可以用很久'
                        : null,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _showKey ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (s.preset == ModelPreset.custom) ...[
                  TextField(
                    controller: _baseUrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '接口地址（OpenAI 兼容）',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<ThinkingStyle>(
                    initialValue: s.thinkingStyle,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '深度思考的参数写法',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ThinkingStyle.deepseek,
                        child: Text('thinking.type（DeepSeek、火山方舟）'),
                      ),
                      DropdownMenuItem(
                        value: ThinkingStyle.openrouter,
                        child: Text('reasoning.enabled（OpenRouter）'),
                      ),
                      DropdownMenuItem(
                        value: ThinkingStyle.none,
                        child: Text('不传'),
                      ),
                    ],
                    onChanged: (v) => setState(
                      () => s.thinkingStyle = v ?? ThinkingStyle.none,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '模型',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _vision,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '看照片用的模型（可不填）',
                    helperText: '有照片时用这个模型。不填就用上面的；deepseek-flash 能看图',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('深度思考'),
                  subtitle: Text(
                    s.thinkingStyle == ThinkingStyle.none
                        ? '当前不发送思考参数，开关无法控制平台。请先选择对应的参数写法。'
                        : '向平台请求高强度思考。可在测试连接或家长面板核对平台反馈。',
                  ),
                  value: s.thinking,
                  onChanged: (v) => setState(() => s.thinking = v),
                ),
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: const Text('测试连接'),
                    ),
                    const SizedBox(width: 12),
                    if (_testing)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    if (_testResult != null)
                      Expanded(child: Text(_testResult!)),
                  ],
                ),
                const Divider(height: 40),
                Text('语音', style: theme.textTheme.titleLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final choice in const {
                      AsrMode.local: '内置离线',
                      AsrMode.system: '系统识别',
                      AsrMode.cloud: '云端转写',
                      AsrMode.off: '只打字',
                    }.entries)
                      ChoiceChip(
                        label: Text(choice.value),
                        selected: s.asrMode == choice.key,
                        onSelected: _speechBusy == null
                            ? (_) => setState(() => s.asrMode = choice.key)
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(switch (s.asrMode) {
                  AsrMode.local =>
                    '录音结束后在本机识别普通话，无需语音 key 或系统语音服务。首次使用需准备内置模型，可能稍慢。',
                  AsrMode.system => '用手机或电脑自带的识别。部分国内安卓手机没有可用的识别服务，可以改用内置离线。',
                  AsrMode.cloud =>
                    '录音后发到 OpenAI 兼容的 /audio/transcriptions 接口，需要另外申请 key。',
                  AsrMode.off => '孩子或家长打字回答，AI 老师的话仍会念出来。',
                }),
                if (s.asrMode == AsrMode.cloud) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _asrUrl,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '转写接口地址',
                      hintText: 'https://...',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _asrModel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '转写模型',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _asrKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: '转写 key',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用内置离线朗读（备用）'),
                  subtitle: const Text('默认使用手机系统声音，启动更快。系统朗读不可用时，可打开此备用选项。'),
                  value: s.localTts,
                  onChanged: _speechBusy == null
                      ? (v) => setState(() => s.localTts = v)
                      : null,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _speechBusy != null
                          ? null
                          : () => _checkSpeech(false),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('试听朗读'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _speechBusy != null || s.asrMode == AsrMode.off
                          ? null
                          : () => _checkSpeech(true),
                      icon: const Icon(Icons.mic_none),
                      label: const Text('测试识别'),
                    ),
                    if (_speechBusy == 'mic')
                      TextButton(
                        onPressed: () => _voiceListener?.finish(),
                        child: const Text('说完了'),
                      ),
                  ],
                ),
                if (_speechBusy != null)
                  const Text('正在准备或处理语音，请稍等。测试识别时请说一句普通话。'),
                if (_speechResult != null) Text(_speechResult!),
                Text('语速：${s.speechRate.toStringAsFixed(2)}（越小越慢）'),
                Slider(
                  value: s.speechRate,
                  min: 0.2,
                  max: 0.8,
                  divisions: 12,
                  onChanged: (v) => setState(() => s.speechRate = v),
                ),
                Text('说过话后，连续静音 ${s.pauseSeconds} 秒自动提交'),
                const Text('没开口时不会提交；中途继续说话会重新计算静音时间。'),
                Slider(
                  value: s.pauseSeconds.toDouble(),
                  min: 2,
                  max: 8,
                  divisions: 6,
                  onChanged: (v) => setState(() => s.pauseSeconds = v.round()),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('老师说完自动听孩子说话'),
                  value: s.autoListen,
                  onChanged: (v) => setState(() => s.autoListen = v),
                ),
                const Divider(height: 40),
                Text('时长', style: theme.textTheme.titleLarge),
                Text('${s.sessionMinutes} 分钟后提醒收尾'),
                Slider(
                  value: s.sessionMinutes.toDouble(),
                  min: 5,
                  max: 40,
                  divisions: 7,
                  onChanged: (v) =>
                      setState(() => s.sessionMinutes = v.round()),
                ),
                const Divider(height: 40),
                FilledButton(
                  onPressed: () async {
                    await _save();
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('保存'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('清除本机所有数据？'),
                        content: const Text('会删除 key、全部设置和对话记录，下次打开需要重新确认。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('清除'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await s.wipe();
                      if (context.mounted) {
                        Navigator.popUntil(context, (r) => r.isFirst);
                      }
                    }
                  },
                  child: const Text('清除本机所有数据'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
