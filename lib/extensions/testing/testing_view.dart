/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The Testing view: the extensions' tests as a tree with each test's state
// from the newest run that has it, Run and Debug on each row and for all,
// Refresh and Cancel, a summary of the last run, and a failed test's
// messages under it, a click going to the failure.
//
// Adapted from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/testing/browser/testingExplorerView.ts (the
// tree, its rows' actions, the result summary `TestResultsViewContent`'s
// counts), icons.ts (`testingStatesToIcons`), theme.ts (the icons' colors),
// testExplorerActions.ts (Run All, Debug All, Refresh, Cancel, Go to Test,
// Go to Next Failure) and explorerProjections/treeProjection.ts (expanding
// a node asks its controller for children).
//
// Deviations: failures show as rows under their test (upstream opens a
// peek view in the editor); the Test Results panel is the "Test Results"
// output channel; no filter box, no `testing/item/context` menus, no
// gutter decorations.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart';
import 'test_service.dart';

/// `testingStatesToIcons`.
IconData testStateIcon(int state) => switch (state) {
  TestResultState.errored => Codicons.issues,
  TestResultState.failed => Codicons.error,
  TestResultState.passed => Codicons.pass,
  TestResultState.queued => Codicons.history,
  TestResultState.running => Codicons.loading,
  TestResultState.skipped => Codicons.debugStepOver,
  _ => Codicons.circleOutline,
};

/// `testStatesToIconColors`.
Color testStateColor(int state) => switch (state) {
  TestResultState.errored =>
    themeColors.get('testing.iconErrored') ??
        themeColors.get('list.errorForeground') ??
        const Color(0xfff14c4c),
  TestResultState.failed =>
    themeColors.get('testing.iconFailed') ??
        themeColors.get('list.errorForeground') ??
        const Color(0xfff14c4c),
  TestResultState.passed =>
    themeColors.get('testing.iconPassed') ?? const Color(0xff73c991),
  TestResultState.queued =>
    themeColors.get('testing.iconQueued') ??
        themeColors.get('list.warningForeground') ??
        const Color(0xffcca700),
  TestResultState.running => themeColors['icon.foreground'],
  _ => themeColors.get('testing.iconUnset') ?? const Color(0xff848484),
};

/// The view's state kept while another view shows.
final class TestingViewSession {
  final Set<String> collapsed = {};
  final Set<String> expandedFailures = {};
  int _nextFailure = 0;
}

class TestingView extends StatefulWidget {
  const TestingView({
    super.key,
    required this.service,
    required this.session,
    required this.onOpen,
    this.onShowOutput,
  });

  final TestService service;
  final TestingViewSession session;

  /// Opens a file at a range (Go to Test, a failure).
  final void Function(VsUri uri, TestRange? range) onOpen;

  /// Shows the Test Results output.
  final VoidCallback? onShowOutput;

  @override
  State<TestingView> createState() => TestingViewState();
}

/// A row of the tree: a test, or one of a failed test's messages.
sealed class _Row {
  const _Row(this.depth);
  final int depth;
}

final class _TestRow extends _Row {
  const _TestRow(this.item, super.depth, {required this.hasChildren});
  final TestCollectionItem item;
  final bool hasChildren;
}

final class _MessageRow extends _Row {
  const _MessageRow(this.test, this.message, super.depth);
  final TestResultItem test;
  final TestMessage message;
}

class TestingViewState extends State<TestingView> {
  final FocusNode _focus = FocusNode(debugLabel: 'testing view');
  String? _selected;
  final Set<String> _expandedRoots = {};

  TestService get _service => widget.service;
  TestingViewSession get _session => widget.session;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Expanding asks the controller for children
  /// (`TreeProjection.expandElement`), roots once as they show.
  void _ensureRootsExpanded() {
    for (final root in _service.roots) {
      if (_expandedRoots.add(root.item.extId)) {
        unawaited(
          _service.expand(root.item.extId, 0).catchError((Object _) {}),
        );
      }
    }
  }

  List<_Row> _rows() {
    final rows = <_Row>[];
    void visit(TestCollectionItem item, int depth) {
      final children = _service.childrenOf(item);
      final expandable =
          children.isNotEmpty ||
          item.expand == TestItemExpandState.expandable ||
          item.expand == TestItemExpandState.busyExpanding;
      rows.add(_TestRow(item, depth, hasChildren: expandable));
      final state = _service.stateOf(item.item.extId)?.$2;
      if (state != null &&
          TestResultState.isFailed(state.ownComputedState) &&
          _session.expandedFailures.contains(item.item.extId)) {
        for (final message in state.errors) {
          rows.add(_MessageRow(state, message, depth + 1));
        }
      }
      if (_session.collapsed.contains(item.item.extId)) return;
      for (final child in children) {
        visit(child, depth + 1);
      }
    }

    final roots = _service.roots;
    // One controller: its children are the tree's top (upstream hides a
    // single root).
    if (roots.length == 1) {
      for (final child in _service.childrenOf(roots.single)) {
        visit(child, 0);
      }
    } else {
      for (final root in roots) {
        visit(root, 0);
      }
    }
    return rows;
  }

  void _toggle(TestCollectionItem item) {
    final id = item.item.extId;
    setState(() {
      if (!_session.collapsed.remove(id)) _session.collapsed.add(id);
    });
    if (!_session.collapsed.contains(id)) {
      unawaited(_service.expand(id, 0).catchError((Object _) {}));
    }
  }

  void _openTest(TestCollectionItem item) {
    final uri = item.item.uri;
    if (uri != null) widget.onOpen(uri, item.item.range);
  }

  void _openMessage(TestResultItem test, TestMessage message) {
    if (message.location case final location?) {
      widget.onOpen(location.uri, location.range);
    } else if (test.item.uri case final uri?) {
      widget.onOpen(uri, test.item.range);
    }
  }

  Future<void> runAll(int group) =>
      _service.runAll(group).then((_) {}).catchError((Object _) {});

  /// `testing.goToNextMessage`: the next failure of the newest run.
  void goToNextFailure() {
    final failures = _service.failures();
    if (failures.isEmpty) return;
    final index = _session._nextFailure++ % failures.length;
    final (test, message) = failures[index];
    setState(() => _session.expandedFailures.add(test.item.extId));
    _openMessage(test, message);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _service,
    builder: (context, _) {
      _ensureRootsExpanded();
      final rows = _rows();
      return ColoredBox(
        color: themeColors['sideBar.background'],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdeViewTitle(
              'Testing',
              actions: [
                if (_service.hasGroup(TestRunGroup.run))
                  IdePaneAction(
                    icon: Codicons.runAll,
                    tooltip: 'Run Tests',
                    onPressed: () => unawaited(runAll(TestRunGroup.run)),
                  ),
                if (_service.hasGroup(TestRunGroup.debug))
                  IdePaneAction(
                    icon: Codicons.debugAll,
                    tooltip: 'Debug Tests',
                    onPressed: () => unawaited(runAll(TestRunGroup.debug)),
                  ),
                IdePaneAction(
                  icon: Codicons.refresh,
                  tooltip: 'Refresh Tests',
                  onPressed: () =>
                      unawaited(_service.refresh().catchError((Object _) {})),
                ),
                if (_service.isRunning)
                  IdePaneAction(
                    icon: Codicons.debugStop,
                    tooltip: 'Cancel Test Run',
                    onPressed: _service.cancel,
                  ),
                IdePaneAction(
                  icon: Codicons.output,
                  tooltip: 'Show Output',
                  onPressed: widget.onShowOutput,
                ),
              ],
            ),
            _Summary(service: _service),
            Expanded(
              child: rows.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _service.roots.isEmpty
                            ? 'No tests have been found in this workspace yet.'
                            : 'Discovering tests…',
                        style: TextStyle(
                          fontSize: 13,
                          color: IdeListColors.description,
                        ),
                      ),
                    )
                  : Focus(
                      focusNode: _focus,
                      onFocusChange: (_) => setState(() {}),
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemExtent: IdeListColors.rowHeight,
                        itemBuilder: (context, index) => switch (rows[index]) {
                          final _TestRow row => _testRow(row),
                          final _MessageRow row => _messageRow(row),
                        },
                      ),
                    ),
            ),
          ],
        ),
      );
    },
  );

  Widget _testRow(_TestRow row) {
    final item = row.item;
    final id = item.item.extId;
    final state = _service.stateOf(id)?.$2;
    final computed = state?.computedState ?? TestResultState.unset;
    final failed =
        state != null && TestResultState.isFailed(state.ownComputedState);
    final collapsed = _session.collapsed.contains(id);
    final canRun = _service
        .profilesOf(item.controllerId)
        .any((p) => p.group & TestRunGroup.run != 0 && p.canRun(item));
    final canDebug = _service
        .profilesOf(item.controllerId)
        .any((p) => p.group & TestRunGroup.debug != 0 && p.canRun(item));
    return IdeListRow(
      key: ValueKey('test:$id'),
      selected: _selected == id,
      focused: _focus.hasFocus,
      tooltip: item.item.error ?? state?.errors.firstOrNull?.message,
      onTap: () {
        setState(() => _selected = id);
        _focus.requestFocus();
        if (failed) {
          setState(() {
            if (!_session.expandedFailures.remove(id)) {
              _session.expandedFailures.add(id);
            }
          });
        }
      },
      onDoubleTap: () => _openTest(item),
      onContextMenu: (position) => unawaited(
        showIdeMenu(
          context,
          position: position,
          entries: [
            if (canRun)
              IdeMenuAction(
                'Run Test',
                onSelected: () => unawaited(
                  _service
                      .runTests(TestRunGroup.run, [id])
                      .catchError((Object _) => null),
                ),
              ),
            if (canDebug)
              IdeMenuAction(
                'Debug Test',
                onSelected: () => unawaited(
                  _service
                      .runTests(TestRunGroup.debug, [id])
                      .catchError((Object _) => null),
                ),
              ),
            if (item.item.uri != null)
              IdeMenuAction('Go to Test', onSelected: () => _openTest(item)),
          ],
        ),
      ),
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: IdeListColors.inset + row.depth * IdeListColors.indent,
          right: 4,
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: row.hasChildren ? () => _toggle(item) : null,
              child: SizedBox(
                width: 16,
                child: row.hasChildren
                    ? Icon(
                        collapsed
                            ? Codicons.chevronRight
                            : Codicons.chevronDown,
                        size: 16,
                        color: themeColors['icon.foreground'],
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              item.item.busy ? Codicons.loading : testStateIcon(computed),
              size: 16,
              color: testStateColor(computed),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: state?.retired ?? false
                      ? IdeListColors.description
                      : IdeListColors.foreground,
                ),
              ),
            ),
            if (item.item.description case final description?)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(
                    description,
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
            if (hovered || _selected == id) ...[
              if (canRun)
                IdeActionButton(
                  icon: Codicons.run,
                  tooltip: 'Run Test',
                  size: 20,
                  onPressed: () => unawaited(
                    _service
                        .runTests(TestRunGroup.run, [id])
                        .catchError((Object _) => null),
                  ),
                ),
              if (canDebug)
                IdeActionButton(
                  icon: Codicons.debugAlt,
                  tooltip: 'Debug Test',
                  size: 20,
                  onPressed: () => unawaited(
                    _service
                        .runTests(TestRunGroup.debug, [id])
                        .catchError((Object _) => null),
                  ),
                ),
              if (item.item.uri != null)
                IdeActionButton(
                  icon: Codicons.goToFile,
                  tooltip: 'Go to Test',
                  size: 20,
                  onPressed: () => _openTest(item),
                ),
            ] else if (state?.ownDuration case final duration?)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  _duration(duration),
                  style: TextStyle(
                    fontSize: 11,
                    color: IdeListColors.description,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _messageRow(_MessageRow row) {
    final key = 'message:${row.test.item.extId}:${row.message.hashCode}';
    final firstLine = row.message.message.split('\n').first;
    return IdeListRow(
      key: ValueKey(key),
      selected: _selected == key,
      focused: _focus.hasFocus,
      tooltip: [
        row.message.message,
        if (row.message.expected case final expected?) 'Expected: $expected',
        if (row.message.actual case final actual?) 'Actual: $actual',
      ].join('\n'),
      onTap: () {
        setState(() => _selected = key);
        _openMessage(row.test, row.message);
      },
      builder: (context, hovered) => Padding(
        padding: EdgeInsets.only(
          left: IdeListColors.inset + row.depth * IdeListColors.indent + 18,
          right: 8,
        ),
        child: Row(
          children: [
            Icon(
              Codicons.error,
              size: 14,
              color: testStateColor(TestResultState.failed),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                firstLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: IdeListColors.foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _duration(num ms) =>
    ms < 1000 ? '${ms.round()}ms' : '${(ms / 1000).toStringAsFixed(1)}s';

/// The newest run's counts (`TestResultsViewContent`'s summary).
class _Summary extends StatelessWidget {
  const _Summary({required this.service});

  final TestService service;

  @override
  Widget build(BuildContext context) {
    final result = service.results.firstOrNull;
    if (result == null) return const SizedBox.shrink();
    final passed = result.counts[TestResultState.passed]!;
    final failed =
        result.counts[TestResultState.failed]! +
        result.counts[TestResultState.errored]!;
    final total = result.tests.where((t) => t.children.isEmpty).length;
    final elapsed = (result.completedAt ?? DateTime.now()).difference(
      result.startedAt,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Row(
        children: [
          Icon(
            result.isComplete
                ? (failed > 0 ? Codicons.error : Codicons.pass)
                : Codicons.loading,
            size: 14,
            color: testStateColor(
              !result.isComplete
                  ? TestResultState.running
                  : failed > 0
                  ? TestResultState.failed
                  : TestResultState.passed,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              result.isComplete
                  ? '$passed/$total tests passed '
                        '(${_duration(elapsed.inMilliseconds)})'
                  : 'Running tests…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: IdeListColors.description),
            ),
          ),
        ],
      ),
    );
  }
}
