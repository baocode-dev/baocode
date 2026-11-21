// A preview of how a skill run in a subagent of its own (`context: fork`)
// reads in the chat: the real ChatScreen, on the mock Claude Code CLI,
// playing what Claude Code 2.1.321 sends for one, as recorded.
//
//   flutter run -d macos -t tool/preview/fork_skill_steps.dart
//
// Two turns: `/code-review` typed (the CLI says nothing of the subagent's
// work until it is done, then gives all of it), then the model calling a
// skill (the subagent's messages come as it works). With
// BAOCODE_PREVIEW_OUT set, it saves a picture of the chat at each step
// there.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

final _frame = GlobalKey();
late final ChatSession _session;

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
      start: (launch) async => _ForkTransport(launch),
    ),
  );
  _session = ChatSession(kernel: kernel, kernels: [kernel], historyCount: 0);
  runApp(
    RepaintBoundary(
      key: _frame,
      child: MaterialApp(
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
        home: ChatScreen(session: _session),
      ),
    ),
  );
  Timer(const Duration(milliseconds: 800), () {
    _session.send(const ComposerMessage(text: '/code-review'));
  });
}

/// Saves the chat as it shows now, as [name].png, when asked to.
Future<void> _shot(String name) async {
  final out = Platform.environment['BAOCODE_PREVIEW_OUT'];
  if (out == null) return;
  await Future<void>.delayed(const Duration(milliseconds: 400));
  final boundary =
      _frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 2);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$out/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
}

/// The mock CLI for all but the turns: those play what the real one sent.
class _ForkTransport implements ClaudeCodeTransport {
  _ForkTransport(this.launch) : _inner = MockClaudeCodeTransport(launch) {
    _inner.messages.listen(_out.add, onDone: _out.close);
  }

  final ClaudeLaunch launch;
  final MockClaudeCodeTransport _inner;
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  int _ids = 0;
  int _turns = 0;

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  @override
  Future<void> get exited => _inner.exited;

  @override
  void close() => _inner.close();

  @override
  void write(Map<String, Object?> message) {
    if (message['type'] != 'user') return _inner.write(message);
    unawaited(_turns++ == 0 ? _slashCommand(message) : _modelCalls(message));
  }

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) {
      _out.add({...message, 'session_id': 'mock-claude-session'});
    }
  }

  Future<void> _pause([int ms = 700]) =>
      Future<void>.delayed(Duration(milliseconds: ms));

  void _say(String text, {String? parent}) => _emit({
    'type': 'assistant',
    'parent_tool_use_id': parent,
    'message': {
      'id': 'msg_${++_ids}',
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  });

  String _call(String name, Map<String, Object?> input, {String? parent}) {
    final id = 'toolu_${++_ids}';
    _emit({
      'type': 'assistant',
      'parent_tool_use_id': parent,
      'message': {
        'id': 'msg_${++_ids}',
        'role': 'assistant',
        'model': 'claude-opus-5-5',
        'content': [
          {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
        ],
      },
    });
    return id;
  }

  void _result(
    String id,
    String content, {
    String? parent,
    Map<String, Object?>? structured,
  }) => _emit({
    'type': 'user',
    'parent_tool_use_id': parent,
    'message': {
      'role': 'user',
      'content': [
        {'type': 'tool_result', 'tool_use_id': id, 'content': content},
      ],
    },
    'tool_use_result': ?structured,
  });

  void _start(Map<String, Object?> message) {
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
  }

  void _done() => _emit({
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

  /// `/code-review` typed: one task, nothing more until it is done; then
  /// all its subagent said, under `forked-command-code-review`.
  Future<void> _slashCommand(Map<String, Object?> message) async {
    _start(message);
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': 'a7b9cae6c8e726d75',
      'description': '/code-review',
      'subagent_type': 'general-purpose',
      'is_backgrounded': false,
      'spawn_depth': 1,
      'task_type': 'local_agent',
      'prompt':
          '`max effort → 5+5 angles × 8 candidates → 1-vote verify → '
          'sweep → ≤15 findings`',
    });
    await _pause(5000);
    await _shot('1-slash-running');
    _emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': 'a7b9cae6c8e726d75',
      'status': 'completed',
      'summary': '/code-review',
    });
    const fork = 'forked-command-code-review';
    final diff = _call('Bash', {
      'command': 'git diff HEAD',
      'description': '读取待审查的 diff',
    }, parent: fork);
    _result(diff, 'diff --git a/a.py b/a.py\n…', parent: fork);
    for (final angle in ['Angle A — 逐行扫描', 'Angle B — 删除行为审计']) {
      final finder = _call('Agent', {
        'description': angle,
        'subagent_type': 'general-purpose',
        'prompt': '审查 a.py 的改动：$angle',
      }, parent: fork);
      _result(finder, '1 条候选：第 5 行 range(1, …) 漏掉了 xs[0]', parent: fork);
    }
    _say('核对完毕：第 5 行 off-by-one，确认。', parent: fork);
    await _pause(300);
    _say(
      '1 finding:\n\n1. `a.py:5`: `range(1, len(xs))` 跳过了 `xs[0]`，'
      '非空输入的平均值都会算错。',
    );
    await _pause(300);
    _done();
    await _shot('2-slash-done');
    await _pause(800);
    _session.send(
      const ComposerMessage(text: 'a.py 有几行？用 count-lines skill 数一下'),
    );
  }

  /// The model calls a skill that runs forked: its subagent's messages come
  /// as it works, under the Skill call.
  Future<void> _modelCalls(Map<String, Object?> message) async {
    _start(message);
    await _pause(500);
    final skill = _call('Skill', {'skill': 'count-lines'});
    await _pause(300);
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': 'aca8be42a9aafb27f',
      'tool_use_id': skill,
      'description': '/count-lines',
      'subagent_type': 'general-purpose',
      'is_backgrounded': false,
      'spawn_depth': 1,
      'task_type': 'local_agent',
      'prompt': 'Run `wc -l a.py` with Bash, then answer with just the number.',
    });
    final count = _call('Bash', {
      'command': 'wc -l a.py',
      'description': '数 a.py 的行数',
    }, parent: skill);
    await _pause(3000);
    await _shot('3-model-running');
    _result(count, '       7 a.py', parent: skill);
    _say('7', parent: skill);
    await _pause(500);
    _emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': 'aca8be42a9aafb27f',
      'tool_use_id': skill,
      'status': 'completed',
      'summary': '/count-lines',
    });
    _result(
      skill,
      'Skill "count-lines" completed (forked execution).\n\nResult:\n7',
      structured: {
        'success': true,
        'commandName': 'count-lines',
        'status': 'forked',
        'agentId': 'aca8be42a9aafb27f',
        'result': '7',
      },
    );
    await _pause(300);
    _say('a.py 有 7 行。');
    await _pause(300);
    _done();
    await _shot('4-model-done');
  }
}
