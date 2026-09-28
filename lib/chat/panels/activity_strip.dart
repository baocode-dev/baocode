import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/cursor_theme.dart';
import '../../kernel/kernel_types.dart';
import '../chat_models.dart';
import '../widgets/file_label.dart';
import '../widgets/hover_builder.dart';
import 'interaction_panel.dart';

/// Indicator area docked on top of the composer: background tasks and the
/// files changed in this turn.
class ActivityStrip extends StatefulWidget {
  const ActivityStrip({
    super.key,
    required this.tasks,
    required this.changes,
    required this.onDismissTask,
    required this.onKeep,
    this.onUndo,
    this.onStopTask,
  });

  final List<KernelTask> tasks;
  final List<FileChange> changes;
  final ValueChanged<KernelTask> onDismissTask;

  /// Stops a running task; null when tasks cannot be stopped.
  final ValueChanged<KernelTask>? onStopTask;
  final VoidCallback onKeep;

  /// Null when the changes cannot be put back: no Undo then.
  final VoidCallback? onUndo;

  static bool hasContent(List<KernelTask> tasks, List<FileChange> changes) =>
      tasks.isNotEmpty || changes.isNotEmpty;

  @override
  State<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends State<ActivityStrip> {
  bool _filesExpanded = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(ActivityStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// Ticks once a second only while a task is running, for elapsed time.
  void _syncTicker() {
    final running = widget.tasks.any(
      (task) => task.status == CommandStatus.running,
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
    final changes = widget.changes;
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
          for (final task in widget.tasks)
            _TaskRow(
              task: task,
              onDismiss: () => widget.onDismissTask(task),
              onStop: switch (widget.onStopTask) {
                final stop? => () => stop(task),
                null => null,
              },
            ),
          if (changes.isNotEmpty) ...[
            _FilesHeader(
              changes: changes,
              expanded: _filesExpanded,
              onToggle: () => setState(() => _filesExpanded = !_filesExpanded),
              onUndo: widget.onUndo,
              onKeep: widget.onKeep,
            ),
            if (_filesExpanded)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 150),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 2),
                  children: [for (final change in changes) _FileRow(change)],
                ),
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
  const _TaskRow({required this.task, required this.onDismiss, this.onStop});

  final KernelTask task;
  final VoidCallback onDismiss;
  final VoidCallback? onStop;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(task.startedAt).inSeconds;
    final (status, color) = switch (task.status) {
      CommandStatus.running => (
        'Running · ${elapsed}s',
        CursorColors.textMuted,
      ),
      CommandStatus.succeeded => ('Passed', CursorColors.added),
      CommandStatus.failed => ('Failed', CursorColors.removed),
    };
    return _StripRow(
      children: [
        SizedBox.square(
          dimension: 14,
          child: task.status == CommandStatus.running
              ? const Padding(
                  padding: EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: CursorColors.textMuted,
                  ),
                )
              : Icon(
                  task.status == CommandStatus.succeeded
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  size: 14,
                  color: color,
                ),
        ),
        const SizedBox(width: 8),
        Icon(
          task.kind == KernelTaskKind.agent
              ? Icons.smart_toy_outlined
              : Icons.terminal_rounded,
          size: 13,
          color: CursorColors.textFaint,
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            task.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: CursorColors.text,
              fontFamily: task.kind == KernelTaskKind.command
                  ? CursorFonts.mono
                  : null,
              fontSize: 11.5,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(status, style: TextStyle(color: color, fontSize: 11.5)),
        const Spacer(),
        if (task.status != CommandStatus.running)
          _IconAction(
            icon: Icons.close_rounded,
            tooltip: 'Dismiss',
            onTap: onDismiss,
          )
        else if (onStop case final stop?)
          _IconAction(icon: Icons.stop_rounded, tooltip: 'Stop', onTap: stop),
      ],
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Icon(icon, size: 14, color: CursorColors.textFaint),
        ),
      ),
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
  final VoidCallback? onUndo;
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
        if (onUndo case final onUndo?) ...[
          SizedBox(
            height: 20,
            child: FittedBox(
              child: PanelButton(label: 'Undo all', onTap: onUndo),
            ),
          ),
          const SizedBox(width: 4),
        ],
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
