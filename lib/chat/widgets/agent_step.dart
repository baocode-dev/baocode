import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_models.dart';
import 'chat_item_view.dart';
import 'hover_builder.dart';
import 'markdown_view.dart';
import 'step_header.dart';

/// A subagent as a step: "Delegated  Find the kernel files · 12 tools",
/// opening to its own steps and its report.
class AgentStep extends StatefulWidget {
  const AgentStep({
    super.key,
    required this.item,
    this.expanded = false,
    this.onToggle,
    this.onMoveToBackground,
  });

  final AgentItem item;
  final bool expanded;
  final VoidCallback? onToggle;

  /// Lets the turn go on while the subagent keeps working.
  final VoidCallback? onMoveToBackground;

  static String detail(AgentItem item) => [
    ?item.agentType,
    if (item.toolUses case final uses? when uses > 0)
      '$uses ${uses == 1 ? 'tool' : 'tools'}',
    if (item.status == CommandStatus.running) ?item.lastTool,
  ].join(' · ');

  @override
  State<AgentStep> createState() => _AgentStepState();
}

class _AgentStepState extends State<AgentStep> {
  /// Its steps opened or closed by hand, by position.
  final Map<int, bool> _opened = {};

  bool _isOpen(int index) =>
      _opened[index] ?? defaultExpanded(widget.item.children[index]);

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final running = item.status == CommandStatus.running;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepHeader(
          verb: running ? 'Delegating' : 'Delegated',
          object: item.description,
          detail: AgentStep.detail(item),
          running: running,
          expanded: widget.expanded,
          // Nothing to open to before its first step.
          onToggle: item.children.isEmpty && item.result == null
              ? null
              : widget.onToggle,
          action: switch (widget.onMoveToBackground) {
            final move? => BackgroundButton(onTap: move),
            null => null,
          },
        ),
        if (widget.expanded &&
            (item.children.isNotEmpty || item.result != null))
          Container(
            margin: const EdgeInsets.only(left: 6, top: 2, bottom: 6),
            padding: const EdgeInsets.only(left: 12),
            decoration: const BoxDecoration(
              border: Border(left: BorderSide(color: CursorColors.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, child) in item.children.indexed)
                  ChatItemView(
                    item: child,
                    expanded: _isOpen(index),
                    onToggle: () =>
                        setState(() => _opened[index] = !_isOpen(index)),
                  ),
                if (item.result case final result?)
                  Padding(
                    padding: EdgeInsets.only(
                      top: item.children.isEmpty ? 4 : 8,
                    ),
                    child: MarkdownView(
                      result,
                      style: MarkdownView.baseStyle.copyWith(
                        color: CursorColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Moves a running command or subagent to the background, as Ctrl+B does
/// in a terminal.
class BackgroundButton extends StatelessWidget {
  const BackgroundButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Keep it running and let the agent go on',
      waitDuration: const Duration(milliseconds: 500),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered) => GestureDetector(
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.move_down_rounded,
                size: 13,
                color: hovered ? CursorColors.text : CursorColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Background',
                style: TextStyle(
                  color: hovered ? CursorColors.text : CursorColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
