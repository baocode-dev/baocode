/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Source Control view, as VS Code shows one Git repository: the
// Changes pane (the commit message, the Commit button, and the Merge,
// Staged and working-tree groups with their actions and menus) and the
// Graph pane (the history with its lanes, references, and each commit's
// changes).
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/scm/browser/scmViewPane.ts, scmHistoryViewPane.ts,
// scm.contribution.ts (`scm.acceptInput`, `scm.clearInput`, the focus
// command) and media/scm.css; the Git extension's commands, menus and
// messages (extensions/git/src/commands.ts, actionButton.ts and
// package.json); src/vs/workbench/browser/actions/listCommands.ts (the
// lists' keys, through [IdeKeyboardList]).
//
// Deviations: a commit's file in the graph opens the file, not a diff
// editor; the action button has Sync Changes and Publish Branch, with no
// remote providers (Publish to GitHub) and a menu at the button for the
// remote to publish to, where upstream has a quick pick; Fetch, Fetch From
// All Remotes, Pull and Push are the Changes pane's `...` and the palette's
// Git commands (a repository's `...` in CHANGES runs them on it), where
// upstream has them in the title bar's overflow; no stash, branch or tag
// commands; the smart commit's Always and Never, and the sync's Don't Show
// Again, last for the session; Generate Commit Message asks Claude Haiku
// (see commit_message.dart), where VS Code asks Copilot. The keyboard walks
// the graph's commits, not the files of an expanded one; the commit input
// keeps no history of messages (`scm.viewPreviousCommit`).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../base/smooth_scroll.dart';
import '../../chat/composer/composer_files.dart';
import '../../chat/composer/file_drag.dart';
import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../settings/user_settings.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../../workspace/editor_launcher.dart' show openExternal;
import '../../workspace/window_controls.dart';
import '../file_service.dart' show IdeHostFiles;
import '../ide_animated_list.dart';
import '../ide_commands.dart';
import '../ide_dates.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_notifications.dart';
import '../ide_panes.dart';
import '../ide_spinning.dart';
import '../save_copy.dart';
import 'commit_message.dart';
import 'git_graph_painter.dart';
import 'git_model.dart';
import 'git_review.dart';
import 'git_repository.dart';
import 'git_service.dart';
import 'git_branch_tree.dart' show IdeGitFavoriteBranches;
import 'ide_git_log_view.dart';
import 'ide_git_ref_labels.dart';
import 'scm_host.dart';
import 'scm_tree.dart';

/// What the Source Control view keeps while another view shows: the
/// commit message, which panes, groups and commits are open, and the
/// smart commit choice.
/// `scm.defaultViewSortKey`: how the list orders changes.
enum IdeScmSort { name, path, status }

class IdeScmSession {
  IdeScmSession({this.settings, this.favoriteBranches});

  /// The favorite branches of each repository, by its folder, which the
  /// window keeps (see [IdeGitLogController.favoriteBranches]).
  final IdeGitFavoriteBranches? favoriteBranches;

  /// settings.json, where the choices made in its dialogs (Always, Never,
  /// Don't Show Again) are kept as VS Code keeps them; none under test,
  /// when they last as long as the session.
  final UserSettings? settings;
  final Map<String, bool> _choices = {};

  bool _choice(String key, bool fallback) => switch (settings?[key]) {
    final bool value => value,
    _ => _choices[key] ?? fallback,
  };

  void _choose(String key, bool value) {
    _choices[key] = value;
    unawaited(
      settings?.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  final TextEditingController message = TextEditingController();
  final Set<String> expandedPanes = {'changes', 'graph'};
  final Set<String> collapsedGroups = {};
  final Set<String> expandedCommits = {};

  /// View as Tree (the default here) or View as List, and the list's order.
  bool treeView = true;
  IdeScmSort sort = IdeScmSort.path;

  /// The tree's collapsed folders (`group:folder:path`).
  final Set<String> collapsedFolders = {};

  /// The commit panel's check marks by path, where they are not the
  /// default (the tracked changes checked, the unversioned files not).
  final Map<String, bool> included = {};

  /// The commit panel's Amend.
  bool amend = false;

  /// The commit options' author (`Name <email>`), for the next commit
  /// only; null for the one configured.
  String? author;

  /// `git.alwaysSignOff`: a Signed-off-by line in each commit.
  bool get signOff => _choice('git.alwaysSignOff', false);
  set signOff(bool value) => _choose('git.alwaysSignOff', value);

  /// Whether a commit runs the repository's hooks (else `--no-verify`).
  bool get runHooks => _choice('baocode.git.runHooks', true);
  set runHooks(bool value) => _choose('baocode.git.runHooks', value);

  IdeGitCommitOptions get commitOptions =>
      IdeGitCommitOptions(author: author, signOff: signOff, runHooks: runHooks);

  /// The messages committed with, or tried, the newest first: what the
  /// commit message history has before those of the log.
  final List<String> recentMessages = [];

  void rememberMessage(String message) {
    recentMessages
      ..remove(message)
      ..insert(0, message);
    if (recentMessages.length > 20) recentMessages.removeLast();
  }

  /// Whether the commit panel lists the ignored files.
  bool showIgnored = false;

  /// `baocode.git.aiReview`: the model reviews a commit before it is made.
  bool get aiReview => _choice('baocode.git.aiReview', false);
  set aiReview(bool value) => _choose('baocode.git.aiReview', value);

  /// What the last review found; null when there is none to show.
  List<IdeGitReviewProblem>? review;

  /// Completes to stop the review under way; null when none is.
  Completer<void>? reviewing;

  /// The commit the review holds back (with Push, or not), done when
  /// committed anyway; null when none waits.
  bool? reviewHeldPush;

  /// The list's focused row, selection and anchor, kept while the view is
  /// away (the Git log left for the editor) to be where they were.
  String? listSelected;
  final Set<String> listSelection = {};
  String? listAnchor;

  /// `git.enableSmartCommit`: commit every change when none is staged.
  bool get enableSmartCommit => _choice('git.enableSmartCommit', false);
  set enableSmartCommit(bool value) => _choose('git.enableSmartCommit', value);

  /// `git.suggestSmartCommit`: ask before doing so.
  bool get suggestSmartCommit => _choice('git.suggestSmartCommit', true);
  set suggestSmartCommit(bool value) =>
      _choose('git.suggestSmartCommit', value);

  /// `git.confirmSync`: ask before Sync Changes.
  bool get confirmSync => _choice('git.confirmSync', true);
  set confirmSync(bool value) => _choose('git.confirmSync', value);

  /// `git.rebaseWhenSync`: Update Project (and Sync) rebases, else merges.
  bool get rebaseWhenSync => _choice('git.rebaseWhenSync', false);
  set rebaseWhenSync(bool value) => _choose('git.rebaseWhenSync', value);

  /// Whether Update Project asks how, as JetBrains IDEs' does until told
  /// not to.
  bool get updateProjectAsks => _choice('baocode.git.updateProjectAsks', true);
  set updateProjectAsks(bool value) =>
      _choose('baocode.git.updateProjectAsks', value);

  /// Completes to cancel the commit message being generated; null when
  /// none is. Kept here, so that the message still arrives when the view
  /// has closed meanwhile.
  Completer<void>? generating;

  /// The Graph pane's selection, scroll and focus.
  late final IdeGitGraphController graph = IdeGitGraphController(
    expandedCommits,
  );

  /// The Git log's (see ide_git_log_view.dart).
  late final IdeGitLogController log = IdeGitLogController(
    favoriteBranches: favoriteBranches,
  );

  void dispose() {
    generating?.complete();
    reviewing?.complete();
    message.dispose();
    graph.dispose();
    log.dispose();
  }
}

/// What the Graph pane keeps: the commit selected, which are open (the
/// session's), their changes as trees once they came and the folders of
/// them closed, the list's scroll and focus.
class IdeGitGraphController extends ChangeNotifier {
  IdeGitGraphController(this.expanded);

  final Set<String> expanded;
  final FocusNode focusNode = FocusNode(debugLabel: 'scm graph');
  final ScrollController scroll = SmoothScrollController();

  /// The commits whose changes were asked for, and those that came.
  final Set<String> _asked = {};
  final Map<String, _CommitTree> _trees = {};
  bool _disposed = false;

  /// [id]'s changes as a tree once they came (under [root], spelled as
  /// [paths]); asked for once, the graph built again when they come.
  _CommitTree? _treeOf(
    IdeGitRepository git,
    String id,
    String root,
    p.Context paths,
  ) {
    if (_trees[id] case final tree?) return tree;
    if (_asked.add(id)) {
      unawaited(
        git
            .commitChanges(id)
            .then(
              (changes) => changes,
              onError: (Object _) => const <IdeGitCommitChange>[],
            )
            .then((changes) {
              if (_disposed) return;
              _trees[id] = _CommitTree(id, root, changes, paths);
              notifyListeners();
            }),
      );
    }
    return null;
  }

  /// Closes [folder] of [tree], or opens it.
  void _toggleFolder(_CommitTree tree, IdeScmTreeFolder folder) {
    tree.toggle(folder);
    notifyListeners();
  }

  String? _selected;
  String? get selected => _selected;
  set selected(String? id) {
    if (id == _selected) return;
    _selected = id;
    notifyListeners();
  }

  bool get hasFocus => focusNode.hasPrimaryFocus;

  /// Opens [row]'s commit, or closes it; the incoming and outgoing changes
  /// do not open.
  void toggle(IdeGraphRow row) {
    final id = row.commit.id;
    if (id == ideIncomingChangesId || id == ideOutgoingChangesId) return;
    if (!expanded.remove(id)) expanded.add(id);
    notifyListeners();
  }

  void collapseAll() {
    expanded.clear();
    notifyListeners();
  }

  /// Go to Current History Item: selects the commit HEAD is on, scrolled
  /// to.
  void goToCurrent(IdeGitRepository git) {
    final rows = git.graph;
    if (rows == null) return;
    final index = rows.indexWhere((row) => row.kind == IdeGraphRowKind.head);
    if (index < 0) return;
    selected = rows[index].commit.id;
    if (scroll.hasClients) {
      unawaited(
        scroll.animateTo(
          (index * IdeListColors.rowHeight).clamp(
            0,
            scroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    focusNode.dispose();
    scroll.dispose();
    super.dispose();
  }
}

/// A commit's changed files as the Source Control view's tree shows a
/// group's (see scm_tree.dart), built once; its rows, the closed folders'
/// files left out, laid out again only when a folder opens or closes.
class _CommitTree {
  _CommitTree(this.id, this.root, List<IdeGitCommitChange> changes, this.paths)
    : _changes = {for (final change in changes) change.path: change},
      _nodes = ideScmTree(root, [
        for (final change in changes)
          IdeGitResource(
            path: change.path,
            originalPath: change.originalPath,
            status: _CommitTreeRow.statusOf(change.status),
            group: IdeGitGroup.staged,
          ),
      ], paths: paths);

  final String id;
  final String root;
  final p.Context paths;
  final Map<String, IdeGitCommitChange> _changes;
  final List<IdeScmTreeNode> _nodes;

  /// The folders closed, by path.
  final Set<String> _collapsed = {};
  List<_TreeEntry>? _rows;

  bool isCollapsed(IdeScmTreeFolder folder) => _collapsed.contains(folder.path);

  void toggle(IdeScmTreeFolder folder) {
    if (!_collapsed.remove(folder.path)) _collapsed.add(folder.path);
    _rows = null;
  }

  /// The rows shown: each folder, and what is in it unless it is closed.
  List<_TreeEntry> get rows => _rows ??= () {
    final rows = <_TreeEntry>[];
    void add(List<IdeScmTreeNode> nodes, int depth) {
      for (final node in nodes) {
        switch (node) {
          case IdeScmTreeFolder(:final path):
            rows.add(_TreeEntry(ValueKey('folder:$id:$path'), node, depth));
            if (!_collapsed.contains(path)) add(node.children, depth + 1);
          case IdeScmTreeFile(:final resource):
            rows.add(
              _TreeEntry(ValueKey('file:$id:${resource.path}'), node, depth),
            );
        }
      }
    }

    add(_nodes, 0);
    return rows;
  }();

  IdeGitCommitChange changeOf(IdeGitResource resource) =>
      _changes[resource.path]!;
}

/// A row of a [_CommitTree]: a folder or a file, [depth] folders in.
class _TreeEntry {
  const _TreeEntry(this.key, this.node, this.depth);

  final Key key;
  final IdeScmTreeNode node;
  final int depth;
}

class IdeScmView extends StatefulWidget {
  const IdeScmView({
    super.key,
    required this.host,
    required this.session,
    this.sessionOf,
    required this.notifications,
    required this.onOpen,
    required this.onOpenChange,
    required this.onRevealInExplorer,
    this.revealInExplorerLabel,
    this.onOpenInTerminal,
    this.onTreeViewChanged,
    this.onAddToChat,
    this.trash,
    this.commitMessage,
    this.onCheckout,
    this.showTitle = true,
    this.showGraph = true,
    this.background,
  });

  /// The IDE's workspace, or the chat window's side panel's project.
  final IdeScmHost host;
  final IdeScmSession session;

  /// Whether the view's title shows over it: not where the page it is on
  /// is named already (the side panel's).
  final bool showTitle;

  /// Whether the Graph pane shows under CHANGES: not where the Git log
  /// shows the history (see ide_git_log_view.dart).
  final bool showGraph;

  /// Behind it; the side bar's when null.
  final Color? background;

  /// What Reveal in Explorer View is called where the explorer is named
  /// otherwise (the side panel's files page); Reveal in Explorer View when
  /// null.
  final String? revealInExplorerLabel;

  /// Opens a terminal in a folder (a repository's Open in Terminal); none
  /// offered when null.
  final ValueChanged<String>? onOpenInTerminal;

  /// Told when View as Tree or View as List is picked, for it to be kept.
  final ValueChanged<bool>? onTreeViewChanged;

  /// The session of a repository of the workspace's ([session] for the one
  /// shown): its commit message, and which of its groups and folders are
  /// folded, when CHANGES shows several (#76). [session] for all when null.
  final IdeScmSession Function(IdeGitRepository git)? sessionOf;
  final IdeNotifications notifications;

  /// Checkout to… (the workbench's Branch picker) on a repository; none
  /// offered when null.
  final ValueChanged<IdeGitRepository>? onCheckout;

  /// Opens a file in the editor.
  final Future<void> Function(String path, {bool focusEditor}) onOpen;

  /// Opens a change's editor, as a click and Open Changes do (the Git
  /// extension's `openChange`): the diff of its sides, or its one side;
  /// [head], its original (Open File (HEAD)).
  final Future<void> Function(
    IdeGitResource resource, {
    bool head,
    bool focusEditor,
  })
  onOpenChange;
  final ValueChanged<String> onRevealInExplorer;

  /// Puts files and folders in the chat's composer; not offered when null.
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  /// Moves a file to the Trash (true once it did); null where there is no
  /// Trash, and untracked files are deleted.
  final Future<bool> Function(String path)? trash;

  /// Writes commit messages (Generate Commit Message); none offered when
  /// null.
  final IdeCommitMessageModel? commitMessage;

  @override
  State<IdeScmView> createState() => IdeScmViewState();
}

/// A row of the Changes list the keyboard walks: a repository's header
/// (when more than one repository shows, #76), a resource group, a folder
/// of the tree, or a change.
sealed class _ScmRow {
  /// What `_selected` holds for it.
  String get key;

  /// Its group's or folder's key; null for a group and a repository.
  String? get parent;

  /// The repository it belongs to; null when one repository shows alone.
  IdeGitRepository? get repo;
}

/// A repository's row in CHANGES (its name, branch and change count),
/// shown above its groups when more than one repository is picked (#76).
final class _RepositoryRow implements _ScmRow {
  _RepositoryRow(this.repo, this.changes);

  /// The repository whose changes its groups' rows follow.
  @override
  final IdeGitRepository repo;

  /// How many changes it has, for its badge.
  final int changes;

  @override
  String get key => 'repo:${repo.service.root}';

  @override
  String? get parent => null;
}

/// A repository's commit message and action button in CHANGES, under its
/// header, when more than one repository shows (#76): as the list's header
/// is for one. Of its own height, which the keyboard steps over.
final class _CommitBoxRow implements _ScmRow {
  _CommitBoxRow(this.repo);

  @override
  final IdeGitRepository repo;

  @override
  String get key => 'commit:${repo.service.root}';

  @override
  String? get parent => 'repo:${repo.service.root}';
}

final class _GroupRow implements _ScmRow {
  _GroupRow(this.repo, this.group, this.resources);

  @override
  final IdeGitRepository? repo;
  final IdeGitGroup group;
  final List<IdeGitResource> resources;

  @override
  String get key =>
      repo == null ? group.name : '${repo!.service.root}\x00${group.name}';

  @override
  String? get parent => repo == null ? null : 'repo:${repo!.service.root}';
}

final class _FolderRow implements _ScmRow {
  _FolderRow(
    this.repo,
    this.group,
    this.folder,
    this.depth,
    this.key,
    this.parent,
  );

  @override
  final IdeGitRepository? repo;
  final IdeGitGroup group;
  final IdeScmTreeFolder folder;
  final int depth;
  @override
  final String key;
  @override
  final String parent;
}

final class _ResourceRow implements _ScmRow {
  _ResourceRow(this.repo, this.resource, this.treeDepth, this.parent);

  @override
  final IdeGitRepository? repo;
  final IdeGitResource resource;

  /// Its depth in the tree; null in the list.
  final int? treeDepth;
  @override
  final String parent;

  @override
  late final String key = '${resource.group.name}:${resource.path}';
}

/// The Changes list's rows for the shown repositories and the view's
/// settings when they were made: made again only when one of them changed,
/// for the list's builds and its keyboard asking for them many times
/// between.
final class _ScmRows {
  _ScmRows(
    this.repos,
    IdeScmSession session,
    List<IdeScmSession> sessions,
    Set<String> collapsedRepositories,
    this.rows,
  ) : treeView = session.treeView,
      sort = session.sort,
      folds = [
        for (final of in sessions)
          (of, {...of.collapsedGroups}, {...of.collapsedFolders}),
      ],
      collapsedRepositories = {...collapsedRepositories};

  /// The repositories shown (their statuses), in the order they list.
  final List<(IdeGitRepository, IdeGitState)> repos;
  final bool treeView;
  final IdeScmSort sort;

  /// The sessions of the repositories shown, with their folded groups and
  /// folders.
  final List<(IdeScmSession, Set<String>, Set<String>)> folds;

  /// The repositories folded under their headers (by root), when more than
  /// one shows.
  final Set<String> collapsedRepositories;
  final List<_ScmRow> rows;

  bool isFor(
    List<(IdeGitRepository, IdeGitState)> repos,
    IdeScmSession session,
    List<IdeScmSession> sessions,
    Set<String> collapsedRepositories,
  ) =>
      _sameRepos(repos, this.repos) &&
      session.treeView == treeView &&
      session.sort == sort &&
      _sameFolds(sessions) &&
      setEquals(collapsedRepositories, this.collapsedRepositories);

  bool _sameFolds(List<IdeScmSession> sessions) {
    if (sessions.length != folds.length) return false;
    for (var i = 0; i < folds.length; i++) {
      final (of, groups, folders) = folds[i];
      if (!identical(sessions[i], of) ||
          !setEquals(of.collapsedGroups, groups) ||
          !setEquals(of.collapsedFolders, folders)) {
        return false;
      }
    }
    return true;
  }

  static bool _sameRepos(
    List<(IdeGitRepository, IdeGitState)> a,
    List<(IdeGitRepository, IdeGitState)> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i].$1, b[i].$1) || !identical(a[i].$2, b[i].$2)) {
        return false;
      }
    }
    return true;
  }

  /// Each row's index by its key.
  late final Map<String, int> indices = {
    for (final (index, row) in rows.indexed) row.key: index,
  };

  /// Each row's widget's key.
  late final List<Key> keys = [
    for (final row in rows)
      row is _GroupRow ? ValueKey('group:${row.key}') : ValueKey(row.key),
  ];
}

class IdeScmViewState extends State<IdeScmView>
    with IdeKeyboardList<IdeScmView> {
  final FocusNode _inputFocus = FocusNode(debugLabel: 'scm input');
  final FocusNode _listFocus = FocusNode(debugLabel: 'scm list');
  final ScrollController _changesScroll = SmoothScrollController();

  /// Each repository's Publish Branch, where the menu of remotes opens.
  final Map<IdeGitRepository, GlobalKey> _publishKeys = {};
  IdeInputValidation? _validation;

  /// With several repositories shown, each one's input (its focus and its
  /// validation) and its commit box's measured height (#76).
  final Map<IdeGitRepository, FocusNode> _inputFocuses = {};
  final Map<IdeGitRepository, IdeInputValidation> _validations = {};
  final Map<String, double> _commitBoxHeights = {};

  /// The rows above the changes (the input, the action button), measured
  /// for revealing a row, and their last height.
  final GlobalKey _headerKey = GlobalKey();
  double _headerHeight = 0;

  /// The focused row's key: a resource's (`group:path`), a folder's or a
  /// group's (`group`).
  String? _selected;

  /// The selected rows' keys, [_selected] among them unless cleared, and
  /// the row a Shift click selects from (upstream's anchor).
  final Set<String> _selection = {};
  String? _anchor;
  IdeGitRepository? get _git => widget.host.git;
  IdeScmSession get _session => widget.session;
  IdeGitGraphController get _graph => _session.graph;

  /// [git]'s session: its message, and its folded groups and folders.
  IdeScmSession _sessionOf(IdeGitRepository git) =>
      identical(git, _git) ? _session : widget.sessionOf?.call(git) ?? _session;

  /// The session folding [repo]'s rows: the one shown's when it shows
  /// alone (null).
  IdeScmSession _foldsOf(IdeGitRepository? repo) =>
      repo == null ? _session : _sessionOf(repo);

  /// Whether CHANGES shows several repositories, each with its own input.
  bool get _grouped => _reposShown > 1;

  /// [git]'s commit message input: the list header's with one repository,
  /// its commit box's with several.
  FocusNode _inputFocusOf(IdeGitRepository git) => _grouped
      ? _inputFocuses.putIfAbsent(
          git,
          () => FocusNode(debugLabel: 'scm input ${git.service.root}'),
        )
      : _inputFocus;

  IdeInputValidation? _validationOf(IdeGitRepository git) =>
      _grouped ? _validations[git] : _validation;

  void _setValidation(IdeGitRepository git, IdeInputValidation? validation) =>
      setState(() {
        if (!_grouped) {
          _validation = validation;
        } else if (validation == null) {
          _validations.remove(git);
        } else {
          _validations[git] = validation;
        }
      });

  /// The repository whose commit message input has the keyboard; null for
  /// none.
  IdeGitRepository? get _inputRepository {
    if (_inputFocus.hasFocus) return _git;
    for (final MapEntry(key: git, value: focus) in _inputFocuses.entries) {
      if (focus.hasFocus) return git;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _message = _session.message.text;
    _session.message.addListener(_messageChanged);
    _listFocus.addListener(_rebuild);
    _selected = _session.listSelected;
    _selection.addAll(_session.listSelection);
    _anchor = _session.listAnchor;
  }

  @override
  void didUpdateWidget(IdeScmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.message.removeListener(_messageChanged);
      widget.session.message.addListener(_messageChanged);
      _message = _session.message.text;
      _validation = null;
      // Another repository of a workspace's shown alone: its own rows.
      // With several, the rows stay: the one shown follows the selection.
      if (!_grouped) {
        _selected = null;
        _selection.clear();
        _anchor = null;
      }
    }
  }

  @override
  void dispose() {
    _session.message.removeListener(_messageChanged);
    _session
      ..listSelected = _selected
      ..listSelection.clear()
      ..listSelection.addAll(_selection)
      ..listAnchor = _anchor;
    _inputFocus.dispose();
    for (final focus in _inputFocuses.values) {
      focus.dispose();
    }
    _listFocus.dispose();
    _changesScroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The message's text when it was last seen: a change clears the
  /// validation, a moved selection does not.
  String _message = '';

  void _messageChanged() {
    final text = _session.message.text;
    if (text == _message) return;
    _message = text;
    if (_validation != null) setState(() => _validation = null);
  }

  void _report(Object error) {
    if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      _report(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final git = _git;
    return ColoredBox(
      color: widget.background ?? AppColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showTitle) IdeViewTitle(context.l10n.scmTitle),
          Expanded(
            child: ListenableBuilder(
              // The shown repositories, so a change in any of them
              // rebuilds CHANGES.
              listenable: Listenable.merge([
                for (final repo in _shownRepositories) repo,
              ]),
              builder: (context, _) => git == null
                  ? _Welcome([context.l10n.scmNoProviders])
                  : _body(git),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(IdeGitRepository git) {
    final l10n = context.l10n;
    final state = git.state;
    final Widget content;
    if (!git.loaded) {
      content = const SizedBox.shrink();
    } else if (state == null) {
      final error = git.error;
      content = (error is IdeGitException && error.message.startsWith('Git is')
          ? _Welcome([l10n.scmInstallGit, error.message])
          : _Welcome(
              [l10n.scmNoRepository],
              button: l10n.scmInitializeRepository,
              onPressed: () => unawaited(_run(git.initialize)),
            ));
    } else {
      content = IdePaneContainer(
        expanded: _session.expandedPanes,
        onToggle: (id) => setState(() {
          if (!_session.expandedPanes.remove(id)) {
            _session.expandedPanes.add(id);
          }
        }),
        panes: [
          IdePane(
            id: 'changes',
            title: l10n.scmChanges,
            weight: 3,
            actions: [
              IdePaneAction(
                icon: Codicons.check,
                tooltip: _withCommitKeys(l10n.scmCommit),
                // With several repositories, the one of the input or the
                // row with the keyboard.
                onPressed: () => unawaited(
                  _commit(repo: _inputRepository ?? _focusedRow?.repo),
                ),
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: l10n.commonRefresh,
                onPressed: () => unawaited(_refreshRepositories()),
              ),
              IdeMenuButton(
                icon: Codicons.ellipsis,
                tooltip: l10n.commonMoreActions,
                entries: _moreActions,
              ),
            ],
            body: _changesList(git, state),
          ),
          if (widget.showGraph)
            IdePane(
              id: 'graph',
              title: l10n.scmGraph,
              // Which repository's, with several.
              description: _grouped ? p.basename(git.service.root) : null,
              weight: 2,
              actions: [
                IdePaneAction(
                  icon: Codicons.target,
                  tooltip: l10n.scmGoToCurrent,
                  onPressed: () => _graph.goToCurrent(git),
                ),
                IdeMenuButton(
                  icon: Codicons.gitBranch,
                  tooltip: l10n.scmGraphBranches,
                  entries: () => [
                    IdeMenuAction(
                      l10n.scmGraphCurrentBranch,
                      checked: git.graphBranch == ideGraphCurrentBranch,
                      onSelected: () => git.graphBranch = ideGraphCurrentBranch,
                    ),
                    IdeMenuAction(
                      l10n.scmGraphAllBranches,
                      checked: git.graphBranch == null,
                      onSelected: () => git.graphBranch = null,
                    ),
                  ],
                ),
                IdePaneAction(
                  icon: Codicons.refresh,
                  tooltip: l10n.commonRefresh,
                  onPressed: () => unawaited(git.refresh()),
                ),
              ],
              body: _graphList(git),
            ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (git.busy || _session.generating != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 2,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: themeColors['progressBar.background'],
            ),
          ),
      ],
    );
  }

  // --- Keyboard ------------------------------------------------------------

  /// Whether a commit message input has the keyboard (upstream
  /// `scmRepository`, which its editor sets).
  bool get inputHasFocus => _inputRepository != null;

  /// `scmInputHasValidationMessage`: the focused input's.
  bool get hasValidation => switch (_inputRepository) {
    final git? => _validationOf(git) != null,
    null => _validation != null,
  };

  /// Whether the input's text has a selection (its
  /// `editorHasSelection`).
  bool get inputHasSelection {
    final selection = _session.message.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  /// `scm.acceptInput`: the Git repository's `git.commit`, of the input
  /// with the keyboard.
  Future<void> commit() => _commit(repo: _inputRepository);

  /// `git.fetch` (Git: Fetch): every remote of the repository shown.
  Future<void> fetch() async {
    final git = _git;
    if (git != null) await _run(git.fetch);
  }

  /// `git.fetchAll` (Git: Fetch From All Remotes).
  Future<void> fetchAll() => _fetchAll();

  /// `git.pull` (Git: Pull): pulls the repository shown.
  Future<void> pull() => _pull();

  /// `git.push` (Git: Push): pushes the repository shown.
  Future<void> push() => _push();

  /// `scm.clearInput`.
  void clearInput() => switch (_inputRepository) {
    final git? => _sessionOf(git).message.clear(),
    null => _session.message.clear(),
  };

  /// `scm.clearValidation`.
  void clearValidation() {
    final git = _inputRepository ?? _git;
    if (git != null && _validationOf(git) != null) _setValidation(git, null);
  }

  /// `workbench.scm.focus` (upstream `SCMViewPane.focus`): the input (the
  /// shown repository's), or the list where a row is selected.
  void focus() => switch ((_selected, _git)) {
    (null, final git?) => _inputFocusOf(git).requestFocus(),
    (null, null) => _inputFocus.requestFocus(),
    _ => _listFocus.requestFocus(),
  };

  bool get _graphHasFocus => _graph.hasFocus;

  /// The shown repositories with their statuses, the ones CHANGES lists.
  List<(IdeGitRepository, IdeGitState)> get _shownStates => [
    for (final git in _shownRepositories)
      if (git.state case final state?) (git, state),
  ];

  /// How many repositories CHANGES shows (more than one groups them).
  int get _reposShown => _shownStates.length;

  List<_ScmRow> get _rows {
    final states = _shownStates;
    return states.isEmpty ? const [] : _rowsOf(states).rows;
  }

  _ScmRows? _rowCache;

  /// The rows of [states] ([_changeRows]), made again only when they or the
  /// view's settings changed.
  _ScmRows _rowsOf(List<(IdeGitRepository, IdeGitState)> states) {
    final collapsed = widget.host.scmCollapsedRepositories;
    final sessions = states.length > 1
        ? [for (final (git, _) in states) _sessionOf(git)]
        : [_session];
    if (_rowCache case final cache?
        when cache.isFor(states, _session, sessions, collapsed)) {
      return cache;
    }
    return _rowCache = _ScmRows(
      states,
      _session,
      sessions,
      collapsed,
      _changeRows(states),
    );
  }

  /// The index of the row of [key] among [_rows]; -1 for none.
  int _indexOf(String? key) {
    if (key == null) return -1;
    final states = _shownStates;
    return states.isEmpty ? -1 : _rowsOf(states).indices[key] ?? -1;
  }

  List<IdeGraphRow> get _commits => _git?.graph ?? const [];

  bool _isSelected(String key) => _selection.contains(key);

  /// Focuses and selects the row of [key] alone; with several
  /// repositories, its repository becomes the one shown (the graph's, the
  /// status bar's), as upstream's follows the selection.
  void _selectOnly(String key) {
    _selected = _anchor = key;
    _selection
      ..clear()
      ..add(key);
    if (!_grouped) return;
    final at = _indexOf(key);
    if (at < 0) return;
    if (_rows[at].repo case final repo? when !identical(repo, _git)) {
      widget.host.selectRepository(repo);
    }
  }

  /// Focuses [key]'s row and selects the rows from the anchor's to it.
  void _selectRange(String key) {
    final rows = _rows;
    final to = _indexOf(key);
    var from = _indexOf(_anchor);
    if (from < 0) from = to;
    _selected = key;
    _anchor = rows[from].key;
    _selection
      ..clear()
      ..addAll([
        for (var i = from < to ? from : to; i <= (from < to ? to : from); i++)
          rows[i].key,
      ]);
  }

  /// A click on [key]'s row: with Shift, selects the rows from the last
  /// one clicked; with Cmd (Ctrl), adds the row to the selection or takes
  /// it out, and true for both (the click does nothing else); else
  /// selects the row alone (upstream's `multiSelectModifier`, `ctrlCmd`).
  bool _multiSelectClick(String key) {
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed) {
      setState(() => _selectRange(key));
      return true;
    }
    if (ideUsesMacKeys ? keyboard.isMetaPressed : keyboard.isControlPressed) {
      setState(() {
        _selected = _anchor = key;
        if (!_selection.remove(key)) _selection.add(key);
      });
      return true;
    }
    setState(() => _selectOnly(key));
    return false;
  }

  /// A right click on [key]'s row: the selection stays when the row is in
  /// it, else the row is selected alone.
  void _selectForMenu(String key) => setState(() {
    if (_isSelected(key)) {
      _selected = key;
    } else {
      _selectOnly(key);
    }
  });

  /// What an action on [key]'s row acts on, [own] the row's changes: when
  /// the row is in a selection of more than one, the changes of its group
  /// selected, alone or in a selected folder (upstream's
  /// `getSCMResources` of the selection); else [own].
  List<IdeGitResource> _targets(
    String key,
    IdeGitGroup group,
    List<IdeGitResource> own, {
    IdeGitRepository? repo,
  }) {
    if (_selection.length < 2 || !_isSelected(key)) return own;
    final targets = <String, IdeGitResource>{};
    for (final row in _rows) {
      if (!_isSelected(row.key)) continue;
      if (!identical(row.repo, repo)) continue;
      switch (row) {
        case _ResourceRow(:final resource) when resource.group == group:
          targets[resource.path] = resource;
        case _FolderRow(group: final of, :final folder) when of == group:
          for (final resource in folder.resources) {
            targets[resource.path] = resource;
          }
        default:
      }
    }
    return targets.isEmpty ? own : targets.values.toList();
  }

  _ScmRow? get _focusedRow {
    final at = _indexOf(_selected);
    return at < 0 ? null : _rows[at];
  }

  /// A group of a repository, keyed so a multi-repository list folds each
  /// on its own.
  static String _groupKey(IdeGitRepository? repo, IdeGitGroup group) =>
      repo == null ? group.name : '${repo.service.root}\x00${group.name}';

  bool _isCollapsed(_ScmRow row) => switch (row) {
    _RepositoryRow(:final repo) =>
      widget.host.scmCollapsedRepositories.contains(repo.service.root),
    _GroupRow(:final repo, :final group) => _foldsOf(
      repo,
    ).collapsedGroups.contains(_groupKey(repo, group)),
    _FolderRow(:final repo, :final key) => _foldsOf(
      repo,
    ).collapsedFolders.contains(key),
    _CommitBoxRow() || _ResourceRow() => false,
  };

  void _setCollapsed(_ScmRow row, bool collapsed) => setState(() {
    switch (row) {
      case _RepositoryRow(:final repo):
        final root = repo.service.root;
        collapsed
            ? widget.host.scmCollapsedRepositories.add(root)
            : widget.host.scmCollapsedRepositories.remove(root);
      case _GroupRow(:final repo):
        final key = _rowGroupKey(row);
        if (key == null) return;
        final groups = _foldsOf(repo).collapsedGroups;
        collapsed ? groups.add(key) : groups.remove(key);
      case _FolderRow(:final repo, :final key):
        final folders = _foldsOf(repo).collapsedFolders;
        collapsed ? folders.add(key) : folders.remove(key);
      case _CommitBoxRow() || _ResourceRow():
    }
  });

  @override
  bool get listHasFocus => _listFocus.hasPrimaryFocus || _graphHasFocus;

  @override
  int get listLength => _graphHasFocus ? _commits.length : _rows.length;

  @override
  int get listFocusedIndex => _graphHasFocus
      ? _commits.indexWhere((row) => row.commit.id == _graph.selected)
      : _indexOf(_selected);

  @override
  int get listPageSize =>
      ideRowsPerPage(_graphHasFocus ? _graph.scroll : _changesScroll);

  @override
  void listFocusAt(int index) {
    if (_graphHasFocus) {
      _graph.selected = _commits[index].commit.id;
      ideRevealRow(_graph.scroll, index);
      return;
    }
    final rows = _rows;
    // A repository's commit box is stepped over, on the way the keyboard
    // goes.
    if (rows[index] is _CommitBoxRow) {
      final from = listFocusedIndex;
      final next = index > from ? index + 1 : index - 1;
      index = next >= 0 && next < rows.length ? next : index - 1;
      if (index < 0) return;
    }
    setState(() => _selectOnly(rows[index].key));
    _revealRow(index);
  }

  void _revealRow(int index) {
    // Below the input, the action button and the limit's notice.
    if (_headerKey.currentContext?.size case final size?) {
      _headerHeight = size.height;
    }
    // Past the repositories' commit boxes above it, with several.
    var top = _headerHeight;
    final rows = _rows;
    for (var i = 0; i < index && i < rows.length; i++) {
      top += _extentOf(rows[i]) ?? IdeListColors.rowHeight;
    }
    ideRevealRange(_changesScroll, top, top + IdeListColors.rowHeight);
  }

  /// [row]'s height in the list when it has its own (a commit box's);
  /// null for the rows'.
  double? _extentOf(_ScmRow row) => switch (row) {
    _CommitBoxRow(:final repo) =>
      _commitBoxHeights[repo.service.root] ?? _commitBoxHeight,
    _ => null,
  };

  /// A commit box's height until it is measured: the input of one line
  /// and the action button.
  static const double _commitBoxHeight = 70;

  @override
  bool get listSupportsMultiselect => _listFocus.hasPrimaryFocus;

  @override
  void listExpandSelection(int delta) {
    final rows = _rows;
    if (rows.isEmpty) return;
    final at = listFocusedIndex;
    final next = at < 0 ? 0 : (at + delta).clamp(0, rows.length - 1);
    setState(() => _selectRange(rows[next].key));
    _revealRow(next);
  }

  @override
  void listSelectAll() => setState(() {
    _selection
      ..clear()
      ..addAll([for (final row in _rows) row.key]);
  });

  @override
  bool get listHasSelection =>
      _listFocus.hasPrimaryFocus && _selection.isNotEmpty;

  @override
  void listClear() => setState(_selection.clear);

  @override
  void listSelect() {
    if (_graphHasFocus) {
      final at = listFocusedIndex;
      if (at >= 0) _graph.toggle(_commits[at]);
      return;
    }
    switch (_focusedRow) {
      case final _ResourceRow row:
        unawaited(widget.onOpenChange(row.resource, focusEditor: true));
      case final row?:
        _setCollapsed(row, !_isCollapsed(row));
      case null:
    }
  }

  @override
  void listToggleExpand() {
    if (_graphHasFocus) return listSelect();
    if (_focusedRow case final row? when row is! _ResourceRow) {
      _setCollapsed(row, !_isCollapsed(row));
    }
  }

  @override
  void listExpand() {
    if (_graphHasFocus) {
      final at = listFocusedIndex;
      if (at >= 0 &&
          !_session.expandedCommits.contains(_commits[at].commit.id)) {
        _graph.toggle(_commits[at]);
      }
      return;
    }
    final row = _focusedRow;
    if (row == null || row is _ResourceRow) return;
    if (_isCollapsed(row)) {
      _setCollapsed(row, false);
    } else {
      listFocusNext(1);
    }
  }

  @override
  void listCollapse() {
    if (_graphHasFocus) {
      final at = listFocusedIndex;
      if (at >= 0 &&
          _session.expandedCommits.contains(_commits[at].commit.id)) {
        _graph.toggle(_commits[at]);
      }
      return;
    }
    final row = _focusedRow;
    if (row == null) return;
    if (row is! _ResourceRow && !_isCollapsed(row)) {
      _setCollapsed(row, true);
    } else if (row.parent case final parent?) {
      final at = _indexOf(parent);
      if (at >= 0) listFocusAt(at);
    }
  }

  @override
  void listCollapseAll() {
    if (_graphHasFocus) {
      _graph.collapseAll();
      return;
    }
    final states = _shownStates;
    if (states.isEmpty) return;
    final focused = _focusedRow;
    setState(() {
      for (final (git, state) in states) {
        final repo = states.length > 1 ? git : null;
        final folds = _foldsOf(repo);
        for (final group in IdeGitGroup.values) {
          void collapse(List<IdeScmTreeNode> nodes) {
            for (final node in nodes) {
              if (node is! IdeScmTreeFolder) continue;
              folds.collapsedFolders.add(_folderKey(repo, group, node));
              collapse(node.children);
            }
          }

          collapse(ideScmGroupTree(state, group));
          folds.collapsedGroups.add(_groupKey(repo, group));
        }
      }
      // The focus goes to its group.
      final key = focused == null ? null : _rowGroupKey(focused);
      if (key != null) _selectOnly(key);
    });
  }

  /// The key of [row]'s group, or null for a repository's row.
  static String? _rowGroupKey(_ScmRow row) => switch (row) {
    _GroupRow(:final repo, :final group) => _groupKey(repo, group),
    _FolderRow(:final repo, :final group) => _groupKey(repo, group),
    _ResourceRow(:final repo, :final resource) => _groupKey(
      repo,
      resource.group,
    ),
    _RepositoryRow() || _CommitBoxRow() => null,
  };

  @override
  bool listTreeKey(String key) {
    if (_graphHasFocus) {
      final at = listFocusedIndex;
      final expanded =
          at >= 0 && _session.expandedCommits.contains(_commits[at].commit.id);
      return switch (key) {
        'treeElementCanCollapse' => expanded,
        'treeElementCanExpand' || 'treeElementHasChild' => at >= 0 && !expanded,
        _ => false,
      };
    }
    final row = _focusedRow;
    final parent = row != null && row is! _ResourceRow;
    return switch (key) {
      'treeElementCanCollapse' => parent && !_isCollapsed(row),
      'treeElementCanExpand' => parent && _isCollapsed(row),
      'treeElementHasChild' => parent,
      'treeElementHasParent' => row?.parent != null,
      _ => false,
    };
  }

  // --- Changes -------------------------------------------------------------

  Widget _changesList(IdeGitRepository git, IdeGitState state) {
    final states = _shownStates;
    final rows = _rowsOf(states);
    final grouped = states.length > 1;
    // Each repository's rows sit under its header, one level in.
    final indent = grouped ? _repoIndent : 0.0;
    // Only the rows shown are built, and where one is is worked out from
    // their height: there can be thousands, and a scrollbar dragged.
    final list = IdeAnimatedList.builder(
      controller: _changesScroll,
      itemExtent: IdeListColors.rowHeight,
      itemExtentOf: grouped ? (index) => _extentOf(rows.rows[index]) : null,
      // The input, the action button, and past the status's limit its
      // notice; with several repositories, each has its own under its
      // header.
      header: Column(
        key: _headerKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!grouped) ...[
            _inputRow(git, state),
            _actionButtonRow(git, state),
            if (state.didHitLimit) _limitRow(git, state),
          ],
        ],
      ),
      keys: rows.keys,
      itemBuilder: (context, index) {
        final row = rows.rows[index];
        final stateOf = row.repo?.state ?? state;
        final repo = row.repo ?? git;
        final Widget built = switch (row) {
          _RepositoryRow(:final repo) => _repositoryRow(repo),
          _CommitBoxRow(:final repo) => _commitBoxRow(repo, stateOf),
          _GroupRow(:final group, :final resources) => _groupRow(
            row.key,
            grouped ? repo : git,
            group,
            resources,
            indent: indent,
          ),
          _FolderRow(:final group, :final folder, :final depth, :final key) =>
            _folderRow(
              grouped ? repo : git,
              stateOf,
              group,
              folder,
              depth,
              key,
              indent: indent,
            ),
          _ResourceRow(:final resource, :final treeDepth) => _resourceRow(
            grouped ? repo : git,
            stateOf,
            resource,
            treeDepth: treeDepth,
            indent: indent,
          ),
        };
        // The guide down from its repository's twistie.
        if (!grouped || row is _RepositoryRow) return built;
        return CustomPaint(
          foregroundPainter: _RepositoryGuidePainter(
            themeColors['tree.inactiveIndentGuidesStroke'],
          ),
          child: built,
        );
      },
    );
    return Focus(
      focusNode: _listFocus,
      // The empty space's menu is View & Sort's.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (details) => unawaited(
          showIdeMenu(
            context,
            position: details.globalPosition,
            entries: _viewSortMenu(),
          ),
        ),
        child: list,
      ),
    );
  }

  /// Past the status's limit: that only its first changes show, and that
  /// the files' changes no longer refresh it (VS Code's warning when a
  /// repository is huge).
  Widget _limitRow(IdeGitRepository git, IdeGitState state) => Padding(
    padding: const EdgeInsets.fromLTRB(19, 2, 12, 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1, right: 6),
          child: Icon(
            Codicons.warning,
            size: 14,
            color: themeColors['editorWarning.foreground'],
          ),
        ),
        Expanded(
          child: Text(
            context.l10n.scmTooManyChanges(IdeGitService.statusLimit),
            style: TextStyle(
              fontSize: 12,
              color: themeColors['descriptionForeground'],
            ),
          ),
        ),
      ],
    ),
  );

  /// The list's order (`SCMTreeSorter` in list mode).
  List<IdeGitResource> _sorted(List<IdeGitResource> resources) {
    int byPath(IdeGitResource a, IdeGitResource b) => a.path.compareTo(b.path);
    switch (_session.sort) {
      case IdeScmSort.path:
        return [...resources]..sort(byPath);
      case IdeScmSort.status:
        return [...resources]..sort((a, b) {
          final order = a.status.label.compareTo(b.status.label);
          return order != 0 ? order : byPath(a, b);
        });
      case IdeScmSort.name:
        // Each name split once, not at every comparison.
        final keyed =
            [
              for (final resource in resources)
                (resource, IdeFileNameKey(p.basename(resource.path))),
            ]..sort((a, b) {
              final order = a.$2.compareTo(b.$2);
              return order != 0 ? order : byPath(a.$1, b.$1);
            });
        return [for (final (resource, _) in keyed) resource];
    }
  }

  /// The Changes list's rows: when more than one repository shows, each
  /// repository's header (#76) over its groups; each group shown (Merge and
  /// Staged Changes hide when empty; Changes does not) and, unless
  /// collapsed, its tree's folders (expanded or not) and files under it
  /// (depth 1), or its list.
  List<_ScmRow> _changeRows(List<(IdeGitRepository, IdeGitState)> states) {
    final rows = <_ScmRow>[];
    final grouped = states.length > 1;
    for (final (git, state) in states) {
      if (grouped) {
        rows.add(_RepositoryRow(git, state.count));
        // A folded repository shows its header alone.
        if (widget.host.scmCollapsedRepositories.contains(git.service.root)) {
          continue;
        }
        rows.add(_CommitBoxRow(git));
      }
      _repoRows(rows, grouped ? git : null, state);
    }
    return rows;
  }

  /// [repo]'s groups and their changes; with several repositories (a
  /// [repo]), an empty Changes hides too, as upstream's do under their
  /// repository.
  void _repoRows(
    List<_ScmRow> rows,
    IdeGitRepository? repo,
    IdeGitState state,
  ) {
    final folds = _foldsOf(repo);
    for (final group in IdeGitGroup.values) {
      final resources = state.group(group);
      if (resources.isEmpty &&
          (repo != null || group != IdeGitGroup.workingTree)) {
        continue;
      }
      final groupRow = _GroupRow(repo, group, resources);
      rows.add(groupRow);
      if (folds.collapsedGroups.contains(groupRow.key)) continue;
      final parent = groupRow.key;
      if (!_session.treeView) {
        for (final resource in _sorted(resources)) {
          rows.add(_ResourceRow(repo, resource, null, parent));
        }
        continue;
      }
      void add(List<IdeScmTreeNode> nodes, int depth, String parent) {
        for (final node in nodes) {
          switch (node) {
            case IdeScmTreeFolder():
              final key = _folderKey(repo, group, node);
              rows.add(_FolderRow(repo, group, node, depth, key, parent));
              if (!folds.collapsedFolders.contains(key)) {
                add(node.children, depth + 1, key);
              }
            case IdeScmTreeFile(:final resource):
              rows.add(_ResourceRow(repo, resource, depth, parent));
          }
        }
      }

      add(ideScmGroupTree(state, group), 2, parent);
    }
  }

  static String _folderKey(
    IdeGitRepository? repo,
    IdeGitGroup group,
    IdeScmTreeFolder folder,
  ) => repo == null
      ? '${group.name}:folder:${folder.path}'
      : '${repo.service.root}\x00${group.name}:folder:${folder.path}';

  /// `Menus.ViewSort`: View as List or Tree, and the list's order.
  List<IdeMenuEntry> _viewSortMenu() => ideMenuGroups([
    [
      IdeMenuAction(
        context.l10n.scmViewAsList,
        checked: !_session.treeView,
        onSelected: () => _setTreeView(false),
      ),
      IdeMenuAction(
        context.l10n.scmViewAsTree,
        checked: _session.treeView,
        onSelected: () => _setTreeView(true),
      ),
    ],
    [
      for (final (sort, label) in [
        (IdeScmSort.name, context.l10n.scmSortByName),
        (IdeScmSort.path, context.l10n.scmSortByPath),
        (IdeScmSort.status, context.l10n.scmSortByStatus),
      ])
        IdeMenuAction(
          label,
          checked: _session.sort == sort,
          enabled: !_session.treeView,
          onSelected: () => setState(() {
            for (final session in _viewSessions) {
              session.sort = sort;
            }
          }),
        ),
    ],
  ]);

  /// The sessions the view's mode and order are kept in: every shown
  /// repository's, so that it stays as the one shown changes.
  List<IdeScmSession> get _viewSessions => [
    _session,
    for (final git in _shownRepositories) _sessionOf(git),
  ];

  /// View as Tree, or as List; told to [IdeScmView.onTreeViewChanged].
  void _setTreeView(bool tree) {
    setState(() {
      for (final session in _viewSessions) {
        session.treeView = tree;
      }
    });
    widget.onTreeViewChanged?.call(tree);
  }

  /// A folder of the tree: its chevron, icon and (compressed) name, the
  /// actions on everything in it, and the dot of what changed inside.
  Widget _folderRow(
    IdeGitRepository git,
    IdeGitState state,
    IdeGitGroup group,
    IdeScmTreeFolder folder,
    int depth,
    String key, {
    double indent = 0,
  }) {
    // The folded folders of its repository's (the one shown's alone).
    final folders = _sessionOf(git).collapsedFolders;
    final collapsed = folders.contains(key);
    // Gathered when acted on: a folder can hold thousands.
    final actions = _folderActions(
      git,
      group,
      () => _targets(
        key,
        group,
        folder.resources.toList(),
        repo: _reposShown > 1 ? git : null,
      ),
    );
    final bubble = git.decorations?.folder(folder.path)?.color;
    final row = IdeListRow(
      key: ValueKey(key),
      selected: _isSelected(key),
      focusedItem: _selected == key,
      focused: _listFocus.hasFocus,
      tooltip: state.pathContext.relative(folder.path, from: state.root),
      onTap: () {
        _listFocus.requestFocus();
        if (_multiSelectClick(key)) return;
        setState(() {
          if (!folders.remove(key)) folders.add(key);
        });
      },
      onContextMenu: (position) {
        _selectForMenu(key);
        unawaited(
          showIdeMenu(
            context,
            position: position,
            entries: ideMenuGroups([
              [
                for (final action in actions)
                  IdeMenuAction(action.label, onSelected: action.run),
                if (group == IdeGitGroup.workingTree)
                  IdeMenuAction(
                    context.l10n.scmAddToGitignore,
                    onSelected: () => unawaited(_ignore(state, [folder.path])),
                  ),
              ],
              ..._pathMenu(state, folder.path, folder: true),
              [
                IdeMenuAction(
                  context.l10n.commonCollapseAll,
                  onSelected: () =>
                      _collapse(group, repo: git, under: folder.path),
                ),
              ],
            ]),
          ),
        );
      },
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: indent + 8.0 + (depth - 1) * 8,
          right: 12,
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
                  color: themeColors['sideBar.foreground'],
                ),
              ),
            ),
            FolderIcon(folder.path, size: 16, expanded: !collapsed),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(
                name: folder.label,
                actions: [
                  if (hovered ||
                      ((_selected == key || _isSelected(key)) &&
                          _listFocus.hasFocus))
                    for (final action in actions)
                      _InlineAction(
                        icon: action.icon,
                        tooltip: action.label,
                        onPressed: action.run,
                      ),
                ],
              ),
            ),
            if (bubble != null)
              Padding(
                padding: const EdgeInsets.only(left: 5),
                child: SizedBox(
                  width: 14,
                  child: Icon(
                    Codicons.circleFilled,
                    size: 14,
                    color: bubble.withValues(alpha: .4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return _draggable([ComposerFile(folder.path, directory: true)], row);
  }

  /// [row], dragged onto the chat's composer, puts [files] in.
  Widget _draggable(List<ComposerFile> files, Widget row) =>
      FileDraggable(key: row.key, files: files, child: row);

  /// `scm/resourceFolder/context`'s inline actions: on every change in the
  /// folder, or of the selection it is in ([targets]).
  List<_Action> _folderActions(
    IdeGitRepository git,
    IdeGitGroup group,
    List<IdeGitResource> Function() targets,
  ) => switch (group) {
    IdeGitGroup.merge => [
      _Action(
        context.l10n.scmStageChanges,
        Codicons.add,
        () => unawaited(_run(() => git.stage(targets()))),
      ),
    ],
    IdeGitGroup.staged => [
      _Action(
        context.l10n.scmUnstageChanges,
        Codicons.remove,
        () => unawaited(_run(() => git.unstage(targets()))),
      ),
    ],
    IdeGitGroup.workingTree => [
      _Action(
        context.l10n.scmDiscardChanges,
        Codicons.discard,
        () =>
            unawaited(_discard(targets(), repo: _reposShown > 1 ? git : null)),
      ),
      _Action(
        context.l10n.scmStageChanges,
        Codicons.add,
        () => unawaited(_run(() => git.stage(targets()))),
      ),
    ],
  };

  /// A commit button's tooltip: [title] and the keys committing, Commit's
  /// (`git.commit`), else the input's Accept (`scm.acceptInput`, which
  /// commits).
  String _withCommitKeys(String title) =>
      switch (KeybindingService.instance.labelFor('git.commit')) {
        final keys? => '$title ($keys)',
        null => KeybindingService.instance.titleWithKeybinding(
          title,
          'scm.acceptInput',
        ),
      };

  /// `scm.acceptInput`'s keybinding, else ⌘Enter / Ctrl+Enter (upstream's
  /// placeholder).
  String get _commitKey =>
      KeybindingService.instance.labelFor('scm.acceptInput') ??
      const IdeKeybinding(LogicalKeyboardKey.enter, primary: true).label();

  /// [git]'s commit message input.
  Widget _inputRow(IdeGitRepository git, IdeGitState state) {
    final branch = state.head.branch;
    final session = _sessionOf(git);
    return KeyedSubtree(
      key: const ValueKey('input'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 5, 12, 5),
        child: IdeInputBox(
          controller: session.message,
          focusNode: _inputFocusOf(git),
          semanticsLabel: context.l10n.scmInput,
          placeholder: branch == null
              ? context.l10n.scmMessagePlaceholder(_commitKey)
              : context.l10n.scmMessagePlaceholderBranch(_commitKey, branch),
          minLines: 1,
          maxLines: 10,
          lineHeight: 20,
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          validation: _validationOf(git),
          // The one shown's clears as its message changes (a listener,
          // which catches it being set too); the others' as typed in.
          onChanged: _grouped && _validations.containsKey(git)
              ? (_) => _setValidation(git, null)
              : null,
          // `.scm-editor-toolbar { padding: 1px 3px 1px 1px }`.
          togglesInset: 3,
          toggles: [
            if (widget.commitMessage != null)
              IdeActionButton(
                icon: session.generating == null
                    ? Codicons.sparkle
                    : Codicons.debugStop,
                tooltip: session.generating == null
                    ? context.l10n.scmGenerateCommitMessage
                    : context.l10n.scmCancelGenerateCommitMessage,
                size: 20,
                onPressed: () => unawaited(_generateCommitMessage(git, state)),
              ),
          ],
        ),
      ),
    );
  }

  /// Generate Commit Message: the staged changes' diff, else every
  /// change's (what the commit would take), with the recent commits for
  /// their conventions, to the model; its message replaces the input's.
  /// Again while it runs, cancels it.
  Future<void> _generateCommitMessage(
    IdeGitRepository git,
    IdeGitState state,
  ) async {
    final model = widget.commitMessage;
    if (model == null) return;
    final l10n = context.l10n;
    final session = _sessionOf(git);
    if (session.generating case final running?) {
      running.complete();
      return;
    }
    final cancel = session.generating = Completer<void>();
    setState(() {});
    try {
      final staged = state.group(IdeGitGroup.staged).isNotEmpty;
      final diff = await git.service.diff(
        staged: staged,
        untracked: [
          if (!staged)
            for (final resource in state.resources)
              if (resource.status == IdeGitStatus.untracked) resource.path,
        ],
      );
      if (cancel.isCompleted) return;
      if (diff.trim().isEmpty) {
        widget.notifications.notify(
          IdeSeverity.info,
          l10n.scmNoChangesToGenerate,
        );
        return;
      }
      final recent = state.head.unborn
          ? const <IdeGitCommit>[]
          : await git.service.log(limit: 10);
      final message = await model(
        ideCommitMessagePrompt(
          diff,
          recentMessages: [for (final commit in recent) commit.message],
          branch: state.head.branch,
        ),
        cancel: cancel.future,
      );
      if (cancel.isCompleted || message.isEmpty) return;
      session.message.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    } on IdeCommitMessageCancelled {
      // Cancelled: the input keeps what it had.
    } catch (error) {
      if (!cancel.isCompleted) {
        widget.notifications.notify(IdeSeverity.error, '$error');
      }
    } finally {
      if (identical(session.generating, cancel)) session.generating = null;
      if (mounted) setState(() {});
    }
  }

  /// Whether Commit has something to commit (actionButton.ts'
  /// `repositoryHasChangesToCommit`, with `git.smartCommitChanges: all`):
  /// staged changes, or others where the smart commit would stage them or
  /// offer to.
  bool _hasChangesToCommit(IdeGitRepository git, IdeGitState state) {
    final session = _sessionOf(git);
    return state.group(IdeGitGroup.staged).isNotEmpty ||
        ((session.enableSmartCommit || session.suggestSmartCommit) &&
            state.group(IdeGitGroup.workingTree).isNotEmpty);
  }

  /// The action button (actionButton.ts' `button`): Commit, enabled, while
  /// there is something to commit, else Publish Branch, Sync Changes, or
  /// Commit, disabled.
  Widget _actionButtonRow(IdeGitRepository git, IdeGitState state) {
    final changes = _hasChangesToCommit(git, state);
    return KeyedSubtree(
      key: const ValueKey('commit-button'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(19, 4, 12, 4),
        child: changes
            ? _commitButton(git, enabled: true)
            : _publishButton(git, state.head) ??
                  _syncButton(git, state.head) ??
                  _commitButton(git, enabled: false),
      ),
    );
  }

  /// `getPublishBranchActionButton`: on a branch without an upstream.
  Widget? _publishButton(IdeGitRepository git, IdeGitHead head) {
    final branch = head.branch;
    if (branch == null || head.upstream != null) return null;
    final syncing = git.syncing;
    return _SplitButton(
      key: _publishKeys.putIfAbsent(git, GlobalKey.new),
      icon: syncing ? null : Codicons.cloudUpload,
      spinning: syncing,
      label: context.l10n.scmPublishBranch,
      tooltip: syncing
          ? context.l10n.scmPublishingBranchNamed(branch)
          : context.l10n.scmPublishBranchNamed(branch),
      enabled: !git.busy,
      onPressed: () => unawaited(_publish(git, branch)),
    );
  }

  /// `getSyncChangesActionButton`: on a branch ahead of its upstream or
  /// behind it.
  Widget? _syncButton(IdeGitRepository git, IdeGitHead head) {
    final upstream = head.upstream;
    if (upstream == null ||
        (!git.syncing && head.ahead == 0 && head.behind == 0)) {
      return null;
    }
    final syncing = git.syncing;
    return _SplitButton(
      icon: syncing ? null : Codicons.sync,
      spinning: syncing,
      label: context.l10n.scmSyncChanges,
      counts: [
        if (head.behind > 0) (head.behind, Codicons.arrowDown),
        if (head.ahead > 0) (head.ahead, Codicons.arrowUp),
      ],
      tooltip: syncing
          ? context.l10n.scmSynchronizingChanges
          : _syncTooltip(head, context.l10n),
      enabled: !git.busy,
      onPressed: () => unawaited(_sync(git, head)),
    );
  }

  /// `Repository.syncTooltip`.
  static String _syncTooltip(IdeGitHead head, AppLocalizations l10n) {
    final upstream = head.upstream;
    if (head.branch == null ||
        head.unborn ||
        upstream == null ||
        (head.ahead == 0 && head.behind == 0)) {
      return l10n.scmSynchronizeChanges;
    }
    if (head.ahead == 0) return l10n.scmPullCommits(head.behind, upstream);
    if (head.behind == 0) return l10n.scmPushCommits(head.ahead, upstream);
    return l10n.scmPullPushCommits(head.behind, head.ahead, upstream);
  }

  /// `git.sync`: confirms (`git.confirmSync`), then pulls and pushes.
  Future<void> _sync(IdeGitRepository git, IdeGitHead head) async {
    final upstream = head.upstream;
    if (upstream == null) return;
    final session = _sessionOf(git);
    if (session.confirmSync) {
      final pick = await showIdeDialog(
        context,
        message: context.l10n.scmConfirmSync(upstream),
        buttons: [context.l10n.commonOk, context.l10n.scmDontShowAgain],
      );
      if (pick == 1) {
        session.confirmSync = false;
      } else if (pick != 0) {
        return;
      }
    }
    await _run(git.sync);
  }

  /// `git.publish`: to the only remote, or to the one picked.
  Future<void> _publish(IdeGitRepository git, String branch) async {
    final l10n = context.l10n;
    try {
      final remotes = await git.remotes();
      if (!mounted) return;
      if (remotes.isEmpty) {
        widget.notifications.notify(IdeSeverity.warning, l10n.scmNoRemotes);
        return;
      }
      var remote = remotes.first;
      if (remotes.length > 1) {
        String? picked;
        final box = _publishKeys[git]?.currentContext?.findRenderObject();
        await showIdeMenu(
          context,
          anchor: box is RenderBox
              ? box.localToGlobal(Offset.zero) & box.size
              : null,
          entries: [
            for (final name in remotes)
              IdeMenuAction(name, onSelected: () => picked = name),
          ],
        );
        if (picked == null) return;
        remote = picked!;
      }
      await git.publish(remote);
    } catch (error) {
      _report(error);
    }
  }

  /// Git: Fetch From All Remotes (`git.fetchAll`): every remote of every
  /// repository in the workspace.
  Future<void> _fetchAll() async {
    final repositories = widget.host.repositories;
    if (repositories.isEmpty) {
      _report(const IdeGitException('No Git repositories to fetch from.'));
      return;
    }
    await Future.wait([for (final (_, git) in repositories) _run(git.fetch)]);
  }

  /// Refresh (the CHANGES pane's): reads the status of every shown
  /// repository.
  Future<void> _refreshRepositories() async {
    for (final git in _shownRepositories) {
      await _run(git.refresh);
    }
  }

  /// Git: Pull (`git.pull`): pulls the upstream of the repository shown
  /// (with several, the one last clicked; a repository's `...` pulls it).
  Future<void> _pull() async {
    if (_git case final git?) await _run(git.pull);
  }

  /// Git: Push (`git.push`): pushes the repository shown.
  Future<void> _push() async {
    if (_git case final git?) await _run(git.push);
  }

  /// A repository's `...` in CHANGES: a terminal in its folder, its
  /// folder in the explorer or the file manager, its path; then `git.fetch`,
  /// Fetch From All Remotes, `git.pull`, `git.push` and Checkout to….
  Future<void> _repositoryMenu(
    IdeGitRepository git,
    Offset position,
    Rect? anchor,
  ) async {
    final l10n = context.l10n;
    final root = git.service.root;
    await showIdeMenu(
      context,
      anchor: anchor,
      position: anchor == null ? position : null,
      entries: ideMenuGroups([
        [
          if (widget.onOpenInTerminal case final open?)
            IdeMenuAction(
              l10n.explorerOpenInTerminal,
              onSelected: () => open(root),
            ),
          IdeMenuAction(
            widget.revealInExplorerLabel ?? l10n.tabRevealInExplorerView,
            onSelected: () => widget.onRevealInExplorer(root),
          ),
          if (_local && WindowControls.canRevealInFileManager)
            IdeMenuAction(
              l10n.revealInFileManager,
              onSelected: () =>
                  unawaited(WindowControls.revealInFileManager(root)),
            ),
        ],
        [
          IdeMenuAction(
            l10n.tabCopyPath,
            onSelected: () =>
                unawaited(Clipboard.setData(ClipboardData(text: root))),
          ),
        ],
        [
          IdeMenuAction(
            l10n.scmFetch,
            onSelected: () => unawaited(_run(git.fetch)),
          ),
          // This repository's every remote, as its Fetch: not the others'.
          IdeMenuAction(
            l10n.scmFetchFromAllRemotes,
            onSelected: () => unawaited(_run(git.fetch)),
          ),
        ],
        [
          IdeMenuAction(
            l10n.scmPull,
            onSelected: () => unawaited(_run(git.pull)),
          ),
          IdeMenuAction(
            l10n.scmPush,
            onSelected: () => unawaited(_run(git.push)),
          ),
        ],
        [
          if (widget.onCheckout case final checkout?)
            IdeMenuAction(
              l10n.gitCheckoutBranchTag,
              onSelected: () => checkout(git),
            ),
        ],
      ]),
    );
  }

  /// The repositories CHANGES shows: every one of the workspace's, each
  /// under its header, when it has several (#76, upstream's without
  /// `scm.alwaysShowRepositories`); else the one Source Control is on.
  List<IdeGitRepository> get _shownRepositories {
    final all = widget.host.repositories;
    if (all.length > 1) return [for (final (_, git) in all) git];
    final active = widget.host.git;
    return active == null ? const [] : [active];
  }

  Widget _commitButton(IdeGitRepository git, {required bool enabled}) =>
      _SplitButton(
        icon: Codicons.check,
        label: context.l10n.scmCommit,
        tooltip: _withCommitKeys(context.l10n.scmCommitChanges),
        enabled: enabled && !git.busy,
        onPressed: () => unawaited(_commit(repo: git)),
        dropdownTooltip: context.l10n.commonMoreActions,
        onDropdown: (anchor) => unawaited(
          showIdeMenu(
            context,
            anchor: anchor,
            alignRight: true,
            entries: ideMenuGroups([
              [
                IdeMenuAction(
                  context.l10n.scmCommit,
                  onSelected: () => unawaited(_commit(repo: git)),
                ),
              ],
              [
                IdeMenuAction(
                  context.l10n.scmCommitAmend,
                  onSelected: () => unawaited(_commit(amend: true, repo: git)),
                ),
              ],
            ]),
          ),
        ),
      );

  /// How far a repository's rows sit in from its header in CHANGES, when
  /// several show (#76).
  static const double _repoIndent = 12;

  /// A repository's row in CHANGES when several show (#76), as upstream's
  /// repository under CHANGES (`.scm-provider`): its name in bold, folding
  /// its commit box and groups under it, its branch after it (with what
  /// changed, [_headLabel]), and at the right end Commit, Fetch, Refresh
  /// and its `...`. Clicked, it becomes the one shown (the graph's).
  Widget _repositoryRow(IdeGitRepository git) {
    final root = git.service.root;
    final key = 'repo:$root';
    final collapsed = widget.host.scmCollapsedRepositories.contains(root);
    final l10n = context.l10n;
    return IdeListRow(
      key: ValueKey(key),
      selected: _isSelected(key),
      focusedItem: _selected == key,
      focused: _listFocus.hasFocus,
      onTap: () {
        _listFocus.requestFocus();
        if (_multiSelectClick(key)) return;
        setState(() {
          if (!widget.host.scmCollapsedRepositories.remove(root)) {
            widget.host.scmCollapsedRepositories.add(root);
          }
        });
      },
      onContextMenu: (position) =>
          unawaited(_repositoryMenu(git, position, null)),
      tooltip: root,
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 8, right: 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Transform.translate(
                offset: const Offset(3, 0),
                child: Icon(
                  collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                  size: 16,
                  color: themeColors['sideBar.foreground'],
                ),
              ),
            ),
            // The name, then its branch, cut short in turn when there is
            // no room.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      p.basename(root),
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (git.state case final state?)
                    if (_headLabel(state) case final label?)
                      Flexible(child: _RepositoryBranch(label)),
                ],
              ),
            ),
            _InlineAction(
              icon: Codicons.check,
              tooltip: _withCommitKeys(l10n.scmCommit),
              onPressed: () => unawaited(_commit(repo: git)),
            ),
            _InlineAction(
              icon: Codicons.repoFetch,
              tooltip: l10n.scmFetch,
              onPressed: () => unawaited(_run(git.fetch)),
            ),
            _InlineAction(
              icon: Codicons.refresh,
              tooltip: l10n.commonRefresh,
              onPressed: () => unawaited(_run(git.refresh)),
            ),
            _InlineAction(
              icon: Codicons.ellipsis,
              tooltip: l10n.commonMoreActions,
              onPressed: () => unawaited(
                _repositoryMenu(git, Offset.zero, _rowEndAnchor(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Git extension's `Repository.headLabel`: the branch, `*` when it
  /// has changes in the working tree, `+` staged ones, `!` conflicts; null
  /// off a branch.
  static String? _headLabel(IdeGitState state) {
    final branch = state.head.branch;
    if (branch == null) return null;
    return '$branch'
        '${state.group(IdeGitGroup.workingTree).isNotEmpty ? '*' : ''}'
        '${state.group(IdeGitGroup.staged).isNotEmpty ? '+' : ''}'
        '${state.group(IdeGitGroup.merge).isNotEmpty ? '!' : ''}';
  }

  /// [git]'s commit box under its header when several repositories show
  /// (#76), as the list's header is for one: its input, its action button
  /// and, past the status's limit, its notice. Measured, for the list to
  /// give it its height as its input grows.
  Widget _commitBoxRow(IdeGitRepository git, IdeGitState state) {
    final root = git.service.root;
    return ClipRect(
      key: ValueKey('commit:$root'),
      child: _ReportHeight(
        onHeight: (height) {
          if (!mounted || _commitBoxHeights[root] == height) return;
          setState(() => _commitBoxHeights[root] = height);
        },
        child: Padding(
          padding: const EdgeInsets.only(left: _repoIndent),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _inputRow(git, state),
              _actionButtonRow(git, state),
              if (state.didHitLimit) _limitRow(git, state),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupRow(
    String key,
    IdeGitRepository git,
    IdeGitGroup group,
    List<IdeGitResource> resources, {
    double indent = 0,
  }) {
    // The folded groups of its repository's (the one shown's alone).
    final groups = _sessionOf(git).collapsedGroups;
    final collapsed = groups.contains(key);
    void toggle() => setState(() {
      if (!groups.remove(key)) groups.add(key);
    });
    final actions = _groupActions(git, group, resources);
    return IdeListRow(
      key: ValueKey('group:$key'),
      selected: _isSelected(key),
      focusedItem: _selected == key,
      focused: _listFocus.hasFocus,
      onTap: () {
        _listFocus.requestFocus();
        if (!_multiSelectClick(key)) toggle();
      },
      onContextMenu: (position) => unawaited(
        showIdeMenu(
          context,
          position: position,
          entries: ideMenuGroups([
            [
              for (final action in actions)
                IdeMenuAction(action.label, onSelected: action.run),
            ],
            [
              if (widget.onAddToChat case final add?)
                if (_present(resources) case final present
                    when present.isNotEmpty)
                  IdeMenuAction(
                    context.l10n.sidePanelAddToChat,
                    onSelected: () =>
                        add([for (final path in present) ComposerFile(path)]),
                  ),
            ],
            [
              if (_session.treeView)
                IdeMenuAction(
                  context.l10n.commonCollapseAll,
                  onSelected: () => _collapse(group, repo: git),
                ),
            ],
          ]),
        ),
      ),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(left: indent + 8, right: 12),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Transform.translate(
                offset: const Offset(3, 0),
                child: Icon(
                  collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                  size: 16,
                  color: themeColors['sideBar.foreground'],
                ),
              ),
            ),
            Expanded(
              child: Text(
                group.localizedLabel(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: themeColors['sideBar.foreground'],
                ),
              ),
            ),
            if (hovered)
              for (final action in actions)
                _InlineAction(
                  icon: action.icon,
                  tooltip: action.label,
                  onPressed: action.run,
                ),
            const SizedBox(width: 6),
            IdeTitleBadge(resources.length),
          ],
        ),
      ),
    );
  }

  /// Folds the folders of [group]'s tree (of [git]'s when several
  /// repositories show): those in the folder at [under] (it too), or all of
  /// them.
  void _collapse(IdeGitGroup group, {IdeGitRepository? repo, String? under}) {
    final git = repo ?? _git;
    final state = git?.state;
    if (git == null || state == null) return;
    final grouped = _reposShown > 1;
    final folders = _sessionOf(git).collapsedFolders;
    setState(() {
      void collapse(List<IdeScmTreeNode> nodes, bool inside) {
        for (final node in nodes) {
          if (node is! IdeScmTreeFolder) continue;
          final mine = inside || under == null || node.path == under;
          if (mine) {
            folders.add(_folderKey(grouped ? repo : null, group, node));
          }
          collapse(node.children, mine);
        }
      }

      collapse(ideScmGroupTree(state, group), false);
    });
  }

  /// Whether the project's files are this machine's: a remote project's
  /// are not shown in the file manager, opened in its apps, nor copied to
  /// the system's clipboard.
  bool get _local => widget.host.files is! IdeHostFiles;

  /// The paths of [resources] still on disk.
  static List<String> _present(List<IdeGitResource> resources) => [
    for (final resource in resources)
      if (!_deleted(resource)) resource.path,
  ];

  /// What a menu offers of the file or [folder] at [path], as the
  /// explorer's does: putting it in the chat, copying it, revealing it,
  /// and copying its path.
  List<List<IdeMenuEntry>> _pathMenu(
    IdeGitState state,
    String path, {
    bool folder = false,
  }) {
    final l10n = context.l10n;
    return [
      [
        if (widget.onAddToChat case final add?)
          IdeMenuAction(
            l10n.sidePanelAddToChat,
            onSelected: () => add([ComposerFile(path, directory: folder)]),
          ),
        if (_local)
          IdeMenuAction(
            l10n.commonCopy,
            onSelected: () =>
                unawaited(WindowControls.writePasteboardFiles([path])),
          ),
      ],
      [
        IdeMenuAction(
          widget.revealInExplorerLabel ?? l10n.tabRevealInExplorerView,
          onSelected: () => widget.onRevealInExplorer(path),
        ),
        if (_local && WindowControls.canRevealInFileManager)
          IdeMenuAction(
            l10n.revealInFileManager,
            onSelected: () =>
                unawaited(WindowControls.revealInFileManager(path)),
          ),
        // To this machine, from a remote project's host too.
        if (!folder && canSaveFileCopy)
          IdeMenuAction(
            l10n.cmdSaveAs,
            onSelected: () => unawaited(
              saveFileCopyAs(
                widget.host.files,
                path,
              ).then<void>((_) {}, onError: _report),
            ),
          ),
      ],
      [
        IdeMenuAction(
          l10n.tabCopyPath,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: path))),
        ),
        IdeMenuAction(
          l10n.tabCopyRelativePath,
          onSelected: () => unawaited(
            Clipboard.setData(
              ClipboardData(
                text: state.pathContext.relative(path, from: state.root),
              ),
            ),
          ),
        ),
      ],
    ];
  }

  List<_Action> _groupActions(
    IdeGitRepository git,
    IdeGitGroup group,
    List<IdeGitResource> resources,
  ) => switch (group) {
    IdeGitGroup.merge => [
      _Action(
        context.l10n.scmStageAllMerge,
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
    IdeGitGroup.staged => [
      _Action(
        context.l10n.scmUnstageAll,
        Codicons.remove,
        () => unawaited(_run(git.unstageAll)),
      ),
    ],
    IdeGitGroup.workingTree => [
      _Action(
        context.l10n.scmDiscardAll,
        Codicons.discard,
        () =>
            unawaited(_discard(resources, repo: _reposShown > 1 ? git : null)),
      ),
      _Action(
        context.l10n.scmStageAll,
        Codicons.add,
        () => unawaited(_run(git.stageAll)),
      ),
    ],
  };

  /// A change's inline actions, on it or the selection it is in
  /// ([targets]).
  List<_Action> _resourceActions(
    IdeGitRepository git,
    IdeGitResource resource,
    List<IdeGitResource> Function() targets,
  ) => [
    if (!_deleted(resource))
      _Action(
        context.l10n.scmOpenFile,
        Codicons.goToFile,
        () => unawaited(_openFiles(targets())),
      ),
    ...switch (resource.group) {
      IdeGitGroup.merge => [
        _Action(
          context.l10n.scmStageChanges,
          Codicons.add,
          () => unawaited(_run(() => git.stage(targets()))),
        ),
      ],
      IdeGitGroup.staged => [
        _Action(
          context.l10n.scmUnstageChanges,
          Codicons.remove,
          () => unawaited(_run(() => git.unstage(targets()))),
        ),
      ],
      IdeGitGroup.workingTree => [
        _Action(
          context.l10n.scmDiscardChanges,
          Codicons.discard,
          () => unawaited(
            _discard(targets(), repo: _reposShown > 1 ? git : null),
          ),
        ),
        _Action(
          context.l10n.scmStageChanges,
          Codicons.add,
          () => unawaited(_run(() => git.stage(targets()))),
        ),
      ],
    },
  ];

  /// Open File on [resources]: each but the deleted, one after another.
  Future<void> _openFiles(List<IdeGitResource> resources) async {
    for (final resource in resources) {
      if (!_deleted(resource)) {
        await widget.onOpen(resource.path, focusEditor: true);
      }
    }
  }

  /// Open Changes (Open File (HEAD) with [head]) on [resources].
  Future<void> _openChanges(
    List<IdeGitResource> resources, {
    bool head = false,
  }) async {
    for (final resource in resources) {
      await widget.onOpenChange(resource, head: head, focusEditor: true);
    }
  }

  static bool _deleted(IdeGitResource resource) => switch (resource.status) {
    IdeGitStatus.deleted ||
    IdeGitStatus.indexDeleted ||
    IdeGitStatus.deletedByUs ||
    IdeGitStatus.bothDeleted => true,
    _ => false,
  };

  /// A change: in the list at depth 2 with its folder, or in the tree at
  /// [treeDepth] without (`hidePath`), after the twistie's space.
  Widget _resourceRow(
    IdeGitRepository git,
    IdeGitState state,
    IdeGitResource resource, {
    int? treeDepth,
    double indent = 0,
  }) {
    final key = '${resource.group.name}:${resource.path}';
    final paths = state.pathContext;
    final relative = paths.relative(resource.path, from: state.root);
    final folder = paths.dirname(relative);
    List<IdeGitResource> targets() => _targets(key, resource.group, [
      resource,
    ], repo: _reposShown > 1 ? git : null);
    final actions = _resourceActions(git, resource, targets);
    void open({bool focus = false}) =>
        unawaited(widget.onOpenChange(resource, focusEditor: focus));

    final row = IdeListRow(
      key: ValueKey(key),
      selected: _isSelected(key),
      focusedItem: _selected == key,
      focused: _listFocus.hasFocus,
      tooltip:
          '${paths.join(state.root, relative)} • '
          '${resource.status.localizedLabel(context.l10n)}',
      onTap: () {
        _listFocus.requestFocus();
        if (!_multiSelectClick(key)) open();
      },
      onDoubleTap: () => open(focus: true),
      onContextMenu: (position) {
        _selectForMenu(key);
        unawaited(_showResourceMenu(position, git, state, resource, targets()));
      },
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left:
              indent +
              (treeDepth == null ? 16 : 8.0 + (treeDepth - 1) * 8 + 22),
          right: 12,
        ),
        child: Row(
          children: [
            FileIcon(resource.path),
            const SizedBox(width: 6),
            Expanded(
              child: IdeResourceLabel(
                name: p.basename(resource.path),
                description: treeDepth != null || folder == '.' ? null : folder,
                strikeThrough: resource.status.strikeThrough,
                letter: resource.status.letter,
                letterColor: resource.status.color,
                actions: [
                  if (hovered ||
                      ((_selected == key || _isSelected(key)) &&
                          _listFocus.hasFocus))
                    for (final action in actions)
                      _InlineAction(
                        icon: action.icon,
                        tooltip: action.label,
                        onPressed: action.run,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    // A deleted file is not there to put in.
    if (resource.status.fileGone) return row;
    return _draggable([
      for (final target in targets())
        if (!target.status.fileGone) ComposerFile(target.path),
    ], row);
  }

  /// [resource]'s menu, its actions on [targets] (it or the selection it
  /// is in); the reveals for one alone.
  Future<void> _showResourceMenu(
    Offset position,
    IdeGitRepository git,
    IdeGitState state,
    IdeGitResource resource,
    List<IdeGitResource> targets,
  ) {
    final working = resource.group == IdeGitGroup.workingTree;
    // The merge group's has Open File alone.
    final merge = resource.group == IdeGitGroup.merge;
    final l10n = context.l10n;
    final one = targets.length == 1 && !_deleted(resource);
    final extension = p.extension(resource.path).toLowerCase();
    final present = _present(targets);
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          if (!merge)
            IdeMenuAction(
              l10n.scmOpenChanges,
              onSelected: () => unawaited(_openChanges(targets)),
            ),
          if (!_deleted(resource))
            IdeMenuAction(
              l10n.scmOpenFile,
              onSelected: () => unawaited(_openFiles(targets)),
            ),
          if (!merge)
            IdeMenuAction(
              l10n.scmOpenFileHead,
              onSelected: () => unawaited(_openChanges(targets, head: true)),
            ),
          if (one && _local) ...[
            if (extension == '.html' || extension == '.htm')
              IdeMenuAction(
                l10n.fileLinkOpenInBrowser,
                onSelected: () => unawaited(openExternal(resource.path)),
              ),
            if (WindowControls.canOpenInDefaultApp)
              IdeMenuAction(
                l10n.openInDefaultApp,
                onSelected: () => unawaited(openExternal(resource.path)),
              ),
          ],
        ],
        [
          if (resource.group == IdeGitGroup.staged)
            IdeMenuAction(
              l10n.scmUnstageChanges,
              onSelected: () => unawaited(_run(() => git.unstage(targets))),
            )
          else
            IdeMenuAction(
              l10n.scmStageChanges,
              onSelected: () => unawaited(_run(() => git.stage(targets))),
            ),
          if (working) ...[
            IdeMenuAction(
              l10n.scmDiscardChanges,
              onSelected: () => unawaited(
                _discard(targets, repo: _reposShown > 1 ? git : null),
              ),
            ),
            IdeMenuAction(
              l10n.scmAddToGitignore,
              onSelected: () => unawaited(
                _ignore(state, [for (final target in targets) target.path]),
              ),
            ),
          ],
        ],
        if (one)
          ..._pathMenu(state, resource.path)
        else if (present.isNotEmpty)
          [
            if (widget.onAddToChat case final add?)
              IdeMenuAction(
                l10n.sidePanelAddToChat,
                onSelected: () =>
                    add([for (final path in present) ComposerFile(path)]),
              ),
            if (_local)
              IdeMenuAction(
                l10n.commonCopy,
                onSelected: () =>
                    unawaited(WindowControls.writePasteboardFiles(present)),
              ),
          ],
      ]),
    );
  }

  /// The Changes pane's `...`: View & Sort, then Git's Commit and
  /// Changes submenus.
  List<IdeMenuEntry> _moreActions() {
    final git = _git!;
    final l10n = context.l10n;
    return [
      IdeMenuAction(l10n.scmViewAndSort, submenu: _viewSortMenu()),
      const IdeMenuSeparator(),
      IdeMenuAction(
        l10n.scmCommit,
        submenu: ideMenuGroups([
          [
            IdeMenuAction(
              l10n.scmCommit,
              onSelected: () => unawaited(_commit()),
            ),
            IdeMenuAction(
              l10n.scmCommitStaged,
              onSelected: () => unawaited(_commit(all: false)),
            ),
            IdeMenuAction(
              l10n.scmCommitAll,
              onSelected: () => unawaited(_commit(all: true)),
            ),
            IdeMenuAction(
              l10n.scmUndoLastCommit,
              onSelected: () => unawaited(_undoLastCommit()),
            ),
          ],
          [
            IdeMenuAction(
              l10n.scmCommitAmend,
              onSelected: () => unawaited(_commit(amend: true)),
            ),
            IdeMenuAction(
              l10n.scmCommitStagedAmend,
              onSelected: () => unawaited(_commit(all: false, amend: true)),
            ),
            IdeMenuAction(
              l10n.scmCommitAllAmend,
              onSelected: () => unawaited(_commit(all: true, amend: true)),
            ),
          ],
        ]),
      ),
      IdeMenuAction(
        l10n.scmChanges,
        submenu: [
          IdeMenuAction(
            l10n.scmStageAll,
            onSelected: () => unawaited(_run(git.stageAll)),
          ),
          IdeMenuAction(
            l10n.scmUnstageAll,
            onSelected: () => unawaited(_run(git.unstageAll)),
          ),
          IdeMenuAction(
            l10n.scmDiscardAll,
            onSelected: () => unawaited(
              _discard(git.state?.group(IdeGitGroup.workingTree) ?? []),
            ),
          ),
        ],
      ),
      const IdeMenuSeparator(),
      IdeMenuAction(
        l10n.scmFetchFromAllRemotes,
        onSelected: () => unawaited(_fetchAll()),
      ),
      IdeMenuAction(l10n.scmPull, onSelected: () => unawaited(_pull())),
      IdeMenuAction(l10n.scmPush, onSelected: () => unawaited(_push())),
    ];
  }

  // --- Commands ------------------------------------------------------------

  /// `git.commit` and its variants: [all] null commits the staged changes,
  /// or everything when none are (the smart commit, asked first); false
  /// only the staged ones; true everything. On [repo] (the repository the
  /// row's Commit is in), or the one Source Control is on.
  Future<void> _commit({
    bool? all,
    bool amend = false,
    IdeGitRepository? repo,
  }) async {
    final git = repo ?? _git;
    final state = git?.state;
    if (git == null || state == null) {
      if (repo != null) {
        widget.notifications.notify(
          IdeSeverity.info,
          context.l10n.scmNoChangesToCommit,
        );
      }
      return;
    }
    final l10n = context.l10n;
    // Its own message, with several repositories.
    final session = _sessionOf(git);
    final message = session.message.text;
    if (message.trim().isEmpty && !amend) {
      _setValidation(git, IdeInputValidation(l10n.scmProvideMessage));
      _inputFocusOf(git).requestFocus();
      return;
    }
    final noStaged = state.group(IdeGitGroup.staged).isEmpty;
    final noUnstaged = state.group(IdeGitGroup.workingTree).isEmpty;
    var commitAll = all ?? false;
    if (all == null && !noUnstaged && noStaged && !amend) {
      if (!session.enableSmartCommit) {
        if (!session.suggestSmartCommit) return;
        final pick = await showIdeDialog(
          context,
          message: l10n.scmNoStagedChanges,
          buttons: [l10n.commonYes, l10n.scmAlways, l10n.scmNever],
        );
        if (pick == 1) {
          session.enableSmartCommit = true;
        } else if (pick == 2) {
          session.suggestSmartCommit = false;
          return;
        } else if (pick != 0) {
          return;
        }
      }
      commitAll = true;
    }
    final merging = state.group(IdeGitGroup.merge).isNotEmpty;
    if (((noStaged && noUnstaged) || (!commitAll && noStaged)) &&
        !amend &&
        !merging) {
      widget.notifications.notify(
        IdeSeverity.info,
        l10n.scmNoChangesToCommit,
        primary: [
          IdeNotificationAction(
            l10n.scmCreateEmptyCommit,
            () => unawaited(_runCommit(message, git: git, empty: true)),
          ),
        ],
      );
      return;
    }
    await _runCommit(message, all: commitAll, amend: amend, git: git);
  }

  Future<void> _runCommit(
    String message, {
    IdeGitRepository? git,
    bool all = false,
    bool amend = false,
    bool empty = false,
  }) async {
    final repo = git ?? _git;
    if (repo == null) return;
    try {
      if (all && !amend) {
        await repo.commitEverything(message);
      } else {
        await repo.commit(message, all: all, amend: amend, empty: empty);
      }
      final session = _sessionOf(repo);
      if (session.message.text == message) session.message.clear();
    } catch (error) {
      _report(error);
    }
  }

  Future<void> _undoLastCommit() async {
    final git = _git;
    if (git == null) return;
    final l10n = context.l10n;
    try {
      final head = await git.headCommit();
      if (!mounted) return;
      if (head == null) {
        widget.notifications.notify(IdeSeverity.warning, l10n.scmCantUndo);
        return;
      }
      if (head.parentIds.length > 1) {
        final pick = await showIdeDialog(
          context,
          message: l10n.scmConfirmUndoMerge,
          buttons: [l10n.scmUndoMergeCommit],
        );
        if (pick != 0) return;
      }
      await git.undoCommit(head);
      _session.message.text = head.message;
    } catch (error) {
      _report(error);
    }
  }

  /// `git.clean` and `git.cleanAll`: confirms as VS Code does, tracked
  /// files and untracked ones apart, then discards. On [repo] (the row's
  /// repository with several), or the one Source Control is on.
  Future<void> _discard(
    List<IdeGitResource> resources, {
    IdeGitRepository? repo,
  }) async {
    final git = repo ?? _git;
    if (git == null || resources.isEmpty) return;
    final untracked = [
      for (final r in resources)
        if (r.status == IdeGitStatus.untracked) r,
    ];
    final tracked = [
      for (final r in resources)
        if (r.status != IdeGitStatus.untracked) r,
    ];
    final toTrash = widget.trash != null;
    final l10n = context.l10n;
    String name(IdeGitResource r) => p.basename(r.path);

    (String, String?, String) untrackedDialog(List<IdeGitResource> files) {
      final one = files.length == 1;
      final warning = toTrash
          ? ''
          : one
          ? '\n\n${l10n.scmIrreversibleFile}'
          : '\n\n${l10n.scmIrreversibleFiles}';
      return (
        one
            ? '${l10n.scmConfirmDeleteUntracked(name(files.single))}$warning'
            : '${l10n.scmConfirmDeleteUntrackedCount(files.length)}$warning',
        toTrash
            ? (one
                  ? l10n.explorerRestoreFromTrash
                  : l10n.scmRestoreFilesFromTrash)
            : null,
        toTrash
            ? l10n.explorerMoveToTrash
            : one
            ? l10n.scmDeleteFile
            : l10n.scmDeleteAllFiles(files.length),
      );
    }

    var chosen = resources;
    if (untracked.isEmpty) {
      final allDeleted = tracked.every((r) => r.status == IdeGitStatus.deleted);
      final one = tracked.length == 1;
      final pick = await showIdeDialog(
        context,
        message: allDeleted
            ? (one
                  ? l10n.scmConfirmRestore(name(tracked.single))
                  : l10n.scmConfirmRestoreAll(tracked.length))
            : (one
                  ? l10n.scmConfirmDiscard(name(tracked.single))
                  : '${l10n.scmConfirmDiscardAll(tracked.length)}\n\n'
                        '${l10n.scmIrreversibleWorkingSet}'),
        buttons: [
          allDeleted
              ? (one
                    ? l10n.scmRestoreFile
                    : l10n.scmRestoreAllFiles(tracked.length))
              : (one
                    ? l10n.scmDiscardFile
                    : l10n.scmDiscardAllFiles(tracked.length)),
        ],
      );
      if (pick != 0) return;
    } else if (tracked.isEmpty) {
      final (message, detail, button) = untrackedDialog(untracked);
      final pick = await showIdeDialog(
        context,
        message: message,
        detail: detail,
        buttons: [button],
      );
      if (pick != 0) return;
    } else {
      final (untrackedMessage, untrackedDetail, _) = untrackedDialog(untracked);
      final trackedMessage = tracked.length == 1
          ? '\n\n${l10n.scmConfirmDiscard(name(tracked.single))}'
          : '\n\n${l10n.scmConfirmDiscardAll(tracked.length)}';
      final pick = await showIdeDialog(
        context,
        message:
            '$untrackedMessage ${untrackedDetail ?? ''}$trackedMessage\n\n'
            '${l10n.scmIrreversibleWorkingSet}',
        buttons: [
          l10n.scmDiscardTrackedFiles(tracked.length),
          l10n.scmDiscardAllFiles(resources.length),
        ],
      );
      if (pick == 0) {
        chosen = tracked;
      } else if (pick != 1) {
        return;
      }
    }
    try {
      await git.discard(chosen, trash: widget.trash);
    } catch (error) {
      _report(error);
    }
    await widget.host.reload([for (final r in chosen) r.path]);
  }

  /// `git.ignore`: appends the files to [state]'s repository's
  /// `.gitignore` (in its editor, where it is open), saves it, and opens
  /// it.
  Future<void> _ignore(IdeGitState state, List<String> paths) async {
    final pathContext = state.pathContext;
    final ignoreFile = pathContext.join(state.root, '.gitignore');
    final lines = [
      for (final path in paths)
        pathContext
            .relative(path, from: state.root)
            .replaceAllMapped(
              RegExp(r'\\|\['),
              (match) => match[0] == r'\' ? '/' : r'\[',
            ),
    ].join('\n');
    try {
      await widget.host.appendLines(ignoreFile, lines);
      await widget.onOpen(ignoreFile, focusEditor: true);
    } catch (error) {
      _report(error);
    }
  }

  // --- Graph ---------------------------------------------------------------

  Widget _graphList(IdeGitRepository git) => IdeGitGraph(
    git: git,
    controller: _graph,
    background: widget.background,
    root: git.state?.root ?? widget.host.root,
    onOpen: (path) => unawaited(widget.onOpen(path, focusEditor: false)),
  );
}

/// The Graph pane's list: the history with its lanes and references, a
/// commit's changes under it once opened, and older commits as it scrolls
/// to them.
class IdeGitGraph extends StatelessWidget {
  const IdeGitGraph({
    super.key,
    required this.git,
    required this.controller,
    required this.root,
    required this.onOpen,
    this.background,
  });

  final IdeGitRepository git;
  final IdeGitGraphController controller;

  /// What it is on, behind the circles; the side bar's by default.
  final Color? background;

  /// The repository's folder, the changed files' paths shown from.
  final String root;

  /// Opens a file a commit changed.
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([git, controller, controller.focusNode]),
    builder: (context, _) {
      final rows = git.graph;
      if (rows == null) return const SizedBox.shrink();
      // Every row's key, and what builds it when it scrolls into view: an
      // open commit's thousands of files cost their keys alone.
      final keys = <Key>[];
      final builders = <WidgetBuilder>[];
      void add(Key key, WidgetBuilder builder) {
        keys.add(key);
        builders.add(builder);
      }

      final paths = git.service.pathContext;
      for (final row in rows) {
        final id = row.commit.id;
        final expanded = controller.expanded.contains(id);
        add(
          ValueKey('commit:$id'),
          (context) => _graphRow(context, row, expanded),
        );
        if (!expanded) continue;
        final tree = controller._treeOf(git, id, root, paths);
        if (tree == null) {
          add(ValueKey('changes:$id'), (_) => _loadingRow(row));
          continue;
        }
        for (final entry in tree.rows) {
          add(entry.key, (_) => _treeRow(row, tree, entry));
        }
      }
      if (git.graphHasMore) {
        final lanes = rows.isEmpty
            ? const <IdeGraphLane>[]
            : rows.last.outputLanes;
        add(
          const ValueKey('more'),
          (_) => _LoadMoreRow(
            lanes: lanes,
            onShown: () => unawaited(git.loadMoreGraph()),
          ),
        );
      }
      return Focus(
        focusNode: controller.focusNode,
        child: IdeAnimatedList.builder(
          controller: controller.scroll,
          itemExtent: IdeListColors.rowHeight,
          keys: keys,
          itemBuilder: (context, index) => builders[index](context),
        ),
      );
    },
  );

  Widget _graphRow(BuildContext context, IdeGraphRow row, bool expanded) {
    final commit = row.commit;
    final selected = controller.selected == commit.id;
    final synthetic =
        commit.id == ideIncomingChangesId || commit.id == ideOutgoingChangesId;
    final current = row.kind == IdeGraphRowKind.head;
    return IdeHover(
      key: ValueKey('commit:${commit.id}'),
      content: IdeCommitHover(row.commit, referenceColors: row.referenceColors),
      position: IdeHoverPosition.right,
      compact: false,
      child: IdeListRow(
        selected: selected,
        focused: controller.focusNode.hasFocus,
        onTap: () {
          controller.focusNode.requestFocus();
          controller
            ..selected = commit.id
            ..toggle(row);
        },
        onContextMenu: synthetic
            ? null
            : (position) {
                controller.selected = commit.id;
                unawaited(
                  showIdeMenu(
                    context,
                    position: position,
                    entries: [
                      IdeMenuAction(
                        context.l10n.scmCopyCommitHash,
                        onSelected: () => unawaited(
                          Clipboard.setData(ClipboardData(text: commit.id)),
                        ),
                      ),
                      IdeMenuAction(
                        context.l10n.scmCopyCommitMessage,
                        onSelected: () => unawaited(
                          Clipboard.setData(
                            ClipboardData(text: commit.message),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
        builder: (context, hovered) {
          // What is behind the circles: the row's list color over the side
          // bar (media/scm.css).
          final colors = themeColors;
          final background = Color.alphaBlend(
            selected
                ? colors[controller.focusNode.hasFocus
                      ? 'list.activeSelectionBackground'
                      : 'list.inactiveSelectionBackground']
                : hovered
                ? colors['list.hoverBackground']
                : Colors.transparent,
            this.background ?? colors['sideBar.background'],
          );
          return Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  CustomPaint(
                    size: Size(ideGraphWidth(row), IdeListColors.rowHeight),
                    painter: IdeGraphPainter(
                      row,
                      background: background,
                      hovered: hovered,
                      expanded: expanded,
                    ),
                  ),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: _subject(commit, context.l10n),
                            style: TextStyle(
                              fontWeight: current ? FontWeight.w600 : null,
                            ),
                          ),
                          if (!synthetic)
                            TextSpan(
                              text: '  ${commit.author}',
                              style: TextStyle(
                                fontSize: 13 * .9,
                                color: colors['descriptionForeground'],
                                fontWeight: current ? FontWeight.w600 : null,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colors['sideBar.foreground'],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // At most half the row, the message keeping the rest.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _badges(row),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// The references' badges, each with its name (`scm.graph.badges: all`):
  /// the colored ones first, in their colors, then the other branches and
  /// the tags in the default label's. Short of room, the names are cut.
  List<Widget> _badges(IdeGraphRow row) {
    String? color(IdeGitRef ref) => row.referenceColors[ref.id];
    final refs = [
      ...row.commit.references.where((ref) => color(ref) != null),
      ...row.commit.references.where((ref) => color(ref) == null),
    ];
    return [
      for (final (index, ref) in refs.indexed) ...[
        if (index > 0) const SizedBox(width: 4),
        Flexible(child: IdeGitRefBadge(ref, color(ref))),
      ],
    ];
  }

  /// The row under an open commit while its changes load: its lanes.
  Widget _loadingRow(IdeGraphRow row) => SizedBox(
    height: IdeListColors.rowHeight,
    child: Row(
      children: [
        const SizedBox(width: 4),
        CustomPaint(
          size: Size(
            ideGraphPlaceholderWidth(row.outputLanes),
            IdeListColors.rowHeight,
          ),
          painter: IdeGraphPlaceholderPainter(
            row.outputLanes,
            highlight: row.circleIndex,
          ),
        ),
      ],
    ),
  );

  /// A folder or file of [row]'s commit's [tree]: a folder opens or closes,
  /// a file (but a deleted one) opens.
  Widget _treeRow(IdeGraphRow row, _CommitTree tree, _TreeEntry entry) =>
      switch (entry.node) {
        final IdeScmTreeFolder folder => _CommitTreeRow(
          lanes: row.outputLanes,
          highlight: row.circleIndex,
          depth: entry.depth,
          tree: tree,
          folder: folder,
          onTap: () => controller._toggleFolder(tree, folder),
        ),
        IdeScmTreeFile(:final resource) => _CommitTreeRow(
          lanes: row.outputLanes,
          highlight: row.circleIndex,
          depth: entry.depth,
          tree: tree,
          resource: resource,
          onTap: resource.status == IdeGitStatus.indexDeleted
              ? null
              : () => onOpen(resource.path),
        ),
      };
}

class _Action {
  const _Action(this.label, this.icon, this.run);

  final String label;
  final IconData icon;
  final VoidCallback run;
}

/// A row's inline action: a 16px icon with a 2px padding.
class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IdeActionButton(
    icon: icon,
    tooltip: tooltip,
    size: 20,
    onPressed: onPressed,
  );
}

/// The welcome content of a view with nothing to show: paragraphs, and a
/// button up to 300px wide.
class _Welcome extends StatelessWidget {
  const _Welcome(this.paragraphs, {this.button, this.onPressed});

  final List<String> paragraphs;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 13),
    children: [
      for (final text in paragraphs)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.5),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: themeColors['sideBar.foreground'],
            ),
          ),
        ),
      if (button case final label?)
        Padding(
          padding: const EdgeInsets.only(top: 6.5),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: _SplitButton(
                label: label,
                tooltip: label,
                enabled: true,
                onPressed: onPressed!,
              ),
            ),
          ),
        ),
    ],
  );
}

/// VS Code's `.monaco-button-dropdown`: the primary button, and, when
/// [onDropdown] is set, a separator and a chevron that opens a menu.
class _SplitButton extends StatefulWidget {
  const _SplitButton({
    super.key,
    this.icon,
    this.spinning = false,
    required this.label,
    this.counts = const [],
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.dropdownTooltip,
    this.onDropdown,
  });

  final IconData? icon;

  /// `$(sync~spin)` in the icon's place.
  final bool spinning;
  final String label;

  /// After the label, each count and its icon (` 2$(arrow-up)`).
  final List<(int, IconData)> counts;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final String? dropdownTooltip;
  final ValueChanged<Rect>? onDropdown;

  @override
  State<_SplitButton> createState() => _SplitButtonState();
}

class _SplitButtonState extends State<_SplitButton> {
  bool _hoverMain = false;
  bool _hoverDropdown = false;
  final GlobalKey _dropdownKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    // `defaultButtonStyles`.
    final colors = themeColors;
    final background = colors['button.background'];
    final foreground = colors['button.foreground'];
    final border = colors['button.border'];
    final enabled = widget.enabled;
    Widget part({
      required bool hover,
      required ValueChanged<bool> onHover,
      required VoidCallback? onTap,
      required Widget child,
      required BorderRadius radius,
      Key? key,
    }) => MouseRegion(
      key: key,
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 26,
          decoration: BoxDecoration(
            color: hover && onTap != null
                ? colors['button.hoverBackground']
                : background,
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );

    final main = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: IdeHover(
        message: widget.tooltip,
        child: part(
          hover: _hoverMain,
          onHover: (value) => setState(() => _hoverMain = value),
          onTap: enabled ? widget.onPressed : null,
          radius: widget.onDropdown == null
              ? BorderRadius.circular(4)
              : const BorderRadius.horizontal(left: Radius.circular(4)),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.spinning) ...[
                  IdeSpinning(Icon(Codicons.sync, size: 16, color: foreground)),
                  const SizedBox(width: 4),
                ] else if (widget.icon case final icon?) ...[
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: foreground,
                    ),
                  ),
                ),
                for (final (count, icon) in widget.counts) ...[
                  Text(
                    ' $count',
                    style: TextStyle(
                      fontSize: 13,
                      height: 18 / 13,
                      color: foreground,
                    ),
                  ),
                  // `.monaco-text-button .codicon { margin: 0 0.2em }`.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.6),
                    child: Icon(icon, size: 16, color: foreground),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    final onDropdown = widget.onDropdown;
    return Opacity(
      opacity: enabled ? 1 : .4,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(child: main),
            if (onDropdown != null) ...[
              Container(
                width: 1,
                height: 26,
                color: background,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ColoredBox(color: colors['button.separator']),
              ),
              IdeHover(
                message: widget.dropdownTooltip ?? '',
                child: part(
                  key: _dropdownKey,
                  hover: _hoverDropdown,
                  onHover: (value) => setState(() => _hoverDropdown = value),
                  onTap: enabled
                      ? () {
                          final box =
                              _dropdownKey.currentContext!.findRenderObject()!
                                  as RenderBox;
                          onDropdown(box.localToGlobal(Offset.zero) & box.size);
                        }
                      : null,
                  radius: const BorderRadius.horizontal(
                    right: Radius.circular(4),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Codicons.chevronDown,
                      size: 16,
                      color: foreground,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A reference badge: 18px high and round, with its icon and name (cut
/// short of room); filled with the reference's color, else outlined in the
/// description's, quiet on any row (a selected one's color is often the
/// badges' default).
class IdeGitRefBadge extends StatelessWidget {
  const IdeGitRefBadge(this.ref, this.color, {super.key});

  final IdeGitRef ref;

  /// The reference's color id; none for an outlined badge.
  final String? color;

  static IconData icon(IdeGitRefKind kind) => switch (kind) {
    IdeGitRefKind.head => Codicons.target,
    IdeGitRefKind.branch => Codicons.gitBranch,
    IdeGitRefKind.remote => Codicons.cloud,
    IdeGitRefKind.tag => Codicons.tag,
  };

  @override
  Widget build(BuildContext context) {
    final branch = ref.kind == IdeGitRefKind.branch;
    final colors = themeColors;
    final color = this.color;
    final foreground = color == null
        ? colors['descriptionForeground']
        : colors['scmGraph.historyItemHoverLabelForeground'];
    final shape = BorderRadius.circular(10);
    return IdeHover(
      message: ref.name,
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: color == null ? null : colors[color],
          borderRadius: shape,
        ),
        // Drawn over, so the icon and name sit as in a filled one.
        foregroundDecoration: color == null
            ? BoxDecoration(
                border: Border.all(
                  color: foreground.withValues(alpha: foreground.a * .6),
                ),
                borderRadius: shape,
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.all(branch ? 3 : 1),
              child: Icon(
                icon(ref.kind),
                size: branch ? 12 : 16,
                color: foreground,
              ),
            ),
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    ref.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A commit's hover: its author and date, message, references and hash.
/// A commit's hover, as the graph and the timeline show it: the author,
/// when, the message, its references and its id.
class IdeCommitHover extends StatelessWidget {
  const IdeCommitHover(
    this.commit, {
    super.key,
    this.referenceColors,
    this.labels = false,
  });

  final IdeGitCommit commit;

  /// The references as the Git log draws them ([IdeGitRefLabelView]), not
  /// as badges.
  final bool labels;

  /// The graph's color ids of [commit]'s references, by id (the others in
  /// the default label's); without them (the timeline's), the references
  /// are not shown.
  final Map<String, String>? referenceColors;

  @override
  Widget build(BuildContext context) {
    final commit = this.commit;
    final colors = themeColors;
    final foreground = colors['editorHoverWidget.foreground'];
    final border = colors['editorHoverWidget.border'];
    final text = TextStyle(fontSize: 13, color: foreground);
    if (commit.id == ideIncomingChangesId ||
        commit.id == ideOutgoingChangesId) {
      return Text(_subject(commit, context.l10n), style: text);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Codicons.account, size: 14, color: foreground),
                ),
                TextSpan(
                  text: ' ${commit.author}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (commit.authorEmail.isNotEmpty)
                  TextSpan(text: ' <${commit.authorEmail}>'),
                const TextSpan(text: ', '),
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Codicons.history, size: 14, color: foreground),
                ),
                TextSpan(
                  text:
                      ' ${ideFromNow(commit.date, ago: true, fullWords: true, l10n: context.l10n)} '
                      '(${_formatDate(commit.date, context.l10n)})',
                ),
              ],
            ),
            style: text,
          ),
          const SizedBox(height: 8),
          Text(commit.message, style: text),
          if (referenceColors case final referenceColors?
              when commit.references.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: labels ? 12 : 4,
              runSpacing: 4,
              children: [
                if (labels)
                  for (final label in ideGitRefLabels(commit.references))
                    IdeGitRefLabelView(label, foreground: foreground)
                else
                  for (final ref in commit.references)
                    IdeGitRefBadge(ref, referenceColors[ref.id]),
              ],
            ),
          ],
          // `.workbench-hover hr`: the border at half strength.
          Divider(
            height: 17,
            thickness: 1,
            color: border.withValues(alpha: border.a / 2),
          ),
          Text.rich(
            TextSpan(
              children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(
                    Codicons.gitCommit,
                    size: 14,
                    color: colors['textLink.foreground'],
                  ),
                ),
                TextSpan(text: ' ${commit.shortId}'),
              ],
            ),
            style: text.copyWith(color: colors['textLink.foreground']),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date, AppLocalizations l10n) {
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    return l10n.scmCommitDate(
      '${date.month}',
      '${date.day}',
      '${date.year}',
      '$hour',
      date.minute.toString().padLeft(2, '0'),
      date.hour < 12 ? 'am' : 'pm',
    );
  }
}

/// A folder or file of an open commit's changes, beside the commit's
/// lanes, [depth] folders in: a folder with its twistie, a file with its
/// status letter.
class _CommitTreeRow extends StatelessWidget {
  const _CommitTreeRow({
    required this.lanes,
    required this.highlight,
    required this.depth,
    required this.tree,
    this.folder,
    this.resource,
    required this.onTap,
  });

  final List<IdeGraphLane> lanes;
  final int highlight;
  final int depth;
  final _CommitTree tree;
  final IdeScmTreeFolder? folder;
  final IdeGitResource? resource;
  final VoidCallback? onTap;

  /// The status of a change's letter (`git show --name-status`).
  static IdeGitStatus statusOf(String letter) => switch (letter) {
    'A' => IdeGitStatus.indexAdded,
    'D' => IdeGitStatus.indexDeleted,
    'R' => IdeGitStatus.indexRenamed,
    'C' => IdeGitStatus.indexCopied,
    'T' => IdeGitStatus.typeChanged,
    _ => IdeGitStatus.indexModified,
  };

  @override
  Widget build(BuildContext context) {
    final paths = tree.paths;
    final folder = this.folder;
    final resource = this.resource;
    final path = folder?.path ?? resource!.path;
    final relative = paths.relative(path, from: tree.root);
    final collapsed = folder != null && tree.isCollapsed(folder);
    return IdeListRow(
      onTap: onTap,
      tooltip: resource == null
          ? relative
          : '$relative • ${resource.status.localizedLabel(context.l10n)}',
      builder: (context, _) => Row(
        children: [
          const SizedBox(width: 4),
          CustomPaint(
            size: Size(
              ideGraphPlaceholderWidth(lanes),
              IdeListColors.rowHeight,
            ),
            painter: IdeGraphPlaceholderPainter(lanes, highlight: highlight),
          ),
          SizedBox(width: depth * IdeListColors.indent),
          SizedBox(
            width: 22,
            child: folder == null
                ? null
                : Icon(
                    collapsed ? Codicons.chevronRight : Codicons.chevronDown,
                    size: 16,
                    color: IdeListColors.foreground,
                  ),
          ),
          if (folder != null)
            FolderIcon(path, expanded: !collapsed)
          else
            FileIcon(path),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: resource == null
                  ? IdeResourceLabel(name: folder!.label)
                  : IdeResourceLabel(
                      name: paths.basename(path),
                      strikeThrough: resource.status.strikeThrough,
                      letter: tree.changeOf(resource).status,
                      letterColor: resource.status.color,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The last row while older commits load: the lanes going on.
class _LoadMoreRow extends StatefulWidget {
  const _LoadMoreRow({required this.lanes, required this.onShown});

  final List<IdeGraphLane> lanes;
  final VoidCallback onShown;

  @override
  State<_LoadMoreRow> createState() => _LoadMoreRowState();
}

class _LoadMoreRowState extends State<_LoadMoreRow> {
  @override
  void initState() {
    super.initState();
    // `scm.graph.pageOnScroll`: shown means scrolled to the end.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: IdeListColors.rowHeight,
    child: Row(
      children: [
        const SizedBox(width: 4),
        CustomPaint(
          size: Size(
            ideGraphPlaceholderWidth(widget.lanes),
            IdeListColors.rowHeight,
          ),
          painter: IdeGraphPlaceholderPainter(widget.lanes),
        ),
      ],
    ),
  );
}

/// A graph commit's subject; the synthetic incoming and outgoing changes'
/// in [l10n]'s language.
String _subject(IdeGitCommit commit, AppLocalizations l10n) {
  if (commit.id == ideIncomingChangesId) return l10n.scmIncomingChanges;
  if (commit.id == ideOutgoingChangesId) return l10n.scmOutgoingChanges;
  return commit.subject;
}

/// A row's `...` menu drops from the row's right end.
Rect? _rowEndAnchor(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox) return null;
  final origin = box.localToGlobal(Offset.zero);
  return Rect.fromPoints(
    origin + Offset(box.size.width - 20, box.size.height),
    origin + Offset(box.size.width, box.size.height),
  );
}

/// The indent guide of a repository's rows in CHANGES when several show
/// (#76): down from its header's twistie, in
/// `tree.inactiveIndentGuidesStroke`.
class _RepositoryGuidePainter extends CustomPainter {
  const _RepositoryGuidePainter(this.color);

  final Color color;

  /// The middle of the header's twistie (its 8px inset, half its 22px and
  /// the 3px it is moved by).
  static const double _x = 22.5;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawLine(
    const Offset(_x, 0),
    Offset(_x, size.height),
    Paint()
      ..color = color
      ..strokeWidth = 1,
  );

  @override
  bool shouldRepaint(_RepositoryGuidePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Lays its child out at the child's own height (up to none) and tells
/// [onHeight], after the frame, when that changed: a list row of a height
/// of its own, in a list that sets each row's.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
      parentUsesSize: true,
    );
    size = constraints.constrain(child.size);
    final height = child.size.height;
    if (height == _reported) return;
    _reported = height;
    SchedulerBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// A repository's branch after its name, as its status bar action: the
/// branch icon and label, only as wide as they are, the label cut short
/// when there is no room.
class _RepositoryBranch extends StatelessWidget {
  const _RepositoryBranch(this.branch);

  final String branch;

  @override
  Widget build(BuildContext context) {
    final color = themeColors['descriptionForeground'];
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Codicons.gitBranch, size: 12, color: color),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              branch,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
