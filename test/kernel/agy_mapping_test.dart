import 'package:baocode/kernel/antigravity/acp_to_claude.dart';
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/handoff.dart';
import 'package:flutter_test/flutter_test.dart';

AcpToolCall call(Map<String, Object?> update) =>
    AcpToolCall('${update['toolCallId'] ?? 'c1'}')..merge(update);

void main() {
  group('tools as Claude Code\'s', () {
    test('an edit: the lines it changed, numbered as in the file', () {
      final edit = call({
        'kind': 'edit',
        'status': 'completed',
        'content': [
          {
            'type': 'diff',
            'path': '/p/a.txt',
            'oldText': 'one\ntwo\nthree',
            'newText': 'one\n2\nthree',
          },
        ],
      });
      final use = claudeToolUse(edit);
      expect(use.name, 'Edit');
      expect(use.input['old_string'], 'one\ntwo\nthree');
      expect(use.input['new_string'], 'one\n2\nthree');
      final result = claudeToolResult(
        edit,
        use.name,
        fileText: 'zero\none\n2\nthree\nfour',
      );
      final hunk =
          (result.structured!['structuredPatch'] as List).single as Map;
      expect(hunk['oldStart'], 2);
      expect(hunk['lines'], [' one', '-two', '+2', ' three']);
      expect(result.structured!.containsKey('originalFile'), isFalse);
    });

    test('a whole file told: its original kept', () {
      final edit = call({
        'kind': 'edit',
        'status': 'completed',
        'content': [
          {
            'type': 'diff',
            'path': '/p/a.txt',
            'oldText': 'a\nb',
            'newText': 'a\nc',
          },
        ],
      });
      final result = claudeToolResult(edit, 'Edit', fileText: 'a\nc');
      expect(result.structured!['originalFile'], 'a\nb');
    });

    test('a new file: Write, created', () {
      final write = call({
        'kind': 'edit',
        'status': 'completed',
        'content': [
          {'type': 'diff', 'path': '/p/new.txt', 'newText': 'hi'},
        ],
      });
      expect(claudeToolUse(write).name, 'Write');
      expect(claudeToolResult(write, 'Write').structured!['type'], 'create');
    });

    test('commands, reads, searches and the app\'s own tools', () {
      expect(
        claudeToolUse(
          call({
            'kind': 'execute',
            'rawInput': {'CommandLine': 'ls', 'toolSummary': 'List'},
          }),
        ).input,
        {'command': 'ls', 'description': 'List'},
      );
      expect(
        claudeToolUse(
          call({
            'kind': 'read',
            'rawInput': {'Path': '/p/a'},
          }),
        ).input,
        {'file_path': '/p/a'},
      );
      expect(
        claudeToolUse(
          call({
            'kind': 'search',
            'rawInput': {'Query': 'foo'},
          }),
        ).name,
        'Grep',
      );
      final own = claudeToolUse(
        call({
          'name': 'mcp_baocode_session_list',
          'rawInput': {'toolSummary': 'x', 'a': 1},
        }),
        servers: const ['baocode'],
      );
      expect(own.name, 'mcp__baocode__session_list');
      expect(own.input, {'a': 1});
    });

    test('a search of the web: WebSearch, its results not told', () {
      final search = call({
        'name': 'search_web',
        'kind': 'search',
        'status': 'completed',
        'title': '"ai papers" on Web',
        'rawInput': {'query': 'ai papers'},
      });
      final use = claudeToolUse(search);
      expect(use.name, 'WebSearch');
      expect(use.input, {'query': 'ai papers'});
      expect(claudeToolResult(search, use.name).content, '');
    });

    test('a failed command says its exit code', () {
      final result = claudeToolResult(
        call({
          'kind': 'execute',
          'status': 'completed',
          'rawOutput': {'exit_code': 2},
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'Command output:\nboom'},
            },
          ],
        }),
        'Bash',
      );
      expect(result.isError, isTrue);
      expect(result.content, 'Exit code 2\nboom');
    });

    test('a failed command with no output still says something: the API '
        'refuses an error with empty content (400)', () {
      final result = claudeToolResult(
        call({'kind': 'execute', 'status': 'failed'}),
        'Bash',
      );
      expect(result.isError, isTrue);
      expect(result.content, '(no output)');
    });

    test('ids as the API takes them', () {
      expect(claudeToolId('a b/c'), 'toolu_agy_a_b_c');
    });
  });

  group('handoff', () {
    Map<String, Object?> user(String uuid, String text) => {
      'type': 'user',
      'uuid': uuid,
      'message': {'role': 'user', 'content': text},
    };
    Map<String, Object?> answer(String uuid, List<Map> content) => {
      'type': 'assistant',
      'uuid': uuid,
      'message': {'role': 'assistant', 'content': content},
    };

    test('only what came after, without results or thoughts', () {
      final chain = [
        user('1', 'seen already'),
        user('2', 'new <system-reminder>aside</system-reminder>'),
        answer('3', [
          {'type': 'thinking', 'thinking': 'secret'},
          {
            'type': 'tool_use',
            'id': 't',
            'name': 'Read',
            'input': {'file_path': '/a'},
          },
        ]),
        {
          'type': 'user',
          'uuid': '4',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'tool_result', 'tool_use_id': 't', 'content': 'body'},
            ],
          },
        },
        answer('5', [
          {'type': 'text', 'text': 'read it'},
        ]),
      ];
      final told = handoffReminder(chain, syncedUuid: '1')!;
      expect(told, startsWith('<system-reminder>'));
      expect(told, isNot(contains('seen already')));
      expect(told, isNot(contains('secret')));
      expect(told, isNot(contains('body')));
      expect(told, isNot(contains('aside')));
      expect(told, contains('"text":"new"'));
      expect(told, contains('"name":"Read"'));
      expect(told, contains('read it'));
      expect(handoffReminder(chain, syncedUuid: '5'), isNull);
    });

    test('past its budget: the first and the last kept', () {
      final chain = [
        for (var i = 0; i < 50; i++) user('$i', 'message $i ${'x' * 500}'),
      ];
      final told = handoffReminder(chain, budget: 3000)!;
      expect(told, contains('message 0 '));
      expect(told, contains('message 49 '));
      expect(told, isNot(contains('message 20 ')));
      expect(told, contains('earlier messages left out'));
    });
  });

  group('agy\'s own', () {
    test('update_steps as TodoWrite', () {
      final call = AcpToolCall('call_1')
        ..merge({
          'name': 'update_steps',
          'kind': 'other',
          'title': 'Run update_steps',
          'status': 'completed',
          'rawInput': {
            'steps': [
              {'status': 'done', 'title': 'Read'},
              {'status': 'in_progress', 'title': 'Run'},
              {'status': 'pending', 'title': 'Report'},
            ],
          },
        });
      final use = claudeToolUse(call);
      expect(use.name, 'TodoWrite');
      expect(use.input['todos'], [
        {'content': 'Read', 'status': 'completed', 'activeForm': 'Read'},
        {'content': 'Run', 'status': 'in_progress', 'activeForm': 'Run'},
        {'content': 'Report', 'status': 'pending', 'activeForm': 'Report'},
      ]);
      final result = claudeToolResult(call, 'TodoWrite');
      expect(result.content, 'Todos have been modified successfully.');
      expect(result.structured, {'newTodos': use.input['todos']});
    });

    test('call_mcp_tool as the MCP tool it reaches, not a command', () {
      final call = AcpToolCall('call_2')
        ..merge({
          'kind': 'execute',
          'title': 'MCP Tool browser_open',
          'status': 'in_progress',
          'rawInput': {
            'ServerName': 'baocode',
            'ToolName': 'browser_open',
            'Arguments': {'url': 'https://example.com'},
          },
        });
      final use = claudeToolUse(call, servers: ['baocode']);
      expect(use.name, 'mcp__baocode__browser_open');
      expect(use.input, {'url': 'https://example.com'});
    });

    test('an MCP tool\'s result, as its server answered it', () {
      final call = AcpToolCall('call_3')
        ..merge({'name': 'mcp_baocode_shot', 'status': 'completed'});
      expect(
        claudeToolResult(
          call,
          'mcp__baocode__shot',
          mcpResult: {
            'content': [
              {'type': 'text', 'text': 'opened'},
            ],
          },
        ).content,
        'opened',
      );
      final shot = claudeToolResult(
        call,
        'mcp__baocode__shot',
        mcpResult: {
          'isError': false,
          'content': [
            {'type': 'text', 'text': 'here'},
            {'type': 'image', 'data': 'AAAA', 'mimeType': 'image/png'},
          ],
        },
      );
      expect(shot.content, [
        {'type': 'text', 'text': 'here'},
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': 'image/png',
            'data': 'AAAA',
          },
        },
      ]);
    });
  });

  group('questions', () {
    // As agy 1.5.16 sends its ask_question's.
    const schema = {
      'type': 'object',
      'properties': {
        'q1': {
          'type': 'array',
          'title': 'Which colors?',
          'items': {
            'anyOf': [
              {'const': '1', 'title': 'red'},
              {'const': '2', 'title': 'green, light'},
              {'const': '3', 'title': 'green'},
            ],
          },
        },
        'q1_other': {
          'type': 'string',
          'title': 'Other',
          'description': 'Optional free-form answer to: Which colors?',
        },
        'q2': {
          'type': 'string',
          'title': 'Which size?',
          'oneOf': [
            {'const': '1', 'title': '(Recommended) S'},
            {'const': '2', 'title': 'L'},
          ],
        },
        'q2_other': {'type': 'string', 'title': 'Other'},
      },
    };

    test('a form put as AskUserQuestion\'s questions', () {
      final form = AgyQuestionForm.of(schema)!;
      expect(form.questions, [
        {
          'question': 'Which colors?',
          'header': '',
          'options': [
            {'label': 'red', 'description': ''},
            {'label': 'green, light', 'description': ''},
            {'label': 'green', 'description': ''},
          ],
          'multiSelect': true,
        },
        {
          'question': 'Which size?',
          'header': '',
          'options': [
            {'label': '(Recommended) S', 'description': ''},
            {'label': 'L', 'description': ''},
          ],
          'multiSelect': false,
        },
      ]);
    });

    test('the picks given back as numbers, the rest in words', () {
      final form = AgyQuestionForm.of(schema)!;
      expect(
        form.content({
          'Which colors?': 'green, light, red, teal',
          'Which size?': 'L',
        }),
        {
          'q1': ['2', '1'],
          'q1_other': 'teal',
          'q2': '2',
        },
      );
      expect(form.content({'Which size?': 'XL'}), {'q2_other': 'XL'});
    });

    test('a form with a field to write in, not a question', () {
      expect(
        AgyQuestionForm.of({
          'properties': {
            'name': {'type': 'string', 'title': 'Name'},
          },
        }),
        isNull,
      );
    });

    test('ask_question\'s call as AskUserQuestion', () {
      final call = AcpToolCall('call_1')
        ..merge({
          'name': 'ask_question',
          'kind': 'other',
          'rawInput': {
            'questions': [
              {
                'question': 'Which?',
                'options': ['a', 'b'],
                'is_multi_select': false,
              },
            ],
          },
        });
      final use = claudeToolUse(call);
      expect(use.name, 'AskUserQuestion');
      expect((use.input['questions'] as List).single, {
        'question': 'Which?',
        'header': '',
        'options': [
          {'label': 'a', 'description': ''},
          {'label': 'b', 'description': ''},
        ],
        'multiSelect': false,
      });
      final result = claudeToolResult(
        call,
        'AskUserQuestion',
        answers: {'Which?': 'b'},
      );
      expect(result.content, contains('"Which?"="b"'));
      expect(result.structured, {
        'answers': {'Which?': 'b'},
      });
    });
  });

  test('agy models: thinking levels as one model', () {
    final models = parseAgyModels(
      'gemini-3.8-flash-low\tGemini 3.8 Flash (Low)\n'
      'gemini-3.8-flash-high\tGemini 3.8 Flash (High)\n'
      'claude-sonnet-4-6\tClaude Sonnet 4.6\n'
      'Loading…\n',
    );
    expect(models, const [
      AgyModel(
        'gemini-3.8-flash',
        'Gemini 3.8 Flash',
        efforts: ['low', 'high'],
      ),
      AgyModel('claude-sonnet-4-6', 'Claude Sonnet 4.6'),
    ]);
  });
}
