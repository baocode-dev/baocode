// The Debug Console: the session's output, the expressions evaluated in it
// and their expandable results, with completion and clear/copy.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/debug/browser/repl.ts and replViewer.ts.
//
// Deviations: no link detection in output, no filter or severity folding;
// the input completes on ⌥Space rather than on typing; with the default
// keybindings or a terminal output (`.clear`, `.help`). ANSI styles are
// debug_ansi.dart's.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show CancellationTokenSource;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../../ide/ide_menu.dart';
import '../../ide/ide_panes.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../base/event.dart';
import '../common/debug_model.dart';
import '../common/debug_source.dart';
import '../common/debug_types.dart';
import '../common/repl_model.dart';
import '../service/debug_service.dart';
import '../session/debug_session.dart';
import 'debug_ansi.dart';
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

/// The tree's twistie: every row has its place, so the text of rows with
/// and without children lines up.
const _twistieWidth = 16.0;

TextStyle _rowStyle(Color color, {bool italic = false}) =>
    TextStyle(fontSize: 13, height: 1.25, color: color, fontStyle: italic ? FontStyle.italic : null);

/// [text] as upstream's `white-space: pre` shows it: a last line break
/// draws no empty line.
String _shown(String text) {
  var shown = text;
  if (shown.endsWith('\n')) shown = shown.substring(0, shown.length - 1);
  if (shown.endsWith('\r')) shown = shown.substring(0, shown.length - 1);
  return shown;
}

/// `debugConsoleInputIcon.foreground`, faded when the theme leaves it to the
/// default (debugColors.ts).
Color _inputIconColor() {
  final defined = themeColors.get('debugConsoleInputIcon.foreground');
  if (defined != null) return defined;
  final color = debugColor('debugConsoleInputIcon.foreground');
  return color.withValues(alpha: color.a * (themeColors.dark ? 0.4 : 0.25));
}

class _ReplRow extends StatelessWidget {
  const _ReplRow({required this.service, required this.element, required this.depth});

  final DebugService service;
  final Object element;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final element = this.element;
    if (element is NestingReplElement || element is DebugExpression) {
      return _NestingRow(service: service, element: element, depth: depth);
    }
    return switch (element) {
      // The input with its marker in the twistie's place.
      ReplEvaluationInput() => _Row(
        depth: depth,
        leading: Icon(Codicons.arrowSmallRight, size: 14, color: _inputIconColor()),
        child: SelectableText(element.value, style: _rowStyle(debugColor('foreground'))),
      ),
      _ => _Row(
        depth: depth,
        child: SelectableText(_shown('$element'), style: _rowStyle(debugColor('foreground'))),
      ),
    };
  }
}

/// A row of the tree: indented by depth, the twistie's place, the content.
class _Row extends StatelessWidget {
  const _Row({required this.depth, required this.child, this.leading});

  final int depth;
  final Widget? leading;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: 8 + depth * IdeListColors.indent, right: 8, top: 1, bottom: 1),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: _twistieWidth, child: leading),
        Expanded(child: child),
      ],
    ),
  );
}

/// An element that may have children: output (of a variable), a group, an
/// evaluation's result and the variables under it, a raw object.
class _NestingRow extends StatefulWidget {
  const _NestingRow({required this.service, required this.element, required this.depth});

  final DebugService service;

  /// A [NestingReplElement] or a [DebugExpression].
  final Object element;
  final int depth;

  @override
  State<_NestingRow> createState() => _NestingRowState();
}

class _NestingRowState extends State<_NestingRow> {
  late bool _expanded = widget.element is ReplGroup && (widget.element as ReplGroup).autoExpand;
  List<Object> _children = const [];
  bool _loaded = false;

  bool get _hasChildren => switch (widget.element) {
    final NestingReplElement e => e.hasChildren,
    final DebugExpression e => e.hasChildren,
    _ => false,
  };

  Future<List<Object>> _getChildren() async => switch (widget.element) {
    final NestingReplElement e => await e.getChildren(),
    final DebugExpression e => await e.getChildren(),
    _ => const [],
  };

  Future<void> _toggle() async {
    if (!_expanded && !_loaded && _hasChildren) {
      _children = await _getChildren();
      _loaded = true;
    }
    if (mounted) setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final element = widget.element;
    final hasChildren = _hasChildren;
    // A group's children are live (output keeps arriving into it).
    final children = element is ReplGroup ? element.children : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GestureDetector(
          onTap: hasChildren ? _toggle : null,
          child: _Row(
            depth: widget.depth,
            leading: hasChildren
                ? Icon(
                    _expanded ? Codicons.chevronDown : Codicons.chevronRight,
                    size: 14,
                    color: IdeListColors.foreground,
                  )
                : null,
            child: _content(element),
          ),
        ),
        if (_expanded)
          for (final child in children ?? _children)
            _ReplRow(service: widget.service, element: child, depth: widget.depth + 1),
      ],
    );
  }

  Widget _content(Object element) => switch (element) {
    // Colored by kind, a failure an italic error (debugExpressionRenderer's
    // `colorize` and `unavailable error`).
    final ReplEvaluationResult r => SelectableText(
      r.value,
      style: _rowStyle(
        debugValueColor(r.value, error: !r.available, type: r.type),
        italic: !r.available,
      ),
    ),
    // The count of identical lines, the text with its ANSI styles in the
    // severity's color, where it was logged.
    final ReplOutputElement o => _withSource(
      o.session,
      o.sourceData,
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (o.count >= 2) ...[IdeCountBadge(o.count), const SizedBox(width: 4)],
          Expanded(
            child: SelectableText.rich(
              ansiTextSpan(
                _shown(o.value),
                _rowStyle(_outputColor(o.severity), italic: o.severity == ReplSeverity.ignore),
                background: debugColor('panel.background'),
              ),
            ),
          ),
        ],
      ),
    ),
    final ReplGroup g => _withSource(
      g.session,
      g.sourceData,
      SelectableText.rich(
        ansiTextSpan(_shown(g.name), _rowStyle(debugColor('foreground')), background: debugColor('panel.background')),
      ),
    ),
    final ReplVariableElement v => _withSource(v.getSession(), v.sourceData, DebugExpressionLabel.of(v.expression)),
    final DebugExpression e => DebugExpressionLabel.of(e),
    _ => SelectableText(_shown('$element'), style: _rowStyle(debugColor('foreground'))),
  };

  /// [child] with its source on the right, a link to it (`SourceWidget`).
  Widget _withSource(DebugSession session, ReplElementSource? data, Widget child) {
    final source = data?.source;
    if (data == null || source is! Source) return child;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: child),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Tooltip(
            message: '${source.uri.path}:${data.lineNumber}',
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => unawaited(
                  widget.service.openSource(
                    session,
                    source,
                    DebugRange(data.lineNumber, data.column, data.lineNumber, data.column),
                  ),
                ),
                child: Text(
                  '${source.name.split(RegExp(r'[/\\]')).last}:${data.lineNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _rowStyle(debugColor('debugConsole.sourceForeground'))
                      .copyWith(decoration: TextDecoration.underline),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The output's color by severity; `ignore` keeps the foreground (and is
/// italic).
Color _outputColor(ReplSeverity severity) => switch (severity) {
  ReplSeverity.ignore => debugColor('foreground'),
  _ => _severityColor(severity),
};
