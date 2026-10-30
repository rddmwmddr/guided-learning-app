import 'package:flutter_test/flutter_test.dart';
import 'package:manmanxiang/app/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('升级后将旧的内置朗读切回系统，保留离线识别选择', () async {
    SharedPreferences.setMockInitialValues({
      'localTts': true,
      'asrMode': 'local',
    });
    final settings = await SettingsStore.load();
    expect(settings.localTts, isFalse);
    expect(settings.asrMode, AsrMode.local);
    settings.localTts = true;
    await settings.save();
    expect((await SettingsStore.load()).localTts, isTrue); // 一次迁移后尊重手动选择。
  });
}
