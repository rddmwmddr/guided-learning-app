# 内置离线语音模型

推理引擎：sherpa-onnx 2.0.1（Apache-2.0），通过 Flutter FFI 调用。
模型随应用打包，第一次使用复制到私有应用支持目录 speech-v1；不会下载模型或上传音频。

- STT：sherpa-onnx-paraformer-zh-small-2024-03-09，int8，普通话，16 kHz。
  官方包：https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-paraformer-zh-small-2024-03-09.tar.bz2
  原始模型来源保留在 asr/README.md。
- TTS：vits-melo-tts-zh_en，单女声，中英文，44.1 kHz。
  官方包：https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-melo-tts-zh_en.tar.bz2
  MIT 许可全文保留在 tts/LICENSE。

模型合计约 250 MiB。修改模型文件时同时更新 OfflineSpeech 的缓存目录版本，避免复用旧缓存。
识别采用“录音后转写”，不提供逐字实时字幕；静音结束或手动结束录音后才推理。
录音和合成音频使用临时文件，完成后删除。教学模型仍按家长设置调用远端 API。

本机模型兼容性测试（无需 Xcode）：

```sh
dart run tool/offline_speech_smoke.dart "$HOME/.pub-cache/hosted/pub.dev/sherpa_onnx_macos-2.0.1/macos"
```

速度和儿童语音准确率必须在目标手机上实测，桌面测试不能替代真机验证。

- VAD：Silero VAD，随应用内置约 629 KiB，用于录音流中的语音活动检测。官方模型：https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx 。先检测到说话，再等待设定的连续静音时长；录音达到安全上限仍没有说过话时，跳过转写和提交。
