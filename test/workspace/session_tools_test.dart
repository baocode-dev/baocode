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
    app = Directory.systemTemp.createTempSync('session-tools').path;
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
      'Sent: it is on it.',
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
      startsWith('It is idle now.'),
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
}

/// The mock's, each launch under a session id of its own.
class _OwnSession implements ClaudeCodeTransport {
  _OwnSession(this._inner, this._id);

  final ClaudeCodeTransport _inner;
  final String _id;

  @override
  Stream<Map<String, Object?>> get messages => _inner.messages.map(
    (message) => message.containsKey('session_id')
        ? {...message, 'session_id': _id}
        : message,
  );

  @override
  void write(Map<String, Object?> message) => _inner.write(message);

  @override
  void close() => _inner.close();

  @override
  Future<void> get exited => _inner.exited;
}
