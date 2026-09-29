import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart';

import '../vs/editor/common/core/range.dart';
import 'document_snapshot.dart';

/// A visual row of one logical document line. Offsets are UTF-16, end-exclusive;
/// [top] and [height] are in unscrolled document coordinates.
class ViewportRow {
  const ViewportRow({
    required this.lineNumber,
    required this.visualLineIndex,
    required this.startOffset,
    required this.endOffset,
    required this.top,
    required this.height,
    required this.left,
    required this.width,
  });

  final int lineNumber;
  final int visualLineIndex;
  final int startOffset;
  final int endOffset;
  final double top;
  final double height;
  final double left;
  final double width;
}

/// Inclusive start and exclusive end indices into [ViewportLayout.rows].
class VisibleRowRange {
  const VisibleRowRange(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => start == end;
}

/// TextPainter-backed geometry for a document in a fixed-size viewport.
///
/// Each distinct logical line is shaped independently, so CR/LF are never
/// painted. Equal lines share their shaped paragraph, and [previousLayout]
/// can preserve paragraphs across edits; row positions are still recomputed
/// exactly from the measured heights. Unwrapped and wrapped lines both use
/// exact TextPainter metrics; a first layout with all-distinct lines must still
/// shape every line to account for variable glyph, span, and fallback heights.
/// Scrolling alone can be updated with [setScrollOffset]. Call [dispose] when
/// finished. Tabs use Flutter's paragraph shaping (custom tab stops are not
/// provided). Rects and hit-test points are relative to the viewport's origin.
/// Positions at a soft wrap have downstream affinity unless specified otherwise.
class ViewportLayout {
  ViewportLayout({
    required this.snapshot,
    required this.style,
    required this.viewportSize,
    this.wrap = false,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
    this.styledLines,
    ViewportLayout? previousLayout,
    double horizontalScrollOffset = 0,
    double verticalScrollOffset = 0,
  }) : assert(viewportSize.width.isFinite && viewportSize.width >= 0),
       assert(viewportSize.height.isFinite && viewportSize.height >= 0),
       assert(!wrap || viewportSize.width > 0) {
    setScrollOffset(
      horizontal: horizontalScrollOffset,
      vertical: verticalScrollOffset,
    );
    final cache = <String, List<_LineShape>>{};
    final previous = previousLayout;
    if (previous != null &&
        !previous._disposed &&
        previous.style == style &&
        previous.wrap == wrap &&
        (!wrap || previous.viewportSize.width == viewportSize.width) &&
        previous.textDirection == textDirection &&
        previous.textScaler == textScaler) {
      for (final shape in previous._ownedShapes) {
        cache.putIfAbsent(shape.content, () => []).add(shape);
      }
    }
    final created = <_LineShape>{};
    var top = 0.0;
    try {
      for (var line = 0; line < snapshot.lineCount; line++) {
        final start = snapshot.lineStarts[line];
        final end = snapshot.contentEnds[line];
        final content = snapshot.text.substring(start, end);
        final spans = styledLines?[line + 1];
        if (spans != null &&
            spans.map((span) => span.toPlainText()).join() != content) {
          throw ArgumentError.value(
            line + 1,
            'styledLines',
            'Text differs from document',
          );
        }
        final candidates = cache.putIfAbsent(content, () => []);
        _LineShape? shape;
        for (final candidate in candidates) {
          if (listEquals(candidate.spans, spans)) {
            shape = candidate;
            break;
          }
        }
        if (shape == null) {
          shape = _LineShape(
            content: content,
            spans: spans == null ? null : List<TextSpan>.of(spans),
            style: style,
            wrapWidth: wrap ? viewportSize.width : double.infinity,
            textDirection: textDirection,
            textScaler: textScaler,
          );
          candidates.add(shape);
          created.add(shape);
        }
        _ownedShapes.add(shape);
        _lineShapes.add(shape);
        _lineTops.add(top);
        for (final row in shape.rows) {
          _rows.add(
            ViewportRow(
              lineNumber: line + 1,
              visualLineIndex: row.visualLineIndex,
              startOffset: start + row.startOffset,
              endOffset: start + row.endOffset,
              top: top + row.top,
              height: row.height,
              left: row.left,
              width: row.width,
            ),
          );
        }
        top += shape.height;
      }
    } catch (_) {
      for (final shape in created) {
        shape.painter.dispose();
      }
      rethrow;
    }
    for (final shape in _ownedShapes) {
      shape.references++;
    }
    shapedLineCount = created.length;
    contentHeight = top;
    rows = List<ViewportRow>.unmodifiable(_rows);
  }

  final DocumentSnapshot snapshot;
  final TextStyle style;
  final Size viewportSize;
  final bool wrap;
  final TextDirection textDirection;
  final TextScaler textScaler;

  /// Optional one-based line runs. Every supplied run must reconstruct the
  /// line's exact raw text so UTF-16 hit testing remains aligned with the model.
  final Map<int, List<TextSpan>>? styledLines;

  /// Number of distinct paragraphs shaped during this construction. Useful for
  /// verifying that edits and scrolling do not reshape unchanged lines.
  late final int shapedLineCount;
  final List<_LineShape> _lineShapes = [];
  final Set<_LineShape> _ownedShapes = {};
  bool _disposed = false;
  final List<double> _lineTops = [];
  final List<ViewportRow> _rows = [];

  late final List<ViewportRow> rows;
  late final double contentHeight;
  double horizontalScrollOffset = 0;
  double verticalScrollOffset = 0;

  /// Scroll offsets are nonnegative and are not clamped to content dimensions.
  /// This allows an editor to reserve space after the final line.
  void setScrollOffset({required double horizontal, required double vertical}) {
    if (!horizontal.isFinite ||
        horizontal < 0 ||
        !vertical.isFinite ||
        vertical < 0) {
      throw ArgumentError('Scroll offsets must be finite and nonnegative.');
    }
    horizontalScrollOffset = horizontal;
    verticalScrollOffset = vertical;
  }

  /// The rows intersecting the vertical viewport; offscreen space yields an
  /// empty range. A zero-height viewport contains no rows.
  VisibleRowRange get visibleRowRange {
    if (viewportSize.height == 0) return const VisibleRowRange(0, 0);
    // First row whose bottom is strictly after the top edge.
    var low = 0;
    var high = rows.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rows[mid].top + rows[mid].height <= verticalScrollOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final first = low;
    high = rows.length;
    final bottom = verticalScrollOffset + viewportSize.height;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rows[mid].top < bottom) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return VisibleRowRange(first, low);
  }

  Iterable<ViewportRow> get visibleRows sync* {
    final range = visibleRowRange;
    for (var i = range.start; i < range.end; i++) {
      yield rows[i];
    }
  }

  /// The visual row's un-clipped bounds in viewport coordinates.
  Rect rowRect(ViewportRow row) => Rect.fromLTWH(
    row.left - horizontalScrollOffset,
    row.top - verticalScrollOffset,
    row.width,
    row.height,
  );

  /// Returns a UTF-16 document offset nearest to [point], including points
  /// outside the viewport (useful when dragging a selection beyond an edge).
  int hitTest(Offset point) {
    final documentY = point.dy + verticalScrollOffset;
    var low = 0;
    var high = rows.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rows[mid].top + rows[mid].height <= documentY) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final row = rows[math.min(low, rows.length - 1)];
    final line = row.lineNumber - 1;
    final local = _lineShapes[line].painter.getPositionForOffset(
      Offset(point.dx + horizontalScrollOffset, documentY - _lineTops[line]),
    );
    return (snapshot.lineStarts[line] + local.offset).clamp(
      snapshot.lineStarts[line],
      snapshot.contentEnds[line],
    );
  }

  /// The un-clipped insertion caret, including offsets in CRLF (which map to
  /// the preceding line's end). [affinity] chooses the side of a soft wrap.
  Rect caretRect(
    int offset, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final position = snapshot.positionAtOffset(offset);
    final line = position.lineNumber - 1;
    final localOffset =
        snapshot.offsetAtPosition(position) - snapshot.lineStarts[line];
    final painter = _lineShapes[line].painter;
    final textPosition = TextPosition(offset: localOffset, affinity: affinity);
    final origin = painter.getOffsetForCaret(textPosition, Rect.zero);
    final height = painter.getFullHeightForCaret(textPosition, Rect.zero);
    return Rect.fromLTWH(
      origin.dx - horizontalScrollOffset,
      origin.dy + _lineTops[line] - verticalScrollOffset,
      1,
      height,
    );
  }

  /// Visible highlight boxes for the half-open [selection], clipped to the
  /// viewport. Each selected line break receives a one-pixel-wide end marker.
  /// BiDi runs and wraps may yield multiple rectangles per logical line.
  List<Rect> selectionRects(IRange selection) {
    final normalized = Range(
      selection.startLineNumber,
      selection.startColumn,
      selection.endLineNumber,
      selection.endColumn,
    );
    final start = snapshot.offsetAtPosition(normalized.getStartPosition());
    final end = snapshot.offsetAtPosition(normalized.getEndPosition());
    if (start >= end || viewportSize.isEmpty) return const [];
    final clip = Offset.zero & viewportSize;
    final results = <Rect>[];
    final range = visibleRowRange;
    var previousLine = -1;
    for (var i = range.start; i < range.end; i++) {
      final line = rows[i].lineNumber - 1;
      if (line == previousLine) continue;
      previousLine = line;
      final lineStart = snapshot.lineStarts[line];
      final contentEnd = snapshot.contentEnds[line];
      if (end <= lineStart || start > contentEnd) continue;
      final from = math.max(start, lineStart) - lineStart;
      final to = math.min(end, contentEnd) - lineStart;
      if (from < to) {
        for (final box in _lineShapes[line].painter.getBoxesForSelection(
          TextSelection(baseOffset: from, extentOffset: to),
          boxHeightStyle: ui.BoxHeightStyle.max,
        )) {
          _addClipped(
            results,
            box.toRect().shift(
              Offset(
                -horizontalScrollOffset,
                _lineTops[line] - verticalScrollOffset,
              ),
            ),
            clip,
          );
        }
      }
      if (snapshot.newlineLengths[line] > 0 &&
          start <= contentEnd &&
          end > contentEnd) {
        _addClipped(
          results,
          caretRect(contentEnd, affinity: TextAffinity.upstream),
          clip,
        );
      }
    }
    return results;
  }

  static void _addClipped(List<Rect> result, Rect rect, Rect clip) {
    final clipped = rect.intersect(clip);
    if (clipped.width > 0 && clipped.height > 0) result.add(clipped);
  }

  /// Paints only visible logical lines and clips both axes to the viewport.
  /// The caller can paint [selectionRects] and [caretRect] independently.
  void paintVisibleText(Canvas canvas, {Offset origin = Offset.zero}) {
    canvas.save();
    canvas.clipRect(origin & viewportSize);
    final range = visibleRowRange;
    var previousLine = -1;
    for (var i = range.start; i < range.end; i++) {
      final line = rows[i].lineNumber - 1;
      if (line == previousLine) continue;
      previousLine = line;
      _lineShapes[line].painter.paint(
        canvas,
        origin +
            Offset(
              -horizontalScrollOffset,
              _lineTops[line] - verticalScrollOffset,
            ),
      );
    }
    canvas.restore();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final shape in _ownedShapes) {
      if (--shape.references == 0) shape.painter.dispose();
    }
  }
}

/// Measured, document-position-independent paragraph geometry. Only identical
/// text and identical styled spans can share it; glyph fallback and styled line
/// heights are never guessed from a representative line.
class _LineShape {
  _LineShape({
    required this.content,
    required this.spans,
    required TextStyle style,
    required double wrapWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
  }) : painter = TextPainter(
         text: spans == null
             ? TextSpan(text: content, style: style)
             : TextSpan(style: style, children: spans),
         textDirection: textDirection,
         textScaler: textScaler,
       ) {
    try {
      painter.layout(maxWidth: wrapWidth);
      final metrics = painter.computeLineMetrics();
      // Flutter returns no line metrics for an empty paragraph.
      if (content.isEmpty) {
        height = painter.preferredLineHeight;
        rows = [
          ViewportRow(
            lineNumber: 0,
            visualLineIndex: 0,
            startOffset: 0,
            endOffset: 0,
            top: 0,
            height: height,
            left: 0,
            width: 0,
          ),
        ];
      } else {
        height = painter.height;
        rows = [
          for (var index = 0; index < metrics.length; index++)
            _rowForMetric(index, metrics),
        ];
      }
    } catch (_) {
      painter.dispose();
      rethrow;
    }
  }

  final String content;
  final List<TextSpan>? spans;
  final TextPainter painter;
  late final double height;
  late final List<ViewportRow> rows;
  int references = 0;

  ViewportRow _rowForMetric(int index, List<ui.LineMetrics> metrics) {
    final localTop = index == 0
        ? 0.0
        : metrics[index].baseline - metrics[index].ascent;
    final localBottom = index + 1 == metrics.length
        ? painter.height
        : metrics[index + 1].baseline - metrics[index + 1].ascent;
    final localMiddle = (localTop + localBottom) / 2;
    final boundary = painter.getLineBoundary(
      painter.getPositionForOffset(Offset(0, localMiddle)),
    );
    return ViewportRow(
      lineNumber: 0,
      visualLineIndex: index,
      startOffset: boundary.start,
      endOffset: boundary.end,
      top: localTop,
      height: localBottom - localTop,
      left: metrics[index].left,
      width: metrics[index].width,
    );
  }
}
