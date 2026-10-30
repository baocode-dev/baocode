import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  /// The text of the request's messages, as sent.
  String sentIn(ModelRequest request) => jsonEncode(request.body['messages']);

  group('files', () {
    test(
      'write, read, edit; an edit of what was not read is refused',
      () async {
        h = await Harness.start(files: {'old.txt': 'alpha\nbeta\n'});
        final path = p.join(h.cwd, 'new.txt');
        h.model.script.addAll([
          Reply.tool('Edit', {
            'file_path': p.join(h.cwd, 'old.txt'),
            'old_string': 'beta',
            'new_string': 'gamma',
          }),
          Reply.tool('Write', {'file_path': path, 'content': 'one\ntwo\n'}),
          Reply.tool('Read', {'file_path': path}),
          Reply.tool('Edit', {
            'file_path': path,
            'old_string': 'two',
            'new_string': 'three',
          }),
          Reply.text('ok'),
        ]);
        await h.turn('files');
        final results = h.toolResults;
        expect(results[0]['is_error'], isTrue);
        expect('${results[0]['content']}', contains('has not been read'));
        expect((results[1]['tool_use_result'] as Map)['type'], 'create');
        expect('${results[2]['content']}', contains('1\tone'));
        final edit = results[3]['tool_use_result'] as Map;
        expect(edit['structuredPatch'], isNotEmpty);
        expect(h.file('new.txt'), 'one\nthree\n');
        expect(h.file('old.txt'), 'alpha\nbeta\n');
      },
    );

    test('a file changed since it was read must be read again', () async {
      h = await Harness.start(files: {'a.txt': 'one\n'});
      final path = p.join(h.cwd, 'a.txt');
      h.model.script.addAll([
        Reply.tool('Read', {'file_path': path}),
        Reply.tool('Bash', {
          'command': 'sleep 1.1; echo changed > a.txt',
          'description': 'Change',
        }),
        Reply.tool('Edit', {
          'file_path': path,
          'old_string': 'changed',
          'new_string': 'x',
        }),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      expect(
        '${h.toolResults.last['content']}',
        contains('changed since it was read'),
      );
      expect(h.file('a.txt'), 'changed\n');
    });

    test('NotebookEdit: a cell replaced and one inserted', () async {
      final notebook = {
        'cells': [
          {
            'cell_type': 'code',
            'id': 'c1',
            'metadata': {},
            'source': ['print(1)\n'],
            'outputs': [],
            'execution_count': 1,
          },
        ],
        'metadata': {
          'language_info': {'name': 'python'},
        },
        'nbformat': 4,
        'nbformat_minor': 5,
      };
      h = await Harness.start(files: {'n.ipynb': jsonEncode(notebook)});
      final path = p.join(h.cwd, 'n.ipynb');
      h.model.script.addAll([
        Reply.tool('Read', {'file_path': path}),
        Reply.tool('NotebookEdit', {
          'notebook_path': path,
          'cell_id': 'c1',
          'new_source': 'print(2)',
        }),
        Reply.tool('NotebookEdit', {
          'notebook_path': path,
          'cell_id': 'c1',
          'new_source': '# Title',
          'cell_type': 'markdown',
          'edit_mode': 'insert',
        }),
        Reply.text('ok'),
      ]);
      await h.turn('edit the notebook');
      expect('${h.toolResults.first['content']}', contains('print(1)'));
      final cells = (jsonDecode(h.file('n.ipynb')) as Map)['cells'] as List;
      expect(cells, hasLength(2));
      expect(jsonEncode(cells[0]), contains('print(2)'));
      expect((cells[0] as Map)['outputs'], isEmpty);
      expect((cells[1] as Map)['cell_type'], 'markdown');
    });

    test(
      'no to-do list tools: TodoWrite and TaskOutput are not offered',
      () async {
        h = await Harness.start();
        h.model.script.add(Reply.text('ok'));
        await h.turn('plan');
        final names = [
          for (final tool in h.model.turns.single.body['tools']! as List)
            (tool as Map)['name'],
        ];
        expect(names, isNot(contains('TodoWrite')));
        expect(names, isNot(contains('TaskOutput')));
        expect(
          names,
          containsAll(['CronCreate', 'ScheduleWakeup', 'SendMessage']),
        );
      },
    );
  });

  group('web', () {
    late HttpServer server;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        if (request.uri.path == '/missing') {
          request.response.statusCode = 404;
        } else {
          request.response.headers.contentType = ContentType.html;
          request.response.write(
            '<html><body><h1>Release notes</h1><p>Version 9 ships today.</p></body></html>',
          );
        }
        request.response.close();
      });
    });

    tearDown(() => server.close(force: true));

    test('WebFetch reads the page and answers from it', () async {
      String? page;
      h = await Harness.start(
        errands: (request) {
          final prompt = sentIn(request);
          if (!prompt.contains('Web page content')) return null;
          page = prompt;
          return Reply.text('Version 9.');
        },
      );
      final url = 'http://127.0.0.1:${server.port}/notes';
      h.model.script.addAll([
        Reply.tools([
          ('WebFetch', {'url': url, 'prompt': 'Which version?'}),
          (
            'WebFetch',
            {'url': 'http://127.0.0.1:${server.port}/missing', 'prompt': 'x'},
          ),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('fetch');
      expect(
        page,
        allOf(contains('# Release notes'), contains('Which version?')),
      );
      final [found, missing] = h.toolResults;
      expect(found['content'], 'Version 9.');
      expect((found['tool_use_result'] as Map)['code'], 200);
      expect(missing['is_error'], isTrue);
      expect(
        jsonEncode(h.permissionRequests.first['permission_suggestions']),
        contains('domain:127.0.0.1'),
      );
    });

    test('WebFetch: redirects followed on the host, told of to another; kept a while', () async {
      var fetched = 0;
      server.close(force: true);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        final response = request.response;
        switch (request.uri.path) {
          case '/moved':
            response.redirect(Uri.parse('/plain'));
            return;
          case '/away':
            response.redirect(
              Uri.parse('http://localhost:${server.port}/plain'),
            );
            return;
          case '/plain':
            fetched++;
            response.headers.contentType = ContentType(
              'text',
              'plain',
              charset: 'iso-8859-1',
            );
            response.add(latin1.encode('caf\u00e9 plain text'));
        }
        response.close();
      });
      String? page;
      h = await Harness.start(
        errands: (request) {
          final prompt = sentIn(request);
          if (!prompt.contains('Web page content')) return null;
          page = prompt;
          return Reply.text('answered');
        },
      );
      final base = 'http://127.0.0.1:${server.port}';
      h.model.script.addAll([
        Reply.tool('WebFetch', {'url': '$base/moved', 'prompt': 'What?'}),
        Reply.tool('WebFetch', {'url': '$base/plain', 'prompt': 'Again?'}),
        Reply.tool('WebFetch', {'url': '$base/away', 'prompt': 'Where?'}),
        Reply.tool('WebFetch', {'url': 'ftp://x', 'prompt': 'Bad'}),
        Reply.text('ok'),
      ]);
      await h.turn('fetch');
      final [moved, again, away, bad] = h.toolResults;
      expect(moved['content'], 'answered');
      expect(page, contains('caf\u00e9 plain text'));
      expect(again['content'], 'answered');
      expect(fetched, 2);
      expect(
        '${away['content']}',
        allOf(contains('sends you to another host'), contains('localhost')),
      );
      expect(bad['is_error'], isTrue);
    });

    test('WebSearch: the API searches; its links come back', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tool('WebSearch', {
          'query': 'dart release',
          'allowed_domains': ['dart.dev'],
        }),
        Reply([
          {
            'type': 'server_tool_use',
            'id': 'srvtoolu_1',
            'name': 'web_search',
            'input': {'query': 'dart release'},
          },
          {
            'type': 'web_search_tool_result',
            'tool_use_id': 'srvtoolu_1',
            'content': [
              {
                'type': 'web_search_result',
                'title': 'Dart 4',
                'url': 'https://dart.dev/4',
                'encrypted_content': 'x',
              },
            ],
          },
          {'type': 'text', 'text': 'Dart 4 is out.'},
        ]),
        Reply.text('Sources: [Dart 4](https://dart.dev/4)'),
      ]);
      await h.turn('search');
      final search = h.model.requests.firstWhere(
        (r) => jsonEncode(r.body['tools']).contains('web_search_20250305'),
      );
      expect(jsonEncode(search.body['tools']), contains('dart.dev'));
      final result = h.toolResults.single;
      expect(
        '${result['content']}',
        allOf(contains('https://dart.dev/4'), contains('Dart 4 is out.')),
      );
      expect((result['tool_use_result'] as Map)['query'], 'dart release');
    });

    test('WebSearch: not offered by the provider', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tools([
          ('WebSearch', {'query': 'xy'}),
          (
            'WebSearch',
            {
              'query': 'xy',
              'allowed_domains': ['a'],
              'blocked_domains': ['b'],
            },
          ),
        ]),
        Reply.failing(
          const ApiError('web_search is not supported', status: 400),
        ),
        Reply.text('ok'),
      ]);
      await h.turn('search');
      final [refused, invalid] = h.toolResults;
      expect('${refused['content']}', contains('Web search is not available'));
      expect('${invalid['content']}', contains('not both'));
    });
  });

  group('shell', () {
    test('output, exit codes, and the shell staying where it went', () async {
      h = await Harness.start(files: {'sub/f.txt': ''});
      h.model.script.addAll([
        Reply.tool('Bash', {
          'command': 'echo out; echo err >&2',
          'description': 'Echo',
        }),
        Reply.tool('Bash', {'command': 'exit 3', 'description': 'Fail'}),
        Reply.tool('Bash', {'command': 'cd sub', 'description': 'Go'}),
        Reply.tool('Bash', {'command': 'ls', 'description': 'List'}),
        Reply.tool('Bash', {'command': 'cd /', 'description': 'Leave'}),
        Reply.tool('Bash', {
          'command': 'sleep 5',
          'description': 'Wait',
          'timeout': 1000,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('run');
      final [echo, fail, _, list, leave, slow] = h.toolResults;
      expect(echo['content'], 'out\nerr');
      expect((echo['tool_use_result'] as Map)['stderr'], 'err');
      expect(fail['is_error'], isTrue);
      expect('${fail['content']}', startsWith('Exit code 3'));
      expect(list['content'], 'f.txt');
      expect(
        '${leave['content']}',
        contains('Shell cwd was reset to ${h.cwd}'),
      );
      expect('${slow['content']}', contains('timed out'));
    });

    test(
      'in the background: started, told when done, a turn of its own',
      () async {
        h = await Harness.start();
        String? told;
        h.model.script.addAll([
          Reply.tool('Bash', {
            'command': 'sleep 0.3; echo done-here',
            'description': 'Slow job',
            'run_in_background': true,
          }),
          Reply.text('started it'),
        ]);
        h.model.route = (request) {
          final text = sentIn(request);
          if (!text.contains('<task-notification>') || told != null) {
            return null;
          }
          told = text;
          return Reply.text('it finished');
        };
        await h.turn('run it in the background');
        final launched = h.toolResults.single['tool_use_result'] as Map;
        final id = launched['backgroundTaskId'];
        expect(h.of('system', 'task_started').single['task_id'], id);
        await h.nextIdle().timeout(const Duration(seconds: 10));
        final ended = h.of('system', 'task_notification').single;
        expect(ended['status'], 'completed');
        expect(
          File('${ended['output_file']}').readAsStringSync(),
          'done-here\n',
        );
        expect(
          told,
          contains('Background command \\"Slow job\\" completed (exit code 0)'),
        );
        expect(h.lastResult['result'], 'it finished');
      },
    );

    test(
      'a running command sent to the background (background_tasks)',
      () async {
        h = await Harness.start();
        h.model.script.addAll([
          Reply.tool('Bash', {
            'command': 'echo first; sleep 1; echo second',
            'description': 'Long',
          }),
          Reply.text('moved on'),
        ]);
        h.model.route = (request) =>
            sentIn(request).contains('<task-notification>')
            ? Reply.text('noted')
            : null;
        final started = h.messages.firstWhere(
          (m) =>
              m['type'] == 'assistant' &&
              jsonEncode(m).contains('"name":"Bash"'),
        );
        final idle = h.nextIdle();
        h.send('long job');
        final call = await started;
        final id =
            (((call['message'] as Map)['content'] as List).single as Map)['id'];
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final answer = await h.request('background_tasks', {'tool_use_id': id});
        expect(answer['backgrounded'], hasLength(1));
        await idle;
        expect(
          '${h.toolResults.single['content']}',
          contains('running in background'),
        );
        expect(h.lastResult['result'], 'moved on');
        await h.nextIdle().timeout(const Duration(seconds: 10));
        final ended = h.of('system', 'task_notification').single;
        expect(
          File('${ended['output_file']}').readAsStringSync(),
          'first\nsecond\n',
        );
      },
    );

    test('stop_task stops it; the model is not told', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tool('Bash', {
          'command': 'sleep 30',
          'description': 'Forever',
          'run_in_background': true,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      final id =
          (h.toolResults.single['tool_use_result'] as Map)['backgroundTaskId'];
      await h.request('stop_task', {'task_id': id});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.of('system', 'task_notification').single['status'], 'killed');
      expect(() => h.request('stop_task', {'task_id': id}), throwsStateError);
      expect(h.model.turns, hasLength(2));
    });

    test('stopped, though what it left running holds its output open '
        '(a dev server\'s watcher)', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tool('Bash', {
          'command': '(sleep 30 &); sleep 30',
          'description': 'Dev server',
          'run_in_background': true,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      final id =
          (h.toolResults.single['tool_use_result'] as Map)['backgroundTaskId'];
      await h.request('stop_task', {'task_id': id});
      expect(h.of('system', 'task_notification').single['status'], 'killed');
    }, skip: Platform.isWindows);

    test('one ends and the model is told; TaskStop stops another', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tool('Bash', {
          'command': 'echo hi',
          'description': 'Hi',
          'run_in_background': true,
        }, id: 'toolu_bg1'),
        Reply.tool('Bash', {
          'command': 'sleep 30',
          'description': 'Long',
          'run_in_background': true,
        }, id: 'toolu_bg2'),
      ]);
      h.model.route = (request) {
        final text = sentIn(request);
        if (text.contains('<task-notification>')) return Reply.text('noted');
        final ids = RegExp(r'background with ID: (\w+)')
            .allMatches(text)
            .map((m) => m[1])
            .toList();
        if (ids.length == 2 && !text.contains('"name":"TaskStop"')) {
          return Reply.tool('TaskStop', {'task_id': ids[1]});
        }
        return null;
      };
      h.model.script.add(Reply.text('done'));
      await h.turn('go');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final stop = h.toolResults[2];
      expect(stop['is_error'], isNot(isTrue));
      expect(
        h.of('system', 'task_notification').map((m) => m['status']),
        containsAll(['completed', 'killed']),
      );
    });
  });

  group('subagents', () {
    bool isSub(ModelRequest request) =>
        jsonEncode((request.body['messages'] as List).first).contains('SUB:');

    test('a general-purpose agent starts one of its own, in the foreground, '
        'its report back to it', () async {
      h = await Harness.start();
      final requests = <String, List<ModelRequest>>{};
      final replies = {
        'SUB1': [
          Reply.tool('Agent', {
            'description': 'Go deeper',
            'prompt': 'SUB2: go deeper',
            'run_in_background': true,
          }),
          Reply.text('deeper said: done deep'),
        ],
        'SUB2': [Reply.text('done deep')],
      };
      h.model.route = (request) {
        final first = jsonEncode((request.body['messages']! as List).first);
        for (final key in ['SUB2', 'SUB1']) {
          if (first.contains('$key:')) {
            (requests[key] ??= []).add(request);
            return replies[key]!.removeAt(0);
          }
        }
        return null;
      };
      h.model.script.addAll([
        Reply.tool('Agent', {
          'description': 'Look',
          'prompt': 'SUB1: look',
          'subagent_type': 'general-purpose',
          'run_in_background': false,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      final tools = [
        for (final t in requests['SUB1']!.first.body['tools']! as List)
          (t as Map)['name'],
      ];
      expect(tools, contains('Agent'));
      expect(
        jsonEncode(requests['SUB1']!.last.body['messages']),
        contains('done deep'),
      );
      expect(
        jsonEncode(h.model.turns.last.body['messages']),
        contains('deeper said: done deep'),
      );
    });

    test('in the foreground: its messages, file and result', () async {
      h = await Harness.start(files: {'a.txt': 'secret 42\n'});
      final sub = [
        Reply.tool('Read', {'file_path': p.join(h.cwd, 'a.txt')}),
        Reply.text('The number is 42.'),
      ];
      ModelRequest? first;
      h.model.route = (request) {
        if (!isSub(request)) return null;
        first ??= request;
        return sub.removeAt(0);
      };
      h.model.script.addAll([
        Reply.tool('Agent', {
          'description': 'Find the number',
          'prompt': 'SUB: find the number in a.txt',
          'subagent_type': 'Explore',
          'run_in_background': false,
        }, id: 'toolu_agent'),
        Reply.text('It is 42'),
      ]);
      await h.turn('find it');
      // Its own prompt and tools: no Agent, no memory for Explore.
      final tools = [
        for (final t in first!.body['tools'] as List) (t as Map)['name'],
      ];
      expect(tools, containsAll(['Read', 'Bash']));
      expect(tools, isNot(contains('Agent')));
      expect(tools, isNot(contains('Write')));
      // Shown under its call.
      final under = h.sent
          .where((m) => m['parent_tool_use_id'] == 'toolu_agent')
          .toList();
      expect(under.where((m) => m['type'] == 'assistant'), hasLength(2));
      expect(under.where((m) => m['type'] == 'user'), isNotEmpty);
      expect(
        h
            .of('system', 'status')
            .where((m) => m['parent_tool_use_id'] == 'toolu_agent'),
        isEmpty,
      );
      final result = h.toolResults.firstWhere(
        (r) => r['tool_use_id'] == 'toolu_agent',
      );
      final fields = result['tool_use_result'] as Map;
      expect(fields['status'], 'completed');
      expect(fields['totalToolUseCount'], 1);
      expect(fields['prompt'], 'SUB: find the number in a.txt');
      expect(jsonEncode(fields['content']), contains('The number is 42.'));
      // The report framed as the model's, not the user's.
      expect('${result['content']}', contains('[Agent report]'));
      expect('${result['content']}', contains('  The number is 42.'));
      // Its transcript, by the session's.
      final dir = p.join(p.withoutExtension(h.sessionFile), 'subagents');
      final file = File(p.join(dir, 'agent-${fields['agentId']}.jsonl'));
      expect(
        file
            .readAsLinesSync()
            .map(jsonDecode)
            .every((l) => (l as Map)['isSidechain'] == true),
        isTrue,
      );
      expect(
        jsonDecode(
          File(p.join(dir, 'agent-${fields['agentId']}.meta.json'))
              .readAsStringSync(),
        ),
        containsPair('agentType', 'Explore'),
      );
      expect(h.of('system', 'task_started').single['is_backgrounded'], isFalse);
      // The main agent is not told twice.
      expect(
        h.model.turns.where((r) => sentIn(r).contains('<task-notification>')),
        isEmpty,
      );
    });

    test('in the background: launched, then a turn with its result', () async {
      h = await Harness.start();
      final release = Completer<void>();
      h.model.route = (request) {
        if (isSub(request)) return Reply.text('Background answer.');
        if (sentIn(request).contains('<task-notification>')) {
          return Reply.text('got it');
        }
        return null;
      };
      h.model.script.addAll([
        Reply.tool('Agent', {
          'description': 'Look around',
          'prompt': 'SUB: look',
          'run_in_background': true,
        }),
        Reply.text('launched'),
      ]);
      release.complete();
      await h.turn('go');
      final launched = h.toolResults.single['tool_use_result'] as Map;
      expect(launched['status'], 'async_launched');
      if (h.of('system', 'task_notification').isEmpty ||
          h.lastResult['result'] != 'got it') {
        await h.nextIdle().timeout(const Duration(seconds: 10));
      }
      final notified = h.model.turns.firstWhere(
        (r) => sentIn(r).contains('<task-notification>'),
      );
      expect(sentIn(notified), contains('Background answer.'));
      expect(h.of('system', 'task_notification').single['status'], 'completed');
    });

    test('sent a message once done: it goes on from where it was', () async {
      h = await Harness.start();
      final seen = <String>[];
      h.model.route = (request) {
        if (sentIn(request).contains('<task-notification>')) {
          return Reply.text('noted');
        }
        if (!isSub(request)) return null;
        seen.add(sentIn(request));
        return Reply.text('answer ${seen.length}');
      };
      h.model.script.addAll([
        Reply.tool('Agent', {
          'description': 'First',
          'prompt': 'SUB: first question',
          'run_in_background': false,
        }),
        Reply.text('ok'),
      ]);
      await h.turn('ask');
      final agentId =
          (h.toolResults.single['tool_use_result'] as Map)['agentId'];
      h.model.script.addAll([
        Reply.tool('SendMessage', {
          'to': agentId,
          'summary': 'a second question',
          'message': 'second question',
        }),
        Reply.text('ok'),
      ]);
      await h.turn('ask again');
      for (var i = 0; i < 100 && seen.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(
        seen.last,
        allOf(
          contains('first question'),
          contains('answer 1'),
          contains('second question'),
        ),
      );
      expect(
        (h.toolResults.last['tool_use_result'] as Map)['agentId'],
        agentId,
      );
    });

    test(
      'custom agents from the project, with their tools and model',
      () async {
        h = await Harness.start(
          files: {
            '.claude/agents/reviewer.md': '---\nname: reviewer\ndescription: Reviews code\ntools: Read, Bash\nmodel: haiku\n---\nYou review code. SUB:\n',
          },
        );
        ModelRequest? sub;
        h.model.route = (request) {
          if (!jsonEncode(request.body['system']).contains('You review code')) {
            return null;
          }
          sub = request;
          return Reply.text('Looks fine.');
        };
        h.model.script.addAll([
          Reply.tool('Agent', {
            'description': 'Review',
            'prompt': 'Review it',
            'subagent_type': 'reviewer',
            'run_in_background': false,
          }),
          Reply.text('ok'),
        ]);
        await h.turn('review');
        expect([
          for (final t in sub!.body['tools'] as List) (t as Map)['name'],
        ], unorderedEquals(['Read', 'Bash']));
        expect(sub!.model, contains('haiku'));
        final agents = h.of('system', 'init').last['agents'] as List;
        expect(agents, contains('reviewer'));
      },
    );

    test('a custom agent\'s own mode: its edits not asked, unless the '
        'session plans', () async {
      h = await Harness.start(
        files: {
          '.claude/agents/writer.md': '---\nname: writer\ndescription: Writes files\ntools: Write\npermissionMode: acceptEdits\n---\nYou write files.\n',
        },
      );
      var step = 0;
      h.model.route = (request) {
        if (!jsonEncode(request.body['system']).contains('You write files')) {
          return null;
        }
        step++;
        return step.isOdd
            ? Reply.tool('Write', {
                'file_path': p.join(h.cwd, 'w$step.txt'),
                'content': 'x',
              })
            : Reply.text('written');
      };
      Reply delegate() => Reply.tool('Agent', {
        'description': 'Write',
        'prompt': 'Write it',
        'subagent_type': 'writer',
        'run_in_background': false,
      });
      h.model.script.addAll([delegate(), Reply.text('ok')]);
      await h.turn('write');
      expect(File(p.join(h.cwd, 'w1.txt')).existsSync(), isTrue);
      expect(h.permissionRequests, isEmpty);
      // Planning: its edit asked, whatever the agent's own mode.
      await h.request('set_permission_mode', {'mode': 'plan'});
      h.model.script.addAll([delegate(), Reply.text('ok')]);
      await h.turn('write again');
      expect(h.permissionRequests.single['tool_name'], 'Write');
    });
  });

  test('Skill: its prompt follows, its tools allowed', () async {
    h = await Harness.start(
      files: {
        '.claude/skills/greet/SKILL.md': '---\nname: greet\ndescription: Greets someone\nallowed-tools: Bash(touch:*)\n---\nSay hello to \$ARGUMENTS.\n',
      },
    );
    h.model.script.addAll([
      Reply.tool('Skill', {'skill': 'greet', 'args': 'Ada'}),
      Reply.tool('Bash', {'command': 'touch greeted', 'description': 'Touch'}),
      Reply.text('Hello, Ada'),
    ]);
    await h.turn('greet Ada');
    // The skills are listed in the context, not in the tool.
    expect(sentIn(h.model.turns.first), contains('- greet: Greets someone'));
    final result = h.toolResults.first;
    expect((result['tool_use_result'] as Map)['commandName'], 'greet');
    final next = sentIn(h.model.turns[1]);
    expect(
      next,
      allOf(
        contains('Base directory for this skill'),
        contains('Say hello to Ada.'),
      ),
    );
    expect(h.permissionRequests, isEmpty);
    expect(h.of('system', 'init').last['skills'], contains('greet'));
  });
}
