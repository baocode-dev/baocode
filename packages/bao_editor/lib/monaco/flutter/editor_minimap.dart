import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart';

import 'document_snapshot.dart';
import 'editor_decorations.dart';
import 'editor_view_theme.dart';
import 'viewport_layout.dart';

/// Vertical geometry of the minimap, after Monaco's `MinimapLayout`: the
/// minimap scrolls proportionally with the editor when its content is taller
/// than the minimap, and the slider covers the editor's visible lines.
class MinimapGeometry {
  const MinimapGeometry._({
    required this.scrollTop,
    required this.sliderTop,
    required this.sliderHeight,
    required this.pixelsPerScroll,
  });

  factory MinimapGeometry.compute({
    required double height,
    required double lineHeight,
    required double viewportHeight,
    required double scrollTop,
    required double scrollHeight,
  }) {
    final scale = MinimapCache.lineHeight / lineHeight;
    final total = scrollHeight * scale;
    final maxMinimapScroll = math.max(0.0, total - height);
    final maxScrollTop = math.max(0.0, scrollHeight - viewportHeight);
    final minimapScrollTop = maxScrollTop <= 0
        ? 0.0
        : scrollTop / maxScrollTop * maxMinimapScroll;
    return MinimapGeometry._(
      scrollTop: minimapScrollTop,
      sliderTop: scrollTop * scale - minimapScrollTop,
      sliderHeight: viewportHeight * scale,
      pixelsPerScroll:
          scale - (maxScrollTop <= 0 ? 0 : maxMinimapScroll / maxScrollTop),
    );
  }

  /// Minimap pixels scrolled out above its top.
  final double scrollTop;
  final double sliderTop;
  final double sliderHeight;

  /// Slider movement per editor scroll pixel (for dragging the slider).
  final double pixelsPerScroll;

  /// Editor scroll position that centers minimap position [y] (from the top
  /// of the minimap) in the viewport.
  double scrollForClick(double y, double lineHeight, double viewportHeight) {
    final viewLine = (y + scrollTop) / MinimapCache.lineHeight;
    return viewLine * lineHeight - viewportHeight / 2;
  }
}

class _Chunk {
  _Chunk(this.picture, this.content, this.spans, this.style);

  final ui.Picture picture;
  final String content;
  final List<List<TextSpan>?> spans;

  /// Hidden lines, colors and column settings the picture was recorded with.
  final Object style;
  DocumentSnapshot? snapshot;
  Map<int, List<TextSpan>>? styledLines;
}

/// Downscaled rendering of view lines, cached as one picture per
/// [chunkLines] view lines. A chunk is re-recorded only when it is painted
/// and its text, spans, or colors changed, so typing re-records at most the
/// visible chunks that contain edited lines.
class MinimapCache {
  static const int chunkLines = 128;
  static const double lineHeight = 2;
  static const double charWidth = 1;

  final Map<int, _Chunk> _chunks = {};

  void _paintChunk(
    Canvas canvas,
    ViewportLayout layout,
    int index,
    Map<int, List<TextSpan>>? styledLines,
    Color foreground,
    int tabSize,
    int maxColumns,
  ) {
    final firstView = index * chunkLines;
    final lastView = math.min(firstView + chunkLines, layout.viewLineCount);
    if (firstView >= lastView) return;
    final snapshot = layout.snapshot;
    final style = (layout.hiddenLines, foreground, tabSize, maxColumns);
    var chunk = _chunks[index];
    if (chunk == null ||
        chunk.style != style ||
        !identical(chunk.snapshot, snapshot) ||
        !identical(chunk.styledLines, styledLines)) {
      final lines = [
        for (var view = firstView; view < lastView; view++)
          layout.modelLineForViewLine(view + 1),
      ];
      final content = layout.hiddenLines.isEmpty
          ? snapshot.text.substring(
              snapshot.lineStarts[lines.first - 1],
              snapshot.contentEnds[lines.last - 1],
            )
          : lines
                .map(
                  (line) => snapshot.text.substring(
                    snapshot.lineStarts[line - 1],
                    snapshot.contentEnds[line - 1],
                  ),
                )
                .join('\n');
      final spans = [for (final line in lines) styledLines?[line]];
      if (chunk == null ||
          chunk.style != style ||
          chunk.content != content ||
          !_sameSpans(chunk.spans, spans)) {
        chunk?.picture.dispose();
        final recorder = ui.PictureRecorder();
        final chunkCanvas = Canvas(recorder);
        final paint = Paint();
        for (var i = 0; i < lines.length; i++) {
          _paintLine(
            chunkCanvas,
            snapshot,
            lines[i],
            spans[i],
            i * lineHeight,
            foreground,
            tabSize,
            maxColumns,
            paint,
          );
        }
        chunk = _Chunk(recorder.endRecording(), content, spans, style);
        _chunks[index] = chunk;
      }
      chunk
        ..snapshot = snapshot
        ..styledLines = styledLines;
    }
    canvas.drawPicture(chunk.picture);
  }

  static bool _sameSpans(List<List<TextSpan>?> a, List<List<TextSpan>?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i]) && !listEquals(a[i], b[i])) return false;
    }
    return true;
  }

  static void _paintLine(
    Canvas canvas,
    DocumentSnapshot snapshot,
    int lineNumber,
    List<TextSpan>? spans,
    double y,
    Color foreground,
    int tabSize,
    int maxColumns,
    Paint paint,
  ) {
    final content = snapshot.text.substring(
      snapshot.lineStarts[lineNumber - 1],
      snapshot.contentEnds[lineNumber - 1],
    );
    if (content.isEmpty) return;
    final segments = <(String, Color)>[];
    if (spans != null) {
      void visit(InlineSpan span, Color color) {
        if (span is! TextSpan) return;
        final own = span.style?.color ?? color;
        final text = span.text;
        if (text != null && text.isNotEmpty) segments.add((text, own));
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child, own);
        }
      }

      for (final span in spans) {
        visit(span, foreground);
      }
      var length = 0;
      for (final (text, _) in segments) {
        length += text.length;
      }
      if (length != content.length) {
        segments
          ..clear()
          ..add((content, foreground));
      }
    } else {
      segments.add((content, foreground));
    }
    var column = 0;
    for (final (text, color) in segments) {
      paint.color = color.withValues(alpha: color.a * 0.6);
      var runStart = -1;
      void flush() {
        if (runStart >= 0 && column > runStart) {
          canvas.drawRect(
            Rect.fromLTWH(
              runStart * charWidth,
              y,
              (math.min(column, maxColumns) - runStart) * charWidth,
              lineHeight - 0.5,
            ),
            paint,
          );
        }
        runStart = -1;
      }

      for (var i = 0; i < text.length && column < maxColumns; i++) {
        final unit = text.codeUnitAt(i);
        if (unit == 0x09) {
          flush();
          column += tabSize - column % tabSize;
        } else if (unit <= 0x20) {
          flush();
          column++;
        } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
          continue; // low surrogate: same column as its pair
        } else {
          if (runStart < 0) runStart = column;
          column++;
        }
      }
      flush();
      if (column >= maxColumns) break;
    }
  }

  /// Drops pictures far from the painted chunks once the cache grows large.
  void _evictFar(int firstChunk, int lastChunk) {
    if (_chunks.length <= 64) return;
    _chunks.removeWhere((index, chunk) {
      final far = index < firstChunk - 16 || index > lastChunk + 16;
      if (far) chunk.picture.dispose();
      return far;
    });
  }

  void dispose() {
    for (final chunk in _chunks.values) {
      chunk.picture.dispose();
    }
    _chunks.clear();
  }
}

/// Paints the minimap: cached line chunks, selection and decoration marks,
/// and the visible-region slider (on hover or while dragging).
class EditorMinimapPainter extends CustomPainter {
  EditorMinimapPainter({
    required this.cache,
    required this.layout,
    required this.rect,
    required this.geometry,
    required this.styledLines,
    required this.foreground,
    required this.background,
    required this.theme,
    required this.tabSize,
    required this.selections,
    required this.decorations,
    required this.showSlider,
    required this.sliderActive,
  });

  final MinimapCache cache;
  final ViewportLayout layout;
  final Rect rect;
  final MinimapGeometry geometry;
  final Map<int, List<TextSpan>>? styledLines;
  final Color foreground;
  final Color background;
  final EditorViewTheme theme;
  final int tabSize;
  final List<TextSelection> selections;
  final EditorDecorationSet decorations;
  final bool showSlider;
  final bool sliderActive;

  @override
  void paint(Canvas canvas, Size size) {
    if (rect.isEmpty) return;
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(
      rect,
      Paint()..color = theme.minimapBackground ?? background,
    );
    canvas.translate(rect.left + 2, rect.top - geometry.scrollTop);
    final firstView = (geometry.scrollTop / MinimapCache.lineHeight).floor();
    final lastView = math.min(
      layout.viewLineCount,
      ((geometry.scrollTop + rect.height) / MinimapCache.lineHeight).ceil(),
    );
    final maxColumns = ((rect.width - 4) / MinimapCache.charWidth).floor();
    // Marks behind text: selections and decorations on visible minimap lines.
    if (lastView > firstView) {
      final snapshot = layout.snapshot;
      final firstLine = layout.modelLineForViewLine(firstView + 1);
      final lastLine = layout.modelLineForViewLine(lastView);
      final start = snapshot.lineStarts[firstLine - 1];
      final end = snapshot.contentEnds[lastLine - 1];
      final paint = Paint();
      void mark(int from, int to, Color color) {
        if (to < start || from > end) return;
        final a = snapshot.positionAtOffset(math.max(from, start)).lineNumber;
        final b = snapshot.positionAtOffset(math.min(to, end)).lineNumber;
        paint.color = color;
        for (var line = a; line <= b; line++) {
          if (layout.hiddenLines.isHidden(line)) continue;
          final view = layout.viewLineForModelLine(line) - 1;
          canvas.drawRect(
            Rect.fromLTWH(
              -2,
              view * MinimapCache.lineHeight,
              rect.width,
              MinimapCache.lineHeight,
            ),
            paint,
          );
        }
      }

      for (final decoration in decorations.intersecting(start, end)) {
        final color = decoration.resolvedMinimap(theme);
        if (color != null) mark(decoration.start, decoration.end, color);
      }
      for (final selection in selections) {
        if (selection.isValid && !selection.isCollapsed) {
          mark(selection.start, selection.end, theme.minimapSelectionHighlight);
        }
      }
    }
    final firstChunk = firstView ~/ MinimapCache.chunkLines;
    final lastChunk = (math.max(lastView - 1, 0)) ~/ MinimapCache.chunkLines;
    for (var chunk = firstChunk; chunk <= lastChunk; chunk++) {
      canvas.save();
      canvas.translate(
        0,
        chunk * MinimapCache.chunkLines * MinimapCache.lineHeight,
      );
      cache._paintChunk(
        canvas,
        layout,
        chunk,
        styledLines,
        foreground,
        tabSize,
        maxColumns,
      );
      canvas.restore();
    }
    cache._evictFar(firstChunk, lastChunk);
    canvas.restore();
    if (showSlider || sliderActive) {
      canvas.drawRect(
        Rect.fromLTWH(
          rect.left,
          rect.top + geometry.sliderTop,
          rect.width,
          geometry.sliderHeight,
        ).intersect(rect),
        Paint()
          ..color = sliderActive
              ? theme.minimapSliderActiveBackground
              : theme.minimapSliderHoverBackground,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EditorMinimapPainter old) =>
      old.layout != layout ||
      old.rect != rect ||
      old.geometry.scrollTop != geometry.scrollTop ||
      old.geometry.sliderTop != geometry.sliderTop ||
      old.geometry.sliderHeight != geometry.sliderHeight ||
      !identical(old.styledLines, styledLines) ||
      old.foreground != foreground ||
      old.background != background ||
      old.theme != theme ||
      old.tabSize != tabSize ||
      !listEquals(old.selections, selections) ||
      old.decorations != decorations ||
      old.showSlider != showSlider ||
      old.sliderActive != sliderActive;
}
