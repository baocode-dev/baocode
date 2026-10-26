/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import 'dart:async';
import 'dart:collection' show UnmodifiableSetView;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../base/smooth_scroll.dart';
import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drag.dart';
import '../chat/composer/file_drop.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../platform/app_paths.dart';
import '../theme/codicons.dart';
import 'ide_hover.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';

import 'package:bao_editor/monaco/vs/base/common/labels.dart';

import 'explorer_excludes.dart';
import 'explorer_history.dart';
import 'explorer_line_count.dart';
import 'file_service.dart';
import 'git/git_model.dart';
import 'git/git_repository.dart';
import 'ide_commands.dart';
import 'ide_dialog.dart';
import 'ide_input.dart';
import 'ide_list.dart';
import 'ide_menu.dart';
import 'ide_notifications.dart';
import 'save_copy.dart';

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
    this.error,
    this.isRoot = false,
  });

  final String path;
  final String name;
  final int depth;
  final bool isDirectory;
  final bool expanded;

  /// A folder of a multi-folder workspace, at the top of the tree: not
  /// renamed, moved nor deleted from it, only taken out of the workspace.
  final bool isRoot;

  /// A non-selectable note under a folder instead of an entry: the error
  /// reading it.
  final String? message;

  /// What reading the folder failed with, for [message].
  final Object? error;
}

/// The explorer's tree state, kept by the workbench so the expansion survives
/// switching side views and other parts (tabs, breadcrumbs) can reveal paths.
///
/// Entry paths are joined onto [root] from their names, so they match the
/// workspace's document paths even when [root] contains symlinks.
class IdeExplorerController extends ChangeNotifier {
  IdeExplorerController({
    required this.files,
    required String root,
    Stream<void> Function(String directory)? watch,
    List<String> roots = const [],
    p.Context? paths,
    IdeExplorerExcludes excludes = IdeExplorerExcludes.none,
    IdeExplorerLineCount? lineCount,
  }) : paths = paths ?? p.context,
       // A private field with a setter, so the parameter cannot be an
       // initializing formal.
       // ignore: prefer_initializing_formals
       _excludes = excludes,
       root = (paths ?? p.context).normalize(root),
       _watchDirectory =
           watch ??
           switch (files) {
             final IdeHostFiles files => files.watchDirectory,
             _ => watchDirectory,
           } {
    this.lineCount = lineCount ?? IdeExplorerLineCount(files: files, paths: this.paths);
    unawaited(_load(this.root));
    this.roots = roots;
    _watchExpanded();
  }

  late final IdeExplorerLineCount lineCount;

  final IdeFileService files;
  final String root;
  final p.Context paths;

  /// The files and folders the tree leaves out (see
  /// [IdeExplorerExcludes]).
  IdeExplorerExcludes get excludes => _excludes;
  IdeExplorerExcludes _excludes;

  /// Shows [excludes] (the setting changed): the rows are made again.
  set excludes(IdeExplorerExcludes excludes) {
    if (_excludes == excludes) return;
    _excludes = excludes;
    _changed();
  }

  /// Whether [path] is shown: not among [excludes]. A hidden folder is not
  /// descended into, so what is under it is left out with it.
  bool _shown(String path) =>
      _excludes.isEmpty || !_excludes.hides(path, rootOf(path), paths);

  /// A multi-folder workspace's folders, the tree's top rows in place of
  /// [root]'s entries (as VS Code lists workspace folders); none for a
  /// folder's project.
  List<String> get roots => _roots;
  List<String> _roots = const [];

  /// Shows [roots] at the top of the tree: those added expanded, as VS
  /// Code opens them.
  set roots(List<String> roots) {
    final normalized = [for (final root in roots) paths.normalize(root)];
    if (listEquals(normalized, _roots)) return;
    for (final root in normalized) {
      if (!_roots.contains(root)) {
        _expanded.add(root);
        unawaited(_load(root));
      }
    }
    _expanded.removeWhere(
      (path) => !_inTree(path, normalized) && paths.isWithin(root, path),
    );
    _roots = normalized;
    _changed();
  }

  /// Whether [path] is a row's: under [roots], or [root] for a folder.
  bool _inTree(String path, List<String> roots) => roots.isEmpty
      ? paths.isWithin(root, path)
      : roots.any((r) => r == path || paths.isWithin(r, path));

  /// Whether [path] is in the tree: under [root], or a workspace folder.
  bool shows(String path) => _inTree(paths.normalize(path), _roots);

  /// Whether [path] is a workspace folder: the top of a tree.
  bool isRoot(String path) => path == root || _roots.contains(path);

  /// The top of [path]'s tree: its workspace folder, or [root].
  String rootOf(String path) {
    for (final root in _roots) {
      if (root == path || paths.isWithin(root, path)) return root;
    }
    return root;
  }

  /// Whether [path] is a folder with a row: one that may hold others
  /// selected (a workspace folder's, but not [root]).
  bool isFolderRow(String path) => _roots.isEmpty
      ? path != root && paths.isWithin(root, path)
      : _inTree(path, _roots);

  /// Where new items go when no row says: [root], or the first workspace
  /// folder.
  String get defaultFolder => _roots.firstOrNull ?? root;

  /// The root and the expanded folders, watched so the tree shows files
  /// made, moved or deleted outside it (an agent's, a terminal's), as VS
  /// Code's explorer follows its file watcher.
  final Stream<void> Function(String directory) _watchDirectory;
  final Map<String, StreamSubscription<void>> _watches = {};
  final Set<String> _changedDirectories = {};
  Timer? _changesTimer;
  final Map<String, List<IdeFile>> _children = {};
  final Map<String, Object> _errors = {};

  /// The file operations done here, to undo and redo.
  final ExplorerHistory history = ExplorerHistory();
  final Set<String> _expanded = {};
  final Map<String, Future<void>> _loads = {};
  List<IdeExplorerRow>? _rows;
  final IdeListSelection<String> _listSelection = IdeListSelection<String>();
  int _revealRequest = 0;
  bool _disposed = false;

  /// The focused row's path, if any (upstream's focus, as distinct from the
  /// selection): the one the keys move from, and which is acted on alone
  /// when it is not in the [selection].
  String? get selected => _listSelection.focused;

  /// The selected rows' paths: the focused one's alone, unless a modifier
  /// click or Shift with the arrows selected more.
  Set<String> get selection => UnmodifiableSetView(_listSelection.values);

  bool isSelected(String path) => _listSelection.values.contains(path);

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
            path: '$directory${paths.separator}',
            name: '',
            depth: depth,
            isDirectory: false,
            message: '$error',
            error: error,
          ),
        );
        return;
      }
      for (final entry in _children[directory] ?? const <IdeFile>[]) {
        final path = paths.join(directory, entry.name);
        // A hidden one is left out with everything under it.
        if (!_shown(path)) continue;
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

    if (_roots.isEmpty) {
      add(root, 0);
      return rows;
    }
    for (final folder in _roots) {
      final expanded = _expanded.contains(folder);
      rows.add(
        IdeExplorerRow(
          path: folder,
          name: paths.basename(folder),
          depth: 0,
          isDirectory: true,
          expanded: expanded,
          isRoot: true,
        ),
      );
      if (expanded) add(folder, 1);
    }
    return rows;
  }

  void _changed() {
    if (_disposed) return;
    _rows = null;
    _watchExpanded();
    notifyListeners();
  }

  /// Watches the root and the expanded folders, and no others.
  void _watchExpanded() {
    final directories = {root, ..._expanded};
    for (final directory in _watches.keys.toList()) {
      if (!directories.contains(directory)) {
        unawaited(_watches.remove(directory)!.cancel());
      }
    }
    for (final directory in directories) {
      if (_watches.containsKey(directory)) continue;
      _watches[directory] = _watchDirectory(directory).listen((_) {
        _changedDirectories.add(directory);
        // Read at most once per [_changesDelay], even while a build or an
        // install keeps writing.
        _changesTimer ??= Timer(_changesDelay, _reloadChanged);
      });
      // Unwatched while collapsed: what was read then may be stale.
      if (_children.containsKey(directory)) {
        unawaited(_load(directory, force: true));
      }
    }
  }

  static const _changesDelay = Duration(milliseconds: 200);

  void _reloadChanged() {
    _changesTimer = null;
    final directories = {..._changedDirectories};
    _changedDirectories.clear();
    for (final directory in directories) {
      if (_watches.containsKey(directory)) {
        unawaited(_load(directory, force: true));
      }
    }
    lineCount.clear();
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
    if (!_expanded.remove(directory)) return;
    _listSelection.values.removeWhere(
      (path) => paths.isWithin(directory, path),
    );
    _changed();
  }

  Future<void> toggle(String directory) => _expanded.contains(directory)
      ? Future.sync(() => collapse(directory))
      : expand(directory);

  /// Collapses every folder.
  void collapseAll() {
    if (_expanded.isEmpty) return;
    _expanded.clear();
    _rows = null;
    final shown = {for (final row in rows) row.path};
    if (_listSelection.focused case final selected?
        when !shown.contains(selected)) {
      _listSelection.focused = null;
    }
    _listSelection.values.retainWhere(shown.contains);
    _changed();
  }

  /// Focuses and selects [path] alone (none for null), as a click does.
  void select(String? path, {bool reveal = false}) {
    if (!reveal &&
        _listSelection.focused == path &&
        setEquals(_listSelection.values, {?path})) {
      return;
    }
    _listSelection.select(path);
    if (reveal) _revealRequest++;
    _changed();
  }

  /// Adds [path] to the selection, or takes it out, and focuses it, as a
  /// Cmd (Ctrl) click does.
  void toggleSelection(String path) {
    _listSelection.toggle(path);
    _changed();
  }

  /// Selects the rows from the last one clicked to [path] and focuses it,
  /// as a Shift click or Shift with the arrows does.
  void selectRange(String path, {bool reveal = false}) {
    final paths = [
      for (final row in rows)
        if (row.message == null) row.path,
    ];
    if (!paths.contains(path)) return;
    _listSelection.range(path, paths);
    if (reveal) _revealRequest++;
    _changed();
  }

  /// Selects every row shown (`list.selectAll`).
  void selectAll() {
    final paths = [
      for (final row in rows)
        if (row.message == null) row.path,
    ];
    if (paths.isEmpty) return;
    _listSelection.selectAll(paths);
    _changed();
  }

  /// Expands the folders above [path], then selects and scrolls to it.
  Future<void> reveal(String path) async {
    final target = paths.normalize(path);
    if (target == root || !_inTree(target, _roots)) return;
    final top = rootOf(target);
    if (top == target) return select(target, reveal: true);
    final parts = paths.split(paths.relative(target, from: top));
    var directory = top;
    if (top != root && _expanded.add(top)) _changed();
    await _load(directory);
    for (final part in parts.take(parts.length - 1)) {
      directory = paths.join(directory, part);
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
  IdeExplorerClipboard? clipboard;

  /// Forgets [path] and what was under it (after a move or delete), so
  /// folders re-read and the expansion does not point at nothing.
  void forget(String path) {
    bool under(String other) => other == path || paths.isWithin(path, other);
    _expanded.removeWhere(under);
    _children.removeWhere((directory, _) => under(directory));
    if (_listSelection.focused case final selected? when under(selected)) {
      _listSelection.focused = null;
    }
    if (_listSelection.anchor case final anchor? when under(anchor)) {
      _listSelection.anchor = null;
    }
    _listSelection.values.removeWhere(under);
    lineCount.invalidate(path);
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _changesTimer?.cancel();
    for (final watch in _watches.values) {
      unawaited(watch.cancel());
    }
    _watches.clear();
    lineCount.dispose();
    super.dispose();
  }
}

/// What was cut or copied in an explorer, and what the system's clipboard
/// held once it was: files copied there since (in Finder, in Explorer, in
/// another tree) are what a paste puts in instead.
class IdeExplorerClipboard {
  IdeExplorerClipboard(this.files, {required this.cut, required this.system});

  final List<ComposerFile> files;
  final bool cut;

  /// The paths on the system's clipboard once [files] were cut or copied.
  final Future<Set<String>> system;
}

/// The files and folders on the system's clipboard; none when it cannot be
/// read.
Future<List<ComposerFile>> _systemClipboardFiles() async {
  try {
    return await WindowControls.readPasteboardFiles();
  } on PlatformException {
    return const [];
  }
}

Set<String> _pathsOf(List<ComposerFile> files) => {
  for (final file in files) p.normalize(file.path),
};

/// The file tree, as VS Code's explorer: chevrons, file icons, indent
/// guides, Git's colors and letters, selection that follows the active
/// editor, keyboard navigation while focused, and the context menu's file
/// operations (new, rename and delete in place, cut, copy and paste, with
/// the system's clipboard too).
///
/// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
/// src/vs/workbench/contrib/files/browser (fileActions.ts,
/// fileActions.contribution.ts, views/explorerViewer.ts) and the Git
/// extension's decorations (extensions/git/src/decorationProvider.ts).
///
/// Deviations: items drag only onto the chat's composer (not to move
/// them), and deleting cannot be undone from the editor. Copied, local
/// items are on the system's clipboard too, and files copied there (in
/// Finder, in Explorer) paste in as copies, onto a remote project's host
/// too. Where no workbench runs its keybindings (the chat's side panel), it
/// runs those of its own commands itself.
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
    this.onOpenInDefaultApp,
    this.onFindInFolder,
    this.onShowHistory,
    this.onOpenInTerminal,
    this.isBound,
    this.local = true,
    this.repositories = const [],
    this.onAddFolder,
    this.onRemoveFolder,
    this.background,
  });

  final IdeExplorerController controller;

  /// What it is on; the side bar's by default.
  final Color? background;

  /// A multi-folder workspace's repositories, for the rows' colors and
  /// letters in place of [git]'s: each path's, that of the folder it is in.
  final List<IdeGitRepository> repositories;

  /// Add Folder to Workspace...; none for a folder's project.
  final VoidCallback? onAddFolder;

  /// Remove Folder from Workspace, of a workspace folder's row.
  final ValueChanged<String>? onRemoveFolder;

  /// Whether the files are this machine's: a remote project's are not
  /// shown in the file manager.
  final bool local;

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

  /// Open in Default App: hands a file to the app the system opens it
  /// with; none where there is no such app.
  final ValueChanged<String>? onOpenInDefaultApp;

  /// Find in Folder...: searches in a folder.
  final ValueChanged<String>? onFindInFolder;

  /// Shows the Git log of a file or folder: Show History.
  final ValueChanged<String>? onShowHistory;

  /// Open in Terminal: opens a terminal in the folder, or in the one
  /// holding the file; null where there are no terminals.
  final ValueChanged<String>? onOpenInTerminal;

  /// Whether a keybinding has a key: the explorer leaves it to the
  /// workbench, which runs its command (see [IdeExplorerState.contextKey]).
  final bool Function(KeyEvent event)? isBound;

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
  _ExplorerEdit.rename(
    String this.renaming, {
    required this.parent,
    required this.directory,
  });

  final String parent;
  final bool directory;
  final String? renaming;
}

class IdeExplorerState extends State<IdeExplorer>
    with IdeKeyboardList<IdeExplorer> {
  final ScrollController _scroll = SmoothScrollController();
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
    _controller.lineCount.addListener(_changed);
    widget.git?.addListener(_changed);
    for (final repository in widget.repositories) {
      repository.addListener(_changed);
    }
    _focusNode.addListener(_focusChanged);
    _revealed = _controller.revealRequest;
    if (_controller.selected != null) _scheduleReveal();
  }

  @override
  void didUpdateWidget(IdeExplorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.lineCount.removeListener(_changed);
      widget.controller.lineCount.addListener(_changed);
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.git != widget.git) {
      oldWidget.git?.removeListener(_changed);
      widget.git?.addListener(_changed);
    }
    if (!listEquals(oldWidget.repositories, widget.repositories)) {
      for (final repository in oldWidget.repositories) {
        repository.removeListener(_changed);
      }
      for (final repository in widget.repositories) {
        repository.addListener(_changed);
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.lineCount.removeListener(_changed);
    widget.git?.removeListener(_changed);
    for (final repository in widget.repositories) {
      repository.removeListener(_changed);
    }
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
      final top = index * IdeExplorer.rowHeight;
      ideRevealRange(_scroll, top, top + IdeExplorer.rowHeight);
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

  /// A click: with Shift, selects the rows from the last one clicked; with
  /// Cmd (Ctrl), adds the row to the selection or takes it out; else opens
  /// it (upstream's `multiSelectModifier`, `ctrlCmd`).
  void _click(IdeExplorerRow row) {
    if (row.message != null) return;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      _controller.selectRange(row.path);
    } else if (ideUsesMacKeys
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed) {
      _controller.toggleSelection(row.path);
    } else {
      _activate(row, keyboard: false);
    }
  }

  IdeExplorerRow? get _selectedRow {
    final selected = _controller.selected;
    return _controller.rows.where((row) => row.path == selected).firstOrNull;
  }

  /// What a command or the menu acts on for [row] (the focused row when
  /// null): the selection when [row] is in it, else [row] alone; of the
  /// selection, none under another selected folder (upstream
  /// `getMultiSelectedResources` and `distinctParents`).
  List<IdeExplorerRow> _targets([IdeExplorerRow? row]) {
    row ??= _selectedRow;
    if (row == null) return const [];
    final selection = _controller.selection;
    if (selection.length < 2 || !selection.contains(row.path)) return [row];
    bool underSelected(String path) {
      for (
        var parent = _controller.paths.dirname(path);
        _controller.isFolderRow(parent);
        parent = _controller.paths.dirname(parent)
      ) {
        if (selection.contains(parent)) return true;
      }
      return false;
    }

    return [
      for (final row in _controller.rows)
        if (row.message == null &&
            selection.contains(row.path) &&
            !underSelected(row.path))
          row,
    ];
  }

  /// The folder new items go in for [row]: itself, or its parent (the
  /// root for none).
  String _folderOf(IdeExplorerRow? row) => row == null
      ? _controller.defaultFolder
      : row.isDirectory
      ? row.path
      : _controller.paths.dirname(row.path);

  // --- Commands ------------------------------------------------------------
  // What the explorer's keybindings run, under upstream's ids: the file
  // operations of fileActions.contribution.ts (`explorer.newFile`,
  // `renameFile`, `moveFileToTrash`, `filesExplorer.copy`…) and the list
  // commands of listCommands.ts (`list.focusDown`, `list.expand`…). The
  // workbench resolves the keys (default_keybindings.dart), so keymaps and
  // keybindings.json decide them.

  /// Whether a keybinding has [event]: it is left to the workbench, which
  /// runs it, or, with none ([IdeExplorer.isBound] null), run here when it
  /// is one of [_commands]. A navigation key none has is kept, as
  /// upstream's list keeps it, rather than moving the focus out.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || _edit != null) return KeyEventResult.ignored;
    if (widget.isBound case final isBound?) {
      if (isBound(event)) return KeyEventResult.ignored;
    } else if (_runKeybinding(event)) {
      return KeyEventResult.handled;
    }
    return ideListNavigationKeys.contains(event.logicalKey)
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  /// Runs the command of [event]'s keybinding, when it is one of
  /// [_commands]; whether it did.
  bool _runKeybinding(KeyEvent event) {
    final commands = _commands;
    final resolution = KeybindingService.instance.resolveEvent(
      event,
      context: _focusedContextKey,
      canRun: (item) => commands.containsKey(item.command),
    );
    if (resolution is! KeybindingFound) return false;
    commands[resolution.command]!(resolution.item.entry.args);
    return true;
  }

  /// The explorer's commands its keybindings run where no workbench runs
  /// them, by upstream's ids, given their arguments.
  Map<String, void Function(Object? args)> get _commands {
    // `list.focusDown` / `list.focusUp`'s argument: how many rows.
    int rows(Object? args) => args is num ? args.toInt() : 1;
    return {
      'explorer.newFile': (_) => unawaited(startCreate(directory: false)),
      'explorer.newFolder': (_) => unawaited(startCreate(directory: true)),
      'renameFile': (_) => renameSelected(),
      'moveFileToTrash': (_) => unawaited(deleteSelected()),
      'deleteFile': (_) => unawaited(deleteSelected(permanently: true)),
      'filesExplorer.copy': (_) => copySelected(),
      'filesExplorer.cut': (_) => copySelected(cut: true),
      'filesExplorer.paste': (_) => unawaited(pasteSelected()),
      'filesExplorer.openFilePreserveFocus': (_) => previewSelected(),
      'list.focusDown': (args) => focusNext(rows(args)),
      'list.focusUp': (args) => focusNext(-rows(args)),
      'list.focusPageDown': (_) => focusPage(1),
      'list.focusPageUp': (_) => focusPage(-1),
      'list.focusFirst': (_) => focusFirst(),
      'list.focusLast': (_) => focusLast(),
      'list.expand': (_) => expandSelected(),
      'list.collapse': (_) => collapseSelected(),
      'list.select': (_) => openSelected(),
      'list.toggleExpand': (_) => toggleSelected(),
      'list.expandSelectionDown': (_) => expandSelection(1),
      'list.expandSelectionUp': (_) => expandSelection(-1),
      'list.selectAll': (_) => selectAll(),
      'list.clear': (_) => clearSelection(),
      'list.collapseAll': (_) => _controller.collapseAll(),
      explorerUndoCommandId: (_) => unawaited(undo()),
      explorerRedoCommandId: (_) => unawaited(redo()),
    };
  }

  /// The context keys with the focus here.
  Object? _focusedContextKey(String key) => switch (key) {
    'filesExplorerFocus' ||
    'foldersViewVisible' ||
    'explorerViewletVisible' ||
    'listFocus' => true,
    'inputFocus' || 'textInputFocus' => false,
    _ => contextKey(key),
  };

  /// The explorer's context keys for its selection (upstream's
  /// `explorerResource*` and the tree's `treeElement*`); null for others.
  Object? contextKey(String key) {
    final row = _selectedRow;
    final folder = row != null && row.isDirectory;
    return switch (key) {
      // None selected: the root folder's.
      'explorerResourceIsRoot' => row == null || row.isRoot,
      'explorerResourceIsFolder' => row == null || folder,
      'explorerResourceReadonly' => false,
      'explorerResourceMoveableToTrash' => widget.trash != null,
      'treeElementCanCollapse' => folder && row.expanded,
      'treeElementCanExpand' => folder && !row.expanded,
      'treeElementHasChild' => folder && row.expanded && _firstChild != null,
      'treeElementHasParent' => row != null && row.depth > 0,
      'listSupportsMultiselect' => true,
      'listHasSelectionOrFocus' =>
        row != null || _controller.selection.isNotEmpty,
      _ => null,
    };
  }

  /// The rows a keyboard moves over (not messages).
  List<IdeExplorerRow> get _navigable => [
    for (final row in _controller.rows)
      if (row.message == null) row,
  ];

  int get _selectedIndex =>
      _navigable.indexWhere((row) => row.path == _controller.selected);

  IdeExplorerRow? get _firstChild {
    final rows = _navigable;
    final index = _selectedIndex;
    if (index < 0 || index + 1 >= rows.length) return null;
    final next = rows[index + 1];
    return next.depth > rows[index].depth ? next : null;
  }

  @override
  bool get listHasFocus => _focusNode.hasFocus;

  @override
  int get listLength => _navigable.length;

  @override
  int get listFocusedIndex => _selectedIndex;

  @override
  int get listPageSize =>
      ideRowsPerPage(_scroll, rowHeight: IdeExplorer.rowHeight);

  @override
  void listFocusAt(int index) {
    final rows = _navigable;
    if (rows.isEmpty) return;
    _controller.select(
      rows[index.clamp(0, rows.length - 1)].path,
      reveal: true,
    );
  }

  @override
  void listSelect() => openSelected();

  @override
  void listToggleExpand() => toggleSelected();

  @override
  void listExpand() => expandSelected();

  @override
  void listCollapse() => collapseSelected();

  @override
  void listCollapseAll() => _controller.collapseAll();

  @override
  bool get listSupportsMultiselect => true;

  @override
  bool get listHasSelection =>
      _controller.selected != null || _controller.selection.isNotEmpty;

  @override
  void listExpandSelection(int delta) => expandSelection(delta);

  @override
  void listSelectAll() => selectAll();

  @override
  void listClear() => clearSelection();

  @override
  bool listTreeKey(String key) => contextKey(key) == true;

  void focusNext(int delta) => listFocusNext(delta);

  void focusPage(int direction) => listFocusPage(direction);

  void focusFirst() => listFocusFirst();

  void focusLast() => listFocusLast();

  /// `list.expandSelectionDown` (1) / `list.expandSelectionUp` (-1): the
  /// selection from the last row clicked to the next one.
  void expandSelection(int delta) {
    final rows = _navigable;
    final index = _selectedIndex;
    if (index < 0) return listFocusAt(0);
    final next = rows[(index + delta).clamp(0, rows.length - 1)];
    _controller.selectRange(next.path, reveal: true);
  }

  /// `list.selectAll`.
  void selectAll() => _controller.selectAll();

  /// `list.clear`: selects nothing.
  void clearSelection() => _controller.select(null);

  /// The largest file kept to make again on Undo once deleted for good.
  static const _undoableBytes = 20 * 1024 * 1024;

  /// [path]'s bytes, to make it again on Undo; null for one too large, or
  /// that cannot be read.
  Future<Uint8List?> _bytesOf(String path) async {
    try {
      final bytes = await readBytesThrough(_controller.files, path);
      return bytes.length > _undoableBytes ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  bool get canUndo => _controller.history.canUndo;
  bool get canRedo => _controller.history.canRedo;

  /// Undoes the last file operation (VS Code's Undo in the explorer): one
  /// that fails is dropped, said why.
  Future<void> undo() async {
    final history = _controller.history;
    final operation = history.takeUndo();
    if (operation == null) return;
    final files = _controller.files;
    String? reveal;
    try {
      switch (operation) {
        case ExplorerMoved(:final moves):
          for (final (:from, :to) in moves.reversed) {
            await files.rename(to, from);
            _controller.forget(to);
            widget.onMoved?.call(to, from);
            reveal = from;
          }
        case ExplorerCreated(:final paths):
          for (final (:path, :directory) in paths.reversed) {
            if (!await _untouched(path, directory: directory)) return;
            await files.delete(path);
            _controller.forget(path);
            widget.onDeleted?.call(path);
          }
        case ExplorerCopied(:final copies):
          for (final (:copy, source: _) in copies.reversed) {
            await files.delete(copy);
            _controller.forget(copy);
            widget.onDeleted?.call(copy);
          }
        case ExplorerDeleted(:final path, :final bytes):
          await files.writeBytes(path, bytes);
          reveal = path;
      }
      history.undone(operation);
    } catch (error) {
      _report(error);
    } finally {
      await _controller.refresh();
      if (reveal != null) await _controller.reveal(reveal);
    }
  }

  /// Does again the last file operation undone.
  Future<void> redo() async {
    final history = _controller.history;
    final operation = history.takeRedo();
    if (operation == null) return;
    final files = _controller.files;
    String? reveal;
    try {
      switch (operation) {
        case ExplorerMoved(:final moves):
          for (final (:from, :to) in moves) {
            await files.rename(from, to);
            _controller.forget(from);
            widget.onMoved?.call(from, to);
            reveal = to;
          }
        case ExplorerCreated(:final paths):
          for (final (:path, :directory) in paths) {
            await files.create(path, directory: directory);
            reveal = path;
          }
        case ExplorerCopied(:final copies, :final upload):
          if (upload) {
            final uploading = context.l10n.explorerUploading;
            await _withProgress(
              uploading,
              (transfer) => uploadTo(files, [
                for (final (:source, :copy) in copies) (from: source, to: copy),
              ], onProgress: transfer.onProgress),
            );
            reveal = copies.lastOrNull?.copy;
          } else {
            for (final (:source, :copy) in copies) {
              await files.copy(source, copy);
              reveal = copy;
            }
          }
        case ExplorerDeleted(:final path):
          await files.delete(path);
          _controller.forget(path);
          widget.onDeleted?.call(path);
      }
      history.redone(operation);
    } catch (error) {
      _report(error);
    } finally {
      await _controller.refresh();
      if (reveal != null) await _controller.reveal(reveal);
    }
  }

  /// Whether [path], made here, is as it was made (an empty file or
  /// folder), or the user lets Undo delete it anyway.
  Future<bool> _untouched(String path, {required bool directory}) async {
    final files = _controller.files;
    final empty = directory
        ? (await files.list(path)).isEmpty
        : (await files.read(path, force: true)).isEmpty;
    if (empty || !mounted) return empty;
    final l10n = context.l10n;
    final pick = await showIdeDialog(
      context,
      type: IdeDialogType.question,
      message: l10n.explorerUndoCreateChanged(_controller.paths.basename(path)),
      detail: l10n.explorerIrreversible,
      buttons: [l10n.commonDelete],
    );
    return pick == 0;
  }

  // --- Dragging within the tree ---------------------------------------------

  /// What is dragged from this tree, while it is.
  List<String>? _dragging;

  /// Its paths on this machine, once dragged out of the window (a remote
  /// project's downloaded): back over the tree, the drag is still a move.
  List<String>? _outward;

  /// The folder a drag would move into, highlighted with what is in it.
  String? _dropFolder;

  /// Whether what is dragged moves into [folder]: none of it is [folder]
  /// or above it, and some of it is elsewhere.
  bool _takes(String folder) {
    final dragging = _dragging;
    if (dragging == null || dragging.isEmpty) return false;
    final paths = _controller.paths;
    if (dragging.any(
      (path) => path == folder || paths.isWithin(path, folder),
    )) {
      return false;
    }
    return dragging.any((path) => paths.dirname(path) != folder);
  }

  /// Where a drop on [row] goes: a folder itself, a file's folder.
  String _folderFor(IdeExplorerRow row) =>
      row.isDirectory ? row.path : _controller.paths.dirname(row.path);

  void _hoverDrop(String? folder) {
    if (folder == _dropFolder) return;
    setState(() => _dropFolder = folder);
  }

  // --- Dragging in from other apps ------------------------------------------

  /// The rows shown, as last built: where a drag from another app is.
  List<(IdeExplorerRow, bool)> _shownRows = const [];
  final GlobalKey _listKey = GlobalKey();

  /// The folder files let go at [position] (the window's) go into: a
  /// folder's row, a file's folder, the top folder below the rows (the
  /// only one); null elsewhere.
  String? _folderAt(Offset position) {
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final local = box.globalToLocal(position);
    if (!(Offset.zero & box.size).contains(local)) return null;
    final offset = _scroll.hasClients ? _scroll.offset : 0.0;
    final index = ((local.dy + offset) / IdeExplorer.rowHeight).floor();
    if (index >= 0 && index < _shownRows.length) {
      final (row, editing) = _shownRows[index];
      if (editing || row.message != null) return null;
      return _folderFor(row);
    }
    return _topFolder;
  }

  /// What is let go below the rows goes into: the project's folder, or a
  /// workspace's only one; none among several (their rows take drops).
  String? get _topFolder => switch (_controller.roots) {
    [] => _controller.root,
    [final only] => only,
    _ => null,
  };

  /// Files from another app (Finder, Explorer) over the tree: the folder
  /// they would go into highlighted.
  void _fileDragOver(Offset position) => _hoverDrop(_folderAt(position));

  /// Files from another app let go over the tree: copied into the folder
  /// they are over (uploaded to a remote project's host), as VS Code does.
  /// What was dragged out of this tree and back in moves.
  void _fileDrop(Offset position, List<ComposerFile> files) {
    final folder = _folderAt(position);
    _hoverDrop(null);
    if (folder == null || files.isEmpty) return;
    final dropped = {for (final file in files) file.path};
    if (_dragging case final dragging?
        when setEquals({...dragging}, dropped) ||
            setEquals({...?_outward}, dropped)) {
      if (_takes(folder)) unawaited(_moveInto(dragging, folder));
      return;
    }
    unawaited(_paste(folder, (files: files, cut: false, external: true)));
  }

  /// Moves [sources] (dragged here) into [folder], as one operation.
  Future<void> _moveInto(List<String> sources, String folder) async {
    final files = _controller.files;
    final paths = _controller.paths;
    final moved = <({String from, String to})>[];
    String? last;
    try {
      for (final source in sources) {
        if (paths.dirname(source) == folder) continue;
        final target = paths.join(folder, paths.basename(source));
        await files.rename(source, target);
        _controller.forget(source);
        widget.onMoved?.call(source, target);
        moved.add((from: source, to: target));
        last = target;
      }
    } catch (error) {
      _report(error);
    }
    if (moved.isNotEmpty) _controller.history.done(ExplorerMoved(moved));
    await _controller.refresh();
    if (last != null) await _controller.reveal(last);
  }

  /// `list.expand`: opens the folder, or goes to its first child.
  void expandSelected() {
    final row = _selectedRow;
    if (row == null) return listFocusAt(0);
    if (!row.isDirectory) return;
    if (!row.expanded) {
      unawaited(_controller.expand(row.path));
    } else if (_firstChild case final child?) {
      _controller.select(child.path, reveal: true);
    }
  }

  /// `list.collapse`: closes the folder, or goes to the parent.
  void collapseSelected() {
    final row = _selectedRow;
    if (row == null) return listFocusAt(0);
    if (row.isDirectory && row.expanded) {
      _controller.collapse(row.path);
      return;
    }
    final parent = _controller.paths.dirname(row.path);
    if (row.depth > 0) _controller.select(parent, reveal: true);
  }

  /// `list.select`: opens the file, the editor focused, or toggles the
  /// folder.
  void openSelected() {
    if (_selectedRow case final row?) _activate(row, keyboard: true);
  }

  /// `list.toggleExpand`: toggles the folder.
  void toggleSelected() {
    final row = _selectedRow;
    if (row != null && row.isDirectory) unawaited(_controller.toggle(row.path));
  }

  /// `filesExplorer.openFilePreserveFocus`: opens the file, the focus kept
  /// here.
  void previewSelected() {
    final row = _selectedRow;
    if (row != null && !row.isDirectory) widget.onOpen(row.path, false);
  }

  /// `renameFile`.
  void renameSelected() {
    if (_selectedRow case final row?) startRename(row);
  }

  /// `moveFileToTrash`, or `deleteFile` ([permanently]).
  Future<void> deleteSelected({bool permanently = false}) =>
      _delete(_targets(), permanently: permanently);

  /// `filesExplorer.copy`, or `filesExplorer.cut`.
  void copySelected({bool cut = false}) {
    final targets = _targets();
    if (targets.isNotEmpty) _copy(targets, cut: cut);
  }

  static List<String> _paths(List<IdeExplorerRow> rows) => [
    for (final row in rows) row.path,
  ];

  // --- Between this machine and a remote host --------------------------------

  /// Runs [transfer] (an upload, a download), how far it is shown in a
  /// notification once it takes a moment: [message] of the files done, and
  /// how far the file on is. [cancellable], the notification can give it
  /// up (the [_Transfer.cancel] it is given completes).
  Future<T> _withProgress<T>(
    String Function(int done, int total) message,
    Future<T> Function(_Transfer transfer) transfer, {
    bool cancellable = false,
  }) async {
    final notifications = IdeNotificationsScope.maybeOf(context);
    final l10n = context.l10n;
    final preparing = l10n.explorerPreparingTransfer;
    final cancel = Completer<void>();
    void giveUp() {
      if (!cancel.isCompleted) cancel.complete();
    }

    var done = 0;
    int? total;
    // Of the file on: what part of it is there.
    var part = 0.0;
    String text() => total == null ? preparing : message(done, total!);
    IdeNotificationProgress progress() => switch (total) {
      final total? when total > 0 => IdeNotificationProgress(
        done + part,
        total: total.toDouble(),
      ),
      _ => const IdeNotificationProgress.infinite(),
    };
    IdeNotification? shown;
    void update() {
      if (shown case final shown?) {
        notifications!.update(shown, message: text(), progress: progress());
      }
    }

    // Not for what is done at once.
    final timer = notifications == null
        ? null
        : Timer(const Duration(milliseconds: 300), () {
            shown = notifications.notify(
              IdeSeverity.info,
              text(),
              progress: progress(),
              sticky: true,
              primary: [
                if (cancellable)
                  IdeNotificationAction(l10n.commonCancel, giveUp),
              ],
              onClose: cancellable ? giveUp : null,
            );
          });
    var lastPart = 0.0;
    try {
      return await transfer(
        _Transfer(
          onProgress: (worked, of) {
            done = worked;
            total = of;
            part = lastPart = 0;
            update();
          },
          onFile: (read, size) {
            part = size == 0 ? 1 : read / size;
            // A notification a percent, not one a stretch.
            if (part - lastPart < 0.01 && part < 1) return;
            lastPart = part;
            update();
          },
          cancel: cancel.future,
        ),
      );
    } finally {
      timer?.cancel();
      if (shown case final shown?) notifications!.close(shown);
    }
  }

  /// [rows] as this machine's files, for other apps (Finder's paste, a drag
  /// out): a remote project's downloaded to a folder here first. Null when
  /// they cannot be had (a remote project's files that do not download).
  Future<List<String>?> _download(List<ComposerFile> rows) async {
    if (widget.local) return [for (final row in rows) row.path];
    final files = _controller.files;
    if (files is! IdeHostFiles) return null;
    final downloading = context.l10n.explorerDownloading;
    final folder = await newDownloadFolder();
    final taken = <String>{};
    final items = <({String from, String to, bool directory})>[];
    for (final (i, row) in rows.indexed) {
      final name = _controller.paths.basename(row.path);
      // The same name from two folders: each in a folder of its own.
      final to = taken.add(name)
          ? p.join(folder, name)
          : p.join(folder, '$i', name);
      items.add((from: row.path, to: to, directory: row.directory));
    }
    if (!mounted) return const [];
    try {
      await _withProgress(
        downloading,
        (transfer) => downloadFrom(
          files,
          items,
          onProgress: transfer.onProgress,
          onFile: transfer.onFile,
          cancel: transfer.cancel,
        ),
        cancellable: true,
      );
    } on TransferCancelledException {
      return null;
    }
    return [for (final item in items) item.to];
  }

  /// The most of a remote project's files a copy downloads onto the
  /// system's clipboard: more stay the app's, pasted here (on the host,
  /// with nothing downloaded), not to fill the connection to the host.
  static const clipboardDownloadLimit = 20 << 20;

  /// Copied, this machine's files are on the system's clipboard too, as
  /// Finder copies them: to paste into the chat, or into another app.
  /// A remote project's are downloaded first, to be on it as this
  /// machine's, unless they are big (see [clipboardDownloadLimit]).
  void _copy(List<IdeExplorerRow> rows, {required bool cut}) {
    final paths = _paths(rows);
    final written = cut
        ? Future<void>.value()
        : widget.local
        ? WindowControls.writePasteboardFiles(paths)
              .then((_) {}, onError: (Object _) {})
        : _copyDownloaded(rows);
    _controller.clipboard = IdeExplorerClipboard(
      [
        for (final row in rows)
          ComposerFile(row.path, directory: row.isDirectory),
      ],
      cut: cut,
      system: written.then(
        (_) async => _pathsOf(await _systemClipboardFiles()),
      ),
    );
  }

  /// A remote project's [rows], downloaded onto the system's clipboard
  /// unless they take more than [clipboardDownloadLimit].
  Future<void> _copyDownloaded(List<IdeExplorerRow> rows) async {
    try {
      final files = _controller.files;
      if (files is IdeRangeFiles) {
        final size = await (files as IdeRangeFiles).sizeOf([
          for (final row in rows) row.path,
        ], limit: clipboardDownloadLimit);
        if (size > clipboardDownloadLimit) return;
      }
      final paths = await _download([
        for (final row in rows)
          ComposerFile(row.path, directory: row.isDirectory),
      ]);
      if (paths != null) await WindowControls.writePasteboardFiles(paths);
    } on Object catch (error) {
      if (mounted) _report(error);
    }
  }

  /// What a paste puts in: what was cut or copied here, unless other files
  /// were copied to the system's clipboard since, which are copied in
  /// ([external]: this machine's); null for nothing.
  Future<({List<ComposerFile> files, bool cut, bool external})?>
  _toPaste() async {
    final clipboard = _controller.clipboard;
    final system = await _systemClipboardFiles();
    if (clipboard != null &&
        (system.isEmpty ||
            setEquals(_pathsOf(system), await clipboard.system))) {
      return (files: clipboard.files, cut: clipboard.cut, external: false);
    }
    if (system.isEmpty) return null;
    return (files: system, cut: false, external: true);
  }

  /// `filesExplorer.paste`: into the selected folder, or the selected
  /// file's.
  Future<void> pasteSelected() => _paste(_folderOf(_selectedRow));

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
    if (_controller.isRoot(row.path)) return;
    setState(
      () => _edit = _ExplorerEdit.rename(
        row.path,
        parent: _controller.paths.dirname(row.path),
        directory: row.isDirectory,
      ),
    );
  }

  void _cancelEdit() {
    if (_edit == null) return;
    setState(() => _edit = null);
    _focusNode.requestFocus();
  }

  /// VS Code's `validateFileName`.
  IdeInputValidation? _validate(_ExplorerEdit edit, String name) {
    final l10n = context.l10n;
    if (name.trim().isEmpty) {
      return IdeInputValidation(l10n.explorerNameRequired);
    }
    if (name.startsWith('/') || name.startsWith(r'\')) {
      return IdeInputValidation(l10n.explorerNameStartsWithSlash);
    }
    final names = name.split(RegExp(r'[\\/]')).where((n) => n.isNotEmpty);
    final original = edit.renaming == null
        ? null
        : _controller.paths.basename(edit.renaming!);
    if (name != original) {
      final siblings = _controller.childrenOf(edit.parent) ?? const [];
      final first = names.first;
      final exists = siblings.any(
        (entry) =>
            entry.name == first &&
            (names.length == 1 || !entry.isDirectory) &&
            _controller.paths.join(edit.parent, entry.name) != edit.renaming,
      );
      if (exists) {
        return IdeInputValidation(l10n.explorerNameExists(name));
      }
    }
    if (names.any((n) => n == '.' || n == '..' || n.contains('\x00'))) {
      return IdeInputValidation(l10n.explorerNameInvalid(name));
    }
    if (names.any((n) => n.trim() != n)) {
      return IdeInputValidation(
        l10n.explorerNameWhitespace,
        IdeValidationSeverity.warning,
      );
    }
    return null;
  }

  Future<void> _commitEdit(_ExplorerEdit edit, String name) async {
    if (!identical(_edit, edit)) return;
    final original = edit.renaming == null
        ? null
        : _controller.paths.basename(edit.renaming!);
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
        final to = _controller.paths.join(edit.parent, name);
        await files.rename(from, to);
        _controller.forget(from);
        widget.onMoved?.call(from, to);
        _controller.history.done(ExplorerMoved([(from: from, to: to)]));
        await _controller.refresh();
        await _controller.reveal(to);
      } else {
        // `a/b/c.txt` makes the folders too.
        final parts = name.split(RegExp(r'[\\/]')).where((n) => n.isNotEmpty);
        var folder = edit.parent;
        final made = <({String path, bool directory})>[];
        for (final part in parts.take(parts.length - 1)) {
          folder = _controller.paths.join(folder, part);
          try {
            await files.create(folder, directory: true);
            made.add((path: folder, directory: true));
          } on IdeFileExistsException {
            // Already there.
          }
        }
        final path = _controller.paths.join(folder, parts.last);
        await files.create(path, directory: edit.directory);
        made.add((path: path, directory: edit.directory));
        _controller.history.done(ExplorerCreated(made));
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
  Future<void> _delete(
    List<IdeExplorerRow> targets, {
    bool permanently = false,
  }) async {
    final rows = [
      for (final row in targets)
        if (!_controller.isRoot(row.path)) row,
    ];
    if (rows.isEmpty) return;
    final trash = permanently ? null : widget.trash;
    final useTrash = trash != null;
    final l10n = context.l10n;
    final primary = useTrash ? l10n.explorerMoveToTrash : l10n.commonDelete;
    final single = rows.length == 1 ? rows.single : null;
    // Upstream's `getFileNamesMessage`: the first ten, then how many more.
    final names = [
      for (final row in rows.take(10)) row.name,
      if (rows.length > 10) l10n.explorerMoreFilesNotShown(rows.length - 10),
    ].join('\n');
    String detail(String text) => single == null ? '$names\n\n$text' : text;
    var unsaved = 0;
    for (final row in rows) {
      unsaved += widget.unsavedIn?.call(row.path) ?? 0;
    }
    final int? pick;
    if (unsaved > 0) {
      pick = await showIdeDialog(
        context,
        message: single == null
            ? l10n.explorerDeleteFilesUnsaved
            : single.isDirectory
            ? l10n.explorerDeleteFolderUnsaved(unsaved, single.name)
            : l10n.explorerDeleteFileUnsaved(single.name),
        detail: detail(l10n.explorerChangesLost),
        buttons: [primary],
      );
    } else if (useTrash) {
      pick = await showIdeDialog(
        context,
        type: IdeDialogType.question,
        message: single == null
            ? l10n.explorerConfirmDeleteMultiple(rows.length)
            : single.isDirectory
            ? l10n.explorerConfirmDeleteFolder(single.name)
            : l10n.explorerConfirmDeleteFile(single.name),
        detail: single == null
            ? detail(l10n.explorerRestoreFilesFromTrash)
            : l10n.explorerRestoreFromTrash,
        buttons: [primary],
      );
    } else {
      pick = await showIdeDialog(
        context,
        message: single == null
            ? l10n.explorerConfirmPermanentDeleteMultiple(rows.length)
            : single.isDirectory
            ? l10n.explorerConfirmPermanentDeleteFolder(single.name)
            : l10n.explorerConfirmPermanentDeleteFile(single.name),
        detail: single == null
            ? detail(l10n.explorerIrreversible)
            : single.isDirectory
            ? l10n.explorerIrreversible
            : l10n.explorerRestoreWithUndo,
        buttons: [primary],
      );
    }
    if (pick != 0 || !mounted) return;
    // Once the Trash fails, asked once, the rest go permanently.
    var toTrash = trash;
    for (final row in rows) {
      try {
        var trashed = false;
        if (toTrash != null) {
          try {
            trashed = await toTrash(row.path);
          } catch (_) {
            if (!mounted) return;
            final again = await showIdeDialog(
              context,
              message: l10n.explorerTrashFailed,
              detail: row.isDirectory || single == null
                  ? l10n.explorerIrreversible
                  : l10n.explorerRestoreWithUndo,
              buttons: [l10n.explorerDeletePermanently],
            );
            if (again != 0) break;
            toTrash = null;
          }
        }
        if (!trashed) {
          // A file's bytes, to make it again on Undo.
          final kept = row.isDirectory ? null : await _bytesOf(row.path);
          await _controller.files.delete(row.path);
          if (kept != null) {
            _controller.history.done(ExplorerDeleted(row.path, kept));
          }
        }
        _controller.forget(row.path);
        widget.onDeleted?.call(row.path);
      } catch (error) {
        _report(error);
      }
    }
    await _controller.refresh();
  }

  /// Paste: copies (with VS Code's simple incremental names when taken) or
  /// moves what was cut into [folder]; files from the system's clipboard
  /// are copied, onto a remote project's host too.
  Future<void> _paste(
    String folder, [
    ({List<ComposerFile> files, bool cut, bool external})? what,
  ]) async {
    final toPaste = what ?? await _toPaste();
    if (toPaste == null || !mounted) return;
    final files = _controller.files;
    final ancestor = context.l10n.explorerPasteIntoAncestor;
    final uploading = context.l10n.explorerUploading;
    // This machine's files, into a remote project's: uploaded together,
    // how far shown.
    final upload = toPaste.external && !widget.local;
    final uploads = <({String from, String to})>[];
    String? last;
    final moved = <({String from, String to})>[];
    final copied = <({String source, String copy})>[];
    try {
      await _controller.expand(folder);
      final taken = {
        for (final entry in _controller.childrenOf(folder) ?? const [])
          entry.name,
      };
      for (final file in toPaste.files) {
        final source = file.path;
        final sourceName = toPaste.external
            ? p.basename(source)
            : _controller.paths.basename(source);
        final target = _controller.paths.join(folder, sourceName);
        if (toPaste.cut && target == source) continue;
        if (!upload &&
            (source == folder || _controller.paths.isWithin(source, folder))) {
          _report(ancestor);
          break;
        }
        if (toPaste.cut) {
          await files.rename(source, target);
          _controller.forget(source);
          widget.onMoved?.call(source, target);
          moved.add((from: source, to: target));
          last = target;
        } else {
          var name = sourceName;
          while (taken.contains(name)) {
            name = ideIncrementFileName(name, isFolder: file.directory);
          }
          taken.add(name);
          final copy = _controller.paths.join(folder, name);
          if (upload) {
            uploads.add((from: source, to: copy));
            continue;
          }
          await files.copy(source, copy);
          copied.add((source: source, copy: copy));
          last = copy;
        }
      }
      if (uploads.isNotEmpty) {
        await _withProgress(
          uploading,
          (transfer) =>
              uploadTo(files, uploads, onProgress: transfer.onProgress),
        );
        for (final (:from, :to) in uploads) {
          copied.add((source: from, copy: to));
          last = to;
        }
      }
      if (toPaste.cut) _controller.clipboard = null;
    } catch (error) {
      _report(error);
    }
    if (moved.isNotEmpty) _controller.history.done(ExplorerMoved(moved));
    if (copied.isNotEmpty) {
      _controller.history.done(ExplorerCopied(copied, upload: upload));
    }
    await _controller.refresh();
    if (last != null) await _controller.reveal(last);
  }

  String _relative(String path) => _controller.paths
      .relative(path, from: _controller.rootOf(path))
      .replaceAll(r'\', '/');

  /// [command]'s keybinding, for the menu: the one that applies with the
  /// focus here.
  String? _keybinding(String command) =>
      KeybindingService.instance.labelFor(command, context: _focusedContextKey);

  /// `MenuId.ExplorerContext`, for [row] or (null) the empty space below the
  /// rows, which is the root folder's.
  Future<void> _showMenu(Offset position, IdeExplorerRow? row) async {
    // Upstream keeps the selection when the clicked row is in it, and acts
    // on all of it.
    if (row != null && !_controller.isSelected(row.path)) {
      _controller.select(row.path);
    }
    final path = row?.path ?? _controller.defaultFolder;
    final isFolder = row == null || row.isDirectory;
    final isRoot = row == null || row.isRoot;
    final workspaceFolder = row != null && row.isRoot;
    final targets = row == null ? const <IdeExplorerRow>[] : _targets(row);
    final canPaste = isFolder && await _toPaste() != null;
    if (!mounted) return;
    final multiple = targets.length > 1;
    final mac = ideUsesMacKeys;
    String? keys(List<IdeKeybinding> bindings) => [
      for (final binding in bindings)
        if (binding.appliesTo(mac: mac)) binding.label(),
    ].firstOrNull;
    final l10n = context.l10n;
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          if (isFolder) ...[
            IdeMenuAction(
              l10n.explorerNewFile,
              keybinding: _keybinding('explorer.newFile'),
              onSelected: () =>
                  unawaited(startCreate(parent: path, directory: false)),
            ),
            IdeMenuAction(
              l10n.explorerNewFolder,
              keybinding: _keybinding('explorer.newFolder'),
              onSelected: () =>
                  unawaited(startCreate(parent: path, directory: true)),
            ),
          ],
          if (widget.local && WindowControls.canRevealInFileManager)
            IdeMenuAction(
              l10n.revealInFileManager,
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
          if (widget.onOpenInDefaultApp case final open?
              when targets.any((target) => !target.isDirectory))
            IdeMenuAction(
              l10n.openInDefaultApp,
              onSelected: () {
                for (final target in targets) {
                  if (!target.isDirectory) open(target.path);
                }
              },
            ),
          // Open in Terminal: in the folder, or in the one holding the
          // file; VS Code's `openInTerminal` (on the folder, the file's
          // folder too).
          if (widget.onOpenInTerminal case final openTerminal?)
            IdeMenuAction(
              l10n.explorerOpenInTerminal,
              onSelected: () => openTerminal(
                !isFolder ? _controller.paths.dirname(path) : path,
              ),
            ),
          // To this machine, from a remote project's host too.
          if (!isFolder && !multiple && canSaveFileCopy)
            IdeMenuAction(
              l10n.cmdSaveAs,
              onSelected: () => unawaited(
                saveFileCopyAs(
                  _controller.files,
                  path,
                ).then<void>((_) {}, onError: _report),
              ),
            ),
        ],
        [
          if (isFolder && !multiple && widget.onFindInFolder != null)
            IdeMenuAction(
              l10n.explorerFindInFolder,
              keybinding: keys(const [
                IdeKeybinding(LogicalKeyboardKey.keyF, shift: true, alt: true),
              ]),
              onSelected: () => widget.onFindInFolder!(path),
            ),
        ],
        [
          if (widget.onShowHistory case final show?
              when !multiple &&
                  (widget.git != null || widget.repositories.isNotEmpty))
            IdeMenuAction(l10n.gitShowHistory, onSelected: () => show(path)),
        ],
        [
          if (!isRoot) ...[
            IdeMenuAction(
              l10n.commonCut,
              keybinding: _keybinding('filesExplorer.cut'),
              onSelected: () => _copy(targets, cut: true),
            ),
            IdeMenuAction(
              l10n.commonCopy,
              keybinding: _keybinding('filesExplorer.copy'),
              onSelected: () => _copy(targets, cut: false),
            ),
          ],
          if (isFolder)
            IdeMenuAction(
              l10n.commonPaste,
              keybinding: _keybinding('filesExplorer.paste'),
              enabled: canPaste,
              onSelected: () => unawaited(_paste(path)),
            ),
        ],
        [
          IdeMenuAction(
            l10n.tabCopyPath,
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
            onSelected: () => unawaited(
              Clipboard.setData(
                ClipboardData(
                  text: multiple ? _paths(targets).join('\n') : path,
                ),
              ),
            ),
          ),
          IdeMenuAction(
            l10n.tabCopyRelativePath,
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
              Clipboard.setData(
                ClipboardData(
                  text: multiple
                      ? [for (final t in targets) _relative(t.path)].join('\n')
                      : _relative(path),
                ),
              ),
            ),
          ),
        ],
        [
          if (widget.onAddFolder case final add? when row == null)
            IdeMenuAction(l10n.ideAddFolderToWorkspace, onSelected: add),
          if (widget.onRemoveFolder case final remove? when workspaceFolder)
            IdeMenuAction(
              l10n.ideRemoveFolderFromWorkspace,
              onSelected: () => remove(path),
            ),
        ],
        [
          if (!isRoot) ...[
            if (!multiple)
              IdeMenuAction(
                l10n.explorerRename,
                keybinding: _keybinding('renameFile'),
                onSelected: () => startRename(row),
              ),
            IdeMenuAction(
              l10n.commonDelete,
              keybinding: _keybinding(
                widget.trash == null ? 'deleteFile' : 'moveFileToTrash',
              ),
              onSelected: () => unawaited(_delete(targets)),
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
      path: _controller.paths.join(edit.parent, '\x00new'),
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
    final rows = _shownRows = _rowsWithEdit();
    final focused = _focusNode.hasFocus;
    final decorations = widget.git?.decorations;
    final repositories = widget.repositories;
    IdeGitDecorations? decorationsOf(String path) {
      if (repositories.isEmpty) return decorations;
      // The deepest: a repository in another's subfolder decorates its own.
      IdeGitRepository? deepest;
      for (final repository in repositories) {
        final root = repository.state?.root;
        if (root != null &&
            (_controller.paths.equals(root, path) ||
                _controller.paths.isWithin(root, path)) &&
            root.length > (deepest?.state?.root.length ?? -1)) {
          deepest = repository;
        }
      }
      return deepest?.decorations;
    }

    // A selected row drags the whole selection.
    List<ComposerFile>? selectedFiles;
    List<ComposerFile> dragged(IdeExplorerRow row) {
      ComposerFile file(IdeExplorerRow row) =>
          ComposerFile(row.path, directory: row.isDirectory);
      if (_controller.selection.length < 2 ||
          !_controller.isSelected(row.path)) {
        return [file(row)];
      }
      return selectedFiles ??= [
        for (final target in _targets(row)) file(target),
      ];
    }

    final tree = ColoredBox(
      // Modern UI: the panes are the side bar's.
      color: widget.background ?? themeColors['sideBar.background'],
      child: Focus(
        focusNode: _focusNode,
        onKeyEvent: _onKey,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // Below the rows: none selected, as VS Code's list does, so that
          // New File… and the rest are at the top folder.
          onTap: () {
            _focusNode.requestFocus();
            clearSelection();
          },
          onSecondaryTapUp: (details) {
            _focusNode.requestFocus();
            clearSelection();
            unawaited(_showMenu(details.globalPosition, null));
          },
          child: _rootDropTarget(
            ListView.builder(
              key: _listKey,
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
                    paths: _controller.paths,
                    validate: (name) => _validate(edit, name),
                    onSubmit: (name) => unawaited(_commitEdit(edit, name)),
                    onCancel: _cancelEdit,
                  );
                }
                final gitDecoration = switch (decorationsOf(row.path)) {
                  _ when row.message != null => null,
                  null => null,
                  final decorations when row.isDirectory =>
                    decorations.folder(row.path),
                  final decorations => decorations.file(row.path),
                };
                final lineDecoration = row.isDirectory || row.message != null
                    ? null
                    : _controller.lineCount.decorationFor(row.path);
                final decoration = lineDecoration != null
                    ? lineDecoration.merge(gitDecoration)
                    : gitDecoration;
                final view = _ExplorerRowView(
                  row: row,
                  selected: _controller.isSelected(row.path),
                  focusedItem: row.path == _controller.selected,
                  focused: focused,
                  decoration: decoration,
                  onTap: () {
                    _focusNode.requestFocus();
                    _click(row);
                  },
                  onContextMenu: (position) {
                    _focusNode.requestFocus();
                    unawaited(_showMenu(position, row));
                  },
                );
                if (row.message != null) {
                  return KeyedSubtree(key: ValueKey(row.path), child: view);
                }
                // Dragged onto the chat's composer, it goes in as a file;
                // within the tree, it moves into the folder dropped on.
                final folder = _folderFor(row);
                final drop = _dropFolder;
                final inDrop =
                    drop != null &&
                    (row.path == drop ||
                        _controller.paths.isWithin(drop, row.path));
                return FileDraggable(
                  key: ValueKey(row.path),
                  files: dragged(row),
                  // Out of the window, to other apps: a remote project's
                  // downloaded first.
                  localPaths: widget.local
                      ? () => [for (final file in dragged(row)) file.path]
                      : null,
                  outward: () async => _outward = await _download(dragged(row)),
                  onDragStarted: () =>
                      _dragging = [for (final file in dragged(row)) file.path],
                  onDragEnd: () {
                    _dragging = null;
                    _outward = null;
                    _hoverDrop(null);
                  },
                  child: DragTarget<FileDragData>(
                    onWillAcceptWithDetails: (_) {
                      final takes = _takes(folder);
                      _hoverDrop(takes ? folder : null);
                      return takes;
                    },
                    onLeave: (_) {
                      if (_dropFolder == folder) _hoverDrop(null);
                    },
                    onAcceptWithDetails: (_) {
                      final sources = _dragging ?? const <String>[];
                      _hoverDrop(null);
                      unawaited(_moveInto(sources, folder));
                    },
                    builder: (context, _, _) => inDrop
                        ? DecoratedBox(
                            decoration: BoxDecoration(
                              color: themeColors['list.dropBackground'],
                            ),
                            child: view,
                          )
                        : view,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // Files dragged in from other apps.
    return FileDropRegion(delegate: _ExplorerFileDrop(this), child: tree);
  }

  /// [list], dropped on below its rows: what is dragged moves to the top
  /// folder (the only one; a workspace's folders take drops on their rows),
  /// all of the tree highlighted.
  Widget _rootDropTarget(Widget list) {
    final root = _topFolder;
    if (root == null) return list;
    return DragTarget<FileDragData>(
      onWillAcceptWithDetails: (_) {
        final takes = _takes(root);
        _hoverDrop(takes ? root : null);
        return takes;
      },
      onLeave: (_) {
        if (_dropFolder == root) _hoverDrop(null);
      },
      onAcceptWithDetails: (_) {
        final sources = _dragging ?? const <String>[];
        _hoverDrop(null);
        unawaited(_moveInto(sources, root));
      },
      builder: (context, _, _) => _dropFolder == root
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: themeColors['list.dropBackground'],
              ),
              child: list,
            )
          : list,
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

/// Files dragged onto the tree from other apps.
class _ExplorerFileDrop implements FileDropDelegate {
  _ExplorerFileDrop(this._explorer);

  final IdeExplorerState _explorer;

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {
    if (_explorer.mounted) _explorer._fileDragOver(position);
  }

  @override
  void fileDragLeave() {
    if (_explorer.mounted) _explorer._hoverDrop(null);
  }

  @override
  void fileDrop(Offset position, List<ComposerFile> files) {
    if (_explorer.mounted) _explorer._fileDrop(position, files);
  }
}

class _ExplorerRowView extends StatelessWidget {
  const _ExplorerRowView({
    required this.row,
    required this.selected,
    required this.focusedItem,
    required this.focused,
    required this.decoration,
    required this.onTap,
    required this.onContextMenu,
  });

  final IdeExplorerRow row;
  final bool selected;

  /// The list's focused row: outlined while the list has focus.
  final bool focusedItem;
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
      final denied = row.error is IdeFileAccessDeniedException;
      return Stack(
        children: [
          Positioned.fill(child: guides),
          Padding(
            padding: EdgeInsets.only(left: left + 24, right: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IdeHover(
                message: switch (row.error) {
                  final error? => localizedFileError(context.l10n, error),
                  null => message,
                },
                followMouse: true,
                child: Row(
                  children: [
                    if (denied) ...[
                      Icon(
                        Codicons.lock,
                        size: 12,
                        color: IdeListColors.errorForeground,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        denied
                            ? context.l10n.explorerNoPermission
                            : context.l10n.explorerCannotReadFolder(
                                switch (row.error) {
                                  final error? => localizedFileError(
                                    context.l10n,
                                    error,
                                  ),
                                  null => message,
                                },
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: IdeListColors.errorForeground,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
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
      focusedItem: focusedItem,
      focused: focused,
      onTap: onTap,
      onContextMenu: onContextMenu,
      // ResourceLabel's title (labels.ts): the path label, tildified as
      // `labelService.getUriLabel` does, then the decoration's.
      tooltip: switch (decoration?.localizedTooltip(context.l10n)) {
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
                        // A workspace folder's, bold as VS Code's roots.
                        fontWeight: row.isRoot ? FontWeight.w600 : null,
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
                      child: _buildBadge(
                        letter: letter,
                        color: color,
                        foreground: foreground,
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

  Widget _buildBadge({
    required String letter,
    required Color? color,
    required Color foreground,
  }) {
    final comma = letter.indexOf(', ');
    if (comma == -1) {
      final isGit = color != null;
      return Text(
        letter,
        style: TextStyle(
          fontSize: 13 * .9,
          fontWeight: isGit ? FontWeight.w600 : FontWeight.w500,
          color: isGit
              ? color.withValues(alpha: .75)
              : foreground.withValues(alpha: .5),
        ),
      );
    }

    final first = letter.substring(0, comma);
    final rest = letter.substring(comma + 2);
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: first,
            style: TextStyle(
              color: foreground.withValues(alpha: .5),
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: ', ',
            style: TextStyle(
              color: foreground.withValues(alpha: .35),
              fontWeight: FontWeight.normal,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              color: (color ?? foreground).withValues(alpha: .75),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 13 * .9),
    );
  }
}

/// A row's inline input: New File/Folder's name, or a rename.
class _ExplorerEditRow extends StatefulWidget {
  const _ExplorerEditRow({
    super.key,
    required this.row,
    required this.edit,
    required this.paths,
    required this.validate,
    required this.onSubmit,
    required this.onCancel,
  });

  final IdeExplorerRow row;
  final _ExplorerEdit edit;
  final p.Context paths;
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
        : widget.paths.basename(widget.edit.renaming!);
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
            FolderIcon(widget.paths.join(widget.edit.parent, name), size: 16)
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

/// What a transfer run by [IdeExplorerState._withProgress] tells how far it
/// is, and when it is to stop.
class _Transfer {
  const _Transfer({
    required this.onProgress,
    required this.onFile,
    required this.cancel,
  });

  final TransferProgress onProgress;
  final FileProgress onFile;
  final Future<void> cancel;
}
