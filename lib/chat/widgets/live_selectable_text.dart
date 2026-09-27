import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// Plain text, selectable under a [SelectionArea], that keeps its selection
/// on the same characters while it changes: for text that streams in.
///
/// A [Text] cannot: each change of its text replaces its selectable, whose
/// selection is then rebuilt, a frame late, from where the selection's ends
/// were on screen. The highlight blinks with every new chunk, and slides
/// onto other characters once the text scrolls to follow new lines.
class LiveSelectableText extends LeafRenderObjectWidget {
  const LiveSelectableText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  RenderLiveSelectableText createRenderObject(BuildContext context) =>
      RenderLiveSelectableText(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        selectionColor: DefaultSelectionStyle.of(context).selectionColor,
        registrar: SelectionContainer.maybeOf(context),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderLiveSelectableText renderObject,
  ) {
    renderObject
      ..text = text
      ..style = DefaultTextStyle.of(context).style.merge(style)
      ..textDirection = Directionality.of(context)
      ..textScaler = MediaQuery.textScalerOf(context)
      ..selectionColor = DefaultSelectionStyle.of(context).selectionColor
      ..registrar = SelectionContainer.maybeOf(context);
  }
}

class RenderLiveSelectableText extends RenderBox {
  RenderLiveSelectableText({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    Color? selectionColor,
    SelectionRegistrar? registrar,
  }) : _text = text,
       _style = style,
       _painter = TextPainter(
         text: TextSpan(text: text, style: style),
         textDirection: textDirection,
         textScaler: textScaler,
       ) {
    _selectionColor = selectionColor;
    _registrar = registrar;
    _selectable = _LiveSelectable(this);
  }

  final TextPainter _painter;
  late final _LiveSelectable _selectable;

  /// The selected range of [text], if any.
  TextSelection? get selection => _selectable.textSelection;

  String get text => _text;
  String _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _painter.text = TextSpan(text: value, style: _style);
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  TextStyle _style;
  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    _painter.text = TextSpan(text: _text, style: value);
    markNeedsLayout();
  }

  set textDirection(TextDirection value) {
    if (value == _painter.textDirection) return;
    _painter.textDirection = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _painter.textScaler) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  Color? _selectionColor;
  set selectionColor(Color? value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  SelectionRegistrar? _registrar;
  set registrar(SelectionRegistrar? value) {
    if (value == _registrar) return;
    _registrar = value;
    if (attached) _selectable.registrar = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _selectable.registrar = _registrar;
  }

  @override
  void detach() {
    _selectable.registrar = null;
    super.detach();
  }

  @override
  void dispose() {
    _selectable.dispose();
    _painter.dispose();
    super.dispose();
  }

  void _layoutText(double maxWidth) =>
      _painter.layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);

  @override
  double computeMinIntrinsicWidth(double height) {
    _layoutText(double.infinity);
    return _painter.minIntrinsicWidth;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    _layoutText(double.infinity);
    return _painter.maxIntrinsicWidth;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    _layoutText(width);
    return _painter.height;
  }

  @override
  double computeMaxIntrinsicHeight(double width) =>
      computeMinIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    _layoutText(constraints.maxWidth);
    return constraints.constrain(_painter.size);
  }

  @override
  void performLayout() {
    _layoutText(constraints.maxWidth);
    size = constraints.constrain(_painter.size);
    _selectable.didLayout();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void paint(PaintingContext context, Offset offset) {
    final selection = _selectable.textSelection;
    final color = _selectionColor;
    if (selection != null && color != null) {
      final paint = Paint()..color = color;
      for (final box in _painter.getBoxesForSelection(selection)) {
        context.canvas.drawRect(box.toRect().shift(offset), paint);
      }
    }
    _painter.paint(context.canvas, offset);
    _selectable.paintHandles(context, offset);
  }

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..label = _text
      ..textDirection = _painter.textDirection;
  }
}

/// The selection of a [RenderLiveSelectableText], as character offsets.
class _LiveSelectable with Selectable, ChangeNotifier, SelectionRegistrant {
  _LiveSelectable(this._render);

  final RenderLiveSelectableText _render;

  int? _start;
  int? _end;
  LayerLink? _startHandle;
  LayerLink? _endHandle;

  TextPainter get _painter => _render._painter;
  String get _text => _render._text;
  Rect get _rect => Offset.zero & size;

  TextSelection? get textSelection => _start == null || _end == null
      ? null
      : TextSelection(baseOffset: _start!, extentOffset: _end!);

  @override
  SelectionGeometry get value => _geometry;
  SelectionGeometry _geometry = const SelectionGeometry(
    status: SelectionStatus.none,
    hasContent: true,
  );

  /// New text keeps the selection where it was, clamped to the text.
  void didLayout() {
    if (_start != null) _start = math.min(_start!, _text.length);
    if (_end != null) _end = math.min(_end!, _text.length);
    _updateGeometry();
  }

  void _updateGeometry() {
    final geometry = _computeGeometry();
    if (geometry == _geometry) return;
    _geometry = geometry;
    notifyListeners();
  }

  Offset _pointAt(int offset) {
    final position = TextPosition(offset: offset);
    return _painter.getOffsetForCaret(position, Rect.zero) +
        Offset(0, _painter.getFullHeightForCaret(position, Rect.zero));
  }

  SelectionGeometry _computeGeometry() {
    final selection = textSelection;
    if (selection == null || !_render.hasSize) {
      return const SelectionGeometry(
        status: SelectionStatus.none,
        hasContent: true,
      );
    }
    final collapsed = selection.isCollapsed;
    final reversed = selection.baseOffset > selection.extentOffset;
    final (startType, endType) = collapsed
        ? (TextSelectionHandleType.collapsed, TextSelectionHandleType.collapsed)
        : reversed
        ? (TextSelectionHandleType.right, TextSelectionHandleType.left)
        : (TextSelectionHandleType.left, TextSelectionHandleType.right);
    return SelectionGeometry(
      startSelectionPoint: SelectionPoint(
        localPosition: _pointAt(selection.baseOffset),
        lineHeight: _painter.preferredLineHeight,
        handleType: startType,
      ),
      endSelectionPoint: SelectionPoint(
        localPosition: _pointAt(selection.extentOffset),
        lineHeight: _painter.preferredLineHeight,
        handleType: endType,
      ),
      selectionRects: [
        for (final box in _painter.getBoxesForSelection(selection))
          box.toRect(),
      ],
      status: collapsed ? SelectionStatus.collapsed : SelectionStatus.uncollapsed,
      hasContent: true,
    );
  }

  @override
  Size get size => _render.hasSize ? _render.size : Size.zero;

  @override
  List<Rect> get boundingBoxes => [_rect];

  @override
  Matrix4 getTransformTo(RenderObject? ancestor) =>
      _render.getTransformTo(ancestor);

  @override
  int get contentLength => _text.length;

  @override
  SelectedContent? getSelectedContent() {
    final selection = textSelection;
    if (selection == null) return null;
    return SelectedContent(plainText: selection.textInside(_text));
  }

  @override
  SelectedContentRange? getSelection() {
    if (_start == null || _end == null) return null;
    return SelectedContentRange(startOffset: _start!, endOffset: _end!);
  }

  @override
  SelectionResult dispatchSelectionEvent(SelectionEvent event) {
    final (start, end) = (_start, _end);
    final result = switch (event) {
      SelectionEdgeUpdateEvent() => _updateEdge(event),
      ClearSelectionEvent() => _select(null, null, SelectionResult.none),
      SelectAllSelectionEvent() => _select(0, _text.length, SelectionResult.none),
      SelectWordSelectionEvent() => _selectAround(
        event.globalPosition,
        _wordAt,
      ),
      SelectParagraphSelectionEvent(absorb: true) => _select(
        0,
        _text.length,
        SelectionResult.next,
      ),
      SelectParagraphSelectionEvent() => _selectAround(
        event.globalPosition,
        _paragraphAt,
      ),
      GranularlyExtendSelectionEvent() => _extendBy(event),
      DirectionallyExtendSelectionEvent() => _extendTo(event),
      _ => SelectionResult.none,
    };
    if (start != _start || end != _end) {
      _render.markNeedsPaint();
      _updateGeometry();
    }
    return result;
  }

  SelectionResult _select(int? start, int? end, SelectionResult result) {
    _start = start;
    _end = end;
    return result;
  }

  Offset _toLocal(Offset globalPosition) => _render.globalToLocal(globalPosition);

  int _positionAt(Offset local) => _painter
      .getPositionForOffset(
        SelectionUtils.adjustDragOffset(
          _rect,
          local,
          direction: _painter.textDirection!,
        ),
      )
      .offset;

  SelectionResult _updateEdge(SelectionEdgeUpdateEvent event) {
    final isEnd = event.type == SelectionEventType.endEdgeUpdate;
    final local = _toLocal(event.globalPosition);
    final other = isEnd ? _start : _end;
    var offset = _rect.isEmpty ? 0 : _positionAt(local);
    // By word or paragraph (a drag after a double or triple click): out to
    // the far side of the unit under the pointer.
    final TextRange Function(int)? unit = switch (event.granularity) {
      TextGranularity.word => _wordAt,
      TextGranularity.paragraph => _paragraphAt,
      _ => null,
    };
    if (unit != null) {
      final range = unit(offset);
      final forward = other == null || (isEnd ? offset >= other : offset > other);
      offset = forward == isEnd ? range.end : range.start;
    }
    if (isEnd) {
      _end = offset;
    } else {
      _start = offset;
    }
    if (_rect.isEmpty) return SelectionUtils.getResultBasedOnRect(_rect, local);
    if (offset == _text.length) return SelectionResult.next;
    if (offset == 0) return SelectionResult.previous;
    return SelectionUtils.getResultBasedOnRect(_rect, local);
  }

  SelectionResult _selectAround(
    Offset globalPosition,
    TextRange Function(int) unit,
  ) {
    final local = _toLocal(globalPosition);
    if (!_rect.contains(local)) {
      return SelectionUtils.getResultBasedOnRect(_rect, local);
    }
    final range = unit(_positionAt(local));
    return _select(range.start, range.end, SelectionResult.end);
  }

  TextRange _wordAt(int offset) =>
      _painter.getWordBoundary(TextPosition(offset: offset));

  TextRange _paragraphAt(int offset) {
    final start = offset == 0 ? 0 : _text.lastIndexOf('\n', offset - 1) + 1;
    final end = _text.indexOf('\n', offset);
    return TextRange(start: start, end: end == -1 ? _text.length : end);
  }

  /// Shift+arrow keys by character, word, line or all, possibly arriving
  /// from a neighbor (no selection yet here).
  SelectionResult _extendBy(GranularlyExtendSelectionEvent event) {
    final forward = event.forward;
    _end ??= forward ? 0 : _text.length;
    _start ??= _end;
    final edge = event.isEnd ? _end! : _start!;
    if (forward && edge == _text.length) return SelectionResult.next;
    if (!forward && edge == 0) return SelectionResult.previous;
    final int moved;
    switch (event.granularity) {
      case TextGranularity.character:
        final boundary = CharacterBoundary(_text);
        moved = forward
            ? boundary.getTrailingTextBoundaryAt(edge) ?? _text.length
            : boundary.getLeadingTextBoundaryAt(edge - 1) ?? 0;
      case TextGranularity.word:
        final boundary = _painter.wordBoundaries.moveByWordBoundary;
        moved = forward
            ? boundary.getTrailingTextBoundaryAt(edge) ?? _text.length
            : boundary.getLeadingTextBoundaryAt(edge - 1) ?? 0;
      case TextGranularity.paragraph:
        final range = _paragraphAt(forward ? edge + 1 : edge - 1);
        moved = forward ? range.end : range.start;
      case TextGranularity.line:
        final line = _painter.getLineBoundary(
          TextPosition(
            offset: edge,
            affinity: forward ? TextAffinity.downstream : TextAffinity.upstream,
          ),
        );
        moved = forward ? line.end : line.start;
      case TextGranularity.document:
        moved = forward ? _text.length : 0;
    }
    if (event.isEnd) {
      _end = moved;
    } else {
      _start = moved;
    }
    if (event.granularity == TextGranularity.document) {
      return forward ? SelectionResult.next : SelectionResult.previous;
    }
    return SelectionResult.end;
  }

  /// Shift+up/down, keeping to a horizontal position.
  SelectionResult _extendTo(DirectionallyExtendSelectionEvent event) {
    final x = _toLocal(Offset(event.dx, 0)).dx;
    final lineHeight = _painter.preferredLineHeight;
    final int moved;
    final SelectionResult result;
    switch (event.direction) {
      case SelectionExtendDirection.previousLine:
      case SelectionExtendDirection.nextLine:
        final edge = (event.isEnd ? _end : _start) ?? 0;
        final below = event.direction == SelectionExtendDirection.nextLine;
        final y = _pointAt(edge).dy + (below ? 0.5 : -1.5) * lineHeight;
        if (y < 0) {
          (moved, result) = (0, SelectionResult.previous);
        } else if (y > size.height) {
          (moved, result) = (_text.length, SelectionResult.next);
        } else {
          (moved, result) = (
            _painter.getPositionForOffset(Offset(x, y)).offset,
            SelectionResult.end,
          );
        }
      case SelectionExtendDirection.forward:
      case SelectionExtendDirection.backward:
        final forward = event.direction == SelectionExtendDirection.forward;
        _end ??= forward ? 0 : _text.length;
        _start ??= _end;
        final edge = event.isEnd ? _end! : _start!;
        final y = _pointAt(edge).dy - lineHeight / 2;
        (moved, result) = (
          _painter.getPositionForOffset(Offset(x, y)).offset,
          SelectionResult.end,
        );
    }
    if (event.isEnd) {
      _end = moved;
    } else {
      _start = moved;
    }
    return result;
  }

  @override
  void pushHandleLayers(LayerLink? startHandle, LayerLink? endHandle) {
    if (startHandle == _startHandle && endHandle == _endHandle) return;
    _startHandle = startHandle;
    _endHandle = endHandle;
    if (_render.attached) _render.markNeedsPaint();
  }

  void paintHandles(PaintingContext context, Offset offset) {
    for (final (link, point) in [
      (_startHandle, _geometry.startSelectionPoint),
      (_endHandle, _geometry.endSelectionPoint),
    ]) {
      if (link == null || point == null) continue;
      context.pushLayer(
        LeaderLayer(link: link, offset: offset + point.localPosition),
        (context, offset) {},
        Offset.zero,
      );
    }
  }
}
