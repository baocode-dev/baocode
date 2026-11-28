import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';
import '../chat_find.dart' show ChatFindMarks;

/// Inline code (or another inline highlight such as `<mark>`): its text, on
/// `textPreformat.background` (or [background]) painted by the
/// [InlineCodeText] it is in.
class InlineCodeSpan extends TextSpan {
  const InlineCodeSpan({
    super.text,
    super.style,
    super.children,
    super.recognizer,
    super.mouseCursor,
    this.background,
    this.horizontalPadding = 0,
  });

  /// Overrides [InlineCodeText]'s default code background when non-null.
  final Color? background;

  /// Extra horizontal backdrop padding on each side, for highlights without
  /// space padding (such as `<mark>`).
  final double horizontalPadding;
}

/// [span] as [Text.rich] does, its [InlineCodeSpan]s on their background.
///
/// Not the text's own `backgroundColor`: a paragraph paints the selection
/// under its text, and that background with the text, over the selection:
/// opaque (Dark Modern's), it hid a selected code's highlight. Painted here
/// before the paragraph, the background is under the selection instead, in
/// every theme.
class InlineCodeText extends StatelessWidget {
  const InlineCodeText(this.span, {super.key, this.maxLines});

  final InlineSpan span;

  /// Cut to as many lines, an ellipsis at the end; all of it when null.
  final int? maxLines;

  @override
  Widget build(BuildContext context) => _InlineCodeBackdrop(
    color: AppColors.inlineCodeBackground,
    child: ChatFindMarks(
      child: Text.rich(
        span,
        maxLines: maxLines,
        overflow: maxLines == null ? null : TextOverflow.ellipsis,
      ),
    ),
  );
}

class _InlineCodeBackdrop extends SingleChildRenderObjectWidget {
  const _InlineCodeBackdrop({required this.color, required super.child});

  final Color color;

  @override
  RenderInlineCodeBackdrop createRenderObject(BuildContext context) =>
      RenderInlineCodeBackdrop(color);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderInlineCodeBackdrop renderObject,
  ) => renderObject.color = color;
}

/// Paints, under its child, the background of each [InlineCodeSpan] of
/// the paragraph in it.
class RenderInlineCodeBackdrop extends RenderProxyBox {
  RenderInlineCodeBackdrop(this._color);

  static const radius = Radius.circular(3);

  Color get color => _color;
  Color _color;
  set color(Color value) {
    if (value == _color) return;
    _color = value;
    markNeedsPaint();
  }

  /// The paragraph within: [Text] may put a mouse region around it.
  RenderParagraph? get _paragraph {
    RenderObject? node = child;
    while (node != null && node is! RenderParagraph) {
      RenderObject? only;
      node.visitChildren((c) => only ??= c);
      node = only;
    }
    return node as RenderParagraph?;
  }

  /// Where in [span]'s text each [InlineCodeSpan] is.
  static List<TextSelection> codeRanges(InlineSpan span) => [
    for (final entry in _backdropRanges(span)) entry.range,
  ];

  static List<
    ({TextSelection range, Color? color, double horizontalPadding})
  >
  _backdropRanges(InlineSpan span) {
    final ranges =
        <({TextSelection range, Color? color, double horizontalPadding})>[];
    var at = 0;
    void walk(InlineSpan span) {
      switch (span) {
        case TextSpan(:final text, :final children):
          final start = at;
          final slot = span is InlineCodeSpan ? ranges.length : -1;
          if (span is InlineCodeSpan) {
            ranges.add((
              range: const TextSelection.collapsed(offset: 0),
              color: span.background,
              horizontalPadding: span.horizontalPadding,
            ));
          }
          at += text?.length ?? 0;
          children?.forEach(walk);
          if (slot != -1) {
            if (at > start) {
              ranges[slot] = (
                range: TextSelection(baseOffset: start, extentOffset: at),
                color: ranges[slot].color,
                horizontalPadding: ranges[slot].horizontalPadding,
              );
            } else {
              ranges.removeAt(slot);
            }
          }
        case PlaceholderSpan():
          // Its object replacement character.
          at += 1;
      }
    }

    walk(span);
    return ranges;
  }

  /// [range] without the spaces that pad it at either end.
  static TextSelection _trimmed(String text, TextSelection range) {
    var start = range.start;
    var end = range.end;
    while (start < end && text[start] == ' ') {
      start++;
    }
    while (end > start && text[end - 1] == ' ') {
      end--;
    }
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  /// Whether [a] and [b] lie on the same line: their vertical overlap covers
  /// more than half of the shorter box, so touching lines with tall fallback
  /// glyphs stay separate.
  static bool _sameLine(Rect a, Rect b) {
    final overlap =
        (a.bottom < b.bottom ? a.bottom : b.bottom) -
        (a.top > b.top ? a.top : b.top);
    if (overlap <= 0) return false;
    final shorter = a.height < b.height ? a.height : b.height;
    return overlap > shorter * 0.5;
  }

  /// Merges [rects] on the same line (such as runs split across monospace and
  /// CJK fallback fonts, or an inline icon) into one bounding box per line.
  @visibleForTesting
  static List<Rect> mergeLineRects(Iterable<Rect> rects) {
    final merged = <Rect>[];
    for (final rect in rects) {
      if (rect.isEmpty) continue;
      final index = merged.indexWhere((line) => _sameLine(line, rect));
      if (index == -1) {
        merged.add(rect);
      } else {
        merged[index] = merged[index].expandToInclude(rect);
      }
    }
    return merged;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_paragraph case final paragraph?) {
      final ranges = _backdropRanges(paragraph.text);
      if (ranges.isNotEmpty) {
        final transform = paragraph.getTransformTo(this);
        final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        for (final entry in ranges) {
          final color = entry.color ?? _color;
          if (color.a <= 0) continue;
          final paint = Paint()..color = color;
          final range = entry.range;
          // A line may break after the code's leading space: that space alone
          // at the end of the line above is no code, so it gets no background.
          final lines = [
            for (final box in paragraph.getBoxesForSelection(
              _trimmed(text, range),
            ))
              box.toRect(),
          ];
          bool onCodeLine(Rect rect) =>
              lines.any((line) => _sameLine(line, rect));
          final boxes = [
            for (final box in paragraph.getBoxesForSelection(range))
              if (onCodeLine(box.toRect())) box.toRect(),
          ];
          final pad = entry.horizontalPadding;
          for (final box in mergeLineRects(boxes)) {
            var rect = MatrixUtils.transformRect(transform, box);
            if (pad > 0) {
              rect = Rect.fromLTRB(
                rect.left - pad,
                rect.top,
                rect.right + pad,
                rect.bottom,
              );
            }
            context.canvas.drawRRect(
              RRect.fromRectAndRadius(rect.shift(offset), radius),
              paint,
            );
          }
        }
      }
    }
    super.paint(context, offset);
  }
}
