import 'dart:convert';

import 'package:http/http.dart' as http;

/// 调用模型时需要的配置。全部由用户自己填写，App 不内置任何 key。
class ModelConfig {
  const ModelConfig({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.thinking = true,
    this.thinkingStyle = ThinkingStyle.deepseek,
  });

  /// OpenAI 兼容的地址，例如 https://api.deepseek.com
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 是否开启深度思考。实测关闭后更容易直接给答案、把错答案说成对。
  final bool thinking;
  final ThinkingStyle thinkingStyle;

  static const deepseekDefault = ModelConfig(
    baseUrl: 'https://api.deepseek.com',
    apiKey: '',
    model: 'deepseek-flash',
  );

  ModelConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? thinking,
    ThinkingStyle? thinkingStyle,
  }) => ModelConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    thinking: thinking ?? this.thinking,
    thinkingStyle: thinkingStyle ?? this.thinkingStyle,
  );
}

/// 不同平台开关深度思考的参数写法不同。
enum ThinkingStyle {
  /// DeepSeek / 火山方舟：{"thinking": {"type": "enabled|disabled"}}
  deepseek,

  /// OpenRouter：{"reasoning": {"enabled": true|false}}
  openrouter,

  /// 不传任何思考参数，由平台默认决定。
  none,
}

class ChatImage {
  const ChatImage(this.base64, {this.mime = 'image/jpeg'});

  final String base64;
  final String mime;
}

class ChatMessage {
  const ChatMessage(this.role, this.text, {this.images = const []});

  final String role;
  final String text;
  final List<ChatImage> images;

  bool get hasImages => images.isNotEmpty;

  Map<String, dynamic> toJson() {
    if (images.isEmpty) return {'role': role, 'content': text};
    return {
      'role': role,
      'content': [
        {'type': 'text', 'text': text},
        for (final img in images)
          {
            'type': 'image_url',
            'image_url': {'url': 'data:${img.mime};base64,${img.base64}'},
          },
      ],
    };
  }
}

class LlmException implements Exception {
  LlmException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 仅保存响应元数据，不保存或展示模型的思考原文。
class ModelCallInfo {
  const ModelCallInfo({
    required this.requestedThinking,
    required this.style,
    required this.elapsed,
    required this.hasReasoning,
    this.reasoningTokens,
  });
  final bool requestedThinking;
  final ThinkingStyle style;
  final Duration elapsed;
  final bool hasReasoning;
  final int? reasoningTokens;

  String get summary {
    if (style == ThinkingStyle.none) return '未发送思考参数，由平台默认决定';
    if (!requestedThinking) return '本轮未请求深度思考';
    if (hasReasoning) {
      return '平台已返回思考信息${reasoningTokens != null ? '（$reasoningTokens 个思考 token）' : ''}';
    }
    return '已请求深度思考，平台未返回可核实的思考信息';
  }
}

class LlmClient {
  LlmClient(this.config, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final ModelConfig config;
  final http.Client _http;
  ModelCallInfo? lastCall;

  Future<String> complete(
    List<ChatMessage> messages, {
    bool? thinking,
    int maxTokens = 4000,
  }) async {
    if (config.apiKey.trim().isEmpty) {
      throw LlmException('还没有填写 API key，请家长先到“设置”里填写。');
    }
    lastCall = null;
    final clock = Stopwatch()..start();
    final useThinking = thinking ?? config.thinking;
    final body = <String, dynamic>{
      'model': config.model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'max_tokens': maxTokens,
      'stream': false,
    };
    switch (config.thinkingStyle) {
      case ThinkingStyle.deepseek:
        body['thinking'] = {'type': useThinking ? 'enabled' : 'disabled'};
        if (useThinking) body['reasoning_effort'] = 'high';
      case ThinkingStyle.openrouter:
        body['reasoning'] = {
          'enabled': useThinking,
          if (useThinking) 'effort': 'high',
        };
      case ThinkingStyle.none:
        break;
    }

    final uri = Uri.parse('${_trimSlash(config.baseUrl)}/chat/completions');
    final http.Response res;
    try {
      res = await _http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer ${config.apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 180));
    } on Exception catch (e) {
      throw LlmException('网络连接失败，请检查网络后再试。（$e）');
    }

    final text = utf8.decode(res.bodyBytes);
    if (res.statusCode != 200) {
      throw LlmException(
        _explain(res.statusCode, text),
        statusCode: res.statusCode,
      );
    }
    final data = jsonDecode(text) as Map<String, dynamic>;
    final choices = data['choices'] as List?;
    String? content;
    Map? responseMessage;
    if (choices != null && choices.isNotEmpty) {
      final message = (choices.first as Map)['message'] as Map?;
      responseMessage = message;
      content = message?['content'] as String?;
    }
    if (content == null || content.trim().isEmpty) {
      throw LlmException('模型这次没有给出回答，请再试一次。');
    }
    final usage = data['usage'];
    final details = usage is Map ? usage['completion_tokens_details'] : null;
    final tokens = details is Map ? details['reasoning_tokens'] : null;
    final reasoning =
        responseMessage?['reasoning_content'] ?? responseMessage?['reasoning'];
    final reasoningDetails = responseMessage?['reasoning_details'];
    lastCall = ModelCallInfo(
      requestedThinking: useThinking,
      style: config.thinkingStyle,
      elapsed: clock.elapsed,
      reasoningTokens: tokens is num ? tokens.toInt() : null,
      hasReasoning:
          (tokens is num && tokens > 0) ||
          (reasoning is String && reasoning.trim().isNotEmpty) ||
          (reasoningDetails is List && reasoningDetails.isNotEmpty),
    );
    return content;
  }

  void close() => _http.close();

  static String _trimSlash(String s) =>
      s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static String _explain(int code, String body) {
    final snippet = body.length > 200 ? body.substring(0, 200) : body;
    return switch (code) {
      401 => 'API key 不对，请家长到“设置”里检查。',
      402 => '账户余额不足，请家长到模型平台充值。',
      403 => '这个 key 没有使用该模型的权限。（$snippet）',
      404 => '找不到这个模型或地址，请检查“设置”里的地址和模型名。',
      429 => '请求太频繁或额度用完了，稍等一会儿再试。',
      >= 500 => '模型平台暂时出了问题（$code），稍后再试。',
      _ => '请求失败（$code）：$snippet',
    };
  }
}
