// A paragraph's inline markdown with where each piece is in its text: the
// `markdown` package parses without positions, and the live preview (see
// markdown_live_text.dart) hides an element's marks, `**` or `](url)`,
// until the caret comes to it, as Typora does. CommonMark's inline rules
// (spec 0.31, "Inlines" and its appendix's emphasis algorithm) as far as
// the preview shows them, with GFM's strikethrough and bare URLs and the
// chat's TeX (InlineMathSyntax).

enum MarkdownInlineKind {
  strong,
  emphasis,
  strike,
  code,
  link,
  image,

  /// `<https://…>`, `<a@b.c>`.
  autolink,

  /// A bare `https://…` or `www.…` (GFM's autolink extension).
  url,

  /// `$…$`, `$$…$$`, `\(…\)`.
  math,

  /// An inline HTML tag or comment.
  html,

  /// A backslash escaping a punctuation character.
  escape,
}

/// An inline element of a text: [start, end) in it, of which
/// [contentStart, contentEnd) is what it shows (a link's text, emphasis'
/// inside, code's code, an image's alt text); the rest are its marks.
class MarkdownInline {
  const MarkdownInline(
    this.kind,
    this.start,
    this.end, {
    int? contentStart,
    int? contentEnd,
    this.target,
    this.title,
    this.children = const [],
  }) : contentStart = contentStart ?? start,
       contentEnd = contentEnd ?? end;

  final MarkdownInlineKind kind;
  final int start;
  final int end;
  final int contentStart;
  final int contentEnd;

  /// Where a link, image or autolink goes, as written (unescaped).
  final String? target;
  final String? title;

  /// The elements within its content.
  final List<MarkdownInline> children;

  /// Whether [offset] is in it or at one of its ends.
  bool touches(int offset) => offset >= start && offset <= end;

  @override
  String toString() =>
      '${kind.name}($start, $end'
      '${contentStart != start || contentEnd != end ? ', $contentStart-$contentEnd' : ''}'
      '${target != null ? ', $target' : ''}'
      '${children.isEmpty ? '' : ', $children'})';
}

/// [text]'s inline elements, outermost first, in order. [references] are
/// the link definitions' destinations by label (normalized, see
/// [normalizeMarkdownLabel]), which `[text][label]` and `[label]` link to.
List<MarkdownInline> parseMarkdownInlines(
  String text, {
  Map<String, String> references = const {},
}) => _InlineParser(text, references).parse();

/// A link label as definitions and references match: case and runs of
/// white space aside.
String normalizeMarkdownLabel(String label) =>
    label.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

/// Every element of [inlines], nested ones too, outer before inner.
Iterable<MarkdownInline> flattenMarkdownInlines(
  List<MarkdownInline> inlines,
) sync* {
  for (final inline in inlines) {
    yield inline;
    yield* flattenMarkdownInlines(inline.children);
  }
}

// --- Parsing -----------------------------------------------------------------

/// A piece of the text being parsed: plain text (a run of `*` among it), or
/// an element.
sealed class _Node {}

class _Text extends _Node {
  _Text(this.start, this.end);

  int start;
  int end;
}

class _Element extends _Node {
  _Element(this.inline);

  final MarkdownInline inline;
}

/// A run of `*`, `_` or `~`, or a `[`/`![`, in the text's nodes.
class _Delimiter {
  _Delimiter(
    this.node, {
    required this.char,
    required this.canOpen,
    required this.canClose,
  }) : length = node.end - node.start;

  final _Text node;
  final String char;

  /// The run's length as written (for the rule of three).
  final int length;
  final bool canOpen;
  final bool canClose;

  /// For brackets: whether a link may still start here (not within one).
  bool active = true;

  int get count => node.end - node.start;
  bool get isBracket => char == '[' || char == '![';
}

class _InlineParser {
  _InlineParser(this.text, this.references);

  final String text;
  final Map<String, String> references;

  final _nodes = <_Node>[];
  final _delimiters = <_Delimiter>[];

  List<MarkdownInline> parse() {
    var i = 0;
    var textStart = 0;
    void flushText(int end) {
      if (end > textStart) _nodes.add(_Text(textStart, end));
    }

    while (i < text.length) {
      final char = text[i];
      final int? next = switch (char) {
        r'\' => _math(i) ?? _escape(i),
        '`' => _codeSpan(i),
        '<' => _angle(i),
        r'$' => _math(i),
        '*' || '_' || '~' => null,
        '[' || '!' || ']' => null,
        'h' || 'w' || 'H' || 'W' => _url(i),
        _ => null,
      };
      if (next != null) {
        // An element: the text before it, then it (added by the method).
        final element = _nodes.removeLast();
        flushText(i);
        _nodes.add(element);
        i = next;
        textStart = i;
        continue;
      }
      if (char == '*' || char == '_' || char == '~') {
        var j = i + 1;
        while (j < text.length && text[j] == char) {
          j++;
        }
        flushText(i);
        _addRun(i, j, char);
        i = j;
        textStart = i;
        continue;
      }
      if (char == '[' || (char == '!' && _at(i + 1) == '[')) {
        final end = char == '!' ? i + 2 : i + 1;
        flushText(i);
        final node = _Text(i, end);
        _nodes.add(node);
        _delimiters.add(
          _Delimiter(
            node,
            char: char == '!' ? '![' : '[',
            canOpen: true,
            canClose: false,
          ),
        );
        i = end;
        textStart = i;
        continue;
      }
      if (char == ']') {
        flushText(i);
        final next = _closeBracket(i);
        if (next != null) {
          i = next;
          textStart = i;
          continue;
        }
        i++;
        textStart = i;
        continue;
      }
      i++;
    }
    flushText(text.length);
    _processEmphasis(null);
    return [
      for (final node in _nodes)
        if (node is _Element) node.inline,
    ];
  }

  String? _at(int i) => i >= 0 && i < text.length ? text[i] : null;

  // --- Elements of one piece -------------------------------------------------

  int? _escape(int i) {
    final next = _at(i + 1);
    if (next == null || !_asciiPunctuation.hasMatch(next)) return null;
    _nodes.add(
      _Element(
        MarkdownInline(
          MarkdownInlineKind.escape,
          i,
          i + 2,
          contentStart: i + 1,
        ),
      ),
    );
    return i + 2;
  }

  /// A code span: a run of backticks to the next run as long. A run with
  /// none is text, the backticks with it.
  int? _codeSpan(int i) {
    if (i > 0 && text[i - 1] == '`') return null;
    var j = i;
    while (j < text.length && text[j] == '`') {
      j++;
    }
    final length = j - i;
    var k = j;
    while (k < text.length) {
      if (text[k] != '`') {
        k++;
        continue;
      }
      var l = k;
      while (l < text.length && text[l] == '`') {
        l++;
      }
      if (l - k == length) {
        _nodes.add(
          _Element(
            MarkdownInline(
              MarkdownInlineKind.code,
              i,
              l,
              contentStart: j,
              contentEnd: k,
            ),
          ),
        );
        return l;
      }
      k = l;
    }
    return null;
  }

  /// `<scheme:…>`, `<a@b.c>`, or an HTML tag or comment.
  int? _angle(int i) {
    final rest = text.substring(i);
    if (_autolink.matchAsPrefix(rest) case final match?) {
      final target = match[1]!;
      _nodes.add(
        _Element(
          MarkdownInline(
            MarkdownInlineKind.autolink,
            i,
            i + match.end,
            contentStart: i + 1,
            contentEnd: i + match.end - 1,
            target: target.contains(':') ? target : 'mailto:$target',
          ),
        ),
      );
      return i + match.end;
    }
    if (_htmlTag.matchAsPrefix(rest) case final match?) {
      _nodes.add(
        _Element(MarkdownInline(MarkdownInlineKind.html, i, i + match.end)),
      );
      return i + match.end;
    }
    return null;
  }

  /// TeX as InlineMathSyntax takes it: `$$…$$`, `\(…\)`, and `$…$` opened
  /// before a non-space, closed after one and not before a digit.
  int? _math(int i) {
    final match = _inlineMath.matchAsPrefix(text, i);
    if (match == null) return null;
    final open = text[i] == r'$' && match[1] == null ? 1 : 2;
    _nodes.add(
      _Element(
        MarkdownInline(
          MarkdownInlineKind.math,
          i,
          match.end,
          contentStart: i + open,
          contentEnd: match.end - open,
        ),
      ),
    );
    return match.end;
  }

  /// A bare URL, at the start of a word.
  int? _url(int i) {
    if (i > 0 && !_urlBefore.hasMatch(text[i - 1])) return null;
    final match = _bareUrl.matchAsPrefix(text, i);
    if (match == null) return null;
    var end = match.end;
    // A closing parenthesis it does not open is the text's.
    final url = text.substring(i, end);
    if (url.endsWith(')') &&
        ')'.allMatches(url).length > '('.allMatches(url).length) {
      end--;
    }
    final target = text.substring(i, end);
    _nodes.add(
      _Element(
        MarkdownInline(
          MarkdownInlineKind.url,
          i,
          end,
          target: target.toLowerCase().startsWith('www.')
              ? 'http://$target'
              : target,
        ),
      ),
    );
    return end;
  }

  // --- Emphasis ---------------------------------------------------------------

  void _addRun(int start, int end, String char) {
    final node = _Text(start, end);
    _nodes.add(node);
    if (char == '~' && end - start != 2) return;
    final before = start == 0 ? ' ' : text[start - 1];
    final after = end >= text.length ? ' ' : text[end];
    final beforeSpace = _space.hasMatch(before);
    final afterSpace = _space.hasMatch(after);
    final beforePunctuation = _punctuation.hasMatch(before);
    final afterPunctuation = _punctuation.hasMatch(after);
    final left =
        !afterSpace &&
        (!afterPunctuation || beforeSpace || beforePunctuation);
    final right =
        !beforeSpace &&
        (!beforePunctuation || afterSpace || afterPunctuation);
    final bool canOpen;
    final bool canClose;
    if (char == '_') {
      canOpen = left && (!right || beforePunctuation);
      canClose = right && (!left || afterPunctuation);
    } else {
      canOpen = left;
      canClose = right;
    }
    if (!canOpen && !canClose) return;
    _delimiters.add(
      _Delimiter(node, char: char, canOpen: canOpen, canClose: canClose),
    );
  }

  /// The spec's "process emphasis", over the delimiters above [bottom].
  void _processEmphasis(_Delimiter? bottom) {
    final first = bottom == null ? 0 : _delimiters.indexOf(bottom) + 1;
    var c = first;
    while (c < _delimiters.length) {
      final closer = _delimiters[c];
      if (closer.isBracket || !closer.canClose) {
        c++;
        continue;
      }
      var o = c - 1;
      _Delimiter? opener;
      for (; o >= first; o--) {
        final candidate = _delimiters[o];
        if (candidate.isBracket ||
            candidate.char != closer.char ||
            !candidate.canOpen) {
          continue;
        }
        if (closer.char == '~') {
          if (candidate.count != closer.count) continue;
        } else if ((candidate.canClose || closer.canOpen) &&
            (candidate.length + closer.length) % 3 == 0 &&
            !(candidate.length % 3 == 0 && closer.length % 3 == 0)) {
          continue;
        }
        opener = candidate;
        break;
      }
      if (opener == null) {
        if (!closer.canOpen) {
          _delimiters.removeAt(c);
        } else {
          c++;
        }
        continue;
      }
      final use = closer.char == '~'
          ? 2
          : (closer.count >= 2 && opener.count >= 2 ? 2 : 1);
      final kind = closer.char == '~'
          ? MarkdownInlineKind.strike
          : (use == 2 ? MarkdownInlineKind.strong : MarkdownInlineKind.emphasis);
      final openNode = opener.node;
      final closeNode = closer.node;
      final from = _nodes.indexOf(openNode);
      final to = _nodes.indexOf(closeNode);
      final inner = _nodes.sublist(from + 1, to);
      final element = _Element(
        MarkdownInline(
          kind,
          openNode.end - use,
          closeNode.start + use,
          contentStart: openNode.end,
          contentEnd: closeNode.start,
          children: [
            for (final node in inner)
              if (node is _Element) node.inline,
          ],
        ),
      );
      openNode.end -= use;
      closeNode.start += use;
      _nodes.replaceRange(from + 1, to, [element]);
      // The delimiters between them are spent.
      _delimiters.removeRange(o + 1, c);
      c = o + 1;
      if (opener.count == 0) {
        _nodes.remove(openNode);
        _delimiters.removeAt(o);
        c--;
      }
      if (closer.count == 0) {
        _nodes.remove(closeNode);
        _delimiters.removeAt(c);
      }
    }
    // What is left above the bottom opens nothing.
    _delimiters.removeRange(first, _delimiters.length);
  }

  // --- Links and images -------------------------------------------------------

  /// A `]` at [i]: a link or image with the last `[` open, when what
  /// follows makes one. Where the parse goes on, or null for text.
  int? _closeBracket(int i) {
    final o = _delimiters.lastIndexWhere((d) => d.isBracket);
    if (o < 0) {
      _nodes.add(_Text(i, i + 1));
      return null;
    }
    final opener = _delimiters[o];
    if (!opener.active) {
      _delimiters.removeAt(o);
      _nodes.add(_Text(i, i + 1));
      return null;
    }
    final image = opener.char == '![';
    final labelStart = opener.node.end;
    final tail = _linkTail(i + 1) ?? _referenceTail(labelStart, i);
    if (tail == null) {
      _delimiters.removeAt(o);
      _nodes.add(_Text(i, i + 1));
      return null;
    }
    // The emphasis within it, then it.
    _processEmphasis(opener);
    final from = _nodes.indexOf(opener.node);
    final inner = _nodes.sublist(from + 1);
    final element = _Element(
      MarkdownInline(
        image ? MarkdownInlineKind.image : MarkdownInlineKind.link,
        opener.node.start,
        tail.end,
        contentStart: labelStart,
        contentEnd: i,
        target: tail.target,
        title: tail.title,
        children: [
          for (final node in inner)
            if (node is _Element) node.inline,
        ],
      ),
    );
    _nodes.replaceRange(from, _nodes.length, [element]);
    _delimiters.removeAt(o);
    // No links in links.
    if (!image) {
      for (final delimiter in _delimiters) {
        if (delimiter.char == '[') delimiter.active = false;
      }
    }
    return tail.end;
  }

  /// `(destination "title")` at [i].
  ({int end, String target, String? title})? _linkTail(int i) {
    if (_at(i) != '(') return null;
    var j = _skipSpace(i + 1);
    String target;
    if (_at(j) == '<') {
      final close = text.indexOf('>', j + 1);
      if (close < 0) return null;
      final destination = text.substring(j + 1, close);
      if (destination.contains('\n') || destination.contains('<')) return null;
      target = destination;
      j = close + 1;
    } else {
      final start = j;
      var depth = 0;
      while (j < text.length) {
        final char = text[j];
        if (char == r'\' && j + 1 < text.length) {
          j += 2;
          continue;
        }
        if (_space.hasMatch(char) || char.codeUnitAt(0) < 0x20) break;
        if (char == '(') depth++;
        if (char == ')') {
          if (depth == 0) break;
          depth--;
        }
        j++;
      }
      if (depth != 0) return null;
      target = text.substring(start, j);
    }
    final afterTarget = j;
    j = _skipSpace(j);
    String? title;
    final quote = _at(j);
    if (j > afterTarget && (quote == '"' || quote == "'" || quote == '(')) {
      final closeChar = quote == '(' ? ')' : quote!;
      var k = j + 1;
      while (k < text.length && text[k] != closeChar) {
        if (text[k] == r'\') k++;
        k++;
      }
      if (k >= text.length) return null;
      title = _unescape(text.substring(j + 1, k));
      j = _skipSpace(k + 1);
    }
    if (_at(j) != ')') return null;
    return (end: j + 1, target: _unescape(target), title: title);
  }

  /// `[label]`, `[]` after a link's text, or the text a label alone, when
  /// a definition has the label.
  ({int end, String target, String? title})? _referenceTail(
    int labelStart,
    int close,
  ) {
    final next = close + 1;
    if (_at(next) == '[') {
      final end = text.indexOf(']', next + 1);
      if (end >= 0) {
        final label = text.substring(next + 1, end);
        final key = normalizeMarkdownLabel(
          label.isEmpty ? text.substring(labelStart, close) : label,
        );
        if (references[key] case final target?) {
          return (end: end + 1, target: target, title: null);
        }
        if (label.isNotEmpty) return null;
      }
    }
    final key = normalizeMarkdownLabel(text.substring(labelStart, close));
    if (references[key] case final target? when key.isNotEmpty) {
      return (end: close + 1, target: target, title: null);
    }
    return null;
  }

  int _skipSpace(int i) {
    while (i < text.length && _space.hasMatch(text[i])) {
      i++;
    }
    return i;
  }
}

String _unescape(String text) =>
    text.replaceAllMapped(_escaped, (match) => match[1]!);

final _escaped = RegExp(r'\\([!-/:-@\[-`{-~])');
final _asciiPunctuation = RegExp(r'[!-/:-@\[-`{-~]');
final _punctuation = RegExp(r'[\p{P}\p{S}]', unicode: true);
final _space = RegExp(r'\s');
final _autolink = RegExp(
  r'<([A-Za-z][A-Za-z0-9+.-]{1,31}:[^<>\s]*'
  r"|[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9]"
  r'(?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
  r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*)>',
);
final _htmlTag = RegExp(
  r'<[A-Za-z][A-Za-z0-9-]*'
  r'''(?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*(?:\s*=\s*(?:[^\s"'=<>`]+|'[^']*'|"[^"]*"))?)*'''
  r'\s*/?>'
  r'|</[A-Za-z][A-Za-z0-9-]*\s*>'
  r'|<!--[\s\S]*?-->',
);
final _inlineMath = RegExp(
  r'(\$\$)[^$]+?\$\$'
  r'|\\\(.+?\\\)'
  r'|\$(?![\s$])[^$\n]+?(?<!\s)\$(?!\d)',
);
final _urlBefore = RegExp(r'[\s*_~(]');
final _bareUrl = RegExp(
  r'(?:[Hh][Tt][Tt][Pp][Ss]?://|[Ww][Ww][Ww]\.)'
  r'[^\s<]*[^\s<?!.,:*_~'
  "'"
  r'"]',
);
