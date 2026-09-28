import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sidebar/sidebar_menu.dart';
import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import '../floating/floating_placement.dart';
import 'hover_builder.dart';
import 'shell_highlight.dart';
import 'step_header.dart';

/// A shell command as a step: "Ran  Check the Flutter version", opening to
/// the command, colored, and what it printed.
class CommandStep extends StatelessWidget {
  const CommandStep({
    super.key,
    required this.command,
    required this.output,
    this.description,
    this.status = CommandStatus.succeeded,
    this.background = false,
    this.expanded = false,
    this.onToggle,
    this.onMoveToBackground,
  });

  final String command;
  final String output;
  final String? description;
  final CommandStatus status;

  /// Left running on its own: the turn went on.
  final bool background;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Lets the turn go on while the command keeps running.
  final VoidCallback? onMoveToBackground;

  bool get _running => status == CommandStatus.running && !background;

  /// Anything to open to: the command may still be on its way.
  bool get _opens => command.trim().isNotEmpty || output.trim().isNotEmpty;

  /// What the header says it is: its description, or its first line.
  static String title(String command, String? description) =>
      switch (description?.trim()) {
        final text? when text.isNotEmpty => text,
        _ => command.trim().split('\n').first,
      };

  static String verb(CommandStatus status, {required bool background}) =>
      background
      ? 'Started'
      : status == CommandStatus.running
      ? 'Running'
      : 'Ran';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: verb(status, background: background),
          object: title(command, description),
          detail: background ? 'in background' : null,
          running: _running,
          expanded: expanded,
          onToggle: _opens ? onToggle : null,
        ),
        if (expanded && _opens)
          StepBody(
            followEnd: _running,
            // Clear of the menu button.
            padding: const EdgeInsets.fromLTRB(12, 10, 36, 10),
            overlay: _CommandMenu(
              command: command,
              output: output,
              onMoveToBackground: onMoveToBackground,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: '\$ ',
                        style: TextStyle(color: CursorColors.textFaint),
                      ),
                      ...highlightShell(command),
                    ],
                  ),
                  style: stepMono,
                ),
                if (output.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(output.trimRight(), style: stepMono),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// `…`: copy the command or its output; while it runs, move it to the
/// background.
class _CommandMenu extends StatelessWidget {
  const _CommandMenu({
    required this.command,
    required this.output,
    this.onMoveToBackground,
  });

  final String command;
  final String output;
  final VoidCallback? onMoveToBackground;

  static void _copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  @override
  Widget build(BuildContext context) {
    return SidebarMenu(
      placement: (side: FloatingSide.bottom, align: FloatingAlign.end),
      items: () => [
        SidebarMenuItem(
          'Copy command',
          icon: Icons.content_copy_rounded,
          onSelected: () => _copy(command),
        ),
        if (output.trim().isNotEmpty)
          SidebarMenuItem(
            'Copy output',
            icon: Icons.notes_rounded,
            onSelected: () => _copy(output.trimRight()),
          ),
        if (onMoveToBackground case final move?)
          SidebarMenuItem(
            'Move to background',
            icon: Icons.move_down_rounded,
            onSelected: move,
          ),
      ],
      builder: (context, menu) => Semantics(
        button: true,
        label: 'More',
        child: HoverBuilder(
          cursor: SystemMouseCursors.click,
          builder: (context, hovered) => GestureDetector(
            onTap: menu.open,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: hovered || menu.isOpen
                    ? CursorColors.hover
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Icon(
                Icons.more_horiz_rounded,
                size: 16,
                color: hovered || menu.isOpen
                    ? CursorColors.text
                    : CursorColors.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
