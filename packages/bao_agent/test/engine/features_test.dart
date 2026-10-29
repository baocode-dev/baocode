import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:bao_agent/src/engine/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

void main() {
  Harness? started;
  late Harness h;

  setUp(() => started = null);
  tearDown(() => started?.dispose());

  Future<Harness> start({
    Map<String, String> files = const {},
    Map<String, Object?> settings = const {},
    Map<String, String> environment = const {},
  }) async => started = await Harness.start(
    files: files,
    settings: settings,
    environment: environment,
  );

  String sentIn(ModelRequest request) => jsonEncode(request.body['messages']);

  group('scheduling', () {
    test('cron expressions: fields, ranges, steps, either day', () {
      final every5 = CronExpression.parse('*/5 * * * *');
      expect(
        every5.next(DateTime(2026, 3, 1, 10, 7)),
        DateTime(2026, 3, 1, 10, 10),
      );
      final weekdays = CronExpression.parse('30 9 * * 1-5');
      // A Saturday: Monday next.
      expect(
        weekdays.next(DateTime(2026, 2, 28, 12)),
        DateTime(2026, 3, 2, 9, 30),
      );
      // Day of month or day of week, as cron has it.
      final either = CronExpression.parse('0 0 15 * 0');
      expect(either.matches(DateTime(2026, 3, 15)), isTrue);
      expect(either.matches(DateTime(2026, 3, 8)), isTrue);
      expect(either.matches(DateTime(2026, 3, 9)), isFalse);
      expect(() => CronExpression.parse('* * *'), throwsFormatException);
      expect(() => CronExpression.parse('61 * * * *'), throwsFormatException);
      expect(CronExpression.parse('0 0 30 2 *').next(DateTime(2026)), isNull);
    });

    test('CronCreate, CronList, CronDelete; a durable job kept on disk; '
        'a job due sends its prompt', () async {
      h = await start();
      h.model.script.addAll([
        Reply.tools([
          ('CronCreate', {'cron': '*/5 * * * *', 'prompt': 'check the build'}),
          (
            'CronCreate',
            {
              'cron': '0 9 * * *',
              'prompt': 'morning report',
              'durable': true,
              'recurring': false,
            },
          ),
          ('CronCreate', {'cron': 'not cron', 'prompt': 'x'}),
        ]),
        Reply.text('scheduled'),
      ]);
      await h.turn('schedule');
      final [every, morning, bad] = h.toolResults;
      expect(bad['is_error'], isTrue);
      final everyId = (every['tool_use_result'] as Map)['id'];
      final morningId = (morning['tool_use_result'] as Map)['id'];
      final kept = jsonDecode(
        File(p.join(h.cwd, '.claude', 'scheduled_tasks.json'))
            .readAsStringSync(),
      ) as Map;
      expect(
        [for (final t in kept['tasks'] as List) (t as Map)['id']],
        [morningId],
      );

      h.model.script.addAll([
        Reply.tools([
          ('CronList', {}),
          ('CronDelete', {'id': morningId}),
          ('CronDelete', {'id': 'nope'}),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('list');
      final [list, deleted, missing] = h.toolResults.sublist(3);
      expect('${list['content']}', allOf(contains(everyId), contains('*/5')));
      expect(deleted['is_error'], isNot(isTrue));
      expect(missing['is_error'], isTrue);
      expect(h.engine.session.scheduler.jobs.keys, [everyId]);

      // Come due: its prompt is sent as the user's.
      final scheduler = h.engine.session.scheduler;
      h.model.script.add(Reply.text('build is green'));
      final idle = h.nextIdle();
      scheduler.tick(DateTime.now().add(const Duration(minutes: 6)));
      await idle;
      expect(sentIn(h.model.turns.last), contains('check the build'));
      expect(h.lastResult['result'], 'build is green');
    });

    test(
      'ScheduleWakeup: clamped, fires its prompt, stopped by stop',
      () async {
        h = await start();
        h.model.script.addAll([
          Reply.tool('ScheduleWakeup', {
            'delaySeconds': 5,
            'reason': 'watching the deploy',
            'prompt': 'is the deploy done?',
            'noop': false,
          }),
          Reply.text('waiting'),
        ]);
        await h.turn('watch the deploy');
        final result = h.toolResults.single['tool_use_result'] as Map;
        expect(result['delaySeconds'], 60);
        final scheduler = h.engine.session.scheduler;
        expect(scheduler.wakeup?.prompt, 'is the deploy done?');

        h.model.script.addAll([
          Reply.tool('ScheduleWakeup', {'stop': true}),
          Reply.text('done'),
        ]);
        final idle = h.nextIdle();
        scheduler.tick(DateTime.now().add(const Duration(seconds: 61)));
        await idle;
        expect(sentIn(h.model.turns[2]), contains('is the deploy done?'));
        expect(scheduler.wakeup, isNull);
      },
    );
  });

  group('worktrees', () {
    test('EnterWorktree moves the session in; ExitWorktree keeps or '
        'removes it, not losing work unasked', () async {
      h = await start(
        files: {'a.txt': 'one\n'},
        settings: {
          'worktree': {'baseRef': 'head'},
        },
      );
      for (final args in [
        ['init', '-q', '-b', 'main'],
        ['-c', 'user.email=t@t', '-c', 'user.name=t', 'add', '.'],
        ['-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-qm', 'one'],
      ]) {
        expect(
          Process.runSync('git', args, workingDirectory: h.cwd).exitCode,
          0,
        );
      }
      final tree = p.join(h.cwd, '.claude', 'worktrees', 'feat');
      h.model.script.addAll([
        Reply.tool('EnterWorktree', {'name': 'feat'}),
        Reply.tool('Bash', {'command': 'pwd', 'description': 'Where'}),
        Reply.tool('Write', {
          'file_path': p.join(tree, 'b.txt'),
          'content': 'two\n',
        }),
        Reply.tool('ExitWorktree', {'action': 'remove'}),
        Reply.tool('ExitWorktree', {'action': 'keep'}),
        Reply.tool('Bash', {'command': 'pwd', 'description': 'Where'}),
        Reply.text('ok'),
      ]);
      h.onPermission = (request) async => {
        'behavior': 'allow',
        'updatedInput': request['input'],
      };
      await h.turn('work in a worktree');
      final [enter, inside, _, refused, kept, back] = h.toolResults;
      expect((enter['tool_use_result'] as Map)['worktree_branch'], isNotNull);
      expect('${inside['content']}', contains(tree));
      expect(refused['is_error'], isTrue);
      expect('${refused['content']}', contains('b.txt'));
      expect('${kept['content']}', contains('Left the worktree'));
      expect('${back['content']}'.trim(), h.cwd);
      expect(Directory(tree).existsSync(), isTrue);
    });
  });

  group('hooks', () {
    test('an http hook is posted the event; PostToolBatch adds context; '
        'UserPromptExpansion blocks a command', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final posted = <Map<String, Object?>>[];
      final headers = <String?>[];
      server.listen((request) async {
        posted.add(
          (jsonDecode(await utf8.decodeStream(request)) as Map)
              .cast<String, Object?>(),
        );
        headers.add(request.headers.value('x-token'));
        request.response
          ..headers.contentType = ContentType.json
          ..write('{}');
        await request.response.close();
      });
      final bin = Directory.systemTemp
          .createTempSync('hooks_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(bin).deleteSync(recursive: true));
      final batch = File(p.join(bin, 'batch.sh'))
        ..writeAsStringSync(
          '#!/bin/sh\necho \'{"hookSpecificOutput": {"hookEventName": '
          '"PostToolBatch", "additionalContext": "BATCH NOTE"}}\'\n',
        );
      final expand = File(p.join(bin, 'expand.sh'))
        ..writeAsStringSync('#!/bin/sh\necho "not today" >&2\nexit 2\n');
      Process.runSync('chmod', ['+x', batch.path, expand.path]);
      h = await start(
        files: {'a.txt': 'hi\n', '.claude/commands/fix.md': 'Fix it.\n'},
        environment: {'HOOK_TOKEN': 'secret'},
        settings: {
          'hooks': {
            'PostToolUse': [
              {
                'matcher': 'Read',
                'hooks': [
                  {
                    'type': 'http',
                    'url': 'http://127.0.0.1:${server.port}/hook',
                    'headers': {'x-token': r'$HOOK_TOKEN'},
                    'allowedEnvVars': ['HOOK_TOKEN'],
                  },
                ],
              },
            ],
            'PostToolBatch': [
              {
                'hooks': [
                  {'type': 'command', 'command': batch.path},
                ],
              },
            ],
            'UserPromptExpansion': [
              {
                'matcher': 'fix',
                'hooks': [
                  {'type': 'command', 'command': expand.path},
                ],
              },
            ],
          },
        },
      );
      h.model.script.addAll([
        Reply.tool('Read', {'file_path': p.join(h.cwd, 'a.txt')}),
        Reply.text('read it'),
      ]);
      await h.turn('read a.txt');
      expect(posted.single['hook_event_name'], 'PostToolUse');
      expect(posted.single.keys, [
        'session_id',
        'transcript_path',
        'cwd',
        'prompt_id',
        'permission_mode',
        'effort',
        'hook_event_name',
        'tool_name',
        'tool_input',
        'tool_response',
        'tool_use_id',
        'duration_ms',
      ]);
      expect(posted.single['tool_name'], 'Read');
      expect(headers.single, 'secret');
      expect(sentIn(h.model.turns.last), contains('BATCH NOTE'));

      final asked = h.model.requests.length;
      await h.turn('/fix');
      expect(h.model.requests, hasLength(asked));
      expect(jsonEncode(h.of('assistant').last), contains('not today'));
    });

    test('what each event tells its hooks', () async {
      Map<String, Object?> hook(String event) => {
        'hooks': [
          {
            'type': 'command',
            'command':
                'cat >> "\$CLAUDE_PROJECT_DIR/$event.jsonl"; '
                'echo >> "\$CLAUDE_PROJECT_DIR/$event.jsonl"',
          },
        ],
      };
      const events = [
        'SessionStart',
        'InstructionsLoaded',
        'PreToolUse',
        'PostToolUseFailure',
        'PermissionRequest',
        'Stop',
        'SubagentStart',
        'SubagentStop',
        'UserPromptExpansion',
        'UserPromptSubmit',
      ];
      h = await start(
        files: {'CLAUDE.md': 'Be brief.\n', '.claude/commands/hi.md': 'Hi.\n'},
        settings: {
          'hooks': {
            for (final e in events) e: [hook(e)],
          },
        },
      );
      h.model.route = (request) =>
          jsonEncode(request.body['messages']).contains('SUB: look')
          ? Reply.text('looked')
          : null;
      h.onPermission = (request) async => {
        'behavior': 'allow',
        'updatedInput': request['input'],
      };
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'exit 3', 'description': 'Fail'}),
        Reply.tool('Write', {
          'file_path': p.join(h.cwd, 'b.txt'),
          'content': 'b',
        }),
        Reply.tool('Agent', {
          'description': 'Look',
          'prompt': 'SUB: look',
          'subagent_type': 'general-purpose',
          'run_in_background': false,
        }),
        Reply.text('done'),
        Reply.text('hi'),
      ]);
      await h.turn('go');
      await h.turn('/hi');
      Map<String, Object?> told(String event, [int at = 0]) {
        final lines = File(p.join(h.cwd, '$event.jsonl'))
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .toList();
        return (jsonDecode(lines[at]) as Map).cast<String, Object?>();
      }

      const common = ['session_id', 'transcript_path', 'cwd'];
      expect(told('SessionStart').keys, [
        ...common,
        'hook_event_name',
        'source',
      ]);
      expect(told('InstructionsLoaded')['memory_type'], 'Project');
      expect(told('PreToolUse').keys, [
        ...common,
        'prompt_id',
        'permission_mode',
        'effort',
        'hook_event_name',
        'tool_name',
        'tool_input',
        'tool_use_id',
      ]);
      expect(told('PostToolUseFailure')['is_interrupt'], isFalse);
      expect(told('PermissionRequest').keys, isNot(contains('tool_use_id')));
      expect(told('SubagentStart').keys, [
        ...common,
        'prompt_id',
        'agent_id',
        'agent_type',
        'hook_event_name',
      ]);
      expect(told('SubagentStop').keys, [
        ...common,
        'prompt_id',
        'permission_mode',
        'agent_id',
        'agent_type',
        'effort',
        'hook_event_name',
        'stop_hook_active',
        'agent_transcript_path',
        'last_assistant_message',
        'background_tasks',
        'session_crons',
      ]);
      final stop = told('Stop');
      expect(stop['background_tasks'], isEmpty);
      expect(stop['session_crons'], isEmpty);
      final expansion = told('UserPromptExpansion');
      expect(expansion['expansion_type'], 'slash_command');
      expect(expansion['command_source'], 'projectSettings');
      expect(expansion['prompt'], '/hi');
      // A prompt of its own, submitted once expanded.
      expect(expansion['prompt_id'], isNot(stop['prompt_id']));
      final submitted = told('UserPromptSubmit', 1);
      expect(submitted['prompt'], '/hi');
      expect(submitted['prompt_id'], expansion['prompt_id']);
      expect(
        jsonEncode(h.model.turns.last.body['messages']),
        contains(
          jsonEncode(
            '<command-message>hi</command-message>\n'
            '<command-name>/hi</command-name>\n',
          ),
        ),
      );
    });

    test('an agent hook looks, then denies a call', () async {
      h = await start(
        settings: {
          'hooks': {
            'PreToolUse': [
              {
                'matcher': 'Bash',
                'hooks': [
                  {
                    'type': 'agent',
                    'prompt': 'Check the command is safe: \$ARGUMENTS',
                  },
                ],
              },
            ],
          },
        },
      );
      ModelRequest? checked;
      h.model.route = (request) {
        if (!jsonEncode(request.body['system']).contains('for a hook')) {
          return null;
        }
        checked = request;
        return Reply.text('{"ok": false, "reason": "it deletes things"}');
      };
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'rm -rf build', 'description': 'Clean'}),
        Reply.text('blocked'),
      ]);
      await h.turn('clean');
      expect(sentIn(checked!), contains('rm -rf build'));
      final tools = [
        for (final t in checked!.body['tools']! as List) (t as Map)['name'],
      ];
      expect(tools, unorderedEquals(['Read', 'Bash']));
      final result = h.toolResults.single;
      expect(result['is_error'], isTrue);
      expect('${result['content']}', contains('it deletes things'));
      // Its messages are its own: none reach the host.
      expect(
        h.of('assistant').where((m) => m['parent_tool_use_id'] != null),
        isEmpty,
      );
    });
  });

  test('Bash says to search with rg only where it is installed', () async {
    final bin = Directory.systemTemp
        .createTempSync('bin_')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(bin).deleteSync(recursive: true));
    final rg = File(p.join(bin, 'rg'))..writeAsStringSync('#!/bin/sh\n');
    Process.runSync('chmod', ['+x', rg.path]);
    Future<String> bash(String path) async {
      final h = await Harness.start(environment: {'PATH': path});
      addTearDown(h.dispose);
      h.model.script.add(Reply.text('ok'));
      await h.turn('hi');
      final tools = h.model.turns.single.body['tools']! as List;
      return '${(tools.firstWhere((t) => (t as Map)['name'] == 'Bash') as Map)['description']}';
    }

    expect(await bash('$bin:/usr/bin:/bin'), contains("`rg --files -g"));
    expect(
      await bash('/usr/bin:/bin'),
      allOf(contains('no `rg`'), isNot(contains('rg --files'))),
    );
  });

  test(
    'auto memory: where it is, its index read in, how to write it',
    () async {
      h = await start();
      final dir = h.engine.session.autoMemoryDir!;
      File(p.join(dir, 'MEMORY.md'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('- [Tabs](tabs.md) — the user wants tabs\n');
      h.engine.session.context.reloadExtensions();
      h.model.script.add(Reply.text('ok'));
      await h.turn('hi');
      final request = h.model.turns.single;
      final system = jsonEncode(request.body['system']);
      expect(system, allOf(contains('# Memory'), contains(dir)));
      expect(
        jsonEncode((request.body['messages']! as List).first),
        contains('the user wants tabs'),
      );
      final init = h.of('system', 'init').single;
      expect((init['memory_paths'] as Map)['auto'], startsWith(dir));
    },
  );
}
