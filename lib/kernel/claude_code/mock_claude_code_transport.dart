import 'dart:async';

import '../mock/mock_script.dart';
import 'claude_code_transport.dart';

/// Plays [MockScript] as Claude Code prints it, for tests and demos: the
/// same message shapes as the CLI (recorded from 2.1.281), answering the
/// control requests a session makes. Questions and plans wait on
/// `can_use_tool` like the real thing; other tools are allowed.
class MockClaudeCodeTransport implements ClaudeCodeTransport {
  MockClaudeCodeTransport([this.launch]);

  final ClaudeLaunch? launch;

  /// Asynchronous, as a process's output is: a reply never lands in the
  /// middle of handling another message.
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async =>
      MockClaudeCodeTransport(launch);

  late String _permissionMode = launch?.permissionMode ?? 'default';
  late String _model = launch?.model ?? 'default';
  late String? _effort = launch?.effort ?? 'high';

  String get _resolvedModel => switch (_model) {
    'default' || 'opus' => 'claude-opus-5-5',
    'opus[1m]' => 'claude-opus-5-5[1m]',
    'sonnet' => 'claude-sonnet-5',
    'haiku' => 'claude-haiku-4-5',
    final model => model,
  };

  int get _window => _resolvedModel.endsWith('[1m]') ? 1000000 : 200000;

  /// Where it compacts: the model's window, or less if set at start.
  late final int? _compactWindow = launch?.autocompact;
  int get _limit => switch (_compactWindow) {
    final window? when window < _window => window,
    _ => _window,
  };
  int _messages = 0;
  int _tools = 0;
  int _requests = 0;
  int _conversationTokens = 1200;
  double _cost = 0;

  /// The run in progress; a new one, or an interrupt, retires it.
  Object? _run;
  final Map<String, Completer<Map<String, Object?>>> _permissions = {};

  static const _sessionId = 'mock-claude-session';

  static const _changeDelay = Duration(milliseconds: 30);

  static const _fixedContext = {
    'System prompt': 3100,
    'System tools': 11800,
    'Memory files': 2400,
  };

  /// MCP servers by name, and where each stands.
  final Map<String, String> _mcp = {
    'github': 'connected',
    'linear': 'needs-auth',
    'postgres': 'failed',
  };

  Map<String, Object?> _mcpServer(String name) => {
    'name': name,
    'status': _mcp[name],
    'scope': name == 'postgres' ? 'project' : 'user',
    if (_mcp[name] == 'connected') ...{
      'serverInfo': {'name': name, 'version': '1.4.0'},
      'tools': [
        for (final tool in const ['search_issues', 'create_pull_request'])
          {'name': tool},
      ],
    },
    if (_mcp[name] == 'failed') 'error': 'Connection closed: ECONNREFUSED',
  };

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add({...message, 'session_id': _sessionId});
  }

  @override
  void write(Map<String, Object?> message) {
    switch (message['type']) {
      case 'control_request':
        _control(
          message['request_id'] as String,
          (message['request'] as Map).cast<String, Object?>(),
        );
      case 'control_response':
        final response = (message['response'] as Map).cast<String, Object?>();
        _permissions
            .remove(response['request_id'])
            ?.complete(
              (response['response'] as Map? ?? const {})
                  .cast<String, Object?>(),
            );
      case 'user':
        final uuid = message['uuid'] as String? ?? 'u${++_messages}';
        final content = ((message['message'] as Map)['content'] as List)
            .cast<Map<Object?, Object?>>();
        final text = content
            .where((block) => block['type'] == 'text')
            .map((block) => block['text'])
            .join('\n');
        _start(uuid, text, message);
    }
  }

  void _respond(String id, [Map<String, Object?> payload = const {}]) => _emit({
    'type': 'control_response',
    'response': {'subtype': 'success', 'request_id': id, 'response': payload},
  });

  void _control(String id, Map<String, Object?> request) {
    switch (request['subtype']) {
      case 'initialize':
        _respond(id, {
          'commands': [
            {
              'name': 'compact',
              'description': 'Clear conversation history but keep a summary',
              'argumentHint': '<optional custom summarization instructions>',
              'builtin': true,
            },
            {
              'name': 'context',
              'description': 'Show current context usage',
              'argumentHint': '',
              'builtin': true,
            },
            {
              'name': 'init',
              'description': 'Initialize a new CLAUDE.md file',
              'argumentHint': '',
              'builtin': true,
            },
            {
              'name': 'plan',
              'description': 'Draft a plan before editing',
              'argumentHint': '',
            },
            {
              'name': 'review',
              'description': 'Review uncommitted changes',
              'argumentHint': '',
              'builtin': true,
            },
            {
              'name': 'doctor',
              'description': 'Diagnose the installation',
              'argumentHint': '',
              'builtin': true,
            },
          ],
          'models': [
            {
              'value': 'default',
              'resolvedModel': 'claude-opus-5-5',
              'displayName': 'Auto',
              'description': 'Balanced quality and speed',
              'supportsEffort': true,
              'supportedEffortLevels': [
                'low',
                'medium',
                'high',
                'xhigh',
                'max',
              ],
              'supportsAutoMode': true,
            },
            {
              'value': 'opus',
              'resolvedModel': 'claude-opus-5-5',
              'displayName': 'Opus 5.5',
              'description': 'Most capable',
              'supportsEffort': true,
              'supportedEffortLevels': [
                'low',
                'medium',
                'high',
                'xhigh',
                'max',
              ],
              'supportsAutoMode': true,
            },
            {
              'value': 'opus[1m]',
              'resolvedModel': 'claude-opus-5-5[1m]',
              'displayName': 'Opus 5.5 (1M context)',
              'description': 'Most capable, for long sessions',
              'supportsEffort': true,
              'supportedEffortLevels': [
                'low',
                'medium',
                'high',
                'xhigh',
                'max',
              ],
              'supportsAutoMode': true,
            },
            {
              'value': 'sonnet',
              'resolvedModel': 'claude-sonnet-5',
              'displayName': 'Sonnet 5',
              'description': 'Fast and capable',
              'supportsEffort': true,
              'supportedEffortLevels': ['low', 'medium', 'high'],
            },
            {
              'value': 'haiku',
              'resolvedModel': 'claude-haiku-4-5',
              'displayName': 'Haiku 4.5',
              'description': 'Fastest',
            },
          ],
          'current_permission_mode': _permissionMode,
        });
      case 'interrupt':
        _respond(id);
        if (_run != null) {
          _run = null;
          _permissions.clear();
          _result(error: true);
        }
      // Changes take a moment, as the CLI's do: it answers other requests
      // meanwhile, with what was in effect before.
      case 'set_model':
        Timer(_changeDelay, () {
          _model = request['model'] as String? ?? 'default';
          _respond(id);
        });
      // An `autoCompactWindow` is stored, not applied: the session keeps
      // the one it started with.
      case 'apply_flag_settings':
        Timer(_changeDelay, () {
          final settings = request['settings'] as Map? ?? const {};
          if (settings['effortLevel'] case final String e) _effort = e;
          _respond(id);
        });
      case 'get_settings':
        _respond(id, {
          'applied': {'model': _resolvedModel, 'effort': _effort},
        });
      case 'set_permission_mode':
        _permissionMode = request['mode'] as String;
        _respond(id, {'mode': _permissionMode});
      case 'get_context_usage':
        final fixed = _fixedContext.values.fold(0, (sum, n) => sum + n);
        _respond(id, {
          'categories': [
            for (final MapEntry(:key, :value) in _fixedContext.entries)
              {'name': key, 'tokens': value, 'kind': 'used'},
            {'name': 'Messages', 'tokens': _conversationTokens, 'kind': 'used'},
            {'name': 'Autocompact buffer', 'tokens': 33000, 'kind': 'buffer'},
            {
              'name': 'Free space',
              'tokens': _limit - fixed - _conversationTokens - 33000,
              'kind': 'free',
            },
          ],
          'totalTokens': fixed + _conversationTokens,
          // Raw as well: the CLI reports the capped window as both.
          'maxTokens': _limit,
          'rawMaxTokens': _limit,
          'percentage': ((fixed + _conversationTokens) / 2000).round(),
        });
      case 'get_usage':
        final now = DateTime.now().toUtc();
        _respond(id, {
          'session': {'total_cost_usd': _cost},
          'subscription_type': 'max',
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {
              'utilization': 12,
              'resets_at': now.add(const Duration(hours: 3)).toIso8601String(),
            },
            'seven_day': {
              'utilization': 36,
              'resets_at': now.add(const Duration(days: 4)).toIso8601String(),
            },
            'model_scoped': [
              {
                'display_name': 'Opus',
                'utilization': 58,
                'resets_at': now.add(const Duration(days: 4)).toIso8601String(),
              },
            ],
          },
          'behaviors': null,
        });
      case 'file_suggestions':
        final query = '${request['query']}'.toLowerCase();
        _respond(id, {
          'suggestions': [
            for (final path in const [
              'lib/main.dart',
              'lib/chat/chat_screen.dart',
              'lib/chat/composer/composer.dart',
              'lib/chat/',
              'pubspec.yaml',
              'README.md',
            ])
              if (path.toLowerCase().contains(query)) {'path': path},
          ],
          'cwd': launch?.cwd,
        });
      case 'rewind_files':
        _respond(id, {'canRewind': true, 'filesChanged': <String>[]});
      case 'rewind_conversation':
        _respond(id, {'rewound': true});
      case 'cancel_async_message':
        _respond(id, {'cancelled': false});
      case 'mcp_status':
        _respond(id, {
          'mcpServers': [for (final name in _mcp.keys) _mcpServer(name)],
        });
      case 'mcp_toggle':
        final name = request['serverName'] as String;
        _mcp[name] = request['enabled'] == true ? 'connected' : 'disabled';
        _respond(id);
      case 'mcp_authenticate':
        _mcp[request['serverName'] as String] = 'connected';
        _respond(id, {
          'authUrl': 'https://example.com/oauth',
          'requiresUserAction': true,
          'callbackExpected': true,
        });
      case 'mcp_reconnect':
        _mcp[request['serverName'] as String] = 'connected';
        _respond(id);
      default:
        _respond(id);
    }
  }

  void _start(String uuid, String prompt, Map<String, Object?> message) {
    _emit({
      'type': 'system',
      'subtype': 'init',
      'cwd': launch?.cwd,
      'model': _resolvedModel,
      'effort': _effort,
      'permissionMode': _permissionMode,
      'terminal_slash_commands': ['doctor'],
    });
    _emit({...message, 'isReplay': true});
    _emit({
      'type': 'command_lifecycle',
      'command_uuid': uuid,
      'state': 'started',
    });
    _conversationTokens += 60 + prompt.length * 2;
    final run = Object();
    _run = run;
    unawaited(_script(run, prompt));
  }

  Future<bool> _wait(Object run, int milliseconds) async {
    await Future<void>.delayed(Duration(milliseconds: milliseconds));
    return identical(_run, run);
  }

  void _event(Map<String, Object?> event) => _emit({
    'type': 'stream_event',
    'event': event,
    'parent_tool_use_id': null,
  });

  void _assistant(String id, List<Map<String, Object?>> content) => _emit({
    'type': 'assistant',
    'message': {
      'id': id,
      'role': 'assistant',
      'model': 'claude-opus-5-5',
      'content': content,
    },
    'parent_tool_use_id': null,
  });

  String _messageStart() {
    final id = 'msg_${++_messages}';
    // As the CLI does before each request to the model.
    _emit({'type': 'system', 'subtype': 'status', 'status': 'requesting'});
    _event({
      'type': 'message_start',
      'message': {'id': id, 'role': 'assistant'},
    });
    return id;
  }

  Future<bool> _thinking(Object run, String text) async {
    final id = _messageStart();
    _event({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'thinking', 'thinking': ''},
    });
    if (!await _wait(run, MockScript.thinkingDelay)) return false;
    for (var start = 0; start < text.length;) {
      final end = (start + MockScript.thinkingChunk).clamp(0, text.length);
      _event({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {
          'type': 'thinking_delta',
          'thinking': text.substring(start, end),
        },
      });
      _conversationTokens += 2;
      start = end;
      if (!await _wait(run, MockScript.thinkingChunkMs)) return false;
    }
    _event({'type': 'content_block_stop', 'index': 0});
    _assistant(id, [
      {'type': 'thinking', 'thinking': text, 'signature': 'mock'},
    ]);
    return true;
  }

  Future<bool> _text(Object run, String text) async {
    final id = _messageStart();
    _event({
      'type': 'content_block_start',
      'index': 0,
      'content_block': {'type': 'text', 'text': ''},
    });
    for (var start = 0; start < text.length;) {
      final end = (start + MockScript.textChunk).clamp(0, text.length);
      _event({
        'type': 'content_block_delta',
        'index': 0,
        'delta': {'type': 'text_delta', 'text': text.substring(start, end)},
      });
      _conversationTokens += 2;
      start = end;
      if (!await _wait(run, MockScript.textChunkMs)) return false;
    }
    _event({'type': 'content_block_stop', 'index': 0});
    _assistant(id, [
      {'type': 'text', 'text': text},
    ]);
    return true;
  }

  /// A tool call and its result. [permission] tools first wait on
  /// `can_use_tool`, and return what the host answered (null when the run
  /// was stopped meanwhile).
  Future<Map<String, Object?>?> _tool(
    Object run,
    String name,
    Map<String, Object?> input, {
    String result = '',
    Object? structured,
    bool permission = false,
    bool error = false,
  }) async {
    final id = 'toolu_${++_tools}';
    _assistant('msg_${++_messages}', [
      {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
    ]);
    var answer = const <String, Object?>{'behavior': 'allow'};
    if (permission) {
      final requestId = 'perm_${++_requests}';
      final done = Completer<Map<String, Object?>>();
      _permissions[requestId] = done;
      _emit({
        'type': 'control_request',
        'request_id': requestId,
        'request': {
          'subtype': 'can_use_tool',
          'tool_name': name,
          'input': input,
          'tool_use_id': id,
          'requires_user_interaction': true,
        },
      });
      answer = await done.future;
      if (!identical(_run, run)) return null;
    }
    final denied = answer['behavior'] != 'allow';
    _emit({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': id,
            'content': denied ? answer['message'] : result,
            'is_error': denied || error,
          },
        ],
      },
      'parent_tool_use_id': null,
      'tool_use_result': ?structured,
    });
    _conversationTokens += 40 + result.length ~/ 2;
    return {...answer, 'tool_use_id': id};
  }

  void _result({bool error = false}) {
    _cost += 0.0421;
    final fixed = _fixedContext.values.fold(0, (sum, n) => sum + n);
    _emit({
      'type': 'result',
      'subtype': error ? 'error_during_execution' : 'success',
      'is_error': false,
      'total_cost_usd': _cost,
      'usage': {
        'input_tokens': 120,
        'cache_read_input_tokens': fixed + _conversationTokens - 120,
        'output_tokens': 480,
      },
      'modelUsage': {
        'claude-opus-5-5': {'contextWindow': _window},
      },
    });
    _emit({
      'type': 'rate_limit_event',
      'rate_limit_info': {
        'status': 'allowed',
        'unifiedWindows': {
          'five_hour': {'utilization': 0.12, 'resetsAt': 1790540400},
          'seven_day': {'utilization': 0.36, 'resetsAt': 1790845200},
        },
      },
    });
    if (!error) {
      _emit({'type': 'prompt_suggestion', 'suggestion': 'Run the tests'});
    }
  }

  Future<void> _script(Object run, String prompt) async {
    final target =
        RegExp(r'@(\S+)').firstMatch(prompt)?.group(1) ??
        'lib/chat/chat_screen.dart';
    if (!await _thinking(run, MockScript.thoughtFor(target))) return;
    if (!await _wait(run, 500)) return;
    await _tool(run, 'Read', {
      'file_path': target,
    }, result: '     1\timport \'package:flutter/material.dart\';\n…');
    if (!await _wait(run, 350)) return;
    await _tool(run, 'Grep', {
      'pattern': MockScript.searchPattern,
      'path': 'lib',
      'output_mode': 'content',
    }, result: MockScript.searchMatches.join('\n'));
    if (!await _wait(run, 400)) return;

    if (prompt.contains('in Ask mode') || _permissionMode == 'dontAsk') {
      // Told to only discuss, or nothing may change: it answers.
      if (!await _text(run, MockScript.discussion)) return;
      _finish(run);
      return;
    }
    if (_permissionMode == 'plan') {
      final verdict = await _tool(
        run,
        'ExitPlanMode',
        {'plan': MockScript.plan},
        result: 'User has approved your plan. You can now start coding.',
        permission: true,
      );
      if (verdict == null) return;
      if (verdict['behavior'] != 'allow') {
        if (!await _text(run, MockScript.keepPlanning)) return;
        _finish(run);
        return;
      }
      for (final rule in verdict['updatedPermissions'] as List? ?? const []) {
        if (rule is Map && rule['type'] == 'setMode') {
          _permissionMode = '${rule['mode']}';
          _emit({
            'type': 'system',
            'subtype': 'status',
            'status': null,
            'permissionMode': _permissionMode,
          });
        }
      }
    } else {
      if (!await _text(run, MockScript.beforeQuestion)) return;
      final questions = [
        for (final q in MockScript.questions)
          {
            'question': q.question,
            'header': q.header,
            'options': [
              for (final option in q.options)
                {'label': option, 'description': ''},
            ],
            'multiSelect': q.multiSelect,
          },
      ];
      final answered = await _tool(
        run,
        'AskUserQuestion',
        {'questions': questions},
        result: 'Your questions have been answered.',
        permission: true,
      );
      if (answered == null) return;
      final input = answered['updatedInput'] as Map? ?? const {};
      final answers = (input['answers'] as Map? ?? const {}).values.join('；');
      _assistant('msg_${++_messages}', [
        {
          'type': 'text',
          'text': answered['behavior'] == 'allow'
              ? '已收到：$answers'
              : '好的，按默认方案继续。',
        },
      ]);
    }

    if (!await _wait(run, 700)) return;
    for (final edit in MockScript.edits) {
      await _tool(
        run,
        'Edit',
        {
          'file_path': edit.path,
          'old_string': [
            for (final line in edit.lines)
              if (!line.startsWith('+')) line.substring(1),
          ].join('\n'),
          'new_string': [
            for (final line in edit.lines)
              if (!line.startsWith('-')) line.substring(1),
          ].join('\n'),
        },
        result: 'The file ${edit.path} has been updated successfully.',
        structured: {
          'filePath': edit.path,
          'structuredPatch': [
            {
              'oldStart': edit.start,
              'oldLines': edit.lines.where((l) => !l.startsWith('+')).length,
              'newStart': edit.start,
              'newLines': edit.lines.where((l) => !l.startsWith('-')).length,
              'lines': edit.lines,
            },
          ],
        },
      );
    }
    const taskId = 'bash_1';
    final bash = await _tool(
      run,
      'Bash',
      {
        'command': MockScript.testCommand,
        'description': 'Run the tests',
        'run_in_background': true,
      },
      result: 'Command running in background with ID: $taskId',
      structured: {'stdout': '', 'stderr': '', 'backgroundTaskId': taskId},
    );
    if (bash == null) return;
    final toolUseId = bash['tool_use_id'];
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': taskId,
      'tool_use_id': toolUseId,
      'description': MockScript.testCommand,
      'task_type': 'local_bash',
      'is_backgrounded': true,
    });
    if (!await _wait(run, 300)) return;
    if (!await _text(run, MockScript.summary)) return;
    _finish(run);

    // The background command outlives the turn.
    await Future<void>.delayed(
      const Duration(milliseconds: MockScript.testRunMs),
    );
    _emit({
      'type': 'system',
      'subtype': 'task_updated',
      'task_id': taskId,
      'patch': {'status': 'completed'},
    });
    _emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': taskId,
      'tool_use_id': toolUseId,
      'status': 'completed',
      'output_file': '/tmp/$taskId.output',
      'summary': MockScript.testOutput,
    });
  }

  void _finish(Object run) {
    if (!identical(_run, run)) return;
    _run = null;
    _result();
  }

  @override
  Future<void> get exited => _out.done;

  @override
  void close() {
    _run = null;
    _permissions.clear();
    if (_out.isClosed) return;
    _out
      ..add(ClaudeExit.message(0, ''))
      ..close();
  }
}
