import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show SizedBox, WidgetSpan;

import '../vs/editor/common/core/cursor_columns.dart';
import '../vs/editor/common/core/range.dart';
import 'document_snapshot.dart';
import 'editor_decorations.dart';

/// A text style a decoration lays over line-relative UTF-16 offsets
/// `[start, end)` (Monaco's `inlineClassName`): merged over the token style,
/// with [opacity] multiplied into the resulting colors.
@immutable
class ViewportInlineStyle {
  const ViewportInlineStyle(this.start, this.end, {this.style, this.opacity});

  final int start;
  final int end;
  final TextStyle? style;
  final double? opacity;

  @override
  bool operator ==(Object other) =>
      other is ViewportInlineStyle &&
      other.start == start &&
      other.end == end &&
      other.style == style &&
      other.opacity == opacity;

  @override
  int get hashCode => Object.hash(start, end, style, opacity);
}

/// Text injected at line-relative UTF-16 [offset] (Monaco's
/// `LineInjectedText`; see [EditorInjectedText]).
@immutable
class ViewportInjection {
  const ViewportInjection(this.offset, this.text);

  final int offset;
  final EditorInjectedText text;

  @override
  bool operator ==(Object other) =>
      other is ViewportInjection &&
      other.offset == offset &&
      other.text == text;

  @override
  int get hashCode => Object.hash(offset, text);
}

/// What decorations change in how one line is shaped: inline styles and
/// injected text ([injections] sorted by offset, in their order at one
/// offset, as `LineInjectedText.fromDecorations` sorts them).
@immutable
class ViewportLineDecorations {
  const ViewportLineDecorations({
    this.styles = const [],
    this.injections = const [],
  });

  static const none = ViewportLineDecorations();

  /// What [decorations] change on one-based [lineNumber] of [snapshot]:
  /// their text styles over the line's part of their ranges, their
  /// `before` text at their start and `after` text at their end
  /// (`LineInjectedText.fromDecorations`: by column, then before ahead of
  /// after, then in decoration order). Looks up only the decorations
  /// touching the line.
  factory ViewportLineDecorations.of(
    EditorDecorationSet decorations,
    DocumentSnapshot snapshot,
    int lineNumber,
  ) {
    final lineStart = snapshot.lineStarts[lineNumber - 1];
    final lineEnd = snapshot.contentEnds[lineNumber - 1];
    List<ViewportInlineStyle>? styles;
    List<(int, int, ViewportInjection)>? injections;
    var order = 0;
    for (final decoration in decorations.intersecting(lineStart, lineEnd)) {
      if (!decoration.affectsLayout) continue;
      if (decoration.textStyle != null || decoration.opacity != null) {
        final start = math.max(decoration.start, lineStart) - lineStart;
        final end = math.min(decoration.end, lineEnd) - lineStart;
        if (end > start) {
          (styles ??= []).add(
            ViewportInlineStyle(
              start,
              end,
              style: decoration.textStyle,
              opacity: decoration.opacity,
            ),
          );
        }
      }
      // A whole-line decoration's content goes at the start of its first
      // line and the end of its last (`_getOrCreateViewModelDecoration`).
      final wholeLine = decoration.isWholeLine;
      if (decoration.before case final before?
          when decoration.start >= lineStart && decoration.start <= lineEnd) {
        (injections ??= []).add((
          0,
          order++,
          ViewportInjection(wholeLine ? 0 : decoration.start - lineStart, before),
        ));
      }
      if (decoration.after case final after?
          when decoration.end >= lineStart && decoration.end <= lineEnd) {
        (injections ??= []).add((
          1,
          order++,
          ViewportInjection(
            wholeLine ? lineEnd - lineStart : decoration.end - lineStart,
            after,
          ),
        ));
      }
    }
    if (styles == null && injections == null) return none;
    injections?.sort((a, b) {
      final byOffset = a.$3.offset.compareTo(b.$3.offset);
      if (byOffset != 0) return byOffset;
      final bySide = a.$1.compareTo(b.$1);
      return bySide != 0 ? bySide : a.$2.compareTo(b.$2);
    });
    return ViewportLineDecorations(
      styles: styles ?? const [],
      injections: [
        if (injections != null)
          for (final (_, _, injection) in injections) injection,
      ],
    );
  }

  final List<ViewportInlineStyle> styles;
  final List<ViewportInjection> injections;

  bool get isEmpty => styles.isEmpty && injections.isEmpty;
}

/// The [ViewportLineDecorations] of one-based [lineNumber]; asked once per
/// line a layout shapes.
typedef ViewportLineDecorator = ViewportLineDecorations Function(
  int lineNumber,
);

/// Injected text a point is over (see [ViewportLayout.injectionAt]).
typedef ViewportInjectionHit = ({
  int lineNumber,
  ViewportInjection injection,
  Rect rect,
});

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

/// Space between lines that belongs to no line: a Monaco view zone (a
/// whitespace of `LinesLayout`), [height] tall after model line
/// [afterLineNumber] (0: above the first line). One after a hidden line is
/// shown after the visible line above it.
@immutable
class ViewportZone {
  const ViewportZone(this.afterLineNumber, this.height);

  final int afterLineNumber;
  final double height;

  @override
  bool operator ==(Object other) =>
      other is ViewportZone &&
      other.afterLineNumber == afterLineNumber &&
      other.height == height;

  @override
  int get hashCode => Object.hash(afterLineNumber, height);
}

/// Inclusive start and exclusive end indices into [ViewportLayout.rows].
class VisibleRowRange {
  const VisibleRowRange(this.start, this.end);

  final int start;
  final int end;

  bool get isEmpty => start == end;
}

/// Sorted, merged model lines hidden from the view (e.g. collapsed folding
/// regions). Lines are one-based and inclusive. Line 1 is never hidden by
/// folding because a region's header line remains visible.
///
/// Maps model lines to view lines in O(log ranges), like the upstream
/// view-model line projection restricted to hidden areas (no wrapping).
class HiddenLineRanges {
  factory HiddenLineRanges(Iterable<(int, int)> ranges) {
    final sorted =
        ranges.where((range) => range.$1 >= 1 && range.$2 >= range.$1).toList()
          ..sort((a, b) => a.$1.compareTo(b.$1));
    final starts = <int>[];
    final ends = <int>[];
    for (final (start, end) in sorted) {
      if (ends.isNotEmpty && start <= ends.last + 1) {
        if (end > ends.last) ends[ends.length - 1] = end;
      } else {
        starts.add(start);
        ends.add(end);
      }
    }
    return HiddenLineRanges._(
      Int32List.fromList(starts),
      Int32List.fromList(ends),
    );
  }

  HiddenLineRanges._(this._starts, this._ends)
    : _before = Int32List(_starts.length + 1) {
    for (var i = 0; i < _starts.length; i++) {
      _before[i + 1] = _before[i] + _ends[i] - _starts[i] + 1;
    }
  }

  static final HiddenLineRanges none = HiddenLineRanges._(
    Int32List(0),
    Int32List(0),
  );

  final Int32List _starts;
  final Int32List _ends;

  /// `_before[k]` is the number of hidden lines in ranges `0..k-1`.
  final Int32List _before;

  bool get isEmpty => _starts.isEmpty;
  int get length => _starts.length;
  int get hiddenLineCount => _before[_starts.length];

  /// One-based inclusive range `index`.
  (int, int) operator [](int index) => (_starts[index], _ends[index]);

  Iterable<(int, int)> get ranges sync* {
    for (var i = 0; i < _starts.length; i++) {
      yield (_starts[i], _ends[i]);
    }
  }

  /// Number of ranges that start at or before [lineNumber].
  int _countStartingAtOrBefore(int lineNumber) {
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_starts[mid] <= lineNumber) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  bool isHidden(int lineNumber) {
    final count = _countStartingAtOrBefore(lineNumber);
    return count > 0 && lineNumber <= _ends[count - 1];
  }

  /// The hidden range containing [lineNumber], if any.
  (int, int)? rangeContaining(int lineNumber) {
    final count = _countStartingAtOrBefore(lineNumber);
    if (count > 0 && lineNumber <= _ends[count - 1]) {
      return (_starts[count - 1], _ends[count - 1]);
    }
    return null;
  }

  /// One-based view line of model [lineNumber]. A hidden line maps to the
  /// visible line above its range.
  int modelToView(int lineNumber) {
    final count = _countStartingAtOrBefore(lineNumber);
    if (count > 0 && lineNumber <= _ends[count - 1]) {
      return _starts[count - 1] - 1 - _before[count - 1];
    }
    return lineNumber - _before[count];
  }

  /// One-based model line of one-based [viewLine].
  int viewToModel(int viewLine) {
    // Range k first affects view line `_starts[k] - _before[k]`; these keys
    // strictly increase because merged ranges are separated by visible lines.
    var low = 0;
    var high = _starts.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_starts[mid] - _before[mid] <= viewLine) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return viewLine + _before[low];
  }

  int viewLineCount(int modelLineCount) =>
      math.max(1, modelLineCount - hiddenLineCount);

  /// Drops or truncates ranges past [lineCount]; returns this when unchanged.
  HiddenLineRanges clampTo(int lineCount) {
    if (_starts.isEmpty || _ends.last <= lineCount) return this;
    return HiddenLineRanges([
      for (var i = 0; i < _starts.length; i++)
        if (_starts[i] <= lineCount)
          (_starts[i], math.min(_ends[i], lineCount)),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is HiddenLineRanges &&
      listEquals(other._starts, _starts) &&
      listEquals(other._ends, _ends);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(_starts), Object.hashAll(_ends));
}

/// TextPainter-backed geometry for a document in a fixed-size viewport.
///
/// Like Monaco, every visual row has one fixed [lineHeight] (a forced strut
/// derived from [style]); tall fallback glyphs keep a shared baseline.
///
/// Unwrapped layouts are virtualized: construction is O(1) in the number of
/// lines, and only lines that are painted, hit-tested or otherwise queried
/// are shaped. Shaped paragraphs live in an LRU cache keyed by line text and
/// spans that [previousLayout] hands over to compatible successors, so edits
/// and scrolling reuse unchanged lines. [rows] is a lazy list; reading a
/// row's `left`/`width` shapes that line. Wrapped layouts remain eager and
/// exact because row counts depend on each line's shaped width.
///
/// [hiddenLines] removes model lines from the view (collapsed folds). Tabs use
/// Flutter's paragraph shaping (custom tab stops are not provided). Rects and
/// hit-test points are relative to the viewport's origin. Positions at a soft
/// wrap have downstream affinity unless specified otherwise. Call [dispose]
/// when finished.
///
/// [lineDecorations] gives each line's inline styles and injected text
/// (Monaco's `ModelLineProjectionData` with injections): an injection is one
/// placeholder in the paragraph, as wide as its box, so it takes room and
/// wraps with the text, while offsets the layout takes and gives stay
/// document offsets (`translateToInputOffset`/`translateToOutputPosition`).
class ViewportLayout {
  ViewportLayout({
    required this.snapshot,
    required this.style,
    required this.viewportSize,
    this.wrap = false,
    this.textDirection = TextDirection.ltr,
    this.textScaler = TextScaler.noScaling,
    this.styledLines,
    this.tabSize,
    this.stopRenderingLineAfter = defaultStopRenderingLineAfter,
    HiddenLineRanges? hiddenLines,
    this.zones = const [],
    this.lineDecorations,
    ViewportLayout? previousLayout,
    double horizontalScrollOffset = 0,
    double verticalScrollOffset = 0,
  }) : assert(viewportSize.width.isFinite && viewportSize.width >= 0),
       assert(viewportSize.height.isFinite && viewportSize.height >= 0),
       assert(!wrap || viewportSize.width > 0),
       hiddenLines = (hiddenLines ?? HiddenLineRanges.none).clampTo(
         snapshot.lineCount,
       ) {
    setScrollOffset(
      horizontal: horizontalScrollOffset,
      vertical: verticalScrollOffset,
    );
    final wrapWidth = wrap ? viewportSize.width : double.infinity;
    final previous = previousLayout;
    if (previous != null &&
        !previous._disposed &&
        previous.stopRenderingLineAfter == stopRenderingLineAfter &&
        previous._cache.isCompatible(
          style,
          wrapWidth,
          textDirection,
          textScaler,
          tabSize,
        )) {
      _cache = previous._cache;
    } else {
      _cache = _ShapeCache(
        style,
        wrapWidth,
        textDirection,
        textScaler,
        tabSize,
      );
    }
    _cache.layouts++;
    viewLineCount = this.hiddenLines.viewLineCount(snapshot.lineCount);
    _placeZones();
    try {
      if (wrap) {
        _layoutWrapped();
      } else {
        rows = _LazyRows(this);
        contentHeight =
            viewLineCount * lineHeight + _zoneSums[_zoneSums.length - 1];
        for (var i = 0; i < _zoneOrder.length; i++) {
          final zone = _zoneOrder[i];
          _zoneTops[zone] = _zoneViews[i] * lineHeight + _zoneSums[i];
        }
        // Shape what the first frame paints, so construction reports the
        // paragraphs a viewport needs (and scrolling reuses them).
        final range = visibleRowRange;
        for (var i = range.start; i < range.end; i++) {
          _shapeForLine(_modelLineOfView(i));
        }
      }
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  final DocumentSnapshot snapshot;
  final TextStyle style;
  final Size viewportSize;
  final bool wrap;
  final TextDirection textDirection;
  final TextScaler textScaler;

  /// Model lines hidden from the view, clamped to [snapshot].
  final HiddenLineRanges hiddenLines;

  /// Space between lines (view zones), in no particular order.
  final List<ViewportZone> zones;

  /// Each line's inline styles and injected text, if any.
  final ViewportLineDecorator? lineDecorations;

  // The zones by position: each one's index into [zones], the zero-based
  // view line it is above, and the heights of those before it.
  late final Int32List _zoneOrder;
  late final Int32List _zoneViews;
  late final Float64List _zoneSums;

  // Unscrolled tops, by index into [zones].
  late final Float64List _zoneTops = Float64List(zones.length);

  void _placeZones() {
    final count = zones.length;
    final order = List<int>.generate(count, (i) => i);
    int viewOf(int i) {
      final after = zones[i].afterLineNumber;
      if (after <= 0) return 0;
      return _viewLineOfModel(math.min(after, snapshot.lineCount) - 1) + 1;
    }

    final views = [for (var i = 0; i < count; i++) viewOf(i)];
    order.sort((a, b) {
      final byView = views[a].compareTo(views[b]);
      return byView != 0 ? byView : a.compareTo(b);
    });
    _zoneOrder = Int32List.fromList(order);
    _zoneViews = Int32List.fromList([for (final i in order) views[i]]);
    _zoneSums = Float64List(count + 1);
    for (var i = 0; i < count; i++) {
      _zoneSums[i + 1] = _zoneSums[i] + math.max(0.0, zones[order[i]].height);
    }
  }

  /// The heights of the zones above zero-based view line [view].
  double _zonesAbove(int view) {
    if (_zoneViews.isEmpty) return 0;
    var low = 0;
    var high = _zoneViews.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (_zoneViews[mid] <= view) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return _zoneSums[low];
  }

  /// Unscrolled top of zero-based view line [view] (unwrapped layouts).
  double _viewTop(int view) => view * lineHeight + _zonesAbove(view);

  /// Unscrolled top of [zones]`[index]`.
  double zoneTop(int index) => _zoneTops[index];

  /// The index into [zones] of the zone at unscrolled [y], if any.
  int? zoneAt(double y) {
    for (var i = 0; i < zones.length; i++) {
      final top = _zoneTops[i];
      if (y >= top && y < top + zones[i].height) return i;
    }
    return null;
  }

  /// Unscrolled top of [rows]`[index]`.
  double rowTop(int index) => wrap ? rows[index].top : _viewTop(index);

  /// When set, tabs advance to the next multiple of [tabSize] visible columns
  /// (Monaco renders a tab as that many spaces; full-width characters count
  /// two columns). Each tab becomes a one-code-unit placeholder, so UTF-16
  /// offsets are unchanged. When null, tabs use Flutter paragraph shaping.
  final int? tabSize;

  /// Monaco's `editor.stopRenderingLineAfter`: a line longer than this many
  /// UTF-16 units is shaped only that far, then ends in a "Show more (…)"
  /// pill; the rest is neither shaped nor painted, and offsets past it map
  /// to the pill's end. -1 renders every line in full.
  final int stopRenderingLineAfter;

  /// Monaco's default for [stopRenderingLineAfter].
  static const defaultStopRenderingLineAfter = 10000;

  /// `renderOverflowingCharCount`: "Show more (N chars)" under 1024, then
  /// KB and MB to one place.
  static String overflowLabel(int overflow) {
    final size = overflow < 1024
        ? '$overflow chars'
        : overflow < 1024 * 1024
        ? '${(overflow / 1024).toStringAsFixed(1)} KB'
        : '${(overflow / 1024 / 1024).toStringAsFixed(1)} MB';
    return 'Show more ($size)';
  }

  /// Optional one-based line runs. A run whose text differs from the line's
  /// exact raw text (for example stale tokens during an edit) is ignored and
  /// the line is painted plainly, so UTF-16 hit testing stays aligned.
  final Map<int, List<TextSpan>>? styledLines;

  late final _ShapeCache _cache;
  bool _disposed = false;

  /// Shapes referenced by this layout: model line index -> shape.
  final Map<int, _LineShape> _lineShapes = {};
  static const int _lineShapeLimit = 2048;

  // Wrapped layouts only: per view line.
  List<_LineShape> _viewShapes = const [];
  List<double> _viewTops = const [];

  int _shapedLineCount = 0;
  double _maxMeasuredWidth = 0;
  int? _longestLineLength;

  /// Number of distinct paragraphs this layout had to shape (during
  /// construction and lazily afterwards). Paragraphs reused from the shared
  /// cache are not counted, which verifies that edits and scrolling do not
  /// reshape unchanged lines.
  int get shapedLineCount => _shapedLineCount;

  /// Number of lines in the view (model lines minus hidden lines).
  late final int viewLineCount;

  /// Visual rows. Unwrapped rows are materialized lazily, one per view line.
  late final List<ViewportRow> rows;
  late final double contentHeight;
  double horizontalScrollOffset = 0;
  double verticalScrollOffset = 0;

  /// Fixed height of every visual row.
  double get lineHeight => _cache.lineHeight;

  /// Approximate advance of one character, measured once per typography.
  double get averageCharWidth => _cache.averageCharWidth;

  /// Advance of one space, measured once per typography.
  double get spaceWidth => _cache.spaceWidth;

  /// Scrollable content width: the widest shaped line seen by this layout, or
  /// an estimate from the longest line's length, whichever is larger. Only
  /// integers are scanned for the estimate (once per layout).
  double get contentWidth {
    if (wrap) return viewportSize.width;
    var longest = _longestLineLength;
    if (longest == null) {
      longest = 0;
      final starts = snapshot.lineStarts;
      final ends = snapshot.contentEnds;
      for (var i = 0; i < starts.length; i++) {
        final length = ends[i] - starts[i];
        if (length > longest!) longest = length;
      }
      if (stopRenderingLineAfter >= 0) {
        longest = math.min(longest!, stopRenderingLineAfter);
      }
      _longestLineLength = longest;
    }
    return math.max(_maxMeasuredWidth, longest! * averageCharWidth);
  }

  void _layoutWrapped() {
    final shapes = <_LineShape>[];
    final tops = <double>[];
    final built = <ViewportRow>[];
    var top = 0.0;
    var zone = 0;
    void placeZonesAbove(int view) {
      for (; zone < _zoneOrder.length && _zoneViews[zone] <= view; zone++) {
        _zoneTops[_zoneOrder[zone]] = top;
        top += _zoneSums[zone + 1] - _zoneSums[zone];
      }
    }

    for (var view = 0; view < viewLineCount; view++) {
      placeZonesAbove(view);
      final line = _modelLineOfView(view);
      final shape = _shapeForLine(line, retain: true);
      shapes.add(shape);
      tops.add(top);
      final start = snapshot.lineStarts[line];
      for (final row in shape.rows) {
        built.add(
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
    placeZonesAbove(viewLineCount);
    _viewShapes = shapes;
    _viewTops = tops;
    contentHeight = top;
    rows = List<ViewportRow>.unmodifiable(built);
  }

  /// Zero-based model line of zero-based [view] line.
  int _modelLineOfView(int view) =>
      hiddenLines.isEmpty ? view : hiddenLines.viewToModel(view + 1) - 1;

  /// Zero-based view line of zero-based model [line] (hidden -> header).
  int _viewLineOfModel(int line) =>
      hiddenLines.isEmpty ? line : hiddenLines.modelToView(line + 1) - 1;

  /// One-based model line shown on one-based [viewLine].
  int modelLineForViewLine(int viewLine) =>
      _modelLineOfView(viewLine.clamp(1, viewLineCount) - 1) + 1;

  /// One-based view line of one-based model [lineNumber].
  int viewLineForModelLine(int lineNumber) =>
      _viewLineOfModel(lineNumber.clamp(1, snapshot.lineCount) - 1) + 1;

  /// Unscrolled top of the (first row of the) one-based model [lineNumber].
  double lineTop(int lineNumber) {
    final view = _viewLineOfModel(lineNumber.clamp(1, snapshot.lineCount) - 1);
    return wrap ? _viewTops[view] : _viewTop(view);
  }

  /// Unscrolled height of all rows of the one-based model [lineNumber].
  double lineRowsHeight(int lineNumber) {
    if (!wrap) return lineHeight;
    final view = _viewLineOfModel(lineNumber.clamp(1, snapshot.lineCount) - 1);
    return _viewShapes[view].height;
  }

  _LineShape _shapeForLine(int line, {bool retain = false}) {
    final existing = _lineShapes[line];
    if (existing != null) return existing;
    final start = snapshot.lineStarts[line];
    final end = snapshot.contentEnds[line];
    final length = end - start;
    final rendered = renderedLength(line + 1);
    final content = snapshot.text.substring(start, start + rendered);
    var spans = styledLines?[line + 1];
    if (spans != null && !_spansMatch(spans, start, end)) spans = null;
    if (spans != null && rendered < length) spans = _truncate(spans, rendered);
    // Monaco counts the characters past the limit, not past the cut.
    final overflow = rendered < length ? length - stopRenderingLineAfter : 0;
    var injections = const <ViewportInjection>[];
    final decorations = lineDecorations?.call(line + 1);
    if (decorations != null && !decorations.isEmpty) {
      if (decorations.styles.isNotEmpty) {
        spans = _applyInlineStyles(
          spans ?? [TextSpan(text: content)],
          decorations.styles,
          content.length,
          style.color,
        );
      }
      injections = [
        for (final injection in decorations.injections)
          if (injection.offset >= 0 &&
              injection.offset <= rendered &&
              injection.text.text.isNotEmpty)
            injection,
      ];
    }
    var shape = _cache.lookup(content, spans, overflow, injections);
    if (shape == null) {
      shape = _LineShape(
        content: content,
        overflow: overflow,
        spans: spans == null ? null : List<TextSpan>.of(spans),
        injections: injections,
        style: style,
        wrapWidth: _cache.wrapWidth,
        textDirection: textDirection,
        textScaler: textScaler,
        strut: _cache.strut,
        lineHeight: _cache.lineHeight,
        tabSize: tabSize,
        spaceWidth: _cache.spaceWidth,
      );
      _cache.add(shape);
      _shapedLineCount++;
    }
    if (!retain && _lineShapes.length >= _lineShapeLimit) _releaseLineShapes();
    shape.references++;
    _lineShapes[line] = shape;
    if (!wrap && shape.width > _maxMeasuredWidth) {
      _maxMeasuredWidth = shape.width;
    }
    return shape;
  }

  bool _spansMatch(List<TextSpan> spans, int start, int end) {
    final text = snapshot.text;
    var at = start;
    for (final span in spans) {
      final part = span.toPlainText(includeSemanticsLabels: false);
      if (at + part.length > end || !text.startsWith(part, at)) return false;
      at += part.length;
    }
    return at == end;
  }

  /// The UTF-16 length of one-based [lineNumber] that is shaped and
  /// painted: all of it, or [stopRenderingLineAfter] units (one fewer
  /// rather than split a surrogate pair).
  int renderedLength(int lineNumber) {
    final line = lineNumber - 1;
    final start = snapshot.lineStarts[line];
    final length = snapshot.contentEnds[line] - start;
    final limit = stopRenderingLineAfter;
    if (limit < 0 || length <= limit) return length;
    if (limit > 0) {
      final last = snapshot.text.codeUnitAt(start + limit - 1);
      if (last >= 0xD800 && last <= 0xDBFF) return limit - 1;
    }
    return limit;
  }

  /// [spans] (covering [length] units) split at [styles]' boundaries, each
  /// piece's style merged with the styles over it in order (Monaco's
  /// `LineDecorationsNormalizer` over the token parts) and its colors faded
  /// by their opacities.
  static List<TextSpan> _applyInlineStyles(
    List<TextSpan> spans,
    List<ViewportInlineStyle> styles,
    int length,
    Color? baseColor,
  ) {
    final runs = <(int, int, TextStyle?)>[];
    var at = 0;
    void flatten(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) return;
      final own = span.style;
      final style = inherited == null ? own : inherited.merge(own);
      final text = span.text;
      if (text != null && text.isNotEmpty) {
        runs.add((at, at + text.length, style));
        at += text.length;
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        flatten(child, style);
      }
    }

    for (final span in spans) {
      flatten(span, null);
    }
    final cuts = <int>{0, length};
    for (final (start, end, _) in runs) {
      cuts
        ..add(start)
        ..add(end);
    }
    for (final s in styles) {
      cuts
        ..add(s.start.clamp(0, length))
        ..add(s.end.clamp(0, length));
    }
    final points = cuts.toList()..sort();
    final source = _plainText(spans);
    final result = <TextSpan>[];
    var runIndex = 0;
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i];
      final b = points[i + 1];
      if (a >= b || b > source.length) continue;
      while (runIndex < runs.length && runs[runIndex].$2 <= a) {
        runIndex++;
      }
      TextStyle? style = runIndex < runs.length && runs[runIndex].$1 <= a
          ? runs[runIndex].$3
          : null;
      var opacity = 1.0;
      var styled = false;
      for (final s in styles) {
        if (s.start <= a && s.end >= b) {
          if (s.style case final extra?) {
            style = style == null ? extra : style.merge(extra);
          }
          opacity *= s.opacity ?? 1;
          styled = true;
        }
      }
      if (styled && opacity < 1) {
        final color = style?.color ?? baseColor;
        style = (style ?? const TextStyle()).copyWith(
          color: color?.withValues(alpha: color.a * opacity),
          decorationColor: style?.decorationColor?.withValues(
            alpha: style.decorationColor!.a * opacity,
          ),
        );
      }
      result.add(TextSpan(text: source.substring(a, b), style: style));
    }
    return result;
  }

  static String _plainText(List<TextSpan> spans) {
    final buffer = StringBuffer();
    for (final span in spans) {
      buffer.write(span.toPlainText(includeSemanticsLabels: false));
    }
    return buffer.toString();
  }

  /// [spans] cut after [length] UTF-16 units of text.
  static List<TextSpan> _truncate(List<TextSpan> spans, int length) {
    final result = <TextSpan>[];
    var remaining = length;
    for (final span in spans) {
      if (remaining <= 0) break;
      final text = span.toPlainText(includeSemanticsLabels: false);
      if (text.length <= remaining) {
        result.add(span);
        remaining -= text.length;
      } else {
        result.add(
          TextSpan(text: text.substring(0, remaining), style: span.style),
        );
        remaining = 0;
      }
    }
    return result;
  }

  void _releaseLineShapes() {
    for (final shape in _lineShapes.values) {
      shape.release();
    }
    _lineShapes.clear();
  }

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

  /// Index of the first row whose bottom is strictly below unscrolled [y]
  /// ([rows].length past the last).
  int rowIndexAt(double y) => _rowIndexAt(y);

  /// Index of the first row whose bottom is strictly below document [y].
  int _rowIndexAt(double y) {
    if (!wrap && _zoneViews.isNotEmpty) {
      var low = 0;
      var high = viewLineCount;
      while (low < high) {
        final mid = (low + high) >> 1;
        if (_viewTop(mid) + lineHeight <= y) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return low;
    }
    if (!wrap) {
      final h = lineHeight;
      var index = (y / h).floor();
      // Correct floating-point rounding against the exact row tops `i * h`.
      if (index < 0) index = 0;
      while (index > 0 && index * h > y) {
        index--;
      }
      while ((index + 1) * h <= y) {
        index++;
      }
      return index;
    }
    var low = 0;
    var high = rows.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (rows[mid].top + rows[mid].height <= y) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  /// The rows intersecting the vertical viewport; offscreen space yields an
  /// empty range. A zero-height viewport contains no rows.
  VisibleRowRange get visibleRowRange {
    if (viewportSize.height == 0) return const VisibleRowRange(0, 0);
    final count = wrap ? rows.length : viewLineCount;
    final first = math.min(_rowIndexAt(verticalScrollOffset), count);
    final bottom = verticalScrollOffset + viewportSize.height;
    if (!wrap && _zoneViews.isNotEmpty) {
      var low = first;
      var high = count;
      while (low < high) {
        final mid = (low + high) >> 1;
        if (_viewTop(mid) < bottom) {
          low = mid + 1;
        } else {
          high = mid;
        }
      }
      return VisibleRowRange(first, low);
    }
    if (!wrap) {
      final h = lineHeight;
      var end = (bottom / h).ceil();
      while (end > first && (end - 1) * h >= bottom) {
        end--;
      }
      while (end < count && end * h < bottom) {
        end++;
      }
      return VisibleRowRange(first, end.clamp(first, count));
    }
    var low = first;
    var high = count;
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

  /// One-based model lines with at least one visible row, in view order.
  Iterable<int> get visibleLineNumbers sync* {
    final range = visibleRowRange;
    var previous = -1;
    for (var i = range.start; i < range.end; i++) {
      final line = wrap ? rows[i].lineNumber : _modelLineOfView(i) + 1;
      if (line == previous) continue;
      previous = line;
      yield line;
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
    final count = wrap ? rows.length : viewLineCount;
    final index = math.min(_rowIndexAt(documentY), count - 1);
    final line = wrap ? rows[index].lineNumber - 1 : _modelLineOfView(index);
    final top = wrap ? _viewTops[_viewLineOfModel(line)] : _viewTop(index);
    final shape = _shapeForLine(line);
    final localY = wrap
        ? documentY - top
        : (documentY - top).clamp(0.0, lineHeight - 0.01);
    final local = shape.painter.getPositionForOffset(
      Offset(point.dx + horizontalScrollOffset, localY),
    );
    // Not past the rendered text: the pill has no offsets of its own, and
    // injected text maps to the column it is at.
    final lineStart = snapshot.lineStarts[line];
    final column = math.min(
      shape.fromParagraph(local.offset),
      shape.content.length,
    );
    return (lineStart + column).clamp(lineStart, snapshot.contentEnds[line]);
  }

  /// The injected text at viewport [point], if any, with its box in
  /// viewport coordinates.
  ViewportInjectionHit? injectionAt(Offset point) {
    if (lineDecorations == null) return null;
    final documentY = point.dy + verticalScrollOffset;
    final count = wrap ? rows.length : viewLineCount;
    if (count == 0) return null;
    final index = _rowIndexAt(documentY);
    if (index >= count) return null;
    final line = wrap ? rows[index].lineNumber - 1 : _modelLineOfView(index);
    final shape = _shapeForLine(line);
    if (shape.injections.isEmpty) return null;
    final top = wrap ? _viewTops[_viewLineOfModel(line)] : _viewTop(index);
    final local = Offset(point.dx + horizontalScrollOffset, documentY - top);
    for (final (index, rect) in shape.injectionRects().indexed) {
      if (rect != null && rect.contains(local)) {
        return (
          lineNumber: line + 1,
          injection: shape.injections[index],
          rect: rect.shift(
            Offset(-horizontalScrollOffset, top - verticalScrollOffset),
          ),
        );
      }
    }
    return null;
  }

  /// The caret after the end of one-based [lineNumber] and the text
  /// injected there (and its "Show more" pill), where a fold's placeholder
  /// goes.
  Rect lineEndRect(int lineNumber) {
    final line = lineNumber.clamp(1, snapshot.lineCount) - 1;
    final shape = _shapeForLine(line);
    final textPosition = TextPosition(
      offset: shape.paragraphLength,
      affinity: TextAffinity.upstream,
    );
    final origin = shape.painter.getOffsetForCaret(textPosition, Rect.zero);
    final view = _viewLineOfModel(line);
    final top = wrap ? _viewTops[view] : _viewTop(view);
    return Rect.fromLTWH(
      origin.dx - horizontalScrollOffset,
      (wrap ? origin.dy : 0) + top - verticalScrollOffset,
      1,
      lineHeight,
    );
  }

  /// The un-clipped insertion caret, including offsets in CRLF (which map to
  /// the preceding line's end). [affinity] chooses the side of a soft wrap.
  /// An offset on a hidden line maps to the start of the visible line above.
  Rect caretRect(
    int offset, {
    TextAffinity affinity = TextAffinity.downstream,
  }) {
    final position = snapshot.positionAtOffset(offset);
    final line = position.lineNumber - 1;
    if (!hiddenLines.isEmpty && hiddenLines.isHidden(line + 1)) {
      final view = _viewLineOfModel(line);
      final top = wrap ? _viewTops[view] : _viewTop(view);
      return Rect.fromLTWH(
        -horizontalScrollOffset,
        top - verticalScrollOffset,
        1,
        lineHeight,
      );
    }
    var localOffset =
        snapshot.offsetAtPosition(position) - snapshot.lineStarts[line];
    final shape = _shapeForLine(line);
    final painter = shape.painter;
    // Past the rendered text, the caret is after the pill (Monaco's range
    // at the line's width).
    if (localOffset > shape.content.length) {
      localOffset = shape.overflow > 0
          ? shape.paragraphLength
          : shape.toParagraph(shape.content.length);
    } else {
      localOffset = shape.toParagraph(localOffset);
    }
    final textPosition = TextPosition(offset: localOffset, affinity: affinity);
    final origin = painter.getOffsetForCaret(textPosition, Rect.zero);
    final lineTopValue = wrap
        ? _viewTops[_viewLineOfModel(line)]
        : _viewTop(_viewLineOfModel(line));
    final height = wrap
        ? painter.getFullHeightForCaret(textPosition, Rect.zero)
        : lineHeight;
    return Rect.fromLTWH(
      origin.dx - horizontalScrollOffset,
      (wrap ? origin.dy : 0) + lineTopValue - verticalScrollOffset,
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
    return offsetRangeRects(
      snapshot.offsetAtPosition(normalized.getStartPosition()),
      snapshot.offsetAtPosition(normalized.getEndPosition()),
    );
  }

  /// Visible boxes for UTF-16 offsets `[start, end)` on visible lines, clipped
  /// to the viewport. With [markNewlines], each selected line break receives
  /// a one-pixel-wide end marker (like a selection).
  List<Rect> offsetRangeRects(int start, int end, {bool markNewlines = true}) {
    if (start >= end || viewportSize.isEmpty) return const [];
    final clip = Offset.zero & viewportSize;
    final results = <Rect>[];
    for (final lineNumber in visibleLineNumbers) {
      final line = lineNumber - 1;
      final lineStart = snapshot.lineStarts[line];
      final contentEnd = snapshot.contentEnds[line];
      if (end <= lineStart || start > contentEnd) continue;
      final rendered = renderedLength(lineNumber);
      final from = math.min(math.max(start, lineStart) - lineStart, rendered);
      final to = math.min(math.min(end, contentEnd) - lineStart, rendered);
      final top = lineTop(lineNumber);
      if (from < to) {
        final shape = _shapeForLine(line);
        for (final box in shape.painter.getBoxesForSelection(
          TextSelection(
            baseOffset: shape.toParagraph(from),
            extentOffset: shape.toParagraph(to),
          ),
          boxHeightStyle: ui.BoxHeightStyle.max,
        )) {
          var rect = box.toRect();
          if (!wrap) rect = Rect.fromLTRB(rect.left, 0, rect.right, lineHeight);
          _addClipped(
            results,
            rect.shift(
              Offset(-horizontalScrollOffset, top - verticalScrollOffset),
            ),
            clip,
          );
        }
      }
      if (markNewlines &&
          snapshot.newlineLengths[line] > 0 &&
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
  /// Lines cut at [stopRenderingLineAfter] end in a pill of
  /// [overflowBackground] saying "Show more (…)" in [overflowForeground]
  /// (`.mtkoverflow`: the button colors).
  void paintVisibleText(
    Canvas canvas, {
    Offset origin = Offset.zero,
    Color overflowBackground = const Color(0xFF297AA0),
    Color overflowForeground = const Color(0xFFFFFFFF),
  }) {
    canvas.save();
    canvas.clipRect(origin & viewportSize);
    for (final lineNumber in visibleLineNumbers) {
      final shape = _shapeForLine(lineNumber - 1);
      final at =
          origin +
          Offset(
            -horizontalScrollOffset,
            lineTop(lineNumber) - verticalScrollOffset,
          );
      shape.painter.paint(canvas, at);
      if (shape.injections.isNotEmpty) shape.paintInjections(canvas, at);
      if (shape.overflow > 0) {
        shape.paintOverflow(
          canvas,
          at,
          background: overflowBackground,
          foreground: overflowForeground,
        );
      }
    }
    canvas.restore();
  }

  /// The "Show more (…)" pill of one-based [lineNumber], unscrolled in
  /// content coordinates; null when the line is rendered in full.
  Rect? overflowRect(int lineNumber) {
    final line = lineNumber.clamp(1, snapshot.lineCount) - 1;
    if (renderedLength(line + 1) ==
        snapshot.contentEnds[line] - snapshot.lineStarts[line]) {
      return null;
    }
    final box = _shapeForLine(line).overflowBox;
    return box?.shift(Offset(0, lineTop(line + 1)));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _releaseLineShapes();
    _cache.release();
  }
}

class _LazyRows extends ListBase<ViewportRow> {
  _LazyRows(this._layout);

  final ViewportLayout _layout;

  @override
  int get length => _layout.viewLineCount;

  @override
  set length(int value) => throw UnsupportedError('Unmodifiable rows');

  @override
  ViewportRow operator [](int index) {
    RangeError.checkValidIndex(index, this);
    final layout = _layout;
    final line = layout._modelLineOfView(index);
    final shape = layout._shapeForLine(line);
    return ViewportRow(
      lineNumber: line + 1,
      visualLineIndex: 0,
      startOffset: layout.snapshot.lineStarts[line],
      endOffset: layout.snapshot.contentEnds[line],
      top: layout._viewTop(index),
      height: layout.lineHeight,
      left: shape.left,
      width: shape.width,
    );
  }

  @override
  void operator []=(int index, ViewportRow value) =>
      throw UnsupportedError('Unmodifiable rows');
}

/// LRU of shaped paragraphs for one typography, shared by successive layouts.
class _ShapeCache {
  _ShapeCache(
    this.style,
    this.wrapWidth,
    this.textDirection,
    this.textScaler,
    this.tabSize,
  ) : strut = StrutStyle.fromTextStyle(style, forceStrutHeight: true) {
    final template = TextPainter(
      text: TextSpan(text: 'abcdefghijklmnopqrstuvwxyz    ', style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      strutStyle: strut,
    )..layout();
    try {
      lineHeight = template.preferredLineHeight;
      averageCharWidth =
          template
              .getOffsetForCaret(const TextPosition(offset: 26), Rect.zero)
              .dx /
          26;
      spaceWidth =
          (template
                  .getOffsetForCaret(const TextPosition(offset: 30), Rect.zero)
                  .dx -
              template
                  .getOffsetForCaret(const TextPosition(offset: 26), Rect.zero)
                  .dx) /
          4;
    } finally {
      template.dispose();
    }
  }

  static const int capacity = 4096;

  final TextStyle style;
  final double wrapWidth;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final int? tabSize;
  final StrutStyle strut;
  late final double lineHeight;
  late final double averageCharWidth;
  late final double spaceWidth;

  /// Content -> shapes with different spans; iteration order is LRU.
  final LinkedHashMap<String, List<_LineShape>> _entries = LinkedHashMap();
  int _size = 0;
  int layouts = 0;

  bool isCompatible(
    TextStyle style,
    double wrapWidth,
    TextDirection textDirection,
    TextScaler textScaler,
    int? tabSize,
  ) =>
      this.tabSize == tabSize &&
      this.style == style &&
      this.wrapWidth == wrapWidth &&
      this.textDirection == textDirection &&
      this.textScaler == textScaler;

  _LineShape? lookup(
    String content,
    List<TextSpan>? spans,
    int overflow,
    List<ViewportInjection> injections,
  ) {
    final candidates = _entries.remove(content);
    if (candidates == null) return null;
    _entries[content] = candidates; // most recently used
    for (final candidate in candidates) {
      if (candidate.overflow == overflow &&
          listEquals(candidate.spans, spans) &&
          listEquals(candidate.injections, injections)) {
        return candidate;
      }
    }
    return null;
  }

  void add(_LineShape shape) {
    final candidates = _entries.remove(shape.content) ?? <_LineShape>[];
    candidates.add(shape);
    _entries[shape.content] = candidates;
    shape.references++;
    _size++;
    while (_size > capacity && _entries.length > 1) {
      final oldest = _entries.keys.first;
      final evicted = _entries.remove(oldest)!;
      for (final shape in evicted) {
        shape.release();
      }
      _size -= evicted.length;
    }
  }

  void release() {
    if (--layouts > 0) return;
    for (final shapes in _entries.values) {
      for (final shape in shapes) {
        shape.release();
      }
    }
    _entries.clear();
    _size = 0;
  }
}

/// Measured, document-position-independent paragraph geometry. Only identical
/// text, styled spans and injections can share it.
///
/// The paragraph holds one placeholder (U+FFFC, one UTF-16 unit) per tab
/// (with tab stops), per injected text and for the overflow pill. Tabs stand
/// for themselves, so a paragraph offset is the line offset plus the
/// injections before it ([toParagraph], [fromParagraph]).
class _LineShape {
  _LineShape({
    required this.content,
    required this.overflow,
    required this.spans,
    required this.injections,
    required TextStyle style,
    required double wrapWidth,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required StrutStyle strut,
    required double lineHeight,
    required int? tabSize,
    required double spaceWidth,
  }) : painter = TextPainter(
         textDirection: textDirection,
         textScaler: textScaler,
         strutStyle: strut,
       ) {
    try {
      if (overflow > 0) {
        _label = TextPainter(
          text: TextSpan(
            text: ViewportLayout.overflowLabel(overflow),
            style: style,
          ),
          textDirection: TextDirection.ltr,
          textScaler: textScaler,
        )..layout();
      }
      _boxes = [
        for (final injection in injections)
          _InjectionBox(injection.text, style, textScaler, spaceWidth),
      ];
      final dimensions = <PlaceholderDimensions>[];
      painter.text = _build(style, tabSize, spaceWidth, dimensions);
      if (dimensions.isNotEmpty) painter.setPlaceholderDimensions(dimensions);
      painter.layout(maxWidth: wrapWidth);
      if (content.isEmpty && injections.isEmpty) {
        height = lineHeight;
        left = 0;
        width = 0;
      } else {
        height = painter.height;
        final metrics = painter.computeLineMetrics();
        _metrics = metrics;
        left = metrics.isEmpty ? 0 : metrics.first.left;
        width = metrics.isEmpty ? painter.width : metrics.first.width;
      }
    } catch (_) {
      painter.dispose();
      _label?.dispose();
      for (final box in _boxes) {
        box.dispose();
      }
      rethrow;
    }
  }

  /// `.mtkoverflow`'s padding and border: 4px and 1px.
  static const _pillInset = 5.0;

  static const _placeholder = WidgetSpan(
    alignment: ui.PlaceholderAlignment.baseline,
    baseline: TextBaseline.alphabetic,
    child: SizedBox.shrink(),
  );

  static PlaceholderDimensions _dimensions(double width) =>
      PlaceholderDimensions(
        size: Size(width, 0),
        alignment: ui.PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        baselineOffset: 0,
      );

  /// Placeholder kinds in paragraph order: an index into [injections], or
  /// [_tabKind]/[_overflowKind].
  List<int> _kinds = const [];
  static const _tabKind = -1;
  static const _overflowKind = -2;

  /// The paragraph: [spans] (or [content]) with a placeholder for each tab,
  /// injection and the overflow pill, whose sizes go to [dimensions].
  InlineSpan _build(
    TextStyle style,
    int? tabSize,
    double spaceWidth,
    List<PlaceholderDimensions> dimensions,
  ) {
    final tabs = tabSize != null && content.contains('\t');
    if (!tabs && injections.isEmpty && overflow == 0) {
      return spans == null
          ? TextSpan(text: content, style: style)
          : TextSpan(style: style, children: spans);
    }
    final tabColumns = tabs ? _tabColumns(content, tabSize) : const <int>[];
    final runs = <(String, TextStyle?)>[];
    void flatten(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) return;
      final own = span.style;
      final merged = inherited == null ? own : inherited.merge(own);
      final text = span.text;
      if (text != null && text.isNotEmpty) runs.add((text, merged));
      for (final child in span.children ?? const <InlineSpan>[]) {
        flatten(child, merged);
      }
    }

    if (spans case final spans?) {
      for (final span in spans) {
        flatten(span, null);
      }
    } else if (content.isNotEmpty) {
      runs.add((content, null));
    }
    final kinds = <int>[];
    final children = <InlineSpan>[];
    var next = 0;
    var tab = 0;
    void inject(int offset) {
      while (next < injections.length && injections[next].offset == offset) {
        children.add(_placeholder);
        dimensions.add(_dimensions(_boxes[next].width));
        kinds.add(next);
        next++;
      }
    }

    var at = 0;
    for (final (text, runStyle) in runs) {
      var segmentStart = 0;
      void flush(int end) {
        if (end > segmentStart) {
          children.add(
            TextSpan(text: text.substring(segmentStart, end), style: runStyle),
          );
        }
        segmentStart = end;
      }

      for (var i = 0; i < text.length; i++) {
        if (next < injections.length && injections[next].offset == at + i) {
          flush(i);
          inject(at + i);
        }
        if (tabs && text.codeUnitAt(i) == 0x09) {
          flush(i);
          children.add(_placeholder);
          dimensions.add(_dimensions(tabColumns[tab++] * spaceWidth));
          kinds.add(_tabKind);
          segmentStart = i + 1;
        }
      }
      flush(text.length);
      at += text.length;
    }
    inject(content.length);
    if (overflow > 0) {
      children.add(_placeholder);
      dimensions.add(_dimensions(_label!.width + 2 * _pillInset));
      kinds.add(_overflowKind);
    }
    _kinds = kinds;
    return TextSpan(style: style, children: children);
  }

  /// Visible columns advanced by each tab of [content], like Monaco's
  /// renderLine (a tab reaches the next multiple of [tabSize]).
  static List<int> _tabColumns(String content, int tabSize) {
    final size = tabSize < 1 ? 1 : tabSize;
    final result = <int>[];
    var column = 0;
    var segmentStart = 0;
    for (var i = 0; i < content.length; i++) {
      if (content.codeUnitAt(i) != 0x09) continue;
      final segment = content.substring(segmentStart, i);
      column += CursorColumns.visibleColumnFromColumn(
        segment,
        segment.length + 1,
        size,
      );
      final advance = size - column % size;
      result.add(advance);
      column += advance;
      segmentStart = i + 1;
    }
    return result;
  }

  final String content;

  /// Characters past the render limit; 0 when rendered in full.
  final int overflow;
  final List<TextSpan>? spans;

  /// Injected text by line offset (see [ViewportLineDecorations]).
  final List<ViewportInjection> injections;
  List<_InjectionBox> _boxes = const [];
  final TextPainter painter;
  TextPainter? _label;
  Color? _labelColor;
  late final double height;

  /// The paragraph's length: the content, its injections and the pill.
  int get paragraphLength =>
      content.length + injections.length + (overflow > 0 ? 1 : 0);

  /// The paragraph offset of line offset [column] (at most the content's
  /// length): past the injections before it, and among those at it, at the
  /// first boundary a cursor stop allows (`InjectedTextCursorStops`; the
  /// leftmost when none does).
  int toParagraph(int column) {
    if (injections.isEmpty) return column;
    var before = 0;
    while (before < injections.length && injections[before].offset < column) {
      before++;
    }
    var end = before;
    while (end < injections.length && injections[end].offset == column) {
      end++;
    }
    return column + before + _caretStop(before, end);
  }

  int _caretStop(int from, int to) {
    if (from == to || injections[from].text.hasLeftCursorStop) return 0;
    for (var j = from + 1; j < to; j++) {
      if (injections[j - 1].text.hasRightCursorStop ||
          injections[j].text.hasLeftCursorStop) {
        return j - from;
      }
    }
    return injections[to - 1].text.hasRightCursorStop ? to - from : 0;
  }

  /// The line offset of paragraph offset [offset]: one within or around
  /// injected text is the column it is at (`translateToInputOffset`).
  int fromParagraph(int offset) {
    var count = 0;
    while (count < injections.length &&
        injections[count].offset + count < offset) {
      count++;
    }
    return offset - count;
  }

  /// Each injection's box in the paragraph (null when not laid out).
  List<Rect?> injectionRects() {
    final result = List<Rect?>.filled(injections.length, null);
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    for (var k = 0; k < boxes.length && k < _kinds.length; k++) {
      final kind = _kinds[k];
      if (kind >= 0) result[kind] = _boxes[kind].rect(boxes[k]);
    }
    return result;
  }

  void paintInjections(Canvas canvas, Offset at) {
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    for (var k = 0; k < boxes.length && k < _kinds.length; k++) {
      final kind = _kinds[k];
      if (kind >= 0) _boxes[kind].paint(canvas, at, boxes[k]);
    }
  }

  /// The pill's box in the paragraph (a row high), when [overflow].
  Rect? get overflowBox {
    if (overflow == 0) return null;
    final boxes = painter.inlinePlaceholderBoxes;
    if (boxes == null || boxes.isEmpty) return null;
    final box = boxes.last;
    final metrics = _metrics;
    final row = metrics.isEmpty ? null : metrics.last;
    final top = row == null ? 0.0 : row.baseline - row.ascent;
    final bottom = row == null ? height : row.baseline + row.descent;
    return Rect.fromLTRB(box.left, top, box.right, math.max(bottom, top + 1));
  }

  void paintOverflow(
    Canvas canvas,
    Offset at, {
    required Color background,
    required Color foreground,
  }) {
    final box = overflowBox;
    var label = _label;
    if (box == null || label == null) return;
    if (_labelColor != foreground) {
      final text = label.text! as TextSpan;
      label.text = TextSpan(
        text: text.text,
        style: text.style!.copyWith(color: foreground),
      );
      label.layout();
      _labelColor = foreground;
    }
    final rect = box.shift(at);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = background,
    );
    label.paint(
      canvas,
      Offset(
        rect.left + _pillInset,
        rect.top + (rect.height - label.height) / 2,
      ),
    );
  }

  /// First row's metrics (the only row when unwrapped).
  late final double left;
  late final double width;
  List<ui.LineMetrics> _metrics = const [];
  int references = 0;

  void release() {
    if (--references > 0) return;
    painter.dispose();
    _label?.dispose();
    for (final box in _boxes) {
      box.dispose();
    }
  }

  late final List<ViewportRow> rows =
      (content.isEmpty && injections.isEmpty) || _metrics.isEmpty
      ? [
          ViewportRow(
            lineNumber: 0,
            visualLineIndex: 0,
            startOffset: 0,
            endOffset: content.length,
            top: 0,
            height: height,
            left: 0,
            width: width,
          ),
        ]
      : [
          for (var index = 0; index < _metrics.length; index++)
            _rowForMetric(index, _metrics),
        ];

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
      startOffset: math.min(fromParagraph(boundary.start), content.length),
      endOffset: math.min(fromParagraph(boundary.end), content.length),
      top: localTop,
      height: localBottom - localTop,
      left: metrics[index].left,
      width: metrics[index].width,
    );
  }
}

/// The box of one injected text: its text shaped in the editor's font with
/// the injection's style, inside CSS margin, border and padding (`border`
/// makes `box-sizing: border-box`, as `collectBorderSettingsCSSText` does).
class _InjectionBox {
  _InjectionBox(
    EditorInjectedText injected,
    TextStyle editorStyle,
    TextScaler textScaler,
    double charWidth,
  ) : _injected = injected {
    final editorFontSize = editorStyle.fontSize ?? 14;
    final fontSize =
        injected.fontSize?.resolve(
          fontSize: editorFontSize,
          editorFontSize: editorFontSize,
          charWidth: charWidth,
          percentOf: editorFontSize,
        ) ??
        editorFontSize;
    double resolve(EditorCssLength length) => length.resolve(
      fontSize: fontSize,
      editorFontSize: editorFontSize,
      charWidth: charWidth,
    );
    var style = TextStyle(
      color: editorStyle.color,
      fontFamily: editorStyle.fontFamily,
      fontFamilyFallback: editorStyle.fontFamilyFallback,
      fontFeatures: editorStyle.fontFeatures,
      fontWeight: editorStyle.fontWeight,
      fontStyle: editorStyle.fontStyle,
      letterSpacing: editorStyle.letterSpacing,
      fontSize: fontSize,
    );
    if (injected.style case final own?) style = style.merge(own);
    if (injected.opacity < 1) {
      final color = style.color;
      style = style.copyWith(
        color: color?.withValues(alpha: color.a * injected.opacity),
      );
    }
    _text = TextPainter(
      text: TextSpan(text: injected.text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    _baseline = _text.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    _margin = injected.margin.resolve(
      fontSize: fontSize,
      editorFontSize: editorFontSize,
      charWidth: charWidth,
    );
    _padding = injected.padding.resolve(
      fontSize: fontSize,
      editorFontSize: editorFontSize,
      charWidth: charWidth,
    );
    _border =
        injected.borderColor == null ||
            injected.borderStyle == EditorBorderStyle.none
        ? 0.0
        : resolve(injected.borderWidth);
    _radius = resolve(injected.borderRadius);
    final chrome = _padding.horizontal + 2 * _border;
    _boxWidth = switch (injected.width) {
      null => _text.width + chrome,
      final width when _border > 0 => math.max(resolve(width), chrome),
      final width => resolve(width) + chrome,
    };
    _boxHeight = switch (injected.height) {
      null => null,
      final height when _border > 0 => resolve(height),
      final height => resolve(height) + _padding.vertical + 2 * _border,
    };
    width = math.max(0, _margin.left + _boxWidth + _margin.right);
  }

  final EditorInjectedText _injected;
  late final TextPainter _text;
  late final double _baseline;
  late final EdgeInsets _margin;
  late final EdgeInsets _padding;
  late final double _border;
  late final double _radius;
  late final double _boxWidth;
  late final double? _boxHeight;

  /// The placeholder's width: margin and box.
  late final double width;

  /// The border box at [placeholder] (a zero-height box on the baseline).
  Rect rect(TextBox placeholder) {
    final textTop = placeholder.top - _baseline;
    final top = textTop - _padding.top - _border;
    return Rect.fromLTWH(
      placeholder.left + _margin.left,
      top,
      _boxWidth,
      _boxHeight ?? _text.height + _padding.vertical + 2 * _border,
    );
  }

  void paint(Canvas canvas, Offset at, TextBox placeholder) {
    final box = rect(placeholder).shift(at);
    final injected = _injected;
    final rrect = RRect.fromRectAndRadius(box, Radius.circular(_radius));
    if (injected.backgroundColor case final background?) {
      var color = background;
      if (injected.opacity < 1) {
        color = color.withValues(alpha: color.a * injected.opacity);
      }
      canvas.drawRRect(rrect, Paint()..color = color);
    }
    if (_border > 0) {
      canvas.drawRRect(
        rrect.deflate(_border / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _border
          ..color = injected.borderColor!,
      );
    }
    final clip = injected.width != null || injected.height != null;
    if (clip) {
      canvas.save();
      canvas.clipRect(box);
    }
    _text.paint(
      canvas,
      Offset(
        box.left + _border + _padding.left,
        placeholder.top + at.dy - _baseline,
      ),
    );
    if (clip) canvas.restore();
  }

  void dispose() => _text.dispose();
}
