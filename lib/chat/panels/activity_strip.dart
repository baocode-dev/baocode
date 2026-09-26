import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../chat_session.dart';
import '../widgets/file_label.dart';
import '../widgets/hover_builder.dart';
import 'ask_question_panel.dart';

/// Indicator area docked on top of the composer: background tasks and the
/// files changed in this turn.
class ActivityStrip extends StatefulWidget {
  const ActivityStrip({super.key, required this.session});

  final ChatSession session;

  static bool hasContent(ChatSession session) =>
      session.tasks.isNotEmpty || session.fileChanges.isNotEmpty;

  @override
  State<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends State<ActivityStrip> {
  bool _filesExpanded = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_syncTicker);
    _syncTicker();
  }

  @override
  void didUpdateWidget(ActivityStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_syncTicker);
      widget.session.addListener(_syncTicker);
    }
  }

  @override
  void dispose() {
    widget.session.removeListener(_syncTicker);
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second only while a task is running, for elapsed time.
  void _syncTicker() {
    final running = widget.session.tasks.any(
      (task) => task.status == TaskStatus.running,
    );
    if (running && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() {}),
      );
    } else if (!running) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final changes = session.fileChanges;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: CursorColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          top: BorderSide(color: CursorColors.borderStrong),
          left: BorderSide(color: CursorColors.borderStrong),
          right: BorderSide(color: CursorColors.borderStrong),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final task in session.tasks)
            _TaskRow(task: task, onDismiss: () => session.dismissTask(task)),
          if (changes.isNotEmpty) ...[
            _FilesHeader(
              changes: changes,
              expanded: _filesExpanded,
              onToggle: () => setState(() => _filesExpanded = !_filesExpanded),
              onUndo: session.undoAllChanges,
              onKeep: session.keepAllChanges,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _filesExpanded
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 150),
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.only(bottom: 2),
                        children: [
                          for (final change in changes) _FileRow(change),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ],
      ),
    );
  }
}

class _StripRow extends StatelessWidget {
  const _StripRow({required this.children, this.onTap});

  final List<Widget> children;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return HoverBuilder(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? CursorColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(children: children),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onDismiss});

  final BackgroundTask task;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(task.startedAt).inSeconds;
    final (status, color) = switch (task.status) {
      TaskStatus.running => ('Running · ${elapsed}s', CursorColors.textMuted),
      TaskStatus.succeeded => ('Passed', CursorColors.added),
      TaskStatus.failed => ('Failed', CursorColors.removed),
    };
    return _StripRow(
      children: [
        SizedBox.square(
          dimension: 14,
          child: task.status == TaskStatus.running
              ? const Padding(
                  padding: EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: CursorColors.textMuted,
                  ),
                )
              : Icon(
                  task.status == TaskStatus.succeeded
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 14,
                  color: color,
                ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.terminal_rounded,
          size: 13,
          color: CursorColors.textFaint,
        ),
        const SizedBox(width: 5),
        Text(
          task.command,
          style: const TextStyle(
            color: CursorColors.text,
            fontFamily: CursorFonts.mono,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(status, style: TextStyle(color: color, fontSize: 11.5)),
        const Spacer(),
        if (task.status != TaskStatus.running)
          GestureDetector(
            onTap: onDismiss,
            child: const MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.close_rounded,
                size: 14,
                color: CursorColors.textFaint,
              ),
            ),
          ),
      ],
    );
  }
}

class _FilesHeader extends StatelessWidget {
  const _FilesHeader({
    required this.changes,
    required this.expanded,
    required this.onToggle,
    required this.onUndo,
    required this.onKeep,
  });

  final List<FileChange> changes;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onUndo;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final added = changes.fold(0, (sum, change) => sum + change.added);
    final removed = changes.fold(0, (sum, change) => sum + change.removed);
    return _StripRow(
      onTap: onToggle,
      children: [
        AnimatedRotation(
          turns: expanded ? 0.25 : 0,
          duration: const Duration(milliseconds: 150),
          child: const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: CursorColors.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${changes.length} ${changes.length == 1 ? 'file' : 'files'} changed',
          style: const TextStyle(color: CursorColors.text, fontSize: 12),
        ),
        const SizedBox(width: 8),
        Text(
          '+$added',
          style: const TextStyle(
            color: CursorColors.added,
            fontFamily: CursorFonts.mono,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '-$removed',
          style: const TextStyle(
            color: CursorColors.removed,
            fontFamily: CursorFonts.mono,
            fontSize: 11.5,
          ),
        ),
        const Spacer(),
        SizedBox(
          height: 20,
          child: FittedBox(
            child: PanelButton(label: 'Undo all', onTap: onUndo),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 20,
          child: FittedBox(
            child: PanelButton(label: 'Keep all', primary: true, onTap: onKeep),
          ),
        ),
      ],
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow(this.change);

  final FileChange change;

  @override
  Widget build(BuildContext context) {
    return _StripRow(
      onTap: () {},
      children: [
        const SizedBox(width: 20),
        FileLabel(change.fileName, fontSize: 12),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            change.directory,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: CursorColors.textFaint,
              fontSize: 11.5,
            ),
          ),
        ),
        Text(
          '+${change.added}',
          style: const TextStyle(
            color: CursorColors.added,
            fontFamily: CursorFonts.mono,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '-${change.removed}',
          style: const TextStyle(
            color: CursorColors.removed,
            fontFamily: CursorFonts.mono,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
