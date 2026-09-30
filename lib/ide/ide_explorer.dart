/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../platform/app_paths.dart';
import '../theme/codicons.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';
import 'editor/monaco/vs/base/common/labels.dart';
import 'file_service.dart';
import 'git/git_model.dart';
import 'git/git_repository.dart';
import 'ide_commands.dart';
import 'ide_dialog.dart';
import 'ide_input.dart';
import 'ide_list.dart';
import 'ide_menu.dart';

/// One visible row of the explorer tree.
@immutable
class IdeExplorerRow {
  const IdeExplorerRow({
    required this.path,
    required this.name,
    required this.depth,
    required this.isDirectory,
    this.expanded = false,
    this.message,
  });

  final String path;
  final String name;
  final int depth;
  final bool isDirectory;
  final bool expanded;

  /// A non-selectable note under a folder (e.g. a read error) instead of an
  /// entry.
  final String? message;
}

/// The explorer's tree state, kept by the workbench so the expansion survives
/// switching side views and other parts (tabs, breadcrumbs) can reveal paths.
///
/// Entry paths are joined onto [root] from their names, so they match the
/// workspace's document paths even when [root] contains symlinks.
class IdeExplorerController extends ChangeNotifier {
  IdeExplorerController({required this.files, required String root})
    : root = p.normalize(root) {
    unawaited(_load(this.root));
  }

  final IdeFileService files;
  final String root;
  final Map<String, List<IdeFile>> _children = {};
  final Map<String, Object> _errors = {};
  final Set<String> _expanded = {};
  final Map<String, Future<void>> _loads = {};
  List<IdeExplorerRow>? _rows;
  String? _selected;
  int _revealRequest = 0;
  bool _disposed = false;

  /// The selected row's path, if any.
  String? get selected => _selected;

  /// Increments whenever the selection should be scrolled into view.
  int get revealRequest => _revealRequest;

  bool isExpanded(String path) => _expanded.contains(path);

  /// Rows in display order: expanded folders followed by their children.
  List<IdeExplorerRow> get rows => _rows ??= _buildRows();

  List<IdeExplorerRow> _buildRows() {
    final rows = <IdeExplorerRow>[];
    void add(String directory, int depth) {
      if (_errors[directory] case final error?) {
        rows.add(
          IdeExplorerRow(
            path: '$directory${p.separator}',
            name: '',
            depth: depth,
            isDirectory: false,
            message: 'Cannot read folder: $error',
          ),
        );
        return;
      }
      for (final entry in _children[directory] ?? const <IdeFile>[]) {
        final path = p.join(directory, entry.name);
        final expanded = entry.isDirectory && _expanded.contains(path);
        rows.add(
          IdeExplorerRow(
            path: path,
            name: entry.name,
            depth: depth,
            isDirectory: entry.isDirectory,
            expanded: expanded,
          ),
        );
        if (expanded) add(path, depth + 1);
      }
    }

    add(root, 0);
    return rows;
  }

  void _changed() {
    if (_disposed) return;
    _rows = null;
    notifyListeners();
  }

  Future<void> _load(String directory, {bool force = false}) {
    if (!force && _children.containsKey(directory)) return Future.value();
    return _loads[directory] ??= () async {
      try {
        final entries = await files.list(directory);
        _children[directory] = entries;
        _errors.remove(directory);
      } catch (error) {
        _errors[directory] = error;
      } finally {
        _loads.remove(directory);
        _changed();
      }
    }();
  }

  Future<void> expand(String directory) async {
    if (_expanded.add(directory)) _changed();
    await _load(directory);
  }

  void collapse(String directory) {
    if (_expanded.remove(directory)) _changed();
  }

  Future<void> toggle(String directory) => _expanded.contains(directory)
      ? Future.sync(() => collapse(directory))
      : expand(directory);

  /// Collapses every folder.
  void collapseAll() {
    if (_expanded.isEmpty) return;
    _expanded.clear();
    if (_selected case final selected?
        when !rows.any((r) => r.path == selected)) {
      _selected = null;
    }
    _changed();
  }

  void select(String? path, {bool reveal = false}) {
    if (_selected == path && !reveal) return;
    _selected = path;
    if (reveal) _revealRequest++;
    _changed();
  }

  /// Expands the folders above [path], then selects and scrolls to it.
  Future<void> reveal(String path) async {
    final target = p.normalize(path);
    if (target == root || !p.isWithin(root, target)) return;
    final parts = p.split(p.relative(target, from: root));
    var directory = root;
    await _load(directory);
    for (final part in parts.take(parts.length - 1)) {
      directory = p.join(directory, part);
      if (_expanded.add(directory)) _changed();
      await _load(directory);
      if (_disposed) return;
    }
    select(target, reveal: true);
  }

  /// Re-reads the root and every expanded folder, keeping the expansion.
  Future<void> refresh() async {
    final directories = [root, ..._expanded];
    await Future.wait([
      for (final directory in directories) _load(directory, force: true),
    ]);
  }

  /// [directory]'s entries, once read.
  List<IdeFile>? childrenOf(String directory) => _children[directory];

  /// What was cut or copied, to paste into a folder (the explorer's own
  /// clipboard, as VS Code keeps one).
  ({List<String> paths, bool cut})? clipboard;

  /// Forgets [path] and what was under it (after a move or delete), so
  /// folders re-read and the expansion does not point at nothing.
  void forget(String path) {
    bool under(String other) => other == path || p.isWithin(path, other);
    _expanded.removeWhere(under);
    _children.removeWhere((directory, _) => under(directory));
    if (_selected case final selected? when under(selected)) _selected = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The file tree, as VS Code's explorer: chevrons, file icons, indent
/// guides, Git's colors and letters, selection that follows the active
/// editor, keyboard navigation while focused, and the context menu's file
/// operations (new, rename and delete in place, cut, copy and paste).
///
/// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
/// src/vs/workbench/contrib/files/browser (fileActions.ts,
/// fileActions.contribution.ts, views/explorerViewer.ts) and the Git
/// extension's decorations (extensions/git/src/decorationProvider.ts).
///
/// Deviations: one item is selected at a time (no multi-select), nothing is
/// dragged, and deleting cannot be undone from the editor.
class IdeExplorer extends StatefulWidget {
  const IdeExplorer({
    super.key,
    required this.controller,
    required this.onOpen,
    this.focusNode,
    this.git,
    this.onMoved,
    this.onDeleted,
    this.unsavedIn,
    this.trash,
    this.onError,
    this.onFindInFolder,
  });

  final IdeExplorerController controller;

  /// Opens a file; [focusEditor] when opened from the keyboard.
  final void Function(String path, bool focusEditor) onOpen;
  final FocusNode? focusNode;

  /// For the rows' colors and letters.
  final IdeGitRepository? git;

  /// A file or folder was renamed or moved (cut and pasted).
  final void Function(String from, String to)? onMoved;
  final ValueChanged<String>? onDeleted;

  /// How many files in a file or folder have unsaved changes.
  final int Function(String path)? unsavedIn;

  /// Moves a file to the Trash (true once it did); null where there is
  /// none, and files are deleted permanently.
  final Future<bool> Function(String path)? trash;
  final ValueChanged<Object>? onError;

  /// Find in Folder...: searches in a folder.
  final ValueChanged<String>? onFindInFolder;

  static const rowHeight = 22.0;
  static const indent = 12.0;

  @override
  State<IdeExplorer> createState() => IdeExplorerState();
}

/// An inline input in the tree: a new file or folder in [parent], or a
/// rename of [renaming].
class _ExplorerEdit {
  const _ExplorerEdit.create(this.parent, {required this.directory})
    : renaming = null;
  _ExplorerEdit.rename(String this.renaming, {required this.directory})
    : parent = p.dirname(renaming);

  final String parent;
  final bool directory;
  final String? renaming;
}

class IdeExplorerState extends State<IdeExplorer> {
  final ScrollController _scroll = ScrollController();
  FocusNode? _ownFocusNode;
  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode(debugLabel: 'explorer'));
  int _revealed = 0;
  _ExplorerEdit? _edit;

  IdeExplorerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    widget.git?.addListener(_changed);
    _focusNode.addListener(_focusChanged);
    _revealed = _controller.revealRequest;
    if (_controller.selected != null) _scheduleReveal();
  }

  @override
  void didUpdateWidget(IdeExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.git != widget.git) {
      oldWidget.git?.removeListener(_changed);
      widget.git?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    widget.git?.removeListener(_changed);
    _focusNode.removeListener(_focusChanged);
    _ownFocusNode?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    if (_controller.revealRequest != _revealed) {
      _revealed = _controller.revealRequest;
      _scheduleReveal();
    }
  }

  void _report(Object error) => widget.onError?.call(error);

  void _scheduleReveal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final index = _controller.rows.indexWhere(
        (row) => row.path == _controller.selected,
      );
      if (index < 0) return;
      const height = IdeExplorer.rowHeight;
      final position = _scroll.position;
      final top = index * height;
      if (top < position.pixels) {
        _scroll.jumpTo(top);
      } else if (top + height > position.pixels + position.viewportDimension) {
        _scroll.jumpTo(
          (top + height - position.viewportDimension).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  void _activate(IdeExplorerRow row, {required bool keyboard}) {
    if (row.message != null) return;
    _controller.select(row.path);
    if (row.isDirectory) {
      unawaited(_controller.toggle(row.path));
    } else {
      widget.onOpen(row.path, keyboard);
    }
  }

  IdeExplorerRow? get _selectedRow {
    final selected = _controller.selected;
    return _controller.rows.where((row) => row.path == selected).firstOrNull;
  }

  /// The folder new items go in for [row]: itself, or its parent (the
  /// root for none).
  String _folderOf(IdeExplorerRow? row) => row == null
      ? _controller.root
      : row.isDirectory
      ? row.path
      : p.dirname(row.path);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _edit != null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final mac = ideUsesMacKeys;
    final primary = mac ? keys.isMetaPressed : keys.isControlPressed;
    final current = _selectedRow;

    // File operations (fileActions.contribution.ts's keybindings).
    if (current != null && current.message == null) {
      if ((mac && key == LogicalKeyboardKey.enter && !primary) ||
          (!mac && key == LogicalKeyboardKey.f2)) {
        startRename(current);
        return KeyEventResult.handled;
      }
      if ((mac && primary && key == LogicalKeyboardKey.backspace) ||
          (!mac && key == LogicalKeyboardKey.delete)) {
        unawaited(_delete(current, permanently: keys.isAltPressed));
        return KeyEventResult.handled;
      }
      if (primary && key == LogicalKeyboardKey.keyC && !keys.isAltPressed) {
        _controller.clipboard = (paths: [current.path], cut: false);
        return KeyEventResult.handled;
      }
      if (primary && key == LogicalKeyboardKey.keyX) {
        _controller.clipboard = (paths: [current.path], cut: true);
        return KeyEventResult.handled;
      }
    }
    if (primary && key == LogicalKeyboardKey.keyV) {
      unawaited(_paste(_folderOf(current)));
      return KeyEventResult.handled;
    }
    if (mac && primary && key == LogicalKeyboardKey.arrowDown) {
      if (current != null) _activate(current, keyboard: true);
      return KeyEventResult.handled;
    }

    final rows = [
      for (final row in _controller.rows)
        if (row.message == null) row,
    ];
    if (rows.isEmpty) return KeyEventResult.ignored;
    final index = rows.indexWhere((row) => row.path == _controller.selected);
    void selectAt(int i) => _controller.select(
      rows[i.clamp(0, rows.length - 1)].path,
      reveal: true,
    );

    if (key == LogicalKeyboardKey.arrowDown) {
      selectAt(index < 0 ? 0 : index + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      selectAt(index < 0 ? 0 : index - 1);
    } else if (key == LogicalKeyboardKey.home) {
      selectAt(0);
    } else if (key == LogicalKeyboardKey.end) {
      selectAt(rows.length - 1);
    } else if (key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.pageUp) {
      final page = _scroll.hasClients
          ? (_scroll.position.viewportDimension ~/ IdeExplorer.rowHeight) - 1
          : 10;
      selectAt(
        (index < 0 ? 0 : index) +
            (key == LogicalKeyboardKey.pageDown ? page : -page),
      );
    } else if (key == LogicalKeyboardKey.arrowRight) {
      if (current == null) {
        selectAt(0);
      } else if (current.isDirectory && !current.expanded) {
        unawaited(_controller.expand(current.path));
      } else if (current.isDirectory &&
          index + 1 < rows.length &&
          rows[index + 1].depth > current.depth) {
        selectAt(index + 1);
      }
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      if (current == null) {
        selectAt(0);
      } else if (current.isDirectory && current.expanded) {
        _controller.collapse(current.path);
      } else {
        final parent = p.dirname(current.path);
        if (parent != _controller.root) {
          _controller.select(parent, reveal: true);
        }
      }
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (current != null) _activate(current, keyboard: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- File operations -----------------------------------------------------

  /// New File... / New Folder...: an input for the name in [parent] (the
  /// selection's folder when null).
  Future<void> startCreate({String? parent, required bool directory}) async {
    final folder = parent ?? _folderOf(_selectedRow);
    if (folder != _controller.root) await _controller.expand(folder);
    if (!mounted) return;
    setState(() => _edit = _ExplorerEdit.create(folder, directory: directory));
  }

  void startRename(IdeExplorerRow row) {
    if (row.path == _controller.root) return;
    setState(
      () => _edit = _ExplorerEdit.rename(row.path, directory: row.isDirectory),
    );
  }

  void _cancelEdit() {
    if (_edit == null) return;
    setState(() => _edit = null);
    _focusNode.requestFocus();
  }

  /// VS Code's `validateFileName`.
  IdeInputValidation? _validate(_ExplorerEdit edit, String name) {
    if (name.trim().isEmpty) {
      return const IdeInputValidation(
        'A file or folder name must be provided.',
      );
    }
    if (name.startsWith('/') || name.startsWith(r'\')) {
      return const IdeInputValidation(
        'A file or folder name cannot start with a slash.',
      );
    }
    final names = name.split(RegExp(r'[\\/]')).where((n) => n.isNotEmpty);
    final original = edit.renaming == null ? null : p.basename(edit.renaming!);
    if (name != original) {
      final siblings = _controller.childrenOf(edit.parent) ?? const [];
      final first = names.first;
      final exists = siblings.any(
        (entry) =>
            entry.name == first &&
            (names.length == 1 || !entry.isDirectory) &&
            p.join(edit.parent, entry.name) != edit.renaming,
      );
      if (exists) {
        return IdeInputValidation(
          'A file or folder $name already exists at this location. Please '
          'choose a different name.',
        );
      }
    }
    if (names.any((n) => n == '.' || n == '..' || n.contains('\x00'))) {
      return IdeInputValidation(
        'The name $name is not valid as a file or folder name. Please '
        'choose a different name.',
      );
    }
    if (names.any((n) => n.trim() != n)) {
      return const IdeInputValidation(
        'Leading or trailing whitespace detected in file or folder name.',
        IdeValidationSeverity.warning,
      );
    }
    return null;
  }

  Future<void> _commitEdit(_ExplorerEdit edit, String name) async {
    if (!identical(_edit, edit)) return;
    final original = edit.renaming == null ? null : p.basename(edit.renaming!);
    final invalid = _validate(edit, name);
    if (name.trim().isEmpty ||
        name == original ||
        invalid?.severity == IdeValidationSeverity.error) {
      _cancelEdit();
      return;
    }
    setState(() => _edit = null);
    _focusNode.requestFocus();
    final files = _controller.files;
    try {
      if (edit.renaming case final from?) {
        final to = p.join(edit.parent, name);
        await files.rename(from, to);
        _controller.forget(from);
        widget.onMoved?.call(from, to);
        await _controller.refresh();
        await _controller.reveal(to);
      } else {
        // `a/b/c.txt` makes the folders too.
        final parts = name.split(RegExp(r'[\\/]')).where((n) => n.isNotEmpty);
        var folder = edit.parent;
        for (final part in parts.take(parts.length - 1)) {
          folder = p.join(folder, part);
          try {
            await files.create(folder, directory: true);
          } on IdeFileExistsException {
            // Already there.
          }
        }
        final path = p.join(folder, parts.last);
        await files.create(path, directory: edit.directory);
        await _controller.refresh();
        await _controller.reveal(path);
        if (!edit.directory) widget.onOpen(path, true);
      }
    } catch (error) {
      _report(error);
      await _controller.refresh();
    }
  }

  /// Delete (to the Trash where there is one) or, [permanently], Delete
  /// Permanently, confirmed as VS Code's `deleteFiles` confirms.
  Future<void> _delete(IdeExplorerRow row, {bool permanently = false}) async {
    if (row.path == _controller.root) return;
    final trash = permanently ? null : widget.trash;
    final useTrash = trash != null;
    final primary = useTrash ? 'Move to Trash' : 'Delete';
    final unsaved = widget.unsavedIn?.call(row.path) ?? 0;
    final int? pick;
    if (unsaved > 0) {
      pick = await showIdeDialog(
        context,
        message: row.isDirectory
            ? (unsaved == 1
                  ? 'You are deleting a folder ${row.name} with unsaved '
                        'changes in 1 file. Do you want to continue?'
                  : 'You are deleting a folder ${row.name} with unsaved '
                        'changes in $unsaved files. Do you want to continue?')
            : 'You are deleting ${row.name} with unsaved changes. Do you '
                  'want to continue?',
        detail: "Your changes will be lost if you don't save them.",
        buttons: [primary],
      );
    } else if (useTrash) {
      pick = await showIdeDialog(
        context,
        type: IdeDialogType.question,
        message: row.isDirectory
            ? "Are you sure you want to delete '${row.name}' and its contents?"
            : "Are you sure you want to delete '${row.name}'?",
        detail: 'You can restore this file from the Trash.',
        buttons: [primary],
      );
    } else {
      pick = await showIdeDialog(
        context,
        message: row.isDirectory
            ? "Are you sure you want to permanently delete '${row.name}' and "
                  'its contents?'
            : "Are you sure you want to permanently delete '${row.name}'?",
        detail: row.isDirectory
            ? 'This action is irreversible!'
            : 'You can restore this file using the Undo command.',
        buttons: [primary],
      );
    }
    if (pick != 0 || !mounted) return;
    try {
      var trashed = false;
      if (trash != null) {
        try {
          trashed = await trash(row.path);
        } catch (_) {
          if (!mounted) return;
          final again = await showIdeDialog(
            context,
            message:
                'Failed to delete using the Trash. Do you want to permanently '
                'delete instead?',
            detail: row.isDirectory
                ? 'This action is irreversible!'
                : 'You can restore this file using the Undo command.',
            buttons: const ['Delete Permanently'],
          );
          if (again != 0) return;
        }
      }
      if (!trashed) await _controller.files.delete(row.path);
      _controller.forget(row.path);
      widget.onDeleted?.call(row.path);
    } catch (error) {
      _report(error);
    }
    await _controller.refresh();
  }

  /// Paste: copies (with VS Code's simple incremental names when taken) or
  /// moves what was cut into [folder].
  Future<void> _paste(String folder) async {
    final clipboard = _controller.clipboard;
    if (clipboard == null) return;
    final files = _controller.files;
    String? last;
    try {
      await _controller.expand(folder);
      for (final source in clipboard.paths) {
        if (clipboard.cut) {
          final target = p.join(folder, p.basename(source));
          if (target == source) continue;
          if (p.isWithin(source, folder)) {
            _report('File to paste is an ancestor of the destination folder');
            break;
          }
          await files.rename(source, target);
          _controller.forget(source);
          widget.onMoved?.call(source, target);
          last = target;
        } else {
          final isDirectory =
              _controller.rows.any((r) => r.path == source && r.isDirectory) ||
              (_controller.childrenOf(p.dirname(source)) ?? const []).any(
                (e) => e.name == p.basename(source) && e.isDirectory,
              );
          final taken = {
            for (final entry in _controller.childrenOf(folder) ?? const [])
              entry.name,
          };
          var name = p.basename(source);
          while (taken.contains(name)) {
            name = ideIncrementFileName(name, isFolder: isDirectory);
          }
          final target = p.join(folder, name);
          await files.copy(source, target);
          last = target;
        }
      }
      if (clipboard.cut) _controller.clipboard = null;
    } catch (error) {
      _report(error);
    }
    await _controller.refresh();
    if (last != null) await _controller.reveal(last);
  }

  String _relative(String path) =>
      p.relative(path, from: _controller.root).replaceAll(r'\', '/');

  /// `MenuId.ExplorerContext`, for [row] or (null) the empty space below the
  /// rows, which is the root folder's.
  Future<void> _showMenu(Offset position, IdeExplorerRow? row) {
    if (row != null) _controller.select(row.path);
    final path = row?.path ?? _controller.root;
    final isFolder = row == null || row.isDirectory;
    final isRoot = row == null;
    final mac = ideUsesMacKeys;
    String? keys(List<IdeKeybinding> bindings) => [
      for (final binding in bindings)
        if (binding.appliesTo(mac: mac)) binding.label(),
    ].firstOrNull;
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          if (isFolder) ...[
            IdeMenuAction(
              'New File...',
              onSelected: () =>
                  unawaited(startCreate(parent: path, directory: false)),
            ),
            IdeMenuAction(
              'New Folder...',
              onSelected: () =>
                  unawaited(startCreate(parent: path, directory: true)),
            ),
          ],
          if (WindowControls.canRevealInFileManager)
            IdeMenuAction(
              'Reveal in Finder',
              keybinding: keys(const [
                IdeKeybinding(
                  LogicalKeyboardKey.keyR,
                  primary: true,
                  alt: true,
                  mac: true,
                ),
              ]),
              onSelected: () =>
                  unawaited(WindowControls.revealInFileManager(path)),
            ),
        ],
        [
          if (isFolder && widget.onFindInFolder != null)
            IdeMenuAction(
              'Find in Folder...',
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.keyF, shift: true, alt: true),
              ]),
              onSelected: () => widget.onFindInFolder!(path),
            ),
        ],
        [
          if (!isRoot) ...[
            IdeMenuAction(
              'Cut',
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.keyX, primary: true),
              ]),
              onSelected: () =>
                  _controller.clipboard = (paths: [path], cut: true),
            ),
            IdeMenuAction(
              'Copy',
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.keyC, primary: true),
              ]),
              onSelected: () =>
                  _controller.clipboard = (paths: [path], cut: false),
            ),
          ],
          if (isFolder)
            IdeMenuAction(
              'Paste',
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.keyV, primary: true),
              ]),
              enabled: _controller.clipboard != null,
              onSelected: () => unawaited(_paste(path)),
            ),
        ],
        [
          IdeMenuAction(
            'Copy Path',
            keybinding: keys(const [
              IdeKeybinding(
                LogicalKeyboardKey.keyC,
                primary: true,
                alt: true,
                mac: true,
              ),
              IdeKeybinding(
                LogicalKeyboardKey.keyC,
                shift: true,
                alt: true,
                mac: false,
              ),
            ]),
            onSelected: () =>
                unawaited(Clipboard.setData(ClipboardData(text: path))),
          ),
          IdeMenuAction(
            'Copy Relative Path',
            keybinding: keys(const [
              IdeKeybinding(
                LogicalKeyboardKey.keyC,
                primary: true,
                alt: true,
                shift: true,
                mac: true,
              ),
            ]),
            onSelected: () => unawaited(
              Clipboard.setData(ClipboardData(text: _relative(path))),
            ),
          ),
        ],
        [
          if (!isRoot) ...[
            IdeMenuAction(
              'Rename...',
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.enter, mac: true),
                IdeKeybinding(LogicalKeyboardKey.f2, mac: false),
              ]),
              onSelected: () => startRename(row),
            ),
            IdeMenuAction(
              'Delete',
              keybinding: keys(const [
                IdeKeybinding(
                  LogicalKeyboardKey.backspace,
                  primary: true,
                  mac: true,
                ),
                IdeKeybinding(LogicalKeyboardKey.delete, mac: false),
              ]),
              onSelected: () => unawaited(_delete(row)),
            ),
          ],
        ],
      ]),
    );
  }

  // --- Rows ----------------------------------------------------------------

  /// The rows with the edit's input in place: a new item first in its
  /// folder, a rename in its row.
  List<(IdeExplorerRow, bool)> _rowsWithEdit() {
    final rows = _controller.rows;
    final edit = _edit;
    if (edit == null) return [for (final row in rows) (row, false)];
    if (edit.renaming case final renaming?) {
      return [for (final row in rows) (row, row.path == renaming)];
    }
    IdeExplorerRow input(int depth) => IdeExplorerRow(
      path: p.join(edit.parent, '\x00new'),
      name: '',
      depth: depth,
      isDirectory: edit.directory,
    );
    final result = <(IdeExplorerRow, bool)>[
      if (edit.parent == _controller.root) (input(0), true),
    ];
    for (final row in rows) {
      result.add((row, false));
      if (row.path == edit.parent) result.add((input(row.depth + 1), true));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rowsWithEdit();
    final focused = _focusNode.hasFocus;
    final decorations = widget.git?.decorations;
    return ColoredBox(
      // Modern UI: the panes are the side bar's.
      color: themeColors['sideBar.background'],
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _focusNode.requestFocus,
          onSecondaryTapUp: (details) {
            _focusNode.requestFocus();
            unawaited(_showMenu(details.globalPosition, null));
          },
          child: ListView.builder(
            controller: _scroll,
            itemExtent: IdeExplorer.rowHeight,
            padding: const EdgeInsets.only(bottom: 12),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final (row, editing) = rows[index];
              if (editing) {
                final edit = _edit!;
                return _ExplorerEditRow(
                  key: ValueKey(('edit', row.path)),
                  row: row,
                  edit: edit,
                  validate: (name) => _validate(edit, name),
                  onSubmit: (name) => unawaited(_commitEdit(edit, name)),
                  onCancel: _cancelEdit,
                );
              }
              return _ExplorerRowView(
                key: ValueKey(row.path),
                row: row,
                selected: row.path == _controller.selected,
                focused: focused,
                decoration: decorations == null || row.message != null
                    ? null
                    : row.isDirectory
                    ? decorations.folder(row.path)
                    : decorations.file(row.path),
                onTap: () {
                  _focusNode.requestFocus();
                  _activate(row, keyboard: false);
                },
                onContextMenu: (position) {
                  _focusNode.requestFocus();
                  unawaited(_showMenu(position, row));
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// VS Code's `incrementFileName` with `explorer.incrementalNaming: simple`:
/// `a.txt` → `a copy.txt` → `a copy 2.txt`.
String ideIncrementFileName(String name, {required bool isFolder}) {
  final extension = isFolder ? '' : p.extension(name);
  final prefix = isFolder ? name : p.basenameWithoutExtension(name);
  final match = RegExp(r'^(.+ copy)( \d+)?$').firstMatch(prefix);
  if (match != null) {
    final number = match[2] == null ? 1 : int.parse(match[2]!.trim());
    return number == 0
        ? '${match[1]}$extension'
        : '${match[1]} ${number + 1}$extension';
  }
  return '$prefix copy$extension';
}

/// The user's home, which path labels start at as `~` (none on the web).
final String _userHome = kIsWeb ? '' : AppPaths.home(Platform.environment);

String _pathLabel(String path) => tildify(path, _userHome);

class _ExplorerRowView extends StatelessWidget {
  const _ExplorerRowView({
    super.key,
    required this.row,
    required this.selected,
    required this.focused,
    required this.decoration,
    required this.onTap,
    required this.onContextMenu,
  });

  final IdeExplorerRow row;
  final bool selected;
  final bool focused;
  final IdeGitDecoration? decoration;
  final VoidCallback onTap;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final left = 4 + row.depth * IdeExplorer.indent;
    final guides = CustomPaint(
      painter: _IndentGuidesPainter(
        row.depth,
        themeColors['tree.inactiveIndentGuidesStroke'],
      ),
      child: const SizedBox.expand(),
    );
    if (row.message case final message?) {
      return Stack(
        children: [
          Positioned.fill(child: guides),
          Padding(
            padding: EdgeInsets.only(left: left + 24, right: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: IdeListColors.errorForeground,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      );
    }
    final decoration = this.decoration;
    final color = decoration?.color;
    final letter = decoration?.letter;
    return IdeListRow(
      selected: selected,
      focused: focused,
      onTap: onTap,
      onContextMenu: onContextMenu,
      // ResourceLabel's title (labels.ts): the path label, tildified as
      // `labelService.getUriLabel` does, then the decoration's.
      tooltip: switch (decoration?.tooltip) {
        final tooltip? => '${_pathLabel(row.path)} • $tooltip',
        null => _pathLabel(row.path),
      },
      builder: (context, hovered) {
        // The row's color (`listWidget.ts` `DefaultStyleController`), and
        // its twistie's: `icon.foreground`, but the row's when selected
        // unless the theme has a selection icon color.
        final foreground = selected
            ? (focused
                  ? IdeListColors.activeSelectionForeground
                  : IdeListColors.inactiveSelectionForeground)
            : hovered
            ? IdeListColors.hoverForeground
            : IdeListColors.foreground;
        final twistie = selected
            ? themeColors.get(
                    focused
                        ? 'list.activeSelectionIconForeground'
                        : 'list.inactiveSelectionIconForeground',
                  ) ??
                  foreground
            : themeColors['icon.foreground'];
        return Stack(
          children: [
            Positioned.fill(child: guides),
            Padding(
              padding: EdgeInsets.only(left: left),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    child: row.isDirectory
                        ? Icon(
                            row.expanded
                                ? Codicons.chevronDown
                                : Codicons.chevronRight,
                            size: 16,
                            color: twistie,
                          )
                        : null,
                  ),
                  const SizedBox(width: 2),
                  if (row.isDirectory)
                    FolderIcon(row.path, size: 16, expanded: row.expanded)
                  else
                    FileIcon(row.path, size: 16),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: color ?? foreground,
                        decoration: decoration?.strikeThrough ?? false
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: color,
                      ),
                    ),
                  ),
                  if (letter == '•')
                    // `bubble`: a dot for a folder with changes inside.
                    Padding(
                      padding: const EdgeInsets.only(left: 5, right: 14),
                      child: Icon(
                        Codicons.circleFilled,
                        size: 14,
                        color: (color ?? foreground).withValues(alpha: .4),
                      ),
                    )
                  else if (letter != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 5, right: 16),
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 13 * .9,
                          fontWeight: FontWeight.w600,
                          color: (color ?? foreground).withValues(alpha: .75),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A row's inline input: New File/Folder's name, or a rename.
class _ExplorerEditRow extends StatefulWidget {
  const _ExplorerEditRow({
    super.key,
    required this.row,
    required this.edit,
    required this.validate,
    required this.onSubmit,
    required this.onCancel,
  });

  final IdeExplorerRow row;
  final _ExplorerEdit edit;
  final IdeInputValidation? Function(String name) validate;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;

  @override
  State<_ExplorerEditRow> createState() => _ExplorerEditRowState();
}

class _ExplorerEditRowState extends State<_ExplorerEditRow> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode(debugLabel: 'explorer input');
  IdeInputValidation? _validation;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    final name = widget.edit.renaming == null
        ? ''
        : p.basename(widget.edit.renaming!);
    // A rename selects the name without its extension.
    final dot = name.lastIndexOf('.');
    final end = widget.edit.directory || dot <= 0 ? name.length : dot;
    _controller = TextEditingController(text: name)
      ..selection = TextSelection(baseOffset: 0, extentOffset: end);
    _focus.addListener(_blurred);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.removeListener(_blurred);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Leaving the input accepts it, as VS Code's does.
  void _blurred() {
    if (!_focus.hasFocus && !_done && mounted) _submit();
  }

  void _submit() {
    if (_done) return;
    _done = true;
    widget.onSubmit(_controller.text);
  }

  void _cancel() {
    if (_done) return;
    _done = true;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final left = 4 + IdeListColors.inset + row.depth * IdeExplorer.indent;
    final name = _controller.text;
    return Padding(
      padding: EdgeInsets.only(left: left, right: IdeListColors.inset + 4),
      child: Row(
        children: [
          const SizedBox(width: 18),
          if (row.isDirectory)
            FolderIcon(p.join(widget.edit.parent, name), size: 16)
          else
            FileIcon(name.isEmpty ? 'file' : name, size: 16),
          const SizedBox(width: 5),
          Expanded(
            child: IdeInputBox(
              controller: _controller,
              focusNode: _focus,
              fontSize: 13,
              lineHeight: 18,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              validation: _validation,
              floatingValidation: true,
              onChanged: (value) =>
                  setState(() => _validation = widget.validate(value)),
              onSubmitted: (_) => _submit(),
              shortcuts: {
                const SingleActivator(LogicalKeyboardKey.escape): _cancel,
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// The row's indent guides, all in `tree.inactiveIndentGuidesStroke` (none
/// is the active one's).
class _IndentGuidesPainter extends CustomPainter {
  const _IndentGuidesPainter(this.depth, this.color);

  final int depth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (depth == 0) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var level = 0; level < depth; level++) {
      final x = 4 + level * IdeExplorer.indent + 8.5;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_IndentGuidesPainter oldDelegate) =>
      oldDelegate.depth != depth || oldDelegate.color != color;
}
