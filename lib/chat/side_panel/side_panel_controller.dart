import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/ide_scm_view.dart' show IdeScmSession;
import '../../ide/ide_explorer.dart';
import '../../settings/user_settings.dart';
import 'file_edit.dart';
import 'file_open.dart';

/// A file the side panel shows: its text or its changes, as [request]
/// asked last.
class SidePanelTab {
  SidePanelTab(this.request);

  FileOpenRequest request;

  /// Goes up each time it is asked for again, for the preview to scroll to
  /// the lines asked for once more.
  int reveal = 0;

  /// Its file's text as edited, once read: kept while the tab is open (see
  /// [AgentSidePanel.keepEdit]); none for changes.
  SidePanelFileEdit? edit;

  String get path => request.path;
  bool get diff => request.diff;

  /// Its text differs from the file's, not saved.
  bool get dirty => edit?.dirty ?? false;

  /// Its edit let go of, once its preview (built with it until the tab
  /// closed) is gone.
  void _dropEdit() {
    final edit = this.edit;
    this.edit = null;
    if (edit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => edit.dispose());
    }
  }
}

/// The side panel's pages, each a list at the left and the tabs it opened
/// at the right: the project's files, the agent's changes, its background
/// commands; and the plan the agent wrote, alone, while there is one.
enum SidePanelSection { files, changes, terminal, plan }

/// The pages there whether or not there is anything on them: not the
/// plan's, there only once the agent wrote one.
const alwaysShownSections = [
  SidePanelSection.files,
  SidePanelSection.changes,
  SidePanelSection.terminal,
];

/// Each conversation keeps its page, and the tabs open on each.
class SidePanelTabs {
  SidePanelSection section = SidePanelSection.changes;

  /// The plan the agent wrote, on the plan page: none until it writes one.
  SidePanelTab? plan;

  /// The page that shows: [section], but the changes page for the plan's
  /// without a plan.
  SidePanelSection get shown => section == SidePanelSection.plan && plan == null
      ? SidePanelSection.changes
      : section;

  /// The files previewed, on the files page.
  final List<SidePanelTab> files = [];
  SidePanelTab? active;

  /// The changes shown, on the changes page.
  final List<SidePanelTab> diffs = [];
  SidePanelTab? activeDiff;

  /// What is open on the terminal page: terminals (their instances) and
  /// background commands' output (their ids).
  final List<Object> terminals = [];
  Object? terminal;

  /// The tab in front on the page shown; none on the terminal page.
  SidePanelTab? get current => switch (section) {
    SidePanelSection.files => active,
    SidePanelSection.changes => activeDiff,
    SidePanelSection.terminal => null,
    SidePanelSection.plan => plan,
  };
}

/// The agent window's side panel, at the right of the conversations as
/// the secondary side bar is in VS Code: the project's files, the changes
/// of the agent focused and its background commands. Shown or not, its
/// width, its lists' width and how changes are listed are the window's,
/// kept between runs ([toJson]); the tabs open are each conversation's own.
class AgentSidePanel extends ChangeNotifier {
  AgentSidePanel({Map<String, Object?>? state, this.onSave, this.settings}) {
    _read(state);
  }

  /// As [state] (what [toJson] gave) has it, once that is read; not once
  /// it was shown, hidden or resized meanwhile.
  void restore(Map<String, Object?>? state) {
    if (state == null || _changed) return;
    _read(state);
    notifyListeners();
  }

  /// Shown, hidden or resized since it was made.
  bool _changed = false;

  void _read(Map<String, Object?>? state) {
    if (state?['shown'] case final bool shown) _shown = shown;
    if (state?['width'] case final num width) {
      _width = width.toDouble().clamp(minWidth, maxWidth);
    }
    if (state?['listWidth'] case final num width) {
      _listWidth = width.toDouble().clamp(minListWidth, maxListWidth);
    }
    if (state?['listShown'] case final bool shown) _listShown = shown;
    if (state?['changesAsTree'] case final bool tree) _changesAsTree = tree;
  }

  /// Told when what [toJson] gives changed, to keep it.
  final VoidCallback? onSave;

  /// settings.json, where the commit's choices (the smart commit's Always
  /// and Never) are kept, as the IDE keeps them; none under test.
  final UserSettings? settings;

  /// Each repository's commit message, and its commit being written, kept
  /// while the panel is (as the IDE's Source Control view keeps its own).
  final Map<IdeGitRepository, IdeScmSession> _scm = {};

  /// The commit message and choices of [git].
  IdeScmSession scmOf(IdeGitRepository git) =>
      _scm[git] ??= IdeScmSession(settings: settings);

  static const defaultWidth = 640.0;
  static const minWidth = 280.0;
  static const maxWidth = 1400.0;

  static const defaultListWidth = 220.0;
  static const minListWidth = 140.0;
  static const maxListWidth = 480.0;

  /// The most tabs open at once on a page, for a conversation: the oldest
  /// out of sight close.
  static const maxTabs = 12;

  bool get shown => _shown;
  bool _shown = false;

  double get width => _width;
  double _width = defaultWidth;

  /// The width of the list at the left of each page.
  double get listWidth => _listWidth;
  double _listWidth = defaultListWidth;

  /// Whether the list at the left of each page shows.
  bool get listShown => _listShown;
  bool _listShown = true;

  /// The changes as a tree of their folders (as the Source Control view's
  /// View as Tree), or as a list.
  bool get changesAsTree => _changesAsTree;
  bool _changesAsTree = true;

  final Expando<SidePanelTabs> _tabs = Expando();

  /// Has the focus while it is anywhere in the panel: its keys (Close Tab)
  /// hold there.
  final FocusNode focusNode = FocusNode(debugLabel: 'side panel');

  /// The tabs open for [conversation] (its session).
  SidePanelTabs tabsOf(Object conversation) =>
      _tabs[conversation] ??= SidePanelTabs();

  /// The files page's tree of each project (by its folder), kept while
  /// the panel is, so it stays expanded as it was.
  final Map<String, IdeExplorerController> _explorers = {};

  /// The tree of the project in [root], read with [files]; a multi-folder
  /// workspace's [roots] at its top (see [setRoots] as they change).
  IdeExplorerController explorerOf(
    String root,
    IdeFileService files, {
    Stream<void> Function(String directory)? watch,
    List<String> roots = const [],
    p.Context? paths,
  }) {
    final key = root;
    final explorer = _explorers[key];
    if (explorer != null && identical(explorer.files, files)) return explorer;
    explorer?.dispose();
    return _explorers[key] = IdeExplorerController(
      files: files,
      root: root,
      watch: watch,
      roots: roots,
      paths: paths ?? p.context,
    );
  }

  /// Has the tree of the workspace in [root] show [roots], its folders
  /// now.
  void setRoots(String root, List<String> roots) =>
      _explorers[root]?.roots = roots;

  /// The repository picked on the changes page of each multi-folder
  /// workspace (by its folder): its folder's path.
  final Map<String, String> _repositories = {};

  /// The folder whose repository's changes show for the workspace in
  /// [root]; none picked yet when null (its first's show).
  String? repositoryOf(String root) => _repositories[p.normalize(root)];

  void selectRepository(String root, String folder) {
    if (_repositories[p.normalize(root)] == folder) return;
    _repositories[p.normalize(root)] = folder;
    notifyListeners();
  }

  /// Goes up each time it is asked for: shown, or a page or a tab opened in
  /// it. The window's sidebar gives way to it then where the two do not
  /// both fit, though it showed already (having given way to the sidebar).
  int get asks => _asks;
  int _asks = 0;

  void show() {
    _asks += 1;
    if (!_setShown(true)) notifyListeners();
  }

  void hide() => _setShown(false);
  void toggle() => _shown ? hide() : show();

  void showSection(Object conversation, SidePanelSection section) {
    tabsOf(conversation).section = section;
    show();
  }

  /// Shows [id] in its tab: a terminal (its instance), or a background
  /// command's output (its id).
  void openTerminal(Object conversation, Object id) {
    final tabs = tabsOf(conversation);
    if (!tabs.terminals.contains(id)) {
      tabs.terminals.add(id);
      while (tabs.terminals.length > maxTabs) {
        tabs.terminals.removeAt(0);
      }
    }
    tabs.terminal = id;
    showSection(conversation, SidePanelSection.terminal);
  }

  /// Closes the tab of [id]; selects the one after it, else before it,
  /// else none.
  void closeTerminal(Object conversation, Object id) {
    final tabs = tabsOf(conversation);
    final index = tabs.terminals.indexOf(id);
    if (index < 0) return;
    tabs.terminals.removeAt(index);
    if (tabs.terminal == id) {
      tabs.terminal = tabs.terminals.isEmpty
          ? null
          : tabs.terminals[index.clamp(0, tabs.terminals.length - 1)];
    }
    notifyListeners();
  }

  /// Whether it changed.
  bool _setShown(bool shown) {
    if (shown == _shown) return false;
    _shown = shown;
    _changed = true;
    notifyListeners();
    onSave?.call();
    return true;
  }

  /// As dragged; kept once the drag ends ([save]).
  set width(double width) {
    final clamped = width.clamp(minWidth, maxWidth);
    if (clamped == _width) return;
    _width = clamped;
    _changed = true;
    notifyListeners();
  }

  /// As dragged; kept once the drag ends ([save]).
  set listWidth(double width) {
    final clamped = width.clamp(minListWidth, maxListWidth);
    if (clamped == _listWidth) return;
    _listWidth = clamped;
    _changed = true;
    notifyListeners();
  }

  void toggleList() {
    _listShown = !_listShown;
    _changed = true;
    notifyListeners();
    onSave?.call();
  }

  set changesAsTree(bool tree) {
    if (tree == _changesAsTree) return;
    _changesAsTree = tree;
    _changed = true;
    notifyListeners();
    onSave?.call();
  }

  void save() => onSave?.call();

  /// Shows [request] for [conversation], in front: a file on the files
  /// page, a file's changes on the changes page, the plan on its own; in
  /// the tab of the same file if there is one.
  void open(Object conversation, FileOpenRequest request) {
    final tabs = tabsOf(conversation);
    if (request.plan) return _openPlan(tabs, request);
    final list = request.diff ? tabs.diffs : tabs.files;
    var tab = list.where((tab) => tab.path == request.path).firstOrNull;
    if (tab == null) {
      tab = SidePanelTab(request);
      list.add(tab);
      // The oldest out of sight close; not one with unsaved changes.
      while (list.length > maxTabs) {
        final oldest = list.indexWhere((tab) => !tab.dirty);
        if (oldest < 0 || oldest == list.length - 1) break;
        list.removeAt(oldest)._dropEdit();
      }
    } else {
      tab
        ..request = request
        ..reveal += 1;
    }
    if (request.diff) {
      tabs
        ..activeDiff = tab
        ..section = SidePanelSection.changes;
    } else {
      tabs
        ..active = tab
        ..section = SidePanelSection.files;
      _reveal(request.path);
    }
    _showAsked();
  }

  /// The plan page, [request]'s plan on it: read anew where it showed.
  void _openPlan(SidePanelTabs tabs, FileOpenRequest request) {
    if (tabs.plan case final tab? when tab.path == request.path) {
      tab
        ..request = request
        ..reveal += 1;
    } else {
      tabs.plan?._dropEdit();
      tabs.plan = SidePanelTab(request);
    }
    tabs.section = SidePanelSection.plan;
    _showAsked();
  }

  /// Shown, as a page or tab asked for in it.
  void _showAsked() {
    _asks += 1;
    if (!_shown) {
      _shown = true;
      _changed = true;
      onSave?.call();
    }
    notifyListeners();
  }

  /// Selects [path] in the tree of its project, as the explorer follows
  /// the editor.
  void _reveal(String path) {
    for (final explorer in _explorers.values) {
      if (explorer.shows(path)) unawaited(explorer.reveal(path));
    }
  }

  /// Brings [tab] to the front for [conversation], on its page.
  void activate(Object conversation, SidePanelTab tab) {
    final tabs = tabsOf(conversation);
    if (tab.diff) {
      tabs
        ..activeDiff = tab
        ..section = SidePanelSection.changes;
    } else {
      tabs
        ..active = tab
        ..section = SidePanelSection.files;
      _reveal(tab.path);
    }
    notifyListeners();
  }

  /// Keeps [edit], its file's text as edited, with [tab] until it closes;
  /// its tab shows whether it has unsaved changes.
  void keepEdit(SidePanelTab tab, SidePanelFileEdit edit) {
    if (identical(tab.edit, edit)) return;
    tab._dropEdit();
    tab.edit = edit
      ..addListener(() {
        // A save may end once the panel is gone.
        if (!_disposed) notifyListeners();
      });
    notifyListeners();
  }

  /// Closes [tab], its changes not saved (see [SidePanelTab.dirty]);
  /// selects the one after it, else before it, else none. The plan's, its
  /// page with it, back to the changes page.
  void close(Object conversation, SidePanelTab tab) {
    final tabs = tabsOf(conversation);
    tab._dropEdit();
    if (identical(tabs.plan, tab)) {
      tabs.plan = null;
      if (tabs.section == SidePanelSection.plan) {
        tabs.section = SidePanelSection.changes;
      }
      return notifyListeners();
    }
    final list = tab.diff ? tabs.diffs : tabs.files;
    final index = list.indexOf(tab);
    if (index < 0) return;
    list.removeAt(index);
    final next = list.isEmpty ? null : list[index.clamp(0, list.length - 1)];
    if (identical(tabs.active, tab)) tabs.active = next;
    if (identical(tabs.activeDiff, tab)) tabs.activeDiff = next;
    notifyListeners();
  }

  /// Closes the tab in front of [conversation]'s page shown, as Close
  /// Editor; hides the panel where the page has none.
  void closeCurrent(Object conversation) {
    final tabs = tabsOf(conversation);
    switch (tabs.section) {
      case SidePanelSection.files ||
          SidePanelSection.changes ||
          SidePanelSection.plan:
        if (tabs.current case final tab?) return close(conversation, tab);
      case SidePanelSection.terminal:
        if (tabs.terminal case final id?) {
          return closeTerminal(conversation, id);
        }
    }
    hide();
  }

  Map<String, Object?> toJson() => {
    'shown': _shown,
    'width': _width,
    'listWidth': _listWidth,
    'listShown': _listShown,
    'changesAsTree': _changesAsTree,
  };

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    focusNode.dispose();
    for (final scm in _scm.values) {
      scm.dispose();
    }
    for (final explorer in _explorers.values) {
      explorer.dispose();
    }
    _explorers.clear();
    super.dispose();
  }
}
