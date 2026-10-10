// The Debug Console: the session's output, the expressions evaluated in it
// and their expandable results, with completion and clear/copy.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/repl.ts and replViewer.ts.
//
// Deviations: no ANSI colors (text is shown as it comes), no filter or
// severity folding; the input completes on ⌥Space rather than on typing;
// with the default keybindings or a terminal output (`.clear`, `.help`).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationTokenSource;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../common/repl_model.dart';
import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_icons.dart';
import 'debug_strings.dart';
import 'debug_toolbar.dart';
import 'debug_widgets.dart';

Color _severityColor(ReplSeverity sev) => switch (sev) {
  ReplSeverity.error => debugColor('debugConsole.errorForeground'),
  ReplSeverity.warning => debugColor('debugConsole.warningForeground'),
  ReplSeverity.info || ReplSeverity.ignore => debugColor('debugConsole.infoForeground'),
};

final _neverCancelled = CancellationTokenSource().token;

/// The Debug Console.
class DebugConsoleView extends StatefulWidget {
  const DebugConsoleView({super.key, required this.service});

  final DebugService service;

  @override
  State<DebugConsoleView> createState() => DebugConsoleViewState();
}

class DebugConsoleViewState extends State<DebugConsoleView> {
  final DisposableStore _listeners = DisposableStore();
  DebugDisposable? _sessionListener;
  DebugSession? _session;
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  int _history = -1;

  DebugService get service => widget.service;

  @override
  void initState() {
    super.initState();
    _listeners.add(service.viewModel.onDidFocusSession(_focus));
    _focus(service.viewModel.focusedSession);
  }

  @override
  void dispose() {
    _sessionListener?.dispose();
    _listeners.dispose();
    _scroll.dispose();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _focus(DebugSession? session) {
    if (session == _session) return;
    _sessionListener?.dispose();
    _sessionListener = session?.onDidChangeReplElements((_) {
      if (!mounted) return;
      setState(() {});
      _scrollToEnd();
    });
    setState(() => _session = session);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  /// Submits the input: evaluate it, or run a `.clear`/`.help` command.
  Future<void> submit() async {
    final text = _input.text.trim();
    final session = _session;
    if (text.isEmpty || session == null) return;
    if (text.startsWith('.')) {
      switch (text.substring(1).trim()) {
        case 'clear':
          clear();
          return;
        case 'help':
          for (final line in [
            'Available commands:',
            '  .clear - Clear the console',
            '  .help - Show this help',
          ]) {
            session.appendToRepl(NewReplElementData(output: '$line\n', sev: ReplSeverity.info, source: null));
          }
          _input.clear();
          setState(() {});
          return;
      }
    }
    _input.clear();
    setState(() => _history = -1);
    await session.addReplExpression(service.viewModel.focusedStackFrame, text);
  }

  /// Completes the word before the caret with the adapter's suggestions.
  Future<void> complete() async {
    final session = _session;
    final text = _input.text;
    if (session == null || text.isEmpty) return;
    final frame = service.viewModel.focusedStackFrame;
    final threadId = frame?.thread.threadId ?? debugActionThread(service)?.threadId;
    if (threadId == null) return;
    try {
      final response = await session.completions(
        frame?.frameId,
        threadId,
        text,
        (lineNumber: 1, column: text.length + 1),
        _neverCancelled,
      );
      final targets = response?.obj('body')?.objects('targets');
      if (targets == null || targets.isEmpty || !mounted) return;
      final box = _inputFocus.context?.findRenderObject() as RenderBox?;
      final anchor = box != null ? box.localToGlobal(Offset.zero) & box.size : Offset.zero & const Size(1, 1);
      await showIdeMenu(
        context,
        anchor: anchor,
        entries: [
          for (final t in targets) IdeMenuAction(t.str('label') ?? '', onSelected: () => _insertCompletion(t)),
        ],
      );
    } on Object {
      // The adapter cannot complete.
    }
  }

  void _insertCompletion(Json target) {
    final label = target.str('text') ?? target.str('label') ?? '';
    final text = _input.text;
    final match = RegExp(r'[A-Za-z0-9_$]+$').firstMatch(text);
    final replaced = match != null ? '${text.substring(0, match.start)}$label' : '$text$label';
    _input.value = TextEditingValue(text: replaced, selection: TextSelection.collapsed(offset: replaced.length));
    _inputFocus.requestFocus();
    setState(() {});
  }

  void clear() {
    _session?.removeReplExpressions();
    _input.clear();
    setState(() {});
  }

  void copyAll() {
    final session = _session;
    if (session == null) return;
    unawaited(debugCopy([for (final e in session.getReplElements()) e.toString()].join('\n')));
  }

  void _historyMove(int delta) {
    final session = _session;
    if (session == null) return;
    final expressions = [
      for (final e in session.getReplElements())
        if (e is ReplEvaluationInput) e.value,
    ];
    if (expressions.isEmpty) return;
    _history = (_history + delta).clamp(-1, expressions.length - 1);
    final text = _history < 0 ? '' : expressions[expressions.length - 1 - _history];
    _input.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() {});
  }

  /// The console's title actions.
  List<Widget> actions(BuildContext context) => [
    IdePaneAction(icon: Codicons.clearAll, tooltip: DebugStrings.of(context).clearConsole, onPressed: clear),
    IdePaneAction(icon: Codicons.copy, tooltip: DebugStrings.of(context).copyAll, onPressed: copyAll),
  ];

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final session = _session;
    final elements = session?.getReplElements() ?? const <ReplElement>[];
    return Column(
      children: [
        Expanded(
          child: elements.isEmpty
              ? DebugEmptyMessage(session == null ? s.noSession : s.debugConsole)
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  itemCount: elements.length,
                  itemBuilder: (context, index) => _ReplRow(service: service, element: elements[index], depth: 0),
                ),
        ),
        _ConsoleInput(
          controller: _input,
          focusNode: _inputFocus,
          enabled: session != null,
          onSubmitted: submit,
          onComplete: complete,
          onHistory: _historyMove,
        ),
      ],
    );
  }
}

class _ConsoleInput extends StatelessWidget {
  const _ConsoleInput({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.onSubmitted,
    required this.onComplete,
    required this.onHistory,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final VoidCallback onSubmitted;
  final VoidCallback onComplete;
  final ValueChanged<int> onHistory;

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: debugColor('panel.border')))),
      child: Row(
        children: [
          Icon(Codicons.chevronRight, size: 14, color: debugColor('debugConsoleInputIcon.foreground')),
          const SizedBox(width: 4),
          Expanded(
            child: IdeInputBox(
              controller: controller,
              focusNode: focusNode,
              placeholder: s.consolePlaceholder,
              semanticsLabel: s.debugConsole,
              onSubmitted: (_) => onSubmitted(),
              shortcuts: {
                const SingleActivator(LogicalKeyboardKey.space, alt: true): onComplete,
                const SingleActivator(LogicalKeyboardKey.arrowUp): () => onHistory(1),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () => onHistory(-1),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplRow extends StatelessWidget {
  const _ReplRow({required this.service, required this.element, required this.depth});

  final DebugService service;
  final ReplElement element;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    if (element is NestingReplElement) {
      return element is RawObjectReplElement
          ? _PlainRow(text: '${element.name}: ${element.value}', color: debugColor('debugTokenExpression.value'), depth: depth)
          : _NestingRow(service: service, element: element, depth: depth);
    }
    final (text, color, italic) = switch (element) {
      ReplEvaluationInput() => ('${element.value}\n', debugColor('debugTokenExpression.name'), false),
      ReplOutputElement() => (element.toString(includeSource: true), _severityColor(element.severity), false),
      ReplVariableElement() => (element.toString(), debugColor('debugTokenExpression.value'), false),
      ReplGroup() => (element.toString(), debugColor('debugConsole.infoForeground'), false),
      _ => (element.toString(), debugColor('debugConsole.infoForeground'), true),
    };
    return _PlainRow(text: text, color: color, depth: depth, italic: italic);
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.text, required this.color, required this.depth, this.italic = false});

  final String text;
  final Color color;
  final int depth;
  final bool italic;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 8 + depth * IdeListColors.indent, right: 8, top: 1, bottom: 1),
    child: SelectableText(
      text,
      style: TextStyle(fontSize: 13, height: 1.25, color: color, fontStyle: italic ? FontStyle.italic : null),
    ),
  );
}

class _NestingRow extends StatefulWidget {
  const _NestingRow({required this.service, required this.element, required this.depth});

  final DebugService service;
  final NestingReplElement element;
  final int depth;

  @override
  State<_NestingRow> createState() => _NestingRowState();
}

class _NestingRowState extends State<_NestingRow> {
  late bool _expanded = widget.element is ReplGroup && (widget.element as ReplGroup).autoExpand;
  List<Object> _children = const [];
  bool _loaded = false;

  Future<void> _toggle() async {
    if (!_expanded && !_loaded && widget.element.hasChildren) {
      _children = await widget.element.getChildren();
      _loaded = true;
    }
    if (mounted) setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final element = widget.element;
    final label = switch (element) {
      final ReplEvaluationResult result => result.value,
      _ => element.toString(),
    };
    final color = element is ReplOutputElement ? _severityColor(element.severity) : debugColor('debugConsole.infoForeground');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Padding(
            padding: EdgeInsets.only(left: 8 + widget.depth * IdeListColors.indent, right: 8, top: 1, bottom: 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  child: element.hasChildren
                      ? Icon(_expanded ? Codicons.chevronDown : Codicons.chevronRight, size: 14, color: IdeListColors.foreground)
                      : null,
                ),
                Expanded(child: SelectableText(label, style: TextStyle(fontSize: 13, height: 1.25, color: color))),
              ],
            ),
          ),
        ),
        if (_expanded)
          for (final child in _children)
            if (child is ReplElement)
              _ReplRow(service: widget.service, element: child, depth: widget.depth + 1)
            else if (child is DebugExpression)
              Padding(
                padding: EdgeInsets.only(left: 8 + (widget.depth + 1) * IdeListColors.indent, right: 8),
                child: DebugExpressionLabel.of(child),
              )
            else
              Padding(
                padding: EdgeInsets.only(left: 8 + (widget.depth + 1) * IdeListColors.indent, right: 8),
                child: SelectableText(
                  '$child',
                  style: TextStyle(fontSize: 13, color: debugColor('debugConsole.infoForeground')),
                ),
              ),
      ],
    );
  }
}
