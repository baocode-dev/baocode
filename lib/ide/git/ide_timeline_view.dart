/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The explorer's Timeline pane with the Git extension's provider: the
// active editor's file's commits (and its staged changes), newest first,
// each with its author and how long ago.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/timeline/browser/timelinePane.ts and
// media/timelinePane.css; extensions/git/src/timelineProvider.ts; the
// keyboard's `list.*` (src/vs/workbench/browser/actions/listCommands.ts,
// through [IdeKeyboardList]).
//
// Deviations: Git is the only source (no local history), and an item does
// not open a diff editor (Enter selects it; on Load more, loads more).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart';
import '../ide_dates.dart';
import '../ide_hover.dart';
import '../ide_list.dart';
import '../ide_menu.dart';
import 'git_model.dart';
import 'git_repository.dart';
import 'ide_scm_view.dart';

/// What the Timeline pane follows: the active editor's file, or the file
/// it was pinned to. Kept by the workbench, as are its pane's actions.
class IdeTimelineController extends ChangeNotifier {
  String? _pinned;
  int _generation = 0;

  /// The file the timeline stays on while other editors activate.
  String? get pinned => _pinned;

  /// Refresh: reads the history again.
  int get generation => _generation;

  /// Pin the Current Timeline / Unpin the Current Timeline.
  void togglePin(String? current) {
    _pinned = _pinned == null ? current : null;
    notifyListeners();
  }

  void refresh() {
    _generation++;
    notifyListeners();
  }
}

/// One of the timeline's items: a commit, or (first) the file's staged
/// changes.
class _TimelineItem {
  const _TimelineItem.commit(IdeGitCommit this.commit)
    : label = null,
      status = null;
  const _TimelineItem.staged(this.status)
    : commit = null,
      label = 'Staged Changes';

  final IdeGitCommit? commit;
  final String? label;
  final IdeGitStatus? status;
}

class IdeTimelineView extends StatefulWidget {
  const IdeTimelineView({
    super.key,
    required this.controller,
    required this.git,
    required this.activePath,
  });

  final IdeTimelineController controller;

  /// The provider; null where there is no repository.
  final IdeGitRepository? git;

  /// The active editor's file; null for none.
  final String? activePath;

  /// Items read per page (`timeline.pageSize`'s fallback).
  static const pageSize = 50;

  /// The file [controller] shows for [activePath].
  static String? pathOf(IdeTimelineController controller, String? activePath) =>
      controller.pinned ?? activePath;

  @override
  State<IdeTimelineView> createState() => _IdeTimelineViewState();
}

class _IdeTimelineViewState extends State<IdeTimelineView>
    with IdeKeyboardList<IdeTimelineView> {
  final _focus = FocusNode(debugLabel: 'timeline');
  final _scroll = ScrollController();

  /// [_selected] on Load more.
  static const _loadMoreId = 'more';

  int _limit = IdeTimelineView.pageSize;
  Object? _key;
  String? _keyPath;
  List<IdeGitCommit>? _commits;
  bool _more = false;
  Object? _error;
  String? _selected;
  int _request = 0;

  String? get _path =>
      IdeTimelineView.pathOf(widget.controller, widget.activePath);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.git?.addListener(_changed);
    _focus.addListener(_focusChanged);
    _load();
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(IdeTimelineView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    if (oldWidget.git != widget.git) {
      oldWidget.git?.removeListener(_changed);
      widget.git?.addListener(_changed);
    }
    _load();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.git?.removeListener(_changed);
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(_load);
  }

  /// The file's resources in Git's state: a commit or a change to them is
  /// what makes the history worth reading again.
  List<IdeGitResource> _resources(String path) => [
    for (final resource
        in widget.git?.state?.resources ?? const <IdeGitResource>[])
      if (resource.path == path) resource,
  ];

  /// Reads the history when what it depends on changed.
  void _load() {
    final path = _path;
    final git = widget.git;
    final head = git?.state?.head;
    final key = (
      path,
      git,
      widget.controller.generation,
      _limit,
      head?.branch,
      head?.ahead,
      head?.unborn,
      path == null ? null : Object.hashAll(_resources(path)),
    );
    if (key == _key) return;
    _key = key;
    if (path != _keyPath) {
      _keyPath = path;
      _limit = IdeTimelineView.pageSize;
      _commits = null;
      _selected = null;
    }
    _error = null;
    if (path == null || git == null || !git.isRepository) {
      _commits = null;
      return;
    }
    final request = ++_request;
    final limit = _limit;
    unawaited(
      git.service
          .fileLog(path, limit: limit + 1)
          .then(
            (commits) {
              if (!mounted || request != _request) return;
              setState(() {
                _more = commits.length > limit;
                _commits = commits.take(limit).toList();
              });
            },
            onError: (Object error) {
              if (!mounted || request != _request) return;
              setState(() {
                _error = error;
                _commits = const [];
              });
            },
          ),
    );
  }

  void _loadMore() {
    setState(() => _limit += IdeTimelineView.pageSize);
    _load();
  }

  /// The items [build] lists: the file's staged change, then its commits;
  /// none while there is no history.
  List<_TimelineItem> _itemsOf(String path, List<IdeGitCommit> commits) {
    final staged = _resources(path)
        .where((resource) => resource.group == IdeGitGroup.staged)
        .firstOrNull;
    return [
      if (staged != null) _TimelineItem.staged(staged.status),
      for (final commit in commits) _TimelineItem.commit(commit),
    ];
  }

  /// The rows' ids (Load more's last), as [_selected] holds them.
  List<String> get _rowIds {
    final path = _path;
    final commits = _commits;
    if (path == null || commits == null || widget.git == null) {
      return const [];
    }
    final items = _itemsOf(path, commits);
    return [
      for (final item in items) item.commit?.id ?? '~',
      if (_more && items.isNotEmpty) _loadMoreId,
    ];
  }

  @override
  bool get listHasFocus => _focus.hasFocus;

  @override
  int get listLength => _rowIds.length;

  @override
  int get listFocusedIndex =>
      _selected == null ? -1 : _rowIds.indexOf(_selected!);

  @override
  int get listPageSize => ideRowsPerPage(_scroll);

  @override
  void listFocusAt(int index) {
    setState(() => _selected = _rowIds[index]);
    ideRevealRow(_scroll, index);
  }

  @override
  void listSelect() {
    if (_selected == _loadMoreId) _loadMore();
  }

  Future<void> _showMenu(Offset position, IdeGitCommit commit) {
    setState(() => _selected = commit.id);
    return showIdeMenu(
      context,
      position: position,
      entries: [
        IdeMenuAction(
          context.l10n.timelineCopyCommitId,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: commit.id))),
        ),
        IdeMenuAction(
          context.l10n.scmCopyCommitMessage,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: commit.message))),
        ),
      ],
    );
  }

  Widget _message(String text) => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: themeColors['sideBar.foreground'],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final path = _path;
    final git = widget.git;
    final l10n = context.l10n;
    if (path == null) return _message(l10n.timelineNoEditor);
    if (git == null || (git.loaded && !git.isRepository)) {
      return _message(l10n.timelineNotConfigured);
    }
    final commits = _commits;
    if (commits == null) {
      return _message(l10n.timelineLoading(p.basename(path)));
    }
    final items = _itemsOf(path, commits);
    if (items.isEmpty) {
      return _message(_error == null ? l10n.timelineNone : '$_error');
    }
    final now = DateTime.now();
    String? previous;
    final rows = <Widget>[];
    for (final item in items) {
      final date = item.commit?.date ?? now;
      final relative = ideFromNow(date, now: now, l10n: l10n);
      final duplicate = relative == previous;
      previous = relative;
      rows.add(_row(item, relative, duplicate: duplicate));
    }
    if (_more) {
      rows.add(
        IdeListRow(
          selected: _selected == _loadMoreId,
          focused: _focus.hasFocus,
          onTap: () {
            _focus.requestFocus();
            _loadMore();
          },
          builder: (context, _) => Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.timelineLoadMore,
                style: TextStyle(
                  fontSize: 13,
                  color: themeColors['sideBar.foreground'],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Focus(
      focusNode: _focus,
      child: ListView(
        controller: _scroll,
        itemExtent: IdeListColors.rowHeight,
        children: rows,
      ),
    );
  }

  Widget _row(_TimelineItem item, String relative, {required bool duplicate}) {
    final commit = item.commit;
    final id = commit?.id ?? '~';
    final selected = _selected == id;
    final colors = themeColors;
    final foreground = colors['sideBar.foreground'];
    final row = IdeListRow(
      key: ValueKey('timeline:$id'),
      selected: selected,
      focused: _focus.hasFocus,
      onTap: () {
        _focus.requestFocus();
        setState(() => _selected = id);
      },
      onContextMenu: commit == null
          ? null
          : (position) => unawaited(_showMenu(position, commit)),
      builder: (context, hovered) => Padding(
        padding: const EdgeInsets.only(left: 16),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Icon(Codicons.gitCommit, size: 16, color: foreground),
            ),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: commit?.subject ?? context.l10n.scmGroupStaged,
                    ),
                    if (commit != null)
                      TextSpan(
                        text: '  ${commit.author}',
                        style: TextStyle(
                          fontSize: 13 * .9,
                          color: colors['descriptionForeground'],
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected
                      ? colors.get('list.activeSelectionForeground') ??
                            foreground
                      : foreground,
                ),
              ),
            ),
            // `.timeline-timestamp-container`: dimmed; a time equal to the
            // previous one is a thin line instead.
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 4),
              child: Opacity(
                opacity: .5,
                child: duplicate
                    ? SizedBox(
                        width: 10,
                        height: IdeListColors.rowHeight,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Opacity(
                            opacity: .25,
                            child: SizedBox(
                              width: 1,
                              height: IdeListColors.rowHeight,
                              child: ColoredBox(color: foreground),
                            ),
                          ),
                        ),
                      )
                    : Text(
                        relative,
                        style: TextStyle(fontSize: 13, color: foreground),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
    if (commit == null) {
      return IdeHover(
        message:
            '${context.l10n.timelineYou(ideFromNow(DateTime.now(), ago: true, fullWords: true, l10n: context.l10n))}'
            '\n\n${item.status?.localizedLabel(context.l10n) ?? ''}',
        child: row,
      );
    }
    return IdeHover(
      content: IdeCommitHover(commit),
      position: IdeHoverPosition.right,
      compact: false,
      child: row,
    );
  }
}
