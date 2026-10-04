// A unit's text as the live preview draws it, Typora's way: the inline
// elements styled (bold, links, code), their marks (`**`, `](url)`) hidden
// until the caret comes to them, and images and TeX shown in place of
// their source. A hidden mark is still there, its characters drawn at no
// size, so the caret and the pointer go through the text as it is.

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'markdown_inline.dart';

/// How a unit's text is drawn.
enum MarkdownTextKind {
  /// Inline markdown: a paragraph's, a heading's, a cell's.
  inline,

  /// Code, colored by its language when it can be.
  code,

  /// As it is written (HTML, link definitions, TeX).
  plain,
}

/// Marks hidden: there, at no size.
const _hidden = TextStyle(fontSize: 0, color: Color(0x00000000));

/// [text]'s spans (see the file's comment), on [style]. Elements touching
/// [reveal] (the selection; none when null) show their marks. [composing]
/// is underlined, as an input method composes it.
TextSpan markdownLiveSpan({
  required String text,
  required TextStyle style,
  MarkdownTextKind kind = MarkdownTextKind.inline,
  List<MarkdownInline> inlines = const [],
  TextRange? reveal,
  TextRange composing = TextRange.empty,
  List<List<TextSpan>>? colors,
  Widget Function(MarkdownInline image, String alt)? image,
  Widget Function(String tex)? math,
}) {
  final pieces = <_Piece>[];
  switch (kind) {
    case MarkdownTextKind.inline:
      _Inlines(
        text,
        pieces,
        reveal: reveal,
        image: image,
        math: math,
      ).walk(0, text.length, inlines, const TextStyle());
    case MarkdownTextKind.code:
      _code(text, pieces, colors);
    case MarkdownTextKind.plain:
      if (text.isNotEmpty) {
        pieces.add(_Piece(0, text.length, const TextStyle()));
      }
  }
  final underline = composing.isValid && !composing.isCollapsed;
  return TextSpan(
    style: style,
    children: [
      for (final piece in pieces)
        for (final part in underline ? piece.split(composing) : [piece])
          if (part.widget case final widget?)
            WidgetSpan(alignment: PlaceholderAlignment.middle, child: widget)
          else
            TextSpan(
              text: text.substring(part.start, part.end),
              style:
                  underline &&
                      part.start >= composing.start &&
                      part.end <= composing.end
                  ? part.style.copyWith(decoration: TextDecoration.underline)
                  : part.style,
            ),
    ],
  );
}

/// [start, end) of the text drawn in [style], or as [widget] (one
/// character standing for it).
class _Piece {
  _Piece(this.start, this.end, this.style, [this.widget]);

  final int start;
  final int end;
  final TextStyle style;
  final Widget? widget;

  /// It cut at [range]'s ends.
  List<_Piece> split(TextRange range) {
    if (widget != null || range.end <= start || range.start >= end) {
      return [this];
    }
    final cuts = [
      start,
      if (range.start > start) range.start,
      if (range.end < end) range.end,
      end,
    ];
    return [
      for (var i = 0; i + 1 < cuts.length; i++)
        _Piece(cuts[i], cuts[i + 1], style),
    ];
  }
}

void _code(String text, List<_Piece> pieces, List<List<TextSpan>>? colors) {
  if (text.isEmpty) return;
  final lines = text.split('\n');
  if (colors == null || colors.length < lines.length) {
    pieces.add(_Piece(0, text.length, const TextStyle()));
    return;
  }
  var at = 0;
  for (final (index, line) in lines.indexed) {
    var column = 0;
    for (final span in colors[index]) {
      final length = span.text?.length ?? 0;
      if (length == 0 || column + length > line.length) continue;
      pieces.add(
        _Piece(
          at + column,
          at + column + length,
          span.style ?? const TextStyle(),
        ),
      );
      column += length;
    }
    if (column < line.length) {
      pieces.add(_Piece(at + column, at + line.length, const TextStyle()));
    }
    if (index + 1 < lines.length) {
      pieces.add(
        _Piece(at + line.length, at + line.length + 1, const TextStyle()),
      );
    }
    at += line.length + 1;
  }
}

class _Inlines {
  _Inlines(
    this.text,
    this.pieces, {
    required this.reveal,
    required this.image,
    required this.math,
  });

  final String text;
  final List<_Piece> pieces;
  final TextRange? reveal;
  final Widget Function(MarkdownInline image, String alt)? image;
  final Widget Function(String tex)? math;

  static TextStyle get _marks => TextStyle(
    color: AppColors.textFaint,
    fontWeight: FontWeight.normal,
    fontStyle: FontStyle.normal,
    decoration: TextDecoration.none,
  );

  static TextStyle get _code => TextStyle(
    color: AppColors.inlineCode,
    fontFamily: AppFonts.mono,
    backgroundColor: AppColors.inlineCodeBackground.withValues(
      alpha: AppColors.inlineCodeBackground.a * 0.6,
    ),
  );

  void add(int start, int end, TextStyle style) {
    if (end > start) pieces.add(_Piece(start, end, style));
  }

  bool _revealed(MarkdownInline inline) {
    final reveal = this.reveal;
    return reveal != null &&
        reveal.isValid &&
        inline.start <= reveal.end &&
        reveal.start <= inline.end;
  }

  void walk(int start, int end, List<MarkdownInline> inlines, TextStyle style) {
    var at = start;
    for (final inline in inlines) {
      add(at, inline.start, style);
      _element(inline, style);
      at = inline.end;
    }
    add(at, end, style);
  }

  void _element(MarkdownInline inline, TextStyle style) {
    final revealed = _revealed(inline);
    final marks = revealed ? style.merge(_marks) : _hidden;
    void around(TextStyle content, {bool nested = true}) {
      add(inline.start, inline.contentStart, marks);
      if (nested) {
        walk(inline.contentStart, inline.contentEnd, inline.children, content);
      } else {
        add(inline.contentStart, inline.contentEnd, content);
      }
      add(inline.contentEnd, inline.end, marks);
    }

    /// The element as [widget], its source hidden.
    bool shown(Widget? widget) {
      if (revealed || widget == null || inline.end <= inline.start) {
        return false;
      }
      add(inline.start, inline.end - 1, _hidden);
      pieces.add(_Piece(inline.end - 1, inline.end, style, widget));
      return true;
    }

    switch (inline.kind) {
      case MarkdownInlineKind.strong:
        around(
          style.merge(
            TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        );
      case MarkdownInlineKind.emphasis:
        around(style.merge(const TextStyle(fontStyle: FontStyle.italic)));
      case MarkdownInlineKind.strike:
        around(
          style.merge(
            TextStyle(
              decoration: TextDecoration.lineThrough,
              color: AppColors.textMuted,
            ),
          ),
        );
      case MarkdownInlineKind.code:
        around(style.merge(_code), nested: false);
      case MarkdownInlineKind.link || MarkdownInlineKind.autolink:
        around(style.merge(TextStyle(color: AppColors.accent)));
      case MarkdownInlineKind.url:
        add(
          inline.start,
          inline.end,
          style.merge(TextStyle(color: AppColors.accent)),
        );
      case MarkdownInlineKind.image:
        final alt = text.substring(inline.contentStart, inline.contentEnd);
        if (!shown(image?.call(inline, alt))) {
          around(
            style.merge(
              TextStyle(
                color: AppColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
            nested: false,
          );
        }
      case MarkdownInlineKind.math:
        final tex = text.substring(inline.contentStart, inline.contentEnd);
        if (!shown(math?.call(tex))) {
          around(
            style.merge(
              TextStyle(color: AppColors.accent, fontFamily: AppFonts.mono),
            ),
            nested: false,
          );
        }
      case MarkdownInlineKind.html:
        add(
          inline.start,
          inline.end,
          style.merge(
            TextStyle(color: AppColors.textFaint, fontFamily: AppFonts.mono),
          ),
        );
      case MarkdownInlineKind.escape:
        add(inline.start, inline.contentStart, marks);
        add(inline.contentStart, inline.end, style);
    }
  }
}

/// A unit's text, its spans built by [spans] (see [markdownLiveSpan]).
class MarkdownUnitController extends TextEditingController {
  MarkdownUnitController({super.text});

  TextSpan Function(TextEditingValue value, TextStyle? style)? spans;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final spans = this.spans;
    if (spans == null) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return spans(
      withComposing ? value : value.copyWith(composing: TextRange.empty),
      style,
    );
  }
}
