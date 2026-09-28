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
  });

  final String text;

  /// Pictures sent with it (screenshots, mockups…).
  final List<ImageAttachment> images;

  /// Sent while the agent was busy: waits for its turn, and can be taken
  /// back until then.
  final bool queued;
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

/// A subagent at work: its own conversation, nested and folded.
class AgentItem extends ChatItem {
  const AgentItem({
    required this.description,
    this.agentType,
    this.status = CommandStatus.running,
    this.tokens,
    this.toolUses,
    this.lastTool,
    this.children = const [],
    this.result,
  });

  final String description;
  final String? agentType;
  final CommandStatus status;
  final int? tokens;
  final int? toolUses;
  final String? lastTool;
  final List<ChatItem> children;

  /// Its final report.
  final String? result;

  AgentItem copyWith({
    CommandStatus? status,
    int? tokens,
    int? toolUses,
    String? lastTool,
    List<ChatItem>? children,
    String? result,
  }) => AgentItem(
    description: description,
    agentType: agentType,
    status: status ?? this.status,
    tokens: tokens ?? this.tokens,
    toolUses: toolUses ?? this.toolUses,
    lastTool: lastTool ?? this.lastTool,
    children: children ?? this.children,
    result: result ?? this.result,
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

/// Transient row at the tail of a live turn while the agent works out of
/// sight, e.g. "Planning next move" while its model has yet to answer.
class LiveStatusItem extends ChatItem {
  const LiveStatusItem(this.label);

  final String label;
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
