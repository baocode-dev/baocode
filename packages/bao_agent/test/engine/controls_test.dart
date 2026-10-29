import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// An MCP server on stdio: a tool, a resource, a prompt.
const _stdioServer = r'''
import sys, json
def send(o):
    o['jsonrpc'] = '2.0'
    sys.stdout.write(json.dumps(o) + "\n")
    sys.stdout.flush()
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    m = json.loads(line)
    if 'id' not in m:
        continue
    method, i, params = m.get('method'), m['id'], m.get('params') or {}
    if method == 'initialize':
        send({'id': i, 'result': {'protocolVersion': params.get('protocolVersion', '2025-06-18'),
              'capabilities': {'tools': {}, 'resources': {}, 'prompts': {}},
              'serverInfo': {'name': 'py', 'version': '1'},
              'instructions': 'Use add for sums.'}})
    elif method == 'tools/list':
        send({'id': i, 'result': {'tools': [{'name': 'add', 'description': 'Adds two numbers',
              'inputSchema': {'type': 'object', 'properties': {'a': {'type': 'number'}, 'b': {'type': 'number'}}}}]}})
    elif method == 'tools/call':
        a = params['arguments']
        send({'id': i, 'result': {'content': [{'type': 'text', 'text': str(a['a'] + a['b'])}]}})
    elif method == 'resources/list':
        send({'id': i, 'result': {'resources': [{'uri': 'mem://note', 'name': 'note', 'mimeType': 'text/plain'}]}})
    elif method == 'resources/read':
        send({'id': i, 'result': {'contents': [{'uri': params['uri'], 'mimeType': 'text/plain', 'text': 'remember milk'}]}})
    elif method == 'prompts/list':
        send({'id': i, 'result': {'prompts': [{'name': 'greet', 'description': 'Greets', 'arguments': [{'name': 'who'}]}]}})
    elif method == 'prompts/get':
        who = (params.get('arguments') or {}).get('who', '')
        send({'id': i, 'result': {'messages': [{'role': 'user', 'content': {'type': 'text', 'text': 'Say hi to ' + who}}]}})
    else:
        send({'id': i, 'error': {'code': -32601, 'message': 'no ' + str(method)}})
''';

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  String sentIn(ModelRequest request) => jsonEncode(request.body['messages']);

  group('control requests', () {
    test('settings: the model and effort set, and said', () async {
      h = await Harness.start();
      await h.request('set_model', {'model': 'sonnet'});
      var applied = (await h.request('get_settings'))['applied'] as Map;
      expect(applied['model'], contains('sonnet'));
      await h.request('apply_flag_settings', {
        'settings': {'model': 'haiku', 'effortLevel': 'low'},
      });
      applied = (await h.request('get_settings'))['applied'] as Map;
      expect(applied['model'], contains('haiku'));
      expect(applied['effort'], 'low');
      h.model.script.add(Reply.text('ok'));
      await h.turn('hi');
      expect(h.model.turns.single.model, contains('haiku'));
      expect(h.of('system', 'init').single['model'], contains('haiku'));
    });

    test('get_context_usage, get_usage, file_suggestions', () async {
      h = await Harness.start(
        files: {
          'README.md': '# Hi',
          'lib/reader.dart': '',
          'CLAUDE.md': 'Be brief.',
        },
      );
      h.model.script.add(Reply.text('ok'));
      await h.turn('hi');
      final context = await h.request('get_context_usage');
      expect(context['maxTokens'], greaterThan(0));
      expect(context['totalTokens'], greaterThan(0));
      final names = [
        for (final c in context['categories'] as List) (c as Map)['name'],
      ];
      expect(names, containsAll(['System prompt', 'System tools', 'Messages']));
      expect(jsonEncode(context), contains('CLAUDE.md'));
      final usage = await h.request('get_usage');
      expect(usage['rate_limits_available'], isFalse);
      final files = await h.request('file_suggestions', {'query': 'rea'});
      final paths = [
        for (final s in files['suggestions'] as List) (s as Map)['path'],
      ];
      expect(paths, containsAll(['README.md', 'lib/reader.dart']));
    });

    test('rewind_conversation: the turns after it are gone', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.text('one'),
        Reply.text('two'),
        Reply.text('three'),
      ]);
      var idle = h.nextIdle();
      h.send('first', uuid: 'u-first');
      await idle;
      idle = h.nextIdle();
      h.send('second', uuid: 'u-second');
      await idle;
      final answer = await h.request('rewind_conversation', {
        'target_message_uuid': 'u-second',
      });
      expect(answer['rewound'], isTrue);
      expect(
        (await h.request('rewind_conversation', {
          'target_message_uuid': 'nope',
        }))['rewound'],
        isFalse,
      );
      await h.turn('again');
      final sent = sentIn(h.model.turns.last);
      expect(
        sent,
        allOf(contains('first'), contains('one'), contains('again')),
      );
      expect(sent, isNot(contains('second')));
    });

    test('rewind_files: the files as they were before a prompt', () async {
      h = await Harness.start(files: {'kept.txt': 'old\n'});
      h.model.script.addAll([
        Reply.tool('Read', {'file_path': p.join(h.cwd, 'kept.txt')}),
        Reply.tools([
          (
            'Edit',
            {
              'file_path': p.join(h.cwd, 'kept.txt'),
              'old_string': 'old',
              'new_string': 'new',
            },
          ),
          ('Write', {'file_path': p.join(h.cwd, 'made.txt'), 'content': 'x'}),
        ]),
        Reply.text('ok'),
      ]);
      final idle = h.nextIdle();
      h.send('change them', uuid: 'u-change');
      await idle;
      expect(h.file('kept.txt'), 'new\n');
      final dry = await h.request('rewind_files', {
        'user_message_id': 'u-change',
        'dry_run': true,
      });
      expect(dry['canRewind'], isTrue);
      expect(
        (dry['filesChanged'] as List).map((f) => p.basename('$f')),
        unorderedEquals(['kept.txt', 'made.txt']),
      );
      expect(h.file('kept.txt'), 'new\n');
      await h.request('rewind_files', {'user_message_id': 'u-change'});
      expect(h.file('kept.txt'), 'old\n');
      expect(File(p.join(h.cwd, 'made.txt')).existsSync(), isFalse);
      expect(
        (await h.request('rewind_files', {
          'user_message_id': 'nope',
        }))['canRewind'],
        isFalse,
      );
    });

    test(
      'an unknown request is an error; interrupt when idle is not',
      () async {
        h = await Harness.start();
        expect(() => h.request('no_such_thing'), throwsStateError);
        await h.request('interrupt');
      },
    );

    test('end_session ends it', () async {
      h = await Harness.start();
      await h.request('end_session');
      await h.engine.done.timeout(const Duration(seconds: 10));
      expect(h.engine.closed, isTrue);
    });
  });

  group('API errors', () {
    test('a refused key: the result says so', () async {
      h = await Harness.start();
      h.model.script.add(
        Reply.failing(
          const ApiError(
            'invalid x-api-key',
            status: 401,
            type: 'authentication_error',
          ),
        ),
      );
      await h.turn('hi');
      expect(h.lastResult['is_error'], isTrue);
      expect(
        h.lastResult['result'],
        allOf(contains('401'), contains('invalid x-api-key')),
      );
      // The host is not told twice.
      expect(h.of('assistant'), isEmpty);
    });

    test('thinking or effort refused: asked again without', () async {
      h = await Harness.start(
        effort: 'high',
        settings: {'alwaysThinkingEnabled': true},
      );
      h.model.script.addAll([
        Reply.failing(
          const ApiError('thinking: not supported by this model', status: 400),
        ),
        Reply.failing(
          const ApiError(
            'output_config.effort: Extra inputs are not permitted',
            status: 400,
          ),
        ),
        Reply.text('fine'),
      ]);
      await h.turn('hi');
      expect(h.lastResult['result'], 'fine');
      final [first, second, third] = h.model.turns;
      expect(first.body, contains('thinking'));
      expect(second.body, isNot(contains('thinking')));
      expect(jsonEncode(second.body), contains('effort'));
      expect(
        jsonEncode(third.body['output_config'] ?? {}),
        isNot(contains('effort')),
      );
    });

    test('a prompt too long: compacted, asked again', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.text('first'),
        Reply.failing(
          const ApiError(
            'prompt is too long: 210000 tokens > 200000 maximum',
            status: 400,
          ),
        ),
        Reply.text('<summary>Earlier talk.</summary>'),
        Reply.text('answered'),
      ]);
      await h.turn('one');
      await h.turn('two');
      expect(h.lastResult['result'], 'answered');
      expect(h.of('system', 'compact_boundary'), hasLength(1));
      expect(sentIn(h.model.turns.last), contains('Earlier talk.'));
    });

    test("a subagent's model the provider lacks: the session's own", () async {
      h = await Harness.start();
      final models = <String>[];
      h.model.route = (request) {
        if (!jsonEncode((request.body['messages'] as List).first)
            .contains('SUB:')) {
          return null;
        }
        models.add(request.model);
        return models.length == 1
            ? Reply.failing(const ApiError('model: not found', status: 404))
            : Reply.text('sub done');
      };
      h.model.script.addAll([
        Reply.tool('Agent', {
          'description': 'Look',
          'prompt': 'SUB: look',
          'model': 'haiku',
          'run_in_background': false,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      expect(models.first, contains('haiku'));
      expect(models.last, h.model.turns.first.model);
      expect(
        (h.toolResults.single['tool_use_result'] as Map)['status'],
        'completed',
      );
    });
  });

  group('MCP', () {
    test("the host's own server, through the control channel", () async {
      final calls = <Map>[];
      h = await Harness.start(sdkServers: ['bao']);
      h.onRequest = (request) async {
        if (request['subtype'] != 'mcp_message') return const {};
        final message = request['message'] as Map;
        calls.add(message);
        final id = message['id'];
        Map<String, Object?> result(Map<String, Object?> r) => {
          'mcp_response': {'jsonrpc': '2.0', 'id': id, 'result': r},
        };
        return switch (message['method']) {
          'initialize' => result({
            'protocolVersion': '2025-06-18',
            'capabilities': {'tools': {}},
            'serverInfo': {'name': 'bao', 'version': '1'},
          }),
          'tools/list' => result({
            'tools': [
              {
                'name': 'open_page',
                'description': 'Opens a page',
                'inputSchema': {
                  'type': 'object',
                  'properties': {
                    'url': {'type': 'string'},
                  },
                },
              },
            ],
          }),
          'tools/call' => result({
            'content': [
              {
                'type': 'text',
                'text':
                    'opened ${(message['params'] as Map)['arguments']['url']}',
              },
            ],
          }),
          _ => {
            'mcp_response': {'jsonrpc': '2.0', 'id': id, 'result': {}},
          },
        };
      };
      h.model.script.addAll([
        Reply.tool('mcp__bao__open_page', {'url': 'https://example.com'}),
        Reply.text('ok'),
      ]);
      await h.turn('open it');
      final init = h.of('system', 'init').single;
      expect(init['tools'], contains('mcp__bao__open_page'));
      expect(
        init['mcp_servers'],
        contains(
          allOf(
            containsPair('name', 'bao'),
            containsPair('status', 'connected'),
          ),
        ),
      );
      expect(
        jsonEncode(h.toolResults.single['content']),
        contains('opened https://example.com'),
      );
      expect(
        calls.map((c) => c['method']),
        containsAll(['initialize', 'tools/list', 'tools/call']),
      );
    });

    test(
      "a server's errors, structured and large results, binary resources",
      () async {
        h = await Harness.start(
          sdkServers: ['kit'],
          environment: {'MAX_MCP_OUTPUT_TOKENS': '50'},
        );
        h.onRequest = (request) async {
          final message = request['message'] as Map;
          final id = message['id'];
          Map<String, Object?> answer(Object result) => {
            'mcp_response': {'jsonrpc': '2.0', 'id': id, 'result': result},
          };
          final params = (message['params'] as Map?) ?? {};
          return switch (message['method']) {
            'initialize' => answer({
              'protocolVersion': '2025-06-18',
              'capabilities': {'tools': {}, 'resources': {}},
              'serverInfo': {'name': 'kit', 'version': '1'},
            }),
            'tools/list' => answer({
              'tools': [
                for (final name in ['fails', 'structured', 'big', 'errs'])
                  {
                    'name': name,
                    'description': name,
                    'inputSchema': {'type': 'object'},
                  },
              ],
            }),
            'resources/list' => answer({
              'resources': [
                {'uri': 'mem://bin', 'name': 'bin'},
              ],
            }),
            'resources/read' => answer({
              'contents': [
                {
                  'uri': 'mem://bin',
                  'mimeType': 'application/octet-stream',
                  'blob': 'AAAAAAAA',
                },
              ],
            }),
            'tools/call' => switch (params['name']) {
              'fails' => {
                'mcp_response': {
                  'jsonrpc': '2.0',
                  'id': id,
                  'error': {'code': -32000, 'message': 'tool broke'},
                },
              },
              'structured' => answer({
                'content': [],
                'structuredContent': {'answer': 42},
              }),
              'big' => answer({
                'content': [
                  {'type': 'text', 'text': 'x' * 1000},
                  {'type': 'text', 'text': 'more'},
                ],
              }),
              _ => answer({
                'isError': true,
                'content': [
                  {'type': 'text', 'text': 'bad input'},
                ],
              }),
            },
            _ => answer({}),
          };
        };
        h.model.script.addAll([
          Reply.tools([
            ('mcp__kit__fails', {}),
            ('mcp__kit__structured', {}),
            ('mcp__kit__big', {}),
            ('mcp__kit__errs', {}),
            ('ReadMcpResourceTool', {'server': 'kit', 'uri': 'mem://bin'}),
            ('ReadMcpResourceTool', {'server': 'none', 'uri': 'x'}),
            ('ListMcpResourcesTool', {'server': 'none'}),
          ]),
          Reply.text('ok'),
        ]);
        await h.turn('go');
        final [fails, structured, big, errs, blob, noServer, noList] = [
          for (final r in h.toolResults) jsonEncode(r['content']),
        ];
        expect(fails, contains('MCP error: tool broke'));
        expect(structured, contains('{\\"answer\\":42}'));
        expect(big, contains('MAX_MCP_OUTPUT_TOKENS'));
        expect(big.length, lessThan(800));
        expect(errs, contains('bad input'));
        expect(h.toolResults[3]['is_error'], isTrue);
        expect(blob, contains('[binary content, 6 bytes]'));
        expect(noServer, contains('is connected'));
        expect(noList, contains('is connected'));
      },
    );

    String? python() {
      try {
        final found = Process.runSync('python3', [
          '-c',
          'import sys; print(sys.executable)',
        ]);
        return found.exitCode == 0 ? '${found.stdout}'.trim() : null;
      } on ProcessException {
        return null;
      }
    }

    test(
      'a stdio server: tools, resources, prompts, status and toggling',
      () async {
        final interpreter = python()!;
        final dir = Directory.systemTemp
            .createTempSync('mcp_')
            .resolveSymbolicLinksSync();
        addTearDown(() => Directory(dir).deleteSync(recursive: true));
        final server = File(p.join(dir, 'server.py'))
          ..writeAsStringSync(_stdioServer);
        h = await Harness.start(
          files: {
            '.mcp.json': jsonEncode({
              'mcpServers': {
                'py': {
                  'command': interpreter,
                  'args': ['-I', server.path],
                },
              },
            }),
          },
        );
        h.model.script.addAll([
          Reply.tools([
            ('mcp__py__add', {'a': 2, 'b': 3}),
            ('ListMcpResourcesTool', {}),
            ('ReadMcpResourceTool', {'server': 'py', 'uri': 'mem://note'}),
          ]),
          Reply.text('5'),
        ]);
        await h.turn('add');
        final [sum, list, read] = h.toolResults;
        expect(jsonEncode(sum['content']), contains('5'));
        expect(jsonEncode(list['content']), contains('mem://note'));
        expect(jsonEncode(read['content']), contains('remember milk'));
        // What the server says of its tools, in the context.
        expect(
          jsonEncode(h.model.turns.first.body['messages']),
          contains('Use add for sums.'),
        );
        // Its prompt, as a command.
        expect(
          h.of('system', 'init').last['slash_commands'],
          contains('mcp__py__greet'),
        );
        h.model.script.add(Reply.text('hi Ada'));
        await h.turn('/mcp__py__greet Ada');
        expect(sentIn(h.model.turns.last), contains('Say hi to Ada'));
        final status = await h.request('mcp_status');
        expect(
          status['mcpServers'],
          contains(
            allOf(
              containsPair('name', 'py'),
              containsPair('status', 'connected'),
            ),
          ),
        );
        await h.request('mcp_toggle', {'serverName': 'py', 'enabled': false});
        h.model.script.add(Reply.text('ok'));
        await h.turn('again');
        final names = [
          for (final t in h.model.turns.last.body['tools'] as List)
            (t as Map)['name'],
        ];
        expect(names, isNot(contains('mcp__py__add')));
        await h.request('mcp_toggle', {'serverName': 'py', 'enabled': true});
        await h.request('mcp_reconnect', {'serverName': 'py'});
        h.model.script.add(Reply.text('ok'));
        await h.turn('and again');
        final back = [
          for (final t in h.model.turns.last.body['tools'] as List)
            (t as Map)['name'],
        ];
        expect(back, contains('mcp__py__add'));
      },
      skip: python() == null ? 'no python3' : false,
    );

    test('an HTTP server', () async {
      final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => http.close(force: true));
      http.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        final id = body['id'];
        request.response.headers.contentType = ContentType.json;
        request.response.headers.set('mcp-session-id', 's1');
        if (id == null) {
          request.response.statusCode = 202;
        } else {
          request.response.write(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': id,
              'result': switch (body['method']) {
                'initialize' => {
                  'protocolVersion': '2025-06-18',
                  'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'web', 'version': '1'},
                },
                'tools/list' => {
                  'tools': [
                    {
                      'name': 'ping',
                      'description': 'Ping',
                      'inputSchema': {'type': 'object'},
                    },
                  ],
                },
                'tools/call' => {
                  'content': [
                    {'type': 'text', 'text': 'pong'},
                  ],
                },
                _ => {},
              },
            }),
          );
        }
        await request.response.close();
      });
      h = await Harness.start(
        flagSettings: {
          'mcpServers': {
            'web': {'type': 'http', 'url': 'http://127.0.0.1:${http.port}/mcp'},
          },
        },
      );
      h.model.script.addAll([
        Reply.tool('mcp__web__ping', {}),
        Reply.text('ok'),
      ]);
      await h.turn('ping');
      expect(jsonEncode(h.toolResults.single['content']), contains('pong'));
    });
  });
}
