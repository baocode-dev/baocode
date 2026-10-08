import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../ide/ide_hover.dart';
import '../../kernel/kernel_types.dart';
import '../chat_models.dart';
import '../widgets/flip_switcher.dart';
import '../widgets/hover_builder.dart';
import '../widgets/orbit_indicator.dart';
import 'change_tree.dart';
import 'interaction_panel.dart';

/// Indicator area docked on top of the composer: background tasks still
/// running and the files changed and not yet kept or undone, as a tree
/// (see [ChangeTree]).
class ActivityStrip extends StatefulWidget {
  const ActivityStrip({
    super.key,
    required this.tasks,
    required this.changes,
    required this.onKeep,
    this.root = '.',
    this.onUndo,
    this.onKeepFiles,
    this.onUndoFiles,
    this.onOpenFile,
    this.onStopTask,
    this.onOpenTask,
    this.canOpenTask,
    this.detailOf,
  });

  final List<KernelTask> tasks;
  final List<FileChange> changes;

  /// The project's directory, which [changes]' paths are in.
  final String root;

  /// Stops a running task; null when tasks cannot be stopped.
  final ValueChanged<KernelTask>? onStopTask;

  /// Opens a subagent's conversation or background command's output.
  final ValueChanged<KernelTask>? onOpenTask;
  final bool Function(KernelTask)? canOpenTask;

  /// What a task did last, e.g. a subagent's last step: after its
  /// description, flipping up to the next as it goes on.
  final String? Function(KernelTask task)? detailOf;
  final VoidCallback onKeep;

  /// Null when the changes cannot be put back: no Undo then.
  final VoidCallback? onUndo;

  final ValueChanged<List<FileChange>>? onKeepFiles;

  /// Null when files cannot be put back one by one.
  final ValueChanged<List<FileChange>>? onUndoFiles;

  /// Opens a file's changes.
  final ValueChanged<FileChange>? onOpenFile;

  static bool hasContent(List<KernelTask> tasks, List<FileChange> changes) =>
      tasks.isNotEmpty || changes.isNotEmpty;

  @override
  State<ActivityStrip> createState() => _ActivityStripState();
}

class _ActivityStripState extends State<ActivityStrip> {
  /// Past this many rows, tasks scroll within the strip.
  static const _maxTaskRows = 4;

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
    final running = widget.tasks.isNotEmpty;
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
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        border: Border(
          top: BorderSide(color: AppColors.borderStrong),
          left: BorderSide(color: AppColors.borderStrong),
          right: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.tasks.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _StripRow.height * _maxTaskRows,
              ),
              child: ListView(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                children: [
                  for (final task in widget.tasks)
                    _TaskRow(
                      key: ValueKey(task.id),
                      task: task,
                      detail: widget.detailOf?.call(task),
                      onOpen: switch (widget.onOpenTask) {
                        final open?
                            when widget.canOpenTask?.call(task) ??
                                task.kind == KernelTaskKind.agent =>
                          () => open(task),
                        _ => null,
                      },
                      onStop: switch (widget.onStopTask) {
                        final stop? => () => stop(task),
                        null => null,
                      },
                    ),
                ],
              ),
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
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: ChangeTree(
                  root: widget.root,
                  changes: changes,
                  onOpen: widget.onOpenFile,
                  onKeep: widget.onKeepFiles,
                  onUndo: widget.onUndoFiles,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StripRow extends StatelessWidget {
  const _StripRow({required this.children, this.onTap, this.semanticLabel});

  static const double height = 28;

  final List<Widget> children;
  final VoidCallback? onTap;

  /// What a tap on it does, read out.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final row = HoverBuilder(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: height,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            color: hovered && onTap != null
                ? AppColors.hover
                : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ),
          child: Row(children: children),
        ),
      ),
    );
    return semanticLabel == null
        ? row
        : Semantics(button: true, hint: semanticLabel, child: row);
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.task,
    this.detail,
    this.onStop,
    this.onOpen,
  });

  final KernelTask task;

  /// What it did last (see [ActivityStrip.detailOf]).
  final String? detail;
  final VoidCallback? onStop;

  /// Opens a subagent's conversation.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(task.startedAt).inSeconds;
    return _StripRow(
      onTap: onOpen,
      semanticLabel: onOpen == null
          ? null
          : context.l10n.stripOpen(task.description),
      children: [
        SizedBox.square(
          dimension: 14,
          // A subagent left to run on its own.
          child: task.kind == KernelTaskKind.agent && task.background
              ? const OrbitIndicator()
              : Padding(
                  padding: EdgeInsets.all(1.5),
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: AppColors.textMuted,
                  ),
                ),
        ),
        const SizedBox(width: 8),
        if (task.kind != KernelTaskKind.agent) ...[
          Icon(Icons.terminal_rounded, size: 13, color: AppColors.textFaint),
          const SizedBox(width: 5),
        ],
        // All the room there is, so the time and the action sit at the end.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                Flexible(
                  child: Text(
                    task.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontFamily: task.kind == KernelTaskKind.command
                          ? AppFonts.mono
                          : null,
                      fontFamilyFallback: task.kind == KernelTaskKind.command
                          ? AppFonts.monoFallbacks
                          : null,
                      fontSize: 11.5,
                    ),
                  ),
                ),
                if (detail case final detail?)
                  // At most half of it, the description having the rest.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: FlipSwitcher(
                        child: Text(
                          '· $detail',
                          key: ValueKey(detail),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          context.l10n.stripRunningElapsed(elapsed),
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(width: 8),
        if (onStop case final stop?)
          _IconAction(
            icon: Icons.stop_rounded,
            tooltip: context.l10n.chatStop,
            onTap: stop,
          ),
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
    return IdeHover(
      message: tooltip,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Icon(icon, size: 14, color: AppColors.textFaint),
          ),
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
        // Narrow, the label gives way to the buttons.
        Expanded(
          child: Row(
            children: [
              AnimatedRotation(
                turns: expanded ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  context.l10n.stripFilesChanged(changes.length),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.text, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '+$added',
                style: TextStyle(
                  color: themeColors['chat.linesAddedForeground'],
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: AppFonts.monoFallbacks,
                  fontSize: 11.5,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '-$removed',
                style: TextStyle(
                  color: themeColors['chat.linesRemovedForeground'],
                  fontFamily: AppFonts.mono,
                  fontFamilyFallback: AppFonts.monoFallbacks,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (onUndo case final onUndo?) ...[
          SizedBox(
            height: 20,
            child: FittedBox(
              child: PanelButton(
                label: context.l10n.stripUndoAll,
                onTap: onUndo,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        SizedBox(
          height: 20,
          child: FittedBox(
            child: PanelButton(
              label: context.l10n.stripKeepAll,
              primary: true,
              onTap: onKeep,
            ),
          ),
        ),
      ],
    );
  }
}
