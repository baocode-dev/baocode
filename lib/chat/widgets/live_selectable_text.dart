import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../selection/chat_selection.dart';

/// Plain text, selectable under a [SelectionArea], that keeps its selection
/// on the same characters while it changes: for text that streams in.
///
/// A [Text] cannot: each change of its text replaces its selectable, whose
/// selection is then rebuilt, a frame late, from where the selection's ends
/// were on screen. The highlight blinks with every new chunk, and slides
/// onto other characters once the text scrolls to follow new lines.
///
/// Laid out a block of lines at a time ([_ChunkedPainter]): text that grows
/// at its end lays out only its last block again, not all of a thought of
/// tens of thousands of characters with every few words.
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

class RenderLiveSelectableText extends RenderBox implements ChatTextLeafSource {
  @override
  ChatTextLeaf get chatTextLeaf => _LiveLeaf(this);

  RenderLiveSelectableText({
    required String text,
    required TextStyle style,
    required TextDirection textDirection,
    required TextScaler textScaler,
    Color? selectionColor,
    SelectionRegistrar? registrar,
  }) : _text = text,
       _style = style,
       _painter = _ChunkedPainter(
         text,
         style,
         textDirection: textDirection,
         textScaler: textScaler,
       ) {
    _selectionColor = selectionColor;
    _registrar = registrar;
    _selectable = _LiveSelectable(this);
  }

  final _ChunkedPainter _painter;
  late final _LiveSelectable _selectable;

  /// The selected range of [text], if any.
  TextSelection? get selection => _selectable.textSelection;

  /// How many of its blocks of lines hold a laid out painter.
  @visibleForTesting
  int get debugHeldBlocks =>
      _painter._chunks.where((chunk) => chunk.painter != null).length;

  String get text => _text;
  String _text;
  set text(String value) {
    if (value == _text) return;
    _text = value;
    _painter.text = value;
    markNeedsLayout();
    markNeedsSemanticsUpdate();
  }

  TextStyle _style;
  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    _painter.style = value;
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
    final clip = _shown(context.canvas, offset);
    if (selection != null && color != null) {
      final paint = Paint()..color = color;
      for (final box in _painter.getBoxesForSelection(
        selection,
        within: clip,
      )) {
        context.canvas.drawRect(box.toRect().shift(offset), paint);
      }
    }
    _painter.paint(context.canvas, offset, clip);
    _selectable.paintHandles(context, offset);
  }

  /// What of it shows, in its own coordinates: the canvas's clip, and its
  /// scroll box's (a canvas of a layer of its own clips nothing).
  Rect _shown(Canvas canvas, Offset offset) {
    var shown = canvas.getLocalClipBounds().shift(-offset);
    if (RenderAbstractViewport.maybeOf(this) case final RenderBox viewport
        when viewport.hasSize) {
      final toViewport = getTransformTo(viewport);
      if (toViewport.invert() != 0) {
        shown = shown.intersect(
          MatrixUtils.transformRect(toViewport, Offset.zero & viewport.size),
        );
      }
    }
    return shown;
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

  _ChunkedPainter get _painter => _render._painter;
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

  /// Its geometry is to be told once this frame's layout is done.
  bool _geometryScheduled = false;
  bool _disposed = false;

  /// New text keeps the selection where it was, clamped to the text. Its
  /// geometry (wrapped anew, say) is told after the frame's layout: the
  /// containers it is told to read their own sizes, which a layout under
  /// way does not allow.
  void didLayout() {
    if (_start != null) _start = math.min(_start!, _text.length);
    if (_end != null) _end = math.min(_end!, _text.length);
    // Nothing selected, nothing to tell, as text streams in.
    if (textSelection == null && _geometry.status == SelectionStatus.none) {
      return;
    }
    if (_geometryScheduled) return;
    _geometryScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _geometryScheduled = false;
      if (!_disposed && _render.attached) _updateGeometry();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
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
        for (final box in _painter.getBoxesForSelection(
          selection,
          exact: false,
        ))
          box.toRect(),
      ],
      status: collapsed
          ? SelectionStatus.collapsed
          : SelectionStatus.uncollapsed,
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
      SelectAllSelectionEvent() => _select(
        0,
        _text.length,
        SelectionResult.none,
      ),
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

  Offset _toLocal(Offset globalPosition) =>
      _render.globalToLocal(globalPosition);

  int _positionAt(Offset local) => _painter
      .getPositionForOffset(
        SelectionUtils.adjustDragOffset(
          _rect,
          local,
          direction: _painter.textDirection,
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
      final forward =
          other == null || (isEnd ? offset >= other : offset > other);
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
        final boundary = _painter.moveByWordBoundary;
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

/// [text] in blocks of lines, a [TextPainter] each, stacked: what a single
/// painter of it would lay out, but each block only once while the text
/// grows at its end. A block ends at the first line break past
/// [_chunkLength] characters, the break between it and the next.
///
/// A block far from what was last painted lets go of its painter, its
/// measures kept: a thought of 60,000 characters held the engine's
/// paragraphs of all of it, while its box shows a few lines. Asked of
/// again (a selection reaching it, scrolled to), it is laid out anew.
class _ChunkedPainter {
  _ChunkedPainter(
    this._text,
    this._style, {
    required this._textDirection,
    required this._textScaler,
  }) {
    _chunkFrom(0);
  }

  static const _chunkLength = 1000;

  /// How far past what was painted blocks keep their painters.
  static const _keepWithin = 1000.0;

  String _text;
  TextStyle _style;
  TextDirection _textDirection;
  TextScaler _textScaler;
  final List<_Chunk> _chunks = [];
  double _maxWidth = double.nan;
  Size _size = Size.zero;

  /// What was last painted, and some way past it: where blocks keep their
  /// painters. Null until painted: all of them.
  Rect? _kept;

  /// For the height of a line, with no block laid out.
  TextPainter? _probe;

  set text(String value) {
    final old = _text;
    _text = value;
    // The blocks (and the breaks after them) it still starts with stay.
    var same = 0;
    final shorter = math.min(old.length, value.length);
    while (same < shorter && old.codeUnitAt(same) == value.codeUnitAt(same)) {
      same++;
    }
    var kept = 0;
    while (kept < _chunks.length && _chunks[kept].end < same) {
      kept++;
    }
    _dropFrom(kept);
    _chunkFrom(kept == 0 ? 0 : _chunks[kept - 1].end + 1);
  }

  set style(TextStyle value) {
    _style = value;
    _rebuild();
  }

  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    _textDirection = value;
    _rebuild();
  }

  TextScaler get textScaler => _textScaler;
  set textScaler(TextScaler value) {
    _textScaler = value;
    _rebuild();
  }

  void _rebuild() {
    _probe?.dispose();
    _probe = null;
    _dropFrom(0);
    _chunkFrom(0);
  }

  void _dropFrom(int index) {
    for (final chunk in _chunks.skip(index)) {
      chunk.release();
    }
    _chunks.length = index;
    _maxWidth = double.nan;
  }

  void _chunkFrom(int start) {
    while (true) {
      final cut = start + _chunkLength >= _text.length
          ? -1
          : _text.indexOf('\n', start + _chunkLength);
      final end = cut == -1 ? _text.length : cut;
      _chunks.add(_Chunk(start, end));
      if (cut == -1) return;
      start = cut + 1;
    }
  }

  /// [chunk]'s painter, laid out as the others are.
  TextPainter _painterOf(_Chunk chunk) {
    final fresh = chunk.painter == null;
    final painter = chunk.painter ??= TextPainter(
      text: TextSpan(
        text: _text.substring(chunk.start, chunk.end),
        style: _style,
      ),
      textDirection: _textDirection,
      textScaler: _textScaler,
    );
    if ((fresh || chunk.laidOutAt != _maxWidth) && _maxWidth == _maxWidth) {
      painter.layout(maxWidth: _maxWidth);
      chunk
        ..laidOutAt = _maxWidth
        ..height = painter.height
        ..width = painter.width
        ..minIntrinsicWidth = painter.minIntrinsicWidth
        ..maxIntrinsicWidth = painter.maxIntrinsicWidth;
    }
    return painter;
  }

  bool _keeps(_Chunk chunk) => switch (_kept) {
    final kept? =>
      chunk.top <= kept.bottom && chunk.top + chunk.height >= kept.top,
    null => true,
  };

  void layout({required double maxWidth}) {
    _maxWidth = maxWidth;
    var top = 0.0;
    var width = 0.0;
    for (final chunk in _chunks) {
      chunk.top = top;
      if (chunk.laidOutAt != maxWidth) {
        _painterOf(chunk);
        if (!_keeps(chunk)) chunk.release();
      }
      top += chunk.height;
      width = math.max(width, chunk.width);
    }
    _size = Size(width, top);
  }

  Size get size => _size;
  double get height => _size.height;

  double get minIntrinsicWidth => _chunks.fold(
    0,
    (width, chunk) => math.max(width, chunk.minIntrinsicWidth),
  );

  double get maxIntrinsicWidth => _chunks.fold(
    0,
    (width, chunk) => math.max(width, chunk.maxIntrinsicWidth),
  );

  double get preferredLineHeight => (_probe ??= TextPainter(
    text: TextSpan(text: ' ', style: _style),
    textDirection: _textDirection,
    textScaler: _textScaler,
  )).preferredLineHeight;

  /// The block [offset] is in, a break between two counting as the end of
  /// the first.
  _Chunk _chunkOf(int offset) {
    var low = 0;
    var high = _chunks.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_chunks[mid].end < offset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return _chunks[low];
  }

  /// The block at [y], the first or last past the ends.
  _Chunk _chunkAt(double y) {
    var low = 0;
    var high = _chunks.length - 1;
    while (low < high) {
      final mid = (low + high + 1) ~/ 2;
      if (_chunks[mid].top <= y) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return _chunks[low];
  }

  TextPosition _local(_Chunk chunk, TextPosition position) => TextPosition(
    offset: (position.offset - chunk.start).clamp(0, chunk.end - chunk.start),
    affinity: position.affinity,
  );

  Offset getOffsetForCaret(TextPosition position, Rect caretPrototype) {
    final chunk = _chunkOf(position.offset);
    return _painterOf(chunk)
            .getOffsetForCaret(_local(chunk, position), caretPrototype) +
        Offset(0, chunk.top);
  }

  double getFullHeightForCaret(TextPosition position, Rect caretPrototype) {
    final chunk = _chunkOf(position.offset);
    return _painterOf(chunk)
        .getFullHeightForCaret(_local(chunk, position), caretPrototype);
  }

  TextPosition getPositionForOffset(Offset offset) {
    final chunk = _chunkAt(offset.dy);
    final position = _painterOf(chunk)
        .getPositionForOffset(offset - Offset(0, chunk.top));
    return TextPosition(
      offset: chunk.start + position.offset,
      affinity: position.affinity,
    );
  }

  /// The boxes of [selection], of the blocks [within] (all when null). A
  /// block selected whole that has let go of its painter is a box of its
  /// own, unless [exact].
  List<TextBox> getBoxesForSelection(
    TextSelection selection, {
    Rect? within,
    bool exact = true,
  }) {
    final start = math.min(selection.baseOffset, selection.extentOffset);
    final end = math.max(selection.baseOffset, selection.extentOffset);
    return [
      for (final chunk in _chunks)
        if (chunk.start < end &&
            start <= chunk.end &&
            (within == null ||
                (chunk.top <= within.bottom &&
                    chunk.top + chunk.height >= within.top)))
          if (!exact &&
              chunk.painter == null &&
              start <= chunk.start &&
              chunk.end <= end)
            TextBox.fromLTRBD(
              0,
              chunk.top,
              chunk.width,
              chunk.top + chunk.height,
              _textDirection,
            )
          else
            for (final box in _painterOf(chunk).getBoxesForSelection(
              TextSelection(
                baseOffset: math.max(start - chunk.start, 0),
                extentOffset: math.min(end, chunk.end) - chunk.start,
              ),
            ))
              TextBox.fromLTRBD(
                box.left,
                box.top + chunk.top,
                box.right,
                box.bottom + chunk.top,
                box.direction,
              ),
    ];
  }

  TextRange _shift(_Chunk chunk, TextRange range) =>
      TextRange(start: chunk.start + range.start, end: chunk.start + range.end);

  TextRange getWordBoundary(TextPosition position) {
    final chunk = _chunkOf(position.offset);
    return _shift(
      chunk,
      _painterOf(chunk).getWordBoundary(_local(chunk, position)),
    );
  }

  TextRange getLineBoundary(TextPosition position) {
    final chunk = _chunkOf(position.offset);
    return _shift(
      chunk,
      _painterOf(chunk).getLineBoundary(_local(chunk, position)),
    );
  }

  /// Moving by word, as [TextPainter.wordBoundaries] does, across blocks.
  TextBoundary get moveByWordBoundary => _ChunkedWordBoundary(this);

  /// Only the blocks in [clip], what shows: a long text's others are not
  /// recorded each frame, and those far from it let go of their painters.
  void paint(Canvas canvas, Offset offset, Rect clip) {
    assert(_maxWidth == _maxWidth, 'paint before layout');
    _kept = clip.inflate(_keepWithin);
    for (final chunk in _chunks) {
      if (chunk.top > clip.bottom || chunk.top + chunk.height < clip.top) {
        if (!_keeps(chunk)) chunk.release();
        continue;
      }
      _painterOf(chunk).paint(canvas, offset + Offset(0, chunk.top));
    }
  }

  void dispose() {
    _probe?.dispose();
    _dropFrom(0);
  }
}

class _Chunk {
  _Chunk(this.start, this.end);

  /// Its text in the whole: [start] to [end], the break (if any) after.
  final int start;
  final int end;

  /// Laid out at [laidOutAt]; null once let go of, its measures kept.
  TextPainter? painter;
  double laidOutAt = double.nan;
  double top = 0;
  double height = 0;
  double width = 0;
  double minIntrinsicWidth = 0;
  double maxIntrinsicWidth = 0;

  void release() {
    painter?.dispose();
    painter = null;
  }
}

class _ChunkedWordBoundary extends TextBoundary {
  _ChunkedWordBoundary(this._painter);

  final _ChunkedPainter _painter;

  @override
  int? getLeadingTextBoundaryAt(int position) {
    if (position < 0) return null;
    final chunk = _painter._chunkOf(position);
    final local = _painter
        ._painterOf(chunk)
        .wordBoundaries
        .moveByWordBoundary
        .getLeadingTextBoundaryAt(position - chunk.start);
    return local == null ? null : chunk.start + local;
  }

  @override
  int? getTrailingTextBoundaryAt(int position) {
    final text = _painter._text;
    if (position >= text.length) return null;
    final chunk = _painter._chunkOf(position);
    if (position >= chunk.end) {
      // The break after it: on into the next block.
      return position + 1 >= text.length
          ? text.length
          : getTrailingTextBoundaryAt(position + 1);
    }
    final local = _painter
        ._painterOf(chunk)
        .wordBoundaries
        .moveByWordBoundary
        .getTrailingTextBoundaryAt(position - chunk.start);
    return local == null ? chunk.end : chunk.start + local;
  }
}

/// A [RenderLiveSelectableText] as a piece of the conversation's text.
class _LiveLeaf implements ChatTextLeaf {
  _LiveLeaf(this._render);

  final RenderLiveSelectableText _render;

  @override
  RenderBox get box => _render;

  @override
  String get text => _render._text;

  @override
  String copyOf(int start, int end) {
    final text = _render._text;
    start = start.clamp(0, text.length);
    return text.substring(start, end.clamp(start, text.length));
  }

  @override
  String Function()? get richCopy => null;

  @override
  String richCopyOf(int start, int end) => copyOf(start, end);

  @override
  List<String Function()?> richPlaceholders() => const [];

  @override
  int positionAt(Offset local) => _render._painter
      .getPositionForOffset(local)
      .offset
      .clamp(0, _render._text.length);

  @override
  List<Rect> rectsFor(int start, int end) => [
    for (final box in _render._painter.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: end),
      exact: false,
    ))
      box.toRect(),
  ];

  @override
  TextRange wordAt(int offset) =>
      _render._painter.getWordBoundary(TextPosition(offset: offset));
}
