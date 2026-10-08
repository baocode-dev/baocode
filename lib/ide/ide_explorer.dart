/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import 'dart:async';
import 'dart:collection' show UnmodifiableSetView;
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb, listEquals, setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../chat/composer/composer_files.dart';
import '../chat/composer/file_drag.dart';
import '../keybindings/keybinding_service.dart';
import '../l10n/l10n.dart';
import '../platform/app_paths.dart';
import '../theme/codicons.dart';
import '../theme/material_file_icons.dart';
import '../theme/workbench_theme.dart' show themeColors;
import '../workspace/window_controls.dart';

import 'package:bao_editor/monaco/vs/base/common/labels.dart';

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
  }) : root = p.normalize(root),
       _watchDirectory =
           watch ??
           switch (files) {
             final IdeHostFiles files => files.watchDirectory,
             _ => watchDirectory,
           } {
    unawaited(_load(this.root));
    this.roots = roots;
    _watchExpanded();
  }

  final IdeFileService files;
  final String root;

  /// A multi-folder workspace's folders, the tree's top rows in place of
  /// [root]'s entries (as VS Code lists workspace folders); none for a
  /// folder's project.
  List<String> get roots => _roots;
  List<String> _roots = const [];

  /// Shows [roots] at the top of the tree: those added expanded, as VS
  /// Code opens them.
  set roots(List<String> roots) {
    final normalized = [for (final root in roots) p.normalize(root)];
    if (listEquals(normalized, _roots)) return;
    for (final root in normalized) {
      if (!_roots.contains(root)) {
        _expanded.add(root);
        unawaited(_load(root));
      }
    }
    _expanded.removeWhere(
      (path) => !_inTree(path, normalized) && p.isWithin(root, path),
    );
    _roots = normalized;
    _changed();
  }

  /// Whether [path] is a row's: under [roots], or [root] for a folder.
  bool _inTree(String path, List<String> roots) => roots.isEmpty
      ? p.isWithin(root, path)
      : roots.any((r) => r == path || p.isWithin(r, path));

  /// Whether [path] is in the tree: under [root], or a workspace folder.
  bool shows(String path) => _inTree(p.normalize(path), _roots);

  /// Whether [path] is a workspace folder: the top of a tree.
  bool isRoot(String path) => path == root || _roots.contains(path);

  /// The top of [path]'s tree: its workspace folder, or [root].
  String rootOf(String path) {
    for (final root in _roots) {
      if (root == path || p.isWithin(root, path)) return root;
    }
    return root;
  }

  /// Whether [path] is a folder with a row: one that may hold others
  /// selected (a workspace folder's, but not [root]).
  bool isFolderRow(String path) => _roots.isEmpty
      ? path != root && p.isWithin(root, path)
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
  final Set<String> _expanded = {};
  final Map<String, Future<void>> _loads = {};
  List<IdeExplorerRow>? _rows;
  String? _selected;
  final Set<String> _selection = {};
  String? _anchor;
  int _revealRequest = 0;
  bool _disposed = false;

  /// The focused row's path, if any (upstream's focus, as distinct from the
  /// selection): the one the keys move from, and which is acted on alone
  /// when it is not in the [selection].
  String? get selected => _selected;

  /// The selected rows' paths: the focused one's alone, unless a modifier
  /// click or Shift with the arrows selected more.
  Set<String> get selection => UnmodifiableSetView(_selection);

  bool isSelected(String path) => _selection.contains(path);

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
            message: '$error',
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

    if (_roots.isEmpty) {
      add(root, 0);
      return rows;
    }
    for (final folder in _roots) {
      final expanded = _expanded.contains(folder);
      rows.add(
        IdeExplorerRow(
          path: folder,
          name: p.basename(folder),
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
    _selection.removeWhere((path) => p.isWithin(directory, path));
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
    if (_selected case final selected? when !shown.contains(selected)) {
      _selected = null;
    }
    _selection.retainWhere(shown.contains);
    _changed();
  }

  /// Focuses and selects [path] alone (none for null), as a click does.
  void select(String? path, {bool reveal = false}) {
    if (!reveal && _selected == path && setEquals(_selection, {?path})) return;
    _selected = path;
    _anchor = path;
    _selection
      ..clear()
      ..addAll([?path]);
    if (reveal) _revealRequest++;
    _changed();
  }

  /// Adds [path] to the selection, or takes it out, and focuses it, as a
  /// Cmd (Ctrl) click does.
  void toggleSelection(String path) {
    _selected = path;
    _anchor = path;
    if (!_selection.remove(path)) _selection.add(path);
    _changed();
  }

  /// Selects the rows from the last one clicked to [path] and focuses it,
  /// as a Shift click or Shift with the arrows does.
  void selectRange(String path, {bool reveal = false}) {
    final paths = [
      for (final row in rows)
        if (row.message == null) row.path,
    ];
    final to = paths.indexOf(path);
    if (to < 0) return;
    var from = _anchor == null ? -1 : paths.indexOf(_anchor!);
    if (from < 0) {
      from = to;
      _anchor = path;
    }
    _selected = path;
    _selection
      ..clear()
      ..addAll(paths.sublist(math.min(from, to), math.max(from, to) + 1));
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
    _selected ??= paths.first;
    _anchor ??= _selected;
    _selection
      ..clear()
      ..addAll(paths);
    _changed();
  }

  /// Expands the folders above [path], then selects and scrolls to it.
  Future<void> reveal(String path) async {
    final target = p.normalize(path);
    if (target == root || !_inTree(target, _roots)) return;
    final top = rootOf(target);
    if (top == target) return select(target, reveal: true);
    final parts = p.split(p.relative(target, from: top));
    var directory = top;
    if (top != root && _expanded.add(top)) _changed();
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
  IdeExplorerClipboard? clipboard;

  /// Forgets [path] and what was under it (after a move or delete), so
  /// folders re-read and the expansion does not point at nothing.
  void forget(String path) {
    bool under(String other) => other == path || p.isWithin(path, other);
    _expanded.removeWhere(under);
    _children.removeWhere((directory, _) => under(directory));
    if (_selected case final selected? when under(selected)) _selected = null;
    if (_anchor case final anchor? when under(anchor)) _anchor = null;
    _selection.removeWhere(under);
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
    this.isBound,
    this.local = true,
    this.repositories = const [],
    this.onAddFolder,
    this.onRemoveFolder,
  });

  final IdeExplorerController controller;

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
        var parent = p.dirname(path);
        _controller.isFolderRow(parent);
        parent = p.dirname(parent)
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
      : p.dirname(row.path);

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
    return _listKeys.contains(event.logicalKey)
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

  static final _listKeys = {
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.home,
    LogicalKeyboardKey.end,
    LogicalKeyboardKey.pageDown,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.space,
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

  void _selectAt(int index) {
    final rows = _navigable;
    if (rows.isEmpty) return;
    _controller.select(
      rows[index.clamp(0, rows.length - 1)].path,
      reveal: true,
    );
  }

  /// `list.focusDown` (1) / `list.focusUp` (-1); the first row when none is
  /// selected.
  void focusNext(int delta) {
    final index = _selectedIndex;
    _selectAt(index < 0 ? 0 : index + delta);
  }

  /// `list.focusPageDown` (1) / `list.focusPageUp` (-1).
  void focusPage(int direction) {
    final page = _scroll.hasClients
        ? (_scroll.position.viewportDimension ~/ IdeExplorer.rowHeight) - 1
        : 10;
    final index = _selectedIndex;
    _selectAt((index < 0 ? 0 : index) + direction * page);
  }

  /// `list.focusFirst`.
  void focusFirst() => _selectAt(0);

  /// `list.focusLast`.
  void focusLast() => _selectAt(_navigable.length - 1);

  /// `list.expandSelectionDown` (1) / `list.expandSelectionUp` (-1): the
  /// selection from the last row clicked to the next one.
  void expandSelection(int delta) {
    final rows = _navigable;
    final index = _selectedIndex;
    if (index < 0) return _selectAt(0);
    final next = rows[(index + delta).clamp(0, rows.length - 1)];
    _controller.selectRange(next.path, reveal: true);
  }

  /// `list.selectAll`.
  void selectAll() => _controller.selectAll();

  /// `list.clear`: selects nothing.
  void clearSelection() => _controller.select(null);

  /// `list.expand`: opens the folder, or goes to its first child.
  void expandSelected() {
    final row = _selectedRow;
    if (row == null) return _selectAt(0);
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
    if (row == null) return _selectAt(0);
    if (row.isDirectory && row.expanded) {
      _controller.collapse(row.path);
      return;
    }
    final parent = p.dirname(row.path);
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

  /// Copied, this machine's files are on the system's clipboard too, as
  /// Finder copies them: to paste into the chat, or into another app.
  void _copy(List<IdeExplorerRow> rows, {required bool cut}) {
    final paths = _paths(rows);
    final written = !cut && widget.local
        ? WindowControls.writePasteboardFiles(paths)
              .then((_) {}, onError: (Object _) {})
        : Future<void>.value();
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
    final l10n = context.l10n;
    if (name.trim().isEmpty) {
      return IdeInputValidation(l10n.explorerNameRequired);
    }
    if (name.startsWith('/') || name.startsWith(r'\')) {
      return IdeInputValidation(l10n.explorerNameStartsWithSlash);
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
        if (!trashed) await _controller.files.delete(row.path);
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
  Future<void> _paste(String folder) async {
    final toPaste = await _toPaste();
    if (toPaste == null || !mounted) return;
    final files = _controller.files;
    final ancestor = context.l10n.explorerPasteIntoAncestor;
    // This machine's files, into a remote project's.
    final upload = toPaste.external && !widget.local;
    String? last;
    try {
      await _controller.expand(folder);
      final taken = {
        for (final entry in _controller.childrenOf(folder) ?? const [])
          entry.name,
      };
      for (final file in toPaste.files) {
        final source = file.path;
        final target = p.join(folder, p.basename(source));
        if (toPaste.cut && target == source) continue;
        if (!upload && (source == folder || p.isWithin(source, folder))) {
          _report(ancestor);
          break;
        }
        if (toPaste.cut) {
          await files.rename(source, target);
          _controller.forget(source);
          widget.onMoved?.call(source, target);
          last = target;
        } else {
          var name = p.basename(source);
          while (taken.contains(name)) {
            name = ideIncrementFileName(name, isFolder: file.directory);
          }
          taken.add(name);
          final copy = p.join(folder, name);
          if (upload) {
            await copyLocalTo(files, source, copy);
          } else {
            await files.copy(source, copy);
          }
          last = copy;
        }
      }
      if (toPaste.cut) _controller.clipboard = null;
    } catch (error) {
      _report(error);
    }
    await _controller.refresh();
    if (last != null) await _controller.reveal(last);
  }

  String _relative(String path) =>
      p.relative(path, from: _controller.rootOf(path)).replaceAll(r'\', '/');

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
    final repositories = widget.repositories;
    IdeGitDecorations? decorationsOf(String path) {
      if (repositories.isEmpty) return decorations;
      for (final repository in repositories) {
        final root = repository.state?.root;
        if (root != null && (p.equals(root, path) || p.isWithin(root, path))) {
          return repository.decorations;
        }
      }
      return null;
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
              final view = _ExplorerRowView(
                row: row,
                selected: _controller.isSelected(row.path),
                focusedItem: row.path == _controller.selected,
                focused: focused,
                decoration: switch (decorationsOf(row.path)) {
                  _ when row.message != null => null,
                  null => null,
                  final decorations when row.isDirectory => decorations.folder(
                    row.path,
                  ),
                  final decorations => decorations.file(row.path),
                },
                onTap: () {
                  _focusNode.requestFocus();
                  _click(row);
                },
                onContextMenu: (position) {
                  _focusNode.requestFocus();
                  unawaited(_showMenu(position, row));
                },
              );
              // Dragged onto the chat's composer, it goes in as a file.
              return row.message != null
                  ? KeyedSubtree(key: ValueKey(row.path), child: view)
                  : FileDraggable(
                      key: ValueKey(row.path),
                      files: dragged(row),
                      child: view,
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
      return Stack(
        children: [
          Positioned.fill(child: guides),
          Padding(
            padding: EdgeInsets.only(left: left + 24, right: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.l10n.explorerCannotReadFolder(message),
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
