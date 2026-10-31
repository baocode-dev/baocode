// A Claude Code CLI that answers each message with a script of the
// showcase's: the lines a real one prints (`stream_event` deltas,
// `assistant` and `user` messages, a subagent's with its
// `parent_tool_use_id`, `task_*` notices, `result`), at a pace that reads
// well. A script may stop at a hold ([ShowRun.hold]) for the scene to take
// its picture, and go on when told. Its pace is [ShowClock.dilation] times
// slower while a video is recorded, as the app's animations are.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/remote/remote_claude.dart';

/// The showcase's time: how much slower than the wall's it runs, while a
/// video is recorded frame by frame.
abstract final class ShowClock {
  static double dilation = 1;

  static Future<void> wait(Duration duration) => Future<void>.delayed(
    Duration(microseconds: (duration.inMicroseconds * dilation).round()),
  );
}

typedef ShowScript = Future<void> Function(ShowRun run);

/// What the agents answer: a script for each message, by its text (the
/// first line's start is enough), and the holds they stop at.
abstract final class ShowScripts {
  static final Map<String, ShowScript> _scripts = {};

  static void register(String prompt, ShowScript script) =>
      _scripts[_key(prompt)] = script;

  static void clear() {
    _scripts.clear();
    for (final hold in _holds.values) {
      if (!hold.released.isCompleted) hold.released.complete();
    }
    _holds.clear();
  }

  static String _key(String prompt) {
    final line = prompt.trim().split('\n').first;
    return line.length > 40 ? line.substring(0, 40) : line;
  }

  static ShowScript? _find(String prompt) => _scripts[_key(prompt)];

  static final Map<String, _Hold> _holds = {};

  static _Hold _hold(String name) => _holds[name] ??= _Hold();

  /// Done once a script has stopped at the hold [name].
  static Future<void> reached(String name) => _hold(name).reached.future;

  /// Lets the script stopped at [name] go on.
  static void release(String name) {
    final hold = _hold(name);
    if (!hold.released.isCompleted) hold.released.complete();
  }
}

class _Hold {
  final reached = Completer<void>();
  final released = Completer<void>();
}

/// The kernel the showcase's agents run on: Claude Code's adapter, as in
/// the app, over [ShowTransport]; the sessions kept in the showcase's
/// Claude Code folder listed and read as the app does.
final KernelDescriptor showClaudeCode = KernelDescriptor(
  id: 'claude-code',
  label: 'Claude Code',
  icon: Icons.auto_awesome_rounded,
  description: 'Anthropic’s coding agent',
  create: (context) => ClaudeCodeKernel(
    showClaudeCode,
    context,
    start: ShowTransport.start,
    readHistoryPage: readClaudeHistoryPage,
    readGoal: readClaudeGoal,
  ),
  catalog: const ClaudeCatalog(),
);

/// The models the showcase's Claude Code offers.
const showModels = [
  {
    'value': 'default',
    'resolvedModel': 'claude-opus-5-5',
    'displayName': 'Default',
    'description': 'Opus 5.5 · Best for everyday, complex tasks',
    'supportsEffort': true,
    'supportedEffortLevels': ['low', 'medium', 'high', 'xhigh', 'max'],
    'supportsAutoMode': true,
  },
  {
    'value': 'fable',
    'resolvedModel': 'claude-fable-5-1',
    'displayName': 'Fable',
    'description': 'Fable 5.1 · Most capable for your hardest work',
    'supportsEffort': true,
    'supportedEffortLevels': ['low', 'medium', 'high', 'xhigh', 'max'],
    'supportsAutoMode': true,
  },
  {
    'value': 'opus',
    'resolvedModel': 'claude-opus-5-5',
    'displayName': 'Opus',
    'description': 'Opus 5.5 · Best for everyday, complex tasks',
    'supportsEffort': true,
    'supportedEffortLevels': ['low', 'medium', 'high', 'xhigh', 'max'],
    'supportsAutoMode': true,
  },
  {
    'value': 'sonnet',
    'resolvedModel': 'claude-sonnet-5-5',
    'displayName': 'Sonnet',
    'description': 'Sonnet 5.5 · Efficient for routine tasks',
    'supportsEffort': true,
    'supportedEffortLevels': ['low', 'medium', 'high'],
  },
  {
    'value': 'haiku',
    'resolvedModel': 'claude-haiku-5-5',
    'displayName': 'Haiku',
    'description': 'Haiku 5.5 · Fastest for quick answers',
  },
];

/// Answers each message with its [ShowScripts] script; the control
/// requests as [MockClaudeCodeTransport] does, but for the models.
class ShowTransport implements ClaudeCodeTransport {
  ShowTransport(this._launch) : _control = MockClaudeCodeTransport(_launch) {
    _control.messages.listen(_fromControl, onDone: _out.close);
  }

  static Future<ClaudeCodeTransport> start(ClaudeLaunch launch) async =>
      ShowTransport(launch);

  final ClaudeLaunch _launch;
  final MockClaudeCodeTransport _control;
  late final String _sessionId = _launch.resume ?? _newId();
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();
  ShowRun? _run;
  double _cost = 0;

  static final _random = Random(7);

  static String _newId() {
    String hex(int n) =>
        [for (var i = 0; i < n; i++) _random.nextInt(16).toRadixString(16)]
            .join();
    return '${hex(8)}-${hex(4)}-4${hex(3)}-a${hex(3)}-${hex(12)}';
  }

  @override
  Stream<Map<String, Object?>> get messages => _out.stream;

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) _out.add({...message, 'session_id': _sessionId});
  }

  void _fromControl(Map<String, Object?> message) {
    // Its models are the showcase's.
    if (message['type'] == 'control_response') {
      final response = (message['response'] as Map).cast<String, Object?>();
      final payload = response['response'];
      if (payload is Map && payload['models'] != null) {
        _emit({
          ...message,
          'response': {
            ...response,
            'response': {...payload, 'models': showModels},
          },
        });
        return;
      }
    }
    // Its own runs' messages are not the showcase's.
    if (message['type'] == 'control_response' ||
        message['type'] == 'control_request') {
      _emit(message);
    }
  }

  /// The goal set with `/goal`, as the CLI's Stop hook has it.
  String? _goal;

  @override
  void write(Map<String, Object?> message) {
    switch (message['type']) {
      // One sent while a turn runs waits for it to end, as in the CLI.
      case 'user' when _run != null:
        _queued.add(message);
      case 'user':
        _start(message);
      case 'control_request' when _isHooksListing(message):
        _emit({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': message['request_id'],
            'response': {
              'hooks': [
                if (_goal case final goal?)
                  {
                    'event': 'Stop',
                    'source': 'sessionHook',
                    'type': 'prompt',
                    'commandText': goal,
                  },
              ],
            },
          },
        });
      case 'control_request' when _isInterrupt(message):
        _run?._stopped = true;
        _run = null;
        _result(error: true);
        _control.write(message);
      default:
        _control.write(message);
    }
  }

  static bool _isHooksListing(Map<String, Object?> message) =>
      (message['request'] as Map?)?['subtype'] == 'get_hooks_listing';

  /// Sets the goal [condition], as `/goal` does: the Stop hook, and the
  /// line the session's file keeps of it.
  void _setGoal(String condition) {
    _goal = condition;
    final config =
        Platform.environment['BAOCODE_SHOWCASE_HOME'] ??
        Platform.environment['HOME']!;
    final file = File(
      '$config/.claude/projects/'
      '${_launch.cwd.replaceAll(RegExp('[^a-zA-Z0-9]'), '-')}/$_sessionId.jsonl',
    )..parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${jsonEncode({
        'type': 'attachment',
        'attachment': {'type': 'goal_status', 'condition': condition, 'sentinel': true, 'met': false},
        'timestamp': DateTime.now().subtract(const Duration(minutes: 7, seconds: 12)).toUtc().toIso8601String(),
        'sessionId': _sessionId,
        'cwd': _launch.cwd,
      })}\n',
      mode: FileMode.append,
    );
    _emit({
      'type': 'system',
      'subtype': 'session_state_changed',
      'state': 'idle',
    });
  }

  static bool _isInterrupt(Map<String, Object?> message) =>
      (message['request'] as Map?)?['subtype'] == 'interrupt';

  final _queued = <Map<String, Object?>>[];

  void _start(Map<String, Object?> message) {
    final content = (message['message'] as Map)['content'];
    final prompt = content is String
        ? content
        : (content as List)
              .cast<Map<Object?, Object?>>()
              .where((block) => block['type'] == 'text')
              .map((block) => block['text'])
              .join('\n');
    final uuid = message['uuid'] as String? ?? _newId();
    _emit({
      'type': 'system',
      'subtype': 'init',
      'cwd': _launch.cwd,
      'model': 'claude-opus-5-5',
      'effort': 'high',
      'permissionMode': _launch.permissionMode ?? 'default',
    });
    _emit({...message, 'isReplay': true});
    _emit({
      'type': 'command_lifecycle',
      'command_uuid': uuid,
      'state': 'started',
    });
    if (prompt.trim().startsWith('/goal ')) {
      _setGoal(prompt.trim().substring('/goal '.length).trim());
    }
    final run = _run = ShowRun._(this);
    final script =
        ShowScripts._find(prompt) ??
        (run) => run.say('OK.', charsPerSecond: double.infinity);
    unawaited(() async {
      try {
        await script(run);
      } on _Stopped {
        return;
      }
      if (!identical(_run, run)) return;
      _run = null;
      _result();
      if (_queued.isNotEmpty) _start(_queued.removeAt(0));
    }());
  }

  void _result({bool error = false}) {
    _cost += 0.0832;
    _emit({
      'type': 'result',
      'subtype': error ? 'error_during_execution' : 'success',
      'is_error': false,
      'total_cost_usd': _cost,
      'duration_ms': 48200,
      'usage': {
        'input_tokens': 120,
        'cache_read_input_tokens': 48000,
        'output_tokens': 2480,
      },
      'modelUsage': {
        'claude-opus-5-5': {'contextWindow': 1000000},
      },
    });
  }

  @override
  Future<void> get exited => _out.done;

  @override
  void close() {
    _run?._stopped = true;
    _run = null;
    _control.close();
  }
}

class _Stopped implements Exception {}

/// A script's way of answering: thoughts and text streamed, tools called
/// and answered, subagents and background tasks started and ended.
class ShowRun {
  ShowRun._(this._transport);

  final ShowTransport _transport;
  bool _stopped = false;
  int _messages = 0;
  int _tools = 0;

  late final String _key = ShowTransport._newId().substring(0, 8);

  void _emit(Map<String, Object?> message) {
    if (_stopped) throw _Stopped();
    _transport._emit(message);
  }

  Future<void> pause(int milliseconds) async {
    await ShowClock.wait(Duration(milliseconds: milliseconds));
    if (_stopped) throw _Stopped();
  }

  /// Stops until the scene releases [name] (see [ShowScripts.release]).
  Future<void> hold(String name) async {
    final hold = ShowScripts._hold(name);
    if (!hold.reached.isCompleted) hold.reached.complete();
    await hold.released.future;
    if (_stopped) throw _Stopped();
  }

  static const _usage = {
    'input_tokens': 3,
    'cache_read_input_tokens': 42000,
    'cache_creation_input_tokens': 900,
    'output_tokens': 180,
  };

  Map<String, Object?> _assistant(
    String id,
    List<Object?> content, {
    String? parent,
    String model = 'claude-opus-5-5',
  }) => {
    'type': 'assistant',
    'message': {
      'id': id,
      'role': 'assistant',
      'model': model,
      'content': content,
      'usage': _usage,
    },
    'parent_tool_use_id': parent,
  };

  Map<String, Object?> _event(Map<String, Object?> event) => {
    'type': 'stream_event',
    'event': event,
    'parent_tool_use_id': null,
  };

  /// Streams [text] as a thought ([thinking]) or as text, at
  /// [charsPerSecond]; a subagent's ([parent]) comes whole, as the CLI
  /// sends those.
  Future<void> _stream(
    String text, {
    required bool thinking,
    String? parent,
    double charsPerSecond = 260,
    int chunk = 5,
    (String, int)? holdAt,
  }) async {
    final id = 'msg_${_key}_${++_messages}';
    final block = thinking
        ? {'type': 'thinking', 'thinking': text, 'signature': 'show'}
        : {'type': 'text', 'text': text};
    if (parent != null) {
      await pause((text.length / charsPerSecond * 1000).round());
      _emit(_assistant(id, [block], parent: parent));
      return;
    }
    _emit({'type': 'system', 'subtype': 'status', 'status': 'requesting'});
    _emit(
      _event({
        'type': 'message_start',
        'message': {'id': id, 'role': 'assistant'},
      }),
    );
    _emit(
      _event({
        'type': 'content_block_start',
        'index': 0,
        'content_block': thinking
            ? {'type': 'thinking', 'thinking': ''}
            : {'type': 'text', 'text': ''},
      }),
    );
    if (charsPerSecond.isInfinite) chunk = text.length;
    final interval = charsPerSecond.isInfinite
        ? 0
        : (chunk / charsPerSecond * 1000).round();
    for (var start = 0; start < text.length;) {
      var end = min(start + chunk, text.length);
      if (end < text.length &&
          text.codeUnitAt(end - 1) >= 0xD800 &&
          text.codeUnitAt(end - 1) <= 0xDBFF) {
        end++;
      }
      _emit(
        _event({
          'type': 'content_block_delta',
          'index': 0,
          'delta': thinking
              ? {
                  'type': 'thinking_delta',
                  'thinking': text.substring(start, end),
                }
              : {'type': 'text_delta', 'text': text.substring(start, end)},
        }),
      );
      start = end;
      if (holdAt case (final name, final at) when start >= at) {
        holdAt = null;
        await hold(name);
      }
      if (interval > 0) await pause(interval);
    }
    _emit(_event({'type': 'content_block_stop', 'index': 0}));
    _emit(_assistant(id, [block]));
  }

  Future<void> think(
    String text, {
    String? parent,
    double charsPerSecond = 600,
  }) => _stream(
    text,
    thinking: true,
    parent: parent,
    charsPerSecond: charsPerSecond,
    chunk: 12,
  );

  /// Says [text]; stopped at the hold [holdAt]'s name once its count of
  /// characters is out.
  Future<void> say(
    String text, {
    String? parent,
    double charsPerSecond = 260,
    int chunk = 5,
    (String, int)? holdAt,
  }) => _stream(
    text,
    thinking: false,
    parent: parent,
    charsPerSecond: charsPerSecond,
    chunk: chunk,
    holdAt: holdAt,
  );

  /// Calls [name] with [input]; answered by [end] (see [tool]).
  String call(
    String name,
    Map<String, Object?> input, {
    String? parent,
    String model = 'claude-opus-5-5',
  }) {
    final id = 'toolu_${_key}_${++_tools}';
    _emit(
      _assistant(
        'msg_${_key}_${++_messages}',
        [
          {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
        ],
        parent: parent,
        model: model,
      ),
    );
    return id;
  }

  /// Answers the call [id] with [result].
  void end(
    String id, {
    String result = '',
    Object? structured,
    String? parent,
    bool error = false,
  }) => _emit({
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': id,
          'content': result,
          'is_error': error,
        },
      ],
    },
    'parent_tool_use_id': parent,
    'tool_use_result': ?structured,
  });

  /// A call answered [took] milliseconds later; [effect] done just
  /// before, as the tool does it (a file written).
  Future<String> tool(
    String name,
    Map<String, Object?> input, {
    String result = '',
    Object? structured,
    String? parent,
    int took = 300,
    void Function()? effect,
  }) async {
    final id = call(name, input, parent: parent);
    await pause(took);
    effect?.call();
    end(id, result: result, structured: structured, parent: parent);
    return id;
  }

  /// Reads [path], [lines] lines of [text] numbered as the Read tool does.
  Future<String> read(
    String path,
    String text, {
    String? parent,
    int took = 250,
  }) => tool(
    'Read',
    {'file_path': path},
    result: [
      for (final (i, line) in text.split('\n').indexed)
        '${'${i + 1}'.padLeft(6)}\t$line',
    ].join('\n'),
    parent: parent,
    took: took,
  );

  /// An edit of [path] from [before] to [after], at line [start], with
  /// its patch as the CLI sends it.
  Future<String> edit(
    String path,
    String before,
    String after, {
    int start = 1,
    String? parent,
    int took = 350,
  }) {
    final old = before.isEmpty ? <String>[] : before.split('\n');
    final updated = after.split('\n');
    // The lines both keep are context, as in the CLI's: a line diff, by
    // the longest run of lines in common.
    final kept = List.generate(
      old.length + 1,
      (_) => List.filled(updated.length + 1, 0),
    );
    for (var i = old.length - 1; i >= 0; i--) {
      for (var j = updated.length - 1; j >= 0; j--) {
        kept[i][j] = old[i] == updated[j]
            ? kept[i + 1][j + 1] + 1
            : max(kept[i + 1][j], kept[i][j + 1]);
      }
    }
    final lines = <String>[];
    var i = 0, j = 0;
    while (i < old.length || j < updated.length) {
      if (i < old.length && j < updated.length && old[i] == updated[j]) {
        lines.add(' ${old[i++]}');
        j++;
      } else if (j == updated.length ||
          i < old.length && kept[i + 1][j] >= kept[i][j + 1]) {
        lines.add('-${old[i++]}');
      } else {
        lines.add('+${updated[j++]}');
      }
    }
    return tool(
      'Edit',
      {'file_path': path, 'old_string': before, 'new_string': after},
      result: 'The file $path has been updated successfully.',
      structured: {
        'filePath': path,
        'structuredPatch': [
          {
            'oldStart': start,
            'oldLines': old.length,
            'newStart': start,
            'newLines': updated.length,
            'lines': lines,
          },
        ],
      },
      parent: parent,
      took: took,
      effect: () {
        final file = File(path);
        if (file.existsSync()) {
          file.writeAsStringSync(
            file.readAsStringSync().replaceFirst(before, after),
          );
        }
      },
    );
  }

  /// A new file, [path], of [text].
  Future<String> write(
    String path,
    String text, {
    String? parent,
    int took = 350,
  }) => tool(
    'Write',
    {'file_path': path, 'content': text},
    result: 'File created successfully at: $path',
    structured: {
      'type': 'create',
      'filePath': path,
      'content': text,
      'structuredPatch': [
        {
          'oldStart': 0,
          'oldLines': 0,
          'newStart': 1,
          'newLines': text.split('\n').length,
          'lines': [for (final l in text.split('\n')) '+$l'],
        },
      ],
    },
    parent: parent,
    took: took,
    effect: () => File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text),
  );

  /// Starts a subagent: its card, at work until [agentDone].
  ShowAgent agent(
    String description,
    String prompt, {
    String type = 'general-purpose',
    bool background = false,
    String model = 'claude-sonnet-5-5',
  }) {
    final id = call('Agent', {
      'description': description,
      'prompt': prompt,
      'subagent_type': type,
      if (background) 'run_in_background': true,
    });
    final task = 'a${_key}_$_tools';
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': task,
      'tool_use_id': id,
      'description': description,
      'task_type': 'local_agent',
      'is_backgrounded': background,
    });
    return ShowAgent._(this, id, task, description, model);
  }

  /// Runs [command] in the background: its task, at work until
  /// [ShowTask.done].
  Future<ShowTask> background(String command, String description) async {
    final task = 'b${_key}_${_tools + 1}';
    final id = await tool(
      'Bash',
      {
        'command': command,
        'description': description,
        'run_in_background': true,
      },
      result:
          'Command running in background with ID: $task. '
          'Output is being written to: /tmp/$task.output.',
      structured: {'stdout': '', 'stderr': '', 'backgroundTaskId': task},
      took: 120,
    );
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': task,
      'tool_use_id': id,
      'description': command,
      'task_type': 'local_bash',
      'is_backgrounded': true,
    });
    return ShowTask._(this, id, task);
  }

  /// A raw line of the CLI's.
  void raw(Map<String, Object?> message) => _emit(message);
}

/// A subagent at work: its messages under its card.
class ShowAgent {
  ShowAgent._(this._run, this.id, this.task, this.description, this.model);

  final ShowRun _run;
  final String id;
  final String task;
  final String description;
  final String model;
  int _toolUses = 0;
  int _tokens = 1800;

  /// What it does next, in its card and the task list.
  void progress(String activity, {String? lastTool}) {
    _run._emit({
      'type': 'system',
      'subtype': 'task_progress',
      'task_id': task,
      'tool_use_id': id,
      'description': activity,
      'last_tool_name': ?lastTool,
      'usage': {'total_tokens': _tokens, 'tool_uses': _toolUses},
    });
  }

  Future<void> say(String text) => _run.say(text, parent: id);

  Future<void> tool(
    String name,
    Map<String, Object?> input, {
    String result = '',
    String? activity,
    int took = 400,
  }) async {
    _toolUses++;
    _tokens += 900 + result.length ~/ 3;
    progress(activity ?? description, lastTool: name);
    final call = _run.call(name, input, parent: id, model: model);
    await _run.pause(took);
    _run.end(call, result: result, parent: id);
  }

  /// Ends it with [report], what it tells the agent.
  void done(String report, {int durationMs = 41000}) {
    _run.end(
      id,
      result: report,
      structured: {
        'status': 'completed',
        'agentId': task,
        'content': [
          {'type': 'text', 'text': report},
        ],
        'totalDurationMs': durationMs,
        'totalTokens': _tokens,
        'totalToolUseCount': _toolUses,
        'resolvedModel': model,
      },
    );
    _run._emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': task,
      'tool_use_id': id,
      'status': 'completed',
      'summary': description,
      'usage': {'total_tokens': _tokens, 'tool_uses': _toolUses},
    });
  }
}

/// A command at work in the background.
class ShowTask {
  ShowTask._(this._run, this.id, this.task);

  final ShowRun _run;
  final String id;
  final String task;

  void done(String summary, {bool failed = false}) {
    _run._emit({
      'type': 'system',
      'subtype': 'task_updated',
      'task_id': task,
      'patch': {'status': failed ? 'failed' : 'completed'},
    });
    _run._emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': task,
      'tool_use_id': id,
      'status': failed ? 'failed' : 'completed',
      'output_file': '/tmp/$task.output',
      'summary': summary,
    });
  }
}
