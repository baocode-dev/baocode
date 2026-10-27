// The local changes as JetBrains IDEs' Commit tool window has them: a tree
// of the changes whose files are checked to be committed (the tracked ones
// at first, the unversioned ones not), as Changes, Unversioned Files and
// Merge Conflicts (under each repository's name where there are several);
// a toolbar over it (Refresh, Rollback, Show Diff, Group by Directory,
// Expand All, Collapse All); under it, Amend, the commit message, and
// Commit and Commit and Push. No staging: the files checked are committed
// as they are in the working tree (`git commit --only -- <paths>`).
//
// A file clicked shows its changes (in the Git log's table's place); a
// double click, Enter or Jump to Source opens it in the editor. Space
// checks and unchecks the row focused; Left and Right fold and unfold.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../base/smooth_scroll.dart';
import '../../chat/composer/composer_files.dart';
import '../../chat/composer/file_drag.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../ide_button.dart';
import '../ide_dialog.dart';
import '../ide_hover.dart';
import '../ide_spinning.dart';
import '../ide_input.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import '../ide_notifications.dart';
import 'commit_message.dart';
import 'git_changelists.dart';
import 'git_model.dart';
import 'git_partial.dart';
import 'git_review.dart';
import 'git_repository.dart';
import 'git_service.dart';
import 'ide_git_log_view.dart' show IdeGitDiffFile;
import 'ide_git_merge_dialog.dart';
import 'ide_git_stash_view.dart';
import 'ide_scm_view.dart' show IdeScmSession;
import 'scm_host.dart';
import 'scm_tree.dart';

class IdeGitCommitPanel extends StatefulWidget {
  const IdeGitCommitPanel({
    super.key,
    required this.host,
    required this.session,
    this.sessionOf,
    required this.notifications,
    required this.onOpen,
    required this.onOpenChange,
    this.onRevealInExplorer,
    this.revealInExplorerLabel,
    this.onAddToChat,
    this.trash,
    this.commitMessage,
    this.onTreeViewChanged,
    this.hunks,
    this.changelists,
    this.onShowDiff,
    this.onOpenAt,
    this.onAsk,
  });

  /// Puts a request about changes in the chat's composer (Ask AI); not
  /// offered when null.
  final ValueChanged<String>? onAsk;

  /// Opens a file in the editor at a line (a review's problem); [onOpen]
  /// at its top when null.
  final Future<void> Function(String path, int line)? onOpenAt;

  /// The IDE's workspace, or the chat window's side panel's project.
  final IdeScmHost host;

  /// The session of the repository shown: the commit message, Amend, and
  /// how the tree shows.
  final IdeScmSession session;

  /// Another repository's session, for its check marks and folds; [session]
  /// for all when null.
  final IdeScmSession Function(IdeGitRepository git)? sessionOf;
  final IdeNotifications notifications;

  /// Opens a file in the editor (Jump to Source).
  final Future<void> Function(String path, {bool focusEditor}) onOpen;

  /// Shows a change: its diff, where the host shows one ([focusEditor]: in
  /// the editor, to edit).
  final Future<void> Function(
    IdeGitResource resource, {
    bool head,
    bool focusEditor,
  })
  onOpenChange;

  /// Reveals a file in the explorer; not offered when null.
  final ValueChanged<String>? onRevealInExplorer;
  final String? revealInExplorerLabel;

  /// Puts files in the chat's composer; not offered when null.
  final ValueChanged<List<ComposerFile>>? onAddToChat;

  /// Moves a file to the Trash (true once it did); untracked files rolled
  /// back are deleted where it is null.
  final Future<bool> Function(String path)? trash;

  /// Writes commit messages (the sparkle); none offered when null.
  final IdeCommitMessageModel? commitMessage;

  /// Told when Group by Directory is turned on or off, to remember it.
  final ValueChanged<bool>? onTreeViewChanged;

  /// The changes left unchecked in the diffs' check boxes: a file with
  /// some is committed in part. None offered when null.
  final IdeGitHunkSelection? hunks;

  /// The changelists the changes are sorted into; one list when null.
  final IdeGitChangelists? changelists;

  /// Shows files' changes in the log's place, from the one at the index:
  /// the Stash tab's, offered with it.
  final void Function(List<IdeGitDiffFile> files, int index)? onShowDiff;

  static const rowHeight = 22.0;

  @override
  State<IdeGitCommitPanel> createState() => IdeGitCommitPanelState();
}

/// Where a change is listed; the ignored files, where they are shown.
enum _Kind { conflicts, changes, unversioned, ignored }

/// A row of the tree: a repository's (where there are several), a group's,
/// a folder's or a file's.
sealed class _Row {
  _Row(this.git, this.depth);

  final IdeGitRepository git;
  final int depth;

  String get key;

  /// The files under it (its own, for a file's).
  List<IdeGitResource> get files;

  /// Its parent's key; null at the top.
  String? parent;
}

final class _RepoRow extends _Row {
  _RepoRow(IdeGitRepository git, this.files) : super(git, 0);

  @override
  final List<IdeGitResource> files;

  @override
  String get key => 'r:${git.service.root}';
}

final class _GroupRow extends _Row {
  _GroupRow(super.git, this.kind, this.files, super.depth, {this.list});

  final _Kind kind;

  /// The changelist it is, where there are several.
  final String? list;

  @override
  final List<IdeGitResource> files;

  @override
  String get key => 'g:${git.service.root}:${_section(kind, list)}';
}

/// Where in the tree a row is: its kind's group, or a changelist's.
String _section(_Kind kind, String? list) =>
    list == null ? kind.name : '${kind.name}:$list';

final class _FolderRow extends _Row {
  _FolderRow(
    super.git,
    this.kind,
    this.folder,
    this.files,
    super.depth, {
    this.list,
  });

  final _Kind kind;
  final String? list;
  final IdeScmTreeFolder folder;

  @override
  final List<IdeGitResource> files;

  @override
  String get key =>
      'f:${git.service.root}:${_section(kind, list)}:${folder.path}';
}

final class _FileRow extends _Row {
  _FileRow(super.git, this.kind, this.resource, super.depth, {this.list});

  final _Kind kind;
  final String? list;
  final IdeGitResource resource;

  @override
  List<IdeGitResource> get files => [resource];

  @override
  String get key =>
      'x:${git.service.root}:${_section(kind, list)}:${resource.path}';
}

class IdeGitCommitPanelState extends State<IdeGitCommitPanel>
    with IdeKeyboardList<IdeGitCommitPanel> {
  final FocusNode _listFocus = FocusNode(debugLabel: 'commit changes');
  final FocusNode _inputFocus = FocusNode(debugLabel: 'commit message');
  final ScrollController _scroll = SmoothScrollController();

  /// The row focused, by key: kept in the session, where it was when the
  /// panel comes back.
  String? get _selected => _session.listSelected;
  set _selected(String? key) => _session.listSelected = key;
  IdeInputValidation? _validation;
  bool _committing = false;

  /// The tree's height above the message, as dragged; null for its
  /// default.
  double? _treeHeight;

  IdeScmSession get _session => widget.session;
  IdeGitRepository? get _git => widget.host.git;

  /// The Stash tab shown, not the changes.
  bool _stashTab = false;
  final GlobalKey<IdeGitStashViewState> _stashKey = GlobalKey();

  IdeScmSession _sessionOf(IdeGitRepository git) =>
      identical(git, _git) ? _session : widget.sessionOf?.call(git) ?? _session;

  /// The repositories listed: each of the host's, else its one.
  List<IdeGitRepository> get _repositories {
    final repositories = widget.host.repositories;
    if (repositories.isEmpty) return [?_git];
    return [for (final (_, git) in repositories) git];
  }

  @override
  void initState() {
    super.initState();
    _messageText = _session.message.text;
    _session.message.addListener(_messageChanged);
    _listFocus.addListener(_rebuild);
    _inputFocus.addListener(_rebuild);
    widget.hunks?.addListener(_rebuild);
    widget.changelists?.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(IdeGitCommitPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.session, widget.session)) {
      oldWidget.session.message.removeListener(_messageChanged);
      widget.session.message.addListener(_messageChanged);
      _messageText = widget.session.message.text;
      _validation = null;
    }
    if (!identical(oldWidget.hunks, widget.hunks)) {
      oldWidget.hunks?.removeListener(_rebuild);
      widget.hunks?.addListener(_rebuild);
    }
    if (!identical(oldWidget.changelists, widget.changelists)) {
      oldWidget.changelists?.removeListener(_rebuild);
      widget.changelists?.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    _session.message.removeListener(_messageChanged);
    widget.hunks?.removeListener(_rebuild);
    widget.changelists?.removeListener(_rebuild);
    _listFocus.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  /// The message's text last seen: the caret moving alone (as when the
  /// input takes the focus) leaves the validation shown.
  String? _messageText;

  void _messageChanged() {
    final text = _session.message.text;
    if (text == _messageText) return;
    _messageText = text;
    final problems = ideGitMessageProblems(text);
    if (_validation != null || !listEquals(problems, _problems)) {
      setState(() {
        _validation = null;
        _problems = problems;
      });
    }
  }

  /// What the commit message inspections find in the message.
  List<IdeGitMessageProblem> _problems = const [];

  /// The validation shown: the commit's, else (as the message is written)
  /// what the inspections find.
  IdeInputValidation? get _shownValidation {
    if (_validation case final validation?) return validation;
    if (_problems.isEmpty || !_inputFocus.hasFocus) return null;
    final l10n = context.l10n;
    return IdeInputValidation(
      [
        for (final problem in _problems)
          switch (problem) {
            IdeGitMessageProblem.longSubject => l10n.gitCommitLongSubject(
              ideGitSubjectLimit,
            ),
            IdeGitMessageProblem.noBlankLine => l10n.gitCommitNoBlankLine,
          },
      ].join('\n'),
      IdeValidationSeverity.warning,
    );
  }

  final GlobalKey _messageKey = GlobalKey();

  /// JetBrains' commit message history (Ctrl+M): the messages committed
  /// with here, then the user's last commits', one put in the input.
  Future<void> _messageHistory() async {
    final git = _git;
    final box = _messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (git == null || box == null) return;
    final l10n = context.l10n;
    final logged = await git.service.recentMessages().catchError(
      (Object _) => const <String>[],
    );
    if (!mounted) return;
    final messages = {..._session.recentMessages, ...logged}.toList();
    String label(String message) {
      final subject = message.split('\n').first.trim();
      return subject.length > 80 ? '${subject.substring(0, 79)}…' : subject;
    }

    await showIdeMenu(
      context,
      position: box.localToGlobal(Offset.zero),
      entries: [
        if (messages.isEmpty)
          IdeMenuAction(l10n.gitCommitNoMessageHistory, enabled: false),
        for (final message in messages.take(20))
          IdeMenuAction(
            label(message),
            onSelected: () {
              _session.message.value = TextEditingValue(
                text: message,
                selection: TextSelection.collapsed(offset: message.length),
              );
              _inputFocus.requestFocus();
            },
          ),
      ],
    );
  }

  /// JetBrains' commit options: the author, Sign-off, Run Git Hooks.
  Future<void> _commitOptions(Offset position) {
    final l10n = context.l10n;
    return showIdeMenu(
      context,
      position: position,
      entries: [
        IdeMenuAction(
          _session.author == null
              ? l10n.gitCommitAuthor
              : l10n.gitCommitAuthorIs(_session.author!),
          onSelected: () => unawaited(_setAuthor()),
        ),
        if (_session.author != null)
          IdeMenuAction(
            l10n.gitCommitAuthorReset,
            onSelected: () => setState(() => _session.author = null),
          ),
        const IdeMenuSeparator(),
        IdeMenuAction(
          l10n.gitCommitSignOff,
          checked: _session.signOff,
          onSelected: () =>
              setState(() => _session.signOff = !_session.signOff),
        ),
        IdeMenuAction(
          l10n.gitCommitRunHooks,
          checked: _session.runHooks,
          onSelected: () =>
              setState(() => _session.runHooks = !_session.runHooks),
        ),
        if (widget.commitMessage != null)
          IdeMenuAction(
            l10n.gitReviewBeforeCommit,
            checked: _session.aiReview,
            onSelected: () =>
                setState(() => _session.aiReview = !_session.aiReview),
          ),
      ],
    );
  }

  /// The next commit's author, as `Name <email>`.
  Future<void> _setAuthor() async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitCommitAuthor,
      buttons: [l10n.commonOk],
      inputs: [
        IdeDialogInput(
          placeholder: l10n.gitCommitAuthorPlaceholder,
          value: _session.author ?? '',
        ),
      ],
      type: IdeDialogType.question,
    );
    if (result == null || result.button != 0 || !mounted) return;
    final author = result.values.first.trim();
    setState(() => _session.author = author.isEmpty ? null : author);
  }

  // --- What the workbench asks of it ---------------------------------------

  /// Whether the commit message has the keyboard (`scmRepository`).
  bool get inputHasFocus => _inputFocus.hasFocus;

  bool get hasValidation => _validation != null;

  bool get inputHasSelection {
    final selection = _session.message.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  void clearValidation() => setState(() => _validation = null);

  void clearInput() => _session.message.clear();

  /// The tree, where a row was focused; else the commit message.
  void focus() => (_selected == null ? _inputFocus : _listFocus).requestFocus();

  Future<void> commit() => _commit();

  Future<void> fetch() async => _run(() async => _git?.fetch());

  Future<void> fetchAll() => _run(() async {
    for (final git in _repositories) {
      await git.fetch();
    }
  });

  Future<void> pull() => _run(() async => _git?.pull());

  Future<void> push() => _run(() async {
    if (_git case final git?) await ideGitPushOrPublish(git);
  });

  /// [resource]'s conflict in the merge dialog.
  Future<void> _mergeConflict(IdeGitRepository git, IdeGitResource resource) =>
      showIdeGitMergeDialog(
        context,
        git: git,
        resource: resource,
        host: widget.host,
        notifications: widget.notifications,
        ai: widget.commitMessage,
      );

  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
    }
  }

  // --- The changes ---------------------------------------------------------

  /// [state]'s changes by where they are listed: the conflicts, the tracked
  /// changes (once each, staged or not), the unversioned files.
  static Map<_Kind, List<IdeGitResource>> _changesOf(IdeGitState state) {
    final tracked = <String, IdeGitResource>{};
    final unversioned = <IdeGitResource>[];
    for (final resource in state.group(IdeGitGroup.staged)) {
      tracked[resource.path] = resource;
    }
    for (final resource in state.group(IdeGitGroup.workingTree)) {
      if (resource.status == IdeGitStatus.untracked) {
        unversioned.add(resource);
        continue;
      }
      // A file staged then changed again: as it is now, unless what was
      // staged says more (added, renamed, deleted).
      final staged = tracked[resource.path];
      if (staged == null || staged.status == IdeGitStatus.indexModified) {
        tracked[resource.path] = resource;
      }
    }
    int byPath(IdeGitResource a, IdeGitResource b) => a.path.compareTo(b.path);
    return {
      _Kind.conflicts: [...state.group(IdeGitGroup.merge)]..sort(byPath),
      _Kind.changes: tracked.values.toList()..sort(byPath),
      _Kind.unversioned: unversioned..sort(byPath),
    };
  }

  /// Checked as the user left it, else as JetBrains IDEs check a change: a
  /// tracked one, unless it is in a changelist of the user's not active.
  bool _isChecked(IdeGitRepository git, IdeGitResource resource) =>
      _sessionOf(git).included[resource.path] ??
      (resource.status != IdeGitStatus.untracked &&
          !_inListAside(resource.path));

  bool _inListAside(String path) {
    final lists = widget.changelists;
    if (lists == null || !lists.several) return false;
    final list = lists.byId(lists.listOf(path));
    return list != null && list.id != lists.active && !list.turn;
  }

  /// Whether [files] are checked: all (true), none (false), or some (null),
  /// as a file some of whose changes are left out is.
  bool? _checkedOf(IdeGitRepository git, List<IdeGitResource> files) {
    var all = true;
    var none = true;
    for (final file in files) {
      if (_isChecked(git, file)) {
        none = false;
        if (_isPartial(file)) all = false;
      } else {
        all = false;
      }
    }
    return all ? true : (none ? false : null);
  }

  void _setChecked(
    IdeGitRepository git,
    Iterable<IdeGitResource> files,
    bool value,
  ) {
    final included = _sessionOf(git).included;
    setState(() {
      for (final file in files) {
        included[file.path] = value;
      }
      _validation = null;
    });
    // Checked or unchecked whole.
    widget.hunks?.clear([for (final file in files) file.path]);
  }

  /// Whether some of [file]'s changes are left out of the commit.
  bool _isPartial(IdeGitResource file) =>
      (widget.hunks?.isPartial(file.path) ?? false) &&
      ideGitPartialCommittable(file);

  /// The files to commit in [git]: the checked ones still changed.
  List<IdeGitResource> _toCommit(IdeGitRepository git) {
    final state = git.state;
    if (state == null) return const [];
    final changes = _changesOf(state);
    return [
      for (final kind in const [_Kind.changes, _Kind.unversioned])
        for (final file in changes[kind]!)
          if (_isChecked(git, file)) file,
    ];
  }

  // --- The tree's rows -----------------------------------------------------

  bool _collapsed(IdeGitRepository git, String key) =>
      _sessionOf(git).collapsedFolders.contains(key);

  void _setCollapsed(_Row row, bool collapsed) {
    final folds = _sessionOf(row.git).collapsedFolders;
    setState(() {
      if (collapsed) {
        folds.add(row.key);
      } else {
        folds.remove(row.key);
      }
    });
  }

  List<_Row> get _rows {
    final repositories = [
      for (final git in _repositories)
        if (git.state != null) git,
    ];
    final several = repositories.length > 1;
    final rows = <_Row>[];
    for (final git in repositories) {
      final state = git.state!;
      final changes = _changesOf(state);
      final all = [for (final files in changes.values) ...files];
      final ignored = _sessionOf(git).showIgnored
          ? _ignoredOf(git)
          : const <IdeGitResource>[];
      if (all.isEmpty && several) continue;
      var depth = 0;
      String? parent;
      if (several) {
        final row = _RepoRow(git, all);
        rows.add(row);
        if (_collapsed(git, row.key)) continue;
        depth = 1;
        parent = row.key;
      }
      final byDirectory = _sessionOf(git).treeView;
      void addGroup(_Kind kind, List<IdeGitResource> files, {String? list}) {
        final group = _GroupRow(git, kind, files, depth, list: list)
          ..parent = parent;
        rows.add(group);
        if (_collapsed(git, group.key)) return;
        if (!byDirectory) {
          for (final file in files) {
            rows.add(
              _FileRow(git, kind, file, depth + 1, list: list)
                ..parent = group.key,
            );
          }
          return;
        }
        void add(List<IdeScmTreeNode> nodes, int depth, String parent) {
          for (final node in nodes) {
            switch (node) {
              case IdeScmTreeFolder():
                final folder = _FolderRow(
                  git,
                  kind,
                  node,
                  _filesUnder(node),
                  depth,
                  list: list,
                )..parent = parent;
                rows.add(folder);
                if (!_collapsed(git, folder.key)) {
                  add(node.children, depth + 1, folder.key);
                }
              case IdeScmTreeFile(:final resource):
                rows.add(
                  _FileRow(git, kind, resource, depth, list: list)
                    ..parent = parent,
                );
            }
          }
        }

        add(
          ideScmTree(state.root, files, paths: git.service.pathContext),
          depth + 1,
          group.key,
        );
      }

      final lists = widget.changelists;
      for (final kind in _Kind.values) {
        final files = kind == _Kind.ignored ? ignored : changes[kind]!;
        if (kind == _Kind.changes && lists != null && lists.several) {
          // Each changelist, the user's even when empty.
          for (final list in lists.lists) {
            final inList = [
              for (final file in files)
                if (lists.listOf(file.path) == list.id) file,
            ];
            if (inList.isEmpty && list.turn) continue;
            addGroup(kind, inList, list: list.id);
          }
          continue;
        }
        if (files.isEmpty) continue;
        addGroup(kind, files);
      }
    }
    _pruneChangelists(repositories);
    return rows;
  }

  /// The changelists told which changes there are, once every repository's
  /// are known: those gone leave their lists.
  void _pruneChangelists(List<IdeGitRepository> known) {
    final lists = widget.changelists;
    if (lists == null || known.length != _repositories.length) return;
    final changed = {
      for (final git in known)
        for (final files in _changesOf(git.state!).values)
          for (final file in files) file.path,
    };
    // After the build: its listeners rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(widget.changelists, lists)) {
        lists.prune(changed);
      }
    });
  }

  static List<IdeGitResource> _filesUnder(IdeScmTreeFolder folder) => [
    for (final node in folder.children)
      ...switch (node) {
        IdeScmTreeFolder() => _filesUnder(node),
        IdeScmTreeFile(:final resource) => [resource],
      },
  ];

  bool _hasChildren(_Row row) => row is! _FileRow;

  // --- Acting --------------------------------------------------------------

  void _select(_Row row, {bool reveal = false}) {
    setState(() => _selected = row.key);
    if (!reveal) return;
    final index = _rows.indexWhere((candidate) => candidate.key == row.key);
    if (index >= 0) {
      ideRevealRow(_scroll, index, rowHeight: IdeGitCommitPanel.rowHeight);
    }
  }

  /// A file's changes: where the host shows them, or ([editor]) in the
  /// editor.
  Future<void> _show(_FileRow row, {bool editor = false}) async {
    if (!identical(row.git, _git)) widget.host.selectRepository(row.git);
    await widget.onOpenChange(row.resource, focusEditor: editor);
  }

  void _toggleCheck(_Row row) {
    if (row is _GroupRow && row.kind == _Kind.conflicts) return;
    if (row is _FileRow && row.kind == _Kind.conflicts) return;
    final files = _checkable(row);
    if (files.isEmpty) return;
    _setChecked(row.git, files, _checkedOf(row.git, files) != true);
  }

  /// The files under [row] that a check mark is for: not the conflicts,
  /// nor the ignored files.
  List<IdeGitResource> _checkable(_Row row) => [
    for (final file in row.files)
      if (file.group != IdeGitGroup.merge &&
          file.status != IdeGitStatus.ignored)
        file,
  ];

  // --- The ignored files ---------------------------------------------------

  /// Each repository's ignored files, for the state they were read in;
  /// read again (shown as they were meanwhile) once it changes.
  final Map<IdeGitRepository, (IdeGitState?, List<IdeGitResource>)> _ignored =
      {};

  /// The ignored folders, ignored whole.
  final Set<String> _ignoredFolders = {};

  List<IdeGitResource> _ignoredOf(IdeGitRepository git) {
    final known = _ignored[git];
    final state = git.state;
    if (known == null || !identical(known.$1, state)) {
      _ignored[git] = (state, known?.$2 ?? const []);
      unawaited(
        git.service.ignoredFiles().then((paths) {
          if (!mounted || !identical(_ignored[git]?.$1, state)) return;
          final separator = git.service.pathContext.separator;
          final files = [
            for (final path in paths)
              IdeGitResource(
                path: path.endsWith(separator)
                    ? path.substring(0, path.length - 1)
                    : path,
                status: IdeGitStatus.ignored,
                group: IdeGitGroup.workingTree,
              ),
          ];
          setState(() {
            _ignored[git] = (state, files);
            for (final path in paths) {
              if (path.endsWith(separator)) {
                _ignoredFolders.add(path.substring(0, path.length - 1));
              }
            }
          });
        }, onError: (Object _) {}),
      );
    }
    return _ignored[git]!.$2;
  }

  /// [paths] (folders among them) added to [git]'s `.gitignore`, from its
  /// top, as JetBrains IDEs add them: `/path`, a folder's ending in `/`.
  Future<void> _ignore(
    IdeGitRepository git,
    List<String> paths, {
    Set<String> folders = const {},
  }) async {
    final pathContext = git.service.pathContext;
    final root = git.service.root;
    // Git's separators, a bracket taken as itself.
    String pattern(String path) => pathContext
        .relative(path, from: root)
        .replaceAllMapped(
          RegExp(r'\\|\['),
          (match) => match[0] == r'\' ? '/' : r'\[',
        );
    final lines = [
      for (final path in paths)
        '/${pattern(path)}${folders.contains(path) ? '/' : ''}',
    ].join('\n');
    await _run(() async {
      await ideAppendLinesToFile(
        widget.host.files,
        pathContext.join(root, '.gitignore'),
        lines,
      );
      await git.refresh(force: true);
    });
  }

  // --- The workbench's list.* commands (IdeKeyboardList) -----------------

  int get _focusedIndex => _rows.indexWhere((row) => row.key == _selected);

  _Row? get _focusedRow {
    final rows = _rows;
    final at = rows.indexWhere((row) => row.key == _selected);
    return at < 0 ? null : rows[at];
  }

  @override
  bool get listHasFocus => _listFocus.hasFocus;

  @override
  int get listLength => _rows.length;

  @override
  int get listFocusedIndex => _focusedIndex;

  @override
  void listFocusAt(int index) {
    final rows = _rows;
    if (rows.isEmpty) return;
    _select(rows[index.clamp(0, rows.length - 1)], reveal: true);
  }

  @override
  int get listPageSize =>
      ideRowsPerPage(_scroll, rowHeight: IdeGitCommitPanel.rowHeight);

  /// Enter: a file's changes in the editor; a group or folder folds.
  @override
  void listSelect() {
    final row = _focusedRow;
    if (row == null) return;
    if (row is _FileRow) {
      unawaited(_show(row, editor: true));
    } else {
      _setCollapsed(row, !_collapsed(row.git, row.key));
    }
  }

  /// Space: as in JetBrains IDEs, checks or unchecks the row.
  @override
  void listToggleExpand() {
    if (_focusedRow case final row?) _toggleCheck(row);
  }

  @override
  void listExpand() {
    final rows = _rows;
    final at = _focusedIndex;
    if (at < 0) return;
    final row = rows[at];
    if (!_hasChildren(row)) return;
    if (_collapsed(row.git, row.key)) {
      _setCollapsed(row, false);
    } else if (at + 1 < rows.length) {
      listFocusAt(at + 1);
    }
  }

  @override
  void listCollapse() {
    final row = _focusedRow;
    if (row == null) return;
    if (_hasChildren(row) && !_collapsed(row.git, row.key)) {
      _setCollapsed(row, true);
    } else if (row.parent case final parent?) {
      final index = _rows.indexWhere((row) => row.key == parent);
      if (index >= 0) listFocusAt(index);
    }
  }

  @override
  void listCollapseAll() => _collapseAll();

  @override
  bool listTreeKey(String key) {
    final rows = _rows;
    final at = _focusedIndex;
    if (at < 0) return false;
    final row = rows[at];
    final open = _hasChildren(row) && !_collapsed(row.git, row.key);
    return switch (key) {
      'treeElementCanCollapse' => open,
      'treeElementCanExpand' =>
        _hasChildren(row) && _collapsed(row.git, row.key),
      'treeElementHasChild' =>
        open && at + 1 < rows.length && rows[at + 1].parent == row.key,
      'treeElementHasParent' => row.parent != null,
      _ => false,
    };
  }

  /// Every group and folder folded.
  void _collapseAll() => setState(() {
    for (final row in _rows) {
      if (_hasChildren(row) && row is! _RepoRow) {
        _sessionOf(row.git).collapsedFolders.add(row.key);
      }
    }
  });

  /// The tree's keys where no workbench routes them (the side panel).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_rows.isEmpty) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        listFocusNext(1);
      case LogicalKeyboardKey.arrowUp:
        listFocusNext(-1);
      case LogicalKeyboardKey.pageDown:
        listFocusPage(1);
      case LogicalKeyboardKey.pageUp:
        listFocusPage(-1);
      case LogicalKeyboardKey.home:
        listFocusFirst();
      case LogicalKeyboardKey.end:
        listFocusLast();
      case LogicalKeyboardKey.arrowRight:
        listExpand();
      case LogicalKeyboardKey.arrowLeft:
        listCollapse();
      case LogicalKeyboardKey.space:
        listToggleExpand();
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        listSelect();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// Commits the files checked in each repository with the message (Amend:
  /// into the last commit); then, with [push], pushes them.
  Future<void> _commit({bool push = false, bool reviewed = false}) async {
    if (_committing || _session.reviewing != null) return;
    final l10n = context.l10n;
    final message = _session.message.text.trim();
    final amend = _session.amend;
    final work = [
      for (final git in _repositories)
        if (_toCommit(git) case final files when files.isNotEmpty) (git, files),
    ];
    if (message.isEmpty && !amend) {
      setState(
        () => _validation = IdeInputValidation(l10n.gitCommitEmptyMessage),
      );
      _inputFocus.requestFocus();
      return;
    }
    if (work.isEmpty && !amend) {
      setState(
        () => _validation = IdeInputValidation(l10n.gitCommitNothingSelected),
      );
      return;
    }
    // Reviewed first, where asked: held back where something is wrong.
    if (!reviewed &&
        _session.aiReview &&
        widget.commitMessage != null &&
        work.isNotEmpty) {
      return _review(hold: push);
    }
    setState(() {
      _committing = true;
      _session.reviewHeldPush = null;
    });
    // In the history, whether the commit is made or not (a hook says no).
    if (message.isNotEmpty) _session.rememberMessage(message);
    final options = _session.commitOptions;
    try {
      if (work.isEmpty) {
        // Amend alone: the last commit's message.
        await _git?.commitResources(
          message,
          const [],
          amend: true,
          options: options,
        );
      }
      for (final (git, files) in work) {
        await _commitIn(git, message, files, amend: amend, options: options);
        _sessionOf(git).included.clear();
        widget.hunks?.clear([for (final file in files) file.path]);
      }
      _session
        ..message.clear()
        ..amend = false
        ..author = null;
      if (push) {
        for (final git in {
          for (final (git, _) in work) git,
          if (work.isEmpty) ?_git,
        }) {
          await ideGitPushOrPublish(git);
        }
      }
    } catch (error) {
      if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  /// Commits [files] in [git]: those some of whose changes are left out
  /// with the others alone (none of a file, where all are left out).
  Future<void> _commitIn(
    IdeGitRepository git,
    String message,
    List<IdeGitResource> files, {
    required bool amend,
    required IdeGitCommitOptions options,
  }) async {
    final hunks = widget.hunks;
    final nothing = context.l10n.gitCommitNothingSelected;
    final partial = <String, String>{};
    final whole = <IdeGitResource>[];
    for (final file in files) {
      if (hunks == null || !_isPartial(file)) {
        whole.add(file);
        continue;
      }
      final (original, modified) = await (
        git.service.show('HEAD', file.path),
        widget.host.files.read(file.path, force: true),
      ).wait;
      final text = await ideGitPartialText(
        original,
        modified,
        hunks.excluded(file.path),
      );
      if (text == modified) {
        whole.add(file);
      } else if (text != original) {
        partial[file.path] = text;
      }
    }
    if (partial.isEmpty && whole.isEmpty && !amend) {
      // Every change left out: `git commit --only` with no paths would
      // commit what is staged.
      throw IdeGitException(nothing);
    }
    if (partial.isEmpty) {
      await git.commitResources(message, whole, amend: amend, options: options);
    } else {
      await git.commitPartial(
        message,
        whole,
        partial,
        amend: amend,
        options: options,
      );
    }
  }

  /// JetBrains' Fixup: [git]'s checked changes committed as a `fixup!` of
  /// [commit], then squashed into it.
  Future<void> fixupInto(IdeGitRepository git, IdeGitCommit commit) async {
    if (_committing) return;
    final l10n = context.l10n;
    final files = _toCommit(git);
    if (files.isEmpty) {
      widget.notifications.notify(
        IdeSeverity.info,
        l10n.gitCommitNothingSelected,
      );
      return;
    }
    setState(() => _committing = true);
    try {
      await _commitIn(
        git,
        'fixup! ${commit.id}',
        files,
        amend: false,
        options: IdeGitCommitOptions(runHooks: _session.runHooks),
      );
      _sessionOf(git).included.clear();
      widget.hunks?.clear([for (final file in files) file.path]);
      await git.autosquash(commit);
    } catch (error) {
      if (mounted) widget.notifications.notify(IdeSeverity.error, '$error');
    } finally {
      if (mounted) setState(() => _committing = false);
    }
  }

  /// Amend checked: the last commit's message in the input, where none is
  /// written yet.
  Future<void> _setAmend(bool value) async {
    setState(() => _session.amend = value);
    final git = _git;
    if (!value || git == null || _session.message.text.trim().isNotEmpty) {
      return;
    }
    final head = await git.headCommit();
    if (!mounted || head == null || !_session.amend) return;
    if (_session.message.text.trim().isNotEmpty) return;
    final text = head.message.trim();
    _session.message.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// Rollback… on [files] of [git], asked first.
  Future<void> _rollback(
    IdeGitRepository git,
    List<IdeGitResource> files,
  ) async {
    if (files.isEmpty) return;
    final l10n = context.l10n;
    final choice = await showIdeDialog(
      context,
      message: l10n.gitCommitRollbackConfirm(files.length),
      detail: l10n.gitCommitRollbackDetail,
      buttons: [l10n.gitCommitRollbackButton],
    );
    if (choice != 0) return;
    await _run(() => git.rollback(files, trash: widget.trash));
  }

  /// The files Rollback acts on from the toolbar: the row focused's, else
  /// the checked ones.
  List<(IdeGitRepository, List<IdeGitResource>)> get _rollbackTargets {
    final rows = _rows;
    final focused = rows.where((row) => row.key == _selected).firstOrNull;
    if (focused != null) return [(focused.git, focused.files)];
    return [
      for (final git in _repositories)
        if (_toCommit(git) case final files when files.isNotEmpty) (git, files),
    ];
  }

  /// What the commit would take of [git] (its checked files' diff): HEAD
  /// against the working tree (with no HEAD yet, what is staged); a file
  /// committed in part, against what of it is.
  Future<String> _commitDiff(IdeGitRepository git, IdeGitState state) async {
    final files = _toCommit(git);
    final unborn = state.head.unborn;
    final partial = [
      if (!unborn)
        for (final file in files)
          if (_isPartial(file)) file,
    ];
    final whole = await git.service.diff(
      staged: unborn,
      paths: unborn
          ? null
          : [
              for (final file in files)
                if (file.status != IdeGitStatus.untracked &&
                    !partial.contains(file))
                  file.path,
            ],
      untracked: [
        for (final file in files)
          if (file.status == IdeGitStatus.untracked) file.path,
      ],
    );
    final parts = StringBuffer();
    for (final file in partial) {
      final (original, modified) = await (
        git.service.show('HEAD', file.path),
        widget.host.files.read(file.path, force: true),
      ).wait;
      final text = await ideGitPartialText(
        original,
        modified,
        widget.hunks!.excluded(file.path),
      );
      parts.write(
        await ideGitUnifiedDiff(
          git.service.pathContext.relative(file.path, from: git.service.root),
          original,
          text,
        ),
      );
    }
    return partial.isEmpty ? whole : '$whole$parts';
  }

  /// The model's review of what the commit would take; [hold], the commit
  /// it holds back (with Push, or not), made at once where nothing blocks
  /// it. Again while it runs, stops it.
  Future<void> _review({bool? hold}) async {
    final model = widget.commitMessage;
    if (model == null) return;
    if (_session.reviewing case final running?) {
      running.complete();
      return;
    }
    final cancel = _session.reviewing = Completer<void>();
    setState(() {
      _session
        ..review = null
        ..reviewHeldPush = null;
    });
    final l10n = context.l10n;
    try {
      final diffs = StringBuffer();
      for (final git in _repositories) {
        final state = git.state;
        if (state == null || _toCommit(git).isEmpty) continue;
        diffs.write(await _commitDiff(git, state));
      }
      if (cancel.isCompleted) return;
      if (diffs.toString().trim().isEmpty) {
        widget.notifications.notify(
          IdeSeverity.info,
          l10n.scmNoChangesToGenerate,
        );
        return;
      }
      final reply = await model(
        ideGitReviewPrompt(diffs.toString(), message: _session.message.text),
        cancel: cancel.future,
      );
      if (cancel.isCompleted || !mounted) return;
      final problems = ideGitReviewProblems(reply);
      if (hold != null && !problems.any((problem) => problem.blocks)) {
        _session.reviewing = null;
        setState(() => _session.review = problems.isEmpty ? null : problems);
        await _commit(push: hold, reviewed: true);
        return;
      }
      setState(() {
        _session
          ..review = problems
          ..reviewHeldPush = hold;
      });
    } on IdeCommitMessageCancelled {
      // Stopped.
    } catch (error) {
      if (!cancel.isCompleted) {
        widget.notifications.notify(
          IdeSeverity.error,
          l10n.gitReviewFailed('$error'),
        );
      }
    } finally {
      if (identical(_session.reviewing, cancel)) _session.reviewing = null;
      if (mounted) setState(() {});
    }
  }

  /// The review under way, or what it found (each problem a click from
  /// its line), and Commit Anyway for the commit it holds back.
  Widget? _reviewBox(BuildContext context) {
    final problems = _session.review;
    final running = _session.reviewing != null;
    if (problems == null && !running) return null;
    final l10n = context.l10n;
    final colors = themeColors;
    final description = IdeListColors.description;
    final held = _session.reviewHeldPush;
    final header = Row(
      children: [
        if (running)
          IdeSpinning(Icon(Codicons.loading, size: 14, color: description))
        else
          Icon(
            problems!.isEmpty ? Codicons.pass : Codicons.checklist,
            size: 14,
            color: problems.isEmpty
                ? colors['testing.iconPassed']
                : description,
          ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            running
                ? l10n.gitReviewRunning
                : problems!.isEmpty
                ? l10n.gitReviewClean
                : l10n.gitReviewFound(problems.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        if (held != null && !running) ...[
          IdeButton(
            label: held
                ? l10n.gitReviewCommitAndPushAnyway
                : l10n.gitReviewCommitAnyway,
            secondary: true,
            onPressed: () => unawaited(_commit(push: held, reviewed: true)),
          ),
          const SizedBox(width: 4),
        ],
        IdeActionButton(
          icon: running ? Codicons.debugStop : Codicons.close,
          tooltip: running ? l10n.gitReviewStop : l10n.dialogCloseDialog,
          size: 20,
          iconSize: 14,
          onPressed: running
              ? () => _session.reviewing?.complete()
              : () => setState(() {
                  _session
                    ..review = null
                    ..reviewHeldPush = null;
                }),
        ),
      ],
    );
    final git = _git;
    return Container(
      constraints: const BoxConstraints(maxHeight: 160),
      padding: const EdgeInsets.fromLTRB(8, 4, 4, 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: colors.get('panel.border') ?? Colors.transparent,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (problems != null && problems.isNotEmpty)
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.only(top: 2),
                children: [
                  for (final problem in problems)
                    IdeListRow(
                      height: 22,
                      tooltip: problem.message,
                      onTap: git == null
                          ? null
                          : () {
                              final path = git.service.pathContext.join(
                                git.service.root,
                                git.service.pathContext.joinAll(
                                  problem.path.split('/'),
                                ),
                              );
                              unawaited(
                                problem.line != null && widget.onOpenAt != null
                                    ? widget.onOpenAt!(path, problem.line!)
                                    : widget.onOpen(path, focusEditor: true),
                              );
                            },
                      builder: (context, hovered) => Row(
                        children: [
                          Icon(
                            switch (problem.severity) {
                              IdeGitReviewSeverity.error => Codicons.error,
                              IdeGitReviewSeverity.warning => Codicons.warning,
                              IdeGitReviewSeverity.info => Codicons.info,
                            },
                            size: 14,
                            color: switch (problem.severity) {
                              IdeGitReviewSeverity.error =>
                                colors['editorError.foreground'],
                              IdeGitReviewSeverity.warning =>
                                colors['editorWarning.foreground'],
                              IdeGitReviewSeverity.info =>
                                colors['editorInfo.foreground'],
                            },
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(text: problem.message),
                                  TextSpan(
                                    text:
                                        '  ${problem.path}${problem.line == null ? '' : ':${problem.line}'}',
                                    style: TextStyle(color: description),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Generates the commit message from what the commit would take (the
  /// checked files' diff); again while it runs, cancels it.
  Future<void> _generateMessage() async {
    final model = widget.commitMessage;
    final git = _git;
    final state = git?.state;
    if (model == null || git == null || state == null) return;
    final l10n = context.l10n;
    if (_session.generating case final running?) {
      running.complete();
      return;
    }
    final cancel = _session.generating = Completer<void>();
    setState(() {});
    try {
      final diff = await _commitDiff(git, state);
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
      _session.message.value = TextEditingValue(
        text: message,
        selection: TextSelection.collapsed(offset: message.length),
      );
    } on IdeCommitMessageCancelled {
      // Cancelled: the message stays as it was.
    } catch (error) {
      if (!cancel.isCompleted) {
        widget.notifications.notify(IdeSeverity.error, '$error');
      }
    } finally {
      if (identical(_session.generating, cancel)) _session.generating = null;
      if (mounted) setState(() {});
    }
  }

  // --- Building ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final repositories = _repositories;
    final git = _git;
    if (git == null) return _Welcome(context.l10n.scmNoProviders);
    return ListenableBuilder(
      listenable: Listenable.merge(repositories),
      builder: (context, _) => !git.loaded
          ? const SizedBox.shrink()
          : git.state == null
          ? _welcome(git)
          : LayoutBuilder(
              builder: (context, constraints) {
                final rows = _rows;
                // The message and its buttons: what is left to the tree, a
                // third at least.
                final treeHeight = math.max(
                  80.0,
                  math.min(
                    _treeHeight ?? constraints.maxHeight * .55,
                    constraints.maxHeight - 170,
                  ),
                );
                if (_stashTab && widget.onShowDiff != null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tabs(context),
                      _stashToolbar(context),
                      Expanded(
                        child: IdeGitStashView(
                          key: _stashKey,
                          repositories: [
                            for (final git in _repositories)
                              (
                                git.service.pathContext.basename(
                                  git.service.root,
                                ),
                                git,
                              ),
                          ],
                          notifications: widget.notifications,
                          onShowDiff: widget.onShowDiff!,
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.onShowDiff != null) _tabs(context),
                    _toolbar(context),
                    if (git.state?.operation case final operation?)
                      _operationBanner(git, operation),
                    // Past Git's status limit: what is listed is not all.
                    if (git.state?.didHitLimit ?? false)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                        child: Text(
                          context.l10n.scmTooManyChanges(
                            IdeGitService.statusLimit,
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: themeColors['editorWarning.foreground'],
                          ),
                        ),
                      ),
                    SizedBox(
                      height: treeHeight,
                      child: rows.isEmpty
                          ? _empty(context)
                          : _tree(context, rows),
                    ),
                    _Divider(
                      onDrag: (delta) =>
                          setState(() => _treeHeight = treeHeight + delta),
                    ),
                    Expanded(child: _commitArea(context)),
                  ],
                );
              },
            ),
    );
  }

  /// JetBrains' Commit and Stash tabs.
  Widget _tabs(BuildContext context) {
    final l10n = context.l10n;
    Widget tab(String label, bool stash) => _PanelTab(
      label: label,
      selected: _stashTab == stash,
      onTap: () => setState(() => _stashTab = stash),
    );
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: themeColors.get('panel.border') ?? Colors.transparent,
          ),
        ),
      ),
      child: Row(
        children: [tab(l10n.gitCommitTab, false), tab(l10n.gitStashTab, true)],
      ),
    );
  }

  /// Over the stashes: Refresh, Stash Changes, Clear.
  Widget _stashToolbar(BuildContext context) {
    final l10n = context.l10n;
    final git = _git;
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IdeActionButton(
              icon: Codicons.refresh,
              tooltip: l10n.commonRefresh,
              onPressed: () => unawaited(git?.refresh(force: true)),
            ),
            IdeActionButton(
              icon: Codicons.gitStash,
              tooltip: l10n.gitStashChangesTitle,
              onPressed: git == null ? null : () => unawaited(_stash(git)),
            ),
            IdeActionButton(
              icon: Codicons.clearAll,
              tooltip: l10n.gitStashClear,
              onPressed: () => unawaited(_stashKey.currentState?.clear()),
            ),
          ],
        ),
      ),
    );
  }

  /// [git]'s changes stashed (only [paths]' where given).
  Future<void> _stash(IdeGitRepository git, {Iterable<String>? paths}) =>
      _run(() => ideGitStashChanges(context, git, paths: paths));

  /// The merge, rebase, cherry-pick or revert Git stopped in: what, how
  /// many conflicts are left, and Continue (once there are none), Skip
  /// and Abort.
  Widget _operationBanner(IdeGitRepository git, IdeGitOperation operation) {
    final l10n = context.l10n;
    final conflicts = git.state?.group(IdeGitGroup.merge).length ?? 0;
    final branch = git.state?.head.branch;
    final what = switch (operation) {
      IdeGitOperation.rebase => l10n.gitOperationRebasing,
      IdeGitOperation.merge => l10n.gitOperationMerging,
      IdeGitOperation.cherryPick => l10n.gitOperationCherryPicking,
      IdeGitOperation.revert => l10n.gitOperationReverting,
    };
    final warning = themeColors['editorWarning.foreground'];
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: .08),
        border: Border.all(color: warning.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Codicons.gitMerge, size: 14, color: warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  [
                    if (branch != null) '$what · $branch' else what,
                    conflicts > 0
                        ? l10n.gitOperationConflicts(conflicts)
                        : l10n.gitOperationResolved,
                  ].join('  —  '),
                  style: TextStyle(
                    fontSize: 12,
                    color: IdeListColors.foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              IdeButton(
                label: l10n.gitOperationContinue,
                onPressed: conflicts > 0
                    ? null
                    : () => unawaited(_run(() => _continue(git))),
              ),
              if (operation.skips)
                IdeButton(
                  label: l10n.gitOperationSkip,
                  secondary: true,
                  onPressed: () =>
                      unawaited(_run(() => git.continueOperation(skip: true))),
                ),
              IdeButton(
                label: l10n.gitOperationAbort,
                secondary: true,
                onPressed: () => unawaited(_abort(git, what)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Continue: what is checked goes into the commit Git goes on with, as
  /// Commit would take it.
  Future<void> _continue(IdeGitRepository git) async {
    await git.continueOperation(
      include: [for (final file in _toCommit(git)) file.path],
    );
    _sessionOf(git).included.clear();
  }

  /// Abort, once confirmed: what was done since it began is undone.
  Future<void> _abort(IdeGitRepository git, String what) async {
    final l10n = context.l10n;
    final answer = await showIdeDialog(
      context,
      message: l10n.gitOperationAbortConfirm(what),
      buttons: [l10n.gitOperationAbort],
    );
    if (answer != 0) return;
    await _run(() => git.continueOperation(abort: true));
  }

  /// Not a repository: why, and Initialize Repository where Git is there.
  Widget _welcome(IdeGitRepository git) {
    final l10n = context.l10n;
    if (git.error case final IdeGitException error
        when error.message.startsWith('Git is')) {
      return _Welcome('${l10n.scmInstallGit}\n\n${error.message}');
    }
    return _Welcome(
      l10n.scmNoRepository,
      button: l10n.scmInitializeRepository,
      onPressed: () => unawaited(_run(git.initialize)),
    );
  }

  Widget _empty(BuildContext context) => Center(
    child: Text(
      context.l10n.gitCommitNoChanges,
      style: TextStyle(fontSize: 12, color: IdeListColors.description),
    ),
  );

  Widget _toolbar(BuildContext context) {
    final l10n = context.l10n;
    final git = _git;
    final rows = _rows;
    final focused = rows.where((row) => row.key == _selected).firstOrNull;
    final byDirectory = git == null ? true : _sessionOf(git).treeView;
    return SizedBox(
      height: 30,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IdeActionButton(
              icon: Codicons.refresh,
              tooltip: l10n.commonRefresh,
              onPressed: () => unawaited(
                _run(() async {
                  for (final git in _repositories) {
                    await git.refresh(force: true);
                  }
                }),
              ),
            ),
            IdeActionButton(
              icon: Codicons.discard,
              tooltip: l10n.gitCommitRollback,
              onPressed: _rollbackTargets.isEmpty
                  ? null
                  : () => unawaited(() async {
                      for (final (git, files) in _rollbackTargets) {
                        await _rollback(git, files);
                      }
                    }()),
            ),
            IdeActionButton(
              icon: Codicons.gitStash,
              tooltip: l10n.gitStashChangesTitle,
              onPressed: git == null || rows.isEmpty
                  ? null
                  : () => unawaited(_stash(git)),
            ),
            IdeActionButton(
              icon: Codicons.diff,
              tooltip: l10n.gitCommitShowDiff,
              // A click shows it in the log's place; this, in the editor.
              onPressed: focused is _FileRow
                  ? () => unawaited(_show(focused, editor: true))
                  : null,
            ),
            const SizedBox(width: 4),
            IdeActionButton(
              icon: Codicons.folder,
              tooltip: l10n.gitCommitGroupByDirectory,
              checked: byDirectory,
              onPressed: () {
                setState(() {
                  for (final git in _repositories) {
                    _sessionOf(git).treeView = !byDirectory;
                  }
                });
                widget.onTreeViewChanged?.call(!byDirectory);
              },
            ),
            IdeActionButton(
              icon: Codicons.expandAll,
              tooltip: l10n.gitCommitExpandAll,
              onPressed: () => setState(() {
                for (final git in _repositories) {
                  _sessionOf(git).collapsedFolders.clear();
                }
              }),
            ),
            IdeActionButton(
              icon: Codicons.collapseAll,
              tooltip: l10n.gitCommitCollapseAll,
              onPressed: _collapseAll,
            ),
            IdeActionButton(
              icon: Codicons.eyeClosed,
              tooltip: l10n.gitCommitShowIgnored,
              checked: _session.showIgnored,
              onPressed: () => setState(() {
                final show = !_session.showIgnored;
                for (final git in _repositories) {
                  _sessionOf(git).showIgnored = show;
                }
              }),
            ),
            const Spacer(),
            if (_repositories.any((git) => git.busy))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IdeSpinning(
                  Icon(
                    Codicons.loading,
                    size: 14,
                    color: IdeListColors.description,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tree(BuildContext context, List<_Row> rows) => Focus(
    focusNode: _listFocus,
    onKeyEvent: _onKey,
    child: ListView.builder(
      controller: _scroll,
      itemExtent: IdeGitCommitPanel.rowHeight,
      itemCount: rows.length,
      itemBuilder: (context, index) => _row(context, rows[index]),
    ),
  );

  Widget _row(BuildContext context, _Row row) {
    final l10n = context.l10n;
    final git = row.git;
    final selected = row.key == _selected;
    final indent = 4.0 + row.depth * 14.0;
    final collapsed = _hasChildren(row) && _collapsed(git, row.key);
    final conflicts =
        (row is _GroupRow && row.kind == _Kind.conflicts) ||
        (row is _FolderRow && row.kind == _Kind.conflicts) ||
        (row is _FileRow && row.kind == _Kind.conflicts);
    final checkable = _checkable(row);
    final check = conflicts || checkable.isEmpty
        ? const SizedBox(width: 18)
        : _Check(
            value: _checkedOf(git, checkable),
            onTap: () {
              _listFocus.requestFocus();
              _select(row);
              _toggleCheck(row);
            },
          );
    final chevron = SizedBox(
      width: 16,
      child: _hasChildren(row)
          ? Icon(
              collapsed ? Codicons.chevronRight : Codicons.chevronDown,
              size: 14,
              color: IdeListColors.foreground,
            )
          : null,
    );
    final count = TextStyle(fontSize: 12, color: IdeListColors.description);
    final Widget content = switch (row) {
      _RepoRow() => Row(
        children: [
          Icon(Codicons.repo, size: 14, color: IdeListColors.foreground),
          const SizedBox(width: 6),
          Flexible(
            child: IdeResourceLabel(
              name: git.service.pathContext.basename(git.service.root),
              description: git.state?.head.branch,
            ),
          ),
          const SizedBox(width: 8),
          Text(l10n.gitLogFileCount(row.files.length), style: count),
        ],
      ),
      _GroupRow(:final kind, :final list) => Row(
        children: [
          if (_changelist(list) case IdeGitChangelist(turn: true)) ...[
            Icon(
              Codicons.sparkle,
              size: 14,
              color: themeColors['textLink.foreground'],
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              switch (kind) {
                _Kind.changes => _changelistName(list),
                _Kind.unversioned => l10n.gitCommitUnversioned,
                _Kind.conflicts => l10n.gitCommitConflicts,
                _Kind.ignored => l10n.gitCommitIgnored,
              },
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: kind == _Kind.conflicts
                    ? themeColors['gitDecoration.conflictingResourceForeground']
                    : IdeListColors.foreground,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(l10n.gitLogFileCount(row.files.length), style: count),
          if (list != null && list == widget.changelists?.active) ...[
            const SizedBox(width: 6),
            Text(l10n.gitChangelistActive, style: count),
          ],
        ],
      ),
      _FolderRow(:final folder) => Row(
        children: [
          FolderIcon(folder.path, expanded: !collapsed),
          const SizedBox(width: 6),
          Flexible(child: IdeResourceLabel(name: folder.label)),
          const SizedBox(width: 8),
          Text('${row.files.length}', style: count),
        ],
      ),
      _FileRow(:final resource) => _fileLabel(git, resource),
    };
    final listRow = IdeListRow(
      key: ValueKey(row.key),
      height: IdeGitCommitPanel.rowHeight,
      selected: selected,
      focused: _listFocus.hasFocus,
      tooltip: switch (row) {
        _FileRow(:final resource) =>
          '${git.service.pathContext.relative(resource.path, from: git.service.root)}'
              ' • ${resource.status.localizedLabel(l10n)}',
        _ => null,
      },
      onTap: () {
        _listFocus.requestFocus();
        _select(row);
        switch (row) {
          case _FileRow():
            unawaited(_show(row));
          // Another repository: the one the log shows; the one shown folds.
          case _RepoRow() when !identical(git, _git):
            widget.host.selectRepository(git);
          case _:
            _setCollapsed(row, !collapsed);
        }
      },
      onDoubleTap: switch (row) {
        // A conflict: its merge, where both sides have the file.
        _FileRow(:final resource)
            when row.kind == _Kind.conflicts && ideGitMergeable(resource) =>
          () => unawaited(_mergeConflict(git, resource)),
        _FileRow() => () => unawaited(_show(row, editor: true)),
        _ => null,
      },
      onContextMenu: (position) {
        _listFocus.requestFocus();
        _select(row);
        unawaited(_menu(context, position, row));
      },
      builder: (context, hovered) => Row(
        children: [
          SizedBox(width: indent),
          chevron,
          check,
          const SizedBox(width: 4),
          Expanded(child: content),
          const SizedBox(width: 8),
        ],
      ),
    );
    // Dragged onto the chat's composer: the file, or the folder, in it.
    final dragged = _composerFiles(row);
    if (dragged.isEmpty) return listRow;
    return FileDraggable(key: listRow.key, files: dragged, child: listRow);
  }

  /// What [row] puts in the chat: a file still there, or a folder itself.
  List<ComposerFile> _composerFiles(_Row row) => switch (row) {
    _FileRow(:final resource)
        when resource.status != IdeGitStatus.deleted &&
            resource.status != IdeGitStatus.indexDeleted =>
      [ComposerFile(resource.path)],
    _FolderRow(:final folder) => [ComposerFile(folder.path, directory: true)],
    _ => const [],
  };

  Widget _fileLabel(IdeGitRepository git, IdeGitResource resource) {
    final paths = git.service.pathContext;
    final byDirectory = _sessionOf(git).treeView;
    final relative = paths.relative(resource.path, from: git.service.root);
    final directory = paths.dirname(relative);
    final status = resource.status;
    return Row(
      children: [
        if (status == IdeGitStatus.ignored &&
            _ignoredFolders.contains(resource.path))
          FolderIcon(resource.path, expanded: false)
        else
          FileIcon(resource.path),
        const SizedBox(width: 6),
        Expanded(
          child: IdeResourceLabel(
            name: paths.basename(resource.path),
            // JetBrains' colors: the name in its status's.
            nameColor: status.color,
            description: byDirectory || directory == '.' ? null : directory,
            strikeThrough: status.strikeThrough,
          ),
        ),
      ],
    );
  }

  IdeGitChangelist? _changelist(String? id) =>
      id == null ? null : widget.changelists?.byId(id);

  /// A changelist's name: the default list's, Changes, until renamed.
  String _changelistName(String? id) => switch (_changelist(id)?.name) {
    final name? when name.isNotEmpty => name,
    _ => context.l10n.gitCommitChanges,
  };

  /// [row]'s changelist entries: a change's move to another list (a new one
  /// too), a list's to make it active, rename or delete it, or commit it
  /// alone.
  List<IdeMenuEntry> _changelistMenu(_Row row) {
    final lists = widget.changelists;
    if (lists == null) return const [];
    final l10n = context.l10n;
    final paths = [
      for (final file in _checkable(row))
        if (file.status != IdeGitStatus.untracked) file.path,
    ];
    final list = switch (row) {
      _GroupRow(kind: _Kind.changes, :final list) => list ?? lists.active,
      _ => null,
    };
    final current = switch (row) {
      _FileRow(:final list) || _FolderRow(:final list) => list,
      _ => null,
    };
    return [
      if (paths.isNotEmpty && row is! _GroupRow && row is! _RepoRow)
        IdeMenuAction(
          l10n.gitChangelistMoveTo,
          submenu: [
            for (final other in lists.lists)
              if (other.id != (current ?? lists.active))
                IdeMenuAction(
                  _changelistName(other.id),
                  onSelected: () => lists.move(paths, other.id),
                ),
            const IdeMenuSeparator(),
            IdeMenuAction(
              l10n.gitChangelistNew,
              onSelected: () => unawaited(_newChangelist(paths)),
            ),
          ],
        ),
      if (list != null) ...[
        if (lists.several && row.files.isNotEmpty)
          IdeMenuAction(
            l10n.gitChangelistCommitOnly,
            onSelected: () => _commitOnly(row),
          ),
        if (lists.several && list != lists.active)
          IdeMenuAction(
            l10n.gitChangelistSetActive,
            onSelected: () => lists.setActive(
              list,
              unassigned: [
                for (final git in _repositories)
                  for (final file in _toCommitOrNot(git)) file.path,
              ],
            ),
          ),
        IdeMenuAction(
          l10n.gitChangelistNew,
          onSelected: () => unawaited(_newChangelist(const [])),
        ),
        if (lists.several) ...[
          IdeMenuAction(
            l10n.gitChangelistRename,
            onSelected: () => unawaited(_renameChangelist(list)),
          ),
          if (list != IdeGitChangelists.defaultId)
            IdeMenuAction(
              l10n.gitChangelistDelete,
              onSelected: () => lists.remove(list),
            ),
        ],
      ],
    ];
  }

  /// Every tracked change of [git]'s, checked or not.
  List<IdeGitResource> _toCommitOrNot(IdeGitRepository git) =>
      switch (git.state) {
        final state? => _changesOf(state)[_Kind.changes]!,
        null => const [],
      };

  /// [row]'s files checked, every other change unchecked: the list's
  /// commit (an agent's turn's, say).
  void _commitOnly(_Row row) {
    final mine = {for (final file in row.files) file.path};
    setState(() {
      for (final git in _repositories) {
        final included = _sessionOf(git).included;
        final state = git.state;
        if (state == null) continue;
        for (final files in _changesOf(state).values) {
          for (final file in files) {
            included[file.path] = mine.contains(file.path);
          }
        }
      }
      _validation = null;
    });
    _inputFocus.requestFocus();
  }

  Future<void> _newChangelist(List<String> paths) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitChangelistNew,
      buttons: [l10n.gitChangelistCreate],
      inputs: [IdeDialogInput(placeholder: l10n.gitChangelistName)],
      type: IdeDialogType.question,
    );
    final name = result?.values.first.trim() ?? '';
    if (result?.button != 0 || name.isEmpty) return;
    widget.changelists?.create(name, paths: paths);
  }

  Future<void> _renameChangelist(String id) async {
    final l10n = context.l10n;
    final result = await showIdeInputDialog(
      context,
      message: l10n.gitChangelistRename,
      buttons: [l10n.gitChangelistRenameButton],
      inputs: [
        IdeDialogInput(
          placeholder: l10n.gitChangelistName,
          value: _changelistName(id),
        ),
      ],
      type: IdeDialogType.question,
    );
    final name = result?.values.first.trim() ?? '';
    if (result?.button != 0 || name.isEmpty) return;
    widget.changelists?.rename(id, name);
  }

  Future<void> _menu(BuildContext context, Offset position, _Row row) {
    final l10n = context.l10n;
    final git = row.git;
    final files = row.files;
    final file = row is _FileRow ? row : null;
    final resource = file?.resource;
    // A file's path, or a folder's.
    final path = switch (row) {
      _FileRow(:final resource) => resource.path,
      _FolderRow(:final folder) => folder.path,
      _RepoRow() => git.service.root,
      _ => null,
    };
    final untracked = [
      for (final file in files)
        if (file.status == IdeGitStatus.untracked) file,
    ];
    final conflicts = [
      for (final file in files)
        if (file.group == IdeGitGroup.merge) file,
    ];
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        // A repository's remotes, as its header in the log's.
        if (row is _RepoRow) ...[
          [
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
              onSelected: () => unawaited(_run(() => ideGitPushOrPublish(git))),
            ),
          ],
        ],
        [
          if (file != null) ...[
            IdeMenuAction(
              l10n.gitCommitShowDiff,
              onSelected: () => unawaited(_show(file, editor: true)),
            ),
            if (resource!.status != IdeGitStatus.deleted &&
                resource.status != IdeGitStatus.indexDeleted)
              IdeMenuAction(
                l10n.gitCommitJumpToSource,
                onSelected: () =>
                    unawaited(widget.onOpen(resource.path, focusEditor: true)),
              ),
          ],
        ],
        _changelistMenu(row),
        [
          if (widget.onAsk case final ask? when files.isNotEmpty) ...[
            if (conflicts.isNotEmpty)
              IdeMenuAction(
                l10n.gitAskAiConflicts,
                onSelected: () => ask(
                  l10n.gitAskAiConflictsPrompt(_relativeList(git, conflicts)),
                ),
              ),
            if (files.length > conflicts.length)
              IdeMenuAction(
                l10n.gitAskAiChanges,
                onSelected: () => ask(
                  l10n.gitAskAiChangesPrompt(
                    _relativeList(git, [
                      for (final file in files)
                        if (file.group != IdeGitGroup.merge) file,
                    ]),
                  ),
                ),
              ),
          ],
        ],
        [
          if (_checkable(row).isNotEmpty)
            IdeMenuAction(
              l10n.gitCommitRollback,
              onSelected: () => unawaited(_rollback(git, _checkable(row))),
            ),
          if (_checkable(row).isNotEmpty && row is! _RepoRow)
            IdeMenuAction(
              l10n.gitStashSelected,
              onSelected: () => unawaited(
                _stash(
                  git,
                  paths: [for (final file in _checkable(row)) file.path],
                ),
              ),
            ),
          if (untracked.isNotEmpty)
            IdeMenuAction(
              l10n.gitCommitAddToVcs,
              onSelected: () => unawaited(_run(() => git.stage(untracked))),
            ),
          if (untracked.isNotEmpty && row is! _RepoRow)
            IdeMenuAction(
              l10n.scmAddToGitignore,
              // An unversioned folder: itself, whatever comes in it later.
              onSelected: () => unawaited(switch (row) {
                _FolderRow(kind: _Kind.unversioned, :final folder) => _ignore(
                  git,
                  [folder.path],
                  folders: {folder.path},
                ),
                _ => _ignore(git, [for (final file in untracked) file.path]),
              }),
            ),
          if (conflicts.isNotEmpty) ...[
            if (resource != null && ideGitMergeable(resource))
              IdeMenuAction(
                l10n.gitConflictMerge,
                onSelected: () => unawaited(_mergeConflict(git, resource)),
              ),
            IdeMenuAction(
              l10n.gitConflictAcceptCurrent,
              onSelected: () =>
                  unawaited(_run(() => git.acceptSide(conflicts, ours: true))),
            ),
            IdeMenuAction(
              l10n.gitConflictAcceptIncoming,
              onSelected: () =>
                  unawaited(_run(() => git.acceptSide(conflicts, ours: false))),
            ),
            IdeMenuAction(
              l10n.gitCommitMarkResolved,
              onSelected: () => unawaited(_run(() => git.stage(conflicts))),
            ),
          ],
        ],
        [
          if (path != null) ...[
            IdeMenuAction(
              l10n.gitLogCopyPath,
              onSelected: () =>
                  unawaited(Clipboard.setData(ClipboardData(text: path))),
            ),
            if (row is! _RepoRow)
              IdeMenuAction(
                l10n.gitLogCopyRelativePath,
                onSelected: () => unawaited(
                  Clipboard.setData(
                    ClipboardData(
                      text: git.service.pathContext.relative(
                        path,
                        from: git.service.root,
                      ),
                    ),
                  ),
                ),
              ),
            if (widget.onRevealInExplorer case final reveal?)
              IdeMenuAction(
                widget.revealInExplorerLabel ?? l10n.tabRevealInExplorerView,
                onSelected: () => reveal(path),
              ),
          ],
          if (widget.onAddToChat case final add?)
            // A folder itself; a group, each of its files still there.
            if (row is _FolderRow || row is _FileRow
                    ? _composerFiles(row)
                    : [
                        for (final file in files)
                          if (file.status != IdeGitStatus.deleted &&
                              file.status != IdeGitStatus.indexDeleted)
                            ComposerFile(file.path),
                      ]
                case final chat when chat.isNotEmpty)
              IdeMenuAction(
                l10n.sidePanelAddToChat,
                onSelected: () => add(chat),
              ),
        ],
      ]),
    );
  }

  /// [files]' paths from [git]'s top, as Git writes them, one after
  /// another.
  static String _relativeList(
    IdeGitRepository git,
    List<IdeGitResource> files,
  ) {
    final paths = git.service.pathContext;
    final listed = [
      for (final file in files.take(20))
        paths.relative(file.path, from: git.service.root).replaceAll(r'\', '/'),
    ];
    return [...listed, if (files.length > listed.length) '…'].join(' ');
  }

  /// The commit message's lines that fit in [height].
  static int lines(double height) => math.max(1, ((height - 8) / 20).floor());

  /// Under the tree: Amend, the commit message, and the buttons.
  Widget _commitArea(BuildContext context) {
    final l10n = context.l10n;
    final git = _git;
    final total = [
      for (final git in _repositories)
        if (git.state case final state?)
          for (final kind in const [_Kind.changes, _Kind.unversioned])
            ..._changesOf(state)[kind]!,
    ].length;
    final checked = [for (final git in _repositories) ..._toCommit(git)].length;
    final busy = _committing || _repositories.any((git) => git.busy);
    final branch = git?.state?.head.branch;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _Check(
                value: _session.amend,
                onTap: () => unawaited(_setAmend(!_session.amend)),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => unawaited(_setAmend(!_session.amend)),
                child: Text(
                  l10n.gitCommitAmend,
                  style: TextStyle(
                    fontSize: 12,
                    color: IdeListColors.foreground,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Builder(
                builder: (context) => IdeActionButton(
                  icon: Codicons.settingsGear,
                  tooltip: l10n.gitCommitOptions,
                  size: 20,
                  iconSize: 14,
                  onPressed: () {
                    final box = context.findRenderObject() as RenderBox;
                    unawaited(
                      _commitOptions(
                        box.localToGlobal(box.size.bottomLeft(Offset.zero)),
                      ),
                    );
                  },
                ),
              ),
              // What the options change, as a reminder.
              if ([
                    if (_session.author case final author?)
                      l10n.gitCommitAuthorIs(author),
                    if (_session.signOff) l10n.gitCommitSignedOff,
                    if (!_session.runHooks) l10n.gitCommitNoHooks,
                  ].join(' · ')
                  case final options when options.isNotEmpty)
                Flexible(
                  flex: 3,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      options,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: IdeListColors.description,
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (branch != null)
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Codicons.gitBranch,
                        size: 13,
                        color: IdeListColors.description,
                      ),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          branch,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: IdeListColors.description,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_reviewBox(context) case final box?) ...[
            const SizedBox(height: 6),
            box,
          ],
          const SizedBox(height: 6),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => IdeInputBox(
                key: _messageKey,
                controller: _session.message,
                focusNode: _inputFocus,
                semanticsLabel: l10n.gitCommitMessage,
                placeholder: l10n.gitCommitMessage,
                // As many lines as fit.
                minLines: lines(constraints.maxHeight),
                maxLines: lines(constraints.maxHeight),
                lineHeight: 20,
                validation: _shownValidation,
                floatingValidation: true,
                shortcuts: {
                  const SingleActivator(
                    LogicalKeyboardKey.keyM,
                    control: true,
                  ): () =>
                      unawaited(_messageHistory()),
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    control: true,
                  ): () =>
                      unawaited(_commit()),
                  const SingleActivator(
                    LogicalKeyboardKey.enter,
                    meta: true,
                  ): () =>
                      unawaited(_commit()),
                },
                toggles: [
                  if (widget.commitMessage != null)
                    IdeActionButton(
                      icon: _session.reviewing == null
                          ? Codicons.checklist
                          : Codicons.debugStop,
                      tooltip: _session.reviewing == null
                          ? l10n.gitReviewWithAi
                          : l10n.gitReviewStop,
                      size: 20,
                      onPressed: () => unawaited(_review()),
                    ),
                  IdeActionButton(
                    icon: Codicons.history,
                    tooltip: l10n.gitCommitMessageHistory,
                    size: 20,
                    onPressed: () => unawaited(_messageHistory()),
                  ),
                  if (widget.commitMessage != null)
                    IdeActionButton(
                      icon: _session.generating == null
                          ? Codicons.sparkle
                          : Codicons.debugStop,
                      tooltip: _session.generating == null
                          ? l10n.scmGenerateCommitMessage
                          : l10n.scmCancelGenerateCommitMessage,
                      size: 20,
                      onPressed: () => unawaited(_generateMessage()),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              IdeButton(
                label: l10n.gitCommitButton,
                onPressed: busy ? null : () => unawaited(_commit()),
              ),
              const SizedBox(width: 6),
              IdeButton(
                label: l10n.gitCommitAndPush,
                secondary: true,
                onPressed: busy ? null : () => unawaited(_commit(push: true)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  total == 0 ? '' : l10n.gitCommitSelected(checked, total),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 12,
                    color: IdeListColors.description,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Push, or where the branch has no upstream yet, Publish to its first
/// remote (`origin` first): as JetBrains' Push sets the upstream.
Future<void> ideGitPushOrPublish(IdeGitRepository git) async {
  final head = git.state?.head;
  if (head == null || head.branch == null) return;
  if (head.upstream != null) return git.push();
  final remotes = await git.service.remotes();
  if (remotes.isEmpty) return git.push();
  await git.publish(remotes.contains('origin') ? 'origin' : remotes.first);
}

/// A check box: checked, unchecked, or some of what it stands for (null).
class _Check extends StatelessWidget {
  const _Check({required this.value, required this.onTap});

  final bool? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final on = value != false;
    final accent =
        colors.get('checkbox.selectBackground') ?? colors['button.background'];
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 18,
          height: 18,
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: on ? accent : colors.get('checkbox.background'),
                border: Border.all(
                  color: on
                      ? accent
                      : colors.get('checkbox.border') ??
                            IdeListColors.description,
                ),
                borderRadius: BorderRadius.circular(3),
              ),
              alignment: Alignment.center,
              child: switch (value) {
                true => Icon(
                  Codicons.check,
                  size: 12,
                  color: colors['button.foreground'],
                ),
                null => Container(
                  width: 8,
                  height: 2,
                  color: colors['button.foreground'],
                ),
                false => null,
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// What shows instead of the changes: a message, and a button under it.
class _Welcome extends StatelessWidget {
  const _Welcome(this.message, {this.button, this.onPressed});

  final String message;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: TextStyle(
            fontSize: 13,
            height: 1.4,
            color: IdeListColors.foreground,
          ),
        ),
        if (button case final button?) ...[
          const SizedBox(height: 12),
          IdeButton(label: button, expand: true, onPressed: onPressed),
        ],
      ],
    ),
  );
}

/// The line between the tree and the message, dragged to size them.
class _Divider extends StatefulWidget {
  const _Divider({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_Divider> createState() => _DividerState();
}

class _DividerState extends State<_Divider> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.resizeRow,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) => widget.onDrag(details.delta.dy),
      child: SizedBox(
        height: 5,
        child: Center(
          child: Container(
            height: _hover ? 3 : 1,
            color: _hover
                ? themeColors['sash.hoverBorder']
                : themeColors.get('panel.border') ?? IdeListColors.description,
          ),
        ),
      ),
    ),
  );
}

/// A tab of the panel's: Commit, Stash.
class _PanelTab extends StatefulWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_PanelTab> createState() => _PanelTabState();
}

class _PanelTabState extends State<_PanelTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = themeColors;
    final selected = widget.selected;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                width: 2,
                color: selected
                    ? colors['panelTitle.activeBorder']
                    : Colors.transparent,
              ),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              color: selected || _hover
                  ? colors['panelTitle.activeForeground']
                  : colors['panelTitle.inactiveForeground'],
            ),
          ),
        ),
      ),
    );
  }
}
