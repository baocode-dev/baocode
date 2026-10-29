// A preview of how todos read in the chat: the real ChatScreen, on the
// mock Claude Code CLI, with a turn that writes and updates todos
// (TodoWrite, TaskCreate, TaskUpdate, TaskList) between other steps.
//
//   flutter run -d macos -t tool/preview/todo_steps.dart
//
// Send any message to play the turn again.

import 'dart:async';

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  late final KernelDescriptor kernel;
  kernel = KernelDescriptor(
    id: 'claude-code',
    label: 'Claude Code',
    icon: Icons.auto_awesome_rounded,
    description: '',
    create: (context) => ClaudeCodeKernel(
      kernel,
      context,
      start: (launch) async => _TodoTransport(launch),
    ),
  );
  final session = ChatSession(
    kernel: kernel,
    kernels: [kernel],
    historyCount: 0,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      locale: const Locale('zh'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: ChatScreen(session: session),
    ),
  );
  Timer(const Duration(milliseconds: 800), () {
    session.send(const ComposerMessage(text: '把输入框改成随内容增高，改完跑一下测试'));
  });
}

/// The mock CLI for all but the turns: those play [_play].
class _TodoTransport implements ClaudeCodeTransport {
  _TodoTransport(this.launch) : _inner = MockClaudeCodeTransport(launch) {
    _inner.messages.listen(_out.add, onDone: _out.close);
  }

  final ClaudeLaunch launch;
  final MockClaudeCodeTransport _inner;
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  int _ids = 0;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<void> get exited => _inner.exited;

  @override
  void close() => _inner.close();

  @override
  void write(Map<String, Object?> message) {
    if (message['type'] != 'user') return _inner.write(message);
    unawaited(_play(message));
  }

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) {
      _out.add({...message, 'session_id': 'mock-claude-session'});
    }
  }

  Future<void> _pause([int ms = 700]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void _say(String text) => _emit({
    'type': 'assistant',
    'parent_tool_use_id': null,
    'message': {
      'id': 'msg_${++_ids}',
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  });

  Future<void> _tool(
    String name,
    Map<String, Object?> input,
    String result, {
    Map<String, Object?>? structured,
    int runFor = 600,
  }) async {
    final id = 'toolu_${++_ids}';
    _emit({
      'type': 'assistant',
      'parent_tool_use_id': null,
      'message': {
        'id': 'msg_${++_ids}',
        'role': 'assistant',
        'model': 'claude-opus-5-5',
        'content': [
          {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
        ],
      },
    });
    await _pause(runFor);
    _emit({
      'type': 'user',
      'parent_tool_use_id': null,
      'message': {
        'role': 'user',
        'content': [
          {'type': 'tool_result', 'tool_use_id': id, 'content': result},
        ],
      },
      'tool_use_result': ?structured,
    });
    await _pause(400);
  }

  static List<Map<String, Object?>> _todos(List<String> statuses) => [
    for (final (i, (content, active)) in const [
      ('读一下 ChatComposer 的高度逻辑', '读 ChatComposer 的高度逻辑'),
      ('改成随内容增高，最多 8 行', '修改输入框高度'),
      ('跑 composer 相关测试', '跑测试'),
    ].indexed)
      {'content': content, 'status': statuses[i], 'activeForm': active},
  ];

  Future<void> _play(Map<String, Object?> message) async {
    _emit({
      'type': 'system',
      'subtype': 'init',
      'cwd': launch.cwd,
      'model': 'claude-opus-5-5',
      'permissionMode': launch.permissionMode ?? 'default',
    });
    _emit({...message, 'isReplay': true});
    _emit({
      'type': 'command_lifecycle',
      'command_uuid': message['uuid'],
      'state': 'started',
    });
    await _pause(500);
    _say('好的，我先把要做的事列一下。');
    await _pause();
    const written = 'Todos have been modified successfully.';
    await _tool('TodoWrite', {
      'todos': _todos(['in_progress', 'pending', 'pending']),
    }, written);
    await _tool('Read', {
      'file_path': 'lib/chat/composer/composer.dart',
    }, '     1\timport \'package:flutter/material.dart\';\n…');
    await _tool('TodoWrite', {
      'todos': _todos(['completed', 'in_progress', 'pending']),
    }, written);
    _say('高度由 `_maxEditorLines` 控制，改成 8 行并开启 `shrinkWrap`。');
    await _pause();
    await _tool('TodoWrite', {
      'todos': _todos(['completed', 'completed', 'in_progress']),
    }, written);
    await _tool(
      'Bash',
      {
        'command': 'flutter test test/composer_test.dart',
        'description': '跑 composer 测试',
      },
      '00:04 +38: All tests passed!',
      runFor: 1500,
    );
    await _tool('TodoWrite', {
      'todos': _todos(['completed', 'completed', 'completed']),
    }, written);
    // The newer CLI's tasks, one call an item.
    await _tool(
      'TaskCreate',
      {
        'subject': '更新 CHANGELOG',
        'description': '记下输入框高度的变化',
        'activeForm': '更新 CHANGELOG',
      },
      'Task #1 created successfully: 更新 CHANGELOG',
      structured: {
        'task': {'id': '1', 'subject': '更新 CHANGELOG'},
      },
    );
    await _tool('TaskUpdate', {
      'taskId': '1',
      'status': 'completed',
    }, 'Updated task #1 status');
    await _tool(
      'TaskList',
      const <String, Object?>{},
      '#1 [completed] 更新 CHANGELOG',
    );
    _say('都完成了：输入框现在随内容增高，最多 8 行后滚动，测试全部通过。');
    await _pause(300);
    _emit({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'total_cost_usd': 0.0421,
      'usage': {
        'input_tokens': 120,
        'cache_read_input_tokens': 18000,
        'output_tokens': 480,
      },
    });
  }
}
