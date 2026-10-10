import 'dart:convert';

import 'package:baocode/kernel/claude_code/claude_haiku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String text(String text) => jsonEncode({
    'type': 'stream_event',
    'event': {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': text},
    },
  });

  test('an answer is timed from Claude Code starting its request', () {
    final timer = ClaudeAnswerTimer()
      ..add('{"type":"system","subtype":"init"}', const Duration(seconds: 2))
      ..add('not json', const Duration(seconds: 2))
      ..add(text('1 2'), const Duration(milliseconds: 2500))
      ..add(text(' 3'), const Duration(milliseconds: 4500))
      ..add(
        jsonEncode({
          'type': 'result',
          'is_error': false,
          'result': '1 2 3',
          'usage': {'output_tokens': 120},
        }),
        const Duration(seconds: 5),
      );
    final answer = timer.answer('', 0);
    expect(answer.text, '1 2 3');
    expect(answer.firstText, const Duration(milliseconds: 500));
    expect(answer.lastText, const Duration(milliseconds: 2500));
    expect(answer.tokensPerSecond, 60);
  });

  test('no speed without a count, or with all the text at once', () {
    String result(Map<String, Object?> usage) => jsonEncode({
      'type': 'result',
      'is_error': false,
      'result': '1',
      'usage': usage,
    });
    final uncounted = ClaudeAnswerTimer()
      ..add(text('1'), const Duration(seconds: 1))
      ..add(text('2'), const Duration(seconds: 2))
      ..add(result({'output_tokens': 0}), const Duration(seconds: 2));
    expect(uncounted.answer('', 0).tokensPerSecond, isNull);
    final whole = ClaudeAnswerTimer()
      ..add(text('1 2 3'), const Duration(seconds: 1))
      ..add(result({'output_tokens': 9}), const Duration(seconds: 1));
    expect(whole.answer('', 0).tokensPerSecond, isNull);
  });

  test('an error result is thrown', () {
    final timer = ClaudeAnswerTimer()
      ..add(
        jsonEncode({
          'type': 'result',
          'is_error': true,
          'result': 'API Error: 401',
        }),
        Duration.zero,
      );
    expect(
      () => timer.answer('', 1),
      throwsA(
        isA<ClaudeHaikuException>().having(
          (e) => e.message,
          'message',
          'API Error: 401',
        ),
      ),
    );
    expect(
      () => ClaudeAnswerTimer().answer('boom', 1),
      throwsA(isA<ClaudeHaikuException>()),
    );
  });
}
