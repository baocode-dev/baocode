import 'package:baocode/browser/browser_tools.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const schema = {
    'type': 'object',
    'properties': {
      'tabId': {'type': 'integer'},
      'x': {'type': 'number'},
      'text': {'type': 'string'},
      'steps': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'tabId': {'type': 'integer'},
            'text': {'type': 'string'},
          },
        },
      },
    },
  };

  test('numbers sent as text are numbers where the schema asks for them, '
      'at any depth', () {
    expect(
      BrowserTools.numbersAsSchemaSays(schema, {
        'tabId': '406885479',
        'x': ' 12.5 ',
        'text': '123',
        'steps': [
          {'tabId': '7', 'text': '42'},
        ],
        'other': '9',
      }),
      {
        'tabId': 406885479,
        'x': 12.5,
        'text': '123',
        'steps': [
          {'tabId': 7, 'text': '42'},
        ],
        'other': '9',
      },
    );
  });

  test('text that is no number is left for the tool to refuse', () {
    expect(BrowserTools.numbersAsSchemaSays(schema, {'tabId': 'first'}), {
      'tabId': 'first',
    });
    expect(BrowserTools.numbersAsSchemaSays(schema, {'tabId': 3.0}), {
      'tabId': 3,
    });
  });

  test(
    'every tool taking a tab has it as a number, sent as text (#274)',
    () async {
      BrowserTools.register();
      addTearDown(BrowserTools.unregister);
      final listed = await ClaudeSdkTools.handle({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/list',
      }, const ClaudeSdkCall(cwd: '/p'));
      final tools = ((listed['result'] as Map)['tools'] as List).cast<Map>();
      final taking = [
        for (final tool in tools)
          if (((tool['inputSchema'] as Map)['properties'] as Map).containsKey(
            'tabId',
          ))
            tool,
      ];
      expect(taking.map((t) => t['name']), contains('browser_snapshot'));
      for (final tool in taking) {
        final schema = (tool['inputSchema'] as Map).cast<String, Object?>();
        expect(
          BrowserTools.numbersAsSchemaSays(schema, {'tabId': '5'})['tabId'],
          5,
          reason: '${tool['name']}',
        );
      }
    },
  );
}
