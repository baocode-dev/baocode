// The Watch view: expressions evaluated in the focused frame on every
// stop, expandable like variables; added, edited, reordered and removed.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/watchExpressionsView.ts.
//
// Deviations: no drag and drop (move is in the context menu).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_model.dart';
import '../service/debug_service.dart';
import 'debug_strings.dart';
import 'debug_tree.dart';
import 'debug_widgets.dart';

class _WatchDataSource extends DebugTreeDataSource<Object> {
  @override
  String idOf(Object element) => (element as DebugTreeElement).getId();

  @override
  bool hasChildren(Object element) => element is ExpressionContainer && element.hasChildren;

  @override
  Future<List<Object>> getChildren(Object element) async =>
      element is ExpressionContainer ? await element.getChildren() : const [];
}

/// The Watch pane's title actions.
List<Widget> watchViewActions(BuildContext context, DebugService service, {VoidCallback? onCollapseAll}) {
  final s = DebugStrings.of(context);
  return [
    IdePaneAction(icon: Codicons.add, tooltip: s.addExpression, onPressed: service.addWatchExpression),
    if (onCollapseAll != null) IdePaneAction(icon: Codicons.collapseAll, tooltip: s.collapseAll, onPressed: onCollapseAll),
    IdePaneAction(
      icon: Codicons.closeAll,
      tooltip: s.removeAllExpressions,
      onPressed: service.model.getWatchExpressions().isEmpty ? null : () => service.removeWatchExpressions(),
    ),
  ];
}

class WatchView extends StatefulWidget {
  const WatchView({super.key, required this.service, this.collapseAll});

  final DebugService service;

  /// Fires to collapse every expression (the title action).
  final Listenable? collapseAll;

  @override
  State<WatchView> createState() => _WatchViewState();
}

class _WatchViewState extends State<WatchView> {
  late final DebugTreeController<Object> _controller = DebugTreeController(_WatchDataSource());
  final DisposableStore _listeners = DisposableStore();
  String? _editingId;
  int _generation = 0;

  DebugService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _listeners
      ..add(_service.viewModel.onDidFocusStackFrame((_) => _evaluateAll()))
      ..add(_service.viewModel.onWillUpdateViews(_evaluateAll))
      ..add(_service.model.onDidChangeWatchExpressions((e) => _evaluateAll(e)))
      ..add(
        _service.viewModel.onDidSelectExpression((selected) {
          final expression = selected?.expression;
          if (expression is Expression && !selected!.settingWatch && _service.model.getWatchExpressions().contains(expression)) {
            setState(() => _editingId = expression.getId());
          }
        }),
      );
    widget.collapseAll?.addListener(_controller.collapseAll);
    _evaluateAll();
  }

  @override
  void didUpdateWidget(WatchView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collapseAll != widget.collapseAll) {
      oldWidget.collapseAll?.removeListener(_controller.collapseAll);
      widget.collapseAll?.addListener(_controller.collapseAll);
    }
  }

  @override
  void dispose() {
    widget.collapseAll?.removeListener(_controller.collapseAll);
    _listeners.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _evaluateAll([Expression? only]) async {
    final generation = ++_generation;
    final frame = _service.viewModel.focusedStackFrame;
    final session = _service.viewModel.focusedSession;
    final expressions = only != null ? [only] : _service.model.getWatchExpressions();
    await Future.wait([
      for (final we in expressions)
        if (we.name.isNotEmpty) we.evaluate(session, frame, 'watch'),
    ]);
    if (!mounted || generation != _generation) return;
    _controller.refresh();
    setState(() {});
  }

  void _contextMenu(Object element, Offset position) {
    final s = DebugStrings.of(context);
    final watches = _service.model.getWatchExpressions();
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            IdeMenuAction(s.addExpression, onSelected: _service.addWatchExpression),
            if (element is Expression) ...[
              IdeMenuAction(s.editExpression, onSelected: () => setState(() => _editingId = element.getId())),
              IdeMenuAction(s.copyValue, onSelected: () => unawaited(debugCopy(element.value))),
            ],
            if (element is Variable) IdeMenuAction(s.copyValue, onSelected: () => unawaited(debugCopy(element.value))),
          ],
          [
            if (element is Expression) ...[
              IdeMenuAction(
                '↑',
                enabled: watches.indexOf(element) > 0,
                onSelected: () => _service.moveWatchExpression(element.getId(), watches.indexOf(element) - 1),
              ),
              IdeMenuAction(
                '↓',
                enabled: watches.indexOf(element) < watches.length - 1,
                onSelected: () => _service.moveWatchExpression(element.getId(), watches.indexOf(element) + 1),
              ),
            ],
          ],
          [
            if (element is Expression)
              IdeMenuAction(s.removeExpression, onSelected: () => _service.removeWatchExpressions(element.getId())),
            IdeMenuAction(s.removeAllExpressions, onSelected: () => _service.removeWatchExpressions()),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final roots = _service.model.getWatchExpressions();
    return DebugTreeView<Object>(
      controller: _controller,
      roots: roots,
      onContextMenu: _contextMenu,
      itemBuilder: (context, row, hovered) {
        final element = row.element;
        if (element is Expression) {
          if (_editingId == element.getId() || element.name.isEmpty) {
            return DebugInlineEditor(
              initialValue: element.name,
              placeholder: s.expressionPlaceholder,
              onDone: (value) {
                setState(() => _editingId = null);
                if (value == null || value.trim().isEmpty) {
                  if (element.name.isEmpty) _service.removeWatchExpressions(element.getId());
                } else if (value != element.name) {
                  _service.renameWatchExpression(element.getId(), value.trim());
                }
                _service.viewModel.setSelectedExpression(null, false);
              },
            );
          }
          return GestureDetector(
            onDoubleTap: () => setState(() => _editingId = element.getId()),
            child: Row(
              children: [
                Expanded(child: IdeHover(message: element.value, child: DebugExpressionLabel.of(element))),
                if (hovered) ...[
                  IdeActionButton(
                    icon: Codicons.edit,
                    tooltip: s.editExpression,
                    size: 20,
                    onPressed: () => setState(() => _editingId = element.getId()),
                  ),
                  IdeActionButton(
                    icon: Codicons.close,
                    tooltip: s.removeExpression,
                    size: 20,
                    onPressed: () => _service.removeWatchExpressions(element.getId()),
                  ),
                ],
              ],
            ),
          );
        }
        if (element is DebugExpression) return DebugExpressionLabel.of(element);
        return Text('$element');
      },
    );
  }
}
