import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:manmanxiang/core/llm_client.dart';

void main() {
  for (final style in [ThinkingStyle.deepseek, ThinkingStyle.openrouter]) {
    test('$style 开关实际传入请求，并检查平台返回的思考证据', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = LlmClient(
        ModelConfig(
          baseUrl: 'https://test.invalid',
          apiKey: 'test',
          model: 'test',
          thinkingStyle: style,
        ),
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': 'answer',
                    'reasoning_content': 'private reasoning',
                  },
                },
              ],
              'usage': {
                'completion_tokens_details': {'reasoning_tokens': 123},
              },
            }),
            200,
          );
        }),
      );
      await client.complete([const ChatMessage('user', 'question')]);
      expect(client.lastCall!.hasReasoning, isTrue);
      expect(client.lastCall!.reasoningTokens, 123);
      expect(client.lastCall!.summary, isNot(contains('private reasoning')));
      if (style == ThinkingStyle.deepseek) {
        expect(bodies.last['thinking'], {'type': 'enabled'});
        expect(bodies.last['reasoning_effort'], 'high');
      } else {
        expect(bodies.last['reasoning'], {'enabled': true, 'effort': 'high'});
      }
      await client.complete([
        const ChatMessage('user', 'recorder'),
      ], thinking: false);
      expect(client.lastCall!.requestedThinking, isFalse);
      expect(bodies.last.containsKey('reasoning_effort'), isFalse);
      if (style == ThinkingStyle.deepseek) {
        expect(bodies.last['thinking'], {'type': 'disabled'});
      } else {
        expect(bodies.last['reasoning'], {'enabled': false});
      }
      client.close();
    });
  }
  test('平台没有思考信息时不宣称已确认思考', () async {
    final client = LlmClient(
      const ModelConfig(
        baseUrl: 'https://test.invalid',
        apiKey: 'test',
        model: 'test',
      ),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': 'answer'},
              },
            ],
          }),
          200,
        ),
      ),
    );
    await client.complete([const ChatMessage('user', 'question')]);
    expect(client.lastCall!.hasReasoning, isFalse);
    expect(client.lastCall!.summary, contains('未返回可核实'));
    client.close();
  });
}
