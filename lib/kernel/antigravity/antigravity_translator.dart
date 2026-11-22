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
  AntigravityTranslator({
    required this.emit,
    required this.nextSeq,
    this.fileText,
  });

  final void Function(KernelEvent event) emit;
  final int Function() nextSeq;

  /// A file's text as it stands (null where it cannot be read).
  final String? Function(String path)? fileText;

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

  /// Called as a command goes on in the background ([tasks] changed).
  void Function()? onTasksChanged;

  /// Whether a call is under way.
  bool get calling =>
      _tools.values.any((tool) => tool.running && !tool.background);

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
    // Read back, a message after a plan: the plan was gone on from.
    if (_userId == null && replaying) {
      endPlanRound();
      resolvePlan(started: true);
    }
    final id = _userId ??= _newId('user');
    _user.write(text);
    final message = UserMessageItem(text: withoutReminders('$_user'));
    if (replaying) replayed[id] = message;
    emit(ItemUpserted(nextSeq(), id, message));
  }

  /// The user's messages read back, in order: timed after, from agy's
  /// records.
  final Map<String, UserMessageItem> replayed = {};

  static final _reminders = RegExp(
    r'<system-reminder>[\s\S]*?(</system-reminder>|$)',
  );

  /// [text] without what the app told agy beside the user's words (its
  /// notes, each a `<system-reminder>`), which agy keeps as part of the
  /// message: read back with it, and its title made of it.
  static String withoutReminders(String text) {
    if (!text.contains('<system-r')) return text;
    var plain = text.replaceAll(_reminders, '');
    // A title cut in one.
    final cut = plain.indexOf('<system-r');
    if (cut >= 0) plain = plain.substring(0, cut);
    return plain.trim();
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
      if (!tool.running || tool.background) continue;
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
    if (_planWrite(tool)) return;
    final item = _itemOf(tool.id, tool);
    if (item == null) return;
    emit(ItemUpserted(nextSeq(), tool.id, item));
    if (tool.running) return;
    if (tool.done) return;
    tool.done = true;
    if (item is CodeDiffItem && !replaying) _edited(tool);
    if (item is TerminalItem && item.background) _backgrounded(tool);
    if (tasks[tool.id] case final task?
        when task.status == CommandStatus.running && item is TerminalItem) {
      tasks[tool.id] = task.copyWith(
        status: item.status,
        summary: _lastLine(item.output),
      );
      onTasksChanged?.call();
    }
  }

  /// The turn ended with [tool]s still running: commands agy left to run
  /// on (it reports their ends later, as updates to them), as tasks.
  void background() {
    var any = false;
    for (final tool in _tools.values) {
      if (!tool.running || tool.kind != 'execute' || tool.background) continue;
      tool.background = true;
      final command = _string(tool.input['CommandLine']) ?? tool.title ?? '';
      tasks[tool.id] = KernelTask(
        id: tool.id,
        description: _string(tool.input['toolSummary']) ?? command,
        kind: KernelTaskKind.command,
        status: CommandStatus.running,
        startedAt: tool.started,
        toolUseId: tool.id,
      );
      emit(ItemUpserted(nextSeq(), tool.id, _itemOf(tool.id, tool)!));
      any = true;
    }
    if (any) onTasksChanged?.call();
  }

  /// Whether [update] only tells of a command left running in the
  /// background (its end): nothing agy took up.
  bool backgroundUpdate(Map<String, Object?> update) =>
      update['sessionUpdate'] == 'tool_call_update' &&
      (_tools[update['toolCallId']]?.background ?? false);

  static String? _lastLine(String output) => output
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .lastOrNull;

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
      // All ACP tells of one is that it started: its work and its report
      // stay agy's, the report told in agy's next reply. So it shows what
      // it was asked, and opens nothing.
      return AgentItem(
        description: _string(input['Role']) ?? summary ?? 'Subagent',
        agentType: switch (_string(input['TypeName'])) {
          'self' => null,
          final type => type,
        },
        prompt: _string(input['Prompt']),
        status: switch (status) {
          ToolStatus.running => CommandStatus.running,
          ToolStatus.failed => CommandStatus.failed,
          _ => CommandStatus.succeeded,
        },
      );
    }
    switch (tool.kind) {
      case 'execute':
        final command =
            _string(input['CommandLine']) ??
            _string(input['command']) ??
            tool.title ??
            '';
        final background = tool.background || _backgroundTask(output) != null;
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
    // agy's own notes (its task list, a walkthrough): not the project's.
    if (agyOwnFile(diff.path)) return;
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
          // The whole file before, as agy tells an edit done (the file as
          // it left it after): no need to work it back from the file, which
          // a next edit may have changed already by the time it is.
          final before when fileText?.call(diff.path) == diff.newText =>
            OriginalText(before),
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

  // --- Plans -----------------------------------------------------------------------

  /// Whether the turn plans (Plan mode): what agy writes of its own then
  /// (a markdown file in its folder) is its plan.
  bool planning = false;

  /// The card of the round of planning under way, by the call that began
  /// it; the one awaiting the user, once the turn is over.
  String? _planCard;
  String? _awaitingCard;
  final Map<String, PlanItem> _plans = {};
  int _planRounds = 0;

  /// The plan put to the user, until they go on from it.
  PlanItem? get awaitingPlan => _plans[_awaitingCard];

  /// Whether [path] is in agy's own folder for its conversations
  /// (`~/.gemini/antigravity-cli/brain`), not the project's.
  static bool agyOwnFile(String path) =>
      RegExp(r'[/\\]antigravity-cli[/\\]brain[/\\]').hasMatch(path);

  /// Shows [tool] on the plan's card, if it writes the plan.
  bool _planWrite(_ToolCall tool) {
    if (!planning || tool.kind != 'edit') return false;
    final path = tool.diff?.path ?? _path(tool);
    if (path == null || !agyOwnFile(path) || !path.endsWith('.md')) {
      return false;
    }
    final card = _planCard ??= tool.id;
    final known = _plans[card];
    final text = tool.diff?.newText ?? known?.text;
    var writes = known?.writes ?? 0;
    final written = !tool.running && !tool.done && tool.status != 'failed';
    if (written) {
      tool.done = true;
      writes++;
    }
    final plan = _plans[card] = PlanItem(
      path: path,
      round: known?.round ?? ++_planRounds,
      title: PlanItem.titleOf(text) ?? known?.title,
      text: text,
      writes: writes,
    );
    emit(ItemUpserted(nextSeq(), card, plan));
    if (written && !replaying) emit(PlanWritten(nextSeq(), path));
    return true;
  }

  /// The turn is over: the plan it wrote, if any, awaits the user.
  void endPlanRound() {
    final card = _planCard;
    if (card == null) return;
    _planCard = null;
    _awaitingCard = card;
    _putPlan(card, _plans[card]!.copyWith(status: PlanStatus.awaiting));
  }

  /// The user went on from the plan awaiting: [started] it, or said what
  /// should change ([feedback]).
  void resolvePlan({required bool started, String? feedback}) {
    final card = _awaitingCard;
    if (card == null) return;
    _awaitingCard = null;
    final plan = _plans[card]!;
    _putPlan(
      card,
      started
          ? plan.copyWith(status: PlanStatus.approved)
          : plan.copyWith(status: PlanStatus.sentBack, feedback: feedback),
    );
  }

  void _putPlan(String card, PlanItem plan) {
    _plans[card] = plan;
    emit(ItemUpserted(nextSeq(), card, plan));
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

  /// Left running as its turn ended: a command in the background.
  bool background = false;

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
