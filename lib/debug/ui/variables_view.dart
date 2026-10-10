// The Variables view: the focused frame's scopes and their variables,
// loaded as they are expanded, with set value, copy, add to watch and
// break on value change.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/variablesView.ts.
//
// Deviations: no visualizers, memory view or "view binary data"; actions
// are a context menu (and double-click to set a value).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../service/debug_service.dart';
import 'debug_strings.dart';
import 'debug_tree.dart';
import 'debug_widgets.dart';

/// Scopes and variables.
class DebugVariablesDataSource extends DebugTreeDataSource<Object> {
  final Set<String> _firstScopeIds = {};

  @override
  String idOf(Object element) => (element as DebugTreeElement).getId();

  @override
  bool hasChildren(Object element) => element is ExpressionContainer && element.hasChildren;

  @override
  Future<List<Object>> getChildren(Object element) async =>
      element is ExpressionContainer ? await element.getChildren() : const [];

  /// The first scope opens unless it is expensive.
  @override
  bool initiallyExpanded(Object element) => element is Scope && _firstScopeIds.contains(element.getId());
}

class VariablesView extends StatefulWidget {
  const VariablesView({super.key, required this.service});

  final DebugService service;

  @override
  State<VariablesView> createState() => _VariablesViewState();
}

class _VariablesViewState extends State<VariablesView> {
  final DebugVariablesDataSource _dataSource = DebugVariablesDataSource();
  late final DebugTreeController<Object> _controller = DebugTreeController(_dataSource);
  final DisposableStore _listeners = DisposableStore();
  List<Scope> _scopes = const [];
  StackFrame? _frame;
  String? _editingId;
  int _load = 0;

  DebugService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _listeners
      ..add(_service.viewModel.onDidFocusStackFrame((_) => _reload()))
      ..add(_service.viewModel.onWillUpdateViews(_refresh))
      ..add(_service.viewModel.onDidEvaluateLazyExpression((_) => _refresh()));
    _reload();
  }

  @override
  void dispose() {
    _listeners.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _refresh() {
    _controller.refresh();
    _reload();
  }

  Future<void> _reload() async {
    final frame = _service.viewModel.focusedStackFrame;
    final load = ++_load;
    if (frame == null) {
      setState(() {
        _frame = null;
        _scopes = const [];
      });
      return;
    }
    final scopes = await frame.getScopes();
    if (!mounted || load != _load) return;
    if (scopes.isNotEmpty && !scopes.first.expensive) _dataSource._firstScopeIds.add(scopes.first.getId());
    if (_frame != frame) _controller.refresh();
    setState(() {
      _frame = frame;
      _scopes = scopes;
    });
  }

  Future<void> _setValue(Variable variable, String value) async {
    final frame = _frame;
    final session = variable.getSession();
    if (session == null) return;
    final evaluateName = variable.evaluateName;
    if (session.capabilities.flag('supportsSetVariable')) {
      await variable.setVariable(value, frame);
    } else if (session.capabilities.flag('supportsSetExpression') && frame != null && evaluateName != null) {
      await variable.setExpression(value, frame);
    }
    // Others may change too.
    _service.viewModel.updateViews();
  }

  bool _canSetValue(Variable v) {
    final session = v.getSession();
    if (session == null) return false;
    final attributes = v.presentationHint?['attributes'];
    if (attributes is List && attributes.contains('readOnly')) return false;
    return session.capabilities.flag('supportsSetVariable') ||
        (session.capabilities.flag('supportsSetExpression') && v.evaluateName != null);
  }

  Future<void> _addDataBreakpoint(Variable v, String accessType) async {
    final session = v.getSession();
    if (session == null) return;
    final info = await session.dataBreakpointInfo(v.name, variablesReference: v.parent.reference);
    final dataId = info?.str('dataId');
    if (info == null || dataId == null) return;
    await _service.addDataBreakpoint(
      DataBreakpoint(
        description: info.str('description') ?? v.name,
        src: DataBreakpointVariable(dataId),
        canPersist: info.flag('canPersist'),
        accessTypes: info.list('accessTypes')?.whereType<String>().toList(),
        accessType: accessType,
      ),
    );
  }

  void _contextMenu(Object element, Offset position) {
    if (element is! Variable) return;
    final s = DebugStrings.of(context);
    final session = element.getSession();
    final evaluateName = element.evaluateName;
    final dataBreakpoints = session?.capabilities.flag('supportsDataBreakpoints') ?? false;
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            IdeMenuAction(
              s.setValue,
              enabled: _canSetValue(element),
              onSelected: () => setState(() => _editingId = element.getId()),
            ),
            IdeMenuAction(s.copyValue, onSelected: () => unawaited(debugCopy(element.value))),
            IdeMenuAction(
              s.copyAsExpression,
              enabled: evaluateName != null,
              onSelected: () => unawaited(debugCopy(evaluateName!)),
            ),
            IdeMenuAction(
              s.addToWatch,
              enabled: evaluateName != null,
              onSelected: () => _service.addWatchExpression(evaluateName),
            ),
          ],
          [
            if (dataBreakpoints) ...[
              IdeMenuAction(s.breakOnValueChange, onSelected: () => unawaited(_addDataBreakpoint(element, 'write'))),
              IdeMenuAction(s.breakOnValueRead, onSelected: () => unawaited(_addDataBreakpoint(element, 'read'))),
            ],
          ],
          [
            IdeMenuAction(s.collapseAll, onSelected: _controller.collapseAll),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    if (_frame == null) return DebugEmptyMessage(s.notPaused);
    return DebugTreeView<Object>(
      controller: _controller,
      roots: _scopes,
      empty: DebugEmptyMessage(s.noVariables),
      onContextMenu: _contextMenu,
      itemBuilder: (context, row, hovered) {
        final element = row.element;
        if (element is Scope) {
          return Align(
            alignment: Alignment.centerLeft,
            child: Text(
              element.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: IdeListColors.foreground),
            ),
          );
        }
        if (element is Variable) {
          if (_editingId == element.getId()) {
            return DebugInlineEditor(
              initialValue: element.value,
              onDone: (value) {
                setState(() => _editingId = null);
                if (value != null && value != element.value) unawaited(_setValue(element, value));
              },
            );
          }
          final lazy = element.presentationHint?['lazy'] == true;
          return GestureDetector(
            onDoubleTap: _canSetValue(element) ? () => setState(() => _editingId = element.getId()) : null,
            child: Row(
              children: [
                Expanded(
                  child: IdeHover(
                    message: element.type != null ? '${element.type}\n${element.value}' : element.value,
                    child: DebugExpressionLabel.of(element),
                  ),
                ),
                if (lazy)
                  IdeActionButton(
                    icon: Codicons.eye,
                    tooltip: s.notAvailable,
                    size: 20,
                    onPressed: () => unawaited(_service.viewModel.evaluateLazyExpression(element)),
                  ),
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
