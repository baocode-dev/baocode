// The Explorer view as the workbench shows it (upstream `ExplorerService`
// with explorerView.ts and its panes): the workspace's folders as a tree,
// its files listed for Quick Open, the panes open (Folders, Outline,
// Timeline), and a file revealed in it.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../settings/user_settings.dart';
import '../explorer_excludes.dart';
import '../file_service.dart';
import '../git/ide_timeline_view.dart';
import '../ide_explorer.dart';
import '../ide_quick_open.dart';
import '../ide_workspace.dart';
import '../workbench/contributions.dart';
import '../workbench/views.dart';

class ExplorerService extends ChangeNotifier {
  ExplorerService({required this.host, required this._settings});

  final WorkbenchHost host;

  /// settings.json, for `explorer.exclude`.
  final UserSettings? Function() _settings;

  /// The tree's widget, while it shows.
  final tree = GlobalKey<IdeExplorerState>();
  IdeExplorerState? get view => tree.currentState;

  /// Around the tree: whether the keyboard is in it.
  final focusNode = FocusNode(debugLabel: 'ide explorer');

  /// The open panes (Folders first, then Outline and Timeline, collapsed as
  /// VS Code starts them).
  final Set<String> panes = {'folder'};

  /// What the Timeline pane follows.
  final timeline = IdeTimelineController();

  /// The workspace's folders as the tree shows them, and its files as Quick
  /// Open lists them (another's after a workspace is swapped).
  IdeExplorerController get controller => _controller!;
  IdeExplorerController? _controller;
  IdeFileIndex get fileIndex => _fileIndex!;
  IdeFileIndex? _fileIndex;
  IdeWorkspace? _workspace;

  /// The file and folder patterns the explorer leaves out
  /// (`explorer.exclude` in settings.json; see [IdeExplorerExcludes]).
  IdeExplorerExcludes get _excludes =>
      IdeExplorerExcludes.parse(_settings()?[IdeExplorerExcludes.settingKey]);

  /// Follows [workspace]'s folders.
  void attach(IdeWorkspace workspace) {
    _workspace = workspace;
    _controller = IdeExplorerController(
      files: workspace.files,
      root: workspace.root,
      roots: workspace.roots,
      paths: workspace.paths,
      excludes: _excludes,
      // Without a folder, no tree to keep current.
      watch: workspace.hasFolder
          ? workspace.watchFolder
          : (_) => const Stream.empty(),
    );
    final index = _fileIndex = IdeFileIndex(
      workspace.files,
      workspace.root,
      roots: workspace.isMultiRoot ? workspace.roots : null,
      pathContext: workspace.paths,
      // Without a folder, the open files alone.
      lister: workspace.hasFolder
          ? null
          : (_, _) async => IdeFileListing([
              for (final doc in workspace.documents)
                if (doc.isFile && doc.label == null) doc.path,
            ]),
    );
    // A remote project's listed at once, for Quick Open not to wait on it.
    if (workspace.hasFolder && workspace.files is IdeHostFiles) {
      unawaited(index.refresh());
    }
  }

  void detach() {
    _controller?.dispose();
    _controller = null;
    _fileIndex?.dispose();
    _fileIndex = null;
    _workspace = null;
  }

  /// A multi-folder workspace's folders changed: the tree and Quick Open
  /// follow.
  void rootsChanged() {
    final workspace = _workspace;
    if (workspace == null || !workspace.isMultiRoot) return;
    controller.roots = workspace.roots;
    fileIndex.roots = workspace.roots;
  }

  /// settings.json read again: its exclusions follow it (a pattern added
  /// elsewhere shows at once).
  void settingsChanged() => _controller?.excludes = _excludes;

  /// Shows the explorer, expands [path]'s folders, selects and focuses it.
  void reveal(String path) {
    host.showView(IdeSideView.explorer);
    if (panes.add('folder')) notifyListeners();
    unawaited(
      controller.reveal(path).then((_) {
        if (host.context != null) focusNode.requestFocus();
      }),
    );
  }

  /// [path], the active editor's, selected in the tree without the
  /// keyboard (`explorer.autoReveal`).
  void follow(String path) => unawaited(_controller?.reveal(path));

  /// The pane [id] opened, or closed.
  void togglePane(String id) {
    if (!panes.remove(id)) panes.add(id);
    notifyListeners();
  }

  /// Show Outline: the explorer, its Outline pane open.
  void showOutline() {
    panes.add('outline');
    host.showView(IdeSideView.explorer);
    notifyListeners();
  }

  /// The Timeline pinned to [path], or following the editor again.
  void toggleTimelinePin(String? path) {
    timeline.togglePin(path);
    notifyListeners();
  }

  /// The explorer's context keys (explorer's `ExplorerFocusContext`,
  /// `ExplorerRootContext`…); null for others.
  Object? contextKey(String key) => switch (key) {
    'filesExplorerFocus' => focusNode.hasFocus,
    // The tree's own view, in the side bar's.
    'focusedView' when focusNode.hasFocus => 'workbench.explorer.fileView',
    _ when key.startsWith('explorerResource') => view?.contextKey(key),
    _ => null,
  };

  @override
  void dispose() {
    detach();
    focusNode.dispose();
    timeline.dispose();
    super.dispose();
  }
}
