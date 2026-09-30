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
// src/vs/workbench/contrib/scm/browser/scmViewPane.ts, scmHistoryViewPane.ts
// and media/scm.css; the Git extension's commands, menus and messages
// (extensions/git/src/commands.ts, actionButton.ts and package.json).
//
// Deviations: a resource opens its file, not a diff editor; no push, pull,
// fetch or sync, stash, branch or tag commands; the smart commit's Always
// and Never last for the session; Generate Commit Message asks Claude
// Haiku (see commit_message.dart), where VS Code asks Copilot.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

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
    required this.onRevealInExplorer,
    this.trash,
    this.commitMessage,
  });

  final IdeWorkspace workspace;
  final IdeScmSession session;
  final IdeNotifications notifications;

  /// Opens a file in the editor.
  final Future<void> Function(String path, {bool focusEditor}) onOpen;
  final ValueChanged<String> onRevealInExplorer;

  /// Moves a file to the Trash (true once it did); null where there is no
  /// Trash, and untracked files are deleted.
  final Future<bool> Function(String path)? trash;

  /// Writes commit messages (Generate Commit Message); none offered when
  /// null.
  final IdeCommitMessageModel? commitMessage;

  @override
  State<IdeScmView> createState() => _IdeScmViewState();
}

class _IdeScmViewState extends State<IdeScmView> {
  final FocusNode _inputFocus = FocusNode(debugLabel: 'scm input');
  final FocusNode _listFocus = FocusNode(debugLabel: 'scm list');
  final FocusNode _graphFocus = FocusNode(debugLabel: 'scm graph');
  final ScrollController _changesScroll = ScrollController();
  final ScrollController _graphScroll = ScrollController();
  IdeInputValidation? _validation;

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
          const IdeViewTitle('Source Control'),
          Expanded(
            child: git == null
                ? const _Welcome(['No source control providers registered.'])
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
    final state = git.state;
    final Widget content;
    if (!git.loaded) {
      content = const SizedBox.shrink();
    } else if (state == null) {
      final error = git.error;
      content = error is IdeGitException && error.message.startsWith('Git is')
          ? _Welcome([
              'Install Git, a popular source control system, to track code '
                  'changes and collaborate with others.',
              error.message,
            ])
          : _Welcome(
              const [
                "The folder currently open doesn't have a Git repository. "
                    'You can initialize a repository which will enable source '
                    'control features powered by Git.',
              ],
              button: 'Initialize Repository',
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
            title: 'Changes',
            weight: 3,
            actions: [
              IdePaneAction(
                icon: Codicons.check,
                tooltip: 'Commit',
                onPressed: () => unawaited(_commit()),
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: 'Refresh',
                onPressed: () => unawaited(git.refresh()),
              ),
              IdeMenuButton(
                icon: Codicons.ellipsis,
                tooltip: 'More Actions...',
                entries: _moreActions,
              ),
            ],
            body: _changesList(git, state),
          ),
          IdePane(
            id: 'graph',
            title: 'Graph',
            weight: 2,
            actions: [
              IdePaneAction(
                icon: Codicons.target,
                tooltip: 'Go to Current History Item',
                onPressed: () => _goToCurrent(git),
              ),
              IdePaneAction(
                icon: Codicons.refresh,
                tooltip: 'Refresh',
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

  // --- Changes -------------------------------------------------------------

  Widget _changesList(IdeGitRepository git, IdeGitState state) {
    final items = <Widget>[_inputRow(state), _commitButtonRow(git, state)];
    for (final group in IdeGitGroup.values) {
      final resources = state.group(group);
      // Merge and Staged Changes hide when empty; Changes does not.
      if (resources.isEmpty && group != IdeGitGroup.workingTree) continue;
      items.add(_groupRow(git, group, resources));
      if (_session.collapsedGroups.contains(group)) continue;
      if (_session.treeView) {
        _addTreeRows(
          items,
          git,
          state,
          group,
          ideScmTree(state.root, resources),
        );
      } else {
        for (final resource in _sorted(resources)) {
          items.add(_resourceRow(git, state, resource));
        }
      }
    }
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

  /// The tree's rows under a group (depth 1): folders, expanded or not,
  /// and files.
  void _addTreeRows(
    List<Widget> items,
    IdeGitRepository git,
    IdeGitState state,
    IdeGitGroup group,
    List<IdeScmTreeNode> nodes, [
    int depth = 2,
  ]) {
    for (final node in nodes) {
      switch (node) {
        case IdeScmTreeFolder():
          final key = _folderKey(group, node);
          items.add(_folderRow(git, state, group, node, depth, key));
          if (!_session.collapsedFolders.contains(key)) {
            _addTreeRows(items, git, state, group, node.children, depth + 1);
          }
        case IdeScmTreeFile(:final resource):
          items.add(_resourceRow(git, state, resource, treeDepth: depth));
      }
    }
  }

  static String _folderKey(IdeGitGroup group, IdeScmTreeFolder folder) =>
      '${group.name}:folder:${folder.path}';

  /// `Menus.ViewSort`: View as List or Tree, and the list's order.
  List<IdeMenuEntry> _viewSortMenu() => ideMenuGroups([
    [
      IdeMenuAction(
        'View as List',
        checked: !_session.treeView,
        onSelected: () => setState(() => _session.treeView = false),
      ),
      IdeMenuAction(
        'View as Tree',
        checked: _session.treeView,
        onSelected: () => setState(() => _session.treeView = true),
      ),
    ],
    [
      for (final (sort, label) in const [
        (IdeScmSort.name, 'Sort Changes by Name'),
        (IdeScmSort.path, 'Sort Changes by Path'),
        (IdeScmSort.status, 'Sort Changes by Status'),
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
        'Stage Changes',
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
    IdeGitGroup.staged => [
      _Action(
        'Unstage Changes',
        Codicons.remove,
        () => unawaited(_run(() => git.unstage(resources))),
      ),
    ],
    IdeGitGroup.workingTree => [
      _Action(
        'Discard Changes',
        Codicons.discard,
        () => unawaited(_discard(resources)),
      ),
      _Action(
        'Stage Changes',
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
  };

  String get _commitKey =>
      const IdeKeybinding(LogicalKeyboardKey.enter, primary: true).label();

  Widget _inputRow(IdeGitState state) {
    final branch = state.head.branch;
    return Padding(
      key: const ValueKey('input'),
      padding: const EdgeInsets.fromLTRB(19, 5, 12, 5),
      child: IdeInputBox(
        controller: _session.message,
        focusNode: _inputFocus,
        semanticsLabel: 'Source Control Input',
        placeholder: branch == null
            ? 'Message ($_commitKey to commit)'
            : 'Message ($_commitKey to commit on "$branch")',
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
                  ? 'Generate Commit Message'
                  : 'Cancel Generating Commit Message',
              size: 20,
              onPressed: () => unawaited(_generateCommitMessage(state)),
            ),
        ],
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
              unawaited(_commit()),
          const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
              unawaited(_commit()),
        },
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
          'There are no changes to generate a commit message for.',
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

  Widget _commitButtonRow(IdeGitRepository git, IdeGitState state) {
    final enabled = state.resources.isNotEmpty && !git.busy;
    return Padding(
      key: const ValueKey('commit-button'),
      padding: const EdgeInsets.fromLTRB(19, 4, 12, 4),
      child: _SplitButton(
        icon: Codicons.check,
        label: 'Commit',
        tooltip: 'Commit Changes',
        enabled: enabled,
        onPressed: () => unawaited(_commit()),
        dropdownTooltip: 'More Actions...',
        onDropdown: (anchor) => unawaited(
          showIdeMenu(
            context,
            anchor: anchor,
            alignRight: true,
            entries: ideMenuGroups([
              [IdeMenuAction('Commit', onSelected: () => unawaited(_commit()))],
              [
                IdeMenuAction(
                  'Commit (Amend)',
                  onSelected: () => unawaited(_commit(amend: true)),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }

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
                  'Collapse All',
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
                group.label,
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
        'Stage All Merge Changes',
        Codicons.add,
        () => unawaited(_run(() => git.stage(resources))),
      ),
    ],
    IdeGitGroup.staged => [
      _Action(
        'Unstage All Changes',
        Codicons.remove,
        () => unawaited(_run(git.unstageAll)),
      ),
    ],
    IdeGitGroup.workingTree => [
      _Action(
        'Discard All Changes',
        Codicons.discard,
        () => unawaited(_discard(resources)),
      ),
      _Action(
        'Stage All Changes',
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
        'Open File',
        Codicons.goToFile,
        () => unawaited(widget.onOpen(resource.path, focusEditor: true)),
      ),
    ...switch (resource.group) {
      IdeGitGroup.merge => [
        _Action(
          'Stage Changes',
          Codicons.add,
          () => unawaited(_run(() => git.stage([resource]))),
        ),
      ],
      IdeGitGroup.staged => [
        _Action(
          'Unstage Changes',
          Codicons.remove,
          () => unawaited(_run(() => git.unstage([resource]))),
        ),
      ],
      IdeGitGroup.workingTree => [
        _Action(
          'Discard Changes',
          Codicons.discard,
          () => unawaited(_discard([resource])),
        ),
        _Action(
          'Stage Changes',
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
    void open({bool focus = false}) {
      if (_deleted(resource)) return;
      unawaited(widget.onOpen(resource.path, focusEditor: focus));
    }

    return IdeListRow(
      key: ValueKey(key),
      selected: _selected == key,
      focused: _listFocus.hasFocus,
      tooltip: '${p.join(state.root, relative)} • ${resource.status.label}',
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
    return showIdeMenu(
      context,
      position: position,
      entries: ideMenuGroups([
        [
          if (!_deleted(resource))
            IdeMenuAction(
              'Open File',
              onSelected: () =>
                  unawaited(widget.onOpen(resource.path, focusEditor: true)),
            ),
        ],
        [
          if (resource.group == IdeGitGroup.staged)
            IdeMenuAction(
              'Unstage Changes',
              onSelected: () => unawaited(_run(() => git.unstage([resource]))),
            )
          else
            IdeMenuAction(
              'Stage Changes',
              onSelected: () => unawaited(_run(() => git.stage([resource]))),
            ),
          if (working) ...[
            IdeMenuAction(
              'Discard Changes',
              onSelected: () => unawaited(_discard([resource])),
            ),
            IdeMenuAction(
              'Add to .gitignore',
              onSelected: () => unawaited(_ignore(state, [resource.path])),
            ),
          ],
        ],
        [
          if (WindowControls.canRevealInFileManager && !_deleted(resource))
            IdeMenuAction(
              'Reveal in Finder',
              onSelected: () =>
                  unawaited(WindowControls.revealInFileManager(resource.path)),
            ),
          if (!_deleted(resource))
            IdeMenuAction(
              'Reveal in Explorer View',
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
    return [
      IdeMenuAction('View & Sort', submenu: _viewSortMenu()),
      const IdeMenuSeparator(),
      IdeMenuAction(
        'Commit',
        submenu: ideMenuGroups([
          [
            IdeMenuAction('Commit', onSelected: () => unawaited(_commit())),
            IdeMenuAction(
              'Commit Staged',
              onSelected: () => unawaited(_commit(all: false)),
            ),
            IdeMenuAction(
              'Commit All',
              onSelected: () => unawaited(_commit(all: true)),
            ),
            IdeMenuAction(
              'Undo Last Commit',
              onSelected: () => unawaited(_undoLastCommit()),
            ),
          ],
          [
            IdeMenuAction(
              'Commit (Amend)',
              onSelected: () => unawaited(_commit(amend: true)),
            ),
            IdeMenuAction(
              'Commit Staged (Amend)',
              onSelected: () => unawaited(_commit(all: false, amend: true)),
            ),
            IdeMenuAction(
              'Commit All (Amend)',
              onSelected: () => unawaited(_commit(all: true, amend: true)),
            ),
          ],
        ]),
      ),
      IdeMenuAction(
        'Changes',
        submenu: [
          IdeMenuAction(
            'Stage All Changes',
            onSelected: () => unawaited(_run(git.stageAll)),
          ),
          IdeMenuAction(
            'Unstage All Changes',
            onSelected: () => unawaited(_run(git.unstageAll)),
          ),
          IdeMenuAction(
            'Discard All Changes',
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
    final message = _session.message.text;
    if (message.trim().isEmpty && !amend) {
      setState(
        () => _validation = const IdeInputValidation(
          'Please provide a commit message',
        ),
      );
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
          message:
              'There are no staged changes to commit.\n\nWould you like to '
              'stage all your changes and commit them directly?',
          buttons: const ['Yes', 'Always', 'Never'],
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
        'There are no changes to commit.',
        primary: [
          IdeNotificationAction(
            'Create Empty Commit',
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
    try {
      final head = await git.headCommit();
      if (!mounted) return;
      if (head == null) {
        widget.notifications.notify(
          IdeSeverity.warning,
          "Can't undo because HEAD doesn't point to any commit.",
        );
        return;
      }
      if (head.parentIds.length > 1) {
        final pick = await showIdeDialog(
          context,
          message:
              'The last commit was a merge commit. Are you sure you want to '
              'undo it?',
          buttons: const ['Undo merge commit'],
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
    String name(IdeGitResource r) => p.basename(r.path);

    (String, String?, String) untrackedDialog(List<IdeGitResource> files) {
      final one = files.length == 1;
      final warning = toTrash
          ? ''
          : one
          ? '\n\nThis is IRREVERSIBLE!\nThis file will be FOREVER LOST if you '
                'proceed.'
          : '\n\nThis is IRREVERSIBLE!\nThese files will be FOREVER LOST if '
                'you proceed.';
      return (
        one
            ? "Are you sure you want to DELETE the following untracked file: "
                  "'${name(files.single)}'?$warning"
            : 'Are you sure you want to DELETE the ${files.length} untracked '
                  'files?$warning',
        toTrash
            ? (one
                  ? 'You can restore this file from the Trash.'
                  : 'You can restore these files from the Trash.')
            : null,
        toTrash
            ? 'Move to Trash'
            : one
            ? 'Delete File'
            : 'Delete All ${files.length} Files',
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
                  ? "Are you sure you want to restore '${name(tracked.single)}'?"
                  : 'Are you sure you want to restore ALL ${tracked.length} '
                        'files?')
            : (one
                  ? "Are you sure you want to discard changes in "
                        "'${name(tracked.single)}'?"
                  : 'Are you sure you want to discard ALL changes in '
                        '${tracked.length} files?\n\nThis is IRREVERSIBLE!\n'
                        'Your current working set will be FOREVER LOST if you '
                        'proceed.'),
        buttons: [
          allDeleted
              ? (one ? 'Restore File' : 'Restore All ${tracked.length} Files')
              : (one ? 'Discard File' : 'Discard All ${tracked.length} Files'),
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
          ? "\n\nAre you sure you want to discard changes in "
                "'${name(tracked.single)}'?"
          : '\n\nAre you sure you want to discard ALL changes in '
                '${tracked.length} files?';
      final pick = await showIdeDialog(
        context,
        message:
            '$untrackedMessage ${untrackedDetail ?? ''}$trackedMessage\n\n'
            'This is IRREVERSIBLE!\nYour current working set will be FOREVER '
            'LOST if you proceed.',
        buttons: [
          tracked.length == 1
              ? 'Discard 1 Tracked File'
              : 'Discard All ${tracked.length} Tracked Files',
          'Discard All ${resources.length} Files',
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
                        'Copy Commit Hash',
                        onSelected: () => unawaited(
                          Clipboard.setData(ClipboardData(text: commit.id)),
                        ),
                      ),
                      IdeMenuAction(
                        'Copy Commit Message',
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
                          text: commit.subject,
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
    this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    this.dropdownTooltip,
    this.onDropdown,
  });

  final IconData? icon;
  final String label;
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
                if (widget.icon case final icon?) ...[
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
      return Text(commit.subject, style: text);
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
                      ' ${ideFromNow(commit.date, ago: true, fullWords: true)} '
                      '(${_formatDate(commit.date)})',
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

  static String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July', //
      'August', 'September', 'October', 'November', 'December',
    ];
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final minute = date.minute.toString().padLeft(2, '0');
    return '${months[date.month - 1]} ${date.day}, ${date.year} at '
        '$hour:$minute ${date.hour < 12 ? 'AM' : 'PM'}';
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
      tooltip: '${p.relative(change.path, from: root)} • ${status.label}',
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
