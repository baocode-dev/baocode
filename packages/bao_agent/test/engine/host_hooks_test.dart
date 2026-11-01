import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;

  tearDown(() => h.dispose());

  Map<String, Object?> hooks(String matcher) => {
    'PreToolUse': [
      {
        'matcher': matcher,
        'hookCallbackIds': ['before'],
      },
    ],
    'PostToolUse': [
      {
        'matcher': matcher,
        'hookCallbackIds': ['after'],
      },
    ],
  };

  test("the host's hooks are called back, its subagents' tools' too, "
      'the tool waiting on the answer', () async {
    h = await Harness.start(files: {'b.txt': 'old\n'});
    final called = <(String, String, String?, String?)>[];
    h.onRequest = (request) async {
      if (request['subtype'] != 'hook_callback') return const {};
      final input = (request['input'] as Map).cast<String, Object?>();
      final path = (input['tool_input'] as Map)['file_path'] as String;
      final file = File(path);
      called.add((
        request['callback_id'] as String,
        input['tool_name'] as String,
        file.existsSync() ? file.readAsStringSync() : null,
        input['agent_id'] as String?,
      ));
      expect(request['tool_use_id'], input['tool_use_id']);
      // The tool waits.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return const {};
    };
    await h.request('initialize', {'hooks': hooks('Write|Edit')});
    h.model.route = (request) {
      final messages = jsonEncode(request.body['messages']);
      if (!messages.contains('SUB: edit')) return null;
      // Read first, as an edit must be.
      return switch ('tool_result'.allMatches(messages).length) {
        0 => Reply.tool('Read', {'file_path': p.join(h.cwd, 'b.txt')}),
        1 => Reply.tool('Edit', {
          'file_path': p.join(h.cwd, 'b.txt'),
          'old_string': 'old',
          'new_string': 'new',
        }),
        _ => Reply.text('edited'),
      };
    };
    h.model.script.addAll([
      Reply.tool('Write', {
        'file_path': p.join(h.cwd, 'a.txt'),
        'content': 'a',
      }),
      Reply.tool('Agent', {
        'description': 'Edit',
        'prompt': 'SUB: edit b.txt',
        'subagent_type': 'general-purpose',
        'run_in_background': false,
      }),
      Reply.text('done'),
    ]);
    await h.turn('go');

    expect(
      [for (final c in called) (c.$1, c.$2, c.$3)],
      [
        ('before', 'Write', null),
        ('after', 'Write', 'a'),
        ('before', 'Edit', 'old\n'),
        ('after', 'Edit', 'new\n'),
      ],
    );
    expect(called[0].$4, isNull);
    expect(called[2].$4, isNotNull);
  });

  test("a host's hook may turn a tool down, and is set anew with each "
      'initialize', () async {
    h = await Harness.start();
    h.onRequest = (request) async => request['callback_id'] == 'before'
        ? {
            'hookSpecificOutput': {
              'hookEventName': 'PreToolUse',
              'permissionDecision': 'deny',
              'permissionDecisionReason': 'not here',
            },
          }
        : const {};
    await h.request('initialize', {'hooks': hooks('Write')});
    h.model.script.addAll([
      Reply.tool('Write', {
        'file_path': p.join(h.cwd, 'a.txt'),
        'content': 'a',
      }),
      Reply.text('stopped'),
    ]);
    await h.turn('go');
    expect(File(p.join(h.cwd, 'a.txt')).existsSync(), isFalse);
    expect(
      jsonEncode(h.model.turns.last.body['messages']),
      contains('not here'),
    );

    await h.request('initialize', {'hooks': <String, Object?>{}});
    h.model.script.addAll([
      Reply.tool('Write', {
        'file_path': p.join(h.cwd, 'a.txt'),
        'content': 'a',
      }),
      Reply.text('written'),
    ]);
    await h.turn('again');
    expect(File(p.join(h.cwd, 'a.txt')).readAsStringSync(), 'a');
  });
}
