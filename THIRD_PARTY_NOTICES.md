# 第三方代码、提示词与模型

本项目的 MIT 许可只适用于相应应用代码，不替代提示词、模型或依赖的许可。各组件保持原作者归属，模型权重未做训练或微调，使用的是上游转换版本。

| 组件 | 来源与作者 | 许可 / 说明 |
|---|---|---|
| 初始应用代码 | syhdeclan，原项目已有 MIT 版权声明 | [LICENSE](LICENSE)，保留原声明 |
| 引导式学习提示词 | [guided-learning-prompts](https://github.com/rddmwmddr/guided-learning-prompts/) 及其贡献者 | CC BY 4.0，保留提示词内容与出处 |
| sherpa-onnx 运行库 | [k2-fsa/sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx)，Xiaomi 及贡献者 | Apache-2.0，Flutter 插件随包提供其许可 |
| Paraformer 中文轻量识别模型 | Alibaba / FunASR；crazyant 的 ONNX 导出；csukuangfj / sherpa-onnx 转换包 `sherpa-onnx-paraformer-zh-small-2024-03-09` | 保留 [FunASR 模型许可 v1.1](assets/speech/asr/LICENSE)，不将其声称为 MIT 或 Apache-2.0 权重 |
| MeloTTS 中英文女声 | [MyShell.ai / MeloTTS](https://github.com/myshell-ai/MeloTTS)，sherpa-onnx 转换包 `vits-melo-tts-zh_en` | [MIT](assets/speech/tts/LICENSE) |
| Silero VAD | [snakers4/silero-vad](https://github.com/snakers4/silero-vad)，通过 sherpa-onnx 发布 | [MIT](assets/speech/vad/LICENSE) |

Paraformer 的原始发布说明：
- [crazyant ONNX 量化导出](https://www.modelscope.cn/models/crazyant/speech_paraformer_asr_nat-zh-cn-16k-common-vocab8358-onnx/summary)
- [原模型 Paraformer](https://modelscope.cn/models/damo/speech_paraformer_asr_nat-zh-cn-16k-common-vocab8358-tensorflow1/summary)
- [sherpa-onnx 使用与转换说明](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-paraformer/paraformer-models.html)
- 所附模型许可来自 [FunASR 的固定源码版本](https://github.com/modelscope/FunASR/blob/dd00b0e42261b628466037f3a522d713399360b6/MODEL_LICENSE)。上游再发布页面未提供完整许可元数据，因此保留原模型协议及完整来源，不能只按某个镜像的 Apache 标签判断。

`tool/speech_models.json` 固定下载地址与 SHA-256。Release APK 包含相应模型及其许可文本；下载或再分发时请同时保留这些说明。Flutter / Dart 其余依赖以各包自带许可为准。

图标由内置 imagegen 工具生成；母版与原始生成提示词保存在 `assets/branding/`。
