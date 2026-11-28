import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_agent/bao_agent.dart'
    show AgentPaths, ForeignBrief, SessionStore, newUuid;
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:path/path.dart' as p;

import '../claude/claude_environment.dart';
import '../claude/claude_unavailable.dart';
import 'acp_connection.dart';
import 'acp_to_claude.dart';
import 'agy_context.dart';
import 'agy_runtime.dart';
import 'control_channel.dart';
import 'handoff.dart';
import 'mcp_endpoint.dart';
import 'mcp_http_server.dart';
import 'swarm_model.dart';
import 'swarm_watcher.dart';

/// Pure-Dart options to launch an Antigravity ACP session via
/// [AgyTransportCore], shared between the desktop app and `baocode-server`.
class AgyLaunchOptions {
  const AgyLaunchOptions({
    required this.cwd,
    this.resume,
    this.model,
    this.permissionMode,
    this.effort,
    this.autocompact,
    this.persist = true,
    this.directories = const [],
    this.folderInstructions = true,
    this.instructions,
    this.sdkServers = const [],
    this.flagSettings = const {},
    this.baseEnvironment,
    this.brainDir,
    this.appendedSystemPrompt,
  });

  factory AgyLaunchOptions.fromJson(Map<String, Object?> json) =>
      AgyLaunchOptions(
        cwd: json['cwd'] as String,
        resume: json['resume'] as String?,
        model: json['model'] as String?,
        permissionMode: json['permissionMode'] as String?,
        effort: json['effort'] as String?,
        autocompact: (json['autocompact'] as num?)?.toInt(),
        persist: json['persist'] as bool? ?? true,
        directories: [
          for (final d in json['directories'] as List? ?? const []) '$d',
        ],
        folderInstructions: json['folderInstructions'] as bool? ?? true,
        instructions: json['instructions'] as String?,
        sdkServers: [
          for (final s in json['sdkServers'] as List? ?? const []) '$s',
        ],
        flagSettings: switch (json['flagSettings']) {
          final Map<Object?, Object?> m => m.cast<String, Object?>(),
          _ => const {},
        },
        baseEnvironment: switch (json['baseEnvironment']) {
          final Map<Object?, Object?> m => {
            for (final entry in m.entries) '${entry.key}': '${entry.value}',
          },
          _ => null,
        },
        brainDir: json['brainDir'] as String?,
        appendedSystemPrompt: json['appendedSystemPrompt'] as String?,
      );

  final String cwd;
  final String? resume;
  final String? model;
  final String? permissionMode;
  final String? effort;
  final int? autocompact;
  final bool persist;
  final List<String> directories;
  final bool folderInstructions;
  final String? instructions;
  final List<String> sdkServers;
  final Map<String, Object?> flagSettings;
  final Map<String, String>? baseEnvironment;
  final String? brainDir;
  final String? appendedSystemPrompt;

  Map<String, Object?> toJson() => {
    'cwd': cwd,
    if (resume != null) 'resume': resume,
    if (model != null) 'model': model,
    if (permissionMode != null) 'permissionMode': permissionMode,
    if (effort != null) 'effort': effort,
    if (autocompact != null) 'autocompact': autocompact,
    'persist': persist,
    if (directories.isNotEmpty) 'directories': directories,
    'folderInstructions': folderInstructions,
    if (instructions != null) 'instructions': instructions,
    if (sdkServers.isNotEmpty) 'sdkServers': sdkServers,
    if (flagSettings.isNotEmpty) 'flagSettings': flagSettings,
    if (baseEnvironment != null) 'baseEnvironment': baseEnvironment,
    if (brainDir != null) 'brainDir': brainDir,
    if (appendedSystemPrompt != null)
      'appendedSystemPrompt': appendedSystemPrompt,
  };

  /// Default BaoCode chat formatting/citation prompt appended when
  /// [appendedSystemPrompt] is omitted.
  static const defaultAppendedSystemPrompt =
      '$_citingCode\n\n$_fileLinks\n\n$_formatting';

  static const _citingCode = '''
<citing_code>
You MUST use the following format when citing code regions or blocks:

```12:15:app/components/Todo.tsx
// ... existing code ...
```

This is the ONLY acceptable format for code citations. The format is ```startLine:endLine:filepath where startLine and endLine are line numbers.
</citing_code>''';

  static const _fileLinks = '''
<file_links>
When you mention a specific file or folder in your reply (one you read, changed, created or point the user to), write it as a markdown link so the user can open it with a click:

[display name](/absolute/path/to/file#L42)

- The target is always the file's full absolute path, wherever the file is and whatever folder your shell is in. Never a relative path (not lib/a.dart, ./a.dart or ../a.dart), never ~/, file://, vscode://, http:// or https:// for local files.
- On Windows the path starts with its drive, no slash before it: [Program.cs](C:/Users/me/app/Program.cs#L12).
- That path is the one on the machine your tools run on. For a file on another machine you reach from there over SSH (with ssh, scp or rsync), write ssh://<host>/<its absolute path there>, the host as you reached it: [app.log](ssh://devbox/var/log/app.log#L120).
- Add a line with #L42, or a range with #L42-L58; not :42 in the target.
- If the path contains spaces, wrap the target in angle brackets: [notes.md](</Users/me/My Project/docs/notes.md#L3>).
- The display name is usually the file name, optionally with the line: [chat_screen.dart:42](/Users/me/app/lib/chat/chat_screen.dart#L42).
- Link only paths you have seen exist, spelled exactly; do not guess or shorten them.
- Write each path as a link, not as bare text or in backticks; links do not work inside inline code or code blocks, which keep the format of <citing_code>.
</file_links>''';

  static const _formatting = r'''
<formatting>
The chat renders GitHub-flavored Markdown, and also:
- Math (TeX): inline $E=mc^2$ or \(...\); display $$...$$ or \[...\] on lines of their own. Not in a ```math fence, which shows as code.
- Mermaid: a ```mermaid block is drawn as a diagram (flowchart, sequence, class, state, ER, gantt, pie, mindmap, timeline, gitGraph…). Prefer flowchart LR to TD: the chat is wider than it is tall. Keep it under about 100 nodes and 200 lines, and quote labels with symbols: A["load (cached)"]; a larger or invalid one shows as its source.
- Images: ![alt](path/to/shot.png) shows a local image inline. If the path contains spaces, wrap it in angle brackets: ![alt](</Users/me/My Project/shot.png>).
- Folding: <details><summary>Title</summary> … </details>, the tags on lines of their own, folds long logs or output away.
Use them where they make the answer clearer (a diagram for a flow or a structure, math for a formula), not as decoration. Other HTML shows as text.
</formatting>''';
}

/// Pure-Dart Antigravity ACP session transport: translates between Claude
/// Code's stream-json protocol and `agy acp` (JSON-RPC 2.0 over stdio),
/// persisting conversations in Claude Code's jsonl layout, serving SDK MCP
/// tools over loopback HTTP, and watching native Swarm and subagent
/// transcripts.
class AgyTransportCore {
  AgyTransportCore._(
    this.options,
    this._runtime,
    this._store,
    this._environment, {
    String? brainDir,
  }) : _brainDir = brainDir ?? options.brainDir {
    _mode = options.permissionMode ?? 'default';
    _model = options.model;
    _effort = options.effort;
    _sdkServers = [...options.sdkServers];
    if (_syncLine case final line?) {
      _agySession = line.session;
      _synced = line.synced;
      _handedOff = line.handedOff;
      _used = line.used;
      _size = line.size;
    }
    _running[_store.sessionId] = this;
  }

  /// Those open, by the conversation's session id.
  static final Map<String, AgyTransportCore> _running = {};

  /// Deletes what agy keeps of the conversation [sessionId] (Claude Code's
  /// session, kept under [configDir]), its process ended first: each
  /// session of agy's its file notes. The file itself is left to delete.
  static Future<void> forget(
    String sessionId,
    String configDir, {
    required AgyRuntime runtime,
  }) async {
    await _running[sessionId]?._end();
    final ids = <String>{};
    final projects = Directory('$configDir/projects');
    if (projects.existsSync()) {
      for (final project in projects.listSync().whereType<Directory>()) {
        final file = File('${project.path}/$sessionId.jsonl');
        if (!file.existsSync()) continue;
        for (final line in await file.readAsLines()) {
          if (!line.contains('"$syncType"')) continue;
          try {
            if (jsonDecode(line) case {
              'type': syncType,
              'agySessionId': final String id,
            }) {
              ids.add(id);
            }
          } on FormatException {
            // Cut short: no id in it.
          }
        }
      }
    }
    for (final id in ids) {
      await runtime.deleteSession(id);
    }
  }

  /// Closes it, and waits a while for agy to be gone: its files are let
  /// go of then.
  Future<void> _end() async {
    final gone = _connection?.exited;
    close();
    try {
      await gone?.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Deleted all the same: what it holds goes once it ends.
    }
  }

  final AgyLaunchOptions options;
  final AgyRuntime _runtime;
  final SessionStore _store;
  final Map<String, String> _environment;
  final String? _brainDir;
  SwarmWatcher? _swarmWatcher;
  SwarmSnapshot? _swarm;

  String get sessionId => _store.sessionId;

  static Future<AgyTransportCore> start(
    AgyLaunchOptions options, {
    required AgyRuntime runtime,
    String? brainDir,
  }) async {
    if (!Directory(options.cwd).existsSync()) {
      throw ClaudeFolderGone(options.cwd);
    }
    if (await runtime.version() == null) {
      throw const ClaudeUnavailable(
        'Antigravity is not installed',
        detail: 'Install it in Settings → Models → Antigravity.',
      );
    }
    final base = options.baseEnvironment ?? await ClaudeEnvironment.of();
    final environment = {...base, ...ClaudeEnvironment.stateDirectory(base)};
    final id = options.resume ?? newUuid();
    final file = AgentPaths.from(environment).sessionFile(options.cwd, id);
    final store = options.resume != null && File(file).existsSync()
        ? SessionStore.resume(
            sessionId: id,
            cwd: options.cwd,
            file: file,
            persist: options.persist,
          )
        : SessionStore(
            sessionId: id,
            cwd: options.cwd,
            file: options.persist ? file : null,
          );
    // Booted while the user writes, for the first message to go at once.
    runtime.warm();
    return AgyTransportCore._(
      options,
      runtime,
      store,
      environment,
      brainDir: brainDir,
    );
  }

  /// What the kernel reads: asynchronous, as a process's output is.
  final StreamController<Map<String, Object?>> _out =
      StreamController.broadcast();

  Stream<Map<String, Object?>> get messages => _out.stream;

  Future<void> get exited => _out.done;

  void _emit(Map<String, Object?> message) {
    if (!_out.isClosed) {
      _out.add({...message, 'session_id': _store.sessionId});
    }
  }

  /// What this asks the kernel: tools' approvals, the edit watch's hooks,
  /// the app's MCP servers.
  late final ControlChannel _kernel = ControlChannel(_emit);

  late String _mode;
  String? _model;
  String? _effort;
  List<String> _sdkServers = const [];

  /// The hooks the kernel has called back (`initialize`'s), by event.
  Map<String, Object?> _hooks = const {};

  // --- What the kernel says ------------------------------------------------------

  void write(Map<String, Object?> message) {
    if (_closed) return;
    switch (message['type']) {
      case 'control_request':
        unawaited(
          _control(
            message['request_id'] as String,
            (message['request'] as Map).cast<String, Object?>(),
          ),
        );
      case 'control_response':
        _kernel.receive(message);
      case 'user':
        if (_steer(message)) return;
        _queue.add(message);
        _next();
    }
  }

  void _respond(String id, [Map<String, Object?> payload = const {}]) => _emit({
    'type': 'control_response',
    'response': {'subtype': 'success', 'request_id': id, 'response': payload},
  });

  void _refuse(String id, String error) => _emit({
    'type': 'control_response',
    'response': {'subtype': 'error', 'request_id': id, 'error': error},
  });

  Future<void> _control(String id, Map<String, Object?> request) async {
    switch (request['subtype']) {
      case 'initialize':
        _hooks = (request['hooks'] as Map? ?? const {}).cast<String, Object?>();
        if (request['sdkMcpServers'] case final List<Object?> servers) {
          _sdkServers = [for (final name in servers) '$name'];
        }
        _respond(id, {
          'commands': _commandList,
          'models': const [],
          'current_permission_mode': _mode,
        });
        _watchSwarm();
      case 'set_model':
        _model = switch (request['model']) {
          final String model when model.isNotEmpty && model != 'default' =>
            model,
          _ => _model,
        };
        _respond(id);
        unawaited(_applyOption('model', _model));
      case 'apply_flag_settings':
        final settings = request['settings'] as Map? ?? const {};
        if (settings['effortLevel'] case final String effort) {
          _effort = effort;
          unawaited(_applyOption('thought_level', _effort));
        }
        _respond(id);
      case 'get_settings':
        _respond(id, {
          'applied': {'model': _model, 'effort': _effort},
        });
      case 'set_permission_mode':
        _mode = request['mode'] as String? ?? _mode;
        _respond(id, {'mode': _mode});
      case 'interrupt':
        _respond(id);
        _interrupt();
      case 'stop_task':
        final taskId = '${request['task_id'] ?? ''}';
        if (taskId.startsWith('swarm-worker:')) {
          final name = taskId.substring('swarm-worker:'.length);
          final stopped = _stopSwarmWorker(name);
          _respond(id, {'stopped': stopped});
        } else if (_subagentConvIds[taskId] case final convId?) {
          _connection?.notify('session/cancel', {'sessionId': convId});
          _subagentWatches[taskId]?.markStopped();
          _settleSubagentTask(taskId, status: 'stopped');
          _respond(id, {'stopped': true});
        } else {
          _respond(id, {'stopped': false});
        }
      case 'rename_session':
        final title = '${request['title'] ?? ''}'.trim();
        if (title.isEmpty) {
          _refuse(id, 'A title is required');
          return;
        }
        _store.note({'type': 'custom-title', 'customTitle': title});
        _respond(id);
        _emit({
          'type': 'system',
          'subtype': 'session_title_changed',
          'title': title,
        });
      case 'get_context_usage':
        _respond(id, _contextUsage());
      case 'rewind_conversation':
        _respond(id, await _rewind(request));
      case 'mcp_status':
        _respond(id, {'mcpServers': const []});
      case 'cancel_async_message':
        final uuid = request['message_uuid'];
        final queued = _queue.indexWhere((m) => m['uuid'] == uuid);
        if (queued >= 0) {
          _queue.removeAt(queued);
          _emit({
            'type': 'command_lifecycle',
            'command_uuid': uuid,
            'state': 'cancelled',
          });
        }
        _respond(id, {'cancelled': queued >= 0});
      default:
        _refuse(id, 'Not supported on Antigravity');
    }
  }

  // --- Turns -----------------------------------------------------------------------

  /// Messages waiting for the turn running to end (as the user would have
  /// them, or the turn not yet prompted; see [_steer]).
  final List<Map<String, Object?>> _queue = [];
  _Turn? _turn;

  void _next() {
    if (_turn != null || _queue.isEmpty || _closed) return;
    unawaited(_run(_queue.removeAt(0)));
  }

  static List<Map<String, Object?>> _contentOf(Map<String, Object?> message) =>
      ((message['message'] as Map?)?['content'] as List? ?? [])
          .whereType<Map<Object?, Object?>>()
          .map((block) => block.cast<String, Object?>())
          .toList();

  /// The user's message [uuid] kept, and told as taken up.
  void _takeUp(String uuid, List<Map<String, Object?>> content) {
    final entry = _store.append({
      'type': 'user',
      'message': {'role': 'user', 'content': content},
      'uuid': uuid,
    });
    _emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': null,
      'uuid': uuid,
      'isReplay': true,
      'timestamp': entry['timestamp'],
    });
    _emit({
      'type': 'command_lifecycle',
      'command_uuid': uuid,
      'state': 'started',
    });
  }

  /// Folds [message] into the turn running, where the user would have it
  /// so (`priority` next or now, as the CLI folds one in between its tool
  /// calls): agy takes a prompt sent mid-turn in, ending the one before at
  /// once, the turn going on in the new one's. Not while a question or an
  /// approval waits on the user.
  bool _steer(Map<String, Object?> message) {
    final turn = _turn;
    final connection = _connection;
    final session = _agySession;
    if (message['priority'] case 'next' || 'now') {
    } else {
      return false;
    }
    if (turn == null ||
        turn.cancelled ||
        turn.prompt == null ||
        !_open ||
        connection == null ||
        session == null ||
        _asked.isNotEmpty) {
      return false;
    }
    final uuid = message['uuid'] as String? ?? newUuid();
    final content = _contentOf(message);
    _closeOpen();
    _takeUp(uuid, content);
    turn
      ..begun = DateTime.now()
      ..prompt = connection.request('session/prompt', {
        'sessionId': session,
        'prompt': _acpPrompt(content),
      });
    return true;
  }

  Future<void> _run(Map<String, Object?> message) async {
    final uuid = message['uuid'] as String? ?? newUuid();
    final turn = _turn = _Turn(uuid);
    _idleTimer?.cancel();
    final content = _contentOf(message);
    _emit({
      'type': 'system',
      'subtype': 'init',
      'cwd': options.cwd,
      'model': _model,
      'effort': _effort,
      'permissionMode': _mode,
      'tools': const <String>[],
    });
    _emit({
      'type': 'system',
      'subtype': 'session_state_changed',
      'state': 'running',
    });
    // What agy has not seen: the conversation as it was before this.
    final before = [..._store.chain];
    _takeUp(uuid, content);
    String? error;
    String? stopReason;
    var checked = DateTime.now();
    final watchdog = Timer.periodic(checkEvery, (_) {
      final now = DateTime.now();
      // Woken from sleep: the time asleep is not agy's silence.
      final slept = now.difference(checked) > checkEvery + _sleepTolerance;
      checked = now;
      if (slept || _waiting(turn)) {
        turn.heard = now;
        return;
      }
      if (now.difference(turn.heard) < stallAfter) return;
      turn.stalled = true;
      _interrupt();
      _dropConnection();
    });
    try {
      final session = await _session();
      final handoff = handoffReminder(before, syncedUuid: _synced);
      if (handoff != null) _handedOff += agyTokens(handoff);
      turn.prompt = _connection!.request('session/prompt', {
        'sessionId': session,
        'prompt': [
          if (handoff != null) {'type': 'text', 'text': handoff},
          ..._acpPrompt(content),
        ],
      });
      // Ended by one the user folded in ([_steer]): on in that one.
      while (true) {
        final prompt = turn.prompt!;
        final response = await prompt;
        _usageOf(response['usage']);
        if (!identical(prompt, turn.prompt)) continue;
        stopReason = response['stopReason'] as String?;
        break;
      }
    } on AgyUnavailable catch (unavailable) {
      error = unavailable.signIn
          ? 'Sign in to Antigravity in Settings → Models → Antigravity.'
          : '$unavailable';
    } on AcpError catch (failure) {
      error = turn.stalled
          ? 'Antigravity stopped answering, and was restarted.'
          : failure.closed && turn.cancelled
          ? null
          : _said(failure.message, failure.data);
      if (failure.closed) _dropConnection();
    } finally {
      watchdog.cancel();
    }
    _closeOpen();
    final interrupted = turn.cancelled || stopReason == 'cancelled';
    _settleCalls(interrupted: interrupted || error != null);
    if (interrupted) {
      _appendUser('[Request interrupted by user]');
    }
    if (error == null && _agySession != null) {
      _synced = _store.leaf;
      _store.note({
        'type': syncType,
        'agySessionId': _agySession,
        'syncedUuid': _synced,
        'handedOff': _handedOff,
        'used': ?_used,
        'size': ?_size,
      });
    }
    _turn = null;
    final size = _size;
    _emit({
      'type': 'result',
      'subtype': interrupted || error != null
          ? 'error_during_execution'
          : 'success',
      'is_error': error != null,
      'result': ?error,
      'duration_ms': DateTime.now().difference(turn.begun).inMilliseconds,
      'usage': {
        'input_tokens': turn.inputTokens ?? _used ?? 0,
        'output_tokens': turn.outputTokens ?? 0,
        'cache_read_input_tokens': turn.cacheRead,
        'cache_creation_input_tokens': turn.cacheWrite,
        'reasoning_tokens': turn.thought,
      },
      if (_model case final model?)
        'modelUsage': {
          model: {'contextWindow': ?size},
        },
    });
    _emit({
      'type': 'system',
      'subtype': 'session_state_changed',
      'state': 'idle',
    });
    _idleSoon();
    _next();
  }

  /// [content] (Claude's blocks) as ACP's.
  static List<Map<String, Object?>> _acpPrompt(
    List<Map<String, Object?>> content,
  ) => [
    for (final block in content)
      switch (block) {
        {'type': 'text', 'text': final String text} => {
          'type': 'text',
          'text': text,
        },
        {
          'type': 'image',
          'source': {
            'type': 'base64',
            'media_type': final String type,
            'data': final String data,
          },
        } =>
          {'type': 'image', 'mimeType': type, 'data': data},
        _ => null,
      },
  ].nonNulls.toList();

  static String _said(String message, Object? data) => switch (data) {
    final String detail when detail.isNotEmpty => '$message: $detail',
    {'details': final String detail} when detail.isNotEmpty =>
      '$message: $detail',
    _ => message,
  };

  /// How long a turn goes without a word from agy, nothing waited on,
  /// before it is taken to hang: Google's models take a minute or two at
  /// times, retrying when busy, saying nothing meanwhile.
  @visibleForTesting
  static Duration stallAfter = const Duration(minutes: 15);

  /// How often a turn's silence is checked.
  @visibleForTesting
  static Duration checkEvery = const Duration(minutes: 1);

  /// A check this much later than due: the machine slept in between.
  static const _sleepTolerance = Duration(seconds: 10);

  /// How long agy has to end a turn cancelled, before its process is
  /// ended (a known fault of agy's: a cancel not heard).
  @visibleForTesting
  static Duration cancelGrace = const Duration(seconds: 15);

  /// Whether agy's silence in [turn] is a wait, not a hang: on the user
  /// (an approval), on a tool running (a long command; with no limit, as
  /// a build or tests may take long), on one of the app's MCP servers.
  bool _waiting(_Turn turn) =>
      _asked.isNotEmpty ||
      _mcpOpen > 0 ||
      turn.calls.any((id) => _calls[id]?.acp.running ?? false);

  void _interrupt() {
    _stopAllActiveSwarmWorkers();
    final turn = _turn;
    if (turn == null || turn.cancelled) return;
    turn.cancelled = true;
    for (final asked in [..._asked.values]) {
      if (!asked.isCompleted) asked.complete(null);
    }
    _asked.clear();
    if (_agySession case final session?) {
      _connection?.notify('session/cancel', {'sessionId': session});
    }
    Timer(cancelGrace, () {
      if (identical(_turn, turn)) _dropConnection();
    });
  }

  /// Conversation ids of non-swarm subagents (`invoke_subagent`) started in
  /// this session, keyed by their Claude tool_use id, for `stop_task`.
  final Map<String, String> _subagentConvIds = {};

  /// Reverse index from subagent conversation id to its parent `Agent`
  /// Claude tool_use id, used to route ACP-forwarded child tool calls into
  /// their subagent card instead of the main chat feed.
  final Map<String, String> _convToSubagentToolUseId = {};

  /// Running background non-swarm subagent tasks whose `task_started` has
  /// been emitted and whose `task_notification` is still pending.
  final Map<String, _SubagentTaskState> _activeSubagentTasks = {};

  /// Running background shell commands (`run_command`) whose `task_started`
  /// has been emitted to drive ActivityStrip. Keyed by Claude `tool_use_id`.
  final Map<String, _BgCommandTask> _bgCommands = {};

  /// Reverse map from Antigravity background task id (`<conv>/task-N`) to the
  /// Claude `tool_use_id` of the originating `run_command` call.
  final Map<String, String> _agyBgTaskIdToCall = {};

  /// How often the main session's `transcript.jsonl` is checked for newly
  /// backgrounded commands while any `Bash` tool call is still running.
  @visibleForTesting
  static Duration bgTaskPollInterval = const Duration(milliseconds: 600);

  Timer? _bgPollTimer;
  DateTime? _mainTranscriptMtime;
  int? _mainTranscriptSize;
  List<_MainTranscriptEntry> _mainTranscriptEntries = const [];
  final Set<int> _claimedTranscriptSteps = {};

  /// How often a non-swarm subagent's `transcript.jsonl` is polled for changes.
  @visibleForTesting
  static Duration subagentPollInterval = const Duration(milliseconds: 1200);

  /// Consecutive unchanged polls after a subagent stops working before its
  /// watcher is torn down.
  @visibleForTesting
  static int subagentIdlePollsToStop = 4;

  /// Consecutive polls while a subagent's transcript file does not yet exist
  /// (or has no parsed steps) before giving up so watchers cannot leak.
  @visibleForTesting
  static int subagentMissingPollsToStop = 25;

  /// Active `transcript.jsonl` pollers for non-swarm subagents, keyed by their
  /// Claude `tool_use_id`.
  final Map<String, _SubagentTranscriptWatch> _subagentWatches = {};

  /// Number of active subagent transcript polling watchers (for tests).
  @visibleForTesting
  int get activeSubagentWatchCount => _subagentWatches.length;

  static final _subagentConvIdPattern = RegExp(
    r'conversation_?id["\s:=]+([0-9a-f-]{36})',
    caseSensitive: false,
  );

  static final _childCallConvPrefix = RegExp(
    r'^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})_',
  );

  static final _bgTaskIdPattern = RegExp(
    r'background task with task id:\s*([^\s"]+)',
    caseSensitive: false,
  );

  static final _bgTaskLogPattern = RegExp(
    r'Task logs are available at:\s*(file://[^\s]+)',
    caseSensitive: false,
  );

  static String? _extractSubagentConvIdFromText(String text) {
    if (text.isEmpty) return null;
    return _subagentConvIdPattern.firstMatch(text)?.group(1);
  }

  static String? _extractSubagentConvId(_Call call) {
    if (_extractSubagentConvIdFromText(call.acp.output ?? '') case final id?) {
      return id;
    }
    if (call.acp.rawOutput case final Map raw) {
      for (final key in const ['conversationId', 'conversation_id']) {
        if (raw[key] case final String id when id.trim().isNotEmpty) {
          return id.trim();
        }
      }
    }
    return null;
  }

  static String? _decodeFileUri(String rawUri) {
    try {
      return Uri.parse(rawUri).toFilePath();
    } on Object {
      return null;
    }
  }

  /// Refreshes parsed entries from the main session's local Antigravity
  /// `transcript.jsonl` when its mtime/size changes.
  List<_MainTranscriptEntry> _readMainTranscript({bool force = false}) {
    final brainDir = _brainDir;
    final session = _agySession;
    if (brainDir == null || session == null) return const [];
    final file = File(
      p.join(
        brainDir,
        session,
        '.system_generated',
        'logs',
        'transcript.jsonl',
      ),
    );
    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      return _mainTranscriptEntries;
    }
    if (stat.type == FileSystemEntityType.notFound) return const [];
    if (!force &&
        _mainTranscriptMtime == stat.modified &&
        _mainTranscriptSize == stat.size) {
      return _mainTranscriptEntries;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      return _mainTranscriptEntries;
    }
    _mainTranscriptMtime = stat.modified;
    _mainTranscriptSize = stat.size;
    _mainTranscriptEntries = _parseMainTranscriptEntries(content);
    return _mainTranscriptEntries;
  }

  static List<_MainTranscriptEntry> _parseMainTranscriptEntries(
    String content,
  ) {
    final entries = <_MainTranscriptEntry>[];
    final pending = <({String name, Map<String, Object?> args})>[];
    for (final rawLine in const LineSplitter().convert(content)) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        continue;
      }
      if (decoded is! Map<Object?, Object?>) continue;
      final type = decoded['type'] as String? ?? '';
      if (type == 'PLANNER_RESPONSE') {
        final calls = decoded['tool_calls'];
        if (calls is List) {
          for (final rawCall in calls) {
            if (rawCall is! Map<Object?, Object?>) continue;
            final name = rawCall['name'] as String? ?? '';
            final rawArgs = rawCall['args'];
            final args = <String, Object?>{};
            if (rawArgs is Map<Object?, Object?>) {
              for (final e in rawArgs.entries) {
                args['${e.key}'] = _decodeTranscriptArg(e.value);
              }
            }
            pending.add((name: name, args: args));
          }
        }
      } else if (type == 'GENERIC') {
        final paired = pending.isNotEmpty ? pending.removeAt(0) : null;
        final stepIndex = (decoded['step_index'] as num?)?.toInt() ?? -1;
        final status = decoded['status'] as String? ?? '';
        final rawText = decoded['content'] as String? ?? '';
        entries.add(
          _MainTranscriptEntry(
            stepIndex: stepIndex,
            status: status,
            toolName: paired?.name ?? '',
            args: paired?.args ?? const {},
            cleanContent: _stripTranscriptTimestamps(rawText),
          ),
        );
      }
    }
    return entries;
  }

  static Object? _decodeTranscriptArg(Object? value) {
    if (value is! String) return value;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return value;
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith('{') && trimmed.endsWith('}')) ||
        (trimmed.startsWith('[') && trimmed.endsWith(']')) ||
        trimmed == 'true' ||
        trimmed == 'false') {
      try {
        return jsonDecode(trimmed);
      } on FormatException {
        return value;
      }
    }
    return value;
  }

  static final _timestampHeaderLine = RegExp(
    r'^(?:Created|Completed) At:\s*\d{4}-\d{2}-\d{2}T.*$',
  );

  static String _stripTranscriptTimestamps(String raw) {
    final lines = const LineSplitter().convert(raw);
    var start = 0;
    while (start < lines.length &&
        (lines[start].trim().isEmpty ||
            _timestampHeaderLine.hasMatch(lines[start].trim()))) {
      start++;
    }
    return lines.sublist(start).join('\n').trim();
  }

  static bool _entryMatchesCall(_MainTranscriptEntry entry, _Call call) {
    final acpName = call.acp.name ?? '';
    if (acpName.isEmpty || entry.toolName != acpName) return false;
    switch (acpName) {
      case 'run_command':
        final expected =
            '${call.acp.input['CommandLine'] ?? call.acp.input['command'] ?? ''}'
                .trim();
        final actual = '${entry.args['CommandLine'] ?? entry.args['command'] ?? ''}'
            .trim();
        if (expected.isNotEmpty && actual.isNotEmpty) {
          return expected == actual;
        }
        return true;
      case 'manage_task':
        final action = '${call.acp.input['Action'] ?? ''}'.trim();
        final entryAction = '${entry.args['Action'] ?? ''}'.trim();
        if (action.isNotEmpty && entryAction.isNotEmpty && action != entryAction) {
          return false;
        }
        final taskId = '${call.acp.input['TaskId'] ?? ''}'.trim();
        final entryTaskId = '${entry.args['TaskId'] ?? ''}'.trim();
        if (taskId.isNotEmpty && entryTaskId.isNotEmpty && taskId != entryTaskId) {
          return false;
        }
        return true;
      case 'manage_subagents':
        final action = '${call.acp.input['Action'] ?? ''}'.trim();
        final entryAction = '${entry.args['Action'] ?? ''}'.trim();
        return action.isEmpty || entryAction.isEmpty || action == entryAction;
      case 'invoke_subagent' || 'start_subagent':
        final role = '${call.acp.input['Role'] ?? ''}'.trim();
        final entryRole = '${entry.args['Role'] ?? ''}'.trim();
        return role.isEmpty || entryRole.isEmpty || role == entryRole;
      case 'define_subagent':
        final name = '${call.acp.input['Name'] ?? ''}'.trim();
        final entryName = '${entry.args['Name'] ?? ''}'.trim();
        return name.isEmpty || entryName.isEmpty || name == entryName;
      default:
        return true;
    }
  }

  _MainTranscriptEntry? _claimMainTranscriptEntry(
    _Call call, {
    bool requireNonEmpty = true,
  }) {
    final entries = _readMainTranscript();
    for (var i = entries.length - 1; i >= 0; i--) {
      final entry = entries[i];
      if (entry.stepIndex >= 0 &&
          _claimedTranscriptSteps.contains(entry.stepIndex)) {
        continue;
      }
      if (!_entryMatchesCall(entry, call)) continue;
      if (requireNonEmpty && entry.cleanContent.isEmpty) continue;
      if (entry.stepIndex >= 0) _claimedTranscriptSteps.add(entry.stepIndex);
      return entry;
    }
    return null;
  }

  String? _fallbackOutputFromMainTranscript(_Call call) {
    final acpName = call.acp.name ?? '';
    const supported = {
      'manage_task',
      'manage_subagents',
      'define_subagent',
      'schedule',
      'invoke_subagent',
      'start_subagent',
      'list_resources',
      'read_resource',
    };
    if (!supported.contains(acpName)) return null;
    final entry = _claimMainTranscriptEntry(call);
    return entry?.cleanContent;
  }

  /// Resolves the parent subagent / swarm worker `tool_use_id` for an
  /// ACP-forwarded child tool call whose id is prefixed with `<convId>_`.
  String? _parentToolUseIdFor(String acpCallId) {
    final match = _childCallConvPrefix.firstMatch(acpCallId);
    if (match == null) return null;
    final convId = match.group(1)!;
    if (convId == _agySession) return null;
    if (_convToSubagentToolUseId[convId] case final parent?) return parent;
    if (_swarm case final swarm?) {
      for (final member in swarm.members) {
        if (member.conversationId == convId) {
          return 'swarm-worker:${member.name}';
        }
      }
    }
    // Race guard: child call may arrive just before invoke_subagent finishes
    // or before its transcript line is claimed. Refresh from main transcript
    // first, else bind if there is a single unbound invoke_subagent call.
    final entries = _readMainTranscript(force: true);
    for (final entry in entries) {
      if (entry.toolName != 'invoke_subagent' &&
          entry.toolName != 'start_subagent') {
        continue;
      }
      if (_extractSubagentConvIdFromText(entry.cleanContent) == convId) {
        for (final candidate in _calls.values) {
          if ((candidate.acp.name == 'invoke_subagent' ||
                  candidate.acp.name == 'start_subagent') &&
              !_subagentConvIds.containsKey(candidate.claudeId) &&
              _entryMatchesCall(entry, candidate)) {
            _bindSubagentConv(candidate, convId);
            return candidate.claudeId;
          }
        }
      }
    }
    final unbound = [
      for (final c in _calls.values)
        if ((c.acp.name == 'invoke_subagent' ||
                c.acp.name == 'start_subagent') &&
            c.told &&
            !_subagentConvIds.containsKey(c.claudeId))
          c,
    ];
    if (unbound.length == 1) {
      _bindSubagentConv(unbound.single, convId);
      return unbound.single.claudeId;
    }
    return null;
  }

  void _bindSubagentConv(_Call call, String convId) {
    if (convId.isEmpty) return;
    _subagentConvIds[call.claudeId] = convId;
    _convToSubagentToolUseId[convId] = call.claudeId;
    if (!call.acp.failed && !_activeSubagentTasks.containsKey(call.claudeId)) {
      final desc = '${call.input['description'] ?? call.acp.summary ?? 'Subagent'}';
      _activeSubagentTasks[call.claudeId] = _SubagentTaskState(
        toolUseId: call.claudeId,
        convId: convId,
        description: desc,
      );
      _emit({
        'type': 'system',
        'subtype': 'task_started',
        'task_id': call.claudeId,
        'tool_use_id': call.claudeId,
        'task_type': 'local_agent',
        'description': desc,
        'is_backgrounded': true,
      });
    }
    _watchSubagentTranscript(call.claudeId, convId);
  }

  void _settleSubagentTask(
    String toolUseId, {
    required String status,
    String? summary,
  }) {
    final state = _activeSubagentTasks.remove(toolUseId);
    if (state == null) return;
    final text = (summary != null && summary.isNotEmpty)
        ? summary
        : state.lastReply;
    _emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': toolUseId,
      'tool_use_id': toolUseId,
      'status': status,
      if (text != null && text.isNotEmpty) 'summary': text,
      if (state.tokens > 0 || state.toolUses > 0)
        'usage': {
          if (state.tokens > 0) 'total_tokens': state.tokens,
          if (state.toolUses > 0) 'tool_uses': state.toolUses,
        },
    });
  }

  void _ensureBgCommandPolling() {
    final hasRunningBash = _calls.values.any(
      (c) => c.told && !c.done && c.name == 'Bash',
    );
    if (!hasRunningBash && _bgCommands.isEmpty) {
      _bgPollTimer?.cancel();
      _bgPollTimer = null;
      return;
    }
    if (_bgPollTimer != null || _closed) return;
    _bgPollTimer = Timer.periodic(bgTaskPollInterval, (_) {
      _syncBackgroundCommands();
    });
  }

  void _syncBackgroundCommands() {
    if (_closed) {
      _bgPollTimer?.cancel();
      _bgPollTimer = null;
      return;
    }
    final runningBash = [
      for (final c in _calls.values)
        if (c.told && !c.done && c.name == 'Bash') c,
    ];
    if (runningBash.isEmpty) {
      _bgPollTimer?.cancel();
      _bgPollTimer = null;
      return;
    }
    final entries = _readMainTranscript();
    for (final call in runningBash) {
      String? agyTaskId;
      String? logPath;
      final directOut = call.acp.output ?? '';
      if (_bgTaskIdPattern.firstMatch(directOut) case final m?) {
        agyTaskId = m.group(1);
      }
      if (_bgTaskLogPattern.firstMatch(directOut) case final m?) {
        logPath = _decodeFileUri(m.group(1)!);
      }
      if (agyTaskId == null || logPath == null) {
        for (var i = entries.length - 1; i >= 0; i--) {
          final entry = entries[i];
          if (!_entryMatchesCall(entry, call)) continue;
          final tid = _bgTaskIdPattern.firstMatch(entry.cleanContent)?.group(1);
          if (tid == null) continue;
          agyTaskId ??= tid;
          final rawLog = _bgTaskLogPattern
              .firstMatch(entry.cleanContent)
              ?.group(1);
          if (rawLog != null) logPath ??= _decodeFileUri(rawLog);
          break;
        }
      }
      final isDaemon = call.acp.input['IsDaemon'] == true;
      if (agyTaskId == null && !isDaemon) continue;
      _registerBgCommand(call, agyTaskId: agyTaskId, logPath: logPath);
    }
  }

  void _registerBgCommand(
    _Call call, {
    String? agyTaskId,
    String? logPath,
  }) {
    final existing = _bgCommands[call.claudeId];
    if (existing != null) {
      if (agyTaskId != null && existing.agyTaskId == null) {
        existing.agyTaskId = agyTaskId;
        _agyBgTaskIdToCall[agyTaskId] = call.claudeId;
      }
      if (logPath != null && existing.outputFile != logPath) {
        existing.outputFile = logPath;
        _emit({
          'type': 'system',
          'subtype': 'task_updated',
          'task_id': existing.taskId,
          'patch': {'output_file': logPath},
        });
      }
      return;
    }
    final taskId = agyTaskId ?? call.claudeId;
    final desc =
        call.acp.summary ??
        '${call.input['description'] ?? call.input['command'] ?? 'Background command'}';
    final bg = _BgCommandTask(
      taskId: taskId,
      toolUseId: call.claudeId,
      description: desc,
      agyTaskId: agyTaskId,
      outputFile: logPath,
    );
    _bgCommands[call.claudeId] = bg;
    if (agyTaskId != null) _agyBgTaskIdToCall[agyTaskId] = call.claudeId;
    _emit({
      'type': 'system',
      'subtype': 'task_started',
      'task_id': taskId,
      'tool_use_id': call.claudeId,
      'task_type': 'local_bash',
      'description': desc,
      'is_backgrounded': true,
      'stoppable': false,
      'output_file': ?logPath,
    });
  }

  void _settleBgCommand(
    String toolUseId, {
    required String status,
    String? summary,
  }) {
    final bg = _bgCommands.remove(toolUseId);
    if (bg == null) return;
    if (bg.agyTaskId != null) _agyBgTaskIdToCall.remove(bg.agyTaskId);
    _emit({
      'type': 'system',
      'subtype': 'task_notification',
      'task_id': bg.taskId,
      'tool_use_id': toolUseId,
      'status': status,
      if (summary != null && summary.isNotEmpty) 'summary': summary,
      if (bg.outputFile != null) 'output_file': bg.outputFile,
    });
    _ensureBgCommandPolling();
  }

  void _settleAllBgTasks({required String status}) {
    _bgPollTimer?.cancel();
    _bgPollTimer = null;
    for (final toolUseId in [..._bgCommands.keys]) {
      _settleBgCommand(toolUseId, status: status);
    }
    for (final toolUseId in [..._activeSubagentTasks.keys]) {
      _settleSubagentTask(toolUseId, status: status);
    }
  }

  /// Starts (or refreshes) lightweight polling of
  /// `<brainDir>/<convId>/.system_generated/logs/transcript.jsonl` for a
  /// non-swarm subagent (`invoke_subagent` / `start_subagent`), emitting
  /// `subagent_transcript` system events whenever the file changes.
  void _watchSubagentTranscript(String toolUseId, String convId) {
    final brainDir = _brainDir;
    if (_closed || brainDir == null || convId.isEmpty) return;
    final existing = _subagentWatches[toolUseId];
    if (existing != null) {
      if (existing.convId == convId) {
        existing.poll();
        return;
      }
      existing.dispose();
      _subagentWatches.remove(toolUseId);
    }
    late final _SubagentTranscriptWatch watch;
    watch = _SubagentTranscriptWatch(
      toolUseId: toolUseId,
      convId: convId,
      file: File(
        p.join(
          brainDir,
          convId,
          '.system_generated',
          'logs',
          'transcript.jsonl',
        ),
      ),
      pollInterval: subagentPollInterval,
      idlePollsToStop: subagentIdlePollsToStop,
      missingPollsToStop: subagentMissingPollsToStop,
      onSteps: (steps, isWorking) {
        if (_closed) return;
        _emit({
          'type': 'system',
          'subtype': 'subagent_transcript',
          'tool_use_id': toolUseId,
          'steps': [for (final s in steps) s.toJson()],
        });
        if (_activeSubagentTasks[toolUseId] case final state?) {
          var toolUses = 0;
          var tokens = 0;
          String? lastReply;
          for (final s in steps) {
            if (s.kind == 'tool') toolUses++;
            tokens += s.inputTokens + s.outputTokens;
            if (s.kind == 'reply') {
              final text = (s.detail ?? s.title).trim();
              if (text.isNotEmpty) lastReply = text;
            }
          }
          state
            ..toolUses = toolUses
            ..tokens = tokens
            ..lastReply = lastReply ?? state.lastReply;
          if (isWorking) {
            final last = steps.last;
            _emit({
              'type': 'system',
              'subtype': 'task_progress',
              'task_id': toolUseId,
              'tool_use_id': toolUseId,
              'description': last.title,
              'last_tool_name': ?last.toolName,
              'usage': {'total_tokens': tokens, 'tool_uses': toolUses},
            });
          } else {
            final failed = steps.isNotEmpty && steps.last.kind == 'error';
            _settleSubagentTask(
              toolUseId,
              status: failed ? 'failed' : 'completed',
              summary: lastReply,
            );
          }
        }
      },
      onDone: (forcedStopped) {
        if (identical(_subagentWatches[toolUseId], watch)) {
          _subagentWatches.remove(toolUseId);
        }
        if (!_closed && _activeSubagentTasks.containsKey(toolUseId)) {
          _settleSubagentTask(
            toolUseId,
            status: forcedStopped ? 'stopped' : 'completed',
          );
        }
      },
    );
    _subagentWatches[toolUseId] = watch;
    watch.start();
  }

  void _stopAllSubagentWatches() {
    for (final watch in [..._subagentWatches.values]) {
      watch.dispose();
    }
    _subagentWatches.clear();
  }

  /// Cancels a single swarm worker by roster [name] and settles its live state.
  bool _stopSwarmWorker(String name) {
    final swarm = _swarm;
    if (swarm == null) return false;
    final member = swarm.members.where((m) => m.name == name).firstOrNull;
    if (member == null) return false;
    if (member.conversationId.isNotEmpty) {
      _connection?.notify('session/cancel', {
        'sessionId': member.conversationId,
      });
    }
    _swarmWatcher?.markStopped(name);
    _swarmWatcher?.checkNow();
    return true;
  }

  /// Cancels all currently running non-coordinator swarm workers (e.g. on
  /// main conversation interrupt or session close).
  void _stopAllActiveSwarmWorkers() {
    final swarm = _swarm;
    if (swarm == null) return;
    var any = false;
    for (final m in swarm.members) {
      if (m.role == SwarmMemberRole.coordinator || !m.isWorking) continue;
      if (m.conversationId.isNotEmpty) {
        _connection?.notify('session/cancel', {
          'sessionId': m.conversationId,
        });
      }
      _swarmWatcher?.markStopped(m.name);
      any = true;
    }
    if (any) _swarmWatcher?.checkNow();
  }

  Future<Map<String, Object?>> _rewind(Map<String, Object?> request) async {
    final target = request['target_message_uuid'] as String?;
    if (target == null) return {'rewound': false, 'error': 'No message given'};
    if (_turn case final turn?) {
      if (request['interrupt_if_running'] != true) {
        return {'rewound': false, 'error': 'A turn is running'};
      }
      _interrupt();
      while (identical(_turn, turn)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
    if (!_store.rewindTo(target)) {
      return {'rewound': false, 'error': 'Message not found: $target'};
    }
    // agy saw what is rewound: it starts over, told the rest.
    if (_synced != null && !_onChain(_synced!)) {
      _synced = null;
      _agySession = null;
      _handedOff = 0;
      _used = null;
    }
    return {'rewound': true};
  }

  bool _onChain(String uuid) => _store.chain.any((e) => e['uuid'] == uuid);

  // --- agy -------------------------------------------------------------------------

  /// How the session is noted beside the conversation.
  static const syncType = 'antigravity-session';

  /// The last note of agy's session in the conversation's file.
  ({String session, String? synced, int handedOff, int? used, int? size})?
  get _syncLine {
    for (final entry in _store.extras.reversed) {
      if (entry case {'type': syncType, 'agySessionId': final String id}) {
        return (
          session: id,
          synced: entry['syncedUuid'] as String?,
          handedOff: (entry['handedOff'] as num?)?.toInt() ?? 0,
          used: (entry['used'] as num?)?.toInt(),
          size: (entry['size'] as num?)?.toInt(),
        );
      }
    }
    return null;
  }

  AcpConnection? _connection;
  Future<String>? _starting;

  /// agy's session; the last message of the conversation it saw.
  String? _agySession;
  String? _synced;

  /// What its session was told of turns on other models, in tokens as
  /// estimated ([agyTokens]): for what fills its context to be told.
  int _handedOff = 0;

  /// The instructions and skills its session was told as it started; the
  /// user's as they are now, for one resumed.
  ForeignBrief? _toldBrief;

  /// Whether [_agySession] is open on [_connection].
  bool _open = false;

  final List<McpEndpoint> _endpoints = [];

  /// agy's session, on an agy started (or resumed) for it.
  Future<String> _session() {
    if (_open && _connection?.done == false && _agySession != null) {
      return Future.value(_agySession);
    }
    return _starting ??= _startSession().whenComplete(() => _starting = null);
  }

  /// When the current `agy acp` process was started (to avoid treating stale
  /// worker transcripts from a previous dead process as still working).
  DateTime _processBornAt = DateTime.now();

  Future<String> _startSession() async {
    _dropConnection();
    _processBornAt = DateTime.now();
    final transport = await _runtime.start(options.cwd);
    final connection = _connection = AcpConnection(
      transport,
      onRequest: _agentRequest,
      onNotification: _notification,
    );
    unawaited(
      connection.exited.then((_) {
        if (identical(_connection, connection)) _dropConnection();
      }),
    );
    await connection.request('initialize', agyHello);
    final base = <String, Object?>{
      'cwd': options.cwd,
      'mcpServers': await _mcpServers(),
      if (options.directories.isNotEmpty)
        'additionalDirectories': options.directories,
    };
    var resumed = false;
    if ((_agySession, _synced) case (final id?, final synced?)
        when _onChain(synced)) {
      try {
        await connection.request('session/resume', {...base, 'sessionId': id});
        resumed = true;
      } on AcpError catch (error) {
        if (error.closed) rethrow;
        // Gone (deleted, another account's): a new one, told all of it.
      }
    }
    if (!resumed) {
      final started = await connection.request('session/new', {
        ...base,
        '_meta': {
          'antigravity': {
            'systemPrompt': {'append': _appendedPrompt()},
          },
        },
      });
      _agySession = started['sessionId'] as String?;
      _synced = null;
      _handedOff = 0;
      _used = null;
      _commandsOf(started);
      if (_agySession == null) {
        throw const AcpError(-32603, 'Antigravity started no session');
      }
    }
    _open = true;
    _watchSwarm();
    await _applyOption('model', _model);
    await _applyOption('thought_level', _effort);
    return _agySession!;
  }

  /// Watches `<brainDir>/<agySessionId>/.system_generated/swarm/` and pushes
  /// live snapshots to the kernel whenever the swarm roster, board, plan, or
  /// worker transcripts change.
  void _watchSwarm() {
    final brainDir = _brainDir;
    final session = _agySession;
    if (_closed || brainDir == null || session == null) return;
    if (_swarmWatcher case final current? when current.swarmId == session) {
      current.updateActiveSince(_processBornAt);
      current.checkNow();
      return;
    }
    _swarmWatcher?.dispose();
    _swarmWatcher = SwarmWatcher(
      brainDir: brainDir,
      swarmId: session,
      activeSince: _processBornAt,
      onSnapshot: (snapshot) {
        if (_closed) return;
        _swarm = snapshot;
        _emit({
          'type': 'system',
          'subtype': 'swarm_update',
          'swarm': snapshot.toJson(),
        });
      },
    )..start();
  }

  /// What agy is told past its own prompt, as the session starts: how the
  /// chat cites code and draws Markdown, the workspace's instructions, and
  /// the user's rules, auto memory, and skills as Claude Code has them.
  String _appendedPrompt() => [
    options.appendedSystemPrompt ??
        AgyLaunchOptions.defaultAppendedSystemPrompt,
    if (options.instructions case final text? when text.isNotEmpty) text,
    ?(_toldBrief = _brief()).text,
    'Notes from BaoCode, the app you run in, come in <system-reminder> '
        'tags in the user\'s messages: take them in, without mentioning '
        'them to the user. One may tell you what was said and done in this '
        'conversation with another model while you were not in it. '
        'Follow BaoCode\'s <citing_code>, <file_links>, and <formatting> '
        'rules over any conflicting link or image path rules above (in '
        'particular: use absolute paths without file://, and always wrap '
        'link or image paths containing spaces in angle brackets <...>).',
  ].join('\n\n');

  ForeignBrief _brief({bool prepareAutoMemory = true}) {
    try {
      return ForeignBrief.of(
        environment: _environment,
        cwd: options.cwd,
        additional: options.directories,
        readAdditional: options.folderInstructions,
        flagSettings: options.flagSettings,
        prepareAutoMemory: prepareAutoMemory,
      );
    } on Object {
      return const ForeignBrief();
    }
  }

  Future<void> _applyOption(String id, String? value) async {
    final connection = _connection;
    final session = _agySession;
    if (value == null || connection == null || session == null || !_open) {
      return;
    }
    try {
      await connection.request('session/set_config_option', {
        'sessionId': session,
        'configId': id,
        'value': value,
      });
    } on AcpError {
      // Not one agy has (a level the model lacks): its own stays.
    }
  }

  /// The app's own MCP servers, served to agy over HTTP on this machine:
  /// each message to them asked of the kernel (`mcp_message`), as the
  /// CLI asks it.
  Future<List<Map<String, Object?>>> _mcpServers() async {
    if (_endpoints.isEmpty) {
      for (final name in _sdkServers) {
        _endpoints.add(
          await McpHttpServer.start((message) => _mcp(name, message)),
        );
      }
    }
    return [
      for (final (i, endpoint) in _endpoints.indexed)
        {
          'type': 'http',
          'name': _sdkServers[i],
          'url': '${endpoint.url}',
          'headers': [
            for (final MapEntry(:key, :value) in endpoint.headers.entries)
              {'name': key, 'value': value},
          ],
        },
    ];
  }

  Future<Map<String, Object?>?> _mcp(
    String server,
    Map<String, Object?> message,
  ) async {
    _mcpOpen++;
    try {
      final response = await _kernel.request('mcp_message', {
        'server_name': server,
        'message': message,
      }, const Duration(hours: 1));
      if (!message.containsKey('id')) return null;
      final answer = (response['mcp_response'] as Map?)
          ?.cast<String, Object?>();
      _noteMcpResult(server, message, answer);
      return answer;
    } finally {
      _mcpOpen--;
    }
  }

  /// Messages to the app's MCP servers not answered yet.
  int _mcpOpen = 0;

  /// What a tool of [server]'s answered, kept for its call to show: agy
  /// tells none of it. Its message names no call, so the first of that
  /// tool's not answered yet takes it; not one of a subagent's (another
  /// conversation of agy's), whose calls are not this session's.
  void _noteMcpResult(
    String server,
    Map<String, Object?> message,
    Map<String, Object?>? answer,
  ) {
    if (message['method'] != 'tools/call') return;
    if (answer?['result'] case final Map<Object?, Object?> result) {
      final params = message['params'] as Map? ?? const {};
      final meta = params['_meta'] as Map? ?? const {};
      final conversation = meta['antigravity.google/conversation_id'];
      if (conversation != null && conversation != _agySession) return;
      final name = 'mcp__${server}__${params['name']}';
      final call = _calls.values
          .where((c) => c.told && !c.done && c.mcpResult == null)
          .where((c) => c.name == name)
          .firstOrNull;
      call?.mcpResult = result.cast();
    }
  }

  /// Ends agy's process: the session stays agy's, resumed on the next.
  void _dropConnection() {
    final connection = _connection;
    _connection = null;
    _open = false;
    _bgPollTimer?.cancel();
    _bgPollTimer = null;
    for (final watch in _subagentWatches.values) {
      watch.markStopped();
    }
    connection?.close();
  }

  // --- Ended when idle -------------------------------------------------------------

  Timer? _idleTimer;

  /// How long agy is kept once a turn is over: its process is big.
  static const idleFor = Duration(minutes: 10);

  void _idleSoon() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleFor, () {
      // Commands or swarm workers it left running in the background keep it.
      if (_turn != null ||
          _calls.values.any((c) => c.acp.running) ||
          (_swarm?.hasActiveWorkers ?? false)) {
        _idleSoon();
        return;
      }
      _dropConnection();
    });
  }

  // --- What agy asks ---------------------------------------------------------------

  final Map<String, Completer<Map<String, Object?>?>> _asked = {};

  /// Rules the user gave to allow a tool from now on ("always allow").
  final List<({String tool, String? content})> _allowed = [];

  Future<Object?> _agentRequest(
    String method,
    Map<String, Object?> params,
  ) async {
    if (method == 'elicitation/create') return _elicit(params);
    if (method != 'session/request_permission') {
      throw AcpError(-32601, 'Method not found: $method');
    }
    final options = [
      for (final option in params['options'] as List? ?? const [])
        if (option is Map) option.cast<String, Object?>(),
    ];
    String? optionOf(String kind) => options
        .where((option) => option['kind'] == kind)
        .map((option) => option['optionId'] as String?)
        .firstOrNull;
    final allow = optionOf('allow_once') ?? optionOf('allow_always');
    final reject = optionOf('reject_once') ?? optionOf('reject_always');
    Map<String, Object?> selected(String? id) => id == null
        ? const {
            'outcome': {'outcome': 'cancelled'},
          }
        : {
            'outcome': {'outcome': 'selected', 'optionId': id},
          };
    final update = (params['toolCall'] as Map?)?.cast<String, Object?>();
    // Not a tool to approve: a question (a subagent's), its options the
    // answers.
    if (update?['toolCallId'] case final String id
        when id.startsWith('interaction_')) {
      if (_turn?.cancelled != false) return selected(null);
      final labels = {
        for (final option in options)
          if (option['optionId'] case final String id)
            '${option['name'] ?? id}': id,
      };
      final question = '${update!['title'] ?? 'Choose an option.'}';
      _closeOpen();
      final answer = await _canUseTool({
        'tool_name': 'AskUserQuestion',
        'input': {
          'questions': [
            {
              'question': question,
              'header': '',
              'options': [
                for (final label in labels.keys)
                  {'label': label, 'description': ''},
              ],
              'multiSelect': false,
            },
          ],
        },
        'tool_use_id': claudeToolId(id),
        'permission_suggestions': const [],
      });
      final picked = switch (answer?['updatedInput']) {
        {'answers': final Map<Object?, Object?> answers} => answers[question],
        _ => null,
      };
      return selected(labels[picked]);
    }
    final call = update == null ? null : _toolCall(update);
    if (call == null || _turn?.cancelled != false) return selected(null);
    _closeOpen();
    _tell(call);
    final allowed = await _allows(call);
    if (!allowed) return selected(reject);
    // An edit allowed: the edit watch told before it lands.
    if (call.edits && !call.preHooked) {
      call.preHooked = true;
      await _hook('PreToolUse', call);
    }
    return selected(allow);
  }

  /// Whether [call] may go ahead: as the mode says, else as the user does.
  Future<bool> _allows(_Call call) async {
    final input = call.input;
    if (_mode == 'bypassPermissions') return true;
    if (call.edits && _isAutoMemory(call)) return true;
    if (call.edits && (_mode == 'acceptEdits' || _mode == 'auto')) return true;
    if (call.acp.kind case 'read' || 'search' || 'fetch') return true;
    final command = input['command'] as String?;
    for (final rule in _allowed) {
      if (rule.tool != call.name) continue;
      final content = rule.content;
      if (content == null) return true;
      if (command == null) continue;
      if (content == command) return true;
      if (content.endsWith(':*') &&
          command.startsWith(content.substring(0, content.length - 2))) {
        return true;
      }
    }
    final answer = await _canUseTool({
      'tool_name': call.name,
      'input': input,
      'tool_use_id': call.claudeId,
      'permission_suggestions': [
        if (call.name == 'Bash' && command != null)
          {
            'type': 'addRules',
            'rules': [
              {'toolName': 'Bash', 'ruleContent': command},
            ],
            'behavior': 'allow',
            'destination': 'session',
          }
        else if (call.edits)
          {'type': 'setMode', 'mode': 'acceptEdits', 'destination': 'session'},
      ],
    });
    if (answer == null || answer['behavior'] != 'allow') {
      if (call.edits) await _hook('PermissionDenied', call);
      return false;
    }
    for (final raw in answer['updatedPermissions'] as List? ?? const []) {
      if (raw is! Map) continue;
      switch (raw['type']) {
        case 'setMode':
          if (raw['mode'] case final String mode) _mode = mode;
        case 'addRules' || 'replaceRules' when raw['behavior'] == 'allow':
          for (final rule in raw['rules'] as List? ?? const []) {
            if (rule case {'toolName': final String tool}) {
              _allowed.add((
                tool: tool,
                content: rule['ruleContent'] as String?,
              ));
            }
          }
      }
    }
    return true;
  }

  /// Whether [call] writes inside the project's auto memory folder, which
  /// the agent may always update without prompting.
  bool _isAutoMemory(_Call call) {
    final dir = (_toldBrief ??= _brief(prepareAutoMemory: false)).autoMemoryDir;
    if (dir == null) return false;
    final target =
        call.input['file_path'] as String? ??
        call.acp.diff?.path ??
        call.acp.path;
    if (target == null || target.isEmpty) return false;
    final normalizedDir = p.normalize(dir);
    final normalizedTarget = p.normalize(
      p.isAbsolute(target) ? target : p.join(options.cwd, target),
    );
    if (p.isWithin(normalizedDir, normalizedTarget)) return true;
    return p.isWithin(_realPath(normalizedDir), _realPath(normalizedTarget));
  }

  static String _realPath(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      try {
        final parent = Directory(p.dirname(path)).resolveSymbolicLinksSync();
        return p.join(parent, p.basename(path));
      } on FileSystemException {
        return path;
      }
    }
  }

  int _requests = 0;

  /// Asks the kernel `can_use_tool` [request], as the CLI does: its answer
  /// (`behavior`, `updatedInput`, …), null for the turn cancelled first.
  Future<Map<String, Object?>?> _canUseTool(
    Map<String, Object?> request,
  ) async {
    final requestId = 'agy-perm-${++_requests}';
    final asked = _asked[requestId] = Completer();
    unawaited(
      _kernel
          .request('can_use_tool', request, const Duration(days: 1))
          .then<void>(
            (answer) {
              if (!asked.isCompleted) asked.complete(answer);
            },
            onError: (Object _) {
              if (!asked.isCompleted) asked.complete(null);
            },
          ),
    );
    final answer = await asked.future;
    _asked.remove(requestId);
    return answer;
  }

  /// A form agy asks the user to fill in (its ask_question's), put to them
  /// as Claude Code's AskUserQuestion; what they picked given back as the
  /// form has it.
  Future<Map<String, Object?>> _elicit(Map<String, Object?> params) async {
    final form = AgyQuestionForm.of(params['requestedSchema']);
    if (_turn?.cancelled != false) return const {'action': 'cancel'};
    if (form == null) return const {'action': 'decline'};
    _closeOpen();
    final call = switch (params['toolCallId']) {
      final String id => _calls[id],
      _ => null,
    };
    if (call != null) _tell(call);
    final answer = await _canUseTool({
      'tool_name': 'AskUserQuestion',
      'input': {'questions': form.questions},
      'tool_use_id': call?.claudeId ?? claudeToolId('ask_${_requests + 1}'),
      'permission_suggestions': const [],
    });
    if (answer == null) return const {'action': 'cancel'};
    if (answer['behavior'] != 'allow') return const {'action': 'decline'};
    final given = switch (answer['updatedInput']) {
      {'answers': final Map<Object?, Object?> answers} => answers,
      _ => const <Object?, Object?>{},
    };
    final answers = {
      for (final MapEntry(:key, :value) in given.entries) '$key': '$value',
    };
    call?.answers = answers;
    return {'action': 'accept', 'content': form.content(answers)};
  }

  /// Calls back the kernel's hooks of [event] for [call], as Claude Code
  /// does, each once the one before is answered.
  Future<void> _hook(String event, _Call call) async {
    for (final raw in _hooks[event] as List? ?? const []) {
      final matcher = (raw as Map).cast<String, Object?>();
      final pattern = matcher['matcher'] as String? ?? '';
      if (pattern.isNotEmpty &&
          !RegExp('^(?:$pattern)\$').hasMatch(call.name)) {
        continue;
      }
      for (final callback in matcher['hookCallbackIds'] as List? ?? const []) {
        try {
          await _kernel.request('hook_callback', {
            'callback_id': callback,
            'input': {
              'hook_event_name': event,
              'tool_name': call.name,
              'tool_input': call.input,
              'tool_use_id': call.claudeId,
            },
            'tool_use_id': call.claudeId,
          }, const Duration(seconds: 15));
        } on ControlError {
          // The edit goes on all the same.
        }
      }
    }
  }

  // --- What agy tells ---------------------------------------------------------------

  void _notification(String method, Map<String, Object?> params) {
    if (method != 'session/update') return;
    if (params['sessionId'] != _agySession) return;
    final update = (params['update'] as Map?)?.cast<String, Object?>();
    if (update == null) return;
    _turn?.heard = DateTime.now();
    switch (update['sessionUpdate']) {
      case 'agent_message_chunk':
        _chunk(_BlockKind.text, _text(update['content']));
      case 'agent_thought_chunk':
        _chunk(_BlockKind.thinking, _text(update['content']));
      case 'tool_call' || 'tool_call_update':
        _closeOpen();
        final call = _toolCall(update);
        if (call != null) _progress(call);
      case 'plan':
        _closeOpen();
        _todos(update);
      case 'usage_update':
        _usageOf(update);
      case 'session_info_update':
        if (update['title'] case final String said) {
          final title = withoutReminders(said);
          // agy does not learn of renames, so it keeps sending its own title
          // on resume: only name an untitled session (matching bao_agent).
          if (title.isNotEmpty && _store.title == null) {
            _store.note({'type': 'ai-title', 'aiTitle': title});
            _emit({
              'type': 'system',
              'subtype': 'session_title_changed',
              'title': title,
            });
          }
        }
      case 'available_commands_update':
        final before = jsonEncode(_commandList);
        _commandsOf(update);
        // Told again as each session starts: the same, as a rule.
        if (jsonEncode(_commandList) == before) return;
        _emit({
          'type': 'system',
          'subtype': 'commands_changed',
          'commands': _commandList,
        });
    }
  }

  static String _text(Object? content) => switch (content) {
    {'type': 'text', 'text': final String text} => text,
    _ => '',
  };

  int? _used;
  int? _size;

  Map<String, Object?> _contextUsage() => agyContextUsage(
    used: _used ?? 0,
    size: _size ?? options.autocompact ?? 0,
    brief: _toldBrief ??= _brief(prepareAutoMemory: false),
    chain: _store.chain,
    handedOff: _handedOff,
  );

  void _usageOf(Object? usage) {
    if (usage is! Map) return;
    final beforeUsed = _used;
    final beforeSize = _size;
    if (usage['used'] case final num used when used > 0 || _used == null) {
      _used = used.toInt();
    }
    if (usage['size'] case final num size when size > 0) {
      _size = size.toInt();
    }
    if (_used != beforeUsed || _size != beforeSize) {
      _emit({
        'type': 'system',
        'subtype': 'context_usage',
        'usage': _contextUsage(),
      });
    }
    // A prompt's, added up: a turn the user folded a message into is
    // told in two prompts or more (see [_steer]).
    final turn = _turn;
    if (turn == null) return;
    if (usage['inputTokens'] case final num input) {
      turn.inputTokens = (turn.inputTokens ?? 0) + input.toInt();
    }
    if (usage['outputTokens'] case final num output) {
      turn.outputTokens = (turn.outputTokens ?? 0) + output.toInt();
    }
    if (usage['cachedReadTokens'] case final num read) {
      turn.cacheRead += read.toInt();
    }
    if (usage['cachedWriteTokens'] case final num written) {
      turn.cacheWrite += written.toInt();
    }
    if (usage['thoughtTokens'] case final num thought) {
      turn.thought += thought.toInt();
    }
  }

  List<Map<String, Object?>> _commands = const [];

  List<Map<String, Object?>> get _commandList => [
    for (final command in _commands)
      {
        'name': command['name'],
        'description': '${command['description'] ?? ''}',
        'argumentHint': switch (command['input']) {
          {'hint': final String hint} => hint,
          _ => '',
        },
      },
  ];

  void _commandsOf(Map<String, Object?> said) {
    if (said['availableCommands'] case final List<Object?> commands) {
      _commands = [
        for (final command in commands)
          if (command case {'name': final String _}) command.cast(),
      ];
    }
  }

  // --- Text and thoughts ----------------------------------------------------------

  _Block? _block;
  int _messages = 0;

  String _messageId() =>
      'msg_agy_${_store.sessionId.substring(0, 8)}_'
      '${DateTime.now().microsecondsSinceEpoch}_${++_messages}';

  void _event(Map<String, Object?> event) => _emit({
    'type': 'stream_event',
    'event': event,
    'parent_tool_use_id': null,
  });

  void _chunk(_BlockKind kind, String text) {
    if (text.isEmpty) return;
    var block = _block;
    if (block == null || block.kind != kind) {
      _closeOpen();
      block = _block = _Block(kind, _messageId());
      _emit({'type': 'system', 'subtype': 'status', 'status': 'requesting'});
      _event({
        'type': 'message_start',
        'message': {'id': block.id, 'role': 'assistant', 'model': _model},
      });
      _event({
        'type': 'content_block_start',
        'index': 0,
        'content_block': kind == _BlockKind.text
            ? const {'type': 'text', 'text': ''}
            : const {'type': 'thinking', 'thinking': ''},
      });
    }
    block.text.write(text);
    _event({
      'type': 'content_block_delta',
      'index': 0,
      'delta': kind == _BlockKind.text
          ? {'type': 'text_delta', 'text': text}
          : {'type': 'thinking_delta', 'thinking': text, 'timed': true},
    });
  }

  /// Ends the text or thought being written: the text kept, the thought
  /// shown only (unsigned, a thought would be turned away by Anthropic's
  /// API as the conversation goes on there).
  void _closeOpen() {
    final block = _block;
    if (block == null) return;
    _block = null;
    _event({'type': 'content_block_stop', 'index': 0});
    _event({'type': 'message_stop'});
    final text = '${block.text}';
    if (block.kind == _BlockKind.thinking) {
      _emit({
        'type': 'assistant',
        'message': _message(block.id, [
          {'type': 'thinking', 'thinking': text, 'signature': ''},
        ]),
        'parent_tool_use_id': null,
        'uuid': newUuid(),
      });
      return;
    }
    _assistant(block.id, [
      {'type': 'text', 'text': text},
    ]);
  }

  Map<String, Object?> _message(
    String id,
    List<Map<String, Object?>> content,
  ) => {
    'id': id,
    'type': 'message',
    'role': 'assistant',
    'model': _model ?? 'antigravity',
    'content': content,
    'stop_reason': null,
    'stop_sequence': null,
    'usage': const {'input_tokens': 0, 'output_tokens': 0},
  };

  /// An answer's block, kept and told.
  void _assistant(
    String id,
    List<Map<String, Object?>> content, {
    String? parentToolUseId,
  }) {
    final entry = _store.append({
      'type': 'assistant',
      'message': _message(id, content),
      'parent_tool_use_id': ?parentToolUseId,
    });
    _emit({
      'type': 'assistant',
      'message': entry['message'],
      'parent_tool_use_id': parentToolUseId,
      'uuid': entry['uuid'],
    });
  }

  void _appendUser(String text) => _store.append({
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': text},
      ],
    },
  });

  // --- Tool calls -----------------------------------------------------------------

  final Map<String, _Call> _calls = {};

  _Call? _toolCall(Map<String, Object?> update) {
    final id = update['toolCallId'];
    if (id is! String) return null;
    _turn?.calls.add(id);
    final call = _calls.putIfAbsent(id, () => _Call(AcpToolCall(id)));
    call.acp.merge(update);
    return call;
  }

  /// [call] as it goes: told once it is known what it does (an edit once
  /// its change is), its result once done.
  void _progress(_Call call) {
    if (!call.told &&
        (!call.edits || call.acp.diff != null || !call.acp.running)) {
      _tell(call);
    }
    if (call.acp.name == 'invoke_subagent' ||
        call.acp.name == 'start_subagent') {
      final convId = _extractSubagentConvId(call);
      if (convId != null) _bindSubagentConv(call, convId);
    }
    if (call.told && !call.done && call.name == 'Bash') {
      _syncBackgroundCommands();
      _ensureBgCommandPolling();
    }
    if (call.told && !call.acp.running && !call.done) _finish(call);
    if (call.acp.name
        case 'swarm' || 'post_message' || 'read_board' || 'swarm_wait') {
      _swarmWatcher?.checkNow();
    }
  }

  void _tell(_Call call) {
    if (call.told) return;
    final use = claudeToolUse(call.acp, servers: _sdkServers);
    final parentToolUseId = _parentToolUseIdFor(call.acp.id);
    call
      ..told = true
      ..name = use.name
      ..input = use.input
      ..parentToolUseId = parentToolUseId;
    // Count tool call JSON tokens in live turn output without skewing live
    // streaming speed with non-streamed tool-call arrival latency.
    if (use.input.isNotEmpty) {
      _event({
        'type': 'content_block_delta',
        'index': -1,
        'delta': {
          'type': 'input_json_delta',
          'partial_json': jsonEncode(use.input),
          'timed': false,
        },
      });
    }
    _assistant(
      _messageId(),
      [
        {
          'type': 'tool_use',
          'id': call.claudeId,
          'name': use.name,
          'input': use.input,
        },
      ],
      parentToolUseId: parentToolUseId,
    );
  }

  void _finish(_Call call) {
    call.done = true;
    String? fileText;
    final diff = call.edits ? call.acp.diff : null;
    if (diff != null) {
      try {
        fileText = File(diff.path).readAsStringSync();
      } on Object {
        // Gone, or not text: the patch numbered from its start.
      }
    }
    final fallbackOutput = (call.acp.output ?? '').isEmpty
        ? _fallbackOutputFromMainTranscript(call)
        : null;
    if (call.acp.name == 'invoke_subagent' ||
        call.acp.name == 'start_subagent') {
      final convId =
          _subagentConvIds[call.claudeId] ??
          _extractSubagentConvId(call) ??
          _extractSubagentConvIdFromText(fallbackOutput ?? '');
      if (convId != null) _bindSubagentConv(call, convId);
    }
    final result = claudeToolResult(
      call.acp,
      call.name,
      fileText: fileText,
      answers: call.answers,
      mcpResult: call.mcpResult,
      fallbackOutput: fallbackOutput,
    );
    var structured = result.structured;
    if ((call.acp.name == 'invoke_subagent' ||
            call.acp.name == 'start_subagent') &&
        !result.isError) {
      if (_subagentConvIds[call.claudeId] case final convId?) {
        structured = {
          ...?structured,
          'status': 'async_launched',
          'agentId': convId,
          if (call.input['prompt'] case final String prompt) 'prompt': prompt,
        };
      }
    }
    _result(
      call,
      result.content,
      isError: result.isError,
      structured: structured,
    );
    if (call.name == 'Bash') {
      _settleBgCommand(
        call.claudeId,
        status: result.isError ? 'failed' : 'completed',
        summary: result.content is String ? result.content as String : null,
      );
      _ensureBgCommandPolling();
    } else if (call.acp.name == 'manage_task' &&
        call.acp.input['Action'] == 'kill') {
      final killedId = '${call.acp.input['TaskId'] ?? ''}'.trim();
      if (_agyBgTaskIdToCall[killedId] case final targetToolUseId?) {
        _settleBgCommand(targetToolUseId, status: 'stopped');
      }
    } else if (call.acp.name == 'manage_subagents') {
      final action = '${call.acp.input['Action'] ?? ''}';
      if (action == 'kill_all') {
        for (final toolUseId in [..._activeSubagentTasks.keys]) {
          _subagentWatches[toolUseId]?.markStopped();
          _settleSubagentTask(toolUseId, status: 'stopped');
        }
      } else if (action == 'kill' && call.acp.input['ConversationIds'] is List) {
        for (final rawId in call.acp.input['ConversationIds'] as List) {
          final convId = '$rawId'.trim();
          if (_convToSubagentToolUseId[convId] case final toolUseId?) {
            _subagentWatches[toolUseId]?.markStopped();
            _settleSubagentTask(toolUseId, status: 'stopped');
          }
        }
      }
    }
    if (call.edits) {
      unawaited(
        _hook(call.acp.failed ? 'PostToolUseFailure' : 'PostToolUse', call),
      );
    }
  }

  /// [content] is text, or Claude's blocks (an MCP tool's image).
  void _result(
    _Call call,
    Object content, {
    bool isError = false,
    Map<String, Object?>? structured,
  }) {
    final parentToolUseId = call.parentToolUseId;
    final entry = _store.append({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {
            'type': 'tool_result',
            'tool_use_id': call.claudeId,
            'content': content,
            if (isError) 'is_error': true,
          },
        ],
      },
      'parent_tool_use_id': ?parentToolUseId,
      'toolUseResult': ?structured,
    });
    _emit({
      'type': 'user',
      'message': entry['message'],
      'parent_tool_use_id': parentToolUseId,
      'uuid': entry['uuid'],
      'tool_use_result': ?structured,
    });
  }

  /// The turn is over: the calls told and not done are answered, for the
  /// conversation to stay whole (each call its result); [interrupted], as
  /// stopped.
  void _settleCalls({required bool interrupted}) {
    for (final call in _calls.values) {
      if (!call.told || call.done) continue;
      if (!interrupted && call.acp.running) continue;
      call.done = true;
      final content = interrupted
          ? 'The user interrupted this tool call.'
          : call.acp.output ?? '(no output)';
      _result(call, content, isError: interrupted);
      if (call.name == 'Bash') {
        _settleBgCommand(
          call.claudeId,
          status: interrupted ? 'stopped' : 'completed',
          summary: content,
        );
      }
    }
    if (interrupted) {
      _settleAllBgTasks(status: 'stopped');
      _calls.clear();
    }
  }

  int _plans = 0;

  void _todos(Map<String, Object?> update) {
    final call = _Call(AcpToolCall('plan_${++_plans}'))
      ..told = true
      ..done = true
      ..name = 'TodoWrite'
      ..input = claudeTodos(update);
    _assistant(_messageId(), [
      {
        'type': 'tool_use',
        'id': call.claudeId,
        'name': call.name,
        'input': call.input,
      },
    ]);
    _result(
      call,
      'Todos have been modified successfully.',
      structured: {'newTodos': call.input['todos']},
    );
  }

  // --- Closing --------------------------------------------------------------------

  bool _closed = false;

  void close() {
    if (_closed) return;
    _closed = true;
    if (identical(_running[_store.sessionId], this)) {
      _running.remove(_store.sessionId);
    }
    _idleTimer?.cancel();
    _swarmWatcher?.dispose();
    _swarmWatcher = null;
    _bgPollTimer?.cancel();
    _bgPollTimer = null;
    _stopAllSubagentWatches();
    _interrupt();
    _dropConnection();
    _kernel.failAll('Antigravity stopped');
    for (final endpoint in _endpoints) {
      unawaited(endpoint.close());
    }
    _endpoints.clear();
    if (_out.isClosed) return;
    _out
      ..add(const {'type': 'transport_exit', 'code': 0, 'stderr': ''})
      ..close();
  }
}

class _Turn {
  _Turn(this.uuid);

  final String uuid;

  /// When its last message was taken up (one folded in, see
  /// AgyTransportCore._steer): the kernel's turn from there.
  DateTime begun = DateTime.now();
  DateTime heard = DateTime.now();
  bool cancelled = false;
  bool stalled = false;

  /// The prompt it waits on: the last sent.
  Future<Map<String, Object?>>? prompt;

  /// The tool calls agy made in it, by id.
  final Set<String> calls = {};
  int? inputTokens;
  int? outputTokens;
  int cacheRead = 0;
  int cacheWrite = 0;
  int thought = 0;
}

enum _BlockKind { text, thinking }

class _Block {
  _Block(this.kind, this.id);

  final _BlockKind kind;
  final String id;
  final StringBuffer text = StringBuffer();
}

/// A tool call of agy's, and what it was told as.
class _Call {
  _Call(this.acp) : claudeId = claudeToolId(acp.id);

  final AcpToolCall acp;
  final String claudeId;

  /// Told as a tool_use; answered with its result.
  bool told = false;
  bool done = false;
  bool preHooked = false;
  String name = '';
  Map<String, Object?> input = const {};
  String? parentToolUseId;

  /// For a question asked: what the user answered, by the question.
  Map<String, String>? answers;

  /// For a tool of the app's MCP servers: what it answered (`result`).
  Map<String, Object?>? mcpResult;

  /// Whether it changes a file.
  bool get edits => acp.kind == 'edit' || name == 'Edit' || name == 'Write';
}

class _MainTranscriptEntry {
  const _MainTranscriptEntry({
    required this.stepIndex,
    required this.status,
    required this.toolName,
    required this.args,
    required this.cleanContent,
  });

  final int stepIndex;
  final String status;
  final String toolName;
  final Map<String, Object?> args;
  final String cleanContent;
}

class _BgCommandTask {
  _BgCommandTask({
    required this.taskId,
    required this.toolUseId,
    required this.description,
    this.agyTaskId,
    this.outputFile,
  });

  final String taskId;
  final String toolUseId;
  final String description;
  String? agyTaskId;
  String? outputFile;
}

class _SubagentTaskState {
  _SubagentTaskState({
    required this.toolUseId,
    required this.convId,
    required this.description,
  });

  final String toolUseId;
  final String convId;
  final String description;
  int toolUses = 0;
  int tokens = 0;
  String? lastReply;
}

/// Lightweight mtime/size poller for a single non-swarm subagent's
/// `transcript.jsonl`, automatically disposing itself once the subagent
/// finishes and stops changing for [idlePollsToStop] consecutive polls (or
/// never produces parsed steps within [missingPollsToStop] polls).
class _SubagentTranscriptWatch {
  _SubagentTranscriptWatch({
    required this.toolUseId,
    required this.convId,
    required this.file,
    required this.pollInterval,
    required this.idlePollsToStop,
    required this.missingPollsToStop,
    required this.onSteps,
    required this.onDone,
  });

  final String toolUseId;
  final String convId;
  final File file;
  final Duration pollInterval;
  final int idlePollsToStop;
  final int missingPollsToStop;
  final void Function(List<SwarmWorkerStep> steps, bool isWorking) onSteps;
  final void Function(bool forcedStopped) onDone;

  Timer? _timer;
  DateTime? _lastMtime;
  int? _lastSize;
  bool _working = true;
  bool _forcedStopped = false;
  int _unchangedPolls = 0;
  int _missingPolls = 0;
  bool _disposed = false;

  void start() {
    if (_disposed || _timer != null) return;
    poll();
    if (_disposed) return;
    _timer = Timer.periodic(pollInterval, (_) => poll());
  }

  /// Marks the subagent as cancelled/disconnected so the watcher settles after
  /// [idlePollsToStop] unchanged polls even if the last written line was
  /// mid-turn.
  void markStopped() {
    _forcedStopped = true;
    _working = false;
  }

  void poll() {
    if (_disposed) return;
    final FileStat stat;
    try {
      stat = file.statSync();
    } on FileSystemException {
      return;
    }
    if (stat.type == FileSystemEntityType.notFound) {
      _missingPolls++;
      if (_forcedStopped || _missingPolls >= missingPollsToStop) {
        _finish();
      }
      return;
    }
    if (_lastMtime == stat.modified && _lastSize == stat.size) {
      if (!_working) {
        _unchangedPolls++;
        if (_unchangedPolls >= idlePollsToStop) {
          _finish();
        }
      } else if (_missingPolls > 0) {
        // File exists but has not produced any parsed steps yet.
        _missingPolls++;
        if (_missingPolls >= missingPollsToStop) {
          _finish();
        }
      }
      return;
    }
    final String content;
    try {
      content = file.readAsStringSync();
    } on FileSystemException {
      // File may be mid-write; retry next tick.
      return;
    }
    _lastMtime = stat.modified;
    _lastSize = stat.size;
    _unchangedPolls = 0;

    final summary = summarizeWorkerTranscript(content);
    if (!summary.hasTranscript || summary.steps.isEmpty) {
      _missingPolls++;
      if (_forcedStopped || _missingPolls >= missingPollsToStop) {
        _finish();
      }
      return;
    }
    _missingPolls = 0;
    _working = !_forcedStopped && summary.isWorking;
    onSteps(summary.steps, _working);
  }

  void _finish() {
    if (_disposed) return;
    dispose();
    onDone(_forcedStopped);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
