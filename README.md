# 慢慢想

一步一步陪孩子自己想，而不是替孩子想。

一个 Flutter 编写的语音引导学习客户端。家长准备题目、书页或身边的现象，孩子通过说话或打字与 AI 老师一问一答。老师每次只问一小步，后台记录学习目标和进度，帮助长对话接着往下走。

提示词来自 [引导式学习提示词库](https://github.com/rddmwmddr/guided-learning-prompts/)。原项目代码版权及许可予以保留，见 [LICENSE](LICENSE)。

## 当前能做什么

- 拍照、选图或输入学习材料；图片直接交给所选模型，不走其他 App 的解题流程。
- 内置离线语音识别，适合没有系统识别服务的 Android 手机。
- 说过话后，连续静音达到设置时长便自动识别、提交；一直没人说话时不会转写或提交。默认等待 4 秒，可调整。
- 默认用手机系统声音朗读；内置离线女声作为备用，也支持只打字。
- 自动保存本机对话，可从“对话记录 → 继续学习”恢复材料、照片、对话和进度。
- 家长面板可插话、拉回主题或请老师收尾，并查看平台是否返回了思考信息。
- 正常跟随最新消息，翻阅旧内容时暂停跟随，可点“回到最新”。

## 安装与验证状态

到 [Releases](https://github.com/rddmwmddr/guided-learning-app/releases) 下载 Android 安装包。首个版本为预览版，主要用于个人测试和开源协作。

| 平台 | 状态 |
|---|---|
| Android arm64 | 已在安卓真机运行；发布包需要用户自行填写模型 API key |
| iOS | 提供源码和图标；真机签名安装尚未完成，暂不提供 IPA |
| macOS / Windows / Linux | 包含 Flutter 平台工程，尚未完成完整功能验证 |

Release 包使用独立发布签名。此前由另一台电脑或调试密钥构建的同包名安装，可能无法直接覆盖更新；不要为此直接卸载有重要记录的旧版。开发版使用独立包名 `.dev`，可以与正式包并存，数据各自独立。

## API key 与数据

- App 不附带任何人的 API key，需要家长在设置中填写自己的 OpenAI 兼容平台地址、模型与 key。
- 默认提供 DeepSeek 和 OpenRouter 配置入口；费用以模型平台计费为准。
- key 通过系统安全存储保存，设置、照片和对话记录保存在本机，直到用户删除。
- **本地保存不等于完全离线。** 教学对话及所选照片会发送到家长配置的模型平台；选择云端转写时，录音也会发送到配置的语音平台。本地识别不会上传录音。
- 本项目没有自建业务服务器，但所选平台的数据政策仍然适用。
- 家长需要在场。AI 可能出错，请以课本、老师和实际核验为准，不要输入儿童身份、学校、住址等不必要的信息。

## 从源码运行

本项目使用 **Flutter 3.47.7 / Dart 3.13.5** 验证。Android 编译使用 Java 17 和 Android SDK 36。请先完成 Flutter 对应平台的环境配置。

```sh
git clone https://github.com/rddmwmddr/guided-learning-app.git
cd guided-learning-app
python3 tool/fetch_speech_models.py
flutter pub get
flutter devices
flutter run -d <设备编号>
```

离线模型二进制不放进 Git。下载脚本从固定上游地址取得模型，同时验证下载包和每个运行资源的 SHA-256；已准备好的文件会复用。模型约占 250 MiB，所以 APK 比普通 Flutter 客户端大，第一次准备模型也会慢一些。下载前请阅读 [第三方说明](THIRD_PARTY_NOTICES.md)，模型不统一适用本仓库的 MIT 许可。

```sh
python3 tool/fetch_speech_models.py --verify-only
```

Homebrew 用户可按需 `source tool/dev-env.sh`；普通 Flutter 环境不依赖此脚本。

iOS 需要完整 Xcode、CocoaPods、自己的 Apple 开发团队和真机开发者模式。项目已清除原电脑的开发团队配置。用 Xcode 打开 `ios/Runner.xcworkspace`，在 Signing & Capabilities 选择自己的 Team 与唯一 Bundle ID。

## 构建 Android Release

```sh
# 首次执行：生成本地专用发布签名，不覆盖已有密钥
python3 tool/create_signing_key.py
python3 tool/fetch_speech_models.py --verify-only
flutter build apk --release --target-platform android-arm64
```

输出：`build/app/outputs/flutter-apk/app-release.apk`。

**请私下备份 `.release/` 与 `android/key.properties`。** 它们被 Git 忽略，不能上传到仓库或 Release；丢失签名密钥会影响后续覆盖更新。Release 构建缺少签名配置时会报错，不会偷偷改用调试密钥。

## 测试与协作

```sh
flutter pub get
dart analyze lib
flutter test --exclude-tags screens
```

普通回归测试不需要真实 key，也不会访问模型平台。`integration_test/` 和 `tool/long_dialogue.dart` 内的真实模型实验需要单独配置，可能产生费用，CI 不自动运行它们。截图测试需额外字体与本机环境，默认排除。

见 [CONTRIBUTING.md](CONTRIBUTING.md) 与 [SECURITY.md](SECURITY.md)。CI 只用只读仓库权限，第三方 Action 固定到提交版本，不需要用户 API key 或签名密钥。

## 目录

```text
lib/core/       模型调用、教学引擎、进度记录
lib/speech/     系统与离线语音、语音活动检测
lib/app/        设置、存档与会话控制
lib/ui/         页面和对话组件
assets/prompts/ 上游提示词（CC BY 4.0）
assets/speech/  语音资源与各自许可；模型由脚本下载
assets/branding/ 图标母版与生成提示词
tool/           模型准备、签名创建、维护与实验工具
```

代码采用 MIT，提示词采用 CC BY 4.0，语音模型与依赖按各自许可使用。详见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。面向公众提供在线服务前，请阅读 [docs/合规说明.md](docs/合规说明.md)，并按实际使用场景自行核实适用要求。
