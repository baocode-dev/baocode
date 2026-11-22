import 'dart:math' as math;

import '../../chat/chat_models.dart';
import '../claude_code/claude_sdk_tools.dart';
import '../kernel_event.dart';
import '../kernel_types.dart';
import '../line_diff.dart';

/// Turns what `agy acp` reports of a session (`session/update`) into the
/// kernel's events: its messages, thoughts and tool calls as items, its
/// edits as changes to review.
class AntigravityTranslator {
  AntigravityTranslator({required this.emit, required this.nextSeq});

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// The turn its edits are made in.
  String? turnId;

  /// Whether what comes is the conversation read back (`session/load`):
  /// its edits were reviewed then, not now.
  bool replaying = false;

  int _items = 0;
  String _newId(String kind) => 'agy-$kind-${++_items}';

  /// The text or thought being written, until something else comes.
  _Open? _open;

  /// The user's message being read back, chunk by chunk.
  String? _userId;
  final StringBuffer _user = StringBuffer();

  final Map<String, _ToolCall> _tools = {};

  /// The background tasks the commands left running, by task id.
  final Map<String, KernelTask> tasks = {};

  /// The subagents started, by the tool call that started them.
  final Map<String, AgentItem> agents = {};

  /// Called as a command goes on in the background ([tasks] changed), or
  /// a subagent starts ([agents]).
  void Function()? onTasksChanged;

  /// Whether a call is under way.
  bool get calling => _tools.values.any((tool) => tool.running);

  // --- Updates ---------------------------------------------------------------------

  /// Applies one `session/update`'s `update`.
  void update(Map<String, Object?> update) {
    switch (update['sessionUpdate']) {
      case 'user_message_chunk':
        _userChunk(_text(update['content']));
      case 'agent_message_chunk':
        _chunk(_OpenKind.text, _text(update['content']));
      case 'agent_thought_chunk':
        _chunk(_OpenKind.thought, _text(update['content']));
      case 'tool_call':
        _toolCall(update, fresh: true);
      case 'tool_call_update':
        _toolCall(update, fresh: false);
      case 'plan':
        _plan(update);
    }
  }

  static String _text(Object? content) => switch (content) {
    {'type': 'text', 'text': final String text} => text,
    {'type': 'resource_link', 'uri': final String uri} => uri,
    {'type': 'resource', 'resource': {'text': final String text}} => text,
    _ => '',
  };

  void _userChunk(String text) {
    _close();
    final id = _userId ??= _newId('user');
    _user.write(text);
    emit(ItemUpserted(nextSeq(), id, UserMessageItem(text: '$_user')));
  }

  void _endUser() {
    _userId = null;
    _user.clear();
  }

  void _chunk(_OpenKind kind, String text) {
    if (text.isEmpty) return;
    _endUser();
    var open = _open;
    if (open == null || open.kind != kind) {
      _close();
      open = _open = _Open(kind, _newId(kind.name));
      emit(
        ItemUpserted(
          nextSeq(),
          open.id,
          kind == _OpenKind.text
              ? const AssistantTextItem('')
              : ThinkingItem(text: '', tokens: 0, startedAt: open.started),
          streaming: true,
        ),
      );
    }
    emit(
      TextDelta(
        nextSeq(),
        open.id,
        open.text.length,
        text,
        tokens: kind == _OpenKind.thought
            ? _tokensOf('${open.text}$text')
            : null,
      ),
    );
    open.text.write(text);
  }

  static int _tokensOf(String text) => (text.length / 4).ceil();

  /// Ends the text or thought being written.
  void _close() {
    final open = _open;
    if (open == null) return;
    _open = null;
    final text = '${open.text}';
    emit(
      ItemCompleted(
        nextSeq(),
        open.id,
        item: open.kind == _OpenKind.text
            ? AssistantTextItem(text)
            : ThinkingItem(
                text: text,
                tokens: _tokensOf(text),
                seconds: math.max(
                  1,
                  DateTime.now().difference(open.started).inSeconds,
                ),
              ),
      ),
    );
  }

  /// Ends what is open as the turn ends; calls still under way are given
  /// up ([interrupted]) or left to finish on their own.
  void settle({bool interrupted = false}) {
    _close();
    _endUser();
    if (!interrupted) return;
    for (final tool in _tools.values) {
      if (!tool.running) continue;
      tool.status = 'failed';
      _show(tool);
    }
  }

  // --- Tool calls ------------------------------------------------------------------

  void _toolCall(Map<String, Object?> update, {required bool fresh}) {
    final id = update['toolCallId'];
    if (id is! String) return;
    _close();
    _endUser();
    final tool = _tools.putIfAbsent(id, () => _ToolCall(id))..merge(update);
    _show(tool);
  }

  void _show(_ToolCall tool) {
    final item = _itemOf(tool.id, tool);
    if (item == null) return;
    emit(ItemUpserted(nextSeq(), tool.id, item));
    if (tool.running) return;
    if (tool.done) return;
    tool.done = true;
    if (item is CodeDiffItem && !replaying) _edited(tool);
    if (item is TerminalItem && item.background) _backgrounded(tool);
  }

  /// What [tool] shows as.
  ChatItem? _itemOf(String id, _ToolCall tool) {
    final input = tool.input;
    final status = tool.running
        ? ToolStatus.running
        : tool.status == 'failed'
        ? ToolStatus.failed
        : ToolStatus.succeeded;
    final name = tool.name ?? '';
    final summary = _string(input['toolSummary']);
    final output = tool.output;
    if (name == 'invoke_subagent' || name == 'start_subagent') {
      final agent = AgentItem(
        description:
            _string(input['Role']) ??
            summary ??
            _string(input['TypeName']) ??
            'Subagent',
        id: id,
        agentType: _string(input['TypeName']),
        prompt: _string(input['Prompt']),
        status: tool.status == 'failed'
            ? CommandStatus.failed
            : CommandStatus.running,
        startedAt: tool.started,
        background: true,
      );
      // A new one: its work to follow (see [onTasksChanged]).
      if (!agents.containsKey(id) && !replaying) {
        Future.microtask(() => onTasksChanged?.call());
      }
      return agents[id] = switch (agents[id]) {
        // As the kernel filled it in from the records since.
        final known? when tool.status != 'failed' => known.copyWith(
          description: agent.description,
          agentType: agent.agentType,
          prompt: agent.prompt,
        ),
        _ => agent,
      };
    }
    switch (tool.kind) {
      case 'execute':
        final command =
            _string(input['CommandLine']) ??
            _string(input['command']) ??
            tool.title ??
            '';
        final background = _backgroundTask(output) != null;
        final exit = tool.rawOutput is Map
            ? (tool.rawOutput as Map)['exit_code']
            : null;
        return TerminalItem(
          command: command,
          description: summary,
          output: _commandOutput(output),
          status: tool.running
              ? CommandStatus.running
              : tool.status == 'failed' || (exit is int && exit != 0)
              ? CommandStatus.failed
              : CommandStatus.succeeded,
          background: background,
          startedAt: tool.started,
        );
      case 'edit':
        if (_diffItem(tool) case final diff?) return diff;
      case 'read':
        final path = _path(tool);
        return ToolCallItem(
          kind: ToolKind.read,
          target: path == null ? tool.title ?? '' : _base(path),
          path: path,
          status: status,
          output: output,
          callId: id,
        );
      case 'search':
        return ToolCallItem(
          kind: ToolKind.grep,
          target:
              _string(input['Query']) ??
              _string(input['Pattern']) ??
              _string(input['SearchPattern']) ??
              tool.title ??
              '',
          status: status,
          output: output,
          callId: id,
        );
      case 'fetch':
        return ToolCallItem(
          kind: ToolKind.web,
          target:
              _string(input['Url']) ??
              _string(input['Query']) ??
              tool.title ??
              '',
          status: status,
          output: output,
          callId: id,
        );
    }
    if (name.startsWith('mcp_')) return _mcpItem(id, tool, status);
    return ToolCallItem(
      kind: ToolKind.other,
      label: name.isEmpty ? null : name,
      target: summary ?? tool.title ?? '',
      status: status,
      output: output,
      callId: id,
      input: input,
    );
  }

  /// The MCP server's prefix agy names a tool of the app's own with.
  static const _ownPrefix = 'mcp_${ClaudeSdkTools.server}_';

  /// [name] as Claude Code would name it (`mcp__baocode__<tool>`), when one
  /// of the app's own tools.
  static String? ownToolName(String name) => name.startsWith(_ownPrefix)
      ? 'mcp__${ClaudeSdkTools.server}__${name.substring(_ownPrefix.length)}'
      : null;

  ChatItem _mcpItem(String id, _ToolCall tool, ToolStatus status) {
    final name = tool.name!;
    final input = {...tool.input}..remove('toolSummary');
    final said = _string(tool.input['toolSummary']) ?? '';
    if (ownToolName(name) case final own?) {
      if (ClaudeSdkTools.called(own) case ClaudeSdkTool(
        name: final toolName,
        :final kind?,
        :final summary,
      )) {
        return ToolCallItem(
          kind: kind,
          tool: toolName,
          callId: id,
          input: input,
          label: said.isEmpty ? null : '',
          target: said.isNotEmpty
              ? said
              : summary?.call(input, tool.output) ?? '',
          status: status,
          output: tool.output,
        );
      }
    }
    return ToolCallItem(
      kind: ToolKind.mcp,
      label: name.substring(4),
      target: said,
      status: status,
      output: tool.output,
      callId: id,
      input: input,
    );
  }

  /// An edit's diff card: from what it put in place of what, as the agent
  /// reported (`content`'s `diff`); null when it reported none.
  CodeDiffItem? _diffItem(_ToolCall tool) {
    final diff = tool.diff;
    if (diff == null) return null;
    final path = diff.path;
    final lines = lineDiff(diff.oldText ?? '', diff.newText);
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    return CodeDiffItem(
      fileName: path.substring(slash + 1),
      directory: slash < 0 ? '' : path.substring(0, slash),
      lines: lines,
    );
  }

  void _edited(_ToolCall tool) {
    final diff = tool.diff;
    if (diff == null || tool.status == 'failed') return;
    final lines = lineDiff(diff.oldText ?? '', diff.newText);
    emit(
      FileEdited(
        nextSeq(),
        FileChange(
          path: diff.path,
          added: lines.where((l) => l.type == DiffLineType.added).length,
          removed: lines.where((l) => l.type == DiffLineType.removed).length,
        ),
        turnId: turnId,
        original: switch (diff.oldText) {
          null => const OriginalText(null),
          final before => OriginalByEdits([
            (before: before, after: diff.newText),
          ]),
        },
      ),
    );
  }

  // --- Background tasks ------------------------------------------------------------

  static final _backgroundPattern = RegExp(
    r'running as a background task with task id:\s*(\S+)',
  );

  /// The task a command's output says it went on as, if it did.
  static String? _backgroundTask(String? output) =>
      output == null ? null : _backgroundPattern.firstMatch(output)?.group(1);

  void _backgrounded(_ToolCall tool) {
    final taskId = _backgroundTask(tool.output);
    if (taskId == null || tasks.containsKey(taskId)) return;
    final command = _string(tool.input['CommandLine']) ?? tool.title ?? '';
    tasks[taskId] = KernelTask(
      id: taskId,
      description: _string(tool.input['toolSummary']) ?? command,
      kind: KernelTaskKind.command,
      status: CommandStatus.running,
      startedAt: tool.started,
      toolUseId: tool.id,
    );
    onTasksChanged?.call();
  }

  /// What agy prints before a command's output (when it was run, its exit
  /// code, the sandbox's note) left out: the output alone.
  static String _commandOutput(String? output) {
    if (output == null) return '';
    const marker = 'Command output:\n';
    final at = output.indexOf(marker);
    if (at >= 0) return output.substring(at + marker.length).trimRight();
    return output
        .split('\n')
        .where(
          (line) =>
              !line.startsWith('Created At: ') &&
              !line.startsWith('Completed At: '),
        )
        .join('\n')
        .trim();
  }

  // --- The plan --------------------------------------------------------------------

  String? _planId;

  void _plan(Map<String, Object?> update) {
    _close();
    final todos = [
      for (final entry in update['entries'] as List? ?? const [])
        if (entry is Map)
          {
            'content': '${entry['content'] ?? ''}',
            'status': '${entry['status'] ?? 'pending'}',
          },
    ];
    final id = _planId ??= _newId('plan');
    emit(
      ItemUpserted(
        nextSeq(),
        id,
        ToolCallItem(
          kind: ToolKind.todo,
          tool: 'TodoWrite',
          input: {'todos': todos},
          target:
              todos
                  .where((todo) => todo['status'] == 'in_progress')
                  .map((todo) => todo['content']!)
                  .firstOrNull ??
              '',
          output: [
            for (final todo in todos) '[${todo['status']}] ${todo['content']}',
          ].join('\n'),
        ),
      ),
    );
  }

  /// A new turn writes its plan anew.
  void begin() {
    _planId = null;
  }

  // --- Helpers ---------------------------------------------------------------------

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  static String _base(String path) => path.split(RegExp(r'[/\\]')).last;

  static String? _path(_ToolCall tool) =>
      _string(tool.input['Path']) ??
      _string(tool.input['AbsolutePath']) ??
      _string(tool.input['File']) ??
      tool.location;
}

enum _OpenKind { text, thought }

class _Open {
  _Open(this.kind, this.id);

  final _OpenKind kind;
  final String id;
  final StringBuffer text = StringBuffer();
  final DateTime started = DateTime.now();
}

/// A tool call as reported so far: `tool_call`, then its updates.
class _ToolCall {
  _ToolCall(this.id);

  final String id;
  final DateTime started = DateTime.now();
  String? name;
  String? kind;
  String? title;
  String? status;
  Map<String, Object?> input = const {};
  Object? rawOutput;
  List<Object?> content = const [];
  String? location;

  /// Whether what it ended as was taken in (its edit, its task).
  bool done = false;

  bool get running =>
      status == null || status == 'pending' || status == 'in_progress';

  void merge(Map<String, Object?> update) {
    if (update['name'] case final String value) name = value;
    if (update['kind'] case final String value) kind = value;
    if (update['title'] case final String value) title = value;
    if (update['status'] case final String value) status = value;
    if (update['rawInput'] case final Map<Object?, Object?> raw) {
      input = raw.cast<String, Object?>();
    } else if (update['args'] case final Map<Object?, Object?> raw) {
      input = raw.cast<String, Object?>();
    }
    if (update.containsKey('rawOutput')) rawOutput = update['rawOutput'];
    if (update['content'] case final List<Object?> content) {
      this.content = content;
    }
    if (update['locations'] case [{'path': final String path}, ...]) {
      location = path;
    }
  }

  /// What it returned: its text content, else its raw output's.
  String? get output {
    final texts = [
      for (final block in content)
        if (block case {'type': 'content', 'content': {'text': final String t}})
          t,
    ];
    if (texts.isNotEmpty) return texts.join('\n');
    return switch (rawOutput) {
      {'output': final String text} => text,
      final String text when text.isNotEmpty => text,
      _ => null,
    };
  }

  /// Its edit, as reported: the file, what was there (none for a new
  /// file) and what is now.
  ({String path, String? oldText, String newText})? get diff {
    for (final block in content) {
      if (block case {
        'type': 'diff',
        'path': final String path,
        'newText': final String newText,
      }) {
        return (
          path: path,
          oldText: (block as Map)['oldText'] as String?,
          newText: newText,
        );
      }
    }
    return null;
  }
}
