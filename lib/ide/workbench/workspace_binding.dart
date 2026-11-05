// The window's services on its workspace (upstream's workbench as its
// `IWorkspaceContextService` changes folders, and the listeners of
// `IEditorService.onDidActiveEditorChange`): each service attached to the
// workspace and detached from it as another is swapped in; its folders,
// its documents and its edits told to those that follow them; the editor
// in front followed by the explorer, the history, the layout and auto
// save.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../ide_workspace.dart';
import '../lsp_ui/lsp_convert.dart' show IdeLocation;
import '../services/auto_save.dart';
import '../services/debug_view.dart';
import '../services/editors.dart';
import '../services/explorer.dart';
import '../services/extensions_view.dart';
import '../services/language.dart';
import '../services/layout.dart';
import '../services/navigation_history.dart';
import '../services/problems.dart';
import '../services/references.dart';
import '../services/scm_service.dart';
import '../services/search_view.dart';
import '../services/terminal_view.dart';
import 'contributions.dart';
import 'services.dart';
import 'storage.dart';
import 'views.dart';

class WorkspaceBinding {
  WorkspaceBinding(this._services);

  final WorkbenchServices _services;

  WorkbenchHost get _host => _services.get();
  EditorService get _editors => _services.get();
  LayoutService get _layout => _services.get();
  ExplorerService get _explorer => _services.get();
  LanguageService get _language => _services.get();
  ScmService get _scm => _services.get();
  TerminalViewService get _terminals => _services.get();
  DebugViewService get _debug => _services.get();
  AutoSaveService get _autoSave => _services.get();
  SearchViewService get _search => _services.get();

  /// The workspace attached, until it is detached.
  IdeWorkspace? get workspace => _workspace;
  IdeWorkspace? _workspace;
  late NavigationHistoryService _history;

  /// The workspace being taken up: its editor in front then is not one
  /// opened, which would leave the Git log.
  bool _attaching = false;
  String? _activeKey;

  /// Has the services follow [workspace].
  void attach(IdeWorkspace workspace) {
    _workspace = workspace;
    workspace.layout.terminals = _terminals.terminals != null;
    _explorer.attach(workspace);
    _language.attach(workspace);
    _services.get<ProblemsService>().clear();
    _services.get<ReferencesService>().clear();
    _services.add(workspace);
    _scm.attach(workspace);
    _history = _services.add(
      NavigationHistoryService(
        workspace: workspace,
        caret: () => _editors.position,
        open: (location) => _editors.openLocation(location, record: false),
        select: _editors.select,
      ),
    );
    workspace.addListener(_workspaceChanged);
    workspace.edits.addListener(_documentEdited);
    _layout.attach(workspace.layout);
    _activeKey = null;
    _attaching = true;
    _workspaceChanged();
    _attaching = false;
    // New terminals start in the project (a workspace's first folder);
    // those running stay where they are. The chat's start where it says.
    _terminals.root = workspace.roots.firstOrNull ?? workspace.root;
    _debug.attach(workspace);
  }

  void detach() {
    final workspace = _workspace;
    if (workspace == null) return;
    _workspace = null;
    _debug.detach(workspace);
    workspace.removeListener(_workspaceChanged);
    workspace.edits.removeListener(_documentEdited);
    _autoSave.detach();
    _services.remove<NavigationHistoryService>();
    _services.remove<IdeWorkspace>(owned: false);
    _layout.detach();
    _scm.detach();
    _explorer.detach();
    _language.detach();
  }

  /// A multi-folder workspace's folders, or the repository shown (of a
  /// workspace's, or of those in a folder's subfolders) changed: the
  /// explorer, Quick Open and Source Control follow.
  void _rootsChanged(IdeWorkspace workspace) {
    _explorer.rootsChanged();
    if (workspace.isMultiRoot) {
      _terminals.root = workspace.roots.firstOrNull ?? workspace.root;
    }
    _scm.rootsChanged();
  }

  /// An edit typed in the editor, which the workspace's own listeners
  /// hear of only when it makes the document dirty or clean again.
  void _documentEdited() {
    _language.documentChanged();
    _autoSave.schedule();
    _search.documentsChanged();
  }

  /// Follows the active editor: remembers it for Quick Open and reveals it
  /// in the explorer, as VS Code's `explorer.autoReveal` does.
  void _workspaceChanged() {
    final workspace = _workspace!;
    _rootsChanged(workspace);
    _services.get<WorkbenchStorage>().keepSoon();
    _language.documentChanged();
    _history.documentsChanged();
    _search.documentsChanged();
    _autoSave.documentsChanged();
    final active = workspace.active;
    if (workspace.takeReveal() case final range? when active != null) {
      final location = IdeLocation(active.path, range);
      // Once the editor shows it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_host.context == null) return;
        _layout.layout.showEditor();
        unawaited(
          _editors.openLocation(
            location,
            select: true,
            record: false,
            afterReveal: _editors.focus,
          ),
        );
      });
    }
    if (active?.key == _activeKey) return;
    // Another editor in front: `onFocusChange` saves the one left.
    if (_activeKey != null) {
      unawaited(_autoSave.saveNow(const {'onFocusChange'}));
    }
    _activeKey = active?.key;
    _history.activeChanged(active);
    if (active == null) return;
    final path = active.path;
    // Upstream's `showEditorIfHidden`: an editor opened ends the chat's
    // maximizing, and has the side bar give way to it rather than it to
    // the side bar.
    _layout.layout.showEditor();
    // In the Git log's place, which has the editor's: the explorer's view
    // back beside it.
    if (_layout.view == IdeSideView.sourceControl && !_attaching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_host.context != null &&
            _layout.view == IdeSideView.sourceControl) {
          _layout.view = IdeSideView.explorer;
        }
      });
    }
    if (!_editors.closing) _services.get<ExtensionsViewService>().editorShown();
    _language.recommendServers();
    _explorer.follow(path);
  }
}
