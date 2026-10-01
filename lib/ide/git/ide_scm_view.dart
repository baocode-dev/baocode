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
// editor; of push, pull
// and fetch only the action button's Sync Changes and Publish Branch, with
// no remote providers (Publish to GitHub) and a menu at the button for the
// remote to publish to, where upstream has a quick pick; no stash, branch
// or tag commands; the smart commit's Always and Never, and the sync's
// Don't Show Again, last for the session; Generate Commit Message asks
// Claude Haiku (see commit_message.dart), where VS Code asks Copilot. The
// keyboard walks the graph's commits, not the files of an expanded one; the
// commit input keeps no history of messages (`scm.viewPreviousCommit`).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../keybindings/keybinding_service.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/cursor_theme.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart';
import '../../workspace/window_controls.dart';
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
import '../ide_workspace.dart';
import 'commit_message.dart';
import 'git_graph_painter.dart';
import 'git_model.dart';
import 'git_repository.dart';
import 'git_service.dart';
import 'scm_tree.dart';

/// What the Source Control view keeps while another view shows: the
/// commit message, which panes, groups and commits are open, and the
/// smart commit choice.
/// `scm.defaultViewSortKey`: how the list orders changes.
enum IdeScmSort { name, path, status }

class IdeScmSession {
  final TextEditingController message = TextEditingController();
  final Set<String> expandedPanes = {'changes', 'graph'};
  final Set<IdeGitGroup> collapsedGroups = {};
  final Set<String> expandedCommits = {};

  /// View as Tree (the default here) or View as List, and the list's order.
  bool treeView = true;
  IdeScmSort sort = IdeScmSort.path;

  /// The tree's collapsed folders (`group:folder:path`).
  final Set<String> collapsedFolders = {};

  /// `git.enableSmartCommit`: commit every change when none is staged.
  bool enableSmartCommit = false;

  /// `git.suggestSmartCommit`: ask before doing so.
  bool suggestSmartCommit = true;

  /// `git.confirmSync`: ask before Sync Changes.
  bool confirmSync = true;

  /// Completes to cancel the commit message being generated; null when
  /// none is. Kept here, so that the message still arrives when the view
  /// has closed meanwhile.
  Completer<void>? generating;

  void dispose() {
    generating?.complete();
    message.dispose();
  }
}

class IdeScmView extends StatefulWidget {
  const IdeScmView({
    super.key,
    required this.workspace,
    required this.session,
    required this.notifications,
    required this.onOpen,
    required this.onOpenChange,
    required this.onRevealInExplorer,
    this.trash,
    this.commitMessage,
  });

  final IdeWorkspace workspace;
  final IdeScmSession session;
  final IdeNotifications notifications;

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

  /// Moves a file to the Trash (true once it did); null where there is no
  /// Trash, and untracked files are deleted.
  final Future<bool> Function(String path)? trash;

  /// Writes commit messages (Generate Commit Message); none offered when
  /// null.
  final IdeCommitMessageModel? commitMessage;

  @override
  State<IdeScmView> createState() => IdeScmViewState();
}

/// A row of the Changes list the keyboard walks: a resource group, a
/// folder of the tree, or a change.
sealed class _ScmRow {
  /// What `_selected` holds for it.
  String get key;

  /// Its group's or folder's key; null for a group.
  String? get parent;
}

final class _GroupRow implements _ScmRow {
  _GroupRow(this.group, this.resources);

  final IdeGitGroup group;
  final List<IdeGitResource> resources;

  @override
  String get key => group.name;

  @override
  String? get parent => null;
}

final class _FolderRow implements _ScmRow {
  _FolderRow(this.group, this.folder, this.depth, this.key, this.parent);

  final IdeGitGroup group;
  final IdeScmTreeFolder folder;
  final int depth;
  @override
  final String key;
  @override
  final String parent;
}

final class _ResourceRow implements _ScmRow {
  _ResourceRow(this.resource, this.treeDepth, this.parent);

  final IdeGitResource resource;

  /// Its depth in the tree; null in the list.
  final int? treeDepth;
  @override
  final String parent;

  @override
  String get key => '${resource.group.name}:${resource.path}';
}

class IdeScmViewState extends State<IdeScmView>
    with IdeKeyboardList<IdeScmView> {
  final FocusNode _inputFocus = FocusNode(debugLabel: 'scm input');
  final FocusNode _listFocus = FocusNode(debugLabel: 'scm list');
  final FocusNode _graphFocus = FocusNode(debugLabel: 'scm graph');
  final ScrollController _changesScroll = ScrollController();
  final ScrollController _graphScroll = ScrollController();

  /// Publish Branch, where the menu of remotes opens.
  final GlobalKey _publishKey = GlobalKey();
  IdeInputValidation? _validation;

  /// The rows above the changes (the input, the action button), measured
  /// for revealing a row, and their last height.
  final GlobalKey _inputKey = GlobalKey();
  final GlobalKey _actionKey = GlobalKey();
  double _headerHeight = 0;

  /// The selected resource (`group:path`) or group (`group`).
  String? _selected;
  String? _selectedCommit;
  final Map<String, Future<List<IdeGitCommitChange>>> _changes = {};

  IdeGitRepository? get _git => widget.workspace.git;
  IdeScmSession get _session => widget.session;

  @override
  void initState() {
    super.initState();
    _message = _session.message.text;
    _session.message.addListener(_messageChanged);
    _listFocus.addListener(_rebuild);
    _graphFocus.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(IdeScmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.message.removeListener(_messageChanged);
      widget.session.message.addListener(_messageChanged);
    }
  }

  @override
  void dispose() {
    _session.message.removeListener(_messageChanged);
    _inputFocus.dispose();
    _listFocus.dispose();
    _graphFocus.dispose();
    _changesScroll.dispose();
    _graphScroll.dispose();
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
      color: CursorColors.sidebarSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeViewTitle(context.l10n.scmTitle),
          Expanded(
            child: git == null
                ? _Welcome([context.l10n.scmNoProviders])
                : ListenableBuilder(
                    listenable: git,
                    builder: (context, _) => _body(git),
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
      content = error is IdeGitException && error.message.startsWith('Git is')
          ? _Welcome([l10n.scmInstallGit, error.message])
          : _Welcome(
              [l10n.scmNoRepository],
              button: l10n.scmInitializeRepository,
              onPressed: () => unawaited(_run(git.initialize)),
            );
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
                tooltip: l10n.scmCommit,
                onPressed: () => unawaited(_commit()),
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: l10n.commonRefresh,
                onPressed: () => unawaited(git.refresh()),
              ),
              IdeMenuButton(
                icon: Codicons.ellipsis,
                tooltip: l10n.commonMoreActions,
                entries: _moreActions,
              ),
            ],
            body: _changesList(git, state),
          ),
          IdePane(
            id: 'graph',
            title: l10n.scmGraph,
            weight: 2,
            actions: [
              IdePaneAction(
                icon: Codicons.target,
                tooltip: l10n.scmGoToCurrent,
                onPressed: () => _goToCurrent(git),
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

  /// Whether the commit message input has the keyboard (upstream
  /// `scmRepository`, which its editor sets).
  bool get inputHasFocus => _inputFocus.hasFocus;

  /// `scmInputHasValidationMessage`.
  bool get hasValidation => _validation != null;

  /// Whether the input's text has a selection (its
  /// `editorHasSelection`).
  bool get inputHasSelection {
    final selection = _session.message.selection;
    return selection.isValid && !selection.isCollapsed;
  }

  /// `scm.acceptInput`: the Git repository's `git.commit`.
  Future<void> commit() => _commit();

  /// `scm.clearInput`.
  void clearInput() => _session.message.clear();

  /// `scm.clearValidation`.
  void clearValidation() {
    if (_validation != null) setState(() => _validation = null);
  }

  /// `workbench.scm.focus` (upstream `SCMViewPane.focus`): the input, or
  /// the list where a row is selected.
  void focus() => (_selected == null ? _inputFocus : _listFocus).requestFocus();

  bool get _graphHasFocus => _graphFocus.hasPrimaryFocus;

  List<_ScmRow> get _rows => switch (_git?.state) {
    final state? => _changeRows(state),
    null => const [],
  };

  List<IdeGraphRow> get _commits => _git?.graph ?? const [];

  _ScmRow? get _focusedRow {
    final key = _selected;
    return key == null
        ? null
        : _rows.where((row) => row.key == key).firstOrNull;
  }

  bool _isCollapsed(_ScmRow row) => switch (row) {
    _GroupRow(:final group) => _session.collapsedGroups.contains(group),
    _FolderRow(:final key) => _session.collapsedFolders.contains(key),
    _ResourceRow() => false,
  };

  void _setCollapsed(_ScmRow row, bool collapsed) => setState(() {
    switch (row) {
      case _GroupRow(:final group):
        collapsed
            ? _session.collapsedGroups.add(group)
            : _session.collapsedGroups.remove(group);
      case _FolderRow(:final key):
        collapsed
            ? _session.collapsedFolders.add(key)
            : _session.collapsedFolders.remove(key);
      case _ResourceRow():
    }
  });

  void _toggleCommit(IdeGraphRow row) {
    final id = row.commit.id;
    if (id == ideIncomingChangesId || id == ideOutgoingChangesId) return;
    setState(() {
      if (!_session.expandedCommits.remove(id)) {
        _session.expandedCommits.add(id);
      }
    });
  }

  @override
  bool get listHasFocus => _listFocus.hasPrimaryFocus || _graphHasFocus;

  @override
  int get listLength => _graphHasFocus ? _commits.length : _rows.length;

  @override
  int get listFocusedIndex => _graphHasFocus
      ? _commits.indexWhere((row) => row.commit.id == _selectedCommit)
      : _rows.indexWhere((row) => row.key == _selected);

  @override
  int get listPageSize =>
      ideRowsPerPage(_graphHasFocus ? _graphScroll : _changesScroll);

  @override
  void listFocusAt(int index) {
    if (_graphHasFocus) {
      setState(() => _selectedCommit = _commits[index].commit.id);
      ideRevealRow(_graphScroll, index);
      return;
    }
    setState(() => _selected = _rows[index].key);
    // Below the input and the action button.
    final heights = [
      for (final key in [_inputKey, _actionKey]) key.currentContext?.size,
    ];
    if (heights.every((size) => size != null)) {
      _headerHeight = heights.fold(0.0, (sum, size) => sum + size!.height);
    }
    ideRevealRow(_changesScroll, index, top: _headerHeight);
  }

  @override
  void listSelect() {
    if (_graphHasFocus) {
      final at = listFocusedIndex;
      if (at >= 0) _toggleCommit(_commits[at]);
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
        _toggleCommit(_commits[at]);
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
        _toggleCommit(_commits[at]);
      }
      return;
    }
    final row = _focusedRow;
    if (row == null) return;
    if (row is! _ResourceRow && !_isCollapsed(row)) {
      _setCollapsed(row, true);
    } else if (row.parent case final parent?) {
      final at = _rows.indexWhere((row) => row.key == parent);
      if (at >= 0) listFocusAt(at);
    }
  }

  @override
  void listCollapseAll() {
    if (_graphHasFocus) {
      setState(_session.expandedCommits.clear);
      return;
    }
    final state = _git?.state;
    if (state == null) return;
    final focused = _focusedRow;
    setState(() {
      for (final group in IdeGitGroup.values) {
        void collapse(List<IdeScmTreeNode> nodes) {
          for (final node in nodes) {
            if (node is! IdeScmTreeFolder) continue;
            _session.collapsedFolders.add(_folderKey(group, node));
            collapse(node.children);
          }
        }

        collapse(ideScmTree(state.root, state.group(group)));
        _session.collapsedGroups.add(group);
      }
      // The focus goes to its group.
      if (focused != null) _selected = focused.key.split(':').first;
    });
  }

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
    final items = <Widget>[
      _inputRow(state),
      _actionButtonRow(git, state),
      for (final row in _changeRows(state))
        switch (row) {
          _GroupRow(:final group, :final resources) => _groupRow(
            git,
            group,
            resources,
          ),
          _FolderRow(:final group, :final folder, :final depth, :final key) =>
            _folderRow(git, state, group, folder, depth, key),
          _ResourceRow(:final resource, :final treeDepth) => _resourceRow(
            git,
            state,
            resource,
            treeDepth: treeDepth,
          ),
        },
    ];
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
        child: IdeAnimatedList(controller: _changesScroll, children: items),
      ),
    );
  }

  /// The list's order (`SCMTreeSorter` in list mode).
  List<IdeGitResource> _sorted(List<IdeGitResource> resources) {
    int byPath(IdeGitResource a, IdeGitResource b) => a.path.compareTo(b.path);
    return [...resources]..sort(switch (_session.sort) {
      IdeScmSort.path => byPath,
      IdeScmSort.name => (a, b) {
        final order = ideCompareFileNames(
          p.basename(a.path),
          p.basename(b.path),
        );
        return order != 0 ? order : byPath(a, b);
      },
      IdeScmSort.status => (a, b) {
        final order = a.status.label.compareTo(b.status.label);
        return order != 0 ? order : byPath(a, b);
      },
    });
  }

  /// The Changes list's rows: each group shown (Merge and Staged Changes
  /// hide when empty; Changes does not) and, unless collapsed, its tree's
  /// folders (expanded or not) and files under it (depth 1), or its list.
  List<_ScmRow> _changeRows(IdeGitState state) {
    final rows = <_ScmRow>[];
    for (final group in IdeGitGroup.values) {
      final resources = state.group(group);
      if (resources.isEmpty && group != IdeGitGroup.workingTree) continue;
      rows.add(_GroupRow(group, resources));
      if (_session.collapsedGroups.contains(group)) continue;
      if (!_session.treeView) {
        for (final resource in _sorted(resources)) {
          rows.add(_ResourceRow(resource, null, group.name));
        }
        continue;
      }
      void add(List<IdeScmTreeNode> nodes, int depth, String parent) {
        for (final node in nodes) {
          switch (node) {
            case IdeScmTreeFolder():
              final key = _folderKey(group, node);
              rows.add(_FolderRow(group, node, depth, key, parent));
              if (!_session.collapsedFolders.contains(key)) {
                add(node.children, depth + 1, key);
              }
            case IdeScmTreeFile(:final resource):
              rows.add(_ResourceRow(resource, depth, parent));
          }
        }
      }

      add(ideScmTree(state.root, resources), 2, group.name);
    }
    return rows;
  }

  static String _folderKey(IdeGitGroup group, IdeScmTreeFolder folder) =>
      '${group.name}:folder:${folder.path}';

  /// `Menus.ViewSort`: View as List or Tree, and the list's order.
  List<IdeMenuEntry> _viewSortMenu() => ideMenuGroups([
    [
      IdeMenuAction(
        context.l10n.scmViewAsList,
        checked: !_session.treeView,
        onSelected: () => setState(() => _session.treeView = false),
      ),
      IdeMenuAction(
        context.l10n.scmViewAsTree,
        checked: _session.treeView,
        onSelected: () => setState(() => _session.treeView = true),
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
          onSelected: () => setState(() => _session.sort = sort),
        ),
    ],
  ]);

  /// A folder of the tree: its chevron, icon and (compressed) name, the
  /// actions on everything in it, and the dot of what changed inside.
  Widget _folderRow(
    IdeGitRepository git,
    IdeGitState state,
    IdeGitGroup group,
    IdeScmTreeFolder folder,
    int depth,
    String key,
  ) {
    final collapsed = _session.collapsedFolders.contains(key);
    final resources = folder.resources.toList();
    final actions = _folderActions(git, group, resources);
    final bubble = git.decorations?.folder(folder.path)?.color;
    return IdeListRow(
      key: ValueKey(key),
      selected: _selected == key,
      focused: _listFocus.hasFocus,
      tooltip: p.relative(folder.path, from: state.root),
      onTap: () {
        _listFocus.requestFocus();
        setState(() {
          _selected = key;
          if (!_session.collapsedFolders.remove(key)) {
            _session.collapsedFolders.add(key);
          }
        });
      },
      onContextMenu: (position) {
        setState(() => _selected = key);
        unawaited(
          showIdeMenu(
            context,
            position: position,
            entries: [
              for (final action in actions)
                IdeMenuAction(action.label, onSelected: action.run),
            ],
          ),
        );
      },
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(left: 8.0 + (depth - 1) * 8, right: 12),
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
                  if (hovered || (_selected == key && _listFocus.hasFocus))
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
  }

  /// `scm/resourceFolder/context`'s inline actions: on every change in the
  /// folder.
  List<_Action> _folderActions(
    IdeGitRepository git,
    IdeGitGroup group,
    List<IdeGitResource> resources,
  ) => switch (group) {
    IdeGitGroup.merge => [
      _Action(
        context.l10n.scmStageChanges,
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
    IdeGitGroup.staged => [
      _Action(
        context.l10n.scmUnstageChanges,
        Codicons.remove,
        () => unawaited(_run(() => git.unstage(resources))),
      ),
    ],
    IdeGitGroup.workingTree => [
      _Action(
        context.l10n.scmDiscardChanges,
        Codicons.discard,
        () => unawaited(_discard(resources)),
      ),
      _Action(
        context.l10n.scmStageChanges,
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
  };

  /// `scm.acceptInput`'s keybinding, else ⌘Enter / Ctrl+Enter (upstream's
  /// placeholder).
  String get _commitKey =>
      KeybindingService.instance.labelFor('scm.acceptInput') ??
      const IdeKeybinding(LogicalKeyboardKey.enter, primary: true).label();

  Widget _inputRow(IdeGitState state) {
    final branch = state.head.branch;
    return KeyedSubtree(
      key: const ValueKey('input'),
      child: Padding(
        key: _inputKey,
        padding: const EdgeInsets.fromLTRB(19, 5, 12, 5),
        child: IdeInputBox(
          controller: _session.message,
          focusNode: _inputFocus,
          semanticsLabel: context.l10n.scmInput,
          placeholder: branch == null
              ? context.l10n.scmMessagePlaceholder(_commitKey)
              : context.l10n.scmMessagePlaceholderBranch(_commitKey, branch),
          minLines: 1,
          maxLines: 10,
          lineHeight: 20,
          padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
          validation: _validation,
          // `.scm-editor-toolbar { padding: 1px 3px 1px 1px }`.
          togglesInset: 3,
          toggles: [
            if (widget.commitMessage != null)
              IdeActionButton(
                icon: _session.generating == null
                    ? Codicons.sparkle
                    : Codicons.debugStop,
                tooltip: _session.generating == null
                    ? context.l10n.scmGenerateCommitMessage
                    : context.l10n.scmCancelGenerateCommitMessage,
                size: 20,
                onPressed: () => unawaited(_generateCommitMessage(state)),
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
  Future<void> _generateCommitMessage(IdeGitState state) async {
    final model = widget.commitMessage;
    final git = widget.workspace.git;
    if (model == null || git == null) return;
    final l10n = context.l10n;
    final session = _session;
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
  bool _hasChangesToCommit(IdeGitState state) =>
      state.group(IdeGitGroup.staged).isNotEmpty ||
      ((_session.enableSmartCommit || _session.suggestSmartCommit) &&
          state.group(IdeGitGroup.workingTree).isNotEmpty);

  /// The action button (actionButton.ts' `button`): Commit, enabled, while
  /// there is something to commit, else Publish Branch, Sync Changes, or
  /// Commit, disabled.
  Widget _actionButtonRow(IdeGitRepository git, IdeGitState state) {
    final changes = _hasChangesToCommit(state);
    return KeyedSubtree(
      key: const ValueKey('commit-button'),
      child: Padding(
        key: _actionKey,
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
      key: _publishKey,
      icon: syncing ? null : Codicons.cloudUpload,
      spinning: syncing,
      label: context.l10n.scmPublishBranch,
      tooltip: syncing
          ? context.l10n.scmPublishingBranchNamed(branch)
          : context.l10n.scmPublishBranchNamed(branch),
      enabled: !git.busy,
      onPressed: () => unawaited(_publish(branch)),
    );
  }

  /// `getSyncChangesActionButton`: on a branch ahead of its upstream or
  /// behind it.
  Widget? _syncButton(IdeGitRepository git, IdeGitHead head) {
    final upstream = head.upstream;
    if (upstream == null || (head.ahead == 0 && head.behind == 0)) {
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
      onPressed: () => unawaited(_sync(head)),
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
  Future<void> _sync(IdeGitHead head) async {
    final git = _git;
    final upstream = head.upstream;
    if (git == null || upstream == null) return;
    if (_session.confirmSync) {
      final pick = await showIdeDialog(
        context,
        message: context.l10n.scmConfirmSync(upstream),
        buttons: [context.l10n.commonOk, context.l10n.scmDontShowAgain],
      );
      if (pick == 1) {
        _session.confirmSync = false;
      } else if (pick != 0) {
        return;
      }
    }
    await _run(git.sync);
  }

  /// `git.publish`: to the only remote, or to the one picked.
  Future<void> _publish(String branch) async {
    final git = _git;
    if (git == null) return;
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
        final box = _publishKey.currentContext?.findRenderObject();
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

  Widget _commitButton(IdeGitRepository git, {required bool enabled}) =>
      _SplitButton(
        icon: Codicons.check,
        label: context.l10n.scmCommit,
        tooltip: context.l10n.scmCommitChanges,
        enabled: enabled && !git.busy,
        onPressed: () => unawaited(_commit()),
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
                  onSelected: () => unawaited(_commit()),
                ),
              ],
              [
                IdeMenuAction(
                  context.l10n.scmCommitAmend,
                  onSelected: () => unawaited(_commit(amend: true)),
                ),
              ],
            ]),
          ),
        ),
      );

  Widget _groupRow(
    IdeGitRepository git,
    IdeGitGroup group,
    List<IdeGitResource> resources,
  ) {
    final collapsed = _session.collapsedGroups.contains(group);
    final key = group.name;
    void toggle() => setState(() {
      _selected = key;
      if (!_session.collapsedGroups.remove(group)) {
        _session.collapsedGroups.add(group);
      }
    });
    final actions = _groupActions(git, group, resources);
    return IdeListRow(
      key: ValueKey('group:$key'),
      selected: _selected == key,
      focused: _listFocus.hasFocus,
      onTap: () {
        _listFocus.requestFocus();
        toggle();
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
              if (_session.treeView)
                IdeMenuAction(
                  context.l10n.commonCollapseAll,
                  onSelected: () => setState(() {
                    void collapse(List<IdeScmTreeNode> nodes) {
                      for (final node in nodes) {
                        if (node is! IdeScmTreeFolder) continue;
                        _session.collapsedFolders.add(_folderKey(group, node));
                        collapse(node.children);
                      }
                    }

                    collapse(ideScmTree(git.state!.root, resources));
                  }),
                ),
            ],
          ]),
        ),
      ),
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
            IdeCountBadge(resources.length),
          ],
        ),
      ),
    );
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
        () => unawaited(_discard(resources)),
      ),
      _Action(
        context.l10n.scmStageAll,
        Codicons.add,
        () => unawaited(_run(git.stageAll)),
      ),
    ],
  };

  List<_Action> _resourceActions(
    IdeGitRepository git,
    IdeGitResource resource,
  ) => [
    if (!_deleted(resource))
      _Action(
        context.l10n.scmOpenFile,
        Codicons.goToFile,
        () => unawaited(widget.onOpen(resource.path, focusEditor: true)),
      ),
    ...switch (resource.group) {
      IdeGitGroup.merge => [
        _Action(
          context.l10n.scmStageChanges,
          Codicons.add,
          () => unawaited(_run(() => git.stage([resource]))),
        ),
      ],
      IdeGitGroup.staged => [
        _Action(
          context.l10n.scmUnstageChanges,
          Codicons.remove,
          () => unawaited(_run(() => git.unstage([resource]))),
        ),
      ],
      IdeGitGroup.workingTree => [
        _Action(
          context.l10n.scmDiscardChanges,
          Codicons.discard,
          () => unawaited(_discard([resource])),
        ),
        _Action(
          context.l10n.scmStageChanges,
          Codicons.add,
          () => unawaited(_run(() => git.stage([resource]))),
        ),
      ],
    },
  ];

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
  }) {
    final key = '${resource.group.name}:${resource.path}';
    final relative = p.relative(resource.path, from: state.root);
    final folder = p.dirname(relative);
    final actions = _resourceActions(git, resource);
    void open({bool focus = false}) =>
        unawaited(widget.onOpenChange(resource, focusEditor: focus));

    return IdeListRow(
      key: ValueKey(key),
      selected: _selected == key,
      focused: _listFocus.hasFocus,
      tooltip:
          '${p.join(state.root, relative)} • '
          '${resource.status.localizedLabel(context.l10n)}',
      onTap: () {
        _listFocus.requestFocus();
        setState(() => _selected = key);
        open();
      },
      onDoubleTap: () => open(focus: true),
      onContextMenu: (position) {
        setState(() => _selected = key);
        unawaited(_showResourceMenu(position, git, state, resource));
      },
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: treeDepth == null ? 16 : 8.0 + (treeDepth - 1) * 8 + 22,
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
                  if (hovered || (_selected == key && _listFocus.hasFocus))
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
  }

  Future<void> _showResourceMenu(
    Offset position,
    IdeGitRepository git,
    IdeGitState state,
    IdeGitResource resource,
  ) {
    final working = resource.group == IdeGitGroup.workingTree;
    // The merge group's has Open File alone.
    final merge = resource.group == IdeGitGroup.merge;
    final l10n = context.l10n;
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          if (!merge)
            IdeMenuAction(
              l10n.scmOpenChanges,
              onSelected: () =>
                  unawaited(widget.onOpenChange(resource, focusEditor: true)),
            ),
          if (!_deleted(resource))
            IdeMenuAction(
              l10n.scmOpenFile,
              onSelected: () =>
                  unawaited(widget.onOpen(resource.path, focusEditor: true)),
            ),
          if (!merge)
            IdeMenuAction(
              l10n.scmOpenFileHead,
              onSelected: () => unawaited(
                widget.onOpenChange(resource, head: true, focusEditor: true),
              ),
            ),
        ],
        [
          if (resource.group == IdeGitGroup.staged)
            IdeMenuAction(
              l10n.scmUnstageChanges,
              onSelected: () => unawaited(_run(() => git.unstage([resource]))),
            )
          else
            IdeMenuAction(
              l10n.scmStageChanges,
              onSelected: () => unawaited(_run(() => git.stage([resource]))),
            ),
          if (working) ...[
            IdeMenuAction(
              l10n.scmDiscardChanges,
              onSelected: () => unawaited(_discard([resource])),
            ),
            IdeMenuAction(
              l10n.scmAddToGitignore,
              onSelected: () => unawaited(_ignore(state, [resource.path])),
            ),
          ],
        ],
        [
          if (WindowControls.canRevealInFileManager && !_deleted(resource))
            IdeMenuAction(
              l10n.explorerRevealInFinder,
              onSelected: () =>
                  unawaited(WindowControls.revealInFileManager(resource.path)),
            ),
          if (!_deleted(resource))
            IdeMenuAction(
              l10n.tabRevealInExplorerView,
              onSelected: () => widget.onRevealInExplorer(resource.path),
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
    ];
  }

  // --- Commands ------------------------------------------------------------

  /// `git.commit` and its variants: [all] null commits the staged changes,
  /// or everything when none are (the smart commit, asked first); false
  /// only the staged ones; true everything.
  Future<void> _commit({bool? all, bool amend = false}) async {
    final git = _git;
    final state = git?.state;
    if (git == null || state == null) return;
    final l10n = context.l10n;
    final message = _session.message.text;
    if (message.trim().isEmpty && !amend) {
      setState(() => _validation = IdeInputValidation(l10n.scmProvideMessage));
      _inputFocus.requestFocus();
      return;
    }
    final noStaged = state.group(IdeGitGroup.staged).isEmpty;
    final noUnstaged = state.group(IdeGitGroup.workingTree).isEmpty;
    var commitAll = all ?? false;
    if (all == null && !noUnstaged && noStaged && !amend) {
      if (!_session.enableSmartCommit) {
        if (!_session.suggestSmartCommit) return;
        final pick = await showIdeDialog(
          context,
          message: l10n.scmNoStagedChanges,
          buttons: [l10n.commonYes, l10n.scmAlways, l10n.scmNever],
        );
        if (pick == 1) {
          _session.enableSmartCommit = true;
        } else if (pick == 2) {
          _session.suggestSmartCommit = false;
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
            () => unawaited(_runCommit(message, empty: true)),
          ),
        ],
      );
      return;
    }
    await _runCommit(message, all: commitAll, amend: amend);
  }

  Future<void> _runCommit(
    String message, {
    bool all = false,
    bool amend = false,
    bool empty = false,
  }) async {
    final git = _git;
    if (git == null) return;
    try {
      if (all && !amend) {
        await git.commitEverything(message);
      } else {
        await git.commit(message, all: all, amend: amend, empty: empty);
      }
      if (_session.message.text == message) _session.message.clear();
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
  /// files and untracked ones apart, then discards.
  Future<void> _discard(List<IdeGitResource> resources) async {
    final git = _git;
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
    await widget.workspace.reload([for (final r in chosen) r.path]);
  }

  /// `git.ignore`: appends the files to the repository's `.gitignore` in
  /// its editor, and saves it.
  Future<void> _ignore(IdeGitState state, List<String> paths) async {
    final ignoreFile = p.join(state.root, '.gitignore');
    final lines = [
      for (final path in paths)
        p
            .relative(path, from: state.root)
            .replaceAllMapped(
              RegExp(r'\\|\['),
              (match) => match[0] == r'\' ? '/' : r'\[',
            ),
    ].join('\n');
    try {
      final workspace = widget.workspace;
      try {
        await workspace.files.create(ignoreFile);
      } on Object catch (_) {
        // It exists.
      }
      await widget.onOpen(ignoreFile, focusEditor: true);
      final doc = workspace.documents
          .where((d) => d.path == p.normalize(ignoreFile))
          .firstOrNull;
      if (doc == null || doc.openError != null) return;
      final text = doc.text;
      final lastLine = text.substring(text.lastIndexOf('\n') + 1);
      workspace.edit(
        doc.path,
        lastLine.trim().isEmpty ? '$text$lines\n' : '$text\n$lines\n',
      );
      await workspace.save(doc);
    } catch (error) {
      _report(error);
    }
  }

  // --- Graph ---------------------------------------------------------------

  void _goToCurrent(IdeGitRepository git) {
    final rows = git.graph;
    if (rows == null) return;
    final index = rows.indexWhere((row) => row.kind == IdeGraphRowKind.head);
    if (index < 0) return;
    setState(() => _selectedCommit = rows[index].commit.id);
    if (_graphScroll.hasClients) {
      unawaited(
        _graphScroll.animateTo(
          (index * IdeListColors.rowHeight).clamp(
            0,
            _graphScroll.position.maxScrollExtent,
          ),
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        ),
      );
    }
  }

  Widget _graphList(IdeGitRepository git) {
    final rows = git.graph;
    if (rows == null) return const SizedBox.shrink();
    final items = <Widget>[];
    for (final row in rows) {
      final id = row.commit.id;
      final expanded = _session.expandedCommits.contains(id);
      items.add(_graphRow(git, row, expanded));
      if (expanded) items.addAll(_commitChangeRows(git, row));
    }
    if (git.graphHasMore) {
      final lanes = rows.isEmpty
          ? const <IdeGraphLane>[]
          : rows.last.outputLanes;
      items.add(
        _LoadMoreRow(
          key: const ValueKey('more'),
          lanes: lanes,
          onShown: () => unawaited(git.loadMoreGraph()),
        ),
      );
    }
    return Focus(
      focusNode: _graphFocus,
      child: IdeAnimatedList(controller: _graphScroll, children: items),
    );
  }

  Widget _graphRow(IdeGitRepository git, IdeGraphRow row, bool expanded) {
    final commit = row.commit;
    final selected = _selectedCommit == commit.id;
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
        focused: _graphFocus.hasFocus,
        onTap: () {
          _graphFocus.requestFocus();
          setState(() {
            _selectedCommit = commit.id;
            if (synthetic) return;
            if (!_session.expandedCommits.remove(commit.id)) {
              _session.expandedCommits.add(commit.id);
            }
          });
        },
        onContextMenu: synthetic
            ? null
            : (position) {
                setState(() => _selectedCommit = commit.id);
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
                ? colors[_graphFocus.hasFocus
                      ? 'list.activeSelectionBackground'
                      : 'list.inactiveSelectionBackground']
                : hovered
                ? colors['list.hoverBackground']
                : Colors.transparent,
            colors['sideBar.background'],
          );
          return Padding(
            padding: const EdgeInsets.only(left: 4, right: 12),
            child: Row(
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
                ..._badges(row),
              ],
            ),
          );
        },
      ),
    );
  }

  /// The references' badges: the first colored one with its name, then the
  /// others grouped by color and icon, counted (`scm.graph.badges: filter`
  /// leaves uncolored ones out).
  List<Widget> _badges(IdeGraphRow row) {
    final refs = [...row.commit.references];
    final badges = <Widget>[];
    String? color(IdeGitRef ref) => row.referenceColors[ref.id];
    if (refs.isNotEmpty && color(refs.first) != null) {
      badges.add(_RefBadge([refs.first], color(refs.first), named: true));
      refs.removeAt(0);
    }
    final byColor = <String, List<IdeGitRef>>{};
    for (final ref in refs) {
      if (color(ref) case final c?) (byColor[c] ??= []).add(ref);
    }
    for (final MapEntry(key: c, value: colored) in byColor.entries) {
      final byKind = <IdeGitRefKind, List<IdeGitRef>>{};
      for (final ref in colored) {
        (byKind[ref.kind] ??= []).add(ref);
      }
      for (final group in byKind.values) {
        badges.add(_RefBadge(group, c));
      }
    }
    return [
      for (final (index, badge) in badges.indexed) ...[
        if (index > 0) const SizedBox(width: 4),
        badge,
      ],
    ];
  }

  List<Widget> _commitChangeRows(IdeGitRepository git, IdeGraphRow row) {
    final id = row.commit.id;
    final future = _changes.putIfAbsent(id, () => git.commitChanges(id));
    final lanes = row.outputLanes;
    return [
      // Grows from the loading row to the files as they arrive.
      AnimatedSize(
        key: ValueKey('changes:$id'),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: FutureBuilder<List<IdeGitCommitChange>>(
          future: future,
          builder: (context, snapshot) {
            final changes = snapshot.data;
            if (changes == null) {
              return SizedBox(
                height: IdeListColors.rowHeight,
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    CustomPaint(
                      size: Size(
                        ideGraphPlaceholderWidth(lanes),
                        IdeListColors.rowHeight,
                      ),
                      painter: IdeGraphPlaceholderPainter(
                        lanes,
                        highlight: row.circleIndex,
                      ),
                    ),
                  ],
                ),
              );
            }
            return Column(
              children: [
                for (final change in changes)
                  _CommitChangeRow(
                    change: change,
                    root: git.state?.root ?? widget.workspace.root,
                    lanes: lanes,
                    highlight: row.circleIndex,
                    onOpen: change.status == 'D'
                        ? null
                        : () => unawaited(
                            widget.onOpen(change.path, focusEditor: false),
                          ),
                  ),
              ],
            );
          },
        ),
      ),
    ];
  }
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
                  _Spinning(Icon(Codicons.sync, size: 16, color: foreground)),
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

/// A codicon turning as `codicon-modifier-spin` turns one: once in 1.5s, in
/// 30 steps; still where motion is turned down.
class _Spinning extends StatefulWidget {
  const _Spinning(this.child);

  final Widget child;

  @override
  State<_Spinning> createState() => _SpinningState();
}

class _SpinningState extends State<_Spinning>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turns = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _turns.stop();
    } else if (!_turns.isAnimating) {
      unawaited(_turns.repeat());
    }
  }

  @override
  void dispose() {
    _turns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: _turns.drive(CurveTween(curve: const _Steps(30))),
    child: widget.child,
  );
}

/// CSS `steps(n)`: jumps at the end of each of [steps] intervals.
class _Steps extends Curve {
  const _Steps(this.steps);

  final int steps;

  @override
  double transformInternal(double t) => (t * steps).floor() / steps;
}

/// A reference badge: 18px high and round, in the reference's color, with
/// its count when it stands for more than one, its icon, and for the first
/// its name.
class _RefBadge extends StatelessWidget {
  const _RefBadge(this.refs, this.color, {this.named = false});

  final List<IdeGitRef> refs;

  /// The reference's color id; none for the hover's default label.
  final String? color;
  final bool named;

  static IconData icon(IdeGitRefKind kind) => switch (kind) {
    IdeGitRefKind.head => Codicons.target,
    IdeGitRefKind.branch => Codicons.gitBranch,
    IdeGitRefKind.remote => Codicons.cloud,
    IdeGitRefKind.tag => Codicons.tag,
  };

  @override
  Widget build(BuildContext context) {
    final kind = refs.first.kind;
    final branch = kind == IdeGitRefKind.branch;
    final colors = themeColors;
    final color = this.color;
    final foreground =
        colors[color == null
            ? 'scmGraph.historyItemHoverDefaultLabelForeground'
            : 'scmGraph.historyItemHoverLabelForeground'];
    return IdeHover(
      message: refs.map((r) => r.name).join(', '),
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color:
              colors[color ??
                  'scmGraph.historyItemHoverDefaultLabelBackground'],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refs.length > 1)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '${refs.length}',
                  style: TextStyle(fontSize: 12, color: foreground),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(branch ? 3 : 1),
              child: Icon(
                icon(kind),
                size: branch ? 12 : 16,
                color: foreground,
              ),
            ),
            if (named)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Text(
                    refs.first.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: foreground),
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
    this.referenceColors = const {},
  });

  final IdeGitCommit commit;

  /// The graph's color ids of [commit]'s references, by id; without any,
  /// the references are not shown.
  final Map<String, String> referenceColors;

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
          if (commit.references.isNotEmpty && referenceColors.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final ref in commit.references)
                  _RefBadge([ref], referenceColors[ref.id], named: true),
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

/// A file an expanded commit changed, beside the commit's lanes.
class _CommitChangeRow extends StatelessWidget {
  const _CommitChangeRow({
    required this.change,
    required this.root,
    required this.lanes,
    required this.highlight,
    required this.onOpen,
  });

  final IdeGitCommitChange change;
  final String root;
  final List<IdeGraphLane> lanes;
  final int highlight;
  final VoidCallback? onOpen;

  static IdeGitStatus _status(String letter) => switch (letter) {
    'A' => IdeGitStatus.indexAdded,
    'D' => IdeGitStatus.indexDeleted,
    'R' => IdeGitStatus.indexRenamed,
    'C' => IdeGitStatus.indexCopied,
    'T' => IdeGitStatus.typeChanged,
    _ => IdeGitStatus.indexModified,
  };

  @override
  Widget build(BuildContext context) {
    final status = _status(change.status);
    final folder = p.dirname(p.relative(change.path, from: root));
    return IdeListRow(
      onTap: onOpen,
      tooltip:
          '${p.relative(change.path, from: root)} • '
          '${status.localizedLabel(context.l10n)}',
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
          FileIcon(change.path),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IdeResourceLabel(
                name: p.basename(change.path),
                description: folder == '.' ? null : folder,
                strikeThrough: status.strikeThrough,
                letter: change.status,
                letterColor: status.color,
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
  const _LoadMoreRow({super.key, required this.lanes, required this.onShown});

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
