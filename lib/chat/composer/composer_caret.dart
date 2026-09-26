import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Wraps the Quill editor [child] and paints a caret over it in place of
/// Quill's own (pass `showCursor: false` to the editor). Quill only scrolls
/// the caret into view when its own cursor is on, so this does that too.
///
/// On Apple platforms Quill offsets its caret prototype by 2px and then
/// centers it on the line, so the caret hangs below the text. This one is
/// sized to the text and centered on the line box, which (with even leading
/// in the text style) is also the center of the glyphs. Solid while typing,
/// blinks when idle.
class ComposerCaret extends StatefulWidget {
  const ComposerCaret({
    super.key,
    required this.editorKey,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.height,
    required this.color,
    required this.child,
    this.width = 1.5,
  });

  final Widget child;

  final GlobalKey<EditorState> editorKey;
  final QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final double height;
  final double width;
  final Color color;

  @override
  State<ComposerCaret> createState() => ComposerCaretState();
}

class ComposerCaretState extends State<ComposerCaret> {
  static const _blinkDelay = Duration(milliseconds: 500);
  static const _blinkInterval = Duration(milliseconds: 530);

  Rect? _rect;

  /// Caret rect in this widget's coordinates, or null when hidden.
  @visibleForTesting
  Rect? get caretRect => _visible ? _rect : null;
  bool _visible = true;
  bool _measureScheduled = false;
  bool _revealPending = false;
  Timer? _blinkTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleCaretMoved);
    widget.focusNode.addListener(_handleCaretMoved);
    widget.scrollController.addListener(_scheduleMeasure);
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(ComposerCaret oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleMeasure();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleCaretMoved);
    widget.focusNode.removeListener(_handleCaretMoved);
    widget.scrollController.removeListener(_scheduleMeasure);
    _blinkTimer?.cancel();
    super.dispose();
  }

  void _handleCaretMoved() {
    _restartBlink();
    // Edits and caret moves follow the caret; plain scrolling does not.
    _revealPending = true;
    _scheduleMeasure();
  }

  void _restartBlink() {
    _blinkTimer?.cancel();
    _blinkTimer = null;
    if (!_visible) setState(() => _visible = true);
    if (!widget.focusNode.hasFocus) return;
    _blinkTimer = Timer(_blinkDelay, () {
      if (!mounted) return;
      setState(() => _visible = false);
      _blinkTimer = Timer.periodic(_blinkInterval, (_) {
        if (mounted) setState(() => _visible = !_visible);
      });
    });
  }

  /// Measures after layout, once the editor reflects the latest change.
  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (!mounted) return;
      if (_revealPending) {
        _revealPending = false;
        if (_revealCaretLine()) return; // Scrolling re-schedules a measure.
      }
      final rect = _measure();
      if (rect != _rect) setState(() => _rect = rect);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Scrolls the editor so the caret's whole line is visible. Returns true
  /// if it scrolled.
  bool _revealCaretLine() {
    final selection = widget.controller.selection;
    final editor = widget.editorKey.currentState?.renderEditor;
    final layer = context.findRenderObject() as RenderBox?;
    final scroll = widget.scrollController;
    if (!selection.isValid ||
        editor == null ||
        layer == null ||
        !editor.attached ||
        !layer.hasSize ||
        !scroll.hasClients) {
      return false;
    }
    final line = editor.getLocalRectForCaret(
      TextPosition(offset: selection.extentOffset),
    );
    final top = layer.globalToLocal(editor.localToGlobal(line.topLeft)).dy;
    final bottom = top + line.height;
    final position = scroll.position;
    var target = position.pixels;
    if (bottom > layer.size.height) {
      target += bottom - layer.size.height;
    } else if (top < 0) {
      target += top;
    }
    target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return false;
    position.jumpTo(target);
    return true;
  }

  Rect? _measure() {
    final selection = widget.controller.selection;
    if (!widget.focusNode.hasFocus || !selection.isCollapsed) return null;
    final editor = widget.editorKey.currentState?.renderEditor;
    final layer = context.findRenderObject() as RenderBox?;
    if (editor == null || layer == null || !editor.attached || !layer.hasSize) {
      return null;
    }
    final position = TextPosition(offset: selection.extentOffset);
    // Line box (top, full line height) in editor-local coordinates. Its x
    // includes Quill's -2px "iOS" nudge, so take x from the selection
    // endpoint instead, which is the true glyph boundary.
    final line = editor.getLocalRectForCaret(position);
    final x = editor
        .getEndpointsForSelection(TextSelection.fromPosition(position))
        .first
        .point
        .dx;
    final origin = layer.globalToLocal(
      editor.localToGlobal(Offset(x, line.top)),
    );
    return Rect.fromLTWH(
      origin.dx.clamp(0, math.max(0, layer.size.width - widget.width)),
      origin.dy + (line.height - widget.height) / 2,
      widget.width,
      widget.height,
    );
  }

  @override
  Widget build(BuildContext context) {
    final rect = _rect;
    return Stack(
      children: [
        // Re-measure when the editor reflows (width change, new lines).
        NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            _scheduleMeasure();
            return true;
          },
          child: SizeChangedLayoutNotifier(child: widget.child),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: rect == null || !_visible
                  ? null
                  : _CaretPainter(rect, widget.color),
            ),
          ),
        ),
      ],
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter(this.rect, this.color);

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(0.75)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}
