import 'package:flutter/material.dart';

import '../chat_models.dart';
import 'activity_row.dart';
import 'agent_step.dart';
import 'assistant_text.dart';
import 'command_step.dart';
import 'notice_row.dart';
import 'step_header.dart';
import 'edit_step.dart';
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
    this.onCancelQueued,
    this.onMoveToBackground,
    this.onStop,
    this.onOpen,
  });

  final ChatItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Starts editing a user message.
  final VoidCallback? onEdit;

  /// Takes back a queued message.
  final VoidCallback? onCancelQueued;

  /// Moves a running command or subagent to the background.
  final VoidCallback? onMoveToBackground;

  /// Stops a running subagent.
  final VoidCallback? onStop;

  /// Opens a subagent's own conversation.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final view = _build();
    // Steps line up on the left: the history centers what is narrower
    // than its column.
    return isStep(item) ? SizedBox(width: double.infinity, child: view) : view;
  }

  Widget _build() {
    return switch (item) {
      UserMessageItem(:final text, :final queued, :final images) =>
        UserMessageBubble(
          text: text,
          images: images,
          onEdit: queued ? null : onEdit,
          queued: queued,
          onCancel: queued ? onCancelQueued : null,
        ),
      AssistantTextItem(:final text) => AssistantText(text),
      ThinkingItem(:final text, :final seconds, :final startedAt) =>
        ThinkingSection(
          text: text,
          seconds: seconds,
          startedAt: startedAt,
          expanded: expanded,
          onToggle: onToggle ?? () {},
        ),
      ToolCallItem(
        :final kind,
        :final target,
        :final detail,
        :final path,
        :final results,
        :final label,
        :final status,
        :final output,
      ) =>
        ToolCallRow(
          kind: kind,
          target: target,
          detail: detail,
          path: path,
          results: results,
          label: label,
          status: status,
          output: output,
          expanded: expanded,
          onToggle: onToggle,
        ),
      final AgentItem agent => AgentStep(
        item: agent,
        onOpen: onOpen,
        onStop: onStop,
        onMoveToBackground: onMoveToBackground,
      ),
      final NoticeItem notice => NoticeRow(item: notice),
      TerminalItem(
        :final command,
        :final description,
        :final output,
        :final status,
        :final background,
      ) =>
        CommandStep(
          command: command,
          description: description,
          output: output,
          status: status,
          background: background,
          expanded: expanded,
          onToggle: onToggle,
          onMoveToBackground: onMoveToBackground,
        ),
      final CodeDiffItem diff => EditStep(
        item: diff,
        expanded: expanded,
        onToggle: onToggle,
      ),
      LiveStatusItem(:final label) => ActivityRow(label: label),
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
    ThinkingItem(:final text, :final seconds) => [
      thinkingTitle(seconds: seconds),
      if (expanded) text.trimRight(),
    ].join('\n'),
    ToolCallItem(
      :final kind,
      :final target,
      :final detail,
      :final label,
      :final status,
      :final results,
      :final output,
    ) =>
      [
        StepHeader.text(
          label ?? toolVerb(kind, running: status == ToolStatus.running),
          target,
          detail,
        ),
        if (expanded)
          if (results.isNotEmpty)
            results.join('\n')
          else if (output?.trimRight() case final output?
              when output.isNotEmpty)
            output,
      ].join('\n'),
    final AgentItem agent => AgentStep.plainText(agent),
    NoticeItem(:final text) => text,
    TerminalItem(
      :final command,
      :final description,
      :final output,
      :final status,
      :final background,
    ) =>
      [
        StepHeader.text(
          CommandStep.verb(status, background: background),
          CommandStep.title(command, description),
          background ? 'in background' : null,
        ),
        if (expanded) ...[
          '\$ $command',
          if (output.trim().isNotEmpty) output.trimRight(),
        ],
      ].join('\n'),
    CodeDiffItem(:final fileName, :final lines) => [
      [
        StepHeader.text('Edited', fileName),
        if (item.added > 0) '+${item.added}',
        if (item.removed > 0) '-${item.removed}',
      ].join(' '),
      if (expanded)
        for (final line in lines)
          '${line.lineNumber} ${switch (line.type) {
            DiffLineType.added => '+',
            DiffLineType.removed => '-',
            DiffLineType.context => ' ',
          }} ${line.text}',
    ].join('\n'),
    LiveStatusItem(:final label) => label,
  };
}

/// Whether [item] is a step the agent took (a thought, a tool call…): one
/// line that may open.
bool isStep(ChatItem item) => switch (item) {
  ThinkingItem() ||
  ToolCallItem() ||
  AgentItem() ||
  TerminalItem() ||
  CodeDiffItem() ||
  LiveStatusItem() => true,
  _ => false,
};

/// Whether a step is open unless opened or closed by hand: a thought while
/// it streams. Tool calls stay closed (opening and closing as they start
/// and end would flicker).
bool defaultExpanded(ChatItem item) => switch (item) {
  ThinkingItem(:final streaming) => streaming,
  _ => false,
};
