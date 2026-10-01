import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../ide/git/git_model.dart';
import '../../ide/git/scm_tree.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../chat_models.dart';

/// The files an agent changed, as the Source Control view's tree shows a
/// group's changes (see scm_tree.dart): by folder, a chain of folders
/// with nothing else in them in one row, folders first, with each file's
/// status letter and its lines added and removed. Hovered, a file or a
/// folder offers Undo and Keep; a click opens the file's changes.
///
/// At most [maxRows] rows show; the rest scroll, built as they come into
/// view.
class ChangeTree extends StatefulWidget {
  const ChangeTree({
    super.key,
    required this.root,
    required this.changes,
    this.maxRows = 7,
    this.onOpen,
    this.onKeep,
    this.onUndo,
  });

  /// The project's directory: the tree's top.
  final String root;
  final List<FileChange> changes;
  final int maxRows;

  final ValueChanged<FileChange>? onOpen;
  final ValueChanged<List<FileChange>>? onKeep;

  /// Null when files cannot be undone one by one.
  final ValueChanged<List<FileChange>>? onUndo;

  @override
  State<ChangeTree> createState() => _ChangeTreeState();
}

sealed class _Row {
  const _Row(this.depth);

  final int depth;
}

final class _FolderRow extends _Row {
  const _FolderRow(this.folder, super.depth, this.changes);

  final IdeScmTreeFolder folder;
  final List<FileChange> changes;
}

final class _FileRow extends _Row {
  const _FileRow(this.change, this.status, super.depth);

  final FileChange change;
  final IdeGitStatus status;
}

class _ChangeTreeState extends State<ChangeTree> {
  /// The folders closed, by path.
  final Set<String> _collapsed = {};
  List<_Row> _rows = const [];

  @override
  void initState() {
    super.initState();
    _layOut();
  }

  @override
  void didUpdateWidget(ChangeTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.changes, widget.changes) ||
        oldWidget.root != widget.root) {
      _layOut();
    }
  }

  /// The letter and color the Source Control view would give it.
  static IdeGitStatus _status(FileChange change) => change.conflict
      ? IdeGitStatus.bothModified
      : switch (change.kind) {
          FileChangeKind.added => IdeGitStatus.indexAdded,
          FileChangeKind.modified => IdeGitStatus.modified,
          FileChangeKind.deleted => IdeGitStatus.deleted,
        };

  void _layOut() {
    final byPath = {for (final change in widget.changes) change.path: change};
    final rows = <_Row>[];
    void add(List<IdeScmTreeNode> nodes, int depth) {
      for (final node in nodes) {
        switch (node) {
          case IdeScmTreeFolder():
            rows.add(
              _FolderRow(node, depth, [
                for (final resource in node.resources) byPath[resource.path]!,
              ]),
            );
            if (!_collapsed.contains(node.path)) add(node.children, depth + 1);
          case IdeScmTreeFile(:final resource):
            rows.add(_FileRow(byPath[resource.path]!, resource.status, depth));
        }
      }
    }

    add(
      ideScmTree(widget.root, [
        for (final change in widget.changes)
          IdeGitResource(
            path: change.path,
            status: _status(change),
            group: IdeGitGroup.workingTree,
          ),
      ]),
      1,
    );
    _rows = rows;
  }

  void _toggle(String folder) => setState(() {
    if (!_collapsed.remove(folder)) _collapsed.add(folder);
    _layOut();
  });

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return SizedBox(
      height: math.min(rows.length, widget.maxRows) * IdeListColors.rowHeight,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemExtent: IdeListColors.rowHeight,
        itemCount: rows.length,
        itemBuilder: (context, index) => switch (rows[index]) {
          final _FolderRow row => _folderRow(row),
          final _FileRow row => _fileRow(row),
        },
      ),
    );
  }

  /// Undo and Keep for [changes], those that can be.
  List<Widget> _actions(List<FileChange> changes) {
    final l10n = context.l10n;
    final undoable = [
      for (final change in changes)
        if (change.tracked) change,
    ];
    return [
      if ((widget.onUndo, undoable) case (final undo?, [_, ...]))
        IdeActionButton(
          icon: Codicons.discard,
          tooltip: l10n.stripUndo,
          size: 20,
          onPressed: () => undo(undoable),
        ),
      if (widget.onKeep case final keep?)
        IdeActionButton(
          icon: Codicons.check,
          tooltip: l10n.stripKeep,
          size: 20,
          onPressed: () => keep(changes),
        ),
    ];
  }

  void _showMenu(
    Offset position,
    List<FileChange> changes, {
    FileChange? file,
  }) {
    final l10n = context.l10n;
    final undoable = [
      for (final change in changes)
        if (change.tracked) change,
    ];
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            if ((widget.onOpen, file) case (final open?, final file?))
              IdeMenuAction(l10n.scmOpenChanges, onSelected: () => open(file)),
          ],
          [
            if ((widget.onUndo, undoable) case (final undo?, [_, ...]))
              IdeMenuAction(l10n.stripUndo, onSelected: () => undo(undoable)),
            if (widget.onKeep case final keep?)
              IdeMenuAction(l10n.stripKeep, onSelected: () => keep(changes)),
          ],
        ]),
      ),
    );
  }

  Widget _folderRow(_FolderRow row) {
    final folder = row.folder;
    final collapsed = _collapsed.contains(folder.path);
    return IdeListRow(
      key: ValueKey('folder:${folder.path}'),
      tooltip: p.relative(folder.path, from: widget.root),
      onTap: () => _toggle(folder.path),
      onContextMenu: (position) => _showMenu(position, row.changes),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: 8.0 + (row.depth - 1) * IdeListColors.indent,
          right: 8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Transform.translate(
                offset: const Offset(3, 0),
                child: Icon(
                  collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                  size: 16,
                  color: IdeListColors.foreground,
                ),
              ),
            ),
            FolderIcon(folder.path, expanded: !collapsed),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(
                name: folder.label,
                actions: [if (hovered) ..._actions(row.changes)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fileRow(_FileRow row) {
    final change = row.change;
    final l10n = context.l10n;
    final kind = switch (change.kind) {
      FileChangeKind.added => l10n.stripChangeAdded,
      FileChangeKind.modified => l10n.stripChangeModified,
      FileChangeKind.deleted => l10n.stripChangeDeleted,
    };
    final note = change.conflict
        ? l10n.stripChangeConflict
        : !change.tracked
        ? l10n.stripChangeUntracked
        : change.shared
        ? l10n.stripChangeShared
        : null;
    final relative = p.isWithin(widget.root, change.path)
        ? p.relative(change.path, from: widget.root)
        : change.path;
    final open = widget.onOpen;
    return IdeListRow(
      key: ValueKey(change.path),
      tooltip: ['$relative • $kind', ?note].join('\n'),
      onTap: open == null ? null : () => open(change),
      onContextMenu: (position) => _showMenu(position, [change], file: change),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: 8.0 + (row.depth - 1) * IdeListColors.indent + 22,
          right: 8,
        ),
        child: Row(
          children: [
            FileIcon(change.path),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(
                name: p.basename(change.path),
                strikeThrough: row.status.strikeThrough,
                letter: row.status.letter,
                letterColor: row.status.color,
                actions: [
                  if (hovered) ..._actions([change]),
                  // What the tooltip says, hinted at while it can show.
                  if (hovered && note != null && !change.conflict)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Codicons.info,
                        size: 13,
                        color: IdeListColors.description,
                      ),
                    ),
                  _LineCounts(change),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `+added -removed`, leaving out a count of none.
class _LineCounts extends StatelessWidget {
  const _LineCounts(this.change);

  final FileChange change;

  @override
  Widget build(BuildContext context) {
    if (change.binary || (change.added == 0 && change.removed == 0)) {
      return const SizedBox.shrink();
    }
    TextStyle style(String color) => TextStyle(
      color: themeColors[color],
      fontFamily: AppFonts.mono,
      fontSize: 11,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (change.added > 0)
            Text('+${change.added}', style: style('chat.linesAddedForeground')),
          if (change.added > 0 && change.removed > 0) const SizedBox(width: 4),
          if (change.removed > 0)
            Text(
              '-${change.removed}',
              style: style('chat.linesRemovedForeground'),
            ),
        ],
      ),
    );
  }
}
