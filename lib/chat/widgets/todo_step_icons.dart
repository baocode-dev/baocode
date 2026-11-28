import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show OverflowBoxFit;

import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../selection/chat_selection.dart';
import 'tool_call_row.dart' show TodoItem;

/// Extracts the single display glyph shown inside a todo badge: the first
/// visible grapheme of [content], uppercased when that stays one grapheme
/// (handling ASCII, accented Latin, Cyrillic, Greek, etc., without expanding
/// `ß` into two letters); `'·'` when [content] has no visible text.
String todoInitial(String content) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) return '·';
  final first = trimmed.characters.first;
  final upper = first.toUpperCase();
  return upper.characters.length == 1 ? upper : first;
}

/// Leading icon for a [ToolKind.todo] step: stacked initial circles while
/// collapsed (when [todos] is non-empty), smoothly transitioning to the
/// checklist icon once expanded, while keeping the expanded row's height so
/// toggling never shifts the layout vertically.
class TodoStepLeading extends StatelessWidget {
  const TodoStepLeading({
    super.key,
    required this.todos,
    required this.expanded,
  });

  final List<TodoItem>? todos;
  final bool expanded;

  static const _iconSize = 15.0;

  @override
  Widget build(BuildContext context) {
    final checklist = Icon(
      Icons.checklist_rounded,
      key: const ValueKey('todo_icon'),
      size: _iconSize,
      color: AppColors.textMuted,
    );
    final items = todos;
    if (items == null || items.isEmpty) return checklist;
    // Lock layout height to the expanded checklist icon so collapsing/expanding
    // causes zero vertical shift; OverflowBox lets the 20px circles paint
    // cleanly into StepHeader's vertical padding without clipping.
    return ChatUnselectable(
      child: SizedBox(
        height: _iconSize,
        child: OverflowBox(
          minHeight: StepTodoIcons.badgeSize,
          maxHeight: StepTodoIcons.badgeSize,
          fit: OverflowBoxFit.deferToChild,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => SizeTransition(
              axis: Axis.horizontal,
              alignment: AlignmentDirectional.centerStart,
              sizeFactor: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: expanded
                ? SizedBox(
                    key: const ValueKey('todo_icon'),
                    height: StepTodoIcons.badgeSize,
                    child: Center(child: checklist),
                  )
                : StepTodoIcons(
                    key: const ValueKey('todo_icons'),
                    todos: items,
                  ),
          ),
        ),
      ),
    );
  }
}

/// Stacked circular first-character badges for a todo step while it is closed:
/// up to [max] overlapping badges tinted by status (green = completed,
/// blue = in progress, neutral = pending), with `+$rest` for any beyond [max].
class StepTodoIcons extends StatelessWidget {
  const StepTodoIcons({super.key, required this.todos, this.max = 5});

  final List<TodoItem> todos;
  final int max;

  static const badgeSize = 20.0;
  static const ringWidth = 1.0;
  static const innerSize = badgeSize - ringWidth * 2;
  static const step = 14.0;

  @override
  Widget build(BuildContext context) {
    if (todos.isEmpty) return const SizedBox.shrink();
    final visibleCount = todos.length < max ? todos.length : max;
    final rest = todos.length - visibleCount;
    final stackWidth = badgeSize + (visibleCount - 1) * step;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          // Match StepWebIcons' slight downward nudge for CJK/Latin alignment.
          offset: const Offset(0, 0.5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: stackWidth,
            height: badgeSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < visibleCount; i++)
                  AnimatedPositioned(
                    key: ValueKey('todo:$i'),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    left: i * step,
                    top: 0,
                    child: _AnimatedTodoBadge(index: i, todo: todos[i]),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeIn,
          child: rest > 0
              ? Padding(
                  key: ValueKey(rest),
                  padding: const EdgeInsetsDirectional.only(start: 4),
                  child: Text(
                    '+$rest',
                    style: TextStyle(color: AppColors.textFaint, fontSize: 12),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey(0)),
        ),
      ],
    );
  }
}

class _AnimatedTodoBadge extends StatefulWidget {
  const _AnimatedTodoBadge({required this.index, required this.todo});

  final int index;
  final TodoItem todo;

  @override
  State<_AnimatedTodoBadge> createState() => _AnimatedTodoBadgeState();
}

class _AnimatedTodoBadgeState extends State<_AnimatedTodoBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    final delayMs = widget.index * 28;
    const enterMs = 200;
    final totalMs = delayMs + enterMs;
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: totalMs),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(delayMs / totalMs, 1.0, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = AppColors.conversationSurface;
    final (Color fill, Color outline, Color glyph) = switch (widget.todo.status) {
      'completed' => () {
        final green = themeColors['charts.green'];
        return (
          Color.alphaBlend(green.withValues(alpha: 0.16), surface),
          green.withValues(alpha: 0.35),
          green,
        );
      }(),
      'in_progress' => () {
        final blue = themeColors['charts.blue'];
        return (
          Color.alphaBlend(blue.withValues(alpha: 0.18), surface),
          blue.withValues(alpha: 0.42),
          blue,
        );
      }(),
      _ => (
        Color.alphaBlend(AppColors.text.withValues(alpha: 0.08), surface),
        AppColors.text.withValues(alpha: 0.14),
        AppColors.textMuted,
      ),
    };
    final initial = todoInitial(widget.todo.content);
    return FadeTransition(
      opacity: _progress,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(-0.22, 0),
          end: Offset.zero,
        ).animate(_progress),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.65, end: 1.0).animate(_progress),
          child: Container(
            width: StepTodoIcons.badgeSize,
            height: StepTodoIcons.badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: surface),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: StepTodoIcons.innerSize,
              height: StepTodoIcons.innerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fill,
                border: Border.all(color: outline, width: 1),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  color: glyph,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
