// Pieces the debug views share: an expression's `name: value` label, an
// inline editor for values and expressions, and the empty-view message.
//
// Ported in part from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5
// (1.135.0): src/vs/workbench/contrib/debug/browser/baseDebugView.ts
// (`renderExpressionValue`, `renderViewTree`, `AbstractExpressionsRenderer`
// input box) and media/debugViewlet.css.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ide/ide_input.dart';
import '../../ide/ide_list.dart';
import '../common/debug_model.dart';
import 'debug_icons.dart';

/// The longest value shown in a row (`maxValueLength`).
const debugMaxValueLength = 1024;

/// `name: value` with the debug token colors.
class DebugExpressionLabel extends StatelessWidget {
  const DebugExpressionLabel({
    super.key,
    required this.name,
    required this.value,
    this.type,
    this.error = false,
    this.changed = false,
    this.nameColor,
    this.showType = false,
    this.deemphasized = false,
  });

  /// The label of [expression] as the views show it.
  factory DebugExpressionLabel.of(DebugExpression expression, {bool showType = false}) {
    final available = expression is! Expression || expression.available;
    return DebugExpressionLabel(
      name: expression.name,
      value: expression.value,
      type: expression.type,
      error: !available,
      changed: expression.valueChanged,
      showType: showType,
      deemphasized: expression is Variable && expression.presentationHint?['visibility'] == 'internal',
    );
  }

  final String name;
  final String value;
  final String? type;
  final bool error;
  final bool changed;
  final Color? nameColor;
  final bool showType;
  final bool deemphasized;

  @override
  Widget build(BuildContext context) {
    final shown = value.length > debugMaxValueLength ? '${value.substring(0, debugMaxValueLength)}...' : value;
    final style = TextStyle(fontSize: 13, height: 1.0, color: IdeListColors.foreground);
    final spans = <InlineSpan>[
      if (name.isNotEmpty)
        TextSpan(
          text: name,
          style: TextStyle(color: nameColor ?? debugColor('debugTokenExpression.name')),
        ),
      if (name.isNotEmpty && showType && type != null && type!.isNotEmpty) ...[
        const TextSpan(text: ': '),
        TextSpan(text: type, style: TextStyle(color: debugColor('debugTokenExpression.type'))),
      ],
      if (name.isNotEmpty && shown.isNotEmpty) const TextSpan(text: ': '),
      if (shown.isNotEmpty)
        TextSpan(
          text: shown.replaceAll('\n', ' '),
          style: TextStyle(color: debugValueColor(value, error: error, type: type)),
        ),
    ];
    final text = Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
    );
    Widget result = Opacity(opacity: deemphasized ? 0.7 : 1, child: text);
    if (changed) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          color: debugColor('debugView.valueChangedHighlight').withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
        child: result,
      );
    }
    return Align(alignment: Alignment.centerLeft, child: result);
  }
}

/// A one-line editor in a row: Enter accepts, Escape or losing focus
/// cancels (accepts, when [acceptOnBlur]).
class DebugInlineEditor extends StatefulWidget {
  const DebugInlineEditor({
    super.key,
    required this.initialValue,
    required this.onDone,
    this.placeholder,
    this.acceptOnBlur = true,
  });

  final String initialValue;
  final String? placeholder;

  /// The value, or null when cancelled.
  final void Function(String? value) onDone;
  final bool acceptOnBlur;

  @override
  State<DebugInlineEditor> createState() => _DebugInlineEditorState();
}

class _DebugInlineEditorState extends State<DebugInlineEditor> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialValue)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initialValue.length);
  final FocusNode _focus = FocusNode();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _finish(widget.acceptOnBlur ? _controller.text : null);
    });
  }

  void _finish(String? value) {
    if (_done) return;
    _done = true;
    widget.onDone(value);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: IdeListColors.rowHeight - 2,
    child: IdeInputBox(
      controller: _controller,
      focusNode: _focus,
      autofocus: true,
      placeholder: widget.placeholder,
      fontSize: 13,
      lineHeight: 16,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      onSubmitted: _finish,
      shortcuts: {const SingleActivator(LogicalKeyboardKey.escape): () => _finish(null)},
    ),
  );
}

/// The message of an empty view.
class DebugEmptyMessage extends StatelessWidget {
  const DebugEmptyMessage(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 6, 12, 6),
    child: Text(message, style: TextStyle(fontSize: 13, color: IdeListColors.description)),
  );
}

/// A small rounded label (the call stack's state, a breakpoint's line).
class DebugStateLabel extends StatelessWidget {
  const DebugStateLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: debugColor('debugView.stateLabelBackground'),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11, color: IdeListColors.foreground),
    ),
  );
}

/// Copies [text] to the clipboard.
Future<void> debugCopy(String text) => Clipboard.setData(ClipboardData(text: text));
