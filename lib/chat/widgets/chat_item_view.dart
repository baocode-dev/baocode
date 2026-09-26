import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'assistant_text.dart';
import 'code_diff_card.dart';
import 'shimmer_text.dart';
import 'terminal_card.dart';
import 'thinking_section.dart';
import 'tool_call_row.dart';
import 'user_message_bubble.dart';

/// Maps a [ChatItem] to its visual component.
class ChatItemView extends StatelessWidget {
  const ChatItemView({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
    this.onEdit,
  });

  final ChatItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Starts editing a user message.
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      UserMessageItem(:final text) => UserMessageBubble(
        text: text,
        onEdit: onEdit,
      ),
      AssistantTextItem(:final text) => AssistantText(text),
      ThinkingItem(:final seconds, :final text) => ThinkingSection(
        seconds: seconds,
        text: text,
        expanded: expanded,
        onToggle: onToggle ?? () {},
      ),
      ToolCallItem(:final kind, :final target, :final detail) => ToolCallRow(
        kind: kind,
        target: target,
        detail: detail,
      ),
      TerminalItem(:final command, :final output, :final succeeded) =>
        TerminalCard(command: command, output: output, succeeded: succeeded),
      CodeDiffItem(:final fileName, :final directory, :final lines) =>
        CodeDiffCard(fileName: fileName, directory: directory, lines: lines),
      LiveStatusItem(:final label) => ShimmerText(label),
    };
  }
}

/// The text of [item] as the history shows it, for copying items that are
/// wholly inside a selection (built or not). Mirrors the widgets above: one
/// line per text block, blocks on the same row joined by a space, so it
/// matches what copying the rendered item yields.
String chatItemPlainText(ChatItem item, {bool expanded = false}) {
  String inline(String text) {
    final parts = text.split('`');
    return [
      for (var i = 0; i < parts.length; i++)
        if (parts[i].isNotEmpty) i.isOdd ? ' ${parts[i]} ' : parts[i],
    ].join();
  }

  return switch (item) {
    UserMessageItem(:final text) => inline(text),
    AssistantTextItem(:final text) => [
      for (final line in text.split('\n'))
        if (line.startsWith('- '))
          '• ${inline(line.substring(2))}'
        else if (line.isNotEmpty)
          inline(line),
    ].join('\n'),
    ThinkingItem(:final seconds, :final text) =>
      expanded ? 'Thought for ${seconds}s\n$text' : 'Thought for ${seconds}s',
    ToolCallItem(:final kind, :final target, :final detail) => [
      switch (kind) {
        ToolKind.read => 'Read',
        ToolKind.grep => 'Grepped',
        ToolKind.listDir => 'Listed',
        ToolKind.search => 'Searched',
      },
      target,
      ?detail,
    ].join(' '),
    TerminalItem(:final command, :final output, :final succeeded) =>
      'Terminal ${succeeded ? 'Success' : 'Failed'}\n\$ $command\n$output',
    CodeDiffItem(:final fileName, :final directory, :final lines) => [
      '$fileName $directory '
          '+${lines.where((l) => l.type == DiffLineType.added).length} '
          '-${lines.where((l) => l.type == DiffLineType.removed).length}',
      for (final line in lines)
        '${line.lineNumber} ${switch (line.type) {
          DiffLineType.added => '+',
          DiffLineType.removed => '-',
          DiffLineType.context => ' ',
        }} ${line.text}',
    ].join('\n'),
    LiveStatusItem(:final label) => '$label…',
  };
}
