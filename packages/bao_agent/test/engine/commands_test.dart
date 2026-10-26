import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  String sentIn(ModelRequest request) => jsonEncode(request.body['messages']);

  /// The assistant's text the engine said itself (a command's output).
  List<String> said() => [
    for (final m in h.of('assistant'))
      for (final block in (m['message'] as Map)['content'] as List)
        if ((block as Map)['type'] == 'text') '${block['text']}',
  ];

  /// The session file's lines.
  List<Map<String, Object?>> kept() => [
    for (final line in File(h.sessionFile).readAsLinesSync())
      (jsonDecode(line) as Map).cast<String, Object?>(),
  ];

  group('slash commands', () {
    test(
      'the commands are listed, the built-in ones and the project\'s',
      () async {
        h = await Harness.start(
          files: {
            '.claude/commands/fix.md': '---\ndescription: Fix an issue\nargument-hint: <number>\n---\nFix issue \$ARGUMENTS carefully.\n',
          },
        );
        h.model.script.add(Reply.text('hi'));
        await h.turn('hello');
        final names = h.of('system', 'init').single['slash_commands'] as List;
        expect(
          names,
          containsAll([
            'compact',
            'context',
            'cost',
            'init',
            'review',
            'goal',
            'fix',
          ]),
        );
        final init = await h.request('initialize');
        final commands = init['commands'] as List;
        final fix = commands.cast<Map>().firstWhere((c) => c['name'] == 'fix');
        expect(fix['description'], 'Fix an issue (project)');
        expect(fix['argumentHint'], '<number>');
      },
    );

    test('a custom command with arguments becomes the prompt', () async {
      h = await Harness.start(
        files: {
          '.claude/commands/fix.md': 'Fix issue \$ARGUMENTS carefully.\n',
        },
      );
      h.model.script.add(Reply.text('fixed'));
      await h.turn('/fix 42');
      expect(sentIn(h.model.turns.single), contains('Fix issue 42 carefully.'));
      final lines = kept();
      expect(
        lines.any(
          (l) => jsonEncode(l).contains('<command-name>/fix</command-name>'),
        ),
        isTrue,
      );
      expect(
        lines.any(
          (l) => l['isMeta'] == true && jsonEncode(l).contains('Fix issue 42'),
        ),
        isTrue,
      );
      expect(h.lastResult['result'], 'fixed');
    });

    test('an unknown command is said to be unknown', () async {
      h = await Harness.start();
      await h.turn('/nope');
      expect(said(), contains('Unknown skill: nope'));
      expect(h.model.requests, isEmpty);
    });

    test('/init, /review and /security-review ask the model', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.text('a'),
        Reply.text('b'),
        Reply.text('c'),
      ]);
      await h.turn('/init');
      await h.turn('/review 12');
      await h.turn('/security-review');
      final [init, review, security] = h.model.turns.map(sentIn).toList();
      expect(init, contains('CLAUDE.md'));
      expect(review, contains('12'));
      expect(security, contains('security'));
    });

    test('/cost, /context and /todos answer at once', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply.tool('TodoWrite', {
          'todos': [
            {
              'content': 'Write it',
              'status': 'in_progress',
              'activeForm': 'Writing it',
            },
          ],
        }),
        Reply.text('ok'),
        Reply.text(''),
      ]);
      await h.turn('work');
      final asked = h.model.requests.length;
      await h.turn('/cost');
      expect(
        said().last,
        allOf(contains('Total cost:'), contains('Usage by model:')),
      );
      await h.turn('/context');
      expect(
        said().last,
        allOf(contains('## Context Usage'), contains('System prompt')),
      );
      await h.turn('/todos');
      expect(said().last, '1 todo:\n◐ Write it');
      expect(h.model.requests, hasLength(asked));
    });

    test(
      '/compact: summed up, and the conversation goes on from there',
      () async {
        h = await Harness.start();
        h.model.script.addAll([
          Reply.text('first answer'),
          Reply.text('<summary>We talked about apples.</summary>'),
          Reply.text('after'),
        ]);
        await h.turn('tell me about apples');
        await h.turn('/compact keep the fruit');
        final summarizing = h.model.requests.firstWhere(
          (r) =>
              jsonEncode(r.body['system'])
                  .contains('summary of a conversation'),
        );
        expect(sentIn(summarizing), contains('keep the fruit'));
        final boundary = h.of('system', 'compact_boundary').single;
        expect((boundary['compact_metadata'] as Map)['trigger'], 'manual');
        expect(h.lastResult['result'], 'Compacted.');
        await h.turn('and now?');
        final next = h.model.turns.last.body['messages'] as List;
        expect(jsonEncode(next.first), contains('We talked about apples.'));
        expect(jsonEncode(next), isNot(contains('first answer')));
        final lines = kept();
        expect(
          lines.where((l) => l['subtype'] == 'compact_boundary'),
          hasLength(1),
        );
        expect(lines.where((l) => l['isCompactSummary'] == true), hasLength(1));
      },
    );

    test('a long conversation is compacted on its own', () async {
      h = await Harness.start();
      h.model.script.addAll([
        Reply(
          [
            {'type': 'text', 'text': 'big'},
          ],
          usage: {'input_tokens': 199000, 'output_tokens': 1},
        ),
        Reply.text('<summary>Big talk.</summary>'),
        Reply.text('small again'),
      ]);
      await h.turn('one');
      await h.turn('two');
      expect(
        h.of('system', 'compact_boundary').single['compact_metadata'],
        containsPair('trigger', 'auto'),
      );
      expect(
        jsonEncode(h.model.turns.last.body['messages']),
        contains('Big talk.'),
      );
    });
  });

  group('plugins', () {
    test("a plugin's commands, skills, agents and hooks", () async {
      final plugin = Directory.systemTemp
          .createTempSync('plugin_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(plugin).deleteSync(recursive: true));
      void write(String path, String text) {
        final file = File(p.join(plugin, path));
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(text);
      }

      write(
        '.claude-plugin/plugin.json',
        jsonEncode({'name': 'kit', 'version': '1.0.0'}),
      );
      write(
        'commands/hello.md',
        '---\ndescription: Says hello\n---\nSay hello to \$ARGUMENTS from \${CLAUDE_PLUGIN_ROOT}.',
      );
      write(
        'skills/lint/SKILL.md',
        '---\nname: lint\ndescription: Lints code\n---\nRun the linter.',
      );
      write(
        'agents/helper.md',
        '---\nname: helper\ndescription: Helps\n---\nYou help.',
      );
      write(
        'hooks/hooks.json',
        jsonEncode({
          'hooks': {
            'SessionStart': [
              {
                'hooks': [
                  {
                    'type': 'command',
                    'command': 'echo "kit at \${CLAUDE_PLUGIN_ROOT}"',
                  },
                ],
              },
            ],
          },
        }),
      );
      h = await Harness.start(
        settings: {
          'enabledPlugins': {'kit@market': true, 'off@market': false},
        },
      );
      File(p.join(h.config, 'plugins', 'installed_plugins.json'))
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          jsonEncode({
            'version': 2,
            'plugins': {
              'kit@market': [
                {'scope': 'user', 'installPath': plugin, 'version': '1.0.0'},
              ],
              'off@market': [
                {'scope': 'user', 'installPath': plugin},
              ],
            },
          }),
        );
      await h.request('reload_plugins');
      h.model.script.add(Reply.text('hi'));
      await h.turn('/kit:hello Ada');
      final init = h.of('system', 'init').last;
      expect(init['slash_commands'], containsAll(['kit:hello', 'kit:lint']));
      expect(init['agents'], contains('kit:helper'));
      expect(init['skills'], contains('kit:lint'));
      expect(init['plugins'], [
        {'name': 'kit', 'path': plugin},
      ]);
      expect(
        sentIn(h.model.turns.single),
        contains('Say hello to Ada from $plugin.'),
      );
      final listing = await h.request('get_hooks_listing');
      expect(
        listing['hooks'],
        contains(
          allOf(
            containsPair('event', 'SessionStart'),
            containsPair('pluginName', 'kit'),
          ),
        ),
      );
    });
  });

  group('goal', () {
    test('set, checked when the agent stops, worked on until met', () async {
      var checks = 0;
      h = await Harness.start(
        errands: (request) {
          if (!jsonEncode(request.body['system']).contains('met the goal')) {
            return null;
          }
          checks++;
          return checks == 1
              ? Reply.text('{"ok": false, "reason": "tests still fail"}')
              : Reply.text('{"ok": true, "reason": "tests pass"}');
        },
      );
      h.model.script.addAll([
        Reply.text('working'),
        Reply.text('fixed the tests'),
      ]);
      await h.turn('/goal all tests pass');
      expect(said(), contains('Goal set: all tests pass'));
      expect(checks, 2);
      final [first, second] = h.model.turns.map(sentIn).toList();
      expect(first, contains('all tests pass'));
      expect(
        second,
        contains('Stop hook feedback:\\n[all tests pass]: tests still fail'),
      );
      final records = [
        for (final l in kept())
          if (l['type'] == 'attachment') l['attachment'] as Map,
      ];
      expect(records.first, containsPair('sentinel', true));
      expect(
        records[1],
        allOf(
          containsPair('met', false),
          containsPair('reason', 'tests still fail'),
        ),
      );
      expect(
        records.last,
        allOf(
          containsPair('met', true),
          contains('iterations'),
          contains('durationMs'),
        ),
      );
      await h.turn('/goal');
      expect(said().last, 'No goal set');
    });

    test('status, listing and clearing; kept across a resume', () async {
      h = await Harness.start(
        errands: (request) =>
            jsonEncode(request.body['system']).contains('met the goal')
            ? Reply.text('{"ok": false, "reason": "not yet"}')
            : null,
      );
      h.model.script.addAll([Reply.text('on it')]);
      // Not met: the agent is sent back once per check; the checks are
      // answered "not yet" until the turn's model replies run out, so the
      // goal is set and then the turn interrupted.
      h.model.script.add(Reply.text('still on it'));
      h.model.script.add(Reply.text('and more'));
      final idle = h.nextIdle();
      h.send('/goal ship it');
      await h.messages.firstWhere(
        (m) => m['type'] == 'assistant' && jsonEncode(m).contains('and more'),
      );
      await h.request('interrupt');
      await idle;
      final listing = await h.request('get_hooks_listing');
      expect(
        listing['hooks'],
        contains(
          allOf(
            containsPair('event', 'Stop'),
            containsPair('source', 'sessionHook'),
            containsPair('type', 'prompt'),
            containsPair('commandText', 'ship it'),
          ),
        ),
      );
      await h.turn('/goal');
      expect(said().last, 'Goal active: ship it');
      final sessionId = h.of('system', 'init').last['session_id'] as String;
      await h.engine.close();
      final again = await Harness.start(from: h, resume: sessionId);
      try {
        await again.turn('/goal');
        expect(
          [for (final m in again.of('assistant')) jsonEncode(m)].last,
          contains('Goal active: ship it'),
        );
        await again.turn('/goal clear');
        expect(
          jsonEncode(again.of('assistant').last),
          contains('Goal cleared: ship it'),
        );
        expect((await again.request('get_hooks_listing'))['hooks'], isEmpty);
      } finally {
        await again.engine.close();
      }
    });
  });

  group('hooks', () {
    late String bin;

    setUp(() {
      bin = Directory.systemTemp
          .createTempSync('hooks_')
          .resolveSymbolicLinksSync();
    });

    tearDown(() => Directory(bin).deleteSync(recursive: true));

    String script(String name, String body) {
      final file = File(p.join(bin, name))
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', file.path]);
      return file.path;
    }

    Map<String, Object?> on(String event, String command, {String? matcher}) =>
        {
          event: [
            {
              'matcher': ?matcher,
              'hooks': [
                {'type': 'command', 'command': command},
              ],
            },
          ],
        };

    test('PreToolUse: exit 2 blocks the call, with what it said', () async {
      final input = p.join(bin, 'input.json');
      h = await Harness.start(
        settings: {
          'hooks': on(
            'PreToolUse',
            script('pre.sh', 'cat > $input\necho "no rm here" >&2\nexit 2'),
            matcher: 'Bash',
          ),
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'rm -rf x', 'description': 'Remove'}),
        Reply.text('ok'),
      ]);
      await h.turn('remove');
      final result = h.toolResults.single;
      expect(result['is_error'], isTrue);
      expect('${result['content']}', contains('no rm here'));
      final given = jsonDecode(File(input).readAsStringSync()) as Map;
      expect(given['hook_event_name'], 'PreToolUse');
      expect(given['tool_name'], 'Bash');
      expect((given['tool_input'] as Map)['command'], 'rm -rf x');
      expect(given['cwd'], h.cwd);
    });

    test('PreToolUse: the input changed, and allowed', () async {
      h = await Harness.start(
        settings: {
          'hooks': on(
            'PreToolUse',
            script(
              'pre.sh',
              'echo \'{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": {"command": "echo changed", "description": "x"}}}\'',
            ),
          ),
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'curl evil', 'description': 'Fetch'}),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      expect(h.permissionRequests, isEmpty);
      expect(h.toolResults.single['content'], 'changed');
    });

    test('PostToolUse: its context goes to the model', () async {
      h = await Harness.start(
        settings: {
          'hooks': on(
            'PostToolUse',
            script(
              'post.sh',
              'echo \'{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": "lint is clean"}}\'',
            ),
            matcher: 'Write|Edit',
          ),
        },
      );
      h.model.script.addAll([
        Reply.tool('Write', {
          'file_path': p.join(h.cwd, 'a.txt'),
          'content': 'x',
        }),
        Reply.text('ok'),
      ]);
      await h.turn('write');
      expect(sentIn(h.model.turns.last), contains('lint is clean'));
    });

    test('UserPromptSubmit: context added, or the prompt blocked', () async {
      final flag = p.join(bin, 'block');
      h = await Harness.start(
        settings: {
          'hooks': on(
            'UserPromptSubmit',
            script(
              'prompt.sh',
              'if [ -f $flag ]; then echo "not that" >&2; exit 2; fi\necho "The time is noon."',
            ),
          ),
        },
      );
      h.model.script.add(Reply.text('ok'));
      await h.turn('hello');
      expect(sentIn(h.model.turns.single), contains('The time is noon.'));
      File(flag).writeAsStringSync('');
      await h.turn('forbidden');
      expect(
        said().last,
        contains('A UserPromptSubmit hook held this prompt back:\nnot that'),
      );
      expect(h.lastResult['is_error'], isTrue);
      expect(h.model.turns, hasLength(1));
    });

    test('Stop: sent back once with its reason', () async {
      final flag = p.join(bin, 'once');
      h = await Harness.start(
        settings: {
          'hooks': on(
            'Stop',
            script(
              'stop.sh',
              'if [ ! -f $flag ]; then touch $flag; echo "run the tests" >&2; exit 2; fi',
            ),
          ),
        },
      );
      h.model.script.addAll([Reply.text('done?'), Reply.text('tests run')]);
      await h.turn('work');
      expect(sentIn(h.model.turns.last), contains('run the tests'));
      expect(h.lastResult['result'], 'tests run');
    });

    test('SessionStart: its output is context for the model', () async {
      h = await Harness.start(
        settings: {
          'hooks': on(
            'SessionStart',
            script('start.sh', 'echo "Branch: main, clean."'),
          ),
        },
      );
      h.model.script.add(Reply.text('ok'));
      await h.turn('hi');
      expect(sentIn(h.model.turns.single), contains('Branch: main, clean.'));
    });

    test('a hook that fails is told, the call goes on', () async {
      h = await Harness.start(
        settings: {
          'hooks': on(
            'PreToolUse',
            script('bad.sh', 'echo broken >&2\nexit 1'),
          ),
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'echo fine', 'description': 'Echo'}),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      expect(h.toolResults.single['content'], 'fine');
      expect(jsonEncode(h.sent), contains('broken'));
    });

    test(
      'prompt hooks: the model judges a call, and whether to stop',
      () async {
        var stops = 0;
        h = await Harness.start(
          settings: {
            'hooks': {
              'PreToolUse': [
                {
                  'matcher': 'Bash',
                  'hooks': [
                    {
                      'type': 'prompt',
                      'prompt': r'Only safe commands: $ARGUMENTS',
                    },
                  ],
                },
              ],
              'Stop': [
                {
                  'hooks': [
                    {'type': 'prompt', 'prompt': 'Were the tests run?'},
                  ],
                },
              ],
            },
          },
          errands: (request) {
            final asked = jsonEncode(request.body);
            if (asked.contains('Only safe commands')) {
              return Reply.text('{"ok": false, "reason": "too dangerous"}');
            }
            if (asked.contains('Were the tests run?')) {
              return Reply.text(
                stops++ == 0
                    ? '{"ok": false, "reason": "run them"}'
                    : '{"ok": true}',
              );
            }
            return null;
          },
        );
        h.model.script.addAll([
          Reply.tool('Bash', {'command': 'rm -rf x', 'description': 'Remove'}),
          Reply.text('done?'),
          Reply.text('tests run'),
        ]);
        await h.turn('clean up');
        final result = h.toolResults.single;
        expect(result['is_error'], isTrue);
        expect('${result['content']}', contains('too dangerous'));
        expect(sentIn(h.model.turns.last), contains('run them'));
        expect(h.lastResult['result'], 'tests run');
        expect(stops, 2);
      },
    );

    test('a hook that takes too long is stopped, the call goes on', () async {
      h = await Harness.start(
        settings: {
          'hooks': {
            'PreToolUse': [
              {
                'hooks': [
                  {'type': 'command', 'command': 'sleep 5', 'timeout': 1},
                ],
              },
            ],
          },
          'permissions': {
            'allow': ['Bash(echo:*)'],
          },
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'echo fine', 'description': 'Echo'}),
        Reply.text('ok'),
      ]);
      final started = DateTime.now();
      await h.turn('go');
      expect(
        DateTime.now().difference(started),
        lessThan(const Duration(seconds: 4)),
      );
      expect(h.toolResults.single['content'], 'fine');
      expect(jsonEncode(h.sent), contains('timed out after 1s'));
    });

    test('the older answers: approve a call, block a stop', () async {
      final flag = p.join(bin, 'once');
      h = await Harness.start(
        settings: {
          'hooks': {
            ...on(
              'PreToolUse',
              script('pre.sh', 'echo \'{"decision": "approve"}\''),
            ),
            ...on(
              'Stop',
              script(
                'stop.sh',
                'if [ ! -f $flag ]; then touch $flag; echo \'{"decision": "block", "reason": "one more"}\'; fi',
              ),
            ),
          },
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'touch made', 'description': 'Make'}),
        Reply.text('done?'),
        Reply.text('done'),
      ]);
      await h.turn('go');
      expect(h.permissionRequests, isEmpty);
      expect(File(p.join(h.cwd, 'made')).existsSync(), isTrue);
      expect(sentIn(h.model.turns.last), contains('one more'));
      expect(h.lastResult['result'], 'done');
    });

    test('continue: false ends the turn, with its reason', () async {
      h = await Harness.start(
        settings: {
          'hooks': on(
            'PreToolUse',
            script(
              'pre.sh',
              'echo \'{"continue": false, "stopReason": "frozen for release"}\'',
            ),
          ),
        },
      );
      h.model.script.addAll([
        Reply.tool('Bash', {'command': 'echo x', 'description': 'Echo'}),
        Reply.text('never'),
      ]);
      await h.turn('go');
      expect(
        '${h.toolResults.single['content']}',
        contains('frozen for release'),
      );
      expect(h.model.turns, hasLength(1));
    });
  }, skip: Platform.isWindows);
}
