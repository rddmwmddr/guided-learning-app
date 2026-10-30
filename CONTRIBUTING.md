# 参与开发

1. 按 README 配置 Flutter，编译前运行 `python3 tool/fetch_speech_models.py`。
2. 修改应用逻辑后执行 `dart analyze lib` 和 `flutter test --exclude-tags screens`。
3. 提交前执行 `python3 tool/check_public_files.py`，检查暂存内容。不要提交 key、录音、真实儿童照片、对话记录、签名文件或本机绝对路径。
4. 提示词以[上游提示词库](https://github.com/rddmwmddr/guided-learning-prompts/)为准，尽量先向上游提交修改，再用 `tool/sync_prompts.sh` 同步。
5. 语音、拍照和权限变更应说明真机、系统、模式以及验证结果。未测试的平台请明确注明。

请在 issue / PR 中使用虚构或已去除身份信息的复现材料。不要把真实 API key 放到日志或截图里。
