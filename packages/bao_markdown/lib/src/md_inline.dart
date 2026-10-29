import 'package:flutter/foundation.dart';

/// What a run of a line's markdown is.
enum MdInlineKind {
  /// `**…**`, `__…__`.
  strong,

  /// `*…*`, `_…_`.
  emphasis,

  /// `***…***`.
  strongEmphasis,

  /// `~~…~~`.
  strike,

  /// `` `…` ``.
  code,

  /// `[text](href "title")`, `[text][label]`, `[label]`.
  link,

  /// `![alt](src "title")`, `<img src width>`.
  image,

  /// `<https://…>`.
  autolink,

  /// A bare `https://…`.
  url,

  /// `$tex$`.
  math,

  /// `[^label]`.
  footnoteRef,

  /// `\*`: the mark itself.
  escape,

  /// `<u>`, `<span style>`, `<b>`…: what their marks make.
  styleTag,

  /// Any other tag: shown as it is written.
  rawHtml,

  /// Something of the app's own, written as [MdAtoms] write it: shown as
  /// one thing, never as its text (a plain text's chips).
  atom,
}

/// A run of a line's markdown: from [start] to [end] (the line's columns),
/// its text from [innerStart] to [innerEnd], the rest its marks.
@immutable
class MdInline {
  const MdInline(
    this.kind,
    this.start,
    this.end,
    this.innerStart,
    this.innerEnd, {
    this.children = const [],
    this.href,
    this.title,
    this.tag,
    this.color,
    this.background,
    this.width,
  });

  final MdInlineKind kind;
  final int start;
  final int end;
  final int innerStart;
  final int innerEnd;

  /// What is inside, parsed (none for code, math, pictures).
  final List<MdInline> children;

  /// A link's, a picture's (its source), an autolink's.
  final String? href;
  final String? title;

  /// A style tag's name (`u`, `span`…).
  final String? tag;

  /// A `<span style>`'s colors, as written (CSS names or values).
  final String? color;
  final String? background;

  /// A picture's width (`<img width>`).
  final double? width;

  /// Whether nothing of it may be edited in place: shown as one thing
  /// where it is a picture's, a formula's.
  bool get atomic =>
      kind == MdInlineKind.image ||
      kind == MdInlineKind.math ||
      kind == MdInlineKind.atom;

  bool contains(int column) => start <= column && column <= end;

  @override
  bool operator ==(Object other) =>
      other is MdInline &&
      other.kind == kind &&
      other.start == start &&
      other.end == end &&
      other.innerStart == innerStart &&
      other.innerEnd == innerEnd &&
      listEquals(other.children, children) &&
      other.href == href &&
      other.title == title &&
      other.tag == tag &&
      other.color == color &&
      other.background == background &&
      other.width == width;

  @override
  int get hashCode => Object.hash(
    kind,
    start,
    end,
    innerStart,
    innerEnd,
    Object.hashAll(children),
    href,
    title,
    tag,
    color,
    background,
    width,
  );

  @override
  String toString() => 'MdInline($kind, $start-$end)';
}

/// The runs of markdown in [text] from [from] to [to] (the rest of it,
/// between them, is text as it is). [definitions] are the text's link
/// definitions, by their labels in lower case.
List<MdInline> parseInline(
  String text,
  int from,
  int to, {
  Map<String, String> definitions = const {},
}) => _InlineParser(text, definitions).parse(from, to);

/// Things of an app's own in a text (a message's chips: a file, a
/// picture…), each written as one run: [open], what it is (its data, of
/// the app's making), [close]. The two marks are of Unicode's private use:
/// nothing typed or pasted has them ([strip] takes them out of what is),
/// so text never reads as one.
abstract final class MdAtoms {
  static const open = '\uE000';
  static const close = '\uE001';

  /// What an input method is told an atom is: one character.
  static const shown = '\uFFFC';

  /// [data] (of one line, without the marks: escaped where it may have
  /// them) as an atom.
  static String encode(String data) {
    assert(!data.contains('\n'), 'An atom is written on one line');
    return '$open${strip(data)}$close';
  }

  /// What the atom [run] of [line] holds.
  static String data(MdInline run, String line) =>
      line.substring(run.innerStart, run.innerEnd);

  /// [text] without the marks: as text, nothing of it an atom.
  static String strip(String text) =>
      text.contains(open) || text.contains(close)
      ? text.replaceAll(open, '').replaceAll(close, '')
      : text;

  /// The atoms in [text] from [from] to [to].
  static List<MdInline> parse(String text, [int from = 0, int? to]) {
    to ??= text.length;
    var at = text.indexOf(open, from);
    if (at < 0 || at >= to) return const [];
    final runs = <MdInline>[];
    while (at >= 0 && at < to) {
      final end = text.indexOf(close, at + 1);
      if (end < 0 || end >= to) break;
      // A mark opened again before this one closes: the first is text.
      final again = text.lastIndexOf(open, end);
      runs.add(MdInline(MdInlineKind.atom, again, end + 1, again + 1, end));
      at = text.indexOf(open, end + 1);
    }
    return runs;
  }
}

/// A stretch of a text as an input method is told of it: each atom
/// ([MdAtoms]) one character, [MdAtoms.shown]. And where an offset of
/// either is in the other: the one place that is worked out, for what is
/// told, what comes back, and the edits in between.
@immutable
class MdTold {
  const MdTold._(this.text, this.start, this._atoms);

  /// Nothing told.
  static const empty = MdTold._('', 0, []);

  /// [source], the text's from [start], as it is told.
  factory MdTold.of(String source, {int start = 0}) {
    if (!source.contains(MdAtoms.open)) {
      return MdTold._(source, start, const []);
    }
    final atoms = <(int, int)>[];
    final told = StringBuffer();
    var at = 0;
    for (final run in MdAtoms.parse(source)) {
      told
        ..write(source.substring(at, run.start))
        ..write(MdAtoms.shown);
      atoms.add((told.length - 1, run.end - run.start));
      at = run.end;
    }
    told.write(source.substring(at));
    return MdTold._(told.toString(), start, atoms);
  }

  /// What is told.
  final String text;

  /// Where it starts in the text.
  final int start;

  /// Each atom: where its character is in [text], and how long it is in
  /// the text. In order.
  final List<(int, int)> _atoms;

  /// The text's offset of [told], an offset in [text].
  int toSource(int told) {
    var offset = start + told;
    for (final (at, length) in _atoms) {
      if (at >= told) break;
      offset += length - 1;
    }
    return offset;
  }

  /// Where the text's [offset] is in [text]: one inside an atom at the
  /// atom's.
  int toTold(int offset) {
    var told = offset - start;
    var shift = 0;
    for (final (at, length) in _atoms) {
      final from = start + at + shift;
      if (offset <= from) break;
      told -= offset >= from + length ? length - 1 : offset - from;
      shift += length - 1;
    }
    return told;
  }

  /// This after [from] to [to] of [text] was replaced by [inserted], as an
  /// input method edits it: the atoms in it gone (what it puts in is
  /// text), those after it moved. (An edit out of step with [text] leaves
  /// it as it was, the atoms moved as told.)
  MdTold edited(int from, int to, String inserted) => MdTold._(
    0 <= from && from <= to && to <= text.length
        ? text.replaceRange(from, to, inserted)
        : text,
    start,
    [
      for (final (at, length) in _atoms)
        if (at < from)
          (at, length)
        else if (at >= to)
          (at + inserted.length - (to - from), length),
    ],
  );
}

/// The runs of [runs] (and in them) that [column] is in or beside, the
/// outermost first.
List<MdInline> inlinesAt(List<MdInline> runs, int column) {
  final found = <MdInline>[];
  var level = runs;
  while (true) {
    MdInline? hit;
    for (final run in level) {
      if (run.contains(column)) {
        hit = run;
        break;
      }
    }
    if (hit == null) return found;
    found.add(hit);
    level = hit.children;
  }
}

class _InlineParser {
  _InlineParser(this.text, this.definitions);

  final String text;
  final Map<String, String> definitions;

  List<MdInline> parse(int from, int to) {
    final runs = <MdInline>[];
    var i = from;
    while (i < to) {
      final run = _at(i, to);
      if (run != null) {
        runs.add(run);
        i = run.end;
      } else {
        i++;
      }
    }
    return runs;
  }

  MdInline? _at(int i, int to) {
    final char = text[i];
    switch (char) {
      case r'\':
        if (i + 1 < to && _escapable.contains(text[i + 1])) {
          return MdInline(MdInlineKind.escape, i, i + 2, i + 1, i + 2);
        }
      case '`':
        return _code(i, to);
      case r'$':
        return _math(i, to);
      case '!':
        if (i + 1 < to && text[i + 1] == '[') {
          final link = _link(i + 1, to);
          if (link != null) {
            return MdInline(
              MdInlineKind.image,
              i,
              link.end,
              i + 2,
              link.textEnd,
              href: link.href,
              title: link.title,
            );
          }
        }
      case '[':
        return _bracket(i, to);
      case '<':
        return _angle(i, to);
      case '*' || '_' || '~':
        return _emphasis(i, to);
      case 'h':
        return _bareUrl(i, to);
    }
    return null;
  }

  MdInline? _code(int i, int to) {
    var open = i;
    while (open < to && text[open] == '`') {
      open++;
    }
    final ticks = open - i;
    var at = open;
    while (at < to) {
      final close = text.indexOf('`' * ticks, at);
      if (close < 0 || close + ticks > to) return null;
      // As many as opened it: not part of a longer run.
      var after = close + ticks;
      if ((after < to && text[after] == '`') ||
          (close > open && text[close - 1] == '`')) {
        while (after < to && text[after] == '`') {
          after++;
        }
        at = after;
        continue;
      }
      var innerStart = open;
      var innerEnd = close;
      // One space each side is the marks', when both are there.
      if (innerEnd - innerStart > 2 &&
          text[innerStart] == ' ' &&
          text[innerEnd - 1] == ' ' &&
          text.substring(innerStart, innerEnd).trim().isNotEmpty) {
        innerStart++;
        innerEnd--;
      }
      return MdInline(MdInlineKind.code, i, after, innerStart, innerEnd);
    }
    return null;
  }

  MdInline? _math(int i, int to) {
    if (i + 1 < to && text[i + 1] == r'$') return null;
    if (i > 0 && text[i - 1] == r'$') return null;
    final match = _inlineMath.matchAsPrefix(text.substring(i, to));
    if (match == null) return null;
    final end = i + match[0]!.length;
    return MdInline(MdInlineKind.math, i, end, i + 1, end - 1);
  }

  MdInline? _bracket(int i, int to) {
    // A footnote's reference.
    if (_footnoteRef.matchAsPrefix(text.substring(i, to)) case final ref?) {
      final end = i + ref[0]!.length;
      return MdInline(MdInlineKind.footnoteRef, i, end, i + 2, end - 1);
    }
    final link = _link(i, to);
    if (link != null) {
      return MdInline(
        MdInlineKind.link,
        i,
        link.end,
        i + 1,
        link.textEnd,
        children: parse(i + 1, link.textEnd),
        href: link.href,
        title: link.title,
      );
    }
    // A reference to a definition: `[text][label]`, `[text][]`, `[label]`.
    final close = _closingBracket(i, to);
    if (close < 0) return null;
    final label = text.substring(i + 1, close);
    var end = close + 1;
    var key = label;
    if (end < to && text[end] == '[') {
      final second = _closingBracket(end, to);
      if (second >= 0) {
        final inner = text.substring(end + 1, second);
        if (inner.isNotEmpty) key = inner;
        end = second + 1;
      }
    }
    final href = definitions[key.toLowerCase()];
    if (href == null) return null;
    return MdInline(
      MdInlineKind.link,
      i,
      end,
      i + 1,
      close,
      children: parse(i + 1, close),
      href: href,
    );
  }

  int _closingBracket(int at, int to) {
    var depth = 0;
    for (var j = at; j < to; j++) {
      final c = text[j];
      if (c == r'\') {
        j++;
        continue;
      }
      if (c == '[') depth++;
      if (c == ']' && --depth == 0) return j;
    }
    return -1;
  }

  /// `[text](href "title")` at [at]: where its text ends, and it.
  ({int textEnd, int end, String href, String? title})? _link(int at, int to) {
    final close = _closingBracket(at, to);
    if (close < 0 || close + 1 >= to || text[close + 1] != '(') return null;
    final match = _destination.matchAsPrefix(text.substring(close + 1, to));
    if (match == null) return null;
    return (
      textEnd: close,
      end: close + 1 + match[0]!.length,
      href: match[1] ?? match[2] ?? '',
      title: match[3] ?? match[4],
    );
  }

  MdInline? _angle(int i, int to) {
    final rest = text.substring(i, to);
    if (_autolink.matchAsPrefix(rest) case final auto?) {
      final end = i + auto[0]!.length;
      return MdInline(
        MdInlineKind.autolink,
        i,
        end,
        i + 1,
        end - 1,
        href: auto[1],
      );
    }
    if (_img.matchAsPrefix(rest) case final img?) {
      final tag = img[0]!;
      final src = _attribute(tag, 'src');
      if (src != null) {
        return MdInline(
          MdInlineKind.image,
          i,
          i + tag.length,
          i,
          i,
          href: src,
          title: _attribute(tag, 'alt'),
          width: double.tryParse(_attribute(tag, 'width') ?? ''),
        );
      }
    }
    if (_openTag.matchAsPrefix(rest) case final open?) {
      final name = open[1]!.toLowerCase();
      if (_styleTags.contains(name)) {
        final innerStart = i + open[0]!.length;
        final tags = RegExp('<(/?)$name(?:\\s[^>]*)?>', caseSensitive: false);
        var depth = 1;
        for (final match in tags.allMatches(
          text.substring(0, to),
          innerStart,
        )) {
          depth += match[1]!.isEmpty ? 1 : -1;
          if (depth == 0) {
            final style = _styleOf(open[2] ?? '');
            return MdInline(
              MdInlineKind.styleTag,
              i,
              match.end,
              innerStart,
              match.start,
              children: parse(innerStart, match.start),
              tag: name,
              color: style.color,
              background: style.background ?? (name == 'mark' ? 'mark' : null),
            );
          }
        }
      }
    }
    if (_anyTag.matchAsPrefix(rest) case final tag?) {
      final end = i + tag[0]!.length;
      return MdInline(MdInlineKind.rawHtml, i, end, i, end);
    }
    return null;
  }

  static ({String? color, String? background}) _styleOf(String attributes) {
    final style =
        RegExp(r'''style\s*=\s*["']([^"']*)["']''')
            .firstMatch(attributes)?[1] ??
        '';
    final color =
        RegExp(r'(?:^|;)\s*color:\s*([^;]+)').firstMatch(style)?[1]?.trim() ??
        RegExp(r'''color\s*=\s*["']([^"']*)["']''').firstMatch(attributes)?[1];
    final background = RegExp(r'background(?:-color)?:\s*([^;]+)')
        .firstMatch(style)?[1]
        ?.trim();
    return (color: color, background: background);
  }

  static String? _attribute(String tag, String name) => RegExp(
    '\\s$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))',
    caseSensitive: false,
  ).firstMatch(tag)?.let((m) => m[1] ?? m[2] ?? m[3]);

  /// The emphasis (`**bold**`, `*italic*`, `~~struck~~`…) at [at];
  /// underscores only between words' edges, as GitHub reads them.
  MdInline? _emphasis(int at, int to) {
    for (final (mark, kind) in const [
      ('***', MdInlineKind.strongEmphasis),
      ('**', MdInlineKind.strong),
      ('__', MdInlineKind.strong),
      ('~~', MdInlineKind.strike),
      ('*', MdInlineKind.emphasis),
      ('_', MdInlineKind.emphasis),
    ]) {
      if (!text.startsWith(mark, at)) continue;
      final start = at + mark.length;
      if (start >= to || text[start].trim().isEmpty) continue;
      final underscore = mark.startsWith('_');
      if (underscore && at > 0 && _word.hasMatch(text[at - 1])) continue;
      // Not the end of a longer run of its marks (`****`).
      if (at > 0 && text[at - 1] == mark[0]) continue;
      var from = start + 1;
      while (true) {
        final close = text.indexOf(mark, from);
        if (close < 0 || close + mark.length > to) break;
        final after = close + mark.length;
        final ok =
            text[close - 1].trim().isNotEmpty &&
            text[close - 1] != r'\' &&
            // Not the end of a longer run (`**b**` in `*a **b** c*`).
            text[close - 1] != mark[0] &&
            // `**a**` is not `*` + `*a*` + `*`.
            (after >= to || text[after] != mark[0]) &&
            (!underscore || after >= to || !_word.hasMatch(text[after]));
        if (ok) {
          return MdInline(
            kind,
            at,
            after,
            start,
            close,
            children: parse(start, close),
          );
        }
        from = close + 1;
      }
    }
    return null;
  }

  MdInline? _bareUrl(int i, int to) {
    if (i > 0 && _wordOrSlash.hasMatch(text[i - 1])) return null;
    final match = _url.matchAsPrefix(text.substring(i, to));
    if (match == null) return null;
    final end = i + match[0]!.length;
    return MdInline(MdInlineKind.url, i, end, i, end, href: match[0]);
  }

  static const _escapable =
      r'\`*_{}[]()#+-.!|~$<>"'
      "'";
  static final _inlineMath = RegExp(r'\$([^\s$](?:[^$]*[^\s$])?)\$(?!\d)');
  static final _footnoteRef = RegExp(r'\[\^[^\]\s]+\]');
  static final _destination = RegExp(
    r'''\(\s*(?:<([^>\n]*)>|([^\s()]*(?:\([^\s()]*\)[^\s()]*)*))(?:\s+(?:"([^"]*)"|'([^']*)'))?\s*\)''',
  );
  static final _autolink = RegExp(
    r'<((?:https?|ftp|mailto|file):[^\s<>]*|[\w.+-]+@[\w-]+(?:\.[\w-]+)+)>',
  );
  static final _img = RegExp(r'<img\s[^>]*>', caseSensitive: false);
  static final _openTag = RegExp(r'<([a-zA-Z]+)((?:\s[^>]*)?)>');
  static final _anyTag = RegExp(
    r'<(?:/?[a-zA-Z][a-zA-Z0-9-]*(?:\s[^<>]*)?/?|!--.*?--)>',
  );
  static const _styleTags = {
    'span',
    'font',
    'mark',
    'u',
    'ins',
    'b',
    'strong',
    'i',
    'em',
    's',
    'del',
    'strike',
    'sup',
    'sub',
    'kbd',
  };
  static final _word = RegExp(r'\w');
  static final _wordOrSlash = RegExp(r'[\w/]');
  static final _url = RegExp(
    r'https?://[^\s<>()\[\]]+[^\s<>()\[\].,;:!?。，；：！？"'
    "'"
    r']',
  );
}

extension<T extends Object> on T {
  R let<R>(R Function(T it) block) => block(this);
}
