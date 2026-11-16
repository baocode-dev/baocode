import 'package:flutter/painting.dart';

import '../md_blocks.dart';
import '../md_inline.dart';
import 'md_offsets.dart';
import 'md_style.dart';

/// Text on a ground of its own (code's, a color's). Not its style's
/// `backgroundColor`: a paragraph paints the selection under its text and
/// that background with the text, over the selection (an opaque one hid
/// it there); the line's box paints [ground] under the selection instead.
class MdGroundSpan extends TextSpan {
  const MdGroundSpan({super.text, super.style, required this.ground});

  final Color ground;

  @override
  RenderComparison compareTo(InlineSpan other) {
    final comparison = super.compareTo(other);
    if (comparison == RenderComparison.identical &&
        (other is! MdGroundSpan || other.ground != ground)) {
      return RenderComparison.paint;
    }
    return comparison;
  }

  @override
  bool operator ==(Object other) =>
      other is MdGroundSpan && other.ground == ground && super == other;

  @override
  int get hashCode => Object.hash(super.hashCode, ground);
}

/// What a line shows: its text's spans, and where its columns are in them.
class MdLineDisplay {
  const MdLineDisplay(this.span, this.offsets, {this.hasWidgets = false});

  final TextSpan span;
  final MdOffsets offsets;

  /// A widget shows in it (a picture, a formula, a chip), its line as high
  /// as it needs.
  final bool hasWidgets;

  /// Nothing of the line shows (a fence's, a table's line where the caret
  /// is not in it): only what lays its caret out.
  bool get isEmpty => offsets.pieces.every(
    (piece) =>
        piece.kind == MdPieceKind.extra || piece.shownEnd == piece.shownStart,
  );
}

/// The style of [info]'s line, before its runs' own.
TextStyle lineStyleOf(MdLineInfo info, MarkdownEditorStyle style) {
  var line = switch (info.kind) {
    MdLineKind.heading => style.heading(info.level),
    MdLineKind.fenceOpen ||
    MdLineKind.fence ||
    MdLineKind.fenceClose ||
    MdLineKind.indentedCode => style.text.merge(style.codeBlock),
    MdLineKind.tableHead ||
    MdLineKind.tableDelimiter ||
    MdLineKind.tableRow ||
    MdLineKind.mathOpen ||
    MdLineKind.math ||
    MdLineKind.mathClose ||
    MdLineKind.mathLine => style.text.merge(style.codeBlock),
    _ => style.text,
  };
  if (info.quoteDepth > 0) line = line.merge(style.quote);
  return line;
}

/// Whether the line is shown as its text (the rest is a box drawn for it,
/// or nothing) where the caret is not in its block.
bool showsText(MdLineInfo info) => switch (info.kind) {
  MdLineKind.fenceOpen ||
  MdLineKind.fenceClose ||
  MdLineKind.tableHead ||
  MdLineKind.tableDelimiter ||
  MdLineKind.tableRow ||
  MdLineKind.mathOpen ||
  MdLineKind.math ||
  MdLineKind.mathClose ||
  MdLineKind.mathLine ||
  MdLineKind.rule ||
  MdLineKind.setextUnderline => false,
  _ => true,
};

/// What line [text] (of [info], its runs [runs]) shows: the runs the
/// column [reveal] (the caret's, on the line) is in with their marks, the
/// rest without; a block's lines as written where [blockRevealed] (the
/// caret in the block), else what [showsText] says.
///
/// Runs [isAtomic] says are one thing show as [atomic] makes them; a code
/// line's text as [code] has it (its spans' text the line's, from
/// [MdLineInfo.contentStart]). Runs [revealed] says no to keep their
/// marks hidden, the caret in them or not.
MdLineDisplay buildLineDisplay(
  String text,
  MdLineInfo info,
  List<MdInline> runs, {
  required MarkdownEditorStyle style,
  TextStyle? lineStyle,
  int? reveal,
  bool blockRevealed = false,
  bool Function(MdInline run)? isAtomic,
  InlineSpan Function(MdInline run, TextStyle style)? atomic,
  List<InlineSpan>? code,
  bool Function(MdInline run)? revealed,
}) {
  final base = lineStyle ?? lineStyleOf(info, style);
  final builder = _Builder(
    text,
    style,
    reveal,
    isAtomic ?? (run) => run.atomic,
    atomic,
    grounds: true,
    revealed: revealed,
  );
  final length = text.length;
  final marks = base.copyWith(color: style.marks);
  switch (info.kind) {
    case MdLineKind.blank:
      final quoteEnd = info.quoteEnd.clamp(0, length);
      builder.hide(0, quoteEnd, MdPieceKind.closer);
      builder.show(quoteEnd, length, base);
    case MdLineKind.paragraph ||
        MdLineKind.heading ||
        MdLineKind.item ||
        MdLineKind.footnote:
      final atx = info.kind == MdLineKind.heading && !info.setext;
      if (atx && reveal != null) {
        builder.hide(0, info.quoteEnd, MdPieceKind.closer);
        builder.show(info.quoteEnd, info.contentStart, marks);
      } else {
        builder.hide(0, info.contentStart, MdPieceKind.closer);
      }
      builder.runs(info.contentStart, info.contentEnd, runs, base);
      if (atx && reveal != null) {
        builder.show(info.contentEnd, length, marks);
      } else {
        builder.hide(info.contentEnd, length, MdPieceKind.closer);
      }
    case MdLineKind.fence || MdLineKind.indentedCode:
      final start = info.contentStart.clamp(0, length);
      builder.hide(0, start, MdPieceKind.closer);
      if (code != null) {
        builder.spans(start, length, code);
      } else {
        builder.show(start, length, base);
      }
    case MdLineKind.html || MdLineKind.frontMatter || MdLineKind.definition:
      builder.show(0, length, marks);
    case MdLineKind.fenceOpen || MdLineKind.fenceClose:
      if (blockRevealed) {
        final start = info.contentStart.clamp(0, length);
        builder.hide(0, start, MdPieceKind.closer);
        builder.show(start, length, marks);
      } else {
        builder.hide(0, length, MdPieceKind.closer);
      }
    case MdLineKind.tableHead ||
        MdLineKind.tableDelimiter ||
        MdLineKind.tableRow ||
        MdLineKind.mathOpen ||
        MdLineKind.math ||
        MdLineKind.mathClose ||
        MdLineKind.mathLine:
      if (blockRevealed) {
        builder.show(0, length, base);
      } else {
        builder.hide(0, length, MdPieceKind.closer);
      }
    case MdLineKind.rule || MdLineKind.setextUnderline:
      if (blockRevealed) {
        builder.hide(0, info.quoteEnd, MdPieceKind.closer);
        builder.show(info.quoteEnd, length, marks);
      } else {
        builder.hide(0, length, MdPieceKind.closer);
      }
  }
  return builder.finish(base);
}

/// What [text] (a table's cell, a line not edited) shows, its runs
/// without their marks.
TextSpan buildInlineSpan(
  String text, {
  required MarkdownEditorStyle style,
  required TextStyle textStyle,
  Map<String, String> definitions = const {},
  bool Function(MdInline run)? isAtomic,
  InlineSpan Function(MdInline run, TextStyle style)? atomic,
}) {
  final builder = _Builder(
    text,
    style,
    null,
    isAtomic ?? (run) => run.atomic,
    atomic,
  );
  builder.runs(
    0,
    text.length,
    parseInline(text, 0, text.length, definitions: definitions),
    textStyle,
  );
  return builder.finish(textStyle).span;
}

/// A line's display, built from its start to its end.
class _Builder {
  _Builder(
    this.text,
    this.style,
    this.reveal,
    this.isAtomic,
    this.atomic, {
    this.grounds = false,
    this.revealed,
  });

  final String text;
  final MarkdownEditorStyle style;
  final int? reveal;
  final bool Function(MdInline run) isAtomic;
  final InlineSpan Function(MdInline run, TextStyle style)? atomic;

  /// Grounds (code's, a color's) as [MdGroundSpan]s, for a line's box to
  /// paint under the selection; else its text's `backgroundColor`.
  final bool grounds;

  /// Whether a run the caret is in shows its marks; every one by default.
  final bool Function(MdInline run)? revealed;

  /// The ground of the run being shown, with [grounds].
  Color? _ground;

  final List<MdPiece> _pieces = [];
  final List<InlineSpan> _spans = [];
  int _shown = 0;
  bool _endsInWidget = false;

  void show(int from, int to, TextStyle textStyle) {
    if (from >= to) return;
    final shown = text.substring(from, to);
    _spans.add(switch (_ground) {
      final ground? => MdGroundSpan(
        text: shown,
        style: textStyle,
        ground: ground,
      ),
      null => TextSpan(text: shown, style: textStyle),
    });
    _pieces.add(
      MdPiece(MdPieceKind.text, from, to, _shown, _shown + to - from),
    );
    _shown += to - from;
    _endsInWidget = false;
  }

  void hide(int from, int to, MdPieceKind kind) {
    if (from >= to) return;
    _pieces.add(MdPiece(kind, from, to, _shown, _shown));
  }

  /// [from] to [to] shown as [spans] (their text the same).
  void spans(int from, int to, List<InlineSpan> spans) {
    if (from >= to) return;
    _spans.addAll(spans);
    _pieces.add(
      MdPiece(MdPieceKind.text, from, to, _shown, _shown + to - from),
    );
    _shown += to - from;
    _endsInWidget = false;
  }

  void _atomic(int from, int to, InlineSpan span) {
    final length = span.toPlainText(includeSemanticsLabels: false).length;
    _spans.add(span);
    _pieces.add(MdPiece(MdPieceKind.atomic, from, to, _shown, _shown + length));
    _shown += length;
    _endsInWidget = span is PlaceholderSpan;
  }

  /// [from] to [to], [runs] in it as they show, the rest in [textStyle].
  void runs(int from, int to, List<MdInline> runs, TextStyle textStyle) {
    var at = from;
    for (final run in runs) {
      if (run.start < at || run.end > to) continue;
      show(at, run.start, textStyle);
      _run(run, textStyle);
      at = run.end;
    }
    show(at, to, textStyle);
  }

  void _run(MdInline run, TextStyle parent) {
    if (atomic != null && isAtomic(run)) {
      _atomic(run.start, run.end, atomic!(run, parent));
      return;
    }
    final revealed =
        reveal != null &&
        run.contains(reveal!) &&
        (this.revealed?.call(run) ?? true);
    final marks = parent.copyWith(color: style.marks);
    void mark(int from, int to, MdPieceKind kind) {
      if (revealed) {
        show(from, to, marks);
      } else {
        hide(from, to, kind);
      }
    }

    if (run.kind == MdInlineKind.rawHtml) {
      show(run.start, run.end, marks);
      return;
    }
    var inner = _styleOf(run, parent);
    final ground = _groundOf(run);
    final outer = _ground;
    mark(run.start, run.innerStart, MdPieceKind.opener);
    if (ground != null) {
      if (grounds) {
        _ground = ground;
      } else {
        inner = inner.copyWith(backgroundColor: ground);
      }
    }
    switch (run.kind) {
      case MdInlineKind.code ||
          MdInlineKind.math ||
          MdInlineKind.image ||
          MdInlineKind.escape ||
          MdInlineKind.url:
        show(run.innerStart, run.innerEnd, inner);
      default:
        runs(run.innerStart, run.innerEnd, run.children, inner);
    }
    _ground = outer;
    mark(run.innerEnd, run.end, MdPieceKind.closer);
  }

  TextStyle _styleOf(MdInline run, TextStyle parent) {
    switch (run.kind) {
      case MdInlineKind.strong:
        return parent.merge(style.bold);
      case MdInlineKind.emphasis:
        return parent.merge(style.italic);
      case MdInlineKind.strongEmphasis:
        return parent.merge(style.bold).merge(style.italic);
      case MdInlineKind.strike:
        return _decorate(parent, TextDecoration.lineThrough);
      case MdInlineKind.code || MdInlineKind.math:
        return parent.merge(style.code);
      case MdInlineKind.link ||
          MdInlineKind.autolink ||
          MdInlineKind.url ||
          MdInlineKind.image:
        return _link(parent);
      case MdInlineKind.footnoteRef:
        return _link(parent).copyWith(fontSize: (parent.fontSize ?? 14) * 0.8);
      case MdInlineKind.escape || MdInlineKind.rawHtml || MdInlineKind.atom:
        return parent;
      case MdInlineKind.styleTag:
        var tagged = switch (run.tag) {
          'u' || 'ins' => _decorate(parent, TextDecoration.underline),
          's' ||
          'del' ||
          'strike' => _decorate(parent, TextDecoration.lineThrough),
          'b' || 'strong' => parent.merge(style.bold),
          'i' || 'em' => parent.merge(style.italic),
          'kbd' => parent.merge(style.code),
          'sup' ||
          'sub' => parent.copyWith(fontSize: (parent.fontSize ?? 14) * 0.75),
          _ => parent,
        };
        if (run.color case final css?) {
          if (style.colorOf(css) case final color?) {
            tagged = tagged.copyWith(color: color);
          }
        }
        return tagged;
    }
  }

  /// The ground [run]'s text is on: code's, or the color it is given.
  Color? _groundOf(MdInline run) => switch (run.kind) {
    MdInlineKind.code || MdInlineKind.math => style.codeBackground,
    MdInlineKind.styleTag =>
      switch (run.background) {
            final css? => style.colorOf(css),
            null => null,
          } ??
          (run.tag == 'kbd' ? style.codeBackground : null),
    _ => null,
  };

  TextStyle _link(TextStyle parent) {
    var link = parent.merge(
      style.link.copyWith(decoration: TextDecoration.none),
    );
    if (style.link.decoration case final decoration?
        when decoration != TextDecoration.none) {
      link = _decorate(link, decoration);
    }
    return link;
  }

  static TextStyle _decorate(TextStyle style, TextDecoration decoration) {
    final current = style.decoration;
    return style.copyWith(
      decoration: current == null || current == TextDecoration.none
          ? decoration
          : TextDecoration.combine([current, decoration]),
    );
  }

  MdLineDisplay finish(TextStyle base) {
    final length = text.length;
    // A caret after a picture at the end is laid out by a character after
    // it; so is an empty line's, as high as one with text then (an empty
    // paragraph's height is rounded otherwise: a line emptied would move
    // those under it by a pixel).
    if (_endsInWidget || _shown == 0) {
      _spans.add(TextSpan(text: '\u200B', style: base));
      _pieces.add(
        MdPiece(MdPieceKind.extra, length, length, _shown, _shown + 1),
      );
      _shown++;
    }
    final span = TextSpan(style: base, children: _spans);
    var hasWidgets = false;
    span.visitChildren((child) => !(hasWidgets = child is PlaceholderSpan));
    return MdLineDisplay(
      span,
      MdOffsets(_pieces, length, _shown),
      hasWidgets: hasWidgets,
    );
  }
}
