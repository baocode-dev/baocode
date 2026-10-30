import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import '../../browser/browser_bridge.dart';
import '../../ide/file_service.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/ide_scm_view.dart' show IdeScmSession;
import '../../ide/ide_code_editor.dart' show IdeCodeHighlights;
import '../../ide/ide_explorer.dart';
import '../../ide/search/ide_search_view.dart';
import '../../ide/search/text_search.dart';
import '../../ide/ide_diff_options.dart';
import '../../settings/user_settings.dart';
import 'file_edit.dart';
import 'file_open.dart';

/// A file the side panel shows: its text or its changes, as [request]
/// asked last.
class SidePanelTab {
  SidePanelTab(this.request) : _preview = request.preview;

  FileOpenRequest request;

  /// The tab of what was looked at last ([FileOpenRequest.preview]): the
  /// next look takes it over, unless it is pinned or edited meanwhile.
  bool get preview => _preview && !dirty;
  bool _preview;

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

  /// Its edit let go of, with its highlighting in [highlights], once its
  /// preview (built with it until the tab closed) is gone.
  void _dropEdit(IdeCodeHighlights highlights) {
    final edit = this.edit;
    this.edit = null;
    if (edit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        highlights.release(edit.controller);
        edit.dispose();
      });
    }
  }
}

/// The side panel's pages, each a list at the left and the tabs it opened
/// at the right: the project's files, the agent's changes, its background
/// commands; and the plan the agent wrote, alone, while there is one.
/// The browser's page is there once a browser of the user's has connected
/// (see lib/browser/browser_bridge.dart).
enum SidePanelSection { files, changes, terminal, browser, plan }

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
  SidePanelSection get shown => switch (section) {
    SidePanelSection.plan when plan == null => SidePanelSection.changes,
    SidePanelSection.browser when !BrowserBridge.instance.used =>
      SidePanelSection.changes,
    _ => section,
  };

  /// The files previewed, on the files page.
  final List<SidePanelTab> files = [];
  SidePanelTab? active;

  /// The changes shown, on the changes page.
  final List<SidePanelTab> diffs = [];
  SidePanelTab? activeDiff;

  /// What the terminal page shows: a terminal (its instance), or a
  /// background command's output (its id); none: its first terminal.
  Object? terminal;

  /// The tab in front on the page shown; none on the terminal page.
  SidePanelTab? get current => switch (section) {
    SidePanelSection.files => active,
    SidePanelSection.changes => activeDiff,
    SidePanelSection.terminal || SidePanelSection.browser => null,
    SidePanelSection.plan => plan,
  };
}

/// The agent window's side panel, at the right of the conversations as
/// the secondary side bar is in VS Code (or at their left, [atLeft]): the
/// project's files, the changes of the agent focused and its background
/// commands. Shown or not, its side, its width, its lists' width and how
/// changes are listed are the window's, kept between runs ([toJson]); the
/// tabs open are each conversation's own.
class AgentSidePanel extends ChangeNotifier {
  AgentSidePanel({Map<String, Object?>? state, this.onSave, this.settings}) {
    IdeDiffOptions.instance.attach(settings);
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
    if (state?['atLeft'] case final bool left) _atLeft = left;
    if (state?['searches'] case final Map<Object?, Object?> searches) {
      for (final MapEntry(:key, :value) in searches.entries) {
        if (value is Map) _keptSearches['$key'] = value.cast<String, Object?>();
      }
    }
  }

  /// Told when what [toJson] gives changed, to keep it.
  final VoidCallback? onSave;

  /// settings.json, where the commit's choices (the smart commit's Always
  /// and Never) are kept, as the IDE keeps them; none under test.
  final UserSettings? settings;

  /// Each repository's commit message, and its commit being written, kept
  /// while the panel is (as the IDE's Source Control view keeps its own).
  final Map<IdeGitRepository, IdeScmSession> _scm = {};

  /// The commit message and choices of [git]; its changes as a tree or a
  /// list as last picked ([changesAsTree]).
  IdeScmSession scmOf(IdeGitRepository git) =>
      _scm[git] ??= IdeScmSession(settings: settings)..treeView = changesAsTree;

  /// The repositories folded under their headers on the changes page of
  /// each project (by its folder), as Source Control's.
  final Map<String, Set<String>> _scmCollapsed = {};

  Set<String> scmCollapsedOf(String root) =>
      _scmCollapsed.putIfAbsent(p.normalize(root), () => {});

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

  /// Whether the list at the left of each page shows: as kept, unless a
  /// file the conversation opened put it out of the way ([open]'s
  /// `listAway`) until the panel is asked for itself or the list is.
  bool get listShown => _listShown && !_listAway;
  bool _listShown = true;
  bool _listAway = false;

  /// The changes as a tree of their folders (as the Source Control view's
  /// View as Tree), or as a list.
  bool get changesAsTree => _changesAsTree;
  bool _changesAsTree = true;

  /// Whether it is at the conversations' left, not their right (Move Side
  /// Panel Left / Right): it keeps its width and pages there.
  bool get atLeft => _atLeft;
  bool _atLeft = false;

  set atLeft(bool left) {
    if (left == _atLeft) return;
    _atLeft = left;
    _changed = true;
    notifyListeners();
    onSave?.call();
  }

  final Expando<SidePanelTabs> _tabs = Expando();

  /// Has the focus while it is anywhere in the panel: its keys (Close Tab)
  /// hold there. Of agents side by side, each pane's has its own
  /// ([focusNodeOf]).
  final FocusNode focusNode = FocusNode(debugLabel: 'side panel');

  final Map<Object, FocusNode> _focusNodes = Map.identity();

  /// The focus of [conversation]'s panel, beside its pane of agents side
  /// by side.
  FocusNode focusNodeOf(Object conversation) =>
      _focusNodes[conversation] ??= FocusNode(debugLabel: 'side panel');

  /// Whether the focus is in a panel: the window's, or a pane's.
  bool get hasFocus =>
      focusNode.hasFocus || _focusNodes.values.any((node) => node.hasFocus);

  /// The conversation of the focused pane, of agents side by side, each
  /// with a panel of its own: [show], [hide] and what opens a page or a tab
  /// in it are its, or the conversation's they name. None (or none given):
  /// the window's one panel, [shown].
  Object? Function()? pane;

  Object? get _pane => pane?.call();

  /// Each pane's panel shown or not, by its conversation: as it was left
  /// there, hidden until asked for there.
  final Expando<bool> _shownIn = Expando();

  /// Whether [conversation]'s pane has its panel shown, of agents side by
  /// side.
  bool shownIn(Object conversation) => _shownIn[conversation] ?? false;

  /// Shown, or hidden, beside [conversation]'s pane.
  void setShownIn(Object conversation, bool shown) {
    if (shown) {
      _asks += 1;
      _listAway = false;
    }
    if (shownIn(conversation) == shown && !shown) return;
    _shownIn[conversation] = shown;
    notifyListeners();
  }

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
    final made = _explorers[key] = IdeExplorerController(
      files: files,
      root: root,
      watch: watch,
      roots: roots,
      paths: paths ?? p.context,
    );
    if (_folderAsked case final folder? when made.shows(folder)) {
      _folderAsked = null;
      // Made as the page builds: changed after it.
      scheduleMicrotask(() => _revealFolder(folder));
    }
    return made;
  }

  /// The files page's text search of each project (by its folder), kept
  /// while the panel is: its query and results stay as they were when
  /// another page or project shows.
  final Map<String, IdeSearchSession> _searches = {};

  /// The search of the project in [root], run by [engine]; made once per
  /// project (its results then still there on coming back).
  IdeSearchSession searchOf(String root, IdeTextSearch engine) =>
      _searches[root] ??= _keptSearch(root, IdeSearchSession(engine: engine));

  /// Each project's search as it was left ([IdeSearchSession.kept]), its
  /// files to include and exclude and its options, kept between runs.
  final Map<String, Map<String, Object?>> _keptSearches = {};

  /// [search] as [root]'s was left, kept as it changes.
  IdeSearchSession _keptSearch(String root, IdeSearchSession search) {
    search
      ..restore(_keptSearches[root])
      ..keptChanges.addListener(() {
        final kept = search.kept;
        if (mapEquals(kept, _keptSearches[root] ?? const {})) return;
        if (kept.isEmpty) {
          _keptSearches.remove(root);
        } else {
          _keptSearches[root] = kept;
        }
        onSave?.call();
      });
    return search;
  }

  /// The projects whose files page shows the search rather than the tree.
  final Set<String> _searching = {};

  /// Whether the project in [root] shows its files page's search.
  bool searchShown(String root) => _searching.contains(root);

  void setSearchShown(String root, bool shown) {
    final changed = shown ? _searching.add(root) : _searching.remove(root);
    if (changed) notifyListeners();
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

  /// The worktree of [folder]'s repository picked for [conversation]'s
  /// changes; null while they follow its agent.
  String? worktreeOf(Object conversation, String folder) =>
      _worktrees[conversation]?[p.normalize(folder)];

  /// Shows [path]'s changes for [folder]'s repository in [conversation];
  /// null to follow its agent again.
  void chooseWorktree(Object conversation, String folder, String? path) {
    final chosen = _worktrees.putIfAbsent(conversation, () => {});
    final key = p.normalize(folder);
    if (chosen[key] == path) return;
    if (path == null) {
      chosen.remove(key);
    } else {
      chosen[key] = path;
    }
    notifyListeners();
  }

  final Map<Object, Map<String, String>> _worktrees = Map.identity();

  /// Goes up each time it is asked for: shown, or a page or a tab opened in
  /// it. The window's sidebar gives way to it then where the two do not
  /// both fit, though it showed already (having given way to the sidebar).
  int get asks => _asks;
  int _asks = 0;

  /// Shown: the focused pane's, of agents side by side ([pane]), else the
  /// window's.
  void show() {
    if (_pane case final pane?) return setShownIn(pane, true);
    _asks += 1;
    _listAway = false;
    if (!_setShown(true)) notifyListeners();
  }

  void hide() {
    if (_pane case final pane?) return setShownIn(pane, false);
    _setShown(false);
  }

  void toggle() => isShown ? hide() : show();

  /// Hides [conversation]'s: beside its pane where agents are side by
  /// side, else the window's.
  void hideFor(Object conversation) {
    if (_pane != null) return setShownIn(conversation, false);
    hide();
  }

  /// Whether the panel [show] and [hide] are for shows: the focused
  /// pane's, else the window's.
  bool get isShown => switch (_pane) {
    final pane? => shownIn(pane),
    null => _shown,
  };

  /// Shown for [conversation]: beside its pane where it is one of agents
  /// side by side, else the window's.
  void _showFor(Object conversation) {
    if (_pane != null) return setShownIn(conversation, true);
    show();
  }

  void showSection(Object conversation, SidePanelSection section) {
    tabsOf(conversation).section = section;
    _showFor(conversation);
  }

  /// Shows [id] on the terminal page: a terminal (its instance), or a
  /// background command's output (its id).
  void openTerminal(Object conversation, Object id) {
    tabsOf(conversation).terminal = id;
    showSection(conversation, SidePanelSection.terminal);
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
    _listShown = _listAway || !_listShown;
    _listAway = false;
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
  /// the tab of the same file if there is one. [listAway]: a file opened
  /// from elsewhere (the conversation) shows alone, the page's list out
  /// of the way until it is asked for (see [listShown]).
  void open(
    Object conversation,
    FileOpenRequest request, {
    bool listAway = false,
  }) {
    final tabs = tabsOf(conversation);
    if (request.plan) return _openPlan(conversation, tabs, request);
    if (listAway && !request.diff) _listAway = true;
    final list = request.diff ? tabs.diffs : tabs.files;
    var tab = list.where((tab) => tab.path == request.path).firstOrNull;
    if (tab == null) {
      tab = SidePanelTab(request);
      // In place of the one looked at last, if this is a look too.
      final looked = request.preview
          ? list.indexWhere((tab) => tab.preview)
          : -1;
      if (looked >= 0) {
        list[looked]._dropEdit(highlights);
        list[looked] = tab;
      } else {
        list.add(tab);
      }
      // The oldest out of sight close; not one with unsaved changes.
      while (list.length > maxTabs) {
        final oldest = list.indexWhere((tab) => !tab.dirty);
        if (oldest < 0 || oldest == list.length - 1) break;
        list.removeAt(oldest)._dropEdit(highlights);
      }
    } else {
      // Opened for itself: kept.
      if (!request.preview) tab._preview = false;
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
    _showAsked(conversation);
  }

  /// The plan page, [request]'s plan on it: read anew where it showed.
  void _openPlan(
    Object conversation,
    SidePanelTabs tabs,
    FileOpenRequest request,
  ) {
    if (tabs.plan case final tab? when tab.path == request.path) {
      tab
        ..request = request
        ..reveal += 1;
    } else {
      tabs.plan?._dropEdit(highlights);
      tabs.plan = SidePanelTab(request);
    }
    tabs.section = SidePanelSection.plan;
    _showAsked(conversation);
  }

  /// Shown, as a page or tab asked for in it: for [conversation], beside
  /// its pane where it is one of agents side by side.
  void _showAsked(Object conversation) {
    if (_pane != null) return setShownIn(conversation, true);
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

  /// Shows the folder at [directory] for [conversation] (a folder the
  /// conversation names): the files page, its tree beside, the folder
  /// selected and expanded there; once the tree is made if it is not yet.
  void openFolder(Object conversation, String directory) {
    _listShown = true;
    _listAway = false;
    _changed = true;
    tabsOf(conversation).section = SidePanelSection.files;
    if (!_revealFolder(directory)) _folderAsked = directory;
    _showAsked(conversation);
    onSave?.call();
  }

  /// A folder asked for before the tree that shows it was made.
  String? _folderAsked;

  /// Whether a tree shows [directory]: selected and expanded in it.
  bool _revealFolder(String directory) {
    var shown = false;
    for (final explorer in _explorers.values) {
      if (!explorer.shows(directory)) continue;
      shown = true;
      unawaited(
        explorer.reveal(directory).then((_) => explorer.expand(directory)),
      );
    }
    return shown;
  }

  /// Keeps [tab] (a double click on it): the next look opens beside it.
  void pin(SidePanelTab tab) {
    if (!tab._preview) return;
    tab._preview = false;
    notifyListeners();
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

  /// The changes page's Git log for [conversation], its changes open kept
  /// behind it.
  void showLog(Object conversation) {
    final tabs = tabsOf(conversation);
    if (tabs.activeDiff == null) return;
    tabs.activeDiff = null;
    notifyListeners();
  }

  /// Keeps [edit], its file's text as edited, with [tab] until it closes;
  /// its tab shows whether it has unsaved changes.
  void keepEdit(SidePanelTab tab, SidePanelFileEdit edit) {
    if (identical(tab.edit, edit)) return;
    tab._dropEdit(highlights);
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
    tab._dropEdit(highlights);
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
      // Its tabs are the terminals themselves, killed by their own Close.
      case SidePanelSection.terminal || SidePanelSection.browser:
        break;
    }
    hide();
  }

  Map<String, Object?> toJson() => {
    'shown': _shown,
    'width': _width,
    'listWidth': _listWidth,
    'listShown': _listShown,
    'changesAsTree': _changesAsTree,
    if (_atLeft) 'atLeft': true,
    if (_keptSearches.isNotEmpty) 'searches': {..._keptSearches},
  };

  bool _disposed = false;

  /// Its tabs' files' highlighting, kept while they are open, for a tab
  /// shown again to be colored at once.
  final IdeCodeHighlights highlights = IdeCodeHighlights();

  @override
  void dispose() {
    _disposed = true;
    highlights.dispose();
    focusNode.dispose();
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    for (final scm in _scm.values) {
      scm.dispose();
    }
    for (final explorer in _explorers.values) {
      explorer.dispose();
    }
    _explorers.clear();
    for (final search in _searches.values) {
      search.dispose();
    }
    _searches.clear();
    super.dispose();
  }
}
