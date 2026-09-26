/// UI-only view models for the conversation history.
sealed class ChatItem {
  const ChatItem();
}

/// What the user sent, as text: mentions and commands are echoed in it
/// (`@lib/main.dart`, `/plan`), not kept as structure.
class UserMessageItem extends ChatItem {
  const UserMessageItem({required this.text});

  final String text;
}

/// Plain assistant prose. Supports `inline code` and `- ` bullet lines.
class AssistantTextItem extends ChatItem {
  const AssistantTextItem(this.text);

  final String text;
}

class ThinkingItem extends ChatItem {
  const ThinkingItem({required this.seconds, required this.text});

  final int seconds;
  final String text;
}

enum ToolKind { read, grep, listDir, search }

class ToolCallItem extends ChatItem {
  const ToolCallItem({required this.kind, required this.target, this.detail});

  final ToolKind kind;
  final String target;
  final String? detail;
}

class TerminalItem extends ChatItem {
  const TerminalItem({
    required this.command,
    required this.output,
    this.succeeded = true,
  });

  final String command;
  final String output;
  final bool succeeded;
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
  });

  final String fileName;
  final String directory;
  final List<DiffLine> lines;
}

/// Transient "Thinking…" / "Generating…" row at the tail of a live turn.
class LiveStatusItem extends ChatItem {
  const LiveStatusItem(this.label);

  final String label;
}
