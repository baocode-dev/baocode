// The Git log: Source Control as a whole page rather than a side bar view.
// Above, the filters (repository, branches, message, user, date) and the
// repository's actions; on the left, the history as a table (its lanes and
// references, date, author and hash), the local changes its first row; on
// the right, the row's details: a commit's message, author, parents,
// references and files, or the local changes' commit box and groups (the
// Source Control view's, see ide_scm_view.dart). A file opens its changes
// in the table's place, which steps to the next and the previous one.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:bao_editor/monaco/flutter/diff_editor_model.dart'
    show DiffHighlight;

import '../../base/give_way_row.dart';
import '../../base/smooth_scroll.dart';
import '../../base/shown_when_ready.dart';
import '../../chat/composer/composer_files.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../file_service.dart';
import '../ide_button.dart';
import '../ide_code_diff.dart';
import '../ide_diff_options.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_modern_ui.dart';
import '../ide_notifications.dart';
import '../ide_spinning.dart';
import 'git_branch_actions.dart';
import 'commit_message.dart';
import 'git_branch_tree.dart';
import 'ide_git_branch_popup.dart';
import 'git_change_editor.dart';
import 'git_checkout.dart' show ideSanitizeBranchName;
import 'git_graph_painter.dart';
import 'git_model.dart';
import 'git_partial.dart';
import 'git_repository.dart';
import 'git_service.dart';
import 'ide_git_list_tree_switch.dart';
import 'ide_git_rebase_dialog.dart';
import 'ide_git_ref_labels.dart';
import 'ide_scm_view.dart';
import 'scm_host.dart';
import 'scm_tree.dart';

part 'ide_git_log_branches.dart';

/// The id of the log's first row, the local changes.
const ideGitWorkingTreeId = 'scm-log-working-tree';

/// Which commits stand out: none, or the user's own (in bold).
enum IdeGitLogHighlight { none, mine }

/// A file's changes the log shows in its table's place: [original] against
/// [modified], [path] on the right; its sides named [originalLabel] and
/// [modifiedLabel] (the commits, `HEAD`, the working tree).
class IdeGitDiffFile {
  const IdeGitDiffFile({
    required this.path,
    required this.original,
    required this.modified,
    this.status,
    this.originalLabel = '',
    this.modifiedLabel = '',
    this.commitId,
    this.onOpenInEditor,
    this.write,
    this.checks,
    this.agent,
  });

  final String path;
  final IdeGitStatus? status;
  final Future<String> Function() original;
  final Future<String> Function() modified;
  final String originalLabel;
  final String modifiedLabel;

  /// The commit whose file it is; null for a local change.
  final String? commitId;

  /// Opens it in the editor, where it can be edited; not offered when null.
  final VoidCallback? onOpenInEditor;

  /// Writes its modified side, the file, once edited in the diff; read
  /// only when null.
  final Future<void> Function(String text)? write;

  /// A check box by each change, to leave it out of a commit; none when
  /// null.
  final IdeDiffChecks? checks;

  /// The agent's change in the file, its parts marked.
  final IdeDiffAgentMarks? agent;
}

/// The files a diff steps through, [index] the one shown; [focus]: it
/// takes the keyboard (not from a list the keys still walk); [start]:
/// where in the file it opens (its last change, stepped back into).
class IdeGitLogDiff {
  IdeGitLogDiff(
    this.files,
    this.index, {
    this.focus = true,
    this.start = IdeDiffStart.first,
  });

  final List<IdeGitDiffFile> files;
  final int index;
  final bool focus;
  final IdeDiffStart start;

  IdeGitDiffFile get file => files[index];
}

/// Which of the repository's worktrees the log shows, and where the agent
/// works ([agentPath], a file or folder in one of them): the side panel's
/// changes follow the agent ([following]) until another is picked
/// ([onSelect] with its path; null to follow it again). Without
/// [onSelect], the worktrees are only listed (the IDE shows its folder's).
class IdeGitWorktreeChoice {
  const IdeGitWorktreeChoice({
    this.agentPath,
    this.following = true,
    this.onSelect,
  });

  final String? agentPath;
  final bool following;
  final ValueChanged<String?>? onSelect;
}

/// What the log keeps while another view shows: the row selected, the
/// diff open, the panes' sizes, how files list, and each commit's files,
/// line counts and branches once read.
class IdeGitLogController extends ChangeNotifier {
  IdeGitLogController({IdeGitFavoriteBranches? favoriteBranches})
    : favoriteBranches = favoriteBranches ?? IdeGitFavoriteBranches() {
    this.favoriteBranches.addListener(notifyListeners);
  }

  final FocusNode focusNode = FocusNode(debugLabel: 'git log');
  final FocusNode searchFocus = FocusNode(debugLabel: 'git log search');
  final ScrollController scroll = SmoothScrollController();
  final TextEditingController search = TextEditingController();
  final TextEditingController fileFilter = TextEditingController();

  String? _selected;

  /// The row selected: a commit's id, or [ideGitWorkingTreeId]; the
  /// local changes' until one is picked.
  String? get selected => _selected;
  set selected(String? id) {
    if (id == _selected && _more.isEmpty) return;
    _selected = id;
    _more.clear();
    // Another row's details: the changes of the one before go.
    _diff = null;
    notifyListeners();
  }

  final Set<String> _more = {};

  /// The commits selected with [selected] (Cmd/Ctrl- or Shift-clicked).
  Set<String> get moreSelected => _more;

  /// Whether [id]'s row is selected.
  bool isSelected(String id) => id == _selected || _more.contains(id);

  /// [selected] with [more] selected too.
  void selectMany(String selected, Iterable<String> more) {
    _selected = selected;
    _more
      ..clear()
      ..addAll(more.where((id) => id != selected));
    _diff = null;
    notifyListeners();
  }

  IdeGitLogDiff? _diff;
  IdeGitLogDiff? get diff => _diff;

  /// The row [reveal] asked to be scrolled to, until the log takes it.
  String? _reveal;

  String? _editingMessage;

  /// The commit whose message is edited in its details (Edit Commit
  /// Message), if any.
  String? get editingMessage => _editingMessage;
  set editingMessage(String? id) {
    if (id == _editingMessage) return;
    _editingMessage = id;
    notifyListeners();
  }

  /// Selects [id]'s row and has the log scroll to it, where it is loaded
  /// (a commit pressed in an editor's annotations).
  void reveal(String id) {
    _reveal = id;
    _diff = null;
    if (id == _selected) {
      notifyListeners();
    } else {
      selected = id;
    }
  }

  /// [reveal]'s row, once.
  String? takeReveal() {
    final id = _reveal;
    _reveal = null;
    return id;
  }

  /// Shows [files]' [index]th in the table's place; with [focus], it takes
  /// the keyboard.
  void showDiff(List<IdeGitDiffFile> files, int index, {bool focus = true}) {
    if (files.isEmpty) return;
    _diff = IdeGitLogDiff(
      files,
      index.clamp(0, files.length - 1),
      focus: focus,
    );
    notifyListeners();
  }

  /// The next file's changes ([delta] 1), or the previous one's (-1).
  /// The file [delta] on; [start], where in it (F7 past a file's last
  /// change: the next's first; Shift+F7 past its first: the previous's
  /// last).
  void stepDiff(int delta, {IdeDiffStart start = IdeDiffStart.first}) =>
      showDiffAt((_diff?.index ?? 0) + delta, start: start);

  /// The file at [index] of those the diff steps through.
  void showDiffAt(int index, {IdeDiffStart start = IdeDiffStart.first}) {
    final diff = _diff;
    if (diff == null || index < 0 || index >= diff.files.length) return;
    _diff = IdeGitLogDiff(diff.files, index, focus: diff.focus, start: start);
    notifyListeners();
  }

  void closeDiff() {
    if (_diff == null) return;
    _diff = null;
    notifyListeners();
  }

  /// The details' width beside the table, and their height under it where
  /// the page is narrow (half of it until dragged).
  double detailsWidth = 380;
  double? detailsHeight;

  static const minDetails = 220.0;

  void resizeDetails({double? width, double? height}) {
    if (width != null) detailsWidth = math.max(minDetails, width);
    if (height != null) detailsHeight = math.max(120, height);
    notifyListeners();
  }

  bool _filesAsTree = false;
  bool get filesAsTree => _filesAsTree;
  set filesAsTree(bool value) {
    if (value == _filesAsTree) return;
    _filesAsTree = value;
    notifyListeners();
  }

  /// Each file's added and deleted lines beside it.
  bool _sizesShown = false;
  bool get sizesShown => _sizesShown;
  set sizesShown(bool value) {
    if (value == _sizesShown) return;
    _sizesShown = value;
    notifyListeners();
  }

  /// The branches that have the commit selected, under its references:
  /// shown until hidden, for every commit.
  bool _branchesShown = true;
  bool get branchesShown => _branchesShown;
  set branchesShown(bool value) {
    if (value == _branchesShown) return;
    _branchesShown = value;
    notifyListeners();
  }

  IdeGitLogHighlight _highlight = IdeGitLogHighlight.none;
  IdeGitLogHighlight get highlight => _highlight;
  set highlight(IdeGitLogHighlight value) {
    if (value == _highlight) return;
    _highlight = value;
    notifyListeners();
  }

  /// The files' filter changed: the files shown are others.
  void fileFilterChanged() => notifyListeners();

  /// The paths the log was last filtered by, the latest first.
  final List<String> recentPaths = [];

  /// The branch tree beside the log, where it is wide enough.
  bool _branchTreeShown = true;
  bool get branchTreeShown => _branchTreeShown;
  set branchTreeShown(bool value) {
    if (value == _branchTreeShown) return;
    _branchTreeShown = value;
    notifyListeners();
  }

  /// The branch tree's width.
  double branchTreeWidth = 220;

  void resizeBranchTree(double width) {
    branchTreeWidth = width.clamp(140, 480);
    notifyListeners();
  }

  /// What the branch tree is narrowed to.
  final TextEditingController branchFilter = TextEditingController();

  void branchFilterChanged() => notifyListeners();

  /// The branch tree's groups and folders folded, by key.
  final Set<String> foldedBranches = {...ideGitBranchTreeFolded};

  void toggleBranchFolder(String key) {
    if (!foldedBranches.remove(key)) foldedBranches.add(key);
    notifyListeners();
  }

  /// The branch tree's row selected, by key.
  String? _branchSelected;
  String? get branchSelected => _branchSelected;
  set branchSelected(String? key) {
    if (key == _branchSelected) return;
    _branchSelected = key;
    notifyListeners();
  }

  /// The favorite refs of each repository: first in the branch tree,
  /// starred.
  final IdeGitFavoriteBranches favoriteBranches;

  bool isFavorite(IdeGitRepository git, String ref) =>
      favoriteBranches.of(git.service.root).contains(ref);

  void toggleFavorite(IdeGitRepository git, String ref) =>
      favoriteBranches.toggle(git.service.root, ref);

  void rememberPath(String path) {
    recentPaths
      ..remove(path)
      ..insert(0, path);
    if (recentPaths.length > 6) recentPaths.removeLast();
  }

  /// The tree's folders closed, by path.
  final Set<String> collapsedFolders = {};

  void toggleFolder(String path) {
    if (!collapsedFolders.remove(path)) collapsedFolders.add(path);
    notifyListeners();
  }

  final Map<String, Future<List<IdeGitCommitChange>>> _changes = {};
  final Map<String, Future<Map<String, ({int? added, int? deleted})>>> _stats =
      {};
  final Map<String, Future<List<IdeGitRef>>> _branches = {};

  /// [id]'s files, read once.
  Future<List<IdeGitCommitChange>> changesOf(IdeGitRepository git, String id) =>
      _changes[id] ??= git.commitChanges(id);

  /// [id]'s lines added and deleted by file, read once; none where Git
  /// could not tell.
  Future<Map<String, ({int? added, int? deleted})>> statsOf(
    IdeGitRepository git,
    String id,
  ) => _stats[id] ??= git
      .commitStats(id)
      .catchError((Object _) => const <String, ({int? added, int? deleted})>{});

  /// The branches that have [id], read once.
  Future<List<IdeGitRef>> branchesOf(IdeGitRepository git, String id) =>
      _branches[id] ??= git.branchesContaining(id);

  /// Forgets the branches read: after a fetch or a commit, they changed.
  void forgetBranches() => _branches.clear();

  @override
  void dispose() {
    focusNode.dispose();
    searchFocus.dispose();
    scroll.dispose();
    search.dispose();
    fileFilter.dispose();
    branchFilter.dispose();
    favoriteBranches.removeListener(notifyListeners);
    super.dispose();
  }
}

/// The files [revision] (a commit, a branch) and the working tree differ
/// in, its side ([label]) against the file's ([workingTree]); none where
/// they do not.
Future<List<IdeGitDiffFile>> ideGitWorkingTreeDiff(
  IdeGitRepository git,
  IdeFileService files,
  String revision,
  String label,
  String workingTree,
) async {
  final changes = await git.service.changesSince(revision);
  Future<String> show(String path) =>
      git.service.show(revision, path).catchError((Object _) => '');
  return [
    for (final change in changes)
      IdeGitDiffFile(
        path: change.path,
        status: ideCommitChangeStatus(change.status),
        original: () => change.status == 'A'
            ? Future.value('')
            : show(change.originalPath ?? change.path),
        modified: () => change.status == 'D'
            ? Future.value('')
            : files.read(change.path).catchError((Object _) => ''),
        originalLabel: label,
        modifiedLabel: workingTree,
      ),
  ];
}

/// The files the revisions [from] and [to] differ in, [from]'s side
/// against [to]'s, each with its label.
Future<List<IdeGitDiffFile>> ideGitRevisionsDiff(
  IdeGitRepository git,
  (String id, String label) from,
  (String id, String label) to,
) async {
  final changes = await git.service.changesSince(from.$1, other: to.$1);
  Future<String> show(String ref, String path) =>
      git.service.show(ref, path).catchError((Object _) => '');
  return [
    for (final change in changes)
      IdeGitDiffFile(
        path: change.path,
        status: ideCommitChangeStatus(change.status),
        original: () => change.status == 'A'
            ? Future.value('')
            : show(from.$1, change.originalPath ?? change.path),
        modified: () =>
            change.status == 'D' ? Future.value('') : show(to.$1, change.path),
        originalLabel: from.$2,
        modifiedLabel: to.$2,
      ),
  ];
}

/// The status of a commit's change by its letter (`git show
/// --name-status`).
IdeGitStatus ideCommitChangeStatus(String letter) => switch (letter) {
  'A' => IdeGitStatus.indexAdded,
  'D' => IdeGitStatus.indexDeleted,
  'R' => IdeGitStatus.indexRenamed,
  'C' => IdeGitStatus.indexCopied,
  'T' => IdeGitStatus.typeChanged,
  _ => IdeGitStatus.indexModified,
};

/// [commit]'s [change] as the log shows it: its first parent's text
/// against its own.
IdeGitDiffFile ideCommitDiffFile(
  IdeGitRepository git,
  IdeGitCommit commit,
  IdeGitCommitChange change,
) {
  final parent = commit.parentIds.firstOrNull;
  Future<String> show(String ref, String path) =>
      git.service.show(ref, path).catchError((Object _) => '');
  return IdeGitDiffFile(
    path: change.path,
    status: ideCommitChangeStatus(change.status),
    original: () => parent == null || change.status == 'A'
        ? Future.value('')
        : show(parent, change.originalPath ?? change.path),
    modified: () =>
        change.status == 'D' ? Future.value('') : show(commit.id, change.path),
    originalLabel: parent == null ? '' : _short(parent),
    modifiedLabel: commit.shortId,
    commitId: commit.id,
  );
}

/// A local change as the log shows it: its sides as Source Control's diff
/// editor compares them (see git_change_editor.dart), its file read with
/// [files].
IdeGitDiffFile ideLocalDiffFile(
  IdeGitRepository git,
  IdeGitState state,
  IdeGitResource resource,
  Future<String> Function(String path) read,
  AppLocalizations l10n, {
  VoidCallback? onOpenInEditor,
  Future<void> Function(String path, String text, {String? expectedText})?
  write,
  IdeGitHunkSelection? hunks,
  IdeDiffAgentMarks? agent,
}) {
  // With check boxes, as a commit of it takes it: HEAD against the file.
  final partial = hunks != null && ideGitPartialCommittable(resource);
  final changeEditor = IdeGitChangeEditor.of(
    resource,
    staged: state.group(IdeGitGroup.staged),
    l10n: l10n,
  );
  final editor = partial
      ? IdeGitChangeEditor(
          label: changeEditor.label,
          left: IdeGitSide(resource.path, 'HEAD'),
          right: IdeGitSide(resource.path),
        )
      : changeEditor;
  Future<String> Function() side(IdeGitSide? side) => switch (side) {
    null => () => Future.value(''),
    IdeGitSide(isFile: true, :final path) => () => read(
      path,
    ).catchError((Object _) => ''),
    IdeGitSide(:final ref, :final path) =>
      () => git.service.show(ref!, path).catchError((Object _) => ''),
  };
  String label(IdeGitSide? side) => switch (side?.ref) {
    null when side == null => '',
    null => l10n.gitChangeWorkingTree,
    '' => l10n.gitChangeIndex,
    final ref => ref,
  };
  // The file's text as last read or written: what a write expects to find,
  // so as not to write over what changed it meanwhile.
  String? known;
  var writing = Future<void>.value();
  final right = editor.right;
  return IdeGitDiffFile(
    path: resource.path,
    status: resource.status,
    original: side(editor.left),
    modified: right != null && right.isFile
        ? () async => known = await side(right)()
        : side(right),
    originalLabel: label(editor.left),
    modifiedLabel: label(editor.right),
    onOpenInEditor: onOpenInEditor,
    // The file itself on the right: edited in the diff, as in the editor.
    write: switch ((right, write)) {
      // One after another: each expects what the one before wrote.
      (IdeGitSide(isFile: true, :final path), final write?) =>
        (text) => writing = writing.then((_) async {
          try {
            await write(path, text, expectedText: known);
            known = text;
          } on Object {
            // Told by [write]; the next expects what was there.
          }
        }),
      _ => null,
    },
    checks: partial ? hunks.checksOf(resource.path) : null,
    // Its parts the agent made, where the file is on the right.
    agent: right != null && right.isFile ? agent : null,
  );
}

String _short(String id) => id.length > 7 ? id.substring(0, 7) : id;

class IdeGitLogView extends StatefulWidget {
  const IdeGitLogView({
    super.key,
    required this.host,
    required this.session,
    required this.changes,
    required this.notifications,
    this.onOpen,
    this.onOpenDiff,
    this.overlay,
    this.overlayTabs,
    this.onCloseOverlay,
    this.onAddToChat,
    this.worktrees = const IdeGitWorktreeChoice(),
    this.background,
    this.border,
    this.ai,
    this.onAsk,
    this.onFixup,
  });

  /// Commits the local changes checked into a commit (Fixup); not offered
  /// when null.
  final Future<void> Function(IdeGitRepository git, IdeGitCommit commit)?
  onFixup;

  /// The model that cleans up a branch in an interactive rebase; not
  /// offered when null.
  final IdeCommitMessageModel? ai;

  /// Puts a request about commits in the chat's composer (Ask AI); not
  /// offered when null.
  final ValueChanged<String>? onAsk;

  /// The IDE's workspace, or the chat window's side panel's project.
  final IdeScmHost host;

  /// The session of the repository shown ([IdeScmHost.git]): its log's
  /// state ([IdeScmSession.log]).
  final IdeScmSession session;

  /// The local changes' details: the Source Control view, its CHANGES
  /// alone. Kept while a commit shows, for its commands.
  final Widget changes;
  final IdeNotifications notifications;

  /// Opens a file in the editor; not offered when null.
  final ValueChanged<String>? onOpen;

  /// Shows a commit's file's changes where the host shows changes (the
  /// side panel's tabs); in the table's place when null.
  final ValueChanged<IdeGitDiffFile>? onOpenDiff;

  /// What shows in the table's place while it is there (the side panel's
  /// change in front), under [overlayTabs] (its tabs) and a way back to
  /// the table ([onCloseOverlay]).
  final Widget? overlay;
  final Widget? overlayTabs;
  final VoidCallback? onCloseOverlay;

  /// Puts files in the chat's composer; not offered when null.
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  /// The worktree shown, and the agent's.
  final IdeGitWorktreeChoice worktrees;

  /// Behind it, and the lines between its parts; the editor's and the
  /// panel's when null.
  final Color? background;
  final Color? border;

  /// Below this width, the details go under the table.
  static const wideWidth = 760.0;

  static const rowHeight = 26.0;

  @override
  State<IdeGitLogView> createState() => IdeGitLogViewState();
}

class IdeGitLogViewState extends State<IdeGitLogView> {
  IdeGitLogController get _log => widget.session.log;
  IdeGitRepository? get _git => widget.host.git;

  Color get _background =>
      widget.background ?? themeColors['editor.background'];
  Color get _border =>
      widget.border ?? themeColors.get('panel.border') ?? AppColors.partBorder;

  Timer? _searchDebounce;

  /// The user's email (`user.email`), for My Commits and the user filter's
  /// Me; null until read, or where there is none.
  String? _userEmail;
  IdeGitRepository? _emailOf;

  @override
  void initState() {
    super.initState();
    _readEmail();
  }

  @override
  void didUpdateWidget(IdeGitLogView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(_emailOf, _git)) _readEmail();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _readEmail() {
    final git = _emailOf = _git;
    _userEmail = null;
    if (git == null) return;
    unawaited(
      git.userEmail.then((email) {
        if (mounted && identical(git, _git)) setState(() => _userEmail = email);
      }),
    );
  }

  void _report(Object error) {
    if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
  }

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      _report(error);
    } finally {
      _log.forgetBranches();
    }
  }

  @override
  Widget build(BuildContext context) {
    final git = _git;
    return ColoredBox(
      color: _background,
      child: git == null
          ? _overlay() ?? widget.changes
          : ListenableBuilder(
              listenable: Listenable.merge([
                git,
                _log,
                for (final (_, repo) in widget.host.repositories) repo,
              ]),
              builder: (context, _) {
                if (_log.takeReveal() case final id?) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _select(id, reveal: true);
                  });
                }
                return git.state == null
                    // Not a repository (yet): Source Control's welcome, but
                    // for a change opened.
                    ? _overlay() ?? widget.changes
                    : _page(git, git.state!);
              },
            ),
    );
  }

  /// [IdeGitLogView.overlay] under its tabs and the way back; null when
  /// there is none.
  Widget? _overlay() {
    final overlay = widget.overlay;
    if (overlay == null) return null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const SizedBox(width: 4),
            IdeActionButton(
              icon: Codicons.arrowLeft,
              tooltip: context.l10n.gitLogBackToLog,
              onPressed: widget.onCloseOverlay,
            ),
            const SizedBox(width: 4),
            Expanded(child: widget.overlayTabs ?? const SizedBox.shrink()),
          ],
        ),
        Expanded(child: overlay),
      ],
    );
  }

  /// HEAD's commit when the page was last built: when it moves (a commit,
  /// a checkout, a pull), the branches that have a commit change.
  String? _headSeen;

  Widget _page(IdeGitRepository git, IdeGitState state) {
    String? head;
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.kind == IdeGraphRowKind.head) head = row.commit.id;
    }
    if (head != _headSeen) {
      _headSeen = head;
      _log.forgetBranches();
    }
    final worktrees = [
      for (final worktree in git.worktrees)
        if (!worktree.bare) worktree,
    ];
    final paths = git.service.pathContext;
    _worktrees = worktrees;
    _shownWorktree = ideWorktreeOf(git.service.root, worktrees, paths);
    _agentWorktree = switch (widget.worktrees.agentPath) {
      final path? => ideWorktreeOf(path, worktrees, paths),
      null => null,
    };
    return _layout(git, state);
  }

  /// The repository's worktrees (bare ones aside), the one shown and the
  /// agent's, as of the last build.
  List<IdeGitWorktree> _worktrees = const [];
  IdeGitWorktree? _shownWorktree;
  IdeGitWorktree? _agentWorktree;

  /// A worktree's name: its folder's.
  String _worktreeName(IdeGitRepository git, IdeGitWorktree worktree) =>
      git.service.pathContext.basename(worktree.path);

  Widget _layout(IdeGitRepository git, IdeGitState state) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _toolbar(git, state),
      Container(height: 1, color: _border),
      if (git.busy)
        SizedBox(
          height: 2,
          child: LinearProgressIndicator(
            minHeight: 2,
            backgroundColor: Colors.transparent,
            color: themeColors['progressBar.background'],
          ),
        ),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= IdeGitLogView.wideWidth;
            final main = _main(git, state);
            final details = _details(git, state);
            if (wide) {
              final tree = _branchTreeFits(constraints.maxWidth)
                  ? math.min(_log.branchTreeWidth, constraints.maxWidth * .3)
                  : null;
              final width = math.min(
                _log.detailsWidth,
                constraints.maxWidth - 360 - (tree ?? 0),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (tree != null) ...[
                    SizedBox(width: tree, child: _branchPane(git)),
                    _Sash(
                      vertical: false,
                      color: _border,
                      size: tree,
                      onResize: _log.resizeBranchTree,
                    ),
                  ],
                  Expanded(child: main),
                  _Sash(
                    vertical: false,
                    color: _border,
                    size: width,
                    after: true,
                    onResize: (width) => _log.resizeDetails(width: width),
                  ),
                  SizedBox(width: width, child: details),
                ],
              );
            }
            final height = math.min(
              _log.detailsHeight ?? constraints.maxHeight / 2,
              constraints.maxHeight * .75,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: main),
                _Sash(
                  vertical: true,
                  color: _border,
                  size: height,
                  after: true,
                  onResize: (height) => _log.resizeDetails(height: height),
                ),
                SizedBox(height: height, child: details),
              ],
            );
          },
        ),
      ),
    ],
  );

  /// Whether the branch tree shows beside the log [width] wide: where it
  /// is wanted and leaves the log room.
  bool _branchTreeFits(double width) =>
      _log.branchTreeShown && width >= _branchTreeWidth;

  /// Below this width, no branch tree.
  static const _branchTreeWidth = 1000.0;

  // --- Toolbar -------------------------------------------------------------

  Widget _toolbar(IdeGitRepository git, IdeGitState state) => LayoutBuilder(
    builder: (context, constraints) {
      final compact = constraints.maxWidth < _compactToolbar;
      final filters = _filters(git);
      if (!compact) {
        return SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                if (constraints.maxWidth >= _branchTreeWidth) ...[
                  IdeActionButton(
                    icon: _log.branchTreeShown
                        ? Codicons.layoutSidebarLeft
                        : Codicons.layoutSidebarLeftOff,
                    tooltip: _log.branchTreeShown
                        ? context.l10n.gitHideBranches
                        : context.l10n.gitShowBranches,
                    checked: _log.branchTreeShown,
                    onPressed: () =>
                        _log.branchTreeShown = !_log.branchTreeShown,
                  ),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ...filters.take(2),
                        SizedBox(width: 240, child: _search(git)),
                        const SizedBox(width: 6),
                        ...filters.skip(2),
                      ],
                    ),
                  ),
                ),
                _clearButton(git),
                const SizedBox(width: 8),
                ..._actions(git, state, compact: false),
              ],
            ),
          ),
        );
      }
      // Narrow (the side panel): the search and the actions, then the
      // filters under them.
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(child: _search(git)),
                  const SizedBox(width: 4),
                  ..._actions(git, state, compact: true),
                ],
              ),
            ),
            SizedBox(
              height: 28,
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: filters),
                    ),
                  ),
                  _clearButton(git),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );

  /// The branch's button: where the branch popup opens.
  final GlobalKey _branchButton = GlobalKey();

  /// The branch popup, under the branch's button.
  void _showBranches(IdeGitRepository git) {
    final box = _branchButton.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final host = _LogBranchHost(this);
    unawaited(
      showIdeGitBranchPopup(
        context,
        git: git,
        anchor: box.localToGlobal(Offset.zero) & box.size,
        host: host,
        actions: IdeGitBranchActions(
          context,
          git,
          host,
        ).repositoryActions(onCommit: showLocalChanges),
      ),
    );
  }

  /// Below this width, the toolbar takes two rows and the repository's
  /// actions go in its menu.
  static const _compactToolbar = 860.0;

  /// The message's search: typed, it filters the log a moment later;
  /// Escape clears it, Down goes to the table.
  Widget _search(IdeGitRepository git) {
    final l10n = context.l10n;
    void apply(String text) {
      _searchDebounce?.cancel();
      git.graphFilter = git.graphFilter.copyWith(text: text);
    }

    return IdeInputBox(
      controller: _log.search,
      focusNode: _log.searchFocus,
      placeholder: l10n.gitLogSearch,
      onChanged: (text) {
        _searchDebounce?.cancel();
        _searchDebounce = Timer(
          const Duration(milliseconds: 300),
          () => apply(text),
        );
        // The clear button comes and goes.
        setState(() {});
      },
      onSubmitted: apply,
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_log.search.text.isEmpty) {
            _log.focusNode.requestFocus();
          } else {
            _log.search.clear();
            apply('');
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowDown): () {
          apply(_log.search.text);
          _log.focusNode.requestFocus();
        },
      },
      toggles: [
        if (_log.search.text.isNotEmpty)
          IdeActionButton(
            icon: Codicons.close,
            tooltip: l10n.gitLogClearSearch,
            size: 18,
            iconSize: 14,
            onPressed: () {
              _log.search.clear();
              apply('');
            },
          ),
      ],
    );
  }

  /// The repository (where there are several) and branches first, then
  /// the user, the date, what stands out, and Clear Filters.
  List<Widget> _filters(IdeGitRepository git) {
    final l10n = context.l10n;
    final filter = git.graphFilter;
    final repositories = widget.host.repositories;
    return [
      if (repositories.length > 1)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _DropButton(
            icon: Codicons.repo,
            // The folder's name, though a worktree of its shows.
            label: p.basename(
              repositories
                      .where((repository) => identical(repository.$2, git))
                      .firstOrNull
                      ?.$1 ??
                  git.service.root,
            ),
            tooltip: l10n.gitLogRepository,
            entries: () => [
              for (final (folder, repo) in repositories)
                IdeMenuAction(
                  switch (repo.state?.count) {
                    final count? when count > 0 =>
                      '${p.basename(folder)}  ($count)',
                    _ => p.basename(folder),
                  },
                  checked: identical(repo, git),
                  onSelected: () => widget.host.selectRepository(repo),
                ),
            ],
          ),
        )
      else
        const SizedBox.shrink(),
      if (_worktrees.length > 1)
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: _worktreeButton(git),
        ),
      Padding(
        padding: const EdgeInsets.only(right: 6),
        child: _DropButton(
          icon: Codicons.gitBranch,
          label: switch (git.graphBranch) {
            null => l10n.scmGraphAllBranches,
            ideGraphCurrentBranch => l10n.scmGraphCurrentBranch,
            final graph => switch (ideGraphRangeOf(graph)) {
              (:final from, :final to) =>
                '${_refLabel(from)}..${_refLabel(to)}',
              null => _refLabel(graph),
            },
          },
          tooltip: l10n.scmGraphBranches,
          active: git.graphBranch != null,
          entries: () => _branchEntries(git),
        ),
      ),
      _DropButton(
        icon: Codicons.file,
        label: _pathsLabel(git),
        tooltip: l10n.gitLogPaths,
        active: filter.paths.isNotEmpty || filter.lines != null,
        entries: () => _pathEntries(git),
      ),
      _DropButton(
        icon: Codicons.person,
        label: switch (filter.author) {
          null => l10n.gitLogUser,
          final author when author == _userEmail => l10n.gitLogMe,
          final author => author,
        },
        tooltip: l10n.gitLogUser,
        active: filter.author != null,
        entries: () => _userEntries(git),
      ),
      _DropButton(
        icon: Codicons.calendar,
        label: switch (_sinceDays(filter.since)) {
          null => l10n.gitLogDate,
          final days => _sinceLabel(days),
        },
        tooltip: l10n.gitLogDate,
        active: filter.since != null,
        entries: () => _dateEntries(git),
      ),
      _DropButton(
        icon: Codicons.eye,
        label: _log.highlight == IdeGitLogHighlight.mine
            ? l10n.gitLogHighlightMine
            : l10n.gitLogHighlight,
        tooltip: l10n.gitLogHighlight,
        active: _log.highlight != IdeGitLogHighlight.none,
        entries: () => [
          IdeMenuAction(
            l10n.gitLogHighlightNone,
            checked: _log.highlight == IdeGitLogHighlight.none,
            onSelected: () => _log.highlight = IdeGitLogHighlight.none,
          ),
          IdeMenuAction(
            l10n.gitLogHighlightMine,
            enabled: _userEmail != null,
            checked: _log.highlight == IdeGitLogHighlight.mine,
            onSelected: () => _log.highlight = IdeGitLogHighlight.mine,
          ),
        ],
      ),
    ];
  }

  /// Clear Filters, kept in sight beside the filters (not scrolled away
  /// with them); none while nothing is filtered.
  Widget _clearButton(IdeGitRepository git) => _filtered(git)
      ? IdeActionButton(
          icon: Codicons.clearAll,
          tooltip: context.l10n.gitLogClearFilters,
          onPressed: () => _clearFilters(git),
        )
      : const SizedBox.shrink();

  /// The worktree shown, ✦ where the agent works; its menu lists them all,
  /// each with its branch, to show another's changes.
  Widget _worktreeButton(IdeGitRepository git) {
    final l10n = context.l10n;
    final choice = widget.worktrees;
    final shown = _shownWorktree;
    final agent = _agentWorktree;
    final select = choice.onSelect;
    final paths = git.service.pathContext;
    bool isShown(IdeGitWorktree worktree) =>
        shown != null && paths.equals(worktree.path, shown.path);
    String branchOf(IdeGitWorktree worktree) =>
        worktree.branch ?? _short(worktree.head ?? '');
    return _DropButton(
      icon: Codicons.worktree,
      label: shown == null ? l10n.gitLogWorktree : _worktreeName(git, shown),
      trailing: agent != null && shown != null && agent.path == shown.path
          ? Codicons.sparkle
          : null,
      tooltip: l10n.gitLogWorktreeOf(shown?.path ?? git.service.root),
      active: shown != null && !shown.main,
      entries: () => ideMenuGroups([
        // Where there is no agent to follow (the IDE's), not offered.
        if (select != null && (choice.agentPath != null || choice.following))
          [
            IdeMenuAction(
              l10n.gitLogFollowAgent,
              checked: choice.following,
              enabled: choice.agentPath != null,
              onSelected: () => select(null),
            ),
          ],
        [
          for (final worktree in _worktrees)
            IdeMenuAction(
              [
                _worktreeName(git, worktree),
                if (worktree.main) '(${l10n.gitLogMainWorktree})',
                if (worktree.prunable) '(${l10n.gitLogWorktreeMissing})',
                if (agent?.path == worktree.path) '✦ AI',
              ].join('  '),
              keybinding: branchOf(worktree),
              checked: isShown(worktree),
              enabled: select != null && !worktree.prunable,
              onSelected: () => select?.call(worktree.path),
            ),
        ],
      ]),
    );
  }

  /// Whether the log shows fewer commits than it could.
  static bool _filtered(IdeGitRepository git) =>
      git.graphFilter.filtered || git.graphBranch != null;

  void _clearFilters(IdeGitRepository git) {
    _searchDebounce?.cancel();
    _log.search.clear();
    git
      ..graphFilter = const IdeGitLogFilter()
      ..graphBranch = null;
  }

  /// The current branch (Checkout to…), and the repository's actions: on
  /// the toolbar, or ([compact]) in its menu.
  List<Widget> _actions(
    IdeGitRepository git,
    IdeGitState state, {
    required bool compact,
  }) {
    final l10n = context.l10n;
    final head = state.head;
    final pullLabel = head.behind > 0
        ? '${l10n.scmPull} (${head.behind})'
        : l10n.scmPull;
    final pushLabel = head.ahead > 0
        ? '${l10n.scmPush} (${head.ahead})'
        : l10n.scmPush;
    final sortLabel = git.graphDateOrder
        ? l10n.gitLogSortDate
        : l10n.gitLogSortTopo;
    void toggleSort() => git.graphDateOrder = !git.graphDateOrder;
    return [
      if (!head.unborn)
        KeyedSubtree(
          key: _branchButton,
          child: _DropButton(
            icon: Codicons.gitBranch,
            label: head.branch ?? _detachedLabel(git),
            tooltip: l10n.gitBranchesTitle,
            maxWidth: compact ? 110 : 180,
            onPressed: () => _showBranches(git),
          ),
        ),
      if (!compact) ...[
        IdeActionButton(
          icon: Codicons.repoFetch,
          tooltip: l10n.scmFetch,
          onPressed: () => unawaited(_run(git.fetch)),
        ),
        _Badged(
          count: head.behind,
          child: IdeActionButton(
            icon: Codicons.repoPull,
            tooltip: pullLabel,
            onPressed: () => unawaited(_run(git.pull)),
          ),
        ),
        _Badged(
          count: head.ahead,
          child: IdeActionButton(
            icon: Codicons.repoPush,
            tooltip: pushLabel,
            onPressed: () => unawaited(
              IdeGitBranchActions(context, git, _LogBranchHost(this)).push(),
            ),
          ),
        ),
        IdeActionButton(
          icon: git.graphDateOrder ? Codicons.calendar : Codicons.listOrdered,
          tooltip: sortLabel,
          onPressed: toggleSort,
        ),
      ],
      IdeMenuButton(
        icon: Codicons.ellipsis,
        tooltip: l10n.commonMoreActions,
        entries: () => ideMenuGroups([
          if (compact)
            [
              IdeMenuAction(
                l10n.scmFetch,
                onSelected: () => unawaited(_run(git.fetch)),
              ),
              IdeMenuAction(
                pullLabel,
                onSelected: () => unawaited(_run(git.pull)),
              ),
              IdeMenuAction(
                '$pushLabel…',
                onSelected: () => unawaited(
                  IdeGitBranchActions(
                    context,
                    git,
                    _LogBranchHost(this),
                  ).push(),
                ),
              ),
            ],
          [
            IdeMenuAction(
              l10n.scmGoToCurrent,
              onSelected: () => _goToCurrent(git),
            ),
            IdeMenuAction(
              l10n.commonRefresh,
              onSelected: () => unawaited(_run(git.refresh)),
            ),
            if (compact)
              IdeMenuAction(
                l10n.gitLogSortDate,
                checked: git.graphDateOrder,
                onSelected: toggleSort,
              ),
          ],
          [
            IdeMenuAction(
              l10n.scmFetchFromAllRemotes,
              onSelected: () => unawaited(_run(() => git.fetch())),
            ),
          ],
        ]),
      ),
    ];
  }

  /// Where HEAD is when it is on no branch: its commit.
  static String _detachedLabel(IdeGitRepository git) {
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.kind == IdeGraphRowKind.head) return row.commit.shortId;
    }
    return 'HEAD';
  }

  /// A ref's name as the branch filter shows it.
  static String _refLabel(String ref) {
    for (final prefix in const ['refs/heads/', 'refs/remotes/', 'refs/tags/']) {
      if (ref.startsWith(prefix)) return ref.substring(prefix.length);
    }
    return ref;
  }

  Future<List<IdeMenuEntry>> _branchEntries(IdeGitRepository git) async {
    final l10n = context.l10n;
    List<IdeGitRef> refs;
    try {
      refs = await git.refs();
    } catch (error) {
      _report(error);
      refs = const [];
    }
    IdeMenuAction pick(String label, String? value) => IdeMenuAction(
      label,
      checked: git.graphBranch == value,
      onSelected: () => git.graphBranch = value,
    );
    List<IdeMenuEntry> of(IdeGitRefKind kind) => [
      for (final ref in refs)
        if (ref.kind == kind && !ref.name.endsWith('/HEAD'))
          pick(ref.name, ref.id),
    ];
    final local = of(IdeGitRefKind.branch);
    final remote = of(IdeGitRefKind.remote);
    final tags = of(IdeGitRefKind.tag);
    final range = ideGraphRangeOf(git.graphBranch);
    return ideMenuGroups([
      [
        pick(l10n.scmGraphAllBranches, null),
        pick(l10n.scmGraphCurrentBranch, ideGraphCurrentBranch),
      ],
      // A comparison's two ways.
      if (range case (:final from, :final to))
        [
          pick(
            l10n.scmGraphRangeIn(_refLabel(to), _refLabel(from)),
            ideGraphRange(from, to),
          ),
          pick(
            l10n.scmGraphRangeIn(_refLabel(from), _refLabel(to)),
            ideGraphRange(to, from),
          ),
        ],
      [
        if (local.isNotEmpty)
          IdeMenuAction(l10n.gitLogLocalBranches, submenu: local),
        if (remote.isNotEmpty)
          IdeMenuAction(l10n.gitLogRemoteBranches, submenu: remote),
        if (tags.isNotEmpty) IdeMenuAction(l10n.gitLogTags, submenu: tags),
      ],
    ]);
  }

  /// [path] as the Paths filter names it: from the repository's folder.
  String _pathName(IdeGitRepository git, String path) {
    final paths = git.service.pathContext;
    final root = git.service.root;
    if (paths.equals(path, root)) return p.basename(path);
    return paths.isWithin(root, path)
        ? paths.relative(path, from: root).replaceAll(r'\', '/')
        : path;
  }

  String _linesLabel(IdeGitLogLines lines) => context.l10n.gitLogLinesOf(
    p.basename(lines.path),
    lines.start,
    lines.end,
  );

  String _pathsLabel(IdeGitRepository git) {
    final filter = git.graphFilter;
    if (filter.lines case final lines?) return _linesLabel(lines);
    return switch (filter.paths) {
      [] => context.l10n.gitLogPaths,
      [final path] => p.basename(path),
      final paths => context.l10n.gitLogPathCount(paths.length),
    };
  }

  /// All, the file in the editor or its folder, and those filtered by of
  /// late (the explorer's Show History too).
  List<IdeMenuEntry> _pathEntries(IdeGitRepository git) {
    final l10n = context.l10n;
    final filter = git.graphFilter;
    final paths = git.service.pathContext;
    final root = git.service.root;
    void pick(String? path) {
      if (path != null) _log.rememberPath(path);
      git.graphFilter = filter.copyWith(paths: [?path], lines: () => null);
    }

    bool only(String path) =>
        filter.lines == null &&
        filter.paths.length == 1 &&
        paths.equals(filter.paths.single, path);
    IdeMenuAction choice(String label, String path) =>
        IdeMenuAction(label, checked: only(path), onSelected: () => pick(path));
    final active = widget.host.activePath;
    final file = active != null && paths.isWithin(root, active) ? active : null;
    final folder = file == null ? null : paths.dirname(file);
    final offered = [?file, ?folder];
    return ideMenuGroups([
      [
        IdeMenuAction(
          l10n.gitLogAllPaths,
          checked: filter.paths.isEmpty && filter.lines == null,
          onSelected: () => pick(null),
        ),
        if (filter.lines case final lines?)
          IdeMenuAction(_linesLabel(lines), checked: true, onSelected: () {}),
      ],
      [
        if (file != null)
          choice(l10n.gitLogCurrentFile(_pathName(git, file)), file),
        if (folder != null)
          choice(l10n.gitLogCurrentFolder(_pathName(git, folder)), folder),
      ],
      [
        for (final path in _log.recentPaths)
          if (!offered.any((offer) => paths.equals(offer, path)))
            choice(_pathName(git, path), path),
      ],
    ]);
  }

  List<IdeMenuEntry> _userEntries(IdeGitRepository git) {
    final l10n = context.l10n;
    final filter = git.graphFilter;
    void pick(String? author) =>
        git.graphFilter = filter.copyWith(author: () => author);
    // The authors of the commits loaded, the most frequent first.
    final counts = <String, int>{};
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      final author = row.commit.author;
      if (author.isEmpty || row.commit.authorEmail.isEmpty) continue;
      counts[author] = (counts[author] ?? 0) + 1;
    }
    final authors = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    final email = _userEmail;
    return ideMenuGroups([
      [
        IdeMenuAction(
          l10n.gitLogAllUsers,
          checked: filter.author == null,
          onSelected: () => pick(null),
        ),
        if (email != null)
          IdeMenuAction(
            l10n.gitLogMe,
            checked: filter.author == email,
            onSelected: () => pick(email),
          ),
      ],
      [
        for (final author in authors.take(30))
          IdeMenuAction(
            author,
            checked: filter.author == author,
            onSelected: () => pick(author),
          ),
      ],
    ]);
  }

  static const _sinceChoices = [1, 7, 30, 365];

  /// The days [since] is before now, as one of [_sinceChoices] picked it.
  static int? _sinceDays(DateTime? since) {
    if (since == null) return null;
    final days = DateTime.now().difference(since).inHours / 24;
    return _sinceChoices.reduce(
      (a, b) => (a - days).abs() <= (b - days).abs() ? a : b,
    );
  }

  String _sinceLabel(int days) => switch (days) {
    1 => context.l10n.gitLogLastDay,
    7 => context.l10n.gitLogLastWeek,
    30 => context.l10n.gitLogLastMonth,
    _ => context.l10n.gitLogLastYear,
  };

  List<IdeMenuEntry> _dateEntries(IdeGitRepository git) {
    final filter = git.graphFilter;
    final current = _sinceDays(filter.since);
    return [
      IdeMenuAction(
        context.l10n.gitLogAnyDate,
        checked: current == null,
        onSelected: () => git.graphFilter = filter.copyWith(since: () => null),
      ),
      for (final days in _sinceChoices)
        IdeMenuAction(
          _sinceLabel(days),
          checked: current == days,
          onSelected: () => git.graphFilter = filter.copyWith(
            since: () => DateTime.now().subtract(Duration(days: days)),
          ),
        ),
    ];
  }

  // --- Table ---------------------------------------------------------------

  /// The table's rows: the local changes, then the commits.
  List<String> _ids(IdeGitRepository git) => [
    ideGitWorkingTreeId,
    for (final row in git.graph ?? const <IdeGraphRow>[]) row.commit.id,
  ];

  /// The row selected: the one picked, else the local changes.
  String _selectedOf(IdeGitRepository git, IdeGitState state) =>
      _log.selected ?? ideGitWorkingTreeId;

  /// Selects [id] alone, or with [keep] leaves the selection as it is;
  /// scrolled to with [reveal].
  void _select(String id, {bool reveal = false, bool keep = false}) {
    if (!keep) _log.selected = id;
    if (!reveal) return;
    final git = _git;
    if (git == null) return;
    final index = _ids(git).indexOf(id);
    if (index >= 0) {
      ideRevealRow(_log.scroll, index, rowHeight: IdeGitLogView.rowHeight);
    }
  }

  /// The row selection grows from with Shift.
  String? _anchor;

  /// A commit's row clicked: it alone, or with Cmd/Ctrl added to or taken
  /// from those selected, or with Shift those from the last clicked to it.
  void _clicked(IdeGitRepository git, String id, {bool synthetic = false}) {
    final keys = HardwareKeyboard.instance;
    final toggle = defaultTargetPlatform == TargetPlatform.macOS
        ? keys.isMetaPressed
        : keys.isControlPressed;
    final selected = _log.selected;
    final commits = selected != null && selected != ideGitWorkingTreeId;
    if (!synthetic && commits && toggle) {
      final all = {selected, ..._log.moreSelected};
      if (!all.remove(id)) {
        _log.selectMany(id, all);
        _anchor = id;
      } else if (all.isNotEmpty) {
        _log.selectMany(id == selected ? all.first : selected, all);
      }
      return;
    }
    if (!synthetic && commits && keys.isShiftPressed) {
      final ids = [
        for (final row in git.graph ?? const <IdeGraphRow>[])
          if (!_isSynthetic(row.commit.id)) row.commit.id,
      ];
      final from = ids.indexOf(_anchor ?? selected);
      final to = ids.indexOf(id);
      if (from >= 0 && to >= 0) {
        final range = ids.sublist(math.min(from, to), math.max(from, to) + 1);
        _log.selectMany(id, range);
        return;
      }
    }
    _anchor = id;
    _select(id);
  }

  static bool _isSynthetic(String id) =>
      id == ideIncomingChangesId || id == ideOutgoingChangesId;

  /// The commits selected, in the graph's order (newest first); one or
  /// none without others.
  List<IdeGitCommit> _selectedCommits(IdeGitRepository git) => [
    for (final row in git.graph ?? const <IdeGraphRow>[])
      if (_log.isSelected(row.commit.id) && !_isSynthetic(row.commit.id))
        row.commit,
  ];

  void _goToCurrent(IdeGitRepository git) {
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.kind == IdeGraphRowKind.head) {
        _log.closeDiff();
        widget.onCloseOverlay?.call();
        return _select(row.commit.id, reveal: true);
      }
    }
  }

  /// Selects the local changes and shows their commit box (Focus on Source
  /// Control, Git: Commit from the palette).
  void showLocalChanges() {
    _log.closeDiff();
    _select(ideGitWorkingTreeId, reveal: true);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final git = _git;
    final state = git?.state;
    if (git == null || state == null) return KeyEventResult.ignored;
    final ids = _ids(git);
    final at = ids.indexOf(_selectedOf(git, state));
    final page = ideRowsPerPage(
      _log.scroll,
      rowHeight: IdeGitLogView.rowHeight,
    );
    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.keyF &&
        (hardware.isMetaPressed || hardware.isControlPressed)) {
      _log.searchFocus.requestFocus();
      _log.search.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _log.search.text.length,
      );
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) unawaited(_openFirstFile(git, ids[at]));
      return KeyEventResult.handled;
    }
    final int? to = switch (key) {
      LogicalKeyboardKey.arrowDown => at + 1,
      LogicalKeyboardKey.arrowUp => at - 1,
      LogicalKeyboardKey.pageDown => at + page,
      LogicalKeyboardKey.pageUp => at - page,
      LogicalKeyboardKey.home => 0,
      LogicalKeyboardKey.end => ids.length - 1,
      _ => null,
    };
    if (to == null) return KeyEventResult.ignored;
    final id = ids[to.clamp(0, ids.length - 1)];
    // Shift: the selection grown to it, as a Shift-click does.
    if (hardware.isShiftPressed && id != ideGitWorkingTreeId) {
      _clicked(git, id);
      _select(id, reveal: true, keep: true);
      return KeyEventResult.handled;
    }
    _anchor = id;
    _select(id, reveal: true);
    return KeyEventResult.handled;
  }

  /// Enter on a commit: its first file's changes.
  Future<void> _openFirstFile(IdeGitRepository git, String id) async {
    if (id == ideGitWorkingTreeId) return;
    IdeGitCommit? commit;
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.commit.id == id) commit = row.commit;
    }
    if (commit == null ||
        id == ideIncomingChangesId ||
        id == ideOutgoingChangesId) {
      return;
    }
    final List<IdeGitCommitChange> changes;
    try {
      changes = await _log.changesOf(git, id);
    } catch (error) {
      return _report(error);
    }
    if (!mounted || changes.isEmpty || _log.selected != id) return;
    final files = [
      for (final change in changes) ideCommitDiffFile(git, commit, change),
    ];
    if (widget.onOpenDiff case final open?) {
      open(files.first);
    } else {
      _log.showDiff(files, 0);
    }
  }

  Widget _main(IdeGitRepository git, IdeGitState state) {
    final l10n = context.l10n;
    if (_overlay() case final overlay?) return overlay;
    if (_log.diff case final diff?) {
      return _DiffArea(
        key: ObjectKey(diff.files),
        diff: diff,
        root: state.root,
        paths: git.service.pathContext,
        border: _border,
        onStep: _log.stepDiff,
        onShow: _log.showDiffAt,
        onAsk: widget.onAsk,
        onClose: () {
          final focused = diff.focus;
          _log.closeDiff();
          // Back to the table, where the keys were.
          if (!focused) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _log.focusNode.requestFocus();
          });
        },
      );
    }
    final rows = git.graph;
    final narrowed = git.graphFilter.narrowed;
    final selected = _selectedOf(git, state);
    final fullGraphWidth = narrowed || rows == null || rows.isEmpty
        ? 22.0
        : rows.map(ideGraphWidth).reduce(math.max);
    final headRow = rows?.indexWhere((row) => row.kind == IdeGraphRowKind.head);
    final count = 1 + (rows?.length ?? 0) + (git.graphHasMore ? 1 : 0);
    return Focus(
      focusNode: _log.focusNode,
      onKeyEvent: _onKey,
      child: ListenableBuilder(
        listenable: _log.focusNode,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            // The graph first, all its lanes: the message keeps no more
            // than its least, and the columns give way.
            final graphWidth = math.max(
              22.0,
              math.min(
                fullGraphWidth,
                constraints.maxWidth - _Columns.subjectMinWidth,
              ),
            );
            final columns = _Columns.of(
              constraints.maxWidth,
              graph: graphWidth,
            );
            return ListView.builder(
              controller: _log.scroll,
              itemExtent: IdeGitLogView.rowHeight,
              itemCount:
                  rows == null || (rows.isEmpty && git.graphFilter.filtered)
                  ? 2
                  : count,
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _workingTreeRow(
                    _localChanges(git, state),
                    selected == ideGitWorkingTreeId,
                    graphWidth: graphWidth,
                    // HEAD right under it: the lane goes on down to it.
                    lane: headRow == 0 && !narrowed
                        ? rows![0].circleIndex
                        : null,
                    columns: columns,
                  );
                }
                if (rows == null) {
                  return _Message(spinning: true, text: l10n.gitLogLoading);
                }
                if (rows.isEmpty) {
                  return _Message(
                    text: l10n.gitLogNoCommits,
                    action: _filtered(git) ? l10n.gitLogClearFilters : null,
                    onAction: () => _clearFilters(git),
                  );
                }
                if (index > rows.length) {
                  return _LoadMore(
                    key: ValueKey(rows.length),
                    onShown: () => unawaited(git.loadMoreGraph()),
                  );
                }
                final row = rows[index - 1];
                return _commitRow(
                  git,
                  row,
                  _log.isSelected(row.commit.id),
                  graphWidth: graphWidth,
                  narrowed: narrowed,
                  columns: columns,
                );
              },
            );
          },
        ),
      ),
    );
  }

  /// The local changes' count: every repository's, where the local
  /// changes' details list them all.
  int _localChanges(IdeGitRepository git, IdeGitState state) {
    final repositories = widget.host.repositories;
    if (repositories.length < 2) return state.count;
    return repositories.fold(
      0,
      (sum, repository) => sum + (repository.$2.state?.count ?? 0),
    );
  }

  Widget _workingTreeRow(
    int count,
    bool selected, {
    required double graphWidth,
    required int? lane,
    required _Columns columns,
  }) {
    final l10n = context.l10n;
    final colors = themeColors;
    return IdeListRow(
      key: const ValueKey(ideGitWorkingTreeId),
      height: IdeGitLogView.rowHeight,
      selected: selected,
      focused: _log.focusNode.hasFocus,
      onTap: () {
        _log.focusNode.requestFocus();
        _select(ideGitWorkingTreeId);
      },
      builder: (context, hovered) => Row(
        children: [
          CustomPaint(
            size: Size(graphWidth, IdeGitLogView.rowHeight),
            painter: _WorkingTreePainter(
              lane: lane ?? 0,
              down: lane != null,
              color: colors[IdeGraphColors.ref],
            ),
          ),
          // Which worktree's they are, where there are several; ✦ where
          // the agent works.
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: count > 0
                        ? l10n.gitLogLocalChangesCount(count)
                        : l10n.gitLogLocalChanges,
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: count > 0
                          ? IdeListColors.foreground
                          : IdeListColors.description,
                    ),
                  ),
                  if (_shownWorktree case final worktree?
                      when _worktrees.length > 1 && _git != null) ...[
                    const TextSpan(text: '   '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Icon(
                        Codicons.worktree,
                        size: 13,
                        color: IdeListColors.description,
                      ),
                    ),
                    TextSpan(
                      text:
                          ' ${[_worktreeName(_git!, worktree), ?worktree.branch].join(' · ')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: IdeListColors.description,
                      ),
                    ),
                  ],
                  if (_agentWorktree != null &&
                      _agentWorktree?.path == _shownWorktree?.path)
                    const WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: _AgentMark(),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (columns.date) const SizedBox(width: _Columns.dateWidth),
          if (columns.author) const SizedBox(width: _Columns.authorWidth),
          if (columns.hash) const SizedBox(width: _Columns.hashWidth),
        ],
      ),
    );
  }

  Widget _commitRow(
    IdeGitRepository git,
    IdeGraphRow row,
    bool selected, {
    required double graphWidth,
    required bool narrowed,
    required _Columns columns,
  }) {
    final commit = row.commit;
    final colors = themeColors;
    final synthetic =
        commit.id == ideIncomingChangesId || commit.id == ideOutgoingChangesId;
    final merge = commit.parentIds.length > 1;
    final mine =
        _log.highlight == IdeGitLogHighlight.mine &&
        _userEmail != null &&
        commit.authorEmail.toLowerCase() == _userEmail!.toLowerCase();
    final dim = merge || synthetic;
    final foreground = dim
        ? IdeListColors.description
        : IdeListColors.foreground;
    final weight = row.kind == IdeGraphRowKind.head || mine
        ? FontWeight.w600
        : null;
    final focused = _log.focusNode.hasFocus;
    return IdeListRow(
      key: ValueKey(commit.id),
      height: IdeGitLogView.rowHeight,
      selected: selected,
      focused: focused,
      onTap: () {
        _log.focusNode.requestFocus();
        _clicked(git, commit.id, synthetic: synthetic);
      },
      onContextMenu: synthetic
          ? null
          : (position) {
              final many = _selectedCommits(git);
              if (many.length > 1 && _log.isSelected(commit.id)) {
                unawaited(_commitsMenu(position, git, many));
                return;
              }
              _select(commit.id);
              unawaited(_commitMenu(position, git, commit));
            },
      builder: (context, hovered) {
        // What is behind the circles: the row's color over the page's.
        final background = Color.alphaBlend(
          selected
              ? (focused
                    ? IdeListColors.activeSelection
                    : IdeListColors.inactiveSelection)
              : hovered
              ? IdeListColors.hover
              : Colors.transparent,
          _background,
        );
        return Row(
          children: [
            ClipRect(
              child: SizedBox(
                width: graphWidth,
                height: IdeGitLogView.rowHeight,
                child: narrowed
                    ? CustomPaint(painter: _DotPainter(colors[row.circleColor]))
                    : OverflowBox(
                        alignment: Alignment.centerLeft,
                        maxWidth: double.infinity,
                        child: CustomPaint(
                          size: Size(
                            ideGraphWidth(row),
                            IdeGitLogView.rowHeight,
                          ),
                          painter: IdeGraphPainter(
                            row,
                            background: background,
                            hovered: hovered,
                            height: IdeGitLogView.rowHeight,
                          ),
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GiveWayRow(
                  children: [
                    GiveWay.fill(
                      _commitHover(
                        row,
                        synthetic: synthetic,
                        child: Text.rich(
                          TextSpan(
                            children: _highlighted(
                              _subjectOf(commit),
                              synthetic ? const [] : git.graphFilter.terms,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: foreground,
                            fontWeight: weight,
                            fontStyle: synthetic ? FontStyle.italic : null,
                          ),
                        ),
                      ),
                      minWidth: 60,
                    ),
                    ..._labels(row, foreground),
                  ],
                ),
              ),
            ),
            if (columns.date)
              SizedBox(
                width: _Columns.dateWidth,
                child: synthetic
                    ? null
                    : Text(
                        _tableDate(commit.date),
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(fontSize: 12, color: foreground),
                      ),
              ),
            if (columns.author)
              SizedBox(
                width: _Columns.authorWidth,
                child: synthetic || commit.author.isEmpty
                    ? null
                    : Row(
                        children: [
                          _Avatar(commit.author, commit.authorEmail, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              commit.author,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: foreground,
                                fontWeight: mine ? FontWeight.w600 : null,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            if (columns.hash)
              SizedBox(
                width: _Columns.hashWidth,
                child: synthetic
                    ? null
                    : Text(
                        _short(commit.id),
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          color: IdeListColors.description,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
              ),
          ],
        );
      },
    );
  }

  /// [text] with [terms] (the search's) standing out, as a list's
  /// matches do.
  static List<TextSpan> _highlighted(String text, List<String> terms) {
    final words = [
      for (final term in terms)
        if (term.trim().isNotEmpty) RegExp.escape(term.trim()),
    ];
    if (words.isEmpty) return [TextSpan(text: text)];
    final match = RegExp(words.join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    var at = 0;
    for (final found in match.allMatches(text)) {
      if (found.start == found.end) continue;
      if (found.start > at) {
        spans.add(TextSpan(text: text.substring(at, found.start)));
      }
      spans.add(
        TextSpan(
          text: found.group(0),
          style: TextStyle(
            color: IdeListColors.highlight,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      at = found.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return spans;
  }

  /// A date as the table shows it: today's and yesterday's by name.
  String _tableDate(DateTime date) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final time = _formatDate(date).substring(11);
    if (day == today) return l10n.gitLogToday(time);
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.gitLogYesterday(time);
    }
    return _formatDate(date);
  }

  /// Over a commit's subject, the whole of it: its author and date, its
  /// message and references, its hash.
  Widget _commitHover(
    IdeGraphRow row, {
    required bool synthetic,
    required Widget child,
  }) => synthetic
      ? child
      : IdeHover(
          content: IdeCommitHover(
            row.commit,
            referenceColors: row.referenceColors,
            labels: true,
          ),
          compact: false,
          child: child,
        );

  /// The references' labels at the row's end, as JetBrains IDEs align
  /// them, the subject cut short before them: short of room the tags give
  /// way first, to their icons alone, then gone; then the remote branches;
  /// the branches last.
  List<GiveWay> _labels(IdeGraphRow row, Color foreground) {
    final labels = ideGitRefLabels(row.commit.references);
    return [
      for (final (index, label) in labels.indexed)
        GiveWay(
          Padding(
            padding: EdgeInsets.only(left: index == 0 ? 12 : 10),
            child: IdeGitRefLabelView(
              label,
              foreground: foreground,
              trailing: [
                for (final ref in [label.ref, ...label.remotes])
                  ..._worktreeMarks(ref),
              ],
            ),
          ),
          compact: Padding(
            padding: EdgeInsets.only(left: index == 0 ? 12 : 4),
            child: IdeGitRefLabelView(label, compact: true),
          ),
          priority:
              switch (label.ref.kind) {
                IdeGitRefKind.head => 3000,
                IdeGitRefKind.branch => 2000,
                IdeGitRefKind.remote => 1000,
                IdeGitRefKind.tag => 0,
              } -
              index,
        ),
    ];
  }

  /// After a branch checked out in a worktree: the worktree's mark (but
  /// for the one shown), and ✦ where the agent works.
  List<Widget> _worktreeMarks(IdeGitRef ref) {
    if (ref.kind != IdeGitRefKind.branch || _worktrees.length < 2) {
      return const [];
    }
    final worktree = _worktrees
        .where((worktree) => worktree.branch == ref.name)
        .firstOrNull;
    if (worktree == null) return const [];
    final l10n = context.l10n;
    final git = _git;
    final shown = _shownWorktree?.path == worktree.path;
    final agent = _agentWorktree?.path == worktree.path;
    return [
      if (!shown && git != null)
        IdeHover(
          message: l10n.gitLogWorktreeAt(
            _worktreeName(git, worktree),
            worktree.path,
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Icon(
              Codicons.worktree,
              size: 13,
              color: IdeListColors.description,
            ),
          ),
        ),
      if (agent) const _AgentMark(),
    ];
  }

  String _subjectOf(IdeGitCommit commit) {
    if (commit.id == ideIncomingChangesId) {
      return context.l10n.scmIncomingChanges;
    }
    if (commit.id == ideOutgoingChangesId) {
      return context.l10n.scmOutgoingChanges;
    }
    return commit.subject;
  }

  Future<void> _commitMenu(
    Offset position,
    IdeGitRepository git,
    IdeGitCommit commit,
  ) {
    final l10n = context.l10n;
    final head = git.state?.head;
    final branches = [
      for (final ref in commit.references)
        if (ref.kind == IdeGitRefKind.branch && ref.name != head?.branch)
          ref.name,
    ];
    final isHead = _isHead(git, commit);
    // In the current branch's history: what rewrites it can.
    final inBranch = head?.branch != null && _inHeadHistory(git, commit);
    final parent = commit.parentIds.firstOrNull;
    final child = _childOf(git, commit);
    IdeMenuAction reset(String label, IdeGitResetMode mode) => IdeMenuAction(
      label,
      onSelected: () => unawaited(_reset(git, commit, mode)),
    );
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          IdeMenuAction(
            l10n.scmCopyCommitHash,
            onSelected: () =>
                unawaited(Clipboard.setData(ClipboardData(text: commit.id))),
          ),
          IdeMenuAction(
            l10n.scmCopyCommitMessage,
            onSelected: () => unawaited(
              Clipboard.setData(ClipboardData(text: commit.message)),
            ),
          ),
          IdeMenuAction(
            l10n.gitLogCopyPatch,
            onSelected: () => unawaited(
              _run(() async {
                final patch = await git.service.patch(commit.id);
                await Clipboard.setData(ClipboardData(text: patch));
              }),
            ),
          ),
          if (commit.references.isNotEmpty)
            IdeMenuAction(
              l10n.gitLogCopyRefNames,
              submenu: _copyRefNames(commit.references),
            ),
        ],
        [
          if (widget.onAsk case final ask?)
            IdeMenuAction(
              l10n.gitAskAiCommit,
              onSelected: () => ask(
                l10n.gitAskAiCommitPrompt(commit.shortId, commit.subject),
              ),
            ),
        ],
        [
          if (!isHead && !inBranch)
            IdeMenuAction(
              l10n.gitLogCherryPick,
              onSelected: () =>
                  unawaited(_run(() => git.cherryPick([commit.id]))),
            ),
          for (final branch in branches)
            IdeMenuAction(
              l10n.gitLogCheckoutBranch(branch),
              onSelected: () => unawaited(_run(() => git.checkout(branch))),
            ),
          IdeMenuAction(
            l10n.gitLogCheckoutRevision,
            onSelected: () =>
                unawaited(_run(() => git.checkout(commit.id, detached: true))),
          ),
          IdeMenuAction(
            l10n.gitLogCompareWithLocal,
            onSelected: () =>
                unawaited(_compareWithLocal(git, commit.id, commit.shortId)),
          ),
        ],
        [
          if (head?.branch != null)
            IdeMenuAction(
              l10n.gitLogResetToHere,
              submenu: [
                reset(l10n.gitLogResetSoft, IdeGitResetMode.soft),
                reset(l10n.gitLogResetMixed, IdeGitResetMode.mixed),
                reset(l10n.gitLogResetHard, IdeGitResetMode.hard),
                reset(l10n.gitLogResetKeep, IdeGitResetMode.keep),
              ],
            ),
          IdeMenuAction(
            l10n.gitLogRevertCommit,
            onSelected: () => unawaited(_run(() => git.revert([commit.id]))),
          ),
          // The last commit, not pushed yet: undone, its changes and its
          // message back to commit again.
          if (isHead && (head?.upstream == null || head!.ahead > 0))
            IdeMenuAction(
              l10n.gitLogUndoCommit,
              onSelected: () => unawaited(_undoCommit(git, commit)),
            ),
          if (isHead || inBranch)
            IdeMenuAction(
              l10n.gitLogEditMessage,
              onSelected: () => _log.editingMessage = commit.id,
            ),
          if ((isHead || inBranch) &&
              commit.parentIds.length == 1 &&
              widget.onFixup != null)
            IdeMenuAction(
              l10n.gitLogFixup,
              onSelected: () => unawaited(widget.onFixup!(git, commit)),
            ),
          if (inBranch && commit.parentIds.length == 1)
            IdeMenuAction(
              l10n.gitLogDropCommit,
              onSelected: () => unawaited(_drop(git, commit)),
            ),
          if ((isHead || inBranch) && commit.parentIds.length <= 1)
            IdeMenuAction(
              l10n.gitLogInteractiveRebase,
              onSelected: () => unawaited(
                showIdeGitRebaseDialog(
                  context,
                  git: git,
                  from: commit,
                  notifications: widget.notifications,
                  ai: widget.ai,
                ),
              ),
            ),
        ],
        [
          if (_outgoing(git).contains(commit.id))
            IdeMenuAction(
              l10n.gitLogPushUpToHere,
              onSelected: () => unawaited(_run(() => git.pushUpTo(commit.id))),
            ),
        ],
        [
          IdeMenuAction(
            l10n.gitLogNewBranch,
            onSelected: () => unawaited(_newBranch(git, commit)),
          ),
          IdeMenuAction(
            l10n.gitLogNewTag,
            onSelected: () => unawaited(_newTag(git, commit)),
          ),
        ],
        [
          IdeMenuAction(
            l10n.gitLogGoToChild,
            enabled: child != null,
            onSelected: () => _select(child!, reveal: true),
          ),
          IdeMenuAction(
            l10n.gitLogGoToParent,
            enabled: parent != null,
            onSelected: () => _select(parent!, reveal: true),
          ),
        ],
      ]),
    );
  }

  /// The menu of [commits] selected together (newest first).
  Future<void> _commitsMenu(
    Offset position,
    IdeGitRepository git,
    List<IdeGitCommit> commits,
  ) {
    final l10n = context.l10n;
    final oldestFirst = commits.reversed.toList();
    final inBranch = [
      for (final commit in commits)
        if (git.state?.head.branch != null && _inHeadHistory(git, commit))
          commit,
    ];
    final elsewhere = commits.length - inBranch.length;
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          IdeMenuAction(
            l10n.gitLogCopyHashes,
            onSelected: () => unawaited(
              Clipboard.setData(
                ClipboardData(text: commits.map((c) => c.id).join('\n')),
              ),
            ),
          ),
          if (widget.onAsk case final ask?)
            IdeMenuAction(
              l10n.gitAskAiCommits(commits.length),
              onSelected: () => ask(
                l10n.gitAskAiCommitsPrompt(
                  oldestFirst.map((c) => c.shortId).join(', '),
                ),
              ),
            ),
        ],
        [
          if (elsewhere == commits.length)
            IdeMenuAction(
              l10n.gitLogCherryPickCount(commits.length),
              onSelected: () => unawaited(
                _run(() => git.cherryPick([for (final c in oldestFirst) c.id])),
              ),
            ),
          if (commits.length == 2)
            IdeMenuAction(
              l10n.gitLogCompareCommits,
              onSelected: () => unawaited(
                _compareCommits(
                  git,
                  (commits.last.id, commits.last.shortId),
                  (commits.first.id, commits.first.shortId),
                ),
              ),
            ),
        ],
        [
          IdeMenuAction(
            l10n.gitLogRevertCommits(commits.length),
            onSelected: () => unawaited(
              _run(() => git.revert([for (final c in commits) c.id])),
            ),
          ),
          if (inBranch.length == commits.length &&
              _consecutive(git, commits) &&
              commits.every((c) => c.parentIds.length <= 1))
            IdeMenuAction(
              l10n.gitLogSquashCommits(commits.length),
              onSelected: () => unawaited(_run(() => git.squash(oldestFirst))),
            ),
        ],
      ]),
    );
  }

  /// Whether [commits] (newest first) follow one another by first parents.
  static bool _consecutive(IdeGitRepository git, List<IdeGitCommit> commits) {
    for (var i = 0; i + 1 < commits.length; i++) {
      if (commits[i].parentIds.firstOrNull != commits[i + 1].id) return false;
    }
    return true;
  }

  /// Two commits compared: the files [from] and [to] differ in, [from]'s
  /// side against [to]'s, in the table's place.
  Future<void> _compareCommits(
    IdeGitRepository git,
    (String id, String label) from,
    (String id, String label) to,
  ) => _showComparison(() => ideGitRevisionsDiff(git, from, to));

  /// [compare]'s files in the table's place; that there are none, or why
  /// they could not be read, told.
  Future<void> _showComparison(
    Future<List<IdeGitDiffFile>> Function() compare,
  ) async {
    final List<IdeGitDiffFile> files;
    try {
      files = await compare();
    } catch (error) {
      _report(error);
      return;
    }
    if (!mounted) return;
    if (files.isEmpty) {
      widget.notifications.notify(
        IdeSeverity.info,
        context.l10n.gitLogNoDifferences,
      );
      return;
    }
    _log.showDiff(files, 0);
  }

  /// Whether [commit] is HEAD's or one before it, by the graph's first
  /// parents.
  static bool _inHeadHistory(IdeGitRepository git, IdeGitCommit commit) {
    final rows = git.graph ?? const <IdeGraphRow>[];
    final byId = {for (final row in rows) row.commit.id: row.commit};
    var at = rows
        .where((row) => row.kind == IdeGraphRowKind.head)
        .firstOrNull
        ?.commit;
    while (at != null) {
      if (at.id == commit.id) return true;
      final parent = at.parentIds.firstOrNull;
      at = parent == null ? null : byId[parent];
    }
    return false;
  }

  /// The commits of HEAD's not pushed yet: as many as it is ahead, down
  /// its first parents.
  static Set<String> _outgoing(IdeGitRepository git) {
    final head = git.state?.head;
    if (head == null || head.upstream == null || head.ahead == 0) return {};
    final rows = git.graph ?? const <IdeGraphRow>[];
    final byId = {for (final row in rows) row.commit.id: row.commit};
    var at = rows
        .where((row) => row.kind == IdeGraphRowKind.head)
        .firstOrNull
        ?.commit;
    final ids = <String>{};
    while (at != null && ids.length < head.ahead) {
      ids.add(at.id);
      final parent = at.parentIds.firstOrNull;
      at = parent == null ? null : byId[parent];
    }
    return ids;
  }

  /// The commit loaded whose first parent [commit] is, if any.
  static String? _childOf(IdeGitRepository git, IdeGitCommit commit) {
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.commit.parentIds.contains(commit.id)) return row.commit.id;
    }
    return null;
  }

  /// Reset Current Branch to Here; Hard, once confirmed.
  Future<void> _reset(
    IdeGitRepository git,
    IdeGitCommit commit,
    IdeGitResetMode mode,
  ) async {
    if (mode == IdeGitResetMode.hard) {
      final l10n = context.l10n;
      final answer = await showIdeDialog(
        context,
        message: l10n.gitLogResetHardConfirm(
          git.state?.head.branch ?? 'HEAD',
          commit.shortId,
        ),
        buttons: [l10n.gitLogResetButton],
      );
      if (answer != 0) return;
    }
    await _run(() => git.reset(commit.id, mode));
  }

  /// Edit Commit Message's save: [commit] given [message]; then the
  /// branch's tip selected, where the commit is now.
  Future<void> _reword(
    IdeGitRepository git,
    IdeGitCommit commit,
    String message,
  ) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || trimmed == commit.message.trim()) {
      _log.editingMessage = null;
      return;
    }
    var done = false;
    await _run(() async {
      await git.reword(commit, trimmed);
      done = true;
    });
    if (!mounted || !done) return;
    _log.editingMessage = null;
    final head = await git.service.revParse('HEAD');
    if (mounted && head != null) _select(head, reveal: true);
  }

  /// Drop Commit, once confirmed.
  Future<void> _drop(IdeGitRepository git, IdeGitCommit commit) async {
    final l10n = context.l10n;
    final answer = await showIdeDialog(
      context,
      message: l10n.gitLogDropConfirm(commit.shortId, commit.subject),
      buttons: [l10n.gitLogDropButton],
    );
    if (answer != 0) return;
    await _run(() => git.drop(commit));
  }

  /// New Tag: asks for a name and a message, then tags [commit].
  Future<void> _newTag(IdeGitRepository git, IdeGitCommit commit) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitLogNewTagAt(commit.shortId),
      buttons: [l10n.gitLogCreateTag],
      inputs: [
        IdeDialogInput(placeholder: l10n.gitTagName),
        IdeDialogInput(placeholder: l10n.gitTagMessage),
      ],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await _run(
      () => git.tag(name, commit.id, message: result.values.last.trim()),
    );
  }

  /// Compare with Local: the files [revision] (a commit, a branch) and
  /// the working tree differ in, in the table's place, its side against
  /// the file's.
  Future<void> _compareWithLocal(
    IdeGitRepository git,
    String revision,
    String label,
  ) => _showComparison(
    () => ideGitWorkingTreeDiff(
      git,
      widget.host.files,
      revision,
      label,
      context.l10n.gitChangeWorkingTree,
    ),
  );

  static bool _isHead(IdeGitRepository git, IdeGitCommit commit) {
    for (final row in git.graph ?? const <IdeGraphRow>[]) {
      if (row.kind == IdeGraphRowKind.head) return row.commit.id == commit.id;
    }
    return false;
  }

  /// Undo Commit: HEAD back to its parent, its changes kept, its message
  /// in the commit message for the next.
  Future<void> _undoCommit(IdeGitRepository git, IdeGitCommit commit) async {
    await _run(() => git.undoCommit(commit));
    if (!mounted) return;
    final message = commit.message.trim();
    widget.session.message.value = TextEditingValue(
      text: message,
      selection: TextSelection.collapsed(offset: message.length),
    );
    showLocalChanges();
  }

  /// Asks for a name, then makes a branch at [commit] and checks it out.
  Future<void> _newBranch(IdeGitRepository git, IdeGitCommit commit) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitLogNewBranchAt(commit.shortId),
      buttons: [l10n.branchBarCreateButton],
      inputs: [IdeDialogInput(placeholder: l10n.gitBranchName)],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0) return;
    final name = ideSanitizeBranchName(result.values.first);
    if (name.isEmpty) return;
    await _run(() => git.branch(name, ref: commit.id));
  }

  // --- Details -------------------------------------------------------------

  Widget _details(IdeGitRepository git, IdeGitState state) {
    final selected = _selectedOf(git, state);
    final local = selected == ideGitWorkingTreeId;
    IdeGraphRow? row;
    if (!local) {
      for (final candidate in git.graph ?? const <IdeGraphRow>[]) {
        if (candidate.commit.id == selected) {
          row = candidate;
          break;
        }
      }
    }
    final many = local ? const <IdeGitCommit>[] : _selectedCommits(git);
    if (many.length > 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Visibility(
            visible: false,
            maintainState: true,
            child: widget.changes,
          ),
          _SelectionSummary(commits: many),
        ],
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // Kept while a commit shows: the commands of Source Control (Git:
        // Commit, Focus on Source Control) act on it.
        Visibility(visible: local, maintainState: true, child: widget.changes),
        if (!local)
          switch (row) {
            final row?
                when row.commit.id != ideIncomingChangesId &&
                    row.commit.id != ideOutgoingChangesId =>
              _CommitDetails(
                key: ValueKey(row.commit.id),
                git: git,
                row: row,
                log: _log,
                root: state.root,
                border: _border,
                onSelect: (id) => _select(id, reveal: true),
                onReword: (message) => _reword(git, row.commit, message),
                onOpenDiff: (files, index) {
                  if (widget.onOpenDiff case final open?) {
                    open(files[index]);
                  } else {
                    _log.showDiff(files, index);
                  }
                },
                onOpen: widget.onOpen,
                onAddToChat: widget.onAddToChat,
              ),
            final row? => _Placeholder(_subjectOf(row.commit)),
            null => _Placeholder(context.l10n.gitLogSelectCommit),
          },
      ],
    );
  }
}

/// `2026-10-26 14:45`, as the table shows a date; with [seconds],
/// `2026-10-26 14:45:26`.
String _formatDate(DateTime date, {bool seconds = false}) {
  String two(int value) => value.toString().padLeft(2, '0');
  final time = '${two(date.hour)}:${two(date.minute)}';
  return '${date.year}-${two(date.month)}-${two(date.day)} '
      '${seconds ? '$time:${two(date.second)}' : time}';
}

/// Which of the table's columns fit beside the message.
class _Columns {
  const _Columns({
    required this.date,
    required this.author,
    required this.hash,
  });

  /// Those [width] has room for beside a graph [graph] wide: the hash's
  /// given up first, then the author's, then the date's, for the message
  /// to keep its least.
  factory _Columns.of(double width, {double graph = 0}) {
    var date = width >= 380, author = width >= 500, hash = width >= 580;
    double taken() =>
        graph +
        subjectMinWidth +
        (date ? dateWidth : 0) +
        (author ? authorWidth : 0) +
        (hash ? hashWidth : 0);
    if (hash && taken() > width) hash = false;
    if (author && taken() > width) author = false;
    if (date && taken() > width) date = false;
    return _Columns(date: date, author: author, hash: hash);
  }

  /// The least a commit's message keeps of a row.
  static const subjectMinWidth = 120.0;

  static const dateWidth = 128.0;
  static const authorWidth = 130.0;
  static const hashWidth = 70.0;

  final bool date;
  final bool author;
  final bool hash;
}

/// A commit's details: its message, author and date, parents, references
/// (and the branches that have it, asked for), and its files, as a list or
/// a tree, filtered.
/// Copies [refs]' names, an item each, by their kinds' icons.
List<IdeMenuEntry> _copyRefNames(List<IdeGitRef> refs) => [
  for (final ref in refs)
    IdeMenuAction(
      ref.name,
      icon: Icon(
        IdeGitRefLabelView.icon(ref.kind),
        color: IdeGitRefLabelView.color(ref.kind),
      ),
      onSelected: () =>
          unawaited(Clipboard.setData(ClipboardData(text: ref.name))),
    ),
];

/// Copies [text], told by [label].
IdeMenuAction _copyItem(String label, String text) => IdeMenuAction(
  label,
  onSelected: () => unawaited(Clipboard.setData(ClipboardData(text: text))),
);

/// A commit's details as text to select, dragged across, or right-clicked:
/// the menu copies what is selected, and offers what was right-clicked
/// copies of its own ([_Offers]: a reference's whole name, the hash).
class _DetailsSelection extends StatefulWidget {
  const _DetailsSelection({required this.child});

  final Widget child;

  @override
  State<_DetailsSelection> createState() => _DetailsSelectionState();
}

class _DetailsSelectionState extends State<_DetailsSelection> {
  /// What is selected, kept: the menu takes the focus, and the selection
  /// goes with it.
  String _selected = '';

  /// What was selected as the right-click under way went down: where it
  /// lets go of the selection (Windows', Linux' off the selection, as
  /// Flutter tells it), what it was to copy.
  String _selectedBefore = '';

  /// Where the right-click under way was, and what was there offered.
  Offset? _at;
  ({Offset at, List<IdeMenuEntry> entries})? _offered;

  void _offer(Offset at, List<IdeMenuEntry> entries) =>
      _offered = (at: at, entries: entries);

  Widget _menu(BuildContext context, SelectableRegionState selection) {
    final l10n = context.l10n;
    final at = _at ?? selection.contextMenuAnchors.primaryAnchor;
    final offered = _offered?.at == _at
        ? _offered!.entries
        : const <IdeMenuEntry>[];
    _offered = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      selection.hideToolbar();
      if (!mounted) return;
      final text = _selected.isNotEmpty ? _selected : _selectedBefore;
      unawaited(
        showIdeMenu(
          this.context,
          position: at,
          entries: ideMenuGroups([
            [
              IdeMenuAction(
                l10n.commonCopy,
                enabled: text.isNotEmpty,
                onSelected: () =>
                    unawaited(Clipboard.setData(ClipboardData(text: text))),
              ),
            ],
            offered,
          ]),
        ),
      );
    });
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons & kSecondaryButton == 0) return;
      _at = event.position;
      _selectedBefore = _selected;
    },
    child: SelectionArea(
      contextMenuBuilder: _menu,
      onSelectionChanged: (content) => _selected = content?.plainText ?? '',
      child: widget.child,
    ),
  );
}

/// [child], whose right-click's menu in [_DetailsSelection] offers
/// [entries] too.
class _Offers extends StatelessWidget {
  const _Offers({required this.entries, required this.child});

  final List<IdeMenuEntry> entries;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      if (event.buttons & kSecondaryButton == 0) return;
      context.findAncestorStateOfType<_DetailsSelectionState>()?._offer(
        event.position,
        entries,
      );
    },
    child: child,
  );
}

class _CommitDetails extends StatelessWidget {
  const _CommitDetails({
    super.key,
    required this.git,
    required this.row,
    required this.log,
    required this.root,
    required this.border,
    required this.onSelect,
    required this.onReword,
    required this.onOpenDiff,
    this.onOpen,
    this.onAddToChat,
  });

  final IdeGitRepository git;
  final IdeGraphRow row;

  /// Saves the message edited (Edit Commit Message).
  final Future<void> Function(String message) onReword;
  final IdeGitLogController log;
  final String root;
  final Color border;
  final ValueChanged<String> onSelect;
  final void Function(List<IdeGitDiffFile> files, int index) onOpenDiff;
  final ValueChanged<String>? onOpen;
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  IdeGitCommit get commit => row.commit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = IdeListColors.description;
    final foreground = IdeListColors.foreground;
    final message = commit.message.trim();
    final newline = message.indexOf('\n');
    final body = newline < 0 ? '' : message.substring(newline + 1).trim();
    return FutureBuilder<List<IdeGitCommitChange>>(
      future: log.changesOf(git, commit.id),
      builder: (context, changes) {
        final files = changes.data;
        final filtered = files == null
            ? null
            : _filtered(files, log.fileFilter.text);
        final entries = filtered == null ? null : _entries(filtered);
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DetailsSelection(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: _Offers(
                              entries: [
                                _copyItem(l10n.scmCopyCommitHash, commit.id),
                              ],
                              child: IdeHover(
                                message: '${l10n.gitLogCopyHash}\n${commit.id}',
                                child: MouseRegion(
                                  cursor: SystemMouseCursors.click,
                                  child: GestureDetector(
                                    onTap: () => unawaited(
                                      Clipboard.setData(
                                        ClipboardData(text: commit.id),
                                      ),
                                    ),
                                    child: Text(
                                      'commit: ${commit.shortId}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: foreground,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // The message, in a box of its own; edited in place.
                          if (log.editingMessage == commit.id)
                            SelectionContainer.disabled(
                              child: _MessageEditor(
                                message: message,
                                border: border,
                                onSave: onReword,
                                onCancel: () => log.editingMessage = null,
                              ),
                            )
                          else
                            Container(
                              constraints: const BoxConstraints(maxHeight: 140),
                              padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
                              decoration: BoxDecoration(
                                border: Border.all(color: border),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: commit.subject,
                                              style: TextStyle(
                                                color: foreground,
                                              ),
                                            ),
                                            if (body.isNotEmpty)
                                              TextSpan(
                                                text: '\n$body',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: description,
                                                ),
                                              ),
                                          ],
                                        ),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IdeActionButton(
                                    icon: Codicons.copy,
                                    tooltip: l10n.scmCopyCommitMessage,
                                    size: 20,
                                    iconSize: 14,
                                    onPressed: () => unawaited(
                                      Clipboard.setData(
                                        ClipboardData(text: commit.message),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.gitLogAuthor,
                            style: TextStyle(fontSize: 12, color: description),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _Avatar(
                                commit.author,
                                commit.authorEmail,
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _Offers(
                                      entries: [
                                        _copyItem(
                                          l10n.gitLogCopyName(commit.author),
                                          commit.author,
                                        ),
                                        if (commit.authorEmail.isNotEmpty)
                                          _copyItem(
                                            l10n.gitLogCopyName(
                                              commit.authorEmail,
                                            ),
                                            commit.authorEmail,
                                          ),
                                      ],
                                      child: IdeHover(
                                        message: commit.authorEmail,
                                        child: Text(
                                          commit.author,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: foreground,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatDate(commit.date, seconds: true),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: description,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (commit.parentIds.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: l10n.gitLogParents),
                                  for (final (index, parent)
                                      in commit.parentIds.indexed) ...[
                                    if (index > 0) const TextSpan(text: ', '),
                                    TextSpan(
                                      text: _short(parent),
                                      style: TextStyle(
                                        color:
                                            themeColors['textLink.foreground'],
                                      ),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () => onSelect(parent),
                                      mouseCursor: SystemMouseCursors.click,
                                    ),
                                  ],
                                ],
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: description,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          _summary(context, files),
                          if (commit.references.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                for (final label in ideGitRefLabels(
                                  commit.references,
                                ))
                                  _refLabel(label),
                              ],
                            ),
                          ],
                          const SizedBox(height: 8),
                          SelectionContainer.disabled(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                IdeButton(
                                  label: log.branchesShown
                                      ? l10n.gitLogHideBranches
                                      : l10n.gitLogShowBranches,
                                  secondary: true,
                                  onPressed: () =>
                                      log.branchesShown = !log.branchesShown,
                                ),
                                IdeButton(
                                  label: log.sizesShown
                                      ? l10n.gitLogHideSizes
                                      : l10n.gitLogShowSizes,
                                  secondary: true,
                                  onPressed: () =>
                                      log.sizesShown = !log.sizesShown,
                                ),
                              ],
                            ),
                          ),
                          if (log.branchesShown) ...[
                            const SizedBox(height: 8),
                            _branches(context),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _filesBar(context),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
            if (changes.hasError)
              SliverToBoxAdapter(child: _Placeholder('${changes.error}'))
            else if (entries == null)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: _Spinner(size: 16)),
                ),
              )
            else
              FutureBuilder<Map<String, ({int? added, int? deleted})>>(
                future: log.sizesShown ? log.statsOf(git, commit.id) : null,
                builder: (context, stats) => SliverFixedExtentList(
                  itemExtent: 24,
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _fileRow(
                      context,
                      entries[index],
                      filtered!,
                      stats.data,
                    ),
                    childCount: entries.length,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
        );
      },
    );
  }

  /// [label], whose right-click copies its names.
  Widget _refLabel(IdeGitRefLabel label) => _Offers(
    entries: _copyRefNames([label.ref, ...label.remotes]),
    child: IdeGitRefLabelView(label, full: true),
  );

  /// `8 files  +120 −30`.
  Widget _summary(BuildContext context, List<IdeGitCommitChange>? files) {
    final description = IdeListColors.description;
    final style = TextStyle(fontSize: 12, color: description);
    return Row(
      children: [
        Icon(Codicons.diff, size: 14, color: description),
        const SizedBox(width: 6),
        if (files != null)
          Text(context.l10n.gitLogFileCount(files.length), style: style),
        const SizedBox(width: 8),
        FutureBuilder<Map<String, ({int? added, int? deleted})>>(
          future: log.statsOf(git, commit.id),
          builder: (context, stats) {
            final data = stats.data;
            if (data == null || data.isEmpty) return const SizedBox.shrink();
            var added = 0;
            var deleted = 0;
            for (final stat in data.values) {
              added += stat.added ?? 0;
              deleted += stat.deleted ?? 0;
            }
            return _Counts(added: added, deleted: deleted);
          },
        ),
      ],
    );
  }

  /// The branches that have the commit, under their count: the current
  /// one's as the log draws it, a local branch and its remote's as one.
  Widget _branches(BuildContext context) => FutureBuilder<List<IdeGitRef>>(
    future: log.branchesOf(git, commit.id),
    builder: (context, branches) {
      final description = IdeListColors.description;
      if (branches.hasError) {
        return Text(
          '${branches.error}',
          style: TextStyle(fontSize: 12, color: description),
        );
      }
      final data = branches.data;
      if (data == null) {
        return const Align(
          alignment: Alignment.centerLeft,
          child: _Spinner(size: 14),
        );
      }
      if (data.isEmpty) {
        return Text(
          context.l10n.gitLogInNoBranch,
          style: TextStyle(fontSize: 12, color: description),
        );
      }
      final current = git.state?.head.branch;
      final labels = ideGitRefLabels([
        for (final ref in data)
          ref.kind == IdeGitRefKind.branch && ref.name == current
              ? IdeGitRef(ref.id, ref.name, IdeGitRefKind.head)
              : ref,
      ]);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.gitLogInBranches(labels.length),
            style: TextStyle(fontSize: 12, color: description),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [for (final label in labels) _refLabel(label)],
          ),
        ],
      );
    },
  );

  /// List and Tree, and the files' filter.
  Widget _filesBar(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IdeGitListTreeSwitch(
            tree: log.filesAsTree,
            onChanged: (tree) => log.filesAsTree = tree,
          ),
        ),
        const SizedBox(height: 6),
        IdeInputBox(
          controller: log.fileFilter,
          placeholder: l10n.gitLogFilterFiles,
          onChanged: (_) => log.fileFilterChanged(),
        ),
      ],
    );
  }

  /// [files] whose path relative to [root] matches [pattern]: `*` and `?`
  /// as wildcards, else as a part of it; case ignored.
  List<IdeGitCommitChange> _filtered(
    List<IdeGitCommitChange> files,
    String pattern,
  ) {
    pattern = pattern.trim();
    if (pattern.isEmpty) return files;
    final paths = git.service.pathContext;
    final RegExp match;
    if (pattern.contains('*') || pattern.contains('?')) {
      final source = RegExp.escape(pattern)
          .replaceAll(r'\*', '.*')
          .replaceAll(r'\?', '.');
      match = RegExp(source, caseSensitive: false);
    } else {
      match = RegExp(RegExp.escape(pattern), caseSensitive: false);
    }
    return [
      for (final file in files)
        if (match.hasMatch(
          paths.relative(file.path, from: root).replaceAll(r'\', '/'),
        ))
          file,
    ];
  }

  /// The rows: each file, or the tree's folders and files.
  List<_FileEntry> _entries(List<IdeGitCommitChange> files) {
    if (!log.filesAsTree) {
      return [for (final file in files) _FileEntry(file, null, 0)];
    }
    final byPath = {for (final file in files) file.path: file};
    final nodes = ideScmTree(root, [
      for (final file in files)
        IdeGitResource(
          path: file.path,
          originalPath: file.originalPath,
          status: ideCommitChangeStatus(file.status),
          group: IdeGitGroup.staged,
        ),
    ], paths: git.service.pathContext);
    final entries = <_FileEntry>[];
    void add(List<IdeScmTreeNode> nodes, int depth) {
      for (final node in nodes) {
        switch (node) {
          case IdeScmTreeFolder():
            entries.add(_FileEntry(null, node, depth));
            if (!log.collapsedFolders.contains(node.path)) {
              add(node.children, depth + 1);
            }
          case IdeScmTreeFile(:final resource):
            entries.add(_FileEntry(byPath[resource.path], null, depth));
        }
      }
    }

    add(nodes, 0);
    return entries;
  }

  Widget _fileRow(
    BuildContext context,
    _FileEntry entry,
    List<IdeGitCommitChange> files,
    Map<String, ({int? added, int? deleted})>? stats,
  ) {
    final paths = git.service.pathContext;
    final indent = entry.depth * 12.0;
    if (entry.folder case final folder?) {
      final collapsed = log.collapsedFolders.contains(folder.path);
      return IdeListRow(
        height: 24,
        onTap: () => log.toggleFolder(folder.path),
        builder: (context, _) => Row(
          children: [
            SizedBox(width: 4 + indent),
            Icon(
              collapsed ? Codicons.chevronRight : Codicons.chevronDown,
              size: 16,
              color: IdeListColors.foreground,
            ),
            const SizedBox(width: 2),
            FolderIcon(folder.path, expanded: !collapsed),
            const SizedBox(width: 6),
            Expanded(child: IdeResourceLabel(name: folder.label)),
          ],
        ),
      );
    }
    final file = entry.file!;
    final status = ideCommitChangeStatus(file.status);
    final relative = paths.relative(file.path, from: root);
    final directory = paths.dirname(relative);
    final stat = stats?[file.path];
    void open() => onOpenDiff([
      for (final file in files) ideCommitDiffFile(git, commit, file),
    ], files.indexOf(file));
    final shown = log.diff?.file;
    return IdeListRow(
      height: 24,
      tooltip: '$relative • ${status.localizedLabel(context.l10n)}',
      selected: shown?.commitId == commit.id && shown?.path == file.path,
      onTap: open,
      onContextMenu: (position) => unawaited(
        showIdeMenu(
          context,
          position: position,
          entries: [
            IdeMenuAction(context.l10n.scmOpenChanges, onSelected: open),
            if (onOpen case final openFile? when file.status != 'D')
              IdeMenuAction(
                context.l10n.scmOpenFile,
                onSelected: () => openFile(file.path),
              ),
            const IdeMenuSeparator(),
            IdeMenuAction(
              context.l10n.gitLogCopyPath,
              onSelected: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: file.path))),
            ),
            IdeMenuAction(
              context.l10n.gitLogCopyRelativePath,
              onSelected: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: relative))),
            ),
            if (onAddToChat case final add? when file.status != 'D')
              IdeMenuAction(
                context.l10n.sidePanelAddToChat,
                onSelected: () => add([ComposerFile(file.path)]),
              ),
          ],
        ),
      ),
      builder: (context, _) => Row(
        children: [
          SizedBox(width: 4 + indent + (log.filesAsTree ? 18 : 0)),
          FileIcon(file.path),
          const SizedBox(width: 6),
          Expanded(
            child: IdeResourceLabel(
              name: paths.basename(file.path),
              description: log.filesAsTree || directory == '.'
                  ? null
                  : directory,
              strikeThrough: status.strikeThrough,
              letter: file.status,
              letterColor: status.color,
            ),
          ),
          if (log.sizesShown && stat != null) ...[
            const SizedBox(width: 6),
            if (stat.added == null)
              Text(
                context.l10n.gitLogBinary,
                style: TextStyle(
                  fontSize: 11,
                  color: IdeListColors.description,
                ),
              )
            else
              _Counts(added: stat.added!, deleted: stat.deleted ?? 0),
          ],
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// A row of a commit's files: a file, or (in the tree) a folder.
class _FileEntry {
  const _FileEntry(this.file, this.folder, this.depth);

  final IdeGitCommitChange? file;
  final IdeScmTreeFolder? folder;
  final int depth;
}

/// `+12 −3`, in the added and deleted decorations' colors.
class _Counts extends StatelessWidget {
  const _Counts({required this.added, required this.deleted});

  final int added;
  final int deleted;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '+$added',
            style: TextStyle(
              color: colors['gitDecoration.addedResourceForeground'],
            ),
          ),
          const TextSpan(text: ' '),
          TextSpan(
            text: '−$deleted',
            style: TextStyle(
              color: colors['gitDecoration.deletedResourceForeground'],
            ),
          ),
        ],
      ),
      style: const TextStyle(
        fontSize: 11,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A file's changes in the table's place: its path, the sides compared,
/// the previous and next files, and the diff. It takes the keyboard when it
/// opens: Escape closes it, Alt+Up and Alt+Down (Shift+F7 and F7) step.
class _DiffArea extends StatefulWidget {
  const _DiffArea({
    super.key,
    required this.diff,
    required this.root,
    required this.paths,
    required this.border,
    required this.onStep,
    required this.onShow,
    required this.onClose,
    this.onAsk,
  });

  final IdeGitLogDiff diff;
  final String root;
  final p.Context paths;

  /// Asks the AI in the chat, a change of the file shown (see
  /// [IdeGitLogView.onAsk]).
  final ValueChanged<String>? onAsk;
  final Color border;
  final void Function(int delta, {IdeDiffStart start}) onStep;
  final ValueChanged<int> onShow;
  final VoidCallback onClose;

  @override
  State<_DiffArea> createState() => _DiffAreaState();
}

/// The Option key's sign on a Mac, Alt elsewhere.
String get _alt => defaultTargetPlatform == TargetPlatform.macOS ? '⌥' : 'Alt+';

class _DiffAreaState extends State<_DiffArea> {
  final FocusNode _focus = FocusNode(debugLabel: 'git log diff');

  /// Each file's diff, for its changes to be stepped through: the one
  /// shown, and the next while it is made ready to show in its place.
  final Map<IdeGitDiffFile, GlobalKey<IdeCodeDiffState>> _codes = {};

  GlobalKey<IdeCodeDiffState> _codeOf(IdeGitDiffFile file) =>
      _codes[file] ??= GlobalKey();

  /// The next change (F7), or, past the file's last, the next file's
  /// first; [delta] -1: the previous, or the previous file's last.
  void _stepChange(int delta) {
    final diff = widget.diff;
    final code = _codes[diff.files[diff.index]];
    if (code?.currentState?.step(delta) ?? false) return;
    final index = diff.index + delta;
    if (index < 0 || index >= diff.files.length) return;
    widget.onStep(
      delta,
      start: delta < 0 ? IdeDiffStart.last : IdeDiffStart.first,
    );
  }

  @override
  void initState() {
    super.initState();
    if (!widget.diff.focus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// The change stepped to in the file shown, and how many it has.
  final ValueNotifier<({int current, int count})> _position = ValueNotifier((
    current: -1,
    count: 0,
  ));

  @override
  void didUpdateWidget(_DiffArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diff.file != widget.diff.file) {
      _position.value = (current: -1, count: 0);
      // The keys still the diff's, its editor gone with the file.
      if (_focus.hasFocus) _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _position.dispose();
    super.dispose();
  }

  /// Go to Changed File: the files stepped through, the one shown checked.
  Future<void> _goToFile(BuildContext anchor) async {
    final box = anchor.findRenderObject();
    if (box is! RenderBox) return;
    final diff = widget.diff;
    final paths = widget.paths;
    await showIdeMenu(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      entries: [
        for (final (index, file) in diff.files.indexed)
          IdeMenuAction(
            paths.relative(file.path, from: widget.root),
            icon: FileIcon(file.path),
            checked: index == diff.index,
            onSelected: () => widget.onShow(index),
          ),
      ],
    );
  }

  /// Viewer Settings: side by side or unified, whitespace, highlighting.
  List<IdeMenuEntry> _settings() {
    final l10n = context.l10n;
    final options = IdeDiffOptions.instance;
    IdeMenuAction layout(String label, IdeDiffLayout value) => IdeMenuAction(
      label,
      checked: options.layout == value,
      onSelected: () => options.layout = value,
    );
    IdeMenuAction whitespace(String label, IdeDiffWhitespace value) =>
        IdeMenuAction(
          label,
          checked: options.whitespace == value,
          onSelected: () => options.whitespace = value,
        );
    IdeMenuAction highlight(String label, DiffHighlight value) => IdeMenuAction(
      label,
      checked: options.highlight == value,
      onSelected: () => options.highlight = value,
    );
    return ideMenuGroups([
      [
        layout(l10n.diffLayoutAuto, IdeDiffLayout.auto),
        layout(l10n.diffSideBySide, IdeDiffLayout.sideBySide),
        layout(l10n.diffUnified, IdeDiffLayout.unified),
      ],
      [
        whitespace(l10n.diffWhitespaceNone, IdeDiffWhitespace.none),
        whitespace(l10n.diffIgnoreWhitespace, IdeDiffWhitespace.trim),
        whitespace(l10n.diffIgnoreAllWhitespace, IdeDiffWhitespace.all),
      ],
      [
        IdeMenuAction(
          l10n.diffCollapseUnchanged,
          checked: options.collapseUnchanged,
          onSelected: () =>
              options.collapseUnchanged = !options.collapseUnchanged,
        ),
      ],
      [
        highlight(l10n.diffHighlightWords, DiffHighlight.words),
        highlight(l10n.diffHighlightCharacters, DiffHighlight.characters),
        highlight(l10n.diffHighlightLines, DiffHighlight.lines),
        highlight(l10n.diffHighlightNone, DiffHighlight.none),
      ],
    ]);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final hardware = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.escape && event is KeyDownEvent) {
      widget.onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f7) {
      _stepChange(hardware.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    final int? step = switch (key) {
      LogicalKeyboardKey.arrowUp when hardware.isAltPressed => -1,
      LogicalKeyboardKey.arrowDown when hardware.isAltPressed => 1,
      _ => null,
    };
    if (step == null) return KeyEventResult.ignored;
    widget.onStep(step);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final diff = widget.diff;
    final paths = widget.paths;
    final border = widget.border;
    final onStep = widget.onStep;
    final onClose = widget.onClose;
    final file = diff.file;
    final relative = paths.relative(file.path, from: widget.root);
    final directory = paths.dirname(relative);
    final description = IdeListColors.description;
    return Focus(
      focusNode: _focus,
      onKeyEvent: _onKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 32,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Narrow: the counts and the sides' labels go first.
                final wide = constraints.maxWidth >= 620;
                return Row(
                  children: [
                    // Go to Changed File, from its name.
                    Flexible(
                      child: Builder(
                        builder: (anchor) => _Pressable(
                          enabled: diff.files.length > 1,
                          tooltip: l10n.diffGoToFile,
                          onTap: () => unawaited(_goToFile(anchor)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FileIcon(file.path),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      if (directory != '.')
                                        TextSpan(
                                          text: '$directory${paths.separator}',
                                          style: TextStyle(color: description),
                                        ),
                                      TextSpan(
                                        text: paths.basename(file.path),
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: IdeListColors.foreground,
                                        ),
                                      ),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (diff.files.length > 1) ...[
                                const SizedBox(width: 2),
                                Icon(
                                  Codicons.chevronDown,
                                  size: 14,
                                  color: description,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (wide &&
                        (file.originalLabel.isNotEmpty ||
                            file.modifiedLabel.isNotEmpty)) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          [
                            if (file.originalLabel.isNotEmpty)
                              file.originalLabel,
                            if (file.modifiedLabel.isNotEmpty)
                              file.modifiedLabel,
                          ].join('  ↔  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: description),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // The differences: which, of how many; F7 and Shift+F7.
                    if (wide)
                      ValueListenableBuilder(
                        valueListenable: _position,
                        builder: (context, position, _) => Padding(
                          padding: const EdgeInsets.only(right: 2),
                          child: Text(
                            position.current < 0 || position.count == 0
                                ? l10n.diffDifferences(position.count)
                                : l10n.diffDifferenceOf(
                                    position.current + 1,
                                    position.count,
                                  ),
                            style: TextStyle(fontSize: 12, color: description),
                          ),
                        ),
                      ),
                    IdeActionButton(
                      icon: Codicons.arrowUp,
                      tooltip: '${l10n.diffPreviousDifference} (⇧F7)',
                      onPressed: () => _stepChange(-1),
                    ),
                    IdeActionButton(
                      icon: Codicons.arrowDown,
                      tooltip: '${l10n.diffNextDifference} (F7)',
                      onPressed: () => _stepChange(1),
                    ),
                    _ToolbarSeparator(color: border),
                    if (diff.files.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Text(
                          '${diff.index + 1} / ${diff.files.length}',
                          style: TextStyle(fontSize: 12, color: description),
                        ),
                      ),
                    IdeActionButton(
                      icon: Codicons.arrowLeft,
                      tooltip: '${l10n.gitLogPreviousFile} ($_alt↑)',
                      onPressed: diff.index > 0 ? () => onStep(-1) : null,
                    ),
                    IdeActionButton(
                      icon: Codicons.arrowRight,
                      tooltip: '${l10n.gitLogNextFile} ($_alt↓)',
                      onPressed: diff.index < diff.files.length - 1
                          ? () => onStep(1)
                          : null,
                    ),
                    _ToolbarSeparator(color: border),
                    IdeMenuButton(
                      icon: Codicons.settingsGear,
                      tooltip: l10n.diffSettings,
                      entries: _settings,
                    ),
                    if (file.onOpenInEditor case final open?)
                      IdeActionButton(
                        icon: Codicons.goToFile,
                        tooltip: l10n.gitLogOpenInEditor,
                        onPressed: open,
                      ),
                    IdeActionButton(
                      icon: Codicons.close,
                      tooltip: '${l10n.gitLogBackToLog} (Esc)',
                      onPressed: onClose,
                    ),
                  ],
                );
              },
            ),
          ),
          Expanded(
            // The file before stays until this one is read, compared and
            // collapsed, scrolled to its change and colored: not each step
            // in turn (the whole text, then its unchanged lines hidden).
            child: ShownWhenReady(
              child: _DiffBody(
                key: ValueKey(file),
                file: file,
                start: diff.start,
                code: _codeOf(file),
                position: _position,
                onAsk: switch (widget.onAsk) {
                  final ask? => (change, line) => ask(
                    context.l10n.gitAskAiHunkPrompt(
                      widget.paths.relative(file.path, from: widget.root),
                      line,
                      change,
                    ),
                  ),
                  null => null,
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reads a file's two sides, then compares them.
class _DiffBody extends StatefulWidget {
  const _DiffBody({
    super.key,
    required this.file,
    required this.start,
    required this.code,
    required this.position,
    this.onAsk,
  });

  final IdeGitDiffFile file;
  final void Function(String change, int line)? onAsk;
  final IdeDiffStart start;
  final GlobalKey<IdeCodeDiffState> code;
  final ValueNotifier<({int current, int count})> position;

  @override
  State<_DiffBody> createState() => _DiffBodyState();
}

class _DiffBodyState extends State<_DiffBody> {
  late final Future<(String, String)> _texts = () async {
    final texts = await Future.wait([
      widget.file.original(),
      widget.file.modified(),
    ]);
    return (texts[0], texts[1]);
  }();

  /// Not shown while it reads: the diff holds it then (see IdeCodeDiff).
  VoidCallback? _release;

  @override
  void initState() {
    super.initState();
    _release = ShownWhenReady.hold(context);
    _texts.whenComplete(_released).ignore();
  }

  void _released() {
    _release?.call();
    _release = null;
  }

  @override
  void dispose() {
    _released();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<(String, String)>(
    future: _texts,
    builder: (context, texts) {
      if (texts.hasError) return _Placeholder('${texts.error}');
      final data = texts.data;
      if (data == null) {
        return const Center(child: _Spinner(size: 16));
      }
      return IdeCodeDiff(
        key: widget.code,
        path: widget.file.path,
        original: data.$1,
        modified: data.$2,
        start: widget.start,
        onEdit: widget.file.write,
        position: widget.position,
        checks: widget.file.checks,
        agent: widget.file.agent,
        onAsk: widget.onAsk,
      );
    },
  );
}

/// A thin line between groups of a toolbar's buttons.
class _ToolbarSeparator extends StatelessWidget {
  const _ToolbarSeparator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 16,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: color,
  );
}

/// [child], pressed as a button (hovered, with [tooltip]) while [enabled].
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.enabled,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: _hover ? themeColors['toolbar.hoverBackground'] : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// What is being read: the loading codicon, turning.
class _Spinner extends StatelessWidget {
  const _Spinner({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => IdeSpinning(
    Icon(Codicons.loading, size: size, color: IdeListColors.description),
  );
}

/// A line of text in the middle of what is empty.
class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: IdeListColors.description),
      ),
    ),
  );
}

/// A filter's button: its label (and icon), and a chevron when it opens a
/// menu ([entries]); highlighted when it narrows the log ([active]).
class _DropButton extends StatefulWidget {
  const _DropButton({
    required this.label,
    required this.tooltip,
    this.icon,
    this.entries,
    this.onPressed,
    this.active = false,
    this.maxWidth = 180,
    this.trailing,
  });

  final String label;
  final String tooltip;
  final IconData? icon;
  final FutureOr<List<IdeMenuEntry>> Function()? entries;
  final VoidCallback? onPressed;
  final bool active;
  final double maxWidth;

  /// After the label: ✦ where the agent works.
  final IconData? trailing;

  @override
  State<_DropButton> createState() => _DropButtonState();
}

class _DropButtonState extends State<_DropButton> {
  bool _hover = false;
  bool _open = false;

  Future<void> _tap() async {
    if (widget.onPressed case final pressed?) return pressed();
    final make = widget.entries;
    if (make == null) return;
    final entries = await make();
    if (!mounted) return;
    final box = context.findRenderObject()! as RenderBox;
    setState(() => _open = true);
    await showIdeMenu(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
      entries: entries,
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.entries != null || widget.onPressed != null;
    final colors = themeColors;
    final foreground = widget.active
        ? colors['textLink.foreground']
        : IdeListColors.foreground;
    return IdeHover(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: enabled ? () => unawaited(_tap()) : null,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: _open
                  ? IdeActionButton.activeBackground
                  : _hover && enabled
                  ? IdeActionButton.hoverBackground
                  : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon case final icon?) ...[
                  Icon(icon, size: 14, color: foreground),
                  const SizedBox(width: 4),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: widget.maxWidth),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: foreground),
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 3),
                  Icon(
                    Codicons.sparkle,
                    size: 12,
                    color: colors['textLink.foreground'],
                  ),
                ],
                if (widget.entries != null) ...[
                  const SizedBox(width: 2),
                  Icon(Codicons.chevronDown, size: 14, color: foreground),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] with [count] in a small badge at its corner, when there is one
/// (the commits to pull or to push).
class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;
    final colors = themeColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -2,
          top: -1,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(minWidth: 13),
              height: 13,
              padding: const EdgeInsets.symmetric(horizontal: 3),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors['activityBarBadge.background'],
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: colors['activityBarBadge.foreground'],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A row of the table that is not a commit: what is being read, or that
/// nothing matches, with a way out ([action]).
class _Message extends StatelessWidget {
  const _Message({
    required this.text,
    this.spinning = false,
    this.action,
    this.onAction,
  });

  final String text;
  final bool spinning;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final description = IdeListColors.description;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (spinning) ...[const _Spinner(size: 14), const SizedBox(width: 6)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: description),
          ),
        ),
        if (action case final action?) ...[
          const SizedBox(width: 8),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onAction,
              child: Text(
                action,
                style: TextStyle(
                  fontSize: 12,
                  color: themeColors['textLink.foreground'],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// ✦: the agent works here.
class _AgentMark extends StatelessWidget {
  const _AgentMark();

  @override
  Widget build(BuildContext context) => IdeHover(
    message: context.l10n.gitLogAgentHere,
    child: Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        Codicons.sparkle,
        size: 13,
        color: themeColors['textLink.foreground'],
      ),
    ),
  );
}

/// An author's picture: their initial on a color of their own.
class _Avatar extends StatelessWidget {
  const _Avatar(this.name, this.email, {required this.size});

  final String name;
  final String email;
  final double size;

  @override
  Widget build(BuildContext context) {
    final key = (email.isEmpty ? name : email).toLowerCase();
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final lanes = IdeGraphColors.lanes;
    final color = themeColors[lanes[hash % lanes.length]];
    final initial = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first).toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * .5,
          height: 1,
          fontWeight: FontWeight.w600,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

/// The local changes' circle: hollow and dashed, at [lane]; with [down],
/// a dashed line on down to HEAD's.
class _WorkingTreePainter extends CustomPainter {
  const _WorkingTreePainter({
    required this.lane,
    required this.down,
    required this.color,
  });

  final int lane;
  final bool down;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = ideGraphLaneWidth * (lane + 1);
    final cy = size.height / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    canvas.drawCircle(Offset(x, cy), 4.5, paint);
    if (!down) return;
    for (var y = cy + 6; y < size.height; y += 4) {
      canvas.drawLine(
        Offset(x, y),
        Offset(x, math.min(y + 2, size.height)),
        paint..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_WorkingTreePainter oldDelegate) =>
      oldDelegate.lane != lane ||
      oldDelegate.down != down ||
      oldDelegate.color != color;
}

/// A commit's circle where the log is filtered, its lanes not joining up.
class _DotPainter extends CustomPainter {
  const _DotPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    Offset(ideGraphLaneWidth, size.height / 2),
    4,
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_DotPainter oldDelegate) => oldDelegate.color != color;
}

/// Shown at the end of the table: older commits load.
class _LoadMore extends StatefulWidget {
  const _LoadMore({super.key, required this.onShown});

  final VoidCallback onShown;

  @override
  State<_LoadMore> createState() => _LoadMoreState();
}

class _LoadMoreState extends State<_LoadMore> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onShown();
    });
  }

  @override
  Widget build(BuildContext context) => const Center(child: _Spinner(size: 14));
}

/// The line between the table and the details, dragged to size them:
/// across ([vertical]) where they are one under the other. What it sizes
/// goes by how far the pointer is from where the drag began, so that the
/// line stays under it, back from past where the size stops too; while
/// dragged, the cursor is its own over the whole window (VS Code's drag
/// shield).
class _Sash extends StatefulWidget {
  const _Sash({
    required this.vertical,
    required this.color,
    required this.size,
    required this.onResize,
    this.after = false,
  });

  final bool vertical;
  final Color color;

  /// The size of what it sizes, now: the part before it, or ([after]) the
  /// one after it.
  final double size;
  final bool after;

  /// What it sizes, sized anew.
  final ValueChanged<double> onResize;

  @override
  State<_Sash> createState() => _SashState();
}

class _SashState extends State<_Sash> {
  bool _hover = false;
  bool _dragging = false;

  /// Where the drag began, and the size then.
  double _start = 0;
  double _startSize = 0;

  OverlayEntry? _shield;

  MouseCursor get _cursor => widget.vertical
      ? SystemMouseCursors.resizeRow
      : SystemMouseCursors.resizeColumn;

  double _along(Offset position) => widget.vertical ? position.dy : position.dx;

  void _begin(DragStartDetails details) {
    _start = _along(details.globalPosition);
    _startSize = widget.size;
    setState(() => _dragging = true);
    if (Overlay.maybeOf(context) case final overlay?) {
      _shield = OverlayEntry(
        builder: (context) => MouseRegion(cursor: _cursor, opaque: true),
      );
      overlay.insert(_shield!);
    }
  }

  void _update(DragUpdateDetails details) {
    final moved = _along(details.globalPosition) - _start;
    widget.onResize(_startSize + (widget.after ? -moved : moved));
  }

  void _end() {
    _removeShield();
    if (mounted) setState(() => _dragging = false);
  }

  void _removeShield() {
    _shield
      ?..remove()
      ..dispose();
    _shield = null;
  }

  @override
  void dispose() {
    _removeShield();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.vertical;
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: _cursor,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onVerticalDragStart: vertical ? _begin : null,
        onVerticalDragUpdate: vertical ? _update : null,
        onVerticalDragEnd: vertical ? (_) => _end() : null,
        onVerticalDragCancel: vertical ? _end : null,
        onHorizontalDragStart: vertical ? null : _begin,
        onHorizontalDragUpdate: vertical ? null : _update,
        onHorizontalDragEnd: vertical ? null : (_) => _end(),
        onHorizontalDragCancel: vertical ? null : _end,
        child: SizedBox(
          width: vertical ? null : 5,
          height: vertical ? 5 : null,
          child: Center(
            child: Container(
              width: vertical ? null : (active ? 3 : 1),
              height: vertical ? (active ? 3 : 1) : null,
              color: active ? IdeModernUI.sashHover : widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Edit Commit Message in a commit's details: the message in a box to
/// edit, saved with the button or Ctrl/Cmd+Enter, left with Escape.
class _MessageEditor extends StatefulWidget {
  const _MessageEditor({
    required this.message,
    required this.border,
    required this.onSave,
    required this.onCancel,
  });

  final String message;
  final Color border;
  final Future<void> Function(String message) onSave;
  final VoidCallback onCancel;

  @override
  State<_MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<_MessageEditor> {
  late final TextEditingController _text = TextEditingController(
    text: widget.message,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'commit message edit');
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Past the menu's giving the focus back to where it was.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onSave(_text.text);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeInputBox(
          controller: _text,
          focusNode: _focus,
          minLines: 3,
          maxLines: 10,
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): _save,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _save,
            const SingleActivator(LogicalKeyboardKey.escape): widget.onCancel,
          },
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IdeButton(
              label: l10n.commonCancel,
              secondary: true,
              onPressed: _saving ? null : widget.onCancel,
            ),
            const SizedBox(width: 6),
            IdeButton(
              label: l10n.commonSave,
              spinning: _saving,
              onPressed: _saving ? null : () => unawaited(_save()),
            ),
          ],
        ),
      ],
    );
  }
}

/// The commits selected together, in the details' place: how many, and
/// each one's id and subject.
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({required this.commits});

  final List<IdeGitCommit> commits;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final description = IdeListColors.description;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      children: [
        Text(
          l10n.gitLogCommitsSelected(commits.length),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: IdeListColors.foreground,
          ),
        ),
        const SizedBox(height: 8),
        for (final commit in commits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${commit.shortId}  ',
                    style: TextStyle(color: description),
                  ),
                  TextSpan(text: commit.subject),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: IdeListColors.foreground),
            ),
          ),
      ],
    );
  }
}
