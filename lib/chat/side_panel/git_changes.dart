import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/git/git_change_editor.dart';
import '../../ide/git/git_model.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/scm_tree.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../workspace/window_controls.dart';
import '../composer/composer_files.dart';
import '../composer/file_drag.dart';
import 'file_open.dart';

/// [resource]'s changes, as the IDE's Source Control opens them (see
/// [IdeGitChangeEditor]): its text at HEAD or in the index against the
/// index's or the file's; an added file's against nothing, a deleted
/// one's text against nothing.
FileOpenRequest gitChangeRequest(
  IdeGitRepository git,
  IdeGitState state,
  IdeGitResource resource,
) {
  final editor = IdeGitChangeEditor.of(
    resource,
    staged: state.group(IdeGitGroup.staged),
  );
  Future<String> Function() show(IdeGitSide side) =>
      () => git.service.show(side.ref!, side.path);
  final (left, right) = (editor.left, editor.right);
  // Deleted: HEAD's text, and no file.
  if (left == null && right != null && right.ref == 'HEAD') {
    return FileOpenRequest(
      resource.path,
      diff: true,
      original: show(right),
      modified: () async => throw IdeFileNotFoundException(resource.path),
    );
  }
  return FileOpenRequest(
    resource.path,
    diff: true,
    // Not there (before the first commit): none before it.
    original: left == null
        ? () async => ''
        : () => show(left)().catchError((Object _) => ''),
    modified: right == null || right.isFile ? null : show(right),
  );
}

/// The project's Git changes, as the IDE's Source Control view lists them:
/// Merge Changes, Staged Changes and Changes, each as a tree of folders
/// (a chain of folders with nothing else in them in one row) or [tree]
/// false a list by path, each file with its folder; each file's status
/// letter. Hovered, a row offers what the view's do (open the file,
/// discard, stage or unstage); its context menu those, the reveals, and
/// adding or copying the files for the chat. A file or folder drags onto
/// the chat's composer, as the explorer's.
class GitChangeList extends StatefulWidget {
  const GitChangeList({
    super.key,
    required this.git,
    required this.state,
    required this.onOpen,
    this.tree = true,
    this.selected,
    this.onOpenFile,
    this.onRevealInFiles,
    this.onAddToChat,
    this.local = true,
    this.trash,
    this.onError,
  });

  final IdeGitRepository git;
  final IdeGitState state;

  /// Opens a file's changes.
  final ValueChanged<IdeGitResource> onOpen;
  final bool tree;

  /// The path of the file whose changes show: its rows are selected.
  final String? selected;
  final ValueChanged<String>? onOpenFile;
  final ValueChanged<String>? onRevealInFiles;

  /// Puts files in the chat's composer.
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  /// Whether the files are this machine's: a remote project's are not
  /// shown in the file manager, nor copied to the system's clipboard.
  final bool local;

  /// Moves an untracked file discarded to the Trash; deleted when null.
  final Future<bool> Function(String path)? trash;
  final ValueChanged<Object>? onError;

  @override
  State<GitChangeList> createState() => _GitChangeListState();
}

sealed class _Row {
  const _Row(this.group);

  final IdeGitGroup group;
}

final class _GroupRow extends _Row {
  const _GroupRow(super.group, this.resources);

  final List<IdeGitResource> resources;
}

final class _FolderRow extends _Row {
  const _FolderRow(super.group, this.folder, this.depth, this.key);

  final IdeScmTreeFolder folder;
  final int depth;
  final String key;
}

/// In the tree at [depth]; in the list where it is null.
final class _FileRow extends _Row {
  _FileRow(this.resource, this.depth) : super(resource.group);

  final IdeGitResource resource;
  final int? depth;
}

class _GitChangeListState extends State<GitChangeList> {
  final Set<IdeGitGroup> _collapsedGroups = {};
  final Set<String> _collapsedFolders = {};

  IdeGitRepository get _git => widget.git;

  List<_Row> _rows() {
    final state = widget.state;
    final rows = <_Row>[];
    for (final group in IdeGitGroup.values) {
      final resources = state.group(group);
      if (resources.isEmpty) continue;
      rows.add(_GroupRow(group, resources));
      if (_collapsedGroups.contains(group)) continue;
      if (!widget.tree) {
        final sorted = [...resources]..sort((a, b) => a.path.compareTo(b.path));
        rows.addAll([for (final resource in sorted) _FileRow(resource, null)]);
        continue;
      }
      void add(List<IdeScmTreeNode> nodes, int depth) {
        for (final node in nodes) {
          switch (node) {
            case IdeScmTreeFolder():
              final key = '${group.name}:${node.path}';
              rows.add(_FolderRow(group, node, depth, key));
              if (!_collapsedFolders.contains(key)) {
                add(node.children, depth + 1);
              }
            case IdeScmTreeFile(:final resource):
              rows.add(_FileRow(resource, depth));
          }
        }
      }

      add(ideScmTree(state.root, resources), 1);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 12),
      itemExtent: IdeListColors.rowHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) => switch (rows[index]) {
        final _GroupRow row => _groupRow(row),
        final _FolderRow row => _folderRow(row),
        final _FileRow row => _fileRow(row),
      },
    );
  }

  static bool _deleted(IdeGitResource resource) => switch (resource.status) {
    IdeGitStatus.deleted ||
    IdeGitStatus.indexDeleted ||
    IdeGitStatus.deletedByUs ||
    IdeGitStatus.bothDeleted => true,
    _ => false,
  };

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      widget.onError?.call(error);
    }
  }

  void _stage(List<IdeGitResource> resources) =>
      unawaited(_run(() => _git.stage(resources)));

  void _unstage(List<IdeGitResource> resources) =>
      unawaited(_run(() => _git.unstage(resources)));

  /// Discards [resources]' changes once confirmed, as the view asks.
  Future<void> _discard(List<IdeGitResource> resources) async {
    if (resources.isEmpty) return;
    final l10n = context.l10n;
    final one = resources.length == 1;
    final untracked = one && resources.single.status == IdeGitStatus.untracked;
    final name = p.basename(resources.first.path);
    final pick = await showIdeDialog(
      context,
      message: !one
          ? l10n.scmConfirmDiscardAll(resources.length)
          : untracked
          ? l10n.scmConfirmDeleteUntracked(name)
          : l10n.scmConfirmDiscard(name),
      detail: !one
          ? l10n.scmIrreversibleWorkingSet
          : untracked && widget.trash == null
          ? l10n.scmIrreversibleFile
          : null,
      buttons: [
        !one
            ? l10n.scmDiscardAllFiles(resources.length)
            : !untracked
            ? l10n.scmDiscardFile
            : widget.trash != null
            ? l10n.explorerMoveToTrash
            : l10n.scmDeleteFile,
      ],
    );
    if (pick != 0) return;
    await _run(() => _git.discard(resources, trash: widget.trash));
  }

  /// What can be done to [resources] of [group], as inline actions and
  /// menu items: discard and stage the changes, or unstage them.
  List<({String label, IconData icon, VoidCallback run})> _actions(
    IdeGitGroup group,
    List<IdeGitResource> resources,
  ) {
    final l10n = context.l10n;
    return [
      if (group == IdeGitGroup.workingTree)
        (
          label: l10n.scmDiscardChanges,
          icon: Codicons.discard,
          run: () => unawaited(_discard(resources)),
        ),
      if (group == IdeGitGroup.staged)
        (
          label: l10n.scmUnstageChanges,
          icon: Codicons.remove,
          run: () => _unstage(resources),
        )
      else
        (
          label: l10n.scmStageChanges,
          icon: Codicons.add,
          run: () => _stage(resources),
        ),
    ];
  }

  List<Widget> _inline(
    List<({String label, IconData icon, VoidCallback run})> actions,
  ) => [
    for (final action in actions)
      IdeActionButton(
        icon: action.icon,
        size: 20,
        tooltip: action.label,
        onPressed: action.run,
      ),
  ];

  void _showMenu(
    Offset position,
    IdeGitGroup group,
    List<IdeGitResource> resources, {
    IdeGitResource? file,
  }) {
    final l10n = context.l10n;
    final root = widget.state.root;
    final path = file?.path;
    final there = file != null && !_deleted(file);
    // What there is of them on disk, for the chat.
    final present = [
      for (final resource in resources)
        if (!_deleted(resource)) resource.path,
    ];
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            if (file != null)
              IdeMenuAction(
                l10n.scmOpenChanges,
                onSelected: () => widget.onOpen(file),
              ),
            if ((widget.onOpenFile, path) case (final open?, final path?)
                when there)
              IdeMenuAction(l10n.scmOpenFile, onSelected: () => open(path)),
          ],
          [
            for (final action in _actions(group, resources))
              IdeMenuAction(action.label, onSelected: action.run),
          ],
          [
            if ((widget.onRevealInFiles, path) case (final reveal?, final path?)
                when there)
              IdeMenuAction(
                l10n.sidePanelRevealInFiles,
                onSelected: () => reveal(path),
              ),
            if (path != null &&
                there &&
                widget.local &&
                WindowControls.canRevealInFileManager)
              IdeMenuAction(
                l10n.revealInFileManager,
                onSelected: () =>
                    unawaited(WindowControls.revealInFileManager(path)),
              ),
          ],
          [
            if ((widget.onAddToChat, present) case (final add?, [_, ...]))
              IdeMenuAction(
                l10n.sidePanelAddToChat,
                onSelected: () =>
                    add([for (final path in present) ComposerFile(path)]),
              ),
            if (widget.local && present.isNotEmpty)
              IdeMenuAction(
                l10n.commonCopy,
                onSelected: () =>
                    unawaited(WindowControls.writePasteboardFiles(present)),
              ),
          ],
          [
            if (path != null) ...[
              IdeMenuAction(
                l10n.tabCopyPath,
                onSelected: () =>
                    unawaited(Clipboard.setData(ClipboardData(text: path))),
              ),
              IdeMenuAction(
                l10n.tabCopyRelativePath,
                onSelected: () => unawaited(
                  Clipboard.setData(
                    ClipboardData(text: p.relative(path, from: root)),
                  ),
                ),
              ),
            ],
          ],
        ]),
      ),
    );
  }

  Widget _chevron(bool collapsed) => SizedBox(
    width: 22,
    child: Icon(
      collapsed ? Codicons.chevronRight : Codicons.chevronDown,
      size: 16,
      color: IdeListColors.foreground,
    ),
  );

  Widget _groupRow(_GroupRow row) {
    final group = row.group;
    final collapsed = _collapsedGroups.contains(group);
    return IdeListRow(
      key: ValueKey('group:${group.name}'),
      onTap: () => setState(() {
        if (!_collapsedGroups.remove(group)) _collapsedGroups.add(group);
      }),
      onContextMenu: (position) => _showMenu(position, group, row.resources),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 4, right: 8),
        child: Row(
          children: [
            _chevron(collapsed),
            Expanded(
              child: IdeResourceLabel(
                name: group.localizedLabel(context.l10n),
                actions: [
                  if (hovered) ..._inline(_actions(group, row.resources)),
                ],
              ),
            ),
            const SizedBox(width: 4),
            IdeCountBadge(row.resources.length),
          ],
        ),
      ),
    );
  }

  Widget _folderRow(_FolderRow row) {
    final folder = row.folder;
    final collapsed = _collapsedFolders.contains(row.key);
    final resources = folder.resources.toList();
    return _draggable(
      [ComposerFile(folder.path, directory: true)],
      IdeListRow(
        key: ValueKey('folder:${row.key}'),
        tooltip: p.relative(folder.path, from: widget.state.root),
        onTap: () => setState(() {
          if (!_collapsedFolders.remove(row.key)) {
            _collapsedFolders.add(row.key);
          }
        }),
        onContextMenu: (position) => _showMenu(position, row.group, resources),
        builder: (context, hovered) => Padding(
          padding: EdgeInsets.only(
            left: 4.0 + row.depth * IdeListColors.indent,
            right: 8,
          ),
          child: Row(
            children: [
              _chevron(collapsed),
              FolderIcon(folder.path, expanded: !collapsed),
              const SizedBox(width: 6),
              Expanded(
                child: IdeResourceLabel(
                  name: folder.label,
                  actions: [
                    if (hovered) ..._inline(_actions(row.group, resources)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [row], dragged onto the chat's composer, puts [files] in.
  Widget _draggable(List<ComposerFile> files, Widget row) =>
      FileDraggable(key: row.key, files: files, child: row);

  Widget _fileRow(_FileRow row) {
    final resource = row.resource;
    final root = widget.state.root;
    final relative = p.relative(resource.path, from: root);
    final folder = p.dirname(relative);
    final l10n = context.l10n;
    final listRow = IdeListRow(
      key: ValueKey('${resource.group.name}:${resource.path}'),
      selected: resource.path == widget.selected,
      tooltip: '$relative • ${resource.status.localizedLabel(l10n)}',
      onTap: () => widget.onOpen(resource),
      onContextMenu: (position) =>
          _showMenu(position, resource.group, [resource], file: resource),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: row.depth == null
              ? 26
              : 4.0 + row.depth! * IdeListColors.indent + 22,
          right: 8,
        ),
        child: Row(
          children: [
            FileIcon(resource.path),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(
                name: p.basename(resource.path),
                description: row.depth != null || folder == '.' ? null : folder,
                strikeThrough: resource.status.strikeThrough,
                letter: resource.status.letter,
                letterColor: resource.status.color,
                actions: [
                  if (hovered) ...[
                    if ((widget.onOpenFile, _deleted(resource)) case (
                      final open?,
                      false,
                    ))
                      IdeActionButton(
                        icon: Codicons.goToFile,
                        size: 20,
                        tooltip: l10n.scmOpenFile,
                        onPressed: () => open(resource.path),
                      ),
                    ..._inline(_actions(resource.group, [resource])),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // A deleted file is not there to put in.
    return _deleted(resource)
        ? listRow
        : _draggable([ComposerFile(resource.path)], listRow);
  }
}
