import 'dart:convert';
import 'dart:math' as math;

import '../../chat/chat_models.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';

/// Translates Claude Code's conversation messages (stream-json output, or
/// the lines of a kept session) into [KernelEvent]s: text, thoughts, tool
/// calls and their results, subagents, tasks, todos and runtime notices.
///
/// Turns, settings and control requests are the kernel's; this only knows
/// the conversation. Items are addressed by the CLI's own ids (message id
/// and block, tool use id, message uuid), so translating a message twice,
/// e.g. streamed and then whole, lands on the same items.
class ClaudeTranslator {
  ClaudeTranslator({required this.emit, required this.nextSeq});

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// The turn changes belong to (the user message uuid that began it).
  String? turnId;

  /// What the agent is busy with out of sight (see [ActivityReported]).
  KernelActivity? _activity;

  void _report(KernelActivity? activity) {
    if (replaying || (activity == null && _activity == null)) return;
    _activity = activity;
    emit(ActivityReported(nextSeq(), activity));
  }

  /// A turn was sent: the agent is at work from now, before the CLI says so.
  void begin() {
    _interruptShown = null;
    _report(_waiting());
  }

  /// The "Interrupted" notice, while nothing has come after it: a stop
  /// that cut several requests short shows once.
  String? _interruptShown;

  KernelActivity _waiting() =>
      KernelActivity(KernelActivityKind.waiting, DateTime.now());

  /// Replaying a kept session: nothing is pending or running any more.
  bool replaying = false;

  // Streamed blocks of the current message.
  String? _messageId;
  final Map<int, String> _streamed = {};

  /// Since when the model has been at the next block: its message's start,
  /// else the last block's end.
  DateTime? _blockSince;

  /// Streamed text and thought blocks, per message and kind, in order,
  /// until the whole message claims them.
  final Map<String, List<String>> _unclaimed = {};

  /// The item each block of a whole message landed on, by the message's
  /// uuid and the block's place: delivered again, it lands there again.
  final Map<String, String> _blockIds = {};
  final Map<String, StringBuffer> _thoughts = {};
  final Map<String, DateTime> _thinkingStarted = {};
  final Map<String, int> _thinkingTokens = {};
  final Map<String, int> _textLength = {};

  final Map<String, _Tool> _tools = {};
  final Map<String, _Agent> _agents = {};
  final Set<String> _denied = {};

  final Map<String, KernelTask> _tasks = {};
  final Map<String, TodoEntry> _todos = {};

  void translate(Map<String, Object?> message) {
    final parent = message['parent_tool_use_id'] as String?;
    switch (message['type']) {
      case 'stream_event' when parent == null:
        _streamEvent(_map(message['event']));
      case 'assistant':
        _assistant(message, parent);
      case 'user':
        _user(message, parent);
      case 'system':
        _system(message);
    }
  }

  /// Settles whatever still streams, e.g. when the turn is interrupted.
  void settle() {
    for (final id in [..._thoughts.keys]) {
      _completeThought(id, null);
    }
    for (final id in [..._textLength.keys]) {
      _textLength.remove(id);
      emit(ItemCompleted(nextSeq(), id));
    }
    _streamed.clear();
    _activity = null;
  }

  // --- Items -------------------------------------------------------------------

  static const _interrupted = NoticeItem(NoticeKind.info, 'Interrupted');

  /// Adds or replaces [id], at the top level or in the subagent [parent].
  void _put(
    String id,
    ChatItem item, {
    String? parent,
    bool streaming = false,
  }) {
    if (parent != null) {
      final agent = _agents[parent];
      if (agent == null) return; // A subagent's message we cannot place.
      agent.children[id] = item;
      _putAgent(parent);
      return;
    }
    _interruptShown = item == _interrupted ? id : null;
    emit(ItemUpserted(nextSeq(), id, item, streaming: streaming));
  }

  void _putAgent(String id) {
    final agent = _agents[id]!;
    agent.item = agent.item.copyWith(children: [...agent.children.values]);
    _put(id, agent.item, parent: _tools[id]?.parent);
  }

  // --- Streaming ---------------------------------------------------------------

  void _streamEvent(Map<String, Object?> event) {
    switch (event['type']) {
      case 'message_start':
        _messageId = _map(event['message'])['id'] as String?;
        _streamed.clear();
        _blockSince = DateTime.now();
      case 'content_block_start':
        final index = event['index'] as int;
        final block = _map(event['content_block']);
        final id = '$_messageId:$index';
        switch (block['type']) {
          case 'thinking' || 'redacted_thinking':
            _streamed[index] = id;
            (_unclaimed['$_messageId:thinking'] ??= []).add(id);
            _thoughts[id] = StringBuffer();
            // A proxy may hold a whole thought back until it is done.
            _thinkingStarted[id] = _blockSince ?? DateTime.now();
            _put(
              id,
              ThinkingItem(
                text: '',
                tokens: 0,
                startedAt: _thinkingStarted[id],
              ),
              streaming: true,
            );
          case 'text':
            _streamed[index] = id;
            (_unclaimed['$_messageId:text'] ??= []).add(id);
            _textLength[id] = 0;
            _put(id, const AssistantTextItem(''), streaming: true);
          case 'tool_use':
            final toolId = block['id'] as String;
            final name = block['name'] as String;
            if (!_tools.containsKey(toolId)) {
              _toolUse(toolId, name, const {}, null);
            }
          default:
            return;
        }
        // The model answers: what it does shows from here. Not from its
        // message's start, which a proxy may send minutes before the first
        // block (holding back a thought until it is done).
        _report(null);
      case 'content_block_delta':
        final id = _streamed[event['index']];
        if (id == null) return;
        final delta = _map(event['delta']);
        switch (delta['type']) {
          case 'thinking_delta':
            final thought = _thoughts[id];
            if (thought == null) return;
            final text = delta['thinking'] as String? ?? '';
            final offset = thought.length;
            thought.write(text);
            emit(
              TextDelta(
                nextSeq(),
                id,
                offset,
                text,
                tokens: math.max(_thinkingTokens[id] ?? 0, thought.length ~/ 4),
              ),
            );
          case 'text_delta':
            final offset = _textLength[id];
            if (offset == null) return;
            final text = delta['text'] as String? ?? '';
            _textLength[id] = offset + text.length;
            emit(TextDelta(nextSeq(), id, offset, text));
        }
      case 'content_block_stop':
        _blockSince = DateTime.now();
        final id = _streamed.remove(event['index']);
        if (id == null) return;
        if (_thoughts.containsKey(id)) {
          _completeThought(id, null);
        } else if (_textLength.remove(id) != null) {
          emit(ItemCompleted(nextSeq(), id));
        }
    }
  }

  void _completeThought(String id, String? whole) {
    final streamed = _thoughts.remove(id)?.toString() ?? '';
    final started = _thinkingStarted.remove(id);
    final text = (whole == null || whole.isEmpty) ? streamed : whole;
    final tokens = math.max(_thinkingTokens.remove(id) ?? 0, text.length ~/ 4);
    emit(
      ItemCompleted(
        nextSeq(),
        id,
        item: ThinkingItem(
          text: text,
          tokens: tokens,
          seconds: math.max(
            1,
            started == null
                ? 0
                : (DateTime.now().difference(started).inMilliseconds / 1000)
                      .round(),
          ),
        ),
      ),
    );
  }

  // --- Whole messages -----------------------------------------------------------

  void _assistant(Map<String, Object?> message, String? parent) {
    final body = _map(message['message']);
    final messageId = body['id'] as String? ?? '${message['uuid']}';
    final eventId = message['uuid'] as String? ?? messageId;
    final synthetic = body['model'] == '<synthetic>';
    for (final (index, raw) in _list(body['content']).indexed) {
      final block = _map(raw);
      final kind = block['type'] == 'text' ? 'text' : 'thinking';
      final key = '$eventId:$index';
      final id = _blockIds[key] ??= switch (_unclaimed['$messageId:$kind']) {
        final ids? when ids.isNotEmpty => ids.removeAt(0),
        _ => key,
      };
      switch (block['type']) {
        case 'text':
          final text = block['text'] as String? ?? '';
          if (synthetic) {
            if (text.isNotEmpty) {
              _put(id, NoticeItem(NoticeKind.command, text), parent: parent);
            }
          } else if (_textLength.remove(id) != null) {
            emit(ItemCompleted(nextSeq(), id, item: AssistantTextItem(text)));
          } else if (text.trim().isNotEmpty) {
            _put(id, AssistantTextItem(text), parent: parent);
          }
        case 'thinking' || 'redacted_thinking':
          final text = block['thinking'] as String? ?? '';
          if (_thoughts.containsKey(id)) {
            _completeThought(id, text);
          } else if (parent == null && text.trim().isNotEmpty) {
            _put(
              id,
              ThinkingItem(text: text, tokens: text.length ~/ 4, seconds: 1),
            );
          }
        case 'tool_use':
          _toolUse(
            block['id'] as String,
            block['name'] as String,
            _map(block['input']),
            parent,
          );
      }
    }
  }

  void _user(Map<String, Object?> message, String? parent) {
    final body = _map(message['message']);
    final content = body['content'];
    final result = message['tool_use_result'] ?? message['toolUseResult'];
    if (content is String) {
      _prompt(message, content, parent);
      return;
    }
    final texts = <String>[];
    final images = <ImageAttachment>[];
    for (final raw in _list(content)) {
      final block = _map(raw);
      switch (block['type']) {
        case 'tool_result':
          _toolResult(block, result);
        case 'text':
          final text = block['text'] as String? ?? '';
          // A note for the model sent along (e.g. by the host), not typed.
          if (text.trimLeft().startsWith('<system-reminder>')) continue;
          texts.add(text);
        case 'image':
          if (_image(_map(block['source'])) case final image?) {
            images.add(image);
          }
      }
    }
    if (texts.isNotEmpty || images.isNotEmpty) {
      _prompt(message, texts.join('\n'), parent, images: images);
    }
  }

  static ImageAttachment? _image(Map<String, Object?> source) {
    if (source['type'] != 'base64') return null;
    try {
      return ImageAttachment(
        bytes: base64Decode(source['data'] as String? ?? ''),
        mediaType: source['media_type'] as String? ?? 'image/png',
      );
    } on FormatException {
      return null;
    }
  }

  /// A message the user sent (or the CLI sent for them).
  void _prompt(
    Map<String, Object?> message,
    String text,
    String? parent, {
    List<ImageAttachment> images = const [],
  }) {
    if (parent != null || message['isMeta'] == true) return;
    final id = message['uuid'] as String?;
    if (id == null) return;
    final trimmed = text.trim();
    if (trimmed.startsWith('<task-notification>')) {
      _agentNotified(trimmed);
      return;
    }
    // Written by the CLI, not typed: e.g. the summary a compacted
    // conversation goes on from. Live it is marked synthetic; kept, by
    // what it is.
    if (message['isSynthetic'] == true ||
        message['isCompactSummary'] == true ||
        message['isVisibleInTranscriptOnly'] == true) {
      return;
    }
    if (trimmed.startsWith('<local-command-caveat>') ||
        trimmed.startsWith('<system-reminder>')) {
      return;
    }
    if (trimmed.contains('<command-name>')) {
      final name = _tag(trimmed, 'command-name') ?? '';
      final args = _tag(trimmed, 'command-args') ?? '';
      final command = name.startsWith('/') ? name : '/$name';
      _put(
        id,
        UserMessageItem(text: args.isEmpty ? command : '$command $args'),
      );
      return;
    }
    if (_tag(trimmed, 'local-command-stdout') case final output?) {
      if (output.trim().isNotEmpty) {
        _put(id, NoticeItem(NoticeKind.command, output.trim()));
      }
      return;
    }
    if (trimmed.startsWith('[Request interrupted by user')) {
      final shown = _interruptShown;
      if (shown == null || shown == id) _put(id, _interrupted);
      return;
    }
    _put(id, UserMessageItem(text: trimmed, images: images));
  }

  // --- Tools ----------------------------------------------------------------------

  void _toolUse(
    String id,
    String name,
    Map<String, Object?> input,
    String? parent,
  ) {
    final known = _tools[id];
    // The streamed start has no input yet; the whole message fills it in.
    final tool = _Tool(name, input, known?.parent ?? parent, known?.startedAt);
    _tools[id] = tool;
    switch (name) {
      case 'Agent' || 'Task':
        final agent = _agents[id] ??= _Agent(
          AgentItem(
            description: _string(input['description']) ?? 'Subagent',
            id: id,
            agentType: _string(input['subagent_type']),
            prompt: _string(input['prompt']),
            status: replaying ? CommandStatus.succeeded : CommandStatus.running,
            startedAt: replaying ? null : tool.startedAt,
            background: input['run_in_background'] == true,
          ),
        );
        // The streamed start has no input: the whole message fills it in.
        if (agent.item.description == 'Subagent' || agent.item.prompt == null) {
          agent.item = agent.item.copyWith(
            description: _string(input['description']),
            agentType: _string(input['subagent_type']),
            prompt: _string(input['prompt']),
          );
        }
        _putAgent(id);
        return;
      case 'TodoWrite':
        if (input['todos'] case final List<Object?> todos) {
          _todos
            ..clear()
            ..addEntries([
              for (final (i, raw) in todos.indexed)
                MapEntry('$i', _todo(_map(raw))),
            ]);
          _reportTodos();
        }
      case 'TaskCreate' when input['subject'] != null:
        _todos[id] = TodoEntry(
          input['subject'] as String,
          TodoStatus.pending,
          activeForm: _string(input['activeForm']),
        );
        _reportTodos();
      case 'TaskUpdate':
        final key = _string(input['taskId']);
        final entry = key == null ? null : _todos[key];
        if (key != null && entry != null) {
          if (input['status'] == 'deleted') {
            _todos.remove(key);
          } else {
            _todos[key] = TodoEntry(
              _string(input['subject']) ?? entry.content,
              _todoStatus(input['status']) ?? entry.status,
              activeForm: _string(input['activeForm']) ?? entry.activeForm,
            );
          }
          _reportTodos();
        }
      case 'ExitPlanMode':
        if (_string(input['plan']) case final plan?) {
          _put(id, AssistantTextItem(plan), parent: tool.parent);
          return;
        }
    }
    _put(
      id,
      _toolItem(tool, replaying ? _Outcome.done : _Outcome.running),
      parent: tool.parent,
    );
  }

  ChatItem _toolItem(_Tool tool, _Outcome outcome, {String? output}) {
    final input = tool.input;
    final status = switch (outcome) {
      _Outcome.running => ToolStatus.running,
      _Outcome.done => ToolStatus.succeeded,
      _Outcome.failed => ToolStatus.failed,
      _Outcome.denied => ToolStatus.denied,
    };
    // What it did, or does while it runs.
    String tense(String done, String doing) =>
        outcome == _Outcome.running ? doing : done;
    String? path(String key) => _string(input[key]);
    String base(String? path) => path == null ? '' : path.split('/').last;
    final name = tool.name;
    if (name.startsWith('mcp__')) {
      final parts = name.split('__');
      return ToolCallItem(
        kind: ToolKind.mcp,
        label: parts.length > 2
            ? '${parts[1]} · ${parts.sublist(2).join('__')}'
            : name,
        target: _summary(input),
        status: status,
        output: output,
      );
    }
    return switch (name) {
      'Read' => ToolCallItem(
        kind: ToolKind.read,
        target: base(path('file_path')),
        path: path('file_path'),
        detail: switch ((input['offset'], input['limit'])) {
          (final int offset, final int limit) => 'L$offset-${offset + limit}',
          _ => null,
        },
        status: status,
        output: outcome == _Outcome.done ? null : output,
      ),
      'Grep' => ToolCallItem(
        kind: ToolKind.grep,
        target: _string(input['pattern']) ?? '',
        status: status,
        output: output,
      ),
      'Glob' => ToolCallItem(
        kind: ToolKind.search,
        label: tense('Globbed', 'Globbing'),
        target: _string(input['pattern']) ?? '',
        status: status,
        output: output,
      ),
      'LS' => ToolCallItem(
        kind: ToolKind.listDir,
        target: base(path('path')),
        path: path('path'),
        status: status,
      ),
      'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit' => ToolCallItem(
        kind: ToolKind.edit,
        label: name == 'Write'
            ? tense('Wrote', 'Writing')
            : tense('Edited', 'Editing'),
        target: base(path('file_path') ?? path('notebook_path')),
        path: path('file_path') ?? path('notebook_path'),
        status: status,
        output: output,
      ),
      'Bash' => TerminalItem(
        command: _string(input['command']) ?? '',
        description: _string(input['description']),
        output: output ?? '',
        status: switch (outcome) {
          _Outcome.running => CommandStatus.running,
          _Outcome.done => CommandStatus.succeeded,
          _ => CommandStatus.failed,
        },
        background: input['run_in_background'] == true,
        startedAt: tool.startedAt,
      ),
      'BashOutput' || 'TaskOutput' => ToolCallItem(
        kind: ToolKind.command,
        label: tense('Read output', 'Reading output'),
        target: _summary(input),
        status: status,
      ),
      'KillShell' || 'KillBash' || 'TaskStop' => ToolCallItem(
        kind: ToolKind.command,
        label: tense('Stopped', 'Stopping'),
        target: _summary(input),
        status: status,
      ),
      'WebFetch' => ToolCallItem(
        kind: ToolKind.web,
        label: tense('Fetched', 'Fetching'),
        target: _string(input['url']) ?? '',
        status: status,
        output: output,
      ),
      'WebSearch' => ToolCallItem(
        kind: ToolKind.web,
        label: tense('Searched the web', 'Searching the web'),
        target: _string(input['query']) ?? '',
        status: status,
        output: output,
      ),
      'Skill' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Used skill', 'Using skill'),
        target: _string(input['skill']) ?? _string(input['command']) ?? '',
        status: status,
      ),
      'ToolSearch' => ToolCallItem(
        kind: ToolKind.search,
        label: tense('Looked up tools', 'Looking up tools'),
        target: _string(input['query']) ?? '',
        status: status,
      ),
      'TodoWrite' ||
      'TaskCreate' ||
      'TaskUpdate' ||
      'TaskList' ||
      'TaskGet' => ToolCallItem(
        kind: ToolKind.todo,
        label: tense('Updated todos', 'Updating todos'),
        target: _string(input['subject']) ?? '',
        status: status,
      ),
      'AskUserQuestion' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Asked', 'Asking'),
        target: [
          for (final q in _list(input['questions']))
            _string(_map(q)['header']) ?? _string(_map(q)['question']) ?? '',
        ].join(' · '),
        status: status,
        output: output,
      ),
      'SendMessage' => ToolCallItem(
        kind: ToolKind.message,
        label: name,
        target: _summary(input),
        status: status,
        output: output,
      ),
      'EnterPlanMode' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Entered plan mode', 'Entering plan mode'),
        target: '',
        status: status,
      ),
      'ExitPlanMode' => ToolCallItem(
        kind: ToolKind.other,
        label: tense('Proposed a plan', 'Proposing a plan'),
        target: '',
        status: status,
      ),
      _ => ToolCallItem(
        kind: ToolKind.other,
        label: name,
        target: _summary(input),
        status: status,
        output: output,
      ),
    };
  }

  void _toolResult(Map<String, Object?> block, Object? result) {
    final id = block['tool_use_id'] as String?;
    final tool = id == null ? null : _tools[id];
    if (id == null || tool == null) return;
    final error = block['is_error'] == true;
    final text = _resultText(block['content']);
    final structured = result is Map ? result.cast<String, Object?>() : null;
    final outcome = _denied.contains(id)
        ? _Outcome.denied
        : error
        ? _Outcome.failed
        : _Outcome.done;
    switch (tool.name) {
      case 'Agent' || 'Task':
        final agent = _agents[id];
        if (agent == null) return;
        if (structured?['status'] == 'async_launched') {
          // Launched in the background: what it says is for the agent (its
          // id, where its output goes). It reports in a notification.
          agent.item = agent.item.copyWith(
            prompt: _string(structured?['prompt']),
            model: _string(structured?['resolvedModel']),
            background: true,
          );
          _putAgent(id);
          return;
        }
        agent.item = agent.item.copyWith(
          status: outcome == _Outcome.done
              ? CommandStatus.succeeded
              : CommandStatus.failed,
          result: _agentReport(structured, text),
          prompt: _string(structured?['prompt']),
          tokens: structured?['totalTokens'] as int?,
          toolUses: structured?['totalToolUseCount'] as int?,
          duration: switch (structured?['totalDurationMs']) {
            final int ms => Duration(milliseconds: ms),
            _ => null,
          },
          model: _string(structured?['resolvedModel']),
        );
        _putAgent(id);
        return;
      case 'Edit' || 'MultiEdit' || 'Write' || 'NotebookEdit'
          when outcome == _Outcome.done && structured != null:
        if (_diff(id, tool, structured)) return;
      case 'Grep' || 'Glob' when outcome == _Outcome.done:
        final matches = _matches(tool.name, structured, text);
        final item = _toolItem(tool, outcome) as ToolCallItem;
        _put(
          id,
          ToolCallItem(
            kind: item.kind,
            label: item.label,
            target: item.target,
            detail:
                '${matches.length} ${tool.name == 'Glob' ? 'files' : 'results'}',
            results: matches,
            status: item.status,
          ),
          parent: tool.parent,
        );
        return;
      case 'Bash':
        final taskId = structured?['backgroundTaskId'] as String?;
        if (taskId != null && !replaying) {
          _put(
            id,
            TerminalItem(
              command: _string(tool.input['command']) ?? '',
              description: _string(tool.input['description']),
              output: 'Running in the background ($taskId)…',
              status: CommandStatus.running,
              background: true,
              startedAt: tool.startedAt,
            ),
            parent: tool.parent,
          );
          return;
        }
        final stdout = _string(structured?['stdout']) ?? '';
        final stderr = _string(structured?['stderr']) ?? '';
        final output = structured == null
            ? text
            : [stdout, stderr].where((s) => s.isNotEmpty).join('\n');
        final interrupted = structured?['interrupted'] == true;
        _put(
          id,
          _toolItem(
            tool,
            interrupted ? _Outcome.failed : outcome,
            output: _tail(output),
          ),
          parent: tool.parent,
        );
        return;
      case 'ExitPlanMode':
        if (_string(tool.input['plan']) != null) return;
      case 'TaskCreate':
        if (structured?['task'] case final Map<Object?, Object?> task) {
          final entry = _todos.remove(id);
          if (entry != null) _todos['${task['id']}'] = entry;
        }
    }
    _put(
      id,
      _toolItem(
        tool,
        outcome,
        output: outcome == _Outcome.done ? _short(text) : _tail(text),
      ),
      parent: tool.parent,
    );
  }

  /// An edit's result as a diff card and a pending change; false when it
  /// carries no patch to show.
  bool _diff(String id, _Tool tool, Map<String, Object?> result) {
    final path =
        _string(result['filePath']) ??
        _string(tool.input['file_path']) ??
        _string(tool.input['notebook_path']);
    if (path == null) return false;
    final lines = <DiffLine>[];
    var added = 0;
    var removed = 0;
    final hunks = _list(result['structuredPatch']);
    if (hunks.isEmpty && tool.name == 'NotebookEdit') {
      // A notebook edit tells the cell's source before and after, not a
      // patch (the file is JSON): its lines, compared.
      String source(String key) => _string(result[key]) ?? '';
      for (final line in _lineDiff(
        source('old_source'),
        source('new_source'),
      )) {
        switch (line.type) {
          case DiffLineType.added:
            added++;
          case DiffLineType.removed:
            removed++;
          case DiffLineType.context:
        }
        if (lines.length < _maxDiffLines) lines.add(line);
      }
    } else if (hunks.isEmpty && result['type'] == 'create') {
      final content = _string(result['content']) ?? '';
      final created = content.isEmpty ? <String>[] : content.split('\n');
      for (final (i, line) in created.take(_maxDiffLines).indexed) {
        lines.add(DiffLine(DiffLineType.added, i + 1, line));
      }
      added = created.length;
    } else {
      for (final raw in hunks) {
        final hunk = _map(raw);
        var oldLine = hunk['oldStart'] as int? ?? 1;
        var newLine = hunk['newStart'] as int? ?? 1;
        for (final line in _list(hunk['lines']).whereType<String>()) {
          if (line.isEmpty) continue;
          final text = line.substring(1);
          switch (line[0]) {
            case '+':
              added++;
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.added, newLine, text));
              }
              newLine++;
            case '-':
              removed++;
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.removed, oldLine, text));
              }
              oldLine++;
            case '\\':
              break;
            default:
              if (lines.length < _maxDiffLines) {
                lines.add(DiffLine(DiffLineType.context, newLine, text));
              }
              oldLine++;
              newLine++;
          }
        }
      }
    }
    if (lines.isEmpty) return false;
    final slash = path.lastIndexOf('/');
    _put(
      id,
      CodeDiffItem(
        fileName: path.substring(slash + 1),
        directory: slash < 0 ? '' : path.substring(0, slash),
        lines: lines,
        added: added,
        removed: removed,
      ),
      parent: tool.parent,
    );
    if (!replaying && tool.parent == null) {
      emit(
        FileEdited(
          nextSeq(),
          FileChange(path: path, added: added, removed: removed),
          turnId: turnId,
        ),
      );
    }
    return true;
  }

  static const _maxDiffLines = 400;

  /// [before] to [after], line by line: kept lines as context, numbered as
  /// in the text they are from. Past a size, all of one replaced by the
  /// other.
  static List<DiffLine> _lineDiff(String before, String after) {
    List<String> split(String text) => text.isEmpty ? [] : text.split('\n');
    final a = split(before);
    final b = split(after);
    // The longest common subsequence, from the end.
    final common = a.length * b.length <= 250000
        ? List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0))
        : null;
    if (common != null) {
      for (var i = a.length - 1; i >= 0; i--) {
        for (var j = b.length - 1; j >= 0; j--) {
          common[i][j] = a[i] == b[j]
              ? common[i + 1][j + 1] + 1
              : math.max(common[i + 1][j], common[i][j + 1]);
        }
      }
    }
    final lines = <DiffLine>[];
    var i = 0;
    var j = 0;
    while (i < a.length || j < b.length) {
      if (common != null && i < a.length && j < b.length && a[i] == b[j]) {
        lines.add(DiffLine(DiffLineType.context, j + 1, b[j]));
        i++;
        j++;
      } else if (i < a.length &&
          (j == b.length ||
              common == null ||
              common[i + 1][j] >= common[i][j + 1])) {
        lines.add(DiffLine(DiffLineType.removed, i + 1, a[i]));
        i++;
      } else {
        lines.add(DiffLine(DiffLineType.added, j + 1, b[j]));
        j++;
      }
    }
    return lines;
  }

  // --- Runtime messages ------------------------------------------------------------

  void _system(Map<String, Object?> message) {
    final uuid = message['uuid'] as String? ?? '${nextSeq()}';
    switch (message['subtype']) {
      // A request to the model is out (until its answer starts), or the
      // conversation is being compacted (until the status clears).
      case 'status':
        switch (message['status']) {
          // Still waiting since the turn was sent: keep its clock.
          case 'requesting' when _activity?.kind != KernelActivityKind.waiting:
            _report(_waiting());
          case 'compacting':
            _report(
              KernelActivity(KernelActivityKind.compacting, DateTime.now()),
            );
          case null when _activity?.kind == KernelActivityKind.compacting:
            _report(null);
        }
      case 'compact_boundary':
        if (_activity?.kind == KernelActivityKind.compacting) _report(null);
        final meta = _map(message['compact_metadata']);
        final before = meta['pre_tokens'] as int?;
        final after = meta['post_tokens'] as int?;
        _put(
          uuid,
          NoticeItem(
            NoticeKind.compaction,
            [
              meta['trigger'] == 'auto'
                  ? 'Conversation compacted automatically'
                  : 'Conversation compacted',
              if (before != null)
                '${_tokens(before)}${after == null ? '' : ' → ${_tokens(after)}'} tokens',
            ].join(' · '),
          ),
        );
      case 'api_retry' when !replaying:
        final attempt = message['attempt'];
        final max = message['max_retries'];
        final delay = ((message['retry_delay_ms'] as int? ?? 0) / 1000).ceil();
        final status = message['error_status'];
        _put(
          'retry:$turnId',
          NoticeItem(
            NoticeKind.retry,
            'Request failed${status == null ? '' : ' ($status)'}; '
            'retrying in ${delay}s (attempt $attempt of $max)',
          ),
        );
      case 'informational':
        final level = message['level'];
        final content = _string(message['content']);
        if (level == 'info' || content == null || content.isEmpty) return;
        _put(
          uuid,
          NoticeItem(
            level == 'warning' ? NoticeKind.warning : NoticeKind.info,
            content,
          ),
        );
      case 'notification' when !replaying:
        if (_string(message['text']) case final text? when text.isNotEmpty) {
          _put(
            'notification:${message['key'] ?? uuid}',
            NoticeItem(NoticeKind.info, text),
          );
        }
      case 'local_command_output':
        if (_string(message['content']) case final text? when text.isNotEmpty) {
          _put(uuid, NoticeItem(NoticeKind.command, text));
        }
      case 'permission_denied':
        final id = message['tool_use_id'] as String?;
        final tool = id == null ? null : _tools[id];
        if (id == null || tool == null) return;
        _denied.add(id);
        _put(id, _toolItem(tool, _Outcome.denied), parent: tool.parent);
      case 'thinking_tokens':
        final estimate = message['estimated_tokens'] as int?;
        final id = _thoughts.keys.lastOrNull;
        if (estimate == null || id == null) return;
        _thinkingTokens[id] = estimate;
        emit(
          ItemUpserted(
            nextSeq(),
            id,
            ThinkingItem(
              text: _thoughts[id].toString(),
              tokens: estimate,
              startedAt: _thinkingStarted[id],
            ),
            streaming: true,
          ),
        );
      case 'task_started' when !replaying:
        final taskId = message['task_id'] as String;
        final agent = message['task_type'] == 'local_agent';
        _tasks[taskId] = KernelTask(
          id: taskId,
          description: _string(message['description']) ?? '',
          kind: agent
              ? KernelTaskKind.agent
              : message['task_type'] == 'local_bash'
              ? KernelTaskKind.command
              : KernelTaskKind.other,
          status: CommandStatus.running,
          startedAt: DateTime.now(),
          toolUseId: message['tool_use_id'] as String?,
          background: message['is_backgrounded'] == true,
        );
        _reportTasks();
        if (message['is_backgrounded'] == true) {
          _agentToBackground(message['tool_use_id'] as String?);
        }
      case 'task_progress' when !replaying:
        final taskId = message['task_id'] as String;
        final usage = _map(message['usage']);
        final summary =
            _string(message['summary']) ?? _string(message['description']);
        if (_tasks[taskId] case final task?) {
          _tasks[taskId] = task.copyWith(summary: summary);
          _reportTasks();
        }
        final toolUseId = message['tool_use_id'] as String?;
        final agent = toolUseId == null ? null : _agents[toolUseId];
        if (agent != null) {
          agent.item = agent.item.copyWith(
            tokens: usage['total_tokens'] as int?,
            toolUses: usage['tool_uses'] as int?,
            lastTool: _string(message['last_tool_name']),
            activity: _string(message['description']),
          );
          _putAgent(toolUseId!);
        }
      case 'task_updated' when !replaying:
        final taskId = message['task_id'] as String;
        final patch = _map(message['patch']);
        if (_tasks[taskId] case final task?) {
          _tasks[taskId] = task.copyWith(
            status: _taskStatus(patch['status']) ?? task.status,
            background: patch['is_backgrounded'] as bool?,
            description: _string(patch['description']),
            summary: _string(patch['error']),
          );
          _reportTasks();
          if (patch['is_backgrounded'] == true) {
            _agentToBackground(task.toolUseId);
          }
        }
      case 'task_notification' when !replaying:
        final taskId = message['task_id'] as String;
        final status =
            _taskStatus(message['status']) ?? CommandStatus.succeeded;
        final summary = _string(message['summary']);
        if (_tasks[taskId] case final task?) {
          _tasks[taskId] = task.copyWith(status: status, summary: summary);
          _reportTasks();
        }
        // A background command's row in the history settles too, and a
        // subagent's card (its report comes in the notification to the
        // agent, see _agentNotified).
        final toolUseId = message['tool_use_id'] as String?;
        final tool = toolUseId == null ? null : _tools[toolUseId];
        if (_agents[toolUseId] case final agent?) {
          final usage = _map(message['usage']);
          agent.item = agent.item.copyWith(
            status: status,
            tokens: usage['total_tokens'] as int?,
            toolUses: usage['tool_uses'] as int?,
            duration: switch (usage['duration_ms']) {
              final int ms => Duration(milliseconds: ms),
              _ => null,
            },
          );
          _putAgent(toolUseId!);
        }
        if (tool != null && tool.name == 'Bash') {
          _put(
            toolUseId!,
            TerminalItem(
              command: _string(tool.input['command']) ?? '',
              description: _string(tool.input['description']),
              output: summary ?? '',
              status: status,
              background: true,
              startedAt: tool.startedAt,
            ),
            parent: tool.parent,
          );
        }
      case 'background_tasks_changed' when !replaying:
        final live = {
          for (final raw in _list(message['tasks']))
            _map(raw)['task_id'] as String,
        };
        var changed = false;
        for (final id in live) {
          final task = _tasks[id];
          if (task != null && !task.background) {
            _tasks[id] = task.copyWith(background: true);
            _agentToBackground(task.toolUseId);
            changed = true;
          }
        }
        if (changed) _reportTasks();
    }
  }

  /// The subagent [toolUseId] started, if one did, now runs on its own.
  void _agentToBackground(String? toolUseId) {
    final agent = toolUseId == null ? null : _agents[toolUseId];
    if (agent == null || agent.item.background) return;
    agent.item = agent.item.copyWith(background: true);
    _putAgent(toolUseId!);
  }

  void _reportTasks() => emit(TasksReported(nextSeq(), [..._tasks.values]));

  void _reportTodos() => emit(TodosReported(nextSeq(), [..._todos.values]));

  // --- Helpers ------------------------------------------------------------------------

  static Map<String, Object?> _map(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

  static List<Object?> _list(Object? value) =>
      value is List ? value.cast<Object?>() : const [];

  static String? _string(Object? value) => value is String ? value : null;

  /// A background subagent stopped, as the CLI tells its agent: how, and
  /// its report.
  void _agentNotified(String notification) {
    final id = _tag(notification, 'tool-use-id');
    final agent = id == null ? null : _agents[id];
    if (agent == null) return;
    final status = _taskStatus(_tag(notification, 'status'));
    final failed = status == CommandStatus.failed;
    agent.item = agent.item.copyWith(
      status: status,
      result:
          _tag(notification, 'result')?.trim() ??
          (failed ? _tag(notification, 'summary') : null),
    );
    _putAgent(id!);
  }

  static String? _tag(String text, String tag) {
    final start = text.indexOf('<$tag>');
    final end = text.indexOf('</$tag>');
    if (start < 0 || end < start) return null;
    return text.substring(start + tag.length + 2, end);
  }

  static String _resultText(Object? content) => switch (content) {
    final String text => text,
    final List<Object?> blocks => [
      for (final block in blocks)
        if (_map(block)['text'] case final String text) text,
    ].join('\n'),
    _ => '',
  };

  static String _summary(Map<String, Object?> input) {
    for (final value in input.values) {
      if (value is String && value.trim().isNotEmpty) {
        final line = value.trim().split('\n').first;
        return line.length > 80 ? '${line.substring(0, 80)}…' : line;
      }
    }
    return input.isEmpty ? '' : _short(jsonEncode(input)) ?? '';
  }

  static String? _short(String text) {
    if (text.isEmpty) return null;
    return text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
  }

  /// The end of a long output, where errors are.
  static String _tail(String text) {
    const max = 4000;
    if (text.length <= max) return text;
    return '…${text.substring(text.length - max)}';
  }

  static List<String> _matches(
    String tool,
    Map<String, Object?>? result,
    String text,
  ) {
    if (tool == 'Glob') {
      final names = _list(result?['filenames']).whereType<String>();
      if (names.isNotEmpty) return names.toList();
    }
    return [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty &&
            !line.startsWith('Found ') &&
            !line.startsWith('No files found') &&
            !line.startsWith('No matches'))
          line.split(':').take(2).join(':'),
    ];
  }

  static String? _agentReport(Map<String, Object?>? result, String text) {
    final content = _resultText(result?['content']);
    final report = content.isNotEmpty ? content : text;
    return report.isEmpty ? null : report;
  }

  static TodoEntry _todo(Map<String, Object?> raw) => TodoEntry(
    _string(raw['content']) ?? '',
    _todoStatus(raw['status']) ?? TodoStatus.pending,
    activeForm: _string(raw['activeForm']),
  );

  static TodoStatus? _todoStatus(Object? status) => switch (status) {
    'pending' => TodoStatus.pending,
    'in_progress' => TodoStatus.inProgress,
    'completed' => TodoStatus.completed,
    _ => null,
  };

  static CommandStatus? _taskStatus(Object? status) => switch (status) {
    'running' || 'pending' => CommandStatus.running,
    'completed' => CommandStatus.succeeded,
    'failed' || 'killed' || 'stopped' => CommandStatus.failed,
    _ => null,
  };

  static String _tokens(int tokens) =>
      tokens >= 1000 ? '${(tokens / 1000).toStringAsFixed(1)}k' : '$tokens';
}

enum _Outcome { running, done, failed, denied }

class _Tool {
  _Tool(this.name, this.input, this.parent, DateTime? startedAt)
    : startedAt = startedAt ?? DateTime.now();

  final String name;
  final Map<String, Object?> input;

  /// The subagent's tool use id, for a subagent's tool.
  final String? parent;
  final DateTime startedAt;
}

class _Agent {
  _Agent(this.item);

  AgentItem item;
  final Map<String, ChatItem> children = {};
}
