import 'dart:typed_data';

/// UI-only view models for the conversation history.
sealed class ChatItem {
  const ChatItem();
}

/// What the user sent, as text: mentions and commands are echoed in it
/// (`@lib/main.dart`, `/plan`), not kept as structure.
class UserMessageItem extends ChatItem {
  const UserMessageItem({
    required this.text,
    this.queued = false,
    this.images = const [],
    this.worked,
  });

  final String text;

  /// Pictures sent with it (screenshots, mockups…).
  final List<ImageAttachment> images;

  /// Sent while the agent was busy: waits for its turn, and can be taken
  /// back until then.
  final bool queued;

  /// How long the agent worked on it, once its turn ended as it should
  /// (not stopped): the work before its answer folds into that.
  final Duration? worked;

  UserMessageItem copyWith({Duration? worked}) => UserMessageItem(
    text: text,
    queued: queued,
    images: images,
    worked: worked ?? this.worked,
  );
}

/// A picture sent with a message.
class ImageAttachment {
  const ImageAttachment({
    required this.bytes,
    required this.mediaType,
    this.name,
  });

  final Uint8List bytes;

  /// `image/png`, `image/jpeg`, `image/gif` or `image/webp`.
  final String mediaType;

  /// The file it came from, if any.
  final String? name;
}

/// Plain assistant prose. Supports `inline code` and `- ` bullet lines.
class AssistantTextItem extends ChatItem {
  const AssistantTextItem(this.text);

  final String text;
}

class ThinkingItem extends ChatItem {
  const ThinkingItem({
    required this.text,
    required this.tokens,
    this.seconds,
    this.startedAt,
  });

  final String text;

  /// Tokens thought so far (all of them, once done).
  final int tokens;

  /// How long the thought took; null while it is still streaming.
  final int? seconds;

  /// When it began, while it streams: its time so far shows live.
  final DateTime? startedAt;

  bool get streaming => seconds == null;
}

enum ToolKind {
  read,
  grep,
  listDir,
  search,
  edit,
  command,
  web,
  agent,
  mcp,
  todo,

  /// A message to another agent.
  message,
  other,
}

enum ToolStatus { running, succeeded, failed, denied }

class ToolCallItem extends ChatItem {
  const ToolCallItem({
    required this.kind,
    required this.target,
    this.detail,
    this.path,
    this.results = const [],
    this.label,
    this.status = ToolStatus.succeeded,
    this.output,
  });

  final ToolKind kind;
  final String target;
  final String? detail;

  /// Full path of the file read, when [target] is its name.
  final String? path;

  /// Matches found (`path:line`), for searches.
  final List<String> results;

  /// What it did, when not said by [kind] (e.g. an MCP tool's name).
  final String? label;
  final ToolStatus status;

  /// What it returned, shown on demand.
  final String? output;
}

/// A subagent at work: its own conversation, one card in the history that
/// opens to it.
class AgentItem extends ChatItem {
  const AgentItem({
    required this.description,
    this.id,
    this.agentType,
    this.prompt,
    this.status = CommandStatus.running,
    this.tokens,
    this.toolUses,
    this.lastTool,
    this.activity,
    this.startedAt,
    this.duration,
    this.model,
    this.children = const [],
    this.result,
    this.background = false,
  });

  final String description;

  /// The tool call that started it, to find it again and act on it.
  final String? id;
  final String? agentType;

  /// What the agent that started it asked of it.
  final String? prompt;
  final CommandStatus status;
  final int? tokens;
  final int? toolUses;
  final String? lastTool;

  /// What it is doing now, e.g. "Reading a.txt".
  final String? activity;

  /// When it started, while it runs (live sessions only).
  final DateTime? startedAt;

  /// How long it took, once done.
  final Duration? duration;
  final String? model;
  final List<ChatItem> children;

  /// Its final report.
  final String? result;

  /// Left to run on its own while the agent goes on: it reports when done.
  final bool background;

  AgentItem copyWith({
    String? description,
    String? agentType,
    String? prompt,
    CommandStatus? status,
    int? tokens,
    int? toolUses,
    String? lastTool,
    String? activity,
    Duration? duration,
    String? model,
    List<ChatItem>? children,
    String? result,
    bool? background,
  }) => AgentItem(
    description: description ?? this.description,
    id: id,
    agentType: agentType ?? this.agentType,
    prompt: prompt ?? this.prompt,
    status: status ?? this.status,
    tokens: tokens ?? this.tokens,
    toolUses: toolUses ?? this.toolUses,
    lastTool: lastTool ?? this.lastTool,
    activity: activity ?? this.activity,
    startedAt: startedAt,
    duration: duration ?? this.duration,
    model: model ?? this.model,
    children: children ?? this.children,
    result: result ?? this.result,
    background: background ?? this.background,
  );
}

enum NoticeKind {
  /// The conversation was summarized to free the context.
  compaction,

  /// A request failed and will be retried.
  retry,
  error,
  info,
  warning,

  /// Output of a command run in the session (e.g. `/context`), markdown.
  command,
}

/// A line from the runtime, not the agent: shown apart from its messages.
class NoticeItem extends ChatItem {
  const NoticeItem(this.kind, this.text);

  final NoticeKind kind;
  final String text;
}

enum CommandStatus { running, succeeded, failed }

class TerminalItem extends ChatItem {
  const TerminalItem({
    required this.command,
    required this.output,
    this.description,
    this.status = CommandStatus.succeeded,
    this.background = false,
    this.startedAt,
  });

  final String command;

  /// What it is for, in words (e.g. "Check the Flutter version"), when the
  /// agent said.
  final String? description;
  final String output;
  final CommandStatus status;

  /// Left running after its turn: shown as a background task too.
  final bool background;
  final DateTime? startedAt;

  bool get succeeded => status != CommandStatus.failed;
}

enum DiffLineType { added, removed, context }

class DiffLine {
  const DiffLine(this.type, this.lineNumber, this.text);

  final DiffLineType type;
  final int lineNumber;
  final String text;
}

class CodeDiffItem extends ChatItem {
  const CodeDiffItem({
    required this.fileName,
    required this.directory,
    required this.lines,
    this._added,
    this._removed,
  });

  final String fileName;
  final String directory;

  /// The changed lines, perhaps only the first of them.
  final List<DiffLine> lines;
  final int? _added;
  final int? _removed;

  /// Lines added and removed in all, [lines] shown or not.
  int get added =>
      _added ?? lines.where((l) => l.type == DiffLineType.added).length;
  int get removed =>
      _removed ?? lines.where((l) => l.type == DiffLineType.removed).length;
}

/// Row at the end of a live turn, all through it: the agent at work, e.g.
/// "Planning next move", or "Compacting conversation". Hidden at times.
class LiveStatusItem extends ChatItem {
  const LiveStatusItem(
    this.label, {
    this.whimsical = false,
    this.visible = true,
  });

  final String label;

  /// Whether the wait has nothing to name (the model yet to answer, not a
  /// chore like compacting): the row may muse rather than say [label].
  final bool whimsical;

  /// Whether it shows now: it stays through the turn, and comes and goes.
  final bool visible;
}

/// A file an agent changed, with its line counts.
class FileChange {
  const FileChange({
    required this.path,
    required this.added,
    required this.removed,
  });

  final String path;
  final int added;
  final int removed;

  String get fileName => path.split('/').last;
  String get directory {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }
}
