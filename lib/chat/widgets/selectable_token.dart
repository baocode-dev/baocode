import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/app_theme.dart';

/// Makes [child] one unit of text selection: selected whole or not at all
/// (whenever the two selection edges fall on either side of it), and copied
/// as [text].
///
/// A leaf [Selectable] rather than a [SelectionContainer] around the label:
/// nested containers each replay the last edge positions they saw when
/// their content re-registers, which in a scrolling list goes stale.
class SelectableToken extends SingleChildRenderObjectWidget {
  const SelectableToken({super.key, required this.text, required super.child});

  final String text;

  @override
  RenderSelectableToken createRenderObject(BuildContext context) =>
      RenderSelectableToken(text, _selectionColor(context))
        ..registrar = SelectionContainer.maybeOf(context);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSelectableToken renderObject,
  ) {
    renderObject
      ..text = text
      ..selectionColor = _selectionColor(context)
      ..registrar = SelectionContainer.maybeOf(context);
  }

  static Color _selectionColor(BuildContext context) =>
      DefaultSelectionStyle.of(context).selectionColor ??
      AppColors.textSelection;
}

class RenderSelectableToken extends RenderProxyBox
    with Selectable, SelectionRegistrant {
  RenderSelectableToken(this.text, this._selectionColor);

  String text;

  Color _selectionColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    if (_selected) markNeedsPaint();
  }

  /// Which side of the tag each edge is on: false before, true after.
  bool? _startAfter;
  bool? _endAfter;

  bool get _selected =>
      _startAfter != null && _endAfter != null && _startAfter != _endAfter;

  // --- Where a point is -----------------------------------------------------

  /// Before or after the tag in reading order: above or left of it on its
  /// line is before; inside, the nearer half decides.
  bool _isAfter(Offset globalPosition) {
    final local = globalToLocal(globalPosition);
    if (local.dy < 0) return false;
    if (local.dy > size.height) return true;
    return local.dx > size.width / 2;
  }

  SelectionResult _resultFor(Offset globalPosition) {
    final local = globalToLocal(globalPosition);
    if (size.contains(local)) return SelectionResult.end;
    return _isAfter(globalPosition)
        ? SelectionResult.next
        : SelectionResult.previous;
  }

  // --- Selectable -------------------------------------------------------------

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final wasSelected = _selected;
    final SelectionResult result;
    switch (event) {
      case SelectionEdgeUpdateEvent(:final globalPosition, :final type):
        final after = _isAfter(globalPosition);
        if (type == SelectionEventType.startEdgeUpdate) {
          _startAfter = after;
        } else {
          _endAfter = after;
        }
        result = _resultFor(globalPosition);
      case SelectAllSelectionEvent():
        _startAfter = false;
        _endAfter = true;
        result = SelectionResult.none;
      case ClearSelectionEvent():
        _startAfter = _endAfter = null;
        result = SelectionResult.none;
      case SelectWordSelectionEvent(:final globalPosition) ||
          SelectParagraphSelectionEvent(:final globalPosition):
        result = _resultFor(globalPosition);
        if (result == SelectionResult.end) {
          _startAfter = false;
          _endAfter = true;
        }
      default:
        result = SelectionResult.none;
    }
    if (_selected != wasSelected) {
      markNeedsPaint();
      _notifyListeners();
    }
    return result;
  }

  @override
  SelectionGeometry get value {
    if (!_selected) {
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: true,
      );
    }
    final forward = _endAfter!;
    SelectionPoint point(bool right) => SelectionPoint(
      localPosition: Offset(right ? size.width : 0, size.height),
      lineHeight: size.height,
      handleType: right
          ? TextSelectionHandleType.right
          : TextSelectionHandleType.left,
    );
    return SelectionGeometry(
      status: SelectionStatus.uncollapsed,
      hasContent: true,
      startSelectionPoint: point(!forward),
      endSelectionPoint: point(forward),
      selectionRects: [Offset.zero & size],
    );
  }

  @override
  SelectedContent? getSelectedContent() =>
      _selected ? SelectedContent(plainText: text) : null;

  @override
  SelectedContentRange? getSelection() {
    if (!_selected) return null;
    final forward = _endAfter!;
    return SelectedContentRange(
      startOffset: forward ? 0 : text.length,
      endOffset: forward ? text.length : 0,
    );
  }

  @override
  int get contentLength => text.length;

  @override
  List<Rect> get boundingBoxes => [Offset.zero & size];

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {}

  final List<VoidCallback> _listeners = [];

  @override
  void addListener(VoidCallback listener) => _listeners.add(listener);

  @override
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  void _notifyListeners() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (_selected) {
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(offset & size, const Radius.circular(4)),
        Paint()..color = _selectionColor,
      );
    }
  }
}
