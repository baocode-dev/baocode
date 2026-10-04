// A markdown document's top-level blocks, by line: what the preview shows
// one by one and edits one at a time (see markdown_preview.dart). The
// `markdown` package parses without positions, so the lines each block
// spans are found here, scanning as its block syntaxes do (the order they
// are tried in, CommonMark's and GFM's rules for what ends a block), and
// each block is then parsed on its own.

/// The lines of a text: where each begins and where its content ends,
/// before its line break (CRLF, a lone CR or a lone LF, as the editor
/// breaks them). A text ending in a line break ends in an empty line.
class MarkdownLines {
  factory MarkdownLines(String text) {
    final starts = <int>[0];
    final ends = <int>[];
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x0A) {
        ends.add(i);
        starts.add(i + 1);
      } else if (unit == 0x0D) {
        ends.add(i);
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) i++;
        starts.add(i + 1);
      }
    }
    ends.add(text.length);
    return MarkdownLines._(text, starts, ends);
  }

  MarkdownLines._(this.text, this.starts, this.ends);

  final String text;

  /// Each line's offset in [text], and where its content ends.
  final List<int> starts;
  final List<int> ends;

  int get length => starts.length;

  String operator [](int line) => text.substring(starts[line], ends[line]);

  /// Lines [start, end)'s text, without the last one's line break.
  String source(int start, int end) =>
      text.substring(starts[start], ends[end - 1]);

  /// The line [offset] is on.
  int lineAt(int offset) {
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (starts[middle] <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    return low;
  }

  /// The line break the text uses: its first one's, LF when it has none.
  String get lineBreak {
    if (starts.length < 2) return '\n';
    return text.substring(ends[0], starts[1]);
  }
}

enum MarkdownBlockKind {
  /// Empty lines, between the others.
  blank,
  paragraph,
  heading,
  list,
  table,
  fence,
  indentedCode,
  quote,
  rule,
  math,
  html,

  /// A YAML header between `---` lines, first in the file.
  frontMatter,
}

/// A block of the document: its lines [start, end), zero-based.
class MarkdownBlock {
  const MarkdownBlock(this.kind, this.start, this.end);

  final MarkdownBlockKind kind;
  final int start;
  final int end;

  @override
  bool operator ==(Object other) =>
      other is MarkdownBlock &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'MarkdownBlock(${kind.name}, $start, $end)';
}

/// [lines] as blocks, in order, every line in one: the empty lines
/// between blocks are blocks of their own ([MarkdownBlockKind.blank]).
List<MarkdownBlock> splitMarkdownBlocks(MarkdownLines lines) =>
    _Splitter(lines).split();

class _Splitter {
  _Splitter(this.lines);

  final MarkdownLines lines;
  int get n => lines.length;

  final blocks = <MarkdownBlock>[];

  List<MarkdownBlock> split() {
    var i = 0;
    if (n > 1 && lines[0].trimRight() == '---') {
      for (var j = 1; j < n; j++) {
        final line = lines[j].trimRight();
        if (line == '---' || line == '...') {
          blocks.add(MarkdownBlock(MarkdownBlockKind.frontMatter, 0, j + 1));
          i = j + 1;
          break;
        }
      }
    }
    while (i < n) {
      if (_blank(lines[i])) {
        var j = i + 1;
        while (j < n && _blank(lines[j])) {
          j++;
        }
        blocks.add(MarkdownBlock(MarkdownBlockKind.blank, i, j));
        i = j;
        continue;
      }
      final (kind, end) = _block(i);
      blocks.add(MarkdownBlock(kind, i, end));
      i = end;
    }
    return blocks;
  }

  /// The block starting at (non-empty) line [i]: its kind and end. The
  /// syntaxes are tried in the order MarkdownView's document tries them:
  /// its own (fences, math), GFM's (tables, lists), then CommonMark's.
  (MarkdownBlockKind, int) _block(int i) {
    final line = lines[i];
    if (_fence(line) case final fence?) {
      return (MarkdownBlockKind.fence, _fenceEnd(i, fence));
    }
    if (_mathEnd(i) case final end?) return (MarkdownBlockKind.math, end);
    if (_tableStarts(i)) return (MarkdownBlockKind.table, _tableEnd(i));
    if (!_rule.hasMatch(line)) {
      if (_listItem(line) case final item?) {
        return (MarkdownBlockKind.list, _listEnd(i, item));
      }
    }
    if (_footnote.hasMatch(line)) {
      return (MarkdownBlockKind.paragraph, _paragraphEnd(i).$2);
    }
    if (_htmlCondition(line) case final condition?) {
      return (MarkdownBlockKind.html, _htmlEnd(i, condition));
    }
    if (_heading.hasMatch(line)) return (MarkdownBlockKind.heading, i + 1);
    if (_indent(line) >= 4) {
      return (MarkdownBlockKind.indentedCode, _indentedEnd(i));
    }
    if (_quote.hasMatch(line)) return (MarkdownBlockKind.quote, _quoteEnd(i));
    if (_rule.hasMatch(line)) return (MarkdownBlockKind.rule, i + 1);
    return _paragraphEnd(i);
  }

  // --- Fences ---------------------------------------------------------------

  int _fenceEnd(int i, ({String char, int length}) fence) {
    final close = RegExp(
      '^ {0,3}${RegExp.escape(fence.char)}{${fence.length},}[ \\t]*\$',
    );
    for (var j = i + 1; j < n; j++) {
      if (close.hasMatch(lines[j])) return j + 1;
    }
    // Unclosed: to the end, as the parser takes it.
    return n;
  }

  // --- Math: MathBlockSyntax's `$$ … $$` and `\[ … \]` ----------------------

  int? _mathEnd(int i) {
    final match = _math.firstMatch(lines[i]);
    if (match == null) return null;
    final close = match[1] == r'$$' ? r'$$' : r'\]';
    if (match[2]!.trimRight().endsWith(close)) return i + 1;
    for (var j = i + 1; j < n; j++) {
      if (lines[j].trimRight().endsWith(close)) return j + 1;
    }
    return n;
  }

  // --- Tables ---------------------------------------------------------------

  bool _tableStarts(int i) =>
      i + 1 < n &&
      _tableDelimiter.hasMatch(lines[i + 1]) &&
      _cells(lines[i]) == _cells(lines[i + 1]);

  /// The body's rows: to an empty line or a line starting another block.
  int _tableEnd(int i) {
    var j = i + 2;
    while (j < n && !_blank(lines[j]) && !_interrupts(j)) {
      j++;
    }
    return j;
  }

  /// How many cells a row has: its pipes not escaped, those at its ends
  /// aside.
  static int _cells(String row) {
    var text = row.trim();
    if (text.startsWith('|')) text = text.substring(1);
    if (text.endsWith('|') && !text.endsWith(r'\|')) {
      text = text.substring(0, text.length - 1);
    }
    var cells = 1;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == r'\') {
        i++;
      } else if (text[i] == '|') {
        cells++;
      }
    }
    return cells;
  }

  // --- Lists ----------------------------------------------------------------

  /// A list: its items, what they hold (indented to their content, or
  /// lazily continuing a paragraph), and the empty lines between them.
  int _listEnd(int i, _ListItem first) {
    var contentIndent = first.contentIndent;
    var end = i + 1;
    // A fence open in an item: its lines continue the item only indented.
    RegExp? fenceClose = switch (_fence(first.content)) {
      final open? => _fenceClose(open),
      null => null,
    };
    for (var j = i + 1; j < n; j++) {
      final line = lines[j];
      if (_blank(line)) continue;
      final hadBlank = j > end;
      final indent = _indent(line);
      if (indent >= contentIndent) {
        final content = _strip(line, contentIndent);
        if (fenceClose != null) {
          if (fenceClose.hasMatch(content)) fenceClose = null;
        } else if (_fence(content) case final open?) {
          fenceClose = _fenceClose(open);
        }
        end = j + 1;
        continue;
      }
      if (fenceClose != null) break;
      final item = _rule.hasMatch(line) ? null : _listItem(line);
      if (item != null && item.sameList(first)) {
        contentIndent = item.contentIndent;
        fenceClose = switch (_fence(item.content)) {
          final open? => _fenceClose(open),
          null => null,
        };
        end = j + 1;
        continue;
      }
      if (hadBlank || item != null || _interrupts(j)) break;
      // A paragraph's lazy continuation.
      end = j + 1;
    }
    return end;
  }

  static RegExp _fenceClose(({String char, int length}) fence) =>
      RegExp('^ {0,3}${RegExp.escape(fence.char)}{${fence.length},}[ \\t]*\$');

  // --- HTML -----------------------------------------------------------------

  /// To the end its start condition's (CommonMark's 1 to 7), and on while
  /// the next line starts another, as HtmlBlockSyntax joins them.
  int _htmlEnd(int i, int condition) {
    var j = i;
    while (true) {
      if (condition >= 6) {
        j++;
        while (j < n && !_blank(lines[j])) {
          j++;
        }
      } else {
        final end = _htmlEnds[condition - 1];
        while (j < n && !end.hasMatch(lines[j])) {
          j++;
        }
        j = j < n ? j + 1 : n;
      }
      if (j >= n) return n;
      final next = _htmlCondition(lines[j]);
      if (next == null) return j;
      condition = next;
    }
  }

  // --- Indented code, quotes, paragraphs -------------------------------------

  /// Lines indented four columns and the empty lines between them.
  int _indentedEnd(int i) {
    var end = i + 1;
    for (var j = i + 1; j < n; j++) {
      if (_blank(lines[j])) continue;
      if (_indent(lines[j]) < 4) break;
      end = j + 1;
    }
    return end;
  }

  /// `>` lines, and the lines lazily continuing their paragraphs.
  int _quoteEnd(int i) {
    var j = i + 1;
    while (j < n && !_blank(lines[j])) {
      if (!_quote.hasMatch(lines[j]) && _interrupts(j)) break;
      j++;
    }
    return j;
  }

  /// A paragraph to an empty line or a line starting a block that may
  /// interrupt it; a setext underline makes it a heading.
  (MarkdownBlockKind, int) _paragraphEnd(int i) {
    for (var j = i + 1; j < n; j++) {
      final line = lines[j];
      if (_blank(line)) return (MarkdownBlockKind.paragraph, j);
      if (_setext.hasMatch(line)) return (MarkdownBlockKind.heading, j + 1);
      if (_interrupts(j)) return (MarkdownBlockKind.paragraph, j);
    }
    return (MarkdownBlockKind.paragraph, n);
  }

  /// Whether line [j] starts a block that may end a paragraph (each block
  /// syntax's `canParse` and `canEndBlock`).
  bool _interrupts(int j) {
    final line = lines[j];
    if (_fence(line) != null || _math.hasMatch(line)) return true;
    if (j + 1 < n && _tableDelimiter.hasMatch(lines[j + 1])) return true;
    if (!_rule.hasMatch(line)) {
      if (_listItem(line) case final item?) {
        // Not empty, and an ordered list only from 1.
        if (!item.empty && (item.number == null || item.number == 1)) {
          return true;
        }
      }
    }
    if (_footnote.hasMatch(line)) return true;
    if (_htmlCondition(line) case final condition? when condition < 7) {
      return true;
    }
    return _heading.hasMatch(line) ||
        _quote.hasMatch(line) ||
        _rule.hasMatch(line);
  }
}

// --- Lines ------------------------------------------------------------------

bool _blank(String line) => _empty.hasMatch(line);

/// The columns of [line]'s leading white space, a tab to the next stop of
/// four.
int _indent(String line) {
  var columns = 0;
  for (var i = 0; i < line.length; i++) {
    switch (line[i]) {
      case ' ':
        columns++;
      case '\t':
        columns += 4 - columns % 4;
      default:
        return columns;
    }
  }
  return columns;
}

/// [line] without its first [columns] columns of white space.
String _strip(String line, int columns) {
  var column = 0;
  var i = 0;
  while (i < line.length && column < columns) {
    if (line[i] == ' ') {
      column++;
    } else if (line[i] == '\t') {
      column += 4 - column % 4;
    } else {
      break;
    }
    i++;
  }
  return line.substring(i);
}

({String char, int length})? _fence(String line) {
  final match = _fenceOpen.firstMatch(line);
  if (match == null) return null;
  final marker = match[2] ?? match[4]!;
  return (char: marker[0], length: marker.length);
}

class _ListItem {
  const _ListItem({
    required this.marker,
    required this.number,
    required this.contentIndent,
    required this.empty,
    required this.content,
  });

  /// The bullet (`-`, `*`, `+`) or the number's delimiter (`.`, `)`).
  final String marker;

  /// An ordered item's number.
  final int? number;

  /// The column its content starts at, which its other lines are indented
  /// to.
  final int contentIndent;
  final bool empty;

  /// What follows the marker on its line.
  final String content;

  /// Whether [other] is an item of the same list: the same bullet, or
  /// numbered with the same delimiter.
  bool sameList(_ListItem other) =>
      marker == other.marker && (number == null) == (other.number == null);
}

_ListItem? _listItem(String line) {
  final match = _listMarker.firstMatch(line);
  if (match == null) return null;
  final indent = match[1]!.length;
  final number = match[2];
  final marker = number == null ? match[4]! : match[3]!;
  final markerEnd = indent + (number?.length ?? 0) + 1;
  final rest = line.substring(match.end);
  final spaces = _indent(rest);
  final empty = rest.trim().isEmpty;
  return _ListItem(
    marker: marker,
    number: number == null ? null : int.parse(number),
    // One space when the item is empty or its content is indented code.
    contentIndent: markerEnd + (empty || spaces > 4 ? 1 : spaces),
    empty: empty,
    content: rest.trimLeft(),
  );
}

/// HTML start condition [line] meets (CommonMark's 1 to 7), if any.
int? _htmlCondition(String line) {
  final match = _htmlStart.firstMatch(line);
  if (match == null) return null;
  for (var i = 1; i <= 7; i++) {
    if (match.namedGroup('c$i') != null) return i;
  }
  return null;
}

// The `markdown` package's patterns (src/patterns.dart), which it does not
// export.
final _empty = RegExp(r'^(?:[ \t]*)$');
final _setext = RegExp(r'^[ ]{0,3}(=+|-+)\s*$');
final _heading = RegExp(
  r'^ {0,3}(#{1,6})(?:[ \x09\x0b\x0c].*?)?(?:\s(#*)\s*)?$',
);
final _quote = RegExp(r'^[ ]{0,3}>[ \t]?.*$');
final _fenceOpen = RegExp(r'^( {0,3})(?:(`{3,})([^`]*)|(~{3,})(.*))$');
final _rule = RegExp(r'^ {0,3}([-*_])[ \t]*\1[ \t]*\1(?:\1|[ \t])*$');
final _listMarker = RegExp(r'^( {0,3})(?:(\d{1,9})([.)])|([*+-]))(?=[ \t]|$)');
final _tableDelimiter = RegExp(
  r'^[ ]{0,3}\|?([ \t]*:?\-+:?[ \t]*\|[ \t]*)+([ \t]|[ \t]*:?\-+:?[ \t]*)?$',
);
final _footnote = RegExp(r'^[ ]{0,3}\[\^([^\] \r\n\x00\t]+)\]:[ \t]*');
final _math = RegExp(r'^ {0,3}(\$\$|\\\[)(.*)$');

const _namedTag =
    '<[a-zA-Z][a-zA-Z0-9-]*'
    r'(?:\s+[a-zA-Z_:][a-zA-Z0-9._:-]*'
    r'''(?:\s*=\s*(?:[^\s"'=<>`]+?|'[^']*?'|"[^"]*?"))?)*'''
    r'\s*/?>'
    '|'
    r'</[a-zA-Z][a-zA-Z0-9-]*\s*>';

final _htmlStart = RegExp(
  '^ {0,3}(?:'
  r'<(?<c1>pre|script|style|textarea)(?:\s|>|$)'
  '|(?<c2><!--)'
  r'|(?<c3><\?)'
  '|(?<c4><![a-z])'
  r'|(?<c5><!\[CDATA\[)'
  '|</?(?<c6>address|article|aside|base|basefont|blockquote|body|'
  'caption|center|col|colgroup|dd|details|dialog|dir|DIV|dl|dt|fieldset|'
  'figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|'
  'header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|'
  'optgroup|option|p|param|section|source|summary|table|tbody|td|tfoot|th|'
  'thead|title|tr|track|ul)'
  r'(?:\s|>|/>|$)'
  '|(?<c7>(?:$_namedTag)\\s*\$))',
  caseSensitive: false,
);

/// The ends of HTML start conditions 1 to 5 (6 and 7 end at an empty line).
final _htmlEnds = [
  RegExp('</(?:pre|script|style|textarea)>', caseSensitive: false),
  RegExp('-->'),
  RegExp(r'\?>'),
  RegExp('>'),
  RegExp(']]>'),
];
