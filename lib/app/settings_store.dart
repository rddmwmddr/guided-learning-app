import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/llm_client.dart';
import 'history_store.dart';

/// 语音识别方式。
enum AsrMode {
  /// 应用内置模型，不依赖系统识别服务、不上传录音。
  local,

  /// 手机或电脑自带的语音识别。免费，但部分国内安卓手机没有可用的识别服务。
  system,

  /// 录音后发到 OpenAI 兼容的转写接口（/audio/transcriptions），需要另填 key。
  cloud,

  /// 不用语音，孩子或家长打字。
  off,
}

/// 预置的模型平台。只是帮家长少填几个字，所有平台都需要自己的 key。
enum ModelPreset {
  deepseek(
    'DeepSeek 官方',
    'https://api.deepseek.com',
    'deepseek-flash',
    ThinkingStyle.deepseek,
  ),
  openrouter(
    'OpenRouter',
    'https://openrouter.ai/api/v1',
    'deepseek/deepseek-v4.1-flash',
    ThinkingStyle.openrouter,
  ),
  custom('其他（OpenAI 兼容）', '', '', ThinkingStyle.none);

  const ModelPreset(this.label, this.baseUrl, this.model, this.thinkingStyle);

  final String label;
  final String baseUrl;
  final String model;
  final ThinkingStyle thinkingStyle;
}

/// 全部设置只保存在本机。key 放在系统安全存储里，其余放在普通偏好里。
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs, this._secure);

  static Future<SettingsStore> load() async {
    final store = SettingsStore._(
      await SharedPreferences.getInstance(),
      const FlutterSecureStorage(),
    );
    await store._read();
    return store;
  }

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  bool guardianConfirmed = false;
  ModelPreset preset = ModelPreset.deepseek;
  String baseUrl = ModelPreset.deepseek.baseUrl;
  String model = ModelPreset.deepseek.model;
  ThinkingStyle thinkingStyle = ModelPreset.deepseek.thinkingStyle;
  bool thinking = true;
  String apiKey = '';

  /// 识别图片用的模型。默认与对话模型相同（deepseek-flash 支持图像理解）。
  String visionModel = '';

  AsrMode asrMode = Platform.isAndroid ? AsrMode.local : AsrMode.system;
  bool localTts = false;
  String asrBaseUrl = '';
  String asrModel = '';
  String asrKey = '';

  /// 语速，0.1–1.0，越小越慢。
  double speechRate = 0.42;

  /// AI 说完后自动开始听孩子说话。
  bool autoListen = true;

  /// 孩子停顿多少秒算说完。研究建议提问后给足等待时间，孩子想的时间比大人长。
  int pauseSeconds = 4;

  /// 一次学习的建议时长（分钟），到点提醒家长收尾。
  int sessionMinutes = 20;

  bool get hasKey => apiKey.trim().isNotEmpty;

  ModelConfig get modelConfig => ModelConfig(
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    thinking: thinking,
    thinkingStyle: thinkingStyle,
  );

  ModelConfig get visionConfig => modelConfig.copyWith(
    model: visionModel.trim().isEmpty ? model : visionModel.trim(),
  );

  Future<void> _read() async {
    final p = _prefs;
    guardianConfirmed = p.getBool('guardianConfirmed') ?? false;
    preset =
        ModelPreset.values.asNameMap()[p.getString('preset')] ??
        ModelPreset.deepseek;
    baseUrl = p.getString('baseUrl') ?? preset.baseUrl;
    model = p.getString('model') ?? preset.model;
    thinkingStyle =
        ThinkingStyle.values.asNameMap()[p.getString('thinkingStyle')] ??
        preset.thinkingStyle;
    thinking = p.getBool('thinking') ?? true;
    visionModel = p.getString('visionModel') ?? '';
    asrMode =
        AsrMode.values.asNameMap()[p.getString('asrMode')] ??
        (Platform.isAndroid ? AsrMode.local : AsrMode.system);
    // 一次性将已安装版本也切回系统朗读；之后尊重用户的手动选择。
    if (!(p.getBool('systemTtsDefaultV2') ?? false)) {
      localTts = false;
      await p.setBool('localTts', false);
      await p.setBool('systemTtsDefaultV2', true);
    } else {
      localTts = p.getBool('localTts') ?? false;
    }
    asrBaseUrl = p.getString('asrBaseUrl') ?? '';
    asrModel = p.getString('asrModel') ?? '';
    speechRate = p.getDouble('speechRate') ?? 0.42;
    autoListen = p.getBool('autoListen') ?? true;
    pauseSeconds = p.getInt('pauseSeconds') ?? 4;
    sessionMinutes = p.getInt('sessionMinutes') ?? 20;
    try {
      apiKey = await _secure.read(key: 'apiKey') ?? '';
      asrKey = await _secure.read(key: 'asrKey') ?? '';
    } catch (_) {
      // 少数设备上安全存储不可用，此时只能请家长重新填写。
      apiKey = '';
      asrKey = '';
    }
  }

  Future<void> confirmGuardian() async {
    guardianConfirmed = true;
    await _prefs.setBool('guardianConfirmed', true);
    notifyListeners();
  }

  Future<void> applyPreset(ModelPreset value) async {
    preset = value;
    if (value != ModelPreset.custom) {
      baseUrl = value.baseUrl;
      model = value.model;
      thinkingStyle = value.thinkingStyle;
    }
    await save();
  }

  Future<void> save() async {
    final p = _prefs;
    await p.setString('preset', preset.name);
    await p.setString('baseUrl', baseUrl.trim());
    await p.setString('model', model.trim());
    await p.setString('thinkingStyle', thinkingStyle.name);
    await p.setBool('thinking', thinking);
    await p.setString('visionModel', visionModel.trim());
    await p.setString('asrMode', asrMode.name);
    await p.setBool('localTts', localTts);
    await p.setString('asrBaseUrl', asrBaseUrl.trim());
    await p.setString('asrModel', asrModel.trim());
    await p.setDouble('speechRate', speechRate);
    await p.setBool('autoListen', autoListen);
    await p.setInt('pauseSeconds', pauseSeconds);
    await p.setInt('sessionMinutes', sessionMinutes);
    try {
      await _secure.write(key: 'apiKey', value: apiKey.trim());
      await _secure.write(key: 'asrKey', value: asrKey.trim());
    } catch (_) {}
    notifyListeners();
  }

  /// 清除本机保存的全部内容（包括 key 和对话记录）。
  Future<void> wipe() async {
    try {
      await HistoryStore().deleteAll();
    } catch (_) {}
    await _prefs.clear();
    try {
      await _secure.deleteAll();
    } catch (_) {}
    await _read();
    notifyListeners();
  }
}
