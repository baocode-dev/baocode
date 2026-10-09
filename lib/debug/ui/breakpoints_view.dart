// The Breakpoints view: the adapter's exception filters (with conditions
// where supported), function, data, source and instruction breakpoints;
// each enabled or not; edited, removed, all activated or not.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/breakpointsView.ts.
//
// Deviations: a flat list (no tree mode); a source breakpoint's
// condition, hit count and log message are edited in the row, and
// "Edit Breakpoint" goes to [BreakpointsView.onEditBreakpoint] (the
// editor's breakpoint widget) when given.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../ide/ide_hover.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../common/debug_utils.dart';
import '../service/debug_service.dart';
import 'debug_icons.dart';
import 'debug_strings.dart';
import 'debug_widgets.dart';

/// What is being edited in a row.
enum BreakpointEditKind { functionName, condition, hitCondition, logMessage, exceptionCondition }

/// The breakpoints as the view lists them (`getElements`).
List<BaseBreakpoint> breakpointsViewElements(DebugService service) {
  final model = service.model;
  final session = service.viewModel.focusedSession;
  final exceptions = model.getExceptionBreakpointsForSession(session?.getId());
  final sources = List.of(model.getBreakpoints())
    ..sort((a, b) {
      final byUri = a.uri.toString().compareTo(b.uri.toString());
      if (byUri != 0) return byUri;
      final byLine = a.lineNumber - b.lineNumber;
      return byLine != 0 ? byLine : (a.column ?? 0) - (b.column ?? 0);
    });
  return [
    ...exceptions,
    ...model.getFunctionBreakpoints(),
    ...model.getDataBreakpoints(),
    ...sources,
    ...model.getInstructionBreakpoints(),
  ];
}

/// The Breakpoints pane's title actions.
List<Widget> breakpointsViewActions(
  BuildContext context,
  DebugService service, {
  required VoidCallback onAddFunctionBreakpoint,
}) {
  final s = DebugStrings.of(context);
  final model = service.model;
  final any = model.getBreakpoints().isNotEmpty ||
      model.getFunctionBreakpoints().isNotEmpty ||
      model.getDataBreakpoints().isNotEmpty ||
      model.getInstructionBreakpoints().isNotEmpty;
  return [
    IdePaneAction(icon: Codicons.add, tooltip: s.addFunctionBreakpoint, onPressed: onAddFunctionBreakpoint),
    IdePaneAction(
      icon: Codicons.activateBreakpoints,
      tooltip: s.toggleActivateBreakpoints,
      onPressed: () => unawaited(service.setBreakpointsActivated(!model.areBreakpointsActivated())),
    ),
    IdePaneAction(
      icon: Codicons.closeAll,
      tooltip: s.removeAllBreakpoints,
      onPressed: any ? () => unawaited(_removeAll(service)) : null,
    ),
  ];
}

Future<void> _removeAll(DebugService service) async {
  await service.removeBreakpoints();
  await service.removeFunctionBreakpoints();
  await service.removeDataBreakpoints();
  await service.removeInstructionBreakpoints();
}

/// Adds an unnamed function breakpoint for [BreakpointsViewState] to edit.
class BreakpointsViewController extends ChangeNotifier {
  String? _pendingFunctionBreakpointId;

  /// Adds a function breakpoint and edits its name.
  Future<void> addFunctionBreakpoint(DebugService service) async {
    final bp = FunctionBreakpoint(name: '');
    await service.addFunctionBreakpoint(bp, send: false);
    _pendingFunctionBreakpointId = bp.getId();
    notifyListeners();
  }
}

class BreakpointsView extends StatefulWidget {
  const BreakpointsView({super.key, required this.service, this.controller, this.onEditBreakpoint});

  final DebugService service;
  final BreakpointsViewController? controller;

  /// "Edit Breakpoint" of a source breakpoint (the editor's widget).
  final void Function(Breakpoint breakpoint)? onEditBreakpoint;

  @override
  State<BreakpointsView> createState() => BreakpointsViewState();
}

class BreakpointsViewState extends State<BreakpointsView> {
  final DisposableStore _listeners = DisposableStore();
  ({String id, BreakpointEditKind kind})? _editing;
  String? _selectedId;

  DebugService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _listeners
      ..add(_service.model.onDidChangeBreakpoints((_) => _changed()))
      ..add(_service.viewModel.onDidFocusSession((_) => _changed()))
      ..add(_service.onDidChangeState((_) => _changed()));
    widget.controller?.addListener(_onController);
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onController);
    _listeners.dispose();
    super.dispose();
  }

  void _onController() {
    final id = widget.controller?._pendingFunctionBreakpointId;
    if (id != null) {
      widget.controller!._pendingFunctionBreakpointId = null;
      setState(() => _editing = (id: id, kind: BreakpointEditKind.functionName));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Edits [kind] of the breakpoint [id] in its row.
  void edit(String id, BreakpointEditKind kind) => setState(() => _editing = (id: id, kind: kind));

  Future<void> _finishEdit(BaseBreakpoint bp, BreakpointEditKind kind, String? value) async {
    setState(() => _editing = null);
    if (value == null) {
      if (bp is FunctionBreakpoint && bp.name.isEmpty) await _service.removeFunctionBreakpoints(bp.getId());
      return;
    }
    final v = value.trim();
    switch ((bp, kind)) {
      case (FunctionBreakpoint(), BreakpointEditKind.functionName):
        if (v.isEmpty) {
          await _service.removeFunctionBreakpoints(bp.getId());
        } else {
          await _service.updateFunctionBreakpoint(bp.getId(), name: v);
        }
      case (FunctionBreakpoint(), BreakpointEditKind.condition):
        await _service.updateFunctionBreakpoint(bp.getId(), condition: v);
      case (FunctionBreakpoint(), BreakpointEditKind.hitCondition):
        await _service.updateFunctionBreakpoint(bp.getId(), hitCondition: v);
      case (DataBreakpoint(), BreakpointEditKind.condition):
        await _service.updateDataBreakpoint(bp.getId(), condition: v);
      case (DataBreakpoint(), BreakpointEditKind.hitCondition):
        await _service.updateDataBreakpoint(bp.getId(), hitCondition: v);
      case (final ExceptionBreakpoint e, BreakpointEditKind.exceptionCondition):
        await _service.setExceptionBreakpointCondition(e, v.isEmpty ? null : v);
      case (final Breakpoint b, _):
        await _service.updateBreakpoints(b.originalUri, {
          b.getId(): switch (kind) {
            BreakpointEditKind.hitCondition => BreakpointUpdateData(hitCondition: v.isEmpty ? null : v),
            BreakpointEditKind.logMessage => BreakpointUpdateData(logMessage: v.isEmpty ? null : v),
            _ => BreakpointUpdateData(condition: v.isEmpty ? null : v),
          },
        });
      default:
        break;
    }
  }

  Future<void> _remove(BaseBreakpoint bp) async {
    switch (bp) {
      case Breakpoint():
        await _service.removeBreakpoints([bp.getId()]);
      case FunctionBreakpoint():
        await _service.removeFunctionBreakpoints(bp.getId());
      case DataBreakpoint():
        await _service.removeDataBreakpoints(bp.getId());
      case InstructionBreakpoint():
        await _service.removeInstructionBreakpoints(
          instructionReference: bp.instructionReference,
          offset: bp.offset,
        );
      default:
        break;
    }
  }

  void _contextMenu(BaseBreakpoint bp, Offset position) {
    final s = DebugStrings.of(context);
    final removable = bp is! ExceptionBreakpoint;
    unawaited(
      showIdeMenu(
        context,
        position: position,
        entries: ideMenuGroups([
          [
            if (bp is Breakpoint) ...[
              if (widget.onEditBreakpoint != null)
                IdeMenuAction(s.editBreakpoint, onSelected: () => widget.onEditBreakpoint!(bp)),
              IdeMenuAction(s.editCondition, onSelected: () => edit(bp.getId(), BreakpointEditKind.condition)),
              IdeMenuAction(s.editHitCount, onSelected: () => edit(bp.getId(), BreakpointEditKind.hitCondition)),
              IdeMenuAction(s.editLogMessage, onSelected: () => edit(bp.getId(), BreakpointEditKind.logMessage)),
            ],
            if (bp is FunctionBreakpoint) ...[
              IdeMenuAction(s.editBreakpoint, onSelected: () => edit(bp.getId(), BreakpointEditKind.functionName)),
              IdeMenuAction(s.editCondition, onSelected: () => edit(bp.getId(), BreakpointEditKind.condition)),
              IdeMenuAction(s.editHitCount, onSelected: () => edit(bp.getId(), BreakpointEditKind.hitCondition)),
            ],
            if (bp is DataBreakpoint) ...[
              IdeMenuAction(s.editCondition, onSelected: () => edit(bp.getId(), BreakpointEditKind.condition)),
              IdeMenuAction(s.editHitCount, onSelected: () => edit(bp.getId(), BreakpointEditKind.hitCondition)),
            ],
            if (bp is ExceptionBreakpoint && bp.supportsCondition)
              IdeMenuAction(s.editCondition, onSelected: () => edit(bp.getId(), BreakpointEditKind.exceptionCondition)),
          ],
          [
            IdeMenuAction(
              bp.enabled ? s.disableBreakpoint : s.enableBreakpoint,
              onSelected: () => unawaited(_service.enableOrDisableBreakpoints(!bp.enabled, bp)),
            ),
            if (removable) IdeMenuAction(s.removeBreakpoint, onSelected: () => unawaited(_remove(bp))),
          ],
          [
            IdeMenuAction(s.addFunctionBreakpoint, onSelected: () => unawaited(_addFunctionBreakpoint())),
            IdeMenuAction(s.toggleActivateBreakpoints, onSelected: () {
              unawaited(_service.setBreakpointsActivated(!_service.model.areBreakpointsActivated()));
            }),
          ],
          [
            IdeMenuAction(s.enableAllBreakpoints, onSelected: () => unawaited(_service.enableOrDisableBreakpoints(true))),
            IdeMenuAction(s.disableAllBreakpoints, onSelected: () => unawaited(_service.enableOrDisableBreakpoints(false))),
            IdeMenuAction(s.removeAllBreakpoints, onSelected: () => unawaited(_removeAll(_service))),
          ],
        ]),
      ),
    );
  }

  Future<void> _addFunctionBreakpoint() async {
    final bp = FunctionBreakpoint(name: '');
    await _service.addFunctionBreakpoint(bp, send: false);
    edit(bp.getId(), BreakpointEditKind.functionName);
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final elements = breakpointsViewElements(_service);
    final state = _service.state;
    final activated = _service.model.areBreakpointsActivated();
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: elements.length,
      itemExtent: IdeListColors.rowHeight,
      itemBuilder: (context, index) {
        final bp = elements[index];
        final editing = _editing?.id == bp.getId() ? _editing!.kind : null;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: IdeListColors.inset),
          child: IdeListRow(
            selected: _selectedId == bp.getId(),
            onTap: () {
              setState(() => _selectedId = bp.getId());
              if (bp is Breakpoint) {
                unawaited(
                  _service.host.openEditor(
                    bp.uri,
                    selection: DebugRange(bp.lineNumber, bp.column ?? 1, bp.lineNumber, bp.column ?? 1),
                  ),
                );
              }
            },
            onDoubleTap: bp is FunctionBreakpoint ? () => edit(bp.getId(), BreakpointEditKind.functionName) : null,
            onContextMenu: (position) {
              setState(() => _selectedId = bp.getId());
              _contextMenu(bp, position);
            },
            builder: (context, hovered) => _BreakpointRow(
              breakpoint: bp,
              presentation: bp is ExceptionBreakpoint
                  ? null
                  : breakpointPresentation(state, activated, bp, s, model: _service.model),
              editing: editing,
              hovered: hovered,
              s: s,
              onToggle: (value) => unawaited(_service.enableOrDisableBreakpoints(value, bp)),
              onEditDone: (kind, value) => unawaited(_finishEdit(bp, kind, value)),
              onEdit: () => switch (bp) {
                ExceptionBreakpoint() => edit(bp.getId(), BreakpointEditKind.exceptionCondition),
                FunctionBreakpoint() => edit(bp.getId(), BreakpointEditKind.functionName),
                final Breakpoint b when widget.onEditBreakpoint != null => widget.onEditBreakpoint!(b),
                _ => edit(bp.getId(), BreakpointEditKind.condition),
              },
              onRemove: bp is ExceptionBreakpoint ? null : () => unawaited(_remove(bp)),
            ),
          ),
        );
      },
    );
  }
}

class _BreakpointRow extends StatelessWidget {
  const _BreakpointRow({
    required this.breakpoint,
    required this.presentation,
    required this.editing,
    required this.hovered,
    required this.s,
    required this.onToggle,
    required this.onEditDone,
    required this.onEdit,
    required this.onRemove,
  });

  final BaseBreakpoint breakpoint;
  final BreakpointPresentation? presentation;
  final BreakpointEditKind? editing;
  final bool hovered;
  final DebugStrings s;
  final ValueChanged<bool> onToggle;
  final void Function(BreakpointEditKind kind, String? value) onEditDone;
  final VoidCallback onEdit;
  final VoidCallback? onRemove;

  String _initial(BreakpointEditKind kind) => switch (kind) {
    BreakpointEditKind.functionName => (breakpoint as FunctionBreakpoint).name,
    BreakpointEditKind.hitCondition => breakpoint.hitCondition ?? '',
    BreakpointEditKind.logMessage => breakpoint.logMessage ?? '',
    _ => breakpoint.condition ?? '',
  };

  String _placeholder(BreakpointEditKind kind) => switch (kind) {
    BreakpointEditKind.functionName => s.functionBreakpointPlaceholder,
    BreakpointEditKind.hitCondition => s.hitCountPlaceholder,
    BreakpointEditKind.logMessage => s.logMessagePlaceholder,
    BreakpointEditKind.exceptionCondition => breakpoint is ExceptionBreakpoint
        ? (breakpoint as ExceptionBreakpoint).conditionDescription ?? s.exceptionConditionPlaceholder
        : s.exceptionConditionPlaceholder,
    BreakpointEditKind.condition => s.conditionPlaceholder,
  };

  @override
  Widget build(BuildContext context) {
    final bp = breakpoint;
    final p = presentation;
    final editing = this.editing;
    final textStyle = TextStyle(fontSize: 13, color: IdeListColors.foreground);
    final descStyle = TextStyle(fontSize: 12, color: IdeListColors.description);

    Widget label;
    String? description;
    String? badge;
    switch (bp) {
      case ExceptionBreakpoint():
        label = Text(bp.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
        description = bp.condition ?? bp.description;
      case FunctionBreakpoint():
        label = Text(bp.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
        description = bp.condition;
      case DataBreakpoint():
        label = Text(bp.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
        description = bp.accessType;
      case Breakpoint():
        label = Text(basenameOrAuthority(bp.uri), maxLines: 1, overflow: TextOverflow.ellipsis, style: textStyle);
        final path = bp.uri.path;
        final slash = path.lastIndexOf('/');
        description = slash > 0 ? path.substring(0, slash) : null;
        badge = bp.column != null ? '${bp.lineNumber}:${bp.column}' : '${bp.lineNumber}';
      case InstructionBreakpoint():
        label = Text('0x${bp.address.toRadixString(16)}', maxLines: 1, style: textStyle);
      default:
        label = Text('$bp', style: textStyle);
    }

    return Row(
      children: [
        _DebugCheckbox(value: bp.enabled, onChanged: onToggle),
        if (p != null)
          SizedBox(
            width: 20,
            child: p.message == null
                ? Icon(p.icon, size: 16, color: p.color)
                : IdeHover(message: p.message, child: Icon(p.icon, size: 16, color: p.color)),
          ),
        const SizedBox(width: 2),
        if (editing != null)
          Expanded(
            child: DebugInlineEditor(
              initialValue: _initial(editing),
              placeholder: _placeholder(editing),
              onDone: (value) => onEditDone(editing, value),
            ),
          )
        else ...[
          Flexible(child: p?.message == null ? label : IdeHover(message: p!.message, child: label)),
          if (description != null && description.isNotEmpty) ...[
            const SizedBox(width: 6),
            Expanded(
              child: Text(description, maxLines: 1, overflow: TextOverflow.ellipsis, softWrap: false, style: descStyle),
            ),
          ] else
            const Spacer(),
          if (hovered) ...[
            if (bp is! ExceptionBreakpoint || bp.supportsCondition)
              IdeActionButton(icon: Codicons.edit, tooltip: s.editBreakpoint, size: 20, onPressed: onEdit),
            if (onRemove != null)
              IdeActionButton(icon: Codicons.close, tooltip: s.removeBreakpoint, size: 20, onPressed: onRemove),
          ],
          if (badge != null) ...[const SizedBox(width: 4), DebugStateLabel(badge)],
          const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// VS Code's 18px checkbox (`.monaco-custom-toggle.monaco-checkbox`).
class _DebugCheckbox extends StatelessWidget {
  const _DebugCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final background = debugColor('checkbox.background');
    final border = debugColor('checkbox.border');
    final foreground = debugColor('checkbox.foreground');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, right: 4),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: background,
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(3),
          ),
          child: value ? Icon(Codicons.check, size: 14, color: foreground) : null,
        ),
      ),
    );
  }
}
