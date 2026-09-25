import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'assistant_text.dart';
import 'code_diff_card.dart';
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
  });

  final ChatItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      UserMessageItem(:final text, :final attachments) => UserMessageBubble(
        text: text,
        attachments: attachments,
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
    };
  }
}
