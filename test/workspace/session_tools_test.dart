import 'dart:async';
import 'dart:io';

import 'package:baocode/bots/bot_tools.dart';
import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_sdk_tools.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/workspace/session_tools.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final launches = <ClaudeLaunch>[];
  late KernelDescriptor kernel;
  kernel = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) => ClaudeCodeKernel(
      kernel,
      context,
      start: (launch) async {
        launches.add(launch);
        return _OwnSession(
          await MockClaudeCodeTransport.start(launch),
          launch.resume ?? 'session-${launches.length}',
        );
      },
    ),
  );
  late Workspace workspace;
  late String app;
  var on = true;

  setUp(() {
    launches.clear();
    on = true;
    SessionToolsSetting.current = () => on;
    // As Git spells it (macOS's temp folder is a link).
    app = Directory.systemTemp
        .createTempSync('session-tools')
        .resolveSymbolicLinksSync();
    workspace = Workspace(kernels: [kernel], projects: [Project('app', app)]);
    SessionTools.register(workspace);
  });

  tearDown(() {
    SessionTools.unregister();
    SessionToolsSetting.current = () => false;
    workspace.dispose();
    Directory(app).deleteSync(recursive: true);
  });

  Future<List<String>> offered(String cwd) async {
    final answer = await ClaudeSdkTools.handle({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/list',
    }, ClaudeSdkCall(cwd: cwd));
    return [
      for (final tool
          in ((answer['result'] as Map)['tools'] as List).cast<Map>())
        tool['name'] as String,
    ];
  }

  Future<String> call(
    String tool,
    Map<String, Object?> arguments, {
    String? from,
  }) async {
    final answer = await ClaudeSdkTools.handle({
      'jsonrpc': '2.0',
      'id': 2,
      'method': 'tools/call',
      'params': {'name': tool, 'arguments': arguments},
    }, ClaudeSdkCall(cwd: app, sessionId: from));
    final result = answer['result'] as Map;
    return ((result['content'] as List).single as Map)['text'] as String;
  }

  /// [thread] started (its session known) and its turn stopped: the
  /// mock's own runs long.
  Future<void> settle(AgentThread thread) async {
    for (var i = 0; i < 500 && thread.session.sessionId == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    thread.session.stop();
    for (var i = 0; i < 500 && thread.session.isStreaming; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  test(
    'only with the setting on, and not to the app\'s own agents (#934)',
    () async {
      expect(await offered(app), containsAll(SessionTools.names));
      workspace.appFolderRoot = p.join(app, 'bots');
      expect(
        await offered(p.join(app, 'bots', 'mia')),
        isNot(contains('session_list')),
      );
      on = false;
      expect(await offered(app), isNot(contains('session_list')));
    },
  );

  test('an agent lists and reads the others, not itself; hands one work '
      'once, said so', () async {
    final lead = workspace.startAgent(workspace.projectAt(app));
    lead.session.send(const ComposerMessage(text: 'coordinate'));
    await settle(lead);
    final tests = workspace.startAgent(workspace.projectAt(app));
    workspace.rename(tests, 'Tests');
    tests.session.send(const ComposerMessage(text: 'run the tests'));
    await settle(tests);
    final leadId = lead.id!;
    final testsId = BotTools.idOf(tests);

    final listed = await call('session_list', {}, from: leadId);
    expect(listed, contains('$testsId | app | Tests | idle'));
    expect(listed, isNot(contains(BotTools.idOf(lead))));

    final started = launches.length;
    final read = await call('session_read', {'session': testsId}, from: leadId);
    expect(read, startsWith('"Tests" in app'));
    expect(read, contains('User: run the tests'));
    // Read, not woken.
    expect(launches, hasLength(started));

    expect(
      await call('session_send', {
        'session': testsId,
        'text': 'and lint',
      }, from: leadId),
      startsWith('Sent: it is on it'),
    );
    await settle(tests);
    final sent = [
      for (var i = 0; i < tests.session.itemCount; i++)
        if (tests.session.itemAt(i) case UserMessageItem(:final text)) text,
    ];
    expect(sent, contains('and lint'));
    expect(
      await call('session_send', {
        'session': testsId,
        'text': 'and lint',
      }, from: leadId),
      startsWith('Not delivered: the same message'),
    );
    expect(
      await call('session_send', {
        'session': BotTools.idOf(lead),
        'text': 'x',
      }, from: leadId),
      endsWith('That is this conversation.'),
    );

    expect(
      await call('session_wait', {
        'session': testsId,
        'seconds': 10,
      }, from: leadId),
      startsWith('$testsId ("Tests") is done.'),
    );

    // At work: queued behind its turn, not cutting it short.
    tests.session.send(const ComposerMessage(text: 'and the docs'));
    for (var i = 0; i < 500 && !tests.session.isStreaming; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(
      await call('session_send', {
        'session': testsId,
        'text': 'then the changelog',
      }, from: leadId),
      startsWith('Queued'),
    );
    expect(tests.session.isStreaming, isTrue);
    expect(
      [for (final (_, message) in tests.session.queued) message.text],
      ['then the changelog'],
    );
    tests.session.stop();
  });

  /// [test] true, in time.
  Future<void> until(bool Function() test, {int seconds = 15}) async {
    for (var i = 0; i < seconds * 50 && !test(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(test(), isTrue);
  }

  /// The messages another agent sent [thread], by who sent them.
  List<(String, String)> fromAgents(AgentThread thread) => [
    for (var i = 0; i < thread.session.itemCount; i++)
      if (thread.session.itemAt(i) case UserMessageItem(
        :final text,
        fromAgent: final from?,
      ))
        (from, text),
  ];

  /// A lead agent, started and stopped: its approvals [permission].
  Future<AgentThread> lead({String permission = 'dontAsk'}) async {
    final lead = workspace.startAgent(workspace.projectAt(app));
    workspace.rename(lead, 'Lead');
    final permissions = lead.session.permissions!;
    permissions.onSelected(
      permissions.options.firstWhere((option) => option.id == permission),
    );
    lead.session.send(const ComposerMessage(text: 'coordinate'));
    await settle(lead);
    return lead;
  }

  AgentThread started(String answer) {
    final id = RegExp(r'Started: (\S+) in').firstMatch(answer)![1];
    return workspace.threads.firstWhere((t) => BotTools.idOf(t) == id);
  }

  test('a conversation started reports back by itself, its reply whole, '
      'as its card: once', () async {
    final boss = await lead();
    final answer = await call('session_new', {
      'text': 'look at the tests (quick)',
      'title': 'Tests',
    }, from: boss.id);
    expect(answer, startsWith('Started: '));
    final tests = started(answer);
    expect(tests.title, 'Tests');
    // As the lead's, its approvals; as its card, the message.
    expect(tests.session.selected(KernelChoiceKind.permission), 'dontAsk');
    await until(() => fromAgents(tests).isNotEmpty);
    expect(fromAgents(tests).single, ('Lead', 'look at the tests (quick)'));
    expect(
      await call('session_list', {'mine': true}, from: boss.id),
      allOf(contains('| Tests |'), endsWith('| yours')),
    );

    // Done: told the lead, with all it said.
    await until(() => fromAgents(boss).isNotEmpty);
    final (from, report) = fromAgents(boss).single;
    expect(from, 'Tests');
    expect(report, contains('is done.\nIts reply:\n\n$_quickReply'));
    await settle(boss);

    // Waited on: said by the wait, not told again.
    expect(
      await call('session_send', {
        'session': BotTools.idOf(tests),
        'text': 'and the docs (quick)',
      }, from: boss.id),
      startsWith('Sent'),
    );
    final waited = await call('session_wait', {
      'sessions': [BotTools.idOf(tests)],
      'seconds': 10,
    }, from: boss.id);
    expect(
      waited,
      '${BotTools.idOf(tests)} ("Tests") is done.\nIts reply:\n\n'
      '$_quickReply',
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fromAgents(boss), hasLength(1));

    expect(
      await call('session_changes', {
        'session': BotTools.idOf(tests),
      }, from: boss.id),
      'It edited no files.',
    );
  });

  test('one waiting on the user says what for; not written to then; '
      'stopped by the lead, not reported', () async {
    final boss = await lead(permission: 'default');
    final tests = started(
      await call('session_new', {
        'text': 'fix the input (ask)',
        'title': 'Input',
      }, from: boss.id),
    );
    // It asks the user: told the lead.
    await until(() => fromAgents(boss).isNotEmpty);
    final (_, report) = fromAgents(boss).single;
    expect(
      report,
      contains(
        'waits on the user. It asks them: Which one? (This / That) Only '
        'they can answer it',
      ),
    );
    await settle(boss);
    // Answering it is the user's.
    expect(tests.session.pendingInteraction, isNotNull);
    expect(
      await call('session_send', {
        'session': BotTools.idOf(tests),
        'text': 'pick the first',
      }, from: boss.id),
      startsWith('Not delivered: it waits on the user. It asks them'),
    );
    final read = await call('session_read', {
      'session': BotTools.idOf(tests),
      'full': true,
    }, from: boss.id);
    expect(read, contains('Only the user can answer it.'));
    expect(read, contains('From "Lead": fix the input (ask)'));
    expect(
      await call('session_read', {
        'session': BotTools.idOf(tests),
        'skip': 1,
      }, from: boss.id),
      endsWith('From "Lead": fix the input (ask)'),
    );

    expect(
      await call('session_stop', {
        'session': BotTools.idOf(tests),
      }, from: boss.id),
      'Stopped.',
    );
    await until(() => !tests.session.isStreaming);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(fromAgents(boss), hasLength(1));
  });

  test('a model picked by its id, another refused with those there are; '
      'a worktree on a branch of its own', () async {
    final boss = await lead();
    expect(
      await call('session_new', {'text': 'x', 'model': 'gpt-0'}, from: boss.id),
      allOf(contains('No model "gpt-0"'), contains('sonnet')),
    );
    final quick = started(
      await call('session_new', {
        'text': 'a look (quick)',
        'model': 'sonnet',
      }, from: boss.id),
    );
    expect(quick.session.selected(KernelChoiceKind.model), 'sonnet');

    Future<void> git(List<String> arguments) async {
      final result = await Process.run('git', arguments, workingDirectory: app);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }

    await git(['init', '-q']);
    await git([
      '-c',
      'user.name=t',
      '-c',
      'user.email=t@t',
      'commit',
      '-q',
      '--allow-empty',
      '-m',
      'first',
    ]);
    final worktree = '$app-fix-login';
    addTearDown(() {
      if (Directory(worktree).existsSync()) {
        Directory(worktree).deleteSync(recursive: true);
      }
    });
    final answer = await call('session_new', {
      'text': 'fix the login (quick)',
      'worktree': 'fix/login',
    }, from: boss.id);
    expect(
      answer,
      contains('It works in $worktree, on the new branch fix/login.'),
    );
    expect(Directory(worktree).existsSync(), isTrue);
    final fixing = started(answer);
    await until(() => fromAgents(fixing).isNotEmpty);
    expect(
      fromAgents(fixing).single.$2,
      startsWith('Work in $worktree (branch fix/login'),
    );
  });
}

/// The mock's, each launch under a session id of its own. A message with
/// "(quick)" in it is answered at once, [_quickReply]; one with "(ask)",
/// with a question for the user at once: not the mock's long run.
class _OwnSession implements ClaudeCodeTransport {
  _OwnSession(this._inner, this._id) {
    _inner.messages.listen(_out.add, onDone: _out.close);
  }

  final ClaudeCodeTransport _inner;
  final String _id;
  final _out = StreamController<Map<String, Object?>>.broadcast();

  /// A quick turn under way.
  bool _running = false;
  int _count = 0;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream.map(
    (message) => message.containsKey('session_id')
        ? {...message, 'session_id': _id}
        : message,
  );

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add({...message, 'session_id': _id});
  }

  @override
  void write(Map<String, Object?> message) {
    final text = switch (message) {
      {'type': 'user', 'message': {'content': final List<Object?> content}} =>
        content.whereType<Map<Object?, Object?>>().map((b) => b['text']).join(),
      _ => '',
    };
    if (text.contains('(quick)') || text.contains('(ask)')) {
      final uuid = message['uuid'] as String;
      _running = true;
      _emit({'type': 'system', 'subtype': 'init', 'model': 'claude-opus-5-5'});
      _emit({...message, 'isReplay': true});
      _emit({
        'type': 'command_lifecycle',
        'command_uuid': uuid,
        'state': 'started',
      });
      if (text.contains('(ask)')) {
        final id = 'toolu_q${++_count}';
        final input = {
          'questions': [
            {
              'question': 'Which one?',
              'header': 'Pick',
              'options': [
                {'label': 'This', 'description': ''},
                {'label': 'That', 'description': ''},
              ],
              'multiSelect': false,
            },
          ],
        };
        _emit({
          'type': 'assistant',
          'message': {
            'id': 'msg_q$_count',
            'role': 'assistant',
            'content': [
              {
                'type': 'tool_use',
                'id': id,
                'name': 'AskUserQuestion',
                'input': input,
              },
            ],
          },
          'parent_tool_use_id': null,
        });
        _emit({
          'type': 'control_request',
          'request_id': 'perm_q$_count',
          'request': {
            'subtype': 'can_use_tool',
            'tool_name': 'AskUserQuestion',
            'input': input,
            'tool_use_id': id,
            'requires_user_interaction': true,
          },
        });
        return;
      }
      Timer(const Duration(milliseconds: 100), () {
        if (!_running) return;
        _running = false;
        _emit({
          'type': 'assistant',
          'message': {
            'id': 'msg_q${++_count}',
            'role': 'assistant',
            'content': [
              {'type': 'text', 'text': _quickReply},
            ],
          },
          'parent_tool_use_id': null,
        });
        _result();
      });
      return;
    }
    if (message
        case {
          'type': 'control_request',
          'request_id': final String id,
          'request': {'subtype': 'interrupt'},
        }
        when _running) {
      _running = false;
      _emit({
        'type': 'control_response',
        'response': {'subtype': 'success', 'request_id': id, 'response': {}},
      });
      _result(error: true);
      return;
    }
    _inner.write(message);
  }

  void _result({bool error = false}) => _emit({
    'type': 'result',
    'subtype': error ? 'error_during_execution' : 'success',
    'is_error': false,
    'total_cost_usd': 0.01,
    'usage': {'input_tokens': 10, 'output_tokens': 10},
  });

  @override
  void close() => _inner.close();

  @override
  Future<void> get exited => _inner.exited;
}

const _quickReply = 'All looked at.\n\nThe tests pass, and the docs are fine.';
