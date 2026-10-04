// A markdown document as the live preview edits it, Typora's way: rows
// (a paragraph, a heading, a list item, a code block, a table…) shown as
// they render, each with the pieces of text typed in (its units: a table
// has one per cell) and where they are in the document. A unit's text is
// its lines' content, joined by `\n`: the marks around it (a list item's
// bullet, a quote's `>`, a fence's backticks, a cell's pipes) are the
// row's, drawn, and typing in a unit changes only its lines' content (see
// [MarkdownUnit.edit]).
//
// Quotes and list items hold blocks of their own: their lines, their marks
// taken off, are split again (splitMarkdownBlocks), as CommonMark's
// container blocks hold others.

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

import 'markdown_blocks.dart';
import 'markdown_document.dart' show markdownSlug;
import 'markdown_inline.dart';

enum MarkdownRowKind {
  paragraph,
  heading,
  code,
  math,
  table,
  rule,
  html,

  /// The YAML header (`---` … `---`).
  frontMatter,

  /// Link definitions (`[label]: url`), shown as they are written.
  definition,
}

/// The room above a row.
enum MarkdownGap { none, item, block, heading }

/// A piece of a row's text, typed in: lines of the document (their
/// content, [segments]), joined by `\n`.
class MarkdownUnit {
  MarkdownUnit(
    String document,
    this.segments, {
    this.newLine = '\n',
    this.empty,
    this.cell = false,
  }) : text = [
         for (final (start, end) in segments) document.substring(start, end),
       ].join('\n');

  /// Each line's content in the document, [start, end).
  final List<(int, int)> segments;
  final String text;

  /// What a line break typed in it is in the document: the line break and
  /// the next line's marks (`> `, a list item's indent).
  final String newLine;

  /// While its text is empty: the document's range what is typed replaces
  /// (white space), and what goes before and after it there (a cell's
  /// spaces, a code block's line break).
  final ({int start, int end, String before, String after})? empty;

  /// A table's cell: no line breaks, its pipes escaped.
  final bool cell;

  int get start => segments.first.$1;
  int get end => segments.last.$2;

  /// Where [offset] of [text] is in the document.
  int toDocument(int offset) {
    var base = 0;
    for (final (start, end) in segments) {
      final length = end - start;
      if (offset <= base + length) {
        return start + (offset - base).clamp(0, length);
      }
      base += length + 1;
    }
    return end;
  }

  /// Where [offset] of the document is in [text]; null when it is not on
  /// one of its lines' content (their ends count).
  int? toText(int offset) {
    var base = 0;
    for (final (start, end) in segments) {
      if (offset >= start && offset <= end) return base + offset - start;
      base += end - start + 1;
    }
    return null;
  }

  /// Where [offset] of the document is in [text], or the nearest place:
  /// its start before it, its end after it, a line's start for the marks
  /// before the line.
  int toTextNear(int offset) {
    if (toText(offset) case final at?) return at;
    if (offset <= start) return 0;
    var base = 0;
    for (final (from, to) in segments) {
      if (offset < from) return base;
      base += to - from + 1;
    }
    return text.length;
  }

  /// The document's edit replacing [start, end) of [text] with [inserted],
  /// and where in the document the end of [inserted] goes.
  ({EditorOffsetEdit edit, int end}) edit(int start, int end, String inserted) {
    var replacement = inserted;
    if (cell) {
      replacement = replacement
          .replaceAll(RegExp('\r\n|\r|\n'), ' ')
          .replaceAllMapped(RegExp(r'(?<!\\)\|'), (_) => r'\|');
    } else {
      replacement = replacement.replaceAll(RegExp('\r\n|\r|\n'), newLine);
    }
    final empty = this.empty;
    if (text.isEmpty && empty != null && replacement.isNotEmpty) {
      return (
        edit: EditorOffsetEdit(
          empty.start,
          empty.end,
          '${empty.before}$replacement${empty.after}',
        ),
        end: empty.start + empty.before.length + replacement.length,
      );
    }
    final from = toDocument(start);
    return (
      edit: EditorOffsetEdit(from, toDocument(end), replacement),
      end: from + replacement.length,
    );
  }
}

/// A list item's marks, on the row its content starts.
class MarkdownItem {
  const MarkdownItem({
    required this.markerStart,
    required this.markerEnd,
    required this.contentStart,
    required this.bullet,
    required this.number,
    required this.list,
    required this.index,
    this.task,
    this.checked = false,
  });

  /// The bullet's or the number's range in the document, and where the
  /// content starts (after a task box).
  final int markerStart;
  final int markerEnd;
  final int contentStart;

  /// `-`, `*`, `+`, or an ordered item's delimiter (`.`, `)`).
  final String bullet;

  /// An ordered item's number as a list shows it (its first item's, then
  /// on by one); null for a bullet.
  final int? number;

  /// The list (unique in the document) and the item's place in it.
  final int list;
  final int index;

  /// A task box's mark (the space or `x`) in the document.
  final int? task;
  final bool checked;

  bool get ordered => number != null;
}

/// A table's cells, its header's row first, as many in each row as it has
/// columns.
class MarkdownTable {
  const MarkdownTable({
    required this.cells,
    required this.align,
    required this.lines,
    required this.prefix,
  });

  final List<List<MarkdownUnit>> cells;

  /// Each column's alignment: `left`, `center`, `right`, or null.
  final List<String?> align;

  /// Its lines' ranges in the document (their marks, `> `, aside), the
  /// delimiter row's second.
  final List<(int, int)> lines;

  /// What starts a new line of it (`> ` in a quote).
  final String prefix;

  int get columns => align.length;
}

class MarkdownRow {
  MarkdownRow({
    required this.kind,
    required this.units,
    required this.start,
    required this.end,
    required this.firstLine,
    required this.lastLine,
    this.gap = MarkdownGap.block,
    this.level = 0,
    this.marker,
    this.item,
    this.depth = 0,
    this.quotes = const [],
    this.info,
    this.closed = true,
    this.table,
  });

  final MarkdownRowKind kind;
  final List<MarkdownUnit> units;

  /// Its lines in the document: where the first starts (its marks, `>`
  /// or a bullet, with it) and the last's content ends, and their numbers
  /// (zero-based, the last's included).
  final int start;
  final int end;
  final int firstLine;
  final int lastLine;

  final MarkdownGap gap;

  /// A heading's level, and its marks' range (`## `, a setext underline's
  /// line).
  final int level;
  final (int, int)? marker;

  /// The list item it starts.
  MarkdownItem? item;

  /// How many lists it is in.
  final int depth;

  /// The quotes it is in (unique in the document), the outermost first.
  final List<int> quotes;

  /// A code block's info string (its language) range, after its fence.
  final (int, int)? info;

  /// Whether its fence (or `$$`) is closed.
  final bool closed;

  final MarkdownTable? table;

  MarkdownUnit get unit => units.first;
}

/// [text]'s rows (see the file's comment). [caretLine], a line the caret is
/// on, has a row though empty (an empty paragraph, Typora's, to type in).
class MarkdownStructure {
  /// [trailing]: a row after the last when that is no paragraph (a code
  /// block, a list), to go on writing in (Typora's): typed in, it starts
  /// a paragraph.
  factory MarkdownStructure(
    String text, {
    int? caretLine,
    bool trailing = false,
  }) {
    final builder = _Builder(text, caretLine)..build();
    if (trailing) builder.trail();
    return MarkdownStructure._(builder.lines, builder.rows, builder.references);
  }

  MarkdownStructure._(this.lines, this.rows, this.references) {
    final taken = <String, int>{};
    for (final (index, row) in rows.indexed) {
      if (row.kind != MarkdownRowKind.heading) continue;
      final text = row.unit.text;
      final base = markdownSlug(
        markdownPlainText(
          text,
          parseMarkdownInlines(text, references: references),
        ),
      );
      final count = taken[base];
      taken[base] = (count ?? 0) + 1;
      anchors[index] = count == null ? base : '$base-$count';
    }
  }

  final MarkdownLines lines;
  final List<MarkdownRow> rows;

  /// The link definitions' destinations, by label (normalized).
  final Map<String, String> references;

  /// The headings' anchors, by row, as GitHub makes them.
  final Map<int, String> anchors = {};

  String get text => lines.text;
  String get lineBreak => lines.lineBreak;

  /// The heading row whose anchor is [anchor].
  int? heading(String anchor) {
    final wanted = markdownSlug(Uri.decodeComponent(anchor));
    for (final MapEntry(:key, :value) in anchors.entries) {
      if (value == anchor || value == wanted) return key;
    }
    return null;
  }

  /// The row [line] (zero-based) is in, or the first after it, or the
  /// last.
  int rowAtLine(int line) {
    for (final (index, row) in rows.indexed) {
      if (line <= row.lastLine) return index;
    }
    return rows.length - 1;
  }

  /// The unit the caret at [offset] of the document is in, and where in
  /// its text: [offset] on a unit's lines, or else (on marks, on lines no
  /// row shows) the nearest unit's nearest end.
  ({int row, int unit, int offset}) caretAt(int offset) {
    var low = 0;
    var high = rows.length - 1;
    // The last row starting at or before the offset.
    while (low < high) {
      final middle = (low + high + 1) >> 1;
      if (rows[middle].start <= offset) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    // The row after the last, at the end of a document with no line break
    // there, shares its offset with the last's end: the last's.
    if (low > 0 &&
        rows[low].start == rows[low].end &&
        rows[low - 1].end >= offset) {
      for (final (u, unit) in rows[low - 1].units.indexed) {
        if (unit.toText(offset) case final at?) {
          return (row: low - 1, unit: u, offset: at);
        }
      }
    }
    final row = rows[low];
    for (final (u, unit) in row.units.indexed) {
      if (unit.toText(offset) case final at?) {
        return (row: low, unit: u, offset: at);
      }
    }
    if (offset > row.end) {
      return (
        row: low,
        unit: row.units.length - 1,
        offset: row.units.last.text.length,
      );
    }
    // On marks (`> `, a bullet, a fence): the text after them on the line,
    // or the row's first.
    final line = lines.lineAt(offset);
    for (final (u, unit) in row.units.indexed) {
      for (final (start, _) in unit.segments) {
        if (start >= offset && lines.lineAt(start) == line) {
          return (row: low, unit: u, offset: unit.toText(start)!);
        }
      }
    }
    if (offset < row.unit.start) return (row: low, unit: 0, offset: 0);
    return (
      row: low,
      unit: row.units.length - 1,
      offset: row.units.last.text.length,
    );
  }
}

/// [text]'s inline elements' content without their marks: what it reads.
String markdownPlainText(String text, List<MarkdownInline> inlines) {
  final buffer = StringBuffer();
  void write(int start, int end, List<MarkdownInline> inlines) {
    var at = start;
    for (final inline in inlines) {
      buffer.write(text.substring(at, inline.start));
      if (inline.kind != MarkdownInlineKind.html) {
        write(inline.contentStart, inline.contentEnd, inline.children);
      }
      at = inline.end;
    }
    buffer.write(text.substring(at, end));
  }

  write(0, text.length, inlines);
  return buffer.toString();
}

// --- Building -----------------------------------------------------------------

/// A line as a container holds it: its text, its marks taken off, and
/// where that text starts in the document.
class _Line {
  const _Line(this.line, this.offset, this.text);

  final int line;
  final int offset;
  final String text;

  int get end => offset + text.length;

  _Line skip(int count) => _Line(line, offset + count, text.substring(count));
}

class _Context {
  const _Context({
    this.prefix = '',
    this.depth = 0,
    this.quotes = const [],
    this.top = false,
  });

  /// A new line's marks in it.
  final String prefix;
  final int depth;
  final List<int> quotes;
  final bool top;
}

class _Builder {
  _Builder(String text, this.caretLine) : lines = MarkdownLines(text);

  final MarkdownLines lines;
  final int? caretLine;
  final rows = <MarkdownRow>[];
  final references = <String, String>{};

  var _quotes = 0;
  var _lists = 0;

  /// The list item the next row starts.
  MarkdownItem? _item;

  String get text => lines.text;
  late final String lineBreak = lines.lineBreak;

  void build() {
    _container(
      [
        for (var i = 0; i < lines.length; i++)
          _Line(i, lines.starts[i], lines[i]),
      ],
      const _Context(top: true),
      MarkdownGap.none,
    );
  }

  /// The row after the last, to go on writing in (see [MarkdownStructure]).
  void trail() {
    final last = rows.lastOrNull;
    if (last != null &&
        last.kind == MarkdownRowKind.paragraph &&
        last.depth == 0 &&
        last.quotes.isEmpty &&
        last.item == null) {
      return;
    }
    final end = text.length;
    if (last != null && last.unit.text.isEmpty && last.unit.start == end) {
      return;
    }
    final line = lines.length - 1;
    rows.add(
      MarkdownRow(
        kind: MarkdownRowKind.paragraph,
        units: [
          MarkdownUnit(
            text,
            [(end, end)],
            newLine: lineBreak,
            empty: (start: end, end: end, before: _blockPrefix(), after: ''),
          ),
        ],
        start: end,
        end: end,
        firstLine: line,
        lastLine: line,
        gap: rows.isEmpty ? MarkdownGap.none : MarkdownGap.block,
      ),
    );
  }

  /// What goes before a block added at the end: an empty line after the
  /// last.
  String _blockPrefix() {
    if (text.trim().isEmpty) return '';
    if (text.endsWith('$lineBreak$lineBreak')) return '';
    return text.endsWith(lineBreak) ? lineBreak : '$lineBreak$lineBreak';
  }

  void _add(MarkdownRow row) {
    if (_item case final item?) {
      row.item = item;
      _item = null;
    }
    rows.add(row);
  }

  MarkdownRow _row(
    MarkdownRowKind kind,
    List<MarkdownUnit> units,
    List<_Line> lines,
    _Context context,
    MarkdownGap gap, {
    int level = 0,
    (int, int)? marker,
    (int, int)? info,
    bool closed = true,
    MarkdownTable? table,
  }) => MarkdownRow(
    kind: kind,
    units: units,
    start: this.lines.starts[lines.first.line],
    end: lines.last.end,
    firstLine: lines.first.line,
    lastLine: lines.last.line,
    gap: gap,
    level: level,
    marker: marker,
    depth: context.depth,
    quotes: context.quotes,
    info: info,
    closed: closed,
    table: table,
  );

  String _newLine(_Context context) => '$lineBreak${context.prefix}';

  /// [lines]' blocks, as rows; the first with the room [gap].
  void _container(List<_Line> lines, _Context context, MarkdownGap gap) {
    if (lines.isEmpty) return;
    final virtual = MarkdownLines(lines.map((line) => line.text).join('\n'));
    final blocks = splitMarkdownBlocks(virtual, frontMatter: context.top);
    var first = true;
    for (final (index, block) in blocks.indexed) {
      final range = lines.sublist(block.start, block.end);
      if (block.kind == MarkdownBlockKind.blank) {
        _blank(
          range,
          context,
          first: index == 0,
          last: index == blocks.length - 1,
          gap: first ? gap : MarkdownGap.block,
        );
        continue;
      }
      final blockGap = first
          ? gap
          : (block.kind == MarkdownBlockKind.heading
                ? MarkdownGap.heading
                : MarkdownGap.block);
      first = false;
      if (_opening(block, range)) {
        // A fence the caret is still typing (```` ```js ````, no Enter
        // yet): a paragraph, not code to the end, as Typora has it.
        _paragraph([range.first], context, blockGap);
        _container(lines.sublist(block.start + 1), context, MarkdownGap.block);
        return;
      }
      switch (block.kind) {
        case MarkdownBlockKind.blank:
          break;
        case MarkdownBlockKind.paragraph:
          _paragraph(range, context, blockGap);
        case MarkdownBlockKind.heading:
          _heading(range, context, blockGap);
        case MarkdownBlockKind.list:
          _list(range, context, blockGap);
        case MarkdownBlockKind.table:
          _table(range, context, blockGap);
        case MarkdownBlockKind.fence:
          _fence(range, context, blockGap);
        case MarkdownBlockKind.indentedCode:
          _indentedCode(range, context, blockGap);
        case MarkdownBlockKind.quote:
          _quote(range, context, blockGap);
        case MarkdownBlockKind.rule:
          _add(
            _row(
              MarkdownRowKind.rule,
              [
                MarkdownUnit(text, [(range.first.offset, range.first.end)]),
              ],
              range,
              context,
              blockGap,
            ),
          );
        case MarkdownBlockKind.math:
          _math(range, context, blockGap);
        case MarkdownBlockKind.html:
          _add(
            _row(
              MarkdownRowKind.html,
              [_lines(range, context)],
              range,
              context,
              blockGap,
            ),
          );
        case MarkdownBlockKind.frontMatter:
          _frontMatter(range, context);
      }
    }
  }

  /// Whether [block] is a fence (or `$$`) left open on the caret's line.
  bool _opening(MarkdownBlock block, List<_Line> lines) {
    if (lines.first.line != caretLine) return false;
    final text = lines.first.text;
    switch (block.kind) {
      case MarkdownBlockKind.fence:
        final close = _fenceCloseOf(text)!;
        return lines.length < 2 || !close.hasMatch(lines.last.text);
      case MarkdownBlockKind.math:
        final open = _mathOpen.matchAsPrefix(text)!;
        final close = open[1] == r'$$' ? r'$$' : r'\]';
        if (lines.length == 1) {
          return !text.trimRight().endsWith(close) ||
              text.trimRight().length - close.length < open.end;
        }
        return !lines.last.text.trimRight().endsWith(close);
      default:
        return false;
    }
  }

  MarkdownUnit _lines(List<_Line> lines, _Context context) => MarkdownUnit(
    text,
    [for (final line in lines) (line.offset, line.end)],
    newLine: _newLine(context),
  );

  /// Empty lines: rows of their own where there are more than the blocks
  /// around them need (Typora's empty paragraphs), and the caret's.
  void _blank(
    List<_Line> lines,
    _Context context, {
    required bool first,
    required bool last,
    required MarkdownGap gap,
  }) {
    final shown = <_Line>[];
    if (context.top) {
      if (first && last) {
        // Nothing else: a row to type in.
        shown.add(lines.first);
      } else {
        // An empty paragraph is an empty line and the one after it; the
        // line after a block is its own, and the last of a text ending in
        // a line break is none.
        final to = first ? lines.length : lines.length - 1;
        for (var i = first ? 0 : 1; i < to; i += 2) {
          shown.add(lines[i]);
        }
      }
    }
    final caret = caretLine;
    if (caret != null) {
      for (final line in lines) {
        if (line.line == caret && !shown.contains(line)) {
          shown.add(line);
          shown.sort((a, b) => a.line.compareTo(b.line));
        }
      }
    }
    final newLine = _newLine(context);
    for (final (index, row) in shown.indexed) {
      // Typed in next to a block, it would be that block's (a paragraph's
      // lazy line): an empty line between.
      final before = !first && identical(row, lines.first) ? newLine : '';
      final after = !last && identical(row, lines.last)
          ? newLine.replaceFirst(RegExp(r'[ \t]+$'), '')
          : '';
      _add(
        _row(
          MarkdownRowKind.paragraph,
          [
            MarkdownUnit(
              text,
              [(row.offset, row.offset)],
              newLine: newLine,
              empty: (
                start: row.offset,
                end: row.end,
                before: before,
                after: after,
              ),
            ),
          ],
          [row],
          context,
          index == 0
              ? (rows.isEmpty ? MarkdownGap.none : gap)
              : MarkdownGap.block,
        ),
      );
    }
  }

  void _paragraph(List<_Line> lines, _Context context, MarkdownGap gap) {
    final definitions = lines.every(
      (line) => _definition.hasMatch(line.text) || line.text.trim().isEmpty,
    );
    if (definitions) {
      for (final line in lines) {
        final match = _definition.firstMatch(line.text);
        if (match == null) continue;
        var destination = match[2]!;
        if (destination.startsWith('<') && destination.endsWith('>')) {
          destination = destination.substring(1, destination.length - 1);
        }
        references.putIfAbsent(normalizeMarkdownLabel(match[1]!), () {
          return destination;
        });
      }
    }
    _add(
      _row(
        definitions ? MarkdownRowKind.definition : MarkdownRowKind.paragraph,
        [
          // A paragraph's lines' leading white space is not its text.
          _lines([
            for (final line in lines)
              line.skip(line.text.length - line.text.trimLeft().length),
          ], context),
        ],
        lines,
        context,
        gap,
      ),
    );
  }

  void _heading(List<_Line> lines, _Context context, MarkdownGap gap) {
    final first = lines.first;
    final atx = _atx.matchAsPrefix(first.text);
    if (atx != null && lines.length == 1) {
      final contentStart = atx.end;
      final rest = first.text.substring(contentStart);
      final closing = _closingHashes.firstMatch(rest);
      final contentEnd =
          contentStart +
          (closing != null ? closing.start : rest.trimRight().length);
      final from = first.offset + contentStart;
      final to = first.offset + contentEnd;
      _add(
        _row(
          MarkdownRowKind.heading,
          [
            MarkdownUnit(
              text,
              [(from, to)],
              newLine: _newLine(context),
              empty: from == to
                  ? (
                      start: from,
                      end: first.end,
                      before: atx[2]!.isEmpty ? ' ' : '',
                      after: '',
                    )
                  : null,
            ),
          ],
          lines,
          context,
          gap,
          level: atx[1]!.length,
          marker: (first.offset, from),
        ),
      );
      return;
    }
    // Setext: its text, then its underline.
    final underline = lines.last;
    _add(
      _row(
        MarkdownRowKind.heading,
        [_lines(lines.sublist(0, lines.length - 1), context)],
        lines,
        context,
        gap,
        level: underline.text.contains('=') ? 1 : 2,
        marker: (underline.offset, underline.end),
      ),
    );
  }

  void _list(List<_Line> lines, _Context context, MarkdownGap gap) {
    final list = _lists++;
    final first = markdownListItem(lines.first.text)!;
    // The items' first lines, as the splitter finds them (_listEnd).
    final starts = <int>[0];
    var contentIndent = first.contentIndent;
    RegExp? fenceClose = _fenceCloseOf(first.content);
    for (var j = 1; j < lines.length; j++) {
      final line = lines[j].text;
      if (line.trim().isEmpty) continue;
      final indent = markdownIndent(line);
      if (indent >= contentIndent) {
        final content = line.substring(
          markdownIndentLength(line, contentIndent),
        );
        if (fenceClose != null) {
          if (fenceClose.hasMatch(content)) fenceClose = null;
        } else {
          fenceClose = _fenceCloseOf(content);
        }
        continue;
      }
      if (fenceClose != null) continue;
      final item = markdownListItem(line);
      if (item != null && item.sameList(first)) {
        starts.add(j);
        contentIndent = item.contentIndent;
        fenceClose = _fenceCloseOf(item.content);
      }
    }
    for (final (index, start) in starts.indexed) {
      final end = index + 1 < starts.length ? starts[index + 1] : lines.length;
      final line = lines[start];
      final item = markdownListItem(line.text)!;
      var contentStart = item.empty
          ? line.text.length
          : item.markerEnd +
                markdownIndentLength(
                  line.text.substring(item.markerEnd),
                  item.contentIndent - item.markerEnd,
                );
      int? task;
      var checked = false;
      if (_task.matchAsPrefix(line.text, contentStart) case final match?) {
        task = line.offset + contentStart + 1;
        checked = match[1] != ' ';
        contentStart = match.end;
      }
      final children = [line.skip(contentStart)];
      for (final next in lines.sublist(start + 1, end)) {
        if (next.text.trim().isEmpty) {
          children.add(_Line(next.line, next.offset, ''));
        } else if (markdownIndent(next.text) >= item.contentIndent) {
          children.add(
            next.skip(markdownIndentLength(next.text, item.contentIndent)),
          );
        } else {
          children.add(next);
        }
      }
      _item = MarkdownItem(
        markerStart: line.offset + item.markerStart,
        markerEnd: line.offset + item.markerEnd,
        contentStart: line.offset + contentStart,
        bullet: item.marker,
        number: first.number == null ? null : first.number! + index,
        list: list,
        index: index,
        task: task,
        checked: checked,
      );
      final inner = _Context(
        prefix: '${context.prefix}${' ' * item.contentIndent}',
        depth: context.depth + 1,
        quotes: context.quotes,
      );
      final itemGap = index == 0 ? gap : MarkdownGap.item;
      _container(children, inner, itemGap);
      if (_item != null) {
        // Nothing in it yet: a row to type its text in.
        final at = children.first;
        final bare =
            at.text.isEmpty &&
            (line.text.isEmpty ||
                !_space.hasMatch(line.text[line.text.length - 1]));
        _add(
          _row(
            MarkdownRowKind.paragraph,
            [
              MarkdownUnit(
                text,
                [(at.offset, at.offset)],
                newLine: _newLine(inner),
                empty: (
                  start: at.offset,
                  end: at.end,
                  before: bare ? ' ' : '',
                  after: '',
                ),
              ),
            ],
            [line],
            inner,
            itemGap,
          ),
        );
      }
    }
  }

  void _quote(List<_Line> lines, _Context context, MarkdownGap gap) {
    final quote = _quotes++;
    final children = [
      for (final line in lines)
        switch (_quoteMark.matchAsPrefix(line.text)) {
          final match? => line.skip(match.end),
          null => line,
        },
    ];
    _container(
      children,
      _Context(
        prefix: '${context.prefix}> ',
        depth: context.depth,
        quotes: [...context.quotes, quote],
      ),
      gap,
    );
  }

  /// A fence's lines: the code between them, its info string.
  void _fence(List<_Line> lines, _Context context, MarkdownGap gap) {
    final open = lines.first;
    final match = _fenceOpen.firstMatch(open.text)!;
    final marker = match[2] ?? match[4]!;
    final infoText = match[3] ?? match[5] ?? '';
    // The info string runs to the line's end.
    final infoStart =
        open.offset +
        open.text.length -
        infoText.length +
        (infoText.length - infoText.trimLeft().length);
    final info = (infoStart, infoStart + infoText.trim().length);
    final close = RegExp(
      '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
    );
    final closed = lines.length >= 2 && close.hasMatch(lines.last.text);
    _code(
      MarkdownRowKind.code,
      lines,
      lines.sublist(1, closed ? lines.length - 1 : lines.length),
      context,
      gap,
      closed: closed,
      info: info,
    );
  }

  /// A code-like block's row: [content], the lines between [lines]' first
  /// and last (its fences), typed in.
  void _code(
    MarkdownRowKind kind,
    List<_Line> lines,
    List<_Line> content,
    _Context context,
    MarkdownGap gap, {
    required bool closed,
    (int, int)? info,
  }) {
    final newLine = _newLine(context);
    final MarkdownUnit unit;
    if (content.isNotEmpty) {
      unit = MarkdownUnit(text, [
        for (final line in content) (line.offset, line.end),
      ], newLine: newLine);
    } else if (closed) {
      final at = lines.last.offset;
      unit = MarkdownUnit(
        text,
        [(at, at)],
        newLine: newLine,
        empty: (start: at, end: at, before: '', after: newLine),
      );
    } else {
      final at = lines.first.end;
      unit = MarkdownUnit(
        text,
        [(at, at)],
        newLine: newLine,
        empty: (start: at, end: at, before: newLine, after: ''),
      );
    }
    _add(_row(kind, [unit], lines, context, gap, closed: closed, info: info));
  }

  void _indentedCode(List<_Line> lines, _Context context, MarkdownGap gap) {
    final content = [
      for (final line in lines) line.skip(markdownIndentLength(line.text, 4)),
    ];
    _add(
      _row(
        MarkdownRowKind.code,
        [
          MarkdownUnit(text, [
            for (final line in content) (line.offset, line.end),
          ], newLine: '${_newLine(context)}    '),
        ],
        lines,
        context,
        gap,
      ),
    );
  }

  /// `$$ … $$` and `\[ … \]`: the TeX between, typed in.
  void _math(List<_Line> lines, _Context context, MarkdownGap gap) {
    final first = lines.first;
    final open = _mathOpen.matchAsPrefix(first.text)!;
    final close = open[1] == r'$$' ? r'$$' : r'\]';
    if (lines.length == 1) {
      final body = first.text.trimRight();
      final from = first.offset + open.end;
      final to = body.endsWith(close) && body.length - close.length >= open.end
          ? first.offset + body.length - close.length
          : first.end;
      _add(
        _row(
          MarkdownRowKind.math,
          [
            MarkdownUnit(text, [(from, to)], newLine: _newLine(context)),
          ],
          lines,
          context,
          gap,
          closed: to != first.end,
        ),
      );
      return;
    }
    final last = lines.last;
    final closed = last.text.trimRight().endsWith(close);
    if (first.text.trim() == open[1] &&
        (!closed || last.text.trim() == close)) {
      _code(
        MarkdownRowKind.math,
        lines,
        lines.sublist(1, closed ? lines.length - 1 : lines.length),
        context,
        gap,
        closed: closed,
      );
      return;
    }
    // TeX on the fence lines too: its lines whole.
    _add(
      _row(
        MarkdownRowKind.math,
        [_lines(lines, context)],
        lines,
        context,
        gap,
        closed: false,
      ),
    );
  }

  void _frontMatter(List<_Line> lines, _Context context) {
    _code(
      MarkdownRowKind.frontMatter,
      lines,
      lines.sublist(1, lines.length - 1),
      context,
      MarkdownGap.none,
      closed: true,
    );
  }

  void _table(List<_Line> lines, _Context context, MarkdownGap gap) {
    final align = [
      for (final (_, _, from, to) in _cells(lines[1].text))
        switch (lines[1].text.substring(from, to)) {
          final cell when cell.startsWith(':') && cell.endsWith(':') =>
            'center',
          final cell when cell.endsWith(':') => 'right',
          final cell when cell.startsWith(':') => 'left',
          _ => null,
        },
    ];
    final columns = align.length;
    final cells = <List<MarkdownUnit>>[];
    for (final (index, line) in lines.indexed) {
      if (index == 1) continue;
      final found = _cells(line.text);
      final row = <MarkdownUnit>[];
      for (var column = 0; column < columns; column++) {
        if (column < found.length) {
          final (rawStart, rawEnd, from, to) = found[column];
          row.add(
            from < to
                ? MarkdownUnit(text, [
                    (line.offset + from, line.offset + to),
                  ], cell: true)
                : MarkdownUnit(
                    text,
                    [(line.offset + rawStart, line.offset + rawStart)],
                    cell: true,
                    empty: (
                      start: line.offset + rawStart,
                      end: line.offset + rawEnd,
                      before: ' ',
                      after: ' ',
                    ),
                  ),
          );
        } else {
          // Missing: typed in, it is added.
          final trimmed = line.text.trimRight();
          final at = line.offset + trimmed.length;
          final missing = column - found.length;
          row.add(
            MarkdownUnit(
              text,
              [(at, at)],
              cell: true,
              empty: (
                start: at,
                end: at,
                before:
                    '${trimmed.endsWith('|') ? '' : ' |'}${' |' * missing} ',
                after: ' |',
              ),
            ),
          );
        }
      }
      cells.add(row);
    }
    _add(
      _row(
        MarkdownRowKind.table,
        [for (final row in cells) ...row],
        lines,
        context,
        gap,
        table: MarkdownTable(
          cells: cells,
          align: align,
          lines: [for (final line in lines) (line.offset, line.end)],
          prefix: context.prefix,
        ),
      ),
    );
  }
}

/// A table row's cells: each one's range between its pipes, and its
/// content's (its spaces aside), in [line].
List<(int, int, int, int)> _cells(String line) {
  var start = 0;
  var end = line.length;
  while (start < end && _space.hasMatch(line[start])) {
    start++;
  }
  while (end > start && _space.hasMatch(line[end - 1])) {
    end--;
  }
  if (start < end && line[start] == '|') start++;
  if (end > start &&
      line[end - 1] == '|' &&
      (end < 2 || line[end - 2] != r'\')) {
    end--;
  }
  final cells = <(int, int, int, int)>[];
  var cellStart = start;
  void add(int cellEnd) {
    var from = cellStart;
    var to = cellEnd;
    while (from < to && _space.hasMatch(line[from])) {
      from++;
    }
    while (to > from && _space.hasMatch(line[to - 1])) {
      to--;
    }
    cells.add((cellStart, cellEnd, from, to));
  }

  for (var i = start; i < end; i++) {
    if (line[i] == r'\') {
      i++;
    } else if (line[i] == '|') {
      add(i);
      cellStart = i + 1;
    }
  }
  add(end);
  return cells;
}

RegExp? _fenceCloseOf(String content) {
  final match = _fenceOpen.firstMatch(content);
  if (match == null) return null;
  final marker = match[2] ?? match[4]!;
  return RegExp(
    '^ {0,3}${RegExp.escape(marker[0])}{${marker.length},}[ \\t]*\$',
  );
}

final _space = RegExp(r'\s');
final _definition = RegExp(r'^ {0,3}\[([^\]]+)\]:[ \t]*(<[^>]*>|\S+)');
final _atx = RegExp(r' {0,3}(#{1,6})([ \t]+|$)');
final _closingHashes = RegExp(r'(?:^|[ \t]+)#+[ \t]*$');
final _task = RegExp(r'\[([ xX])\](?=[ \t]|$)[ \t]?');
final _quoteMark = RegExp(r' {0,3}>[ \t]?');
final _fenceOpen = RegExp(r'^( {0,3})(?:(`{3,})([^`]*)|(~{3,})(.*))$');
final _mathOpen = RegExp(r' {0,3}(\$\$|\\\[)');
