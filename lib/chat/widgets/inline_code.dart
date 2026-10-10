import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../theme/app_theme.dart';

/// Inline code: its text, on `textPreformat.background` painted by the
/// [InlineCodeText] it is in.
class InlineCodeSpan extends TextSpan {
  const InlineCodeSpan({
    super.text,
    super.style,
    super.children,
    super.recognizer,
    super.mouseCursor,
  });
}

/// [span] as [Text.rich] does, its [InlineCodeSpan]s on their background.
///
/// Not the text's own `backgroundColor`: a paragraph paints the selection
/// under its text, and that background with the text, over the selection:
/// opaque (Dark Modern's), it hid a selected code's highlight. Painted here
/// before the paragraph, the background is under the selection instead, in
/// every theme.
class InlineCodeText extends StatelessWidget {
  const InlineCodeText(this.span, {super.key});

  final InlineSpan span;

  @override
  Widget build(BuildContext context) => _InlineCodeBackdrop(
    color: AppColors.inlineCodeBackground,
    child: Text.rich(span),
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
  static List<TextSelection> codeRanges(InlineSpan span) {
    final ranges = <TextSelection>[];
    var at = 0;
    void walk(InlineSpan span) {
      switch (span) {
        case TextSpan(:final text, :final children):
          final start = at;
          at += text?.length ?? 0;
          children?.forEach(walk);
          if (span is InlineCodeSpan && at > start) {
            ranges.add(TextSelection(baseOffset: start, extentOffset: at));
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

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_paragraph case final paragraph? when _color.a > 0) {
      final ranges = codeRanges(paragraph.text);
      if (ranges.isNotEmpty) {
        final transform = paragraph.getTransformTo(this);
        final paint = Paint()..color = _color;
        final text = paragraph.text.toPlainText(includeSemanticsLabels: false);
        for (final range in ranges) {
          // A line may break after the code's leading space: that space alone
          // at the end of the line above is no code, so it gets no background.
          final lines = [
            for (final box in paragraph.getBoxesForSelection(
              _trimmed(text, range),
            ))
              box.toRect(),
          ];
          bool onCodeLine(Rect rect) => lines.any(
            (line) => line.top < rect.bottom && rect.top < line.bottom,
          );
          for (final box in paragraph.getBoxesForSelection(range)) {
            if (!onCodeLine(box.toRect())) continue;
            final rect = MatrixUtils.transformRect(transform, box.toRect());
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
