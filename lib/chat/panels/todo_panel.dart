import 'package:flutter/material.dart';

import '../../kernel/kernel_types.dart';
import '../../l10n/l10n.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;

/// The agent's todo list, docked above the composer while it has open
/// items: done ones struck through, the current one in its active words.
class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.todos});

  final List<TodoEntry> todos;

  static bool hasContent(List<TodoEntry> todos) =>
      todos.any((todo) => todo.status != TodoStatus.completed);

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final todos = widget.todos;
    final done = todos.where((t) => t.status == TodoStatus.completed).length;
    final current = todos
        .where((t) => t.status == TodoStatus.inProgress)
        .firstOrNull;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: CursorColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: CursorColors.borderStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => setState(() => _open = !_open),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.checklist_rounded,
                      size: 14,
                      color: CursorColors.textMuted,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.todoCount(done, todos.length),
                      style: TextStyle(
                        color: CursorColors.text,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    // All the room there is, so the chevron sits at the end.
                    if (current != null && !_open) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          current.activeForm ?? current.content,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: CursorColors.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ] else
                      const Spacer(),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      size: 16,
                      color: CursorColors.textFaint,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                children: [
                  for (final todo in todos)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              switch (todo.status) {
                                TodoStatus.completed =>
                                  Icons.check_circle_rounded,
                                TodoStatus.inProgress =>
                                  Icons.radio_button_checked_rounded,
                                TodoStatus.pending =>
                                  Icons.radio_button_unchecked_rounded,
                              },
                              size: 13,
                              // As upstream's todo list.
                              color: switch (todo.status) {
                                TodoStatus.completed =>
                                  themeColors['charts.green'],
                                TodoStatus.inProgress =>
                                  themeColors['charts.blue'],
                                TodoStatus.pending => CursorColors.text,
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              todo.status == TodoStatus.inProgress
                                  ? todo.activeForm ?? todo.content
                                  : todo.content,
                              style: TextStyle(
                                color: todo.status == TodoStatus.completed
                                    ? CursorColors.textFaint
                                    : CursorColors.text,
                                fontSize: 12.5,
                                decoration: todo.status == TodoStatus.completed
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
