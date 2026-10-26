import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_agent/bao_agent.dart';
import 'package:bao_agent/src/tools/file_state.dart';
import 'package:bao_agent/src/tools/tool.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// The less travelled ways: plans approved, agents that fail, compaction
/// under pressure, notebooks with outputs, inputs not quite right.
void main() {
  late Harness h;

  tearDown(() => h.dispose());

  String sentIn(ModelRequest request) => jsonEncode(request.body['messages']);

  test('a plan approved: the mode is left, the plan given back', () async {
    h = await Harness.start(permissionMode: 'plan');
    h.model.script.add(Reply.text('looking'));
    await h.turn('plan');
    final plan = RegExp(r'write it to ([^ ]+\.md)')
        .firstMatch(sentIn(h.model.turns.first))![1]!;
    h.model.script.addAll([
      Reply.tool('Write', {
        'file_path': plan,
        'content': '# Plan\n\nStep one.',
      }),
      Reply.tool('ExitPlanMode', {}),
      Reply.tool('Write', {
        'file_path': p.join(h.cwd, 'done.txt'),
        'content': 'x',
      }),
      Reply.text('done'),
    ]);
    h.onPermission = (request) async => {
      'behavior': 'allow',
      'updatedInput': request['input'],
      if (request['tool_name'] == 'ExitPlanMode')
        'updatedPermissions': [
          {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
        ],
    };
    await h.turn('go');
    final exit = h.toolResults[1];
    expect(
      '${exit['content']}',
      allOf(contains('The user approved your plan'), contains('Step one.')),
    );
    expect((exit['tool_use_result'] as Map)['filePath'], plan);
    expect(
      (await h.request('get_settings'))['applied'],
      containsPair('permissionMode', 'acceptEdits'),
    );
    // Edits are accepted now: not asked about.
    expect(h.permissionRequests.map((r) => r['tool_name']), ['ExitPlanMode']);
  });

  test('a plan sent rather than written is kept in its file, which the '
      'user is shown', () async {
    // #298: the file named was not there, and its tab said so.
    h = await Harness.start(permissionMode: 'plan');
    h.model.script.add(Reply.text('looking'));
    await h.turn('plan');
    final plan = RegExp(r'write it to ([^ ]+\.md)')
        .firstMatch(sentIn(h.model.turns.first))![1]!;
    expect(File(plan).existsSync(), isFalse);
    h.model.script.addAll([
      Reply.tool('ExitPlanMode', {'plan': '# Plan\n\nStep one.'}),
      Reply.text('done'),
    ]);
    Map<String, Object?>? asked;
    h.onPermission = (request) async {
      asked = request;
      // Shown the file: there by then.
      expect(File(plan).readAsStringSync(), '# Plan\n\nStep one.');
      return {'behavior': 'allow', 'updatedInput': request['input']};
    };
    await h.turn('go');
    expect((asked!['input'] as Map)['planFilePath'], plan);
    expect(File(plan).readAsStringSync(), '# Plan\n\nStep one.');
  });

  test('in plan mode, the cache ends before the reminder: the next turn '
      'reads it', () async {
    h = await Harness.start(permissionMode: 'plan');
    final path = p.join(h.cwd, 'f.txt');
    File(path).writeAsStringSync('hello');
    h.model.script.addAll([
      Reply.tool('Read', {'file_path': path}),
      Reply.tool('Read', {'file_path': path}),
      Reply.text('done'),
    ]);
    await h.turn('look');
    List<Map> messagesOf(ModelRequest request) => [
      for (final m in request.body['messages'] as List) m as Map,
    ];
    final first = messagesOf(h.model.turns[1]);
    final second = messagesOf(h.model.turns[2]);
    final last = (first.last['content'] as List).cast<Map>();
    expect('${last.last['text']}', contains('plan mode'));
    expect(last.last.containsKey('cache_control'), isFalse);
    expect(last[last.length - 2]['cache_control'], isNotNull);
    // What the first wrote to the cache, the second sends the same.
    final i = first.length - 1;
    expect(
      jsonEncode(second[i]),
      jsonEncode({...first[i], 'content': last.sublist(0, last.length - 1)}),
    );
  });

  test('questions not answered; EnterPlanMode is not for subagents', () async {
    h = await Harness.start();
    h.model.route = (request) {
      if (!jsonEncode((request.body['messages'] as List).first)
          .contains('SUB:')) {
        return null;
      }
      return sentIn(request).contains('EnterPlanMode') &&
              sentIn(request).contains('tool_result')
          ? Reply.text('fine')
          : Reply.tool('EnterPlanMode', {});
    };
    h.model.script.addAll([
      Reply.tool('AskUserQuestion', {
        'questions': [
          {
            'question': 'A or B?',
            'header': 'Pick',
            'multiSelect': false,
            'options': [
              {'label': 'A', 'description': 'a'},
              {'label': 'A', 'description': 'again'},
            ],
          },
        ],
      }),
      Reply.tool('AskUserQuestion', {
        'questions': [
          {
            'question': 'A or B?',
            'header': 'Pick',
            'multiSelect': false,
            'options': [
              {'label': 'A', 'description': 'a'},
              {'label': 'B', 'description': 'b'},
            ],
          },
        ],
      }),
      Reply.tool('Agent', {'description': 'Plan', 'prompt': 'SUB: plan'}),
      Reply.text('ok'),
    ]);
    await h.turn('ask');
    final [duplicate, unanswered, agent] = h.toolResults
        .where(
          (r) =>
              r['tool_use_id'] != null &&
              !'${r['tool_use_id']}'.startsWith('toolu_sub'),
        )
        .take(3)
        .toList();
    expect('${duplicate['content']}', contains('Option labels must be unique'));
    expect('${unanswered['content']}', contains('did not answer'));
    expect(agent['is_error'], isNot(isTrue));
  });

  group('subagents, as they go wrong', () {
    test('a type not there, an ID not there, a type in other case', () async {
      h = await Harness.start();
      h.model.route = (request) =>
          jsonEncode(request.body['system']).contains('You are an agent')
          ? Reply.text('found')
          : null;
      h.model.script.addAll([
        Reply.tools([
          (
            'Agent',
            {'description': 'x', 'prompt': 'p', 'subagent_type': 'nope'},
          ),
          ('Agent', {'description': 'x', 'prompt': 'p', 'resume': 'a-missing'}),
          (
            'Agent',
            {
              'description': 'x',
              'prompt': 'p',
              'subagent_type': 'general-PURPOSE',
            },
          ),
        ]),
        Reply.text('ok'),
      ]);
      await h.turn('go');
      final [unknown, missing, cased] = h.toolResults;
      expect(
        '${unknown['content']}',
        allOf(contains("no agent of the kind 'nope'"), contains('Explore')),
      );
      expect('${missing['content']}', contains('with the ID a-missing'));
      expect((cased['tool_use_result'] as Map)['status'], 'completed');
    });

    test('its API fails: the call says so; its hooks run', () async {
      final bin = Directory.systemTemp
          .createTempSync('hooks_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(bin).deleteSync(recursive: true));
      final hook = File(p.join(bin, 'start.sh'))
        ..writeAsStringSync(
          '#!/bin/sh\necho \'{"hookSpecificOutput": {"hookEventName": "SubagentStart", "additionalContext": "Mind the tests."}}\'\n',
        );
      Process.runSync('chmod', ['+x', hook.path]);
      h = await Harness.start(
        settings: {
          'hooks': {
            'SubagentStart': [
              {
                'hooks': [
                  {'type': 'command', 'command': hook.path},
                ],
              },
            ],
          },
        },
        environment: {'CLAUDE_CODE_SUBAGENT_MODEL': 'haiku'},
      );
      final seen = <ModelRequest>[];
      h.model.route = (request) {
        if (!jsonEncode((request.body['messages'] as List).first)
            .contains('SUB:')) {
          return null;
        }
        seen.add(request);
        return Reply.failing(
          const ApiError('overloaded', status: 529, type: 'overloaded_error'),
        );
      };
      h.model.script.addAll([
        Reply.tool('Agent', {'description': 'Work', 'prompt': 'SUB: work'}),
        Reply.text('it failed'),
      ]);
      await h.turn('go');
      expect(seen.single.model, contains('haiku'));
      expect(sentIn(seen.single), contains('Mind the tests.'));
      final result = h.toolResults.single;
      expect(result['is_error'], isTrue);
      expect('${result['content']}', contains('overloaded'));
      expect(
        h
            .of('assistant')
            .where(
              (m) =>
                  m['parent_tool_use_id'] != null && m['error'] == 'api_error',
            ),
        hasLength(1),
      );
    });

    test('stopped with the turn', () async {
      h = await Harness.start();
      h.model.delay = const Duration(milliseconds: 200);
      h.model.route = (request) =>
          jsonEncode((request.body['messages'] as List).first).contains('SUB:')
          ? Reply.text('a long answer that takes a while to come')
          : null;
      h.model.script.addAll([
        Reply.tool('Agent', {'description': 'Slow', 'prompt': 'SUB: slow'}),
      ]);
      final idle = h.nextIdle();
      h.send('go');
      await h.messages.firstWhere(
        (m) => m['type'] == 'system' && m['subtype'] == 'task_started',
      );
      await h.request('interrupt');
      await idle;
      expect(h.lastResult['subtype'], 'error_during_execution');
      expect(h.of('system', 'task_notification').single['status'], 'killed');
    });
  });

  group('compaction', () {
    test('a PreCompact hook adds to the instructions; todos and the plan carried over', () async {
      final bin = Directory.systemTemp
          .createTempSync('hooks_')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(bin).deleteSync(recursive: true));
      final hook = File(p.join(bin, 'pre.sh'))
        ..writeAsStringSync('#!/bin/sh\necho "Keep the API notes."\n');
      Process.runSync('chmod', ['+x', hook.path]);
      h = await Harness.start(
        permissionMode: 'plan',
        settings: {
          'hooks': {
            'PreCompact': [
              {
                'matcher': 'manual',
                'hooks': [
                  {'type': 'command', 'command': hook.path},
                ],
              },
            ],
          },
        },
      );
      h.model.script.add(Reply.text('looking'));
      await h.turn('plan');
      final plan = RegExp(r'write it to ([^ ]+\.md)')
          .firstMatch(sentIn(h.model.turns.first))![1]!;
      h.model.script.addAll([
        Reply.tools([
          ('Write', {'file_path': plan, 'content': '# Plan'}),
          (
            'TodoWrite',
            {
              'todos': [
                {
                  'content': 'First',
                  'status': 'pending',
                  'activeForm': 'Doing first',
                },
              ],
            },
          ),
        ]),
        Reply.text('ok'),
        Reply.text(''),
        Reply.text('<summary>Summed.</summary>'),
      ]);
      await h.turn('write');
      await h.turn('/compact');
      final summarizing = h.model.requests.lastWhere(
        (r) =>
            jsonEncode(r.body['system']).contains('summary of a conversation'),
      );
      expect(sentIn(summarizing), contains('Keep the API notes.'));
      final summary = h
          .of('user')
          .lastWhere((m) => m['isCompactSummary'] == true);
      expect(
        jsonEncode(summary),
        allOf(contains('[pending] First'), contains(plan)),
      );
    });

    test(
      'too long even to sum up: the oldest left out until it fits',
      () async {
        h = await Harness.start();
        for (var i = 0; i < 6; i++) {
          h.model.script.add(Reply.text('answer $i'));
        }
        for (var i = 0; i < 6; i++) {
          await h.turn('question $i');
        }
        h.model.script.addAll([
          Reply.failing(const ApiError('prompt is too long', status: 400)),
          Reply.text('<summary>Later part.</summary>'),
        ]);
        await h.turn('/compact');
        final attempts = h.model.requests
            .where(
              (r) =>
                  jsonEncode(r.body['system'])
                      .contains('summary of a conversation'),
            )
            .toList();
        expect(attempts, hasLength(2));
        expect(sentIn(attempts.last), isNot(contains('question 0')));
        expect(sentIn(attempts.last), contains('question 5'));
        expect(h.lastResult['result'], 'Compacted.');
      },
    );

    test('nothing to compact; the summary failing', () async {
      h = await Harness.start();
      await h.turn('/compact');
      expect(h.lastResult['result'], 'Nothing to compact.');
      h.model.script.addAll([
        Reply.text('one'),
        Reply.failing(const ApiError('invalid', status: 400)),
      ]);
      await h.turn('hi');
      await h.turn('/compact');
      expect(h.lastResult['is_error'], isTrue);
      expect(
        jsonEncode(h.of('assistant').last),
        contains('Error compacting conversation'),
      );
    });
  });

  test('notebook outputs, UTF-16 text, PDFs', () async {
    h = await Harness.start();
    final notebook = {
      'cells': [
        {
          'cell_type': 'code',
          'id': 'c1',
          'source': 'print(1)',
          'outputs': [
            {
              'output_type': 'stream',
              'text': ['1\n'],
            },
            {
              'output_type': 'error',
              'ename': 'ValueError',
              'evalue': 'bad',
              'traceback': ['line 1'],
            },
            {
              'output_type': 'display_data',
              'data': {
                'image/png': 'iVBORw0KGgo=',
                'text/plain': ['<Figure>'],
              },
            },
          ],
        },
      ],
      'metadata': {
        'language_info': {'name': 'r'},
      },
      'nbformat': 4,
      'nbformat_minor': 5,
    };
    File(p.join(h.cwd, 'n.ipynb')).writeAsStringSync(jsonEncode(notebook));
    File(p.join(h.cwd, 'bad.ipynb')).writeAsStringSync('{nope');
    File(p.join(h.cwd, 'u16.txt')).writeAsBytesSync(
      const FileText('', encoding: 'utf16le').encode('héllo\nwörld\n'),
    );
    File(p.join(h.cwd, 'doc.pdf'))
        .writeAsBytesSync(utf8.encode('%PDF-1.4 fake'));
    h.model.script.addAll([
      Reply.tools([
        ('Read', {'file_path': p.join(h.cwd, 'n.ipynb')}),
        ('Read', {'file_path': p.join(h.cwd, 'bad.ipynb')}),
        ('Read', {'file_path': p.join(h.cwd, 'u16.txt')}),
        ('Read', {'file_path': p.join(h.cwd, 'doc.pdf')}),
        ('Read', {'file_path': p.join(h.cwd, 'doc.pdf'), 'pages': '1-50'}),
      ]),
      Reply.tool('Edit', {
        'file_path': p.join(h.cwd, 'u16.txt'),
        'old_string': 'wörld',
        'new_string': 'welt',
      }),
      Reply.text('ok'),
    ]);
    await h.turn('read');
    final [nb, bad, u16, pdf, pages, edit] = h.toolResults;
    final cells = jsonEncode(nb['content']);
    expect(
      cells,
      allOf(
        contains('<language>r</language>'),
        contains('ValueError: bad'),
        contains('image/png'),
      ),
    );
    expect('${bad['content']}', contains('not valid JSON'));
    expect('${u16['content']}', allOf(contains('héllo'), contains('wörld')));
    expect(jsonEncode(pdf['content']), contains('application/pdf'));
    expect(jsonEncode(pages['content']), contains('application/pdf'));
    expect(edit['is_error'], isNot(isTrue));
    final written = File(p.join(h.cwd, 'u16.txt')).readAsBytesSync();
    expect(written.sublist(0, 2), [0xFF, 0xFE]);
    expect(readText(File(p.join(h.cwd, 'u16.txt'))).text, 'héllo\nwelt\n');
  });

  test('inputs set right or refused by their schema', () {
    final schema = {
      'type': 'object',
      'required': ['name'],
      'properties': {
        'name': {
          'type': 'string',
          'enum': ['a', 'b'],
        },
        'count': {'type': 'integer'},
        'ratio': {'type': 'number'},
        'flag': {'type': 'boolean'},
        'items': {
          'type': 'array',
          'minItems': 1,
          'maxItems': 2,
          'items': {'type': 'string'},
        },
      },
    };
    expect(
      validateSchema(schema, {
        'name': 'a',
        'count': 2,
        'items': ['x'],
      }),
      isNull,
    );
    expect(validateSchema(schema, {}), contains('`name` is missing'));
    expect(
      validateSchema(schema, {'name': 'c'}),
      contains('must be one of a, b'),
    );
    expect(
      validateSchema(schema, {'name': 'a', 'count': 1.5}),
      contains('integer'),
    );
    expect(
      validateSchema(schema, {'name': 'a', 'ratio': 'x'}),
      contains('number'),
    );
    expect(
      validateSchema(schema, {'name': 'a', 'flag': 'x'}),
      contains('boolean'),
    );
    expect(
      validateSchema(schema, {'name': 'a', 'items': []}),
      contains('at least 1'),
    );
    expect(
      validateSchema(schema, {
        'name': 'a',
        'items': ['x', 'y', 'z'],
      }),
      contains('at most 2'),
    );
    expect(
      validateSchema(schema, {
        'name': 'a',
        'items': [1],
      }),
      contains('items[0]'),
    );
    expect(
      validateSchema(schema, {'name': 'a', 'items': 'x'}),
      contains('array'),
    );
    expect(validateSchema(schema, 'x'), contains('object'));
    expect(
      coerceInput(schema, {
        'count': '3',
        'ratio': '0.5',
        'flag': 'true',
        'name': 'a',
      }),
      {'count': 3, 'ratio': 0.5, 'flag': true, 'name': 'a'},
    );
    expect(coerceInput(schema, {'count': 2.0, 'flag': 'false'}), {
      'count': 2,
      'flag': false,
    });
    expect(
      const ToolOutput([
        {'type': 'text', 'text': 'a'},
        {'type': 'image'},
      ]).text,
      'a',
    );
    expect('${const ToolFailure('why')}', 'why');
    expect(Uint8List(0), isEmpty);
  });

  test('checkpoints read back after a resume: files rewound', () async {
    h = await Harness.start(files: {'f.txt': 'before\n'});
    h.model.script.addAll([
      Reply.tool('Read', {'file_path': p.join(h.cwd, 'f.txt')}),
      Reply.tool('Write', {
        'file_path': p.join(h.cwd, 'f.txt'),
        'content': 'after\n',
      }),
      Reply.text('ok'),
    ]);
    final idle = h.nextIdle();
    h.send('change', uuid: 'u-change');
    await idle;
    expect(h.file('f.txt'), 'after\n');
    final sessionId = h.of('system', 'init').single['session_id'] as String;
    await h.engine.close();
    final again = await Harness.start(from: h, resume: sessionId);
    try {
      final answer = await again.request('rewind_files', {
        'user_message_id': 'u-change',
      });
      expect(answer['canRewind'], isTrue);
      expect(h.file('f.txt'), 'before\n');
    } finally {
      await again.engine.close();
    }
  });

  test('Bash: long output cut in the middle; TaskOutput filtered; TaskStop of what is not running', () async {
    h = await Harness.start(environment: {'BASH_MAX_OUTPUT_LENGTH': '200'});
    h.model.script.addAll([
      Reply.tool('Bash', {'command': 'seq 1 500', 'description': 'Count'}),
      Reply.tool('Bash', {
        'command': 'printf "keep 1\\ndrop\\nkeep 2\\n"',
        'description': 'Print',
        'run_in_background': true,
      }, id: 'toolu_print'),
    ]);
    h.model.route = (request) {
      final text = sentIn(request);
      if (text.contains('<task-notification>')) return Reply.text('noted');
      final id = RegExp(r'background with ID: (\w+)').firstMatch(text)?[1];
      if (id == null) return null;
      if (!text.contains('"name":"TaskOutput"')) {
        return Reply.tools([
          ('TaskOutput', {'task_id': id, 'block': true, 'filter': '^keep'}),
          ('TaskOutput', {'task_id': id, 'filter': '('}),
          ('TaskStop', {'task_id': 'b-none'}),
          ('TaskStop', {}),
        ]);
      }
      return null;
    };
    h.model.script.add(Reply.text('done'));
    await h.turn('go');
    final results = h.toolResults;
    expect(
      '${results[0]['content']}',
      allOf(contains('lines truncated'), startsWith('1\n'), endsWith('500')),
    );
    final [filtered, invalid, none, missing] = results.sublist(2, 6);
    expect(
      '${filtered['content']}',
      allOf(contains('keep 1'), contains('keep 2'), isNot(contains('drop'))),
    );
    expect('${invalid['content']}', contains('Invalid filter'));
    expect('${none['content']}', contains('No task found'));
    expect(missing['is_error'], isTrue);
  });
}
