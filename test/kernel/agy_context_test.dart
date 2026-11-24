import 'package:bao_agent/bao_agent.dart' show ForeignBrief;
import 'package:baocode/kernel/antigravity/agy_context.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> user(Object content) => {
  'type': 'user',
  'message': {'role': 'user', 'content': content},
};

Map<String, Object?> answer(String id, List<Map<String, Object?>> content) => {
  'type': 'assistant',
  'message': {'id': id, 'role': 'assistant', 'content': content},
};

Map<String, int> categories(Map<String, Object?> usage) => {
  for (final category in usage['categories'] as List)
    (category as Map)['name'] as String: category['tokens'] as int,
};

void main() {
  const brief = ForeignBrief(
    files: [(path: '/p/CLAUDE.md', type: 'Project', text: 'x')],
    skills: [(name: 'review', text: 'y')],
  );

  test('agy\'s own turns counted; other models\' left to the handoff', () {
    final chain = [
      user('on Claude ${'c' * 4000}'),
      answer('msg_01', [
        {'type': 'text', 'text': 'Claude ${'c' * 4000}'},
      ]),
      user([
        {'type': 'text', 'text': 'a' * 400},
      ]),
      answer('msg_agy_1', [
        {
          'type': 'tool_use',
          'id': 'toolu_agy_r',
          'name': 'Read',
          'input': {'file_path': '/p/a'},
        },
      ]),
      user([
        {
          'type': 'tool_result',
          'tool_use_id': 'toolu_agy_r',
          'content': 'r' * 800,
        },
      ]),
      answer('msg_agy_2', [
        {'type': 'text', 'text': 'b' * 200},
      ]),
    ];
    final usage = agyContextUsage(
      used: 20000,
      size: 1 << 20,
      brief: ForeignBrief(
        files: [(path: '/p/CLAUDE.md', type: 'Project', text: 'm' * 4000)],
        skills: [(name: 'review', text: 's' * 400)],
      ),
      chain: chain,
      handedOff: 50,
    );
    final parts = categories(usage);
    expect(parts['Memory files'], 1000);
    expect(parts['Skills'], 100);
    final breakdown = usage['messageBreakdown'] as Map;
    // The prompt it answered and the handoff; not Claude's turn.
    expect(breakdown['userMessageTokens'], 100 + 50);
    expect(breakdown['assistantMessageTokens'], 50);
    expect(breakdown['toolResultTokens'], 200);
    final read = (breakdown['toolCallsByType'] as List).single as Map;
    expect(read['name'], 'Read');
    expect(read['resultTokens'], 200);
    // agy's own prompt and tools: the rest of what it said it used.
    expect(parts['System prompt'], 20000 - 1000 - 100 - parts['Messages']!);
    expect(parts['Free space'], (1 << 20) - 20000);
    expect(usage['totalTokens'], 20000);
  });

  test('more estimated than used (agy compacted): scaled into it', () {
    final usage = agyContextUsage(
      used: 1000,
      size: 100000,
      brief: brief,
      chain: [
        user('q' * 40000),
        answer('msg_agy_1', [
          {'type': 'text', 'text': 'a' * 40000},
        ]),
      ],
    );
    final parts = categories(usage);
    final told = parts.entries
        .where((part) => part.key != 'Free space')
        .fold(0, (sum, part) => sum + part.value);
    expect(told, 1000);
    expect(parts['System prompt'], greaterThanOrEqualTo(0));
  });

  test('nothing used yet: only the window', () {
    final usage = agyContextUsage(used: 0, size: 1000, brief: brief);
    expect(categories(usage), {'Free space': 1000});
  });

  test('Han counts about one token each, ASCII about four characters', () {
    expect(agyTokens('abcdefgh'), 2);
    expect(agyTokens('你好'), 2);
  });
}
