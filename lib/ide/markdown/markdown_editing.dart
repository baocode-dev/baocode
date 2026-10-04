// What the live preview's keys and commands do to the document, Typora's
// way: Enter splits a paragraph or continues a list (and leaves it on an
// empty item), Backspace at a row's start takes its marks off (a bullet, a
// heading's `#`, a quote's `>`) or joins it to the row before, Tab nests a
// list item, ⌘B wraps the selection in `**`, and so on. Each works on the
// document's rows (markdown_structure.dart) and gives the edits to make
// and where the caret goes after them; typing itself is a unit's edit
// (MarkdownUnit.edit).

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';

import 'markdown_inline.dart';
import 'markdown_structure.dart';

/// The edits a key or command makes ([edits], in the document before
/// them, apart), and the selection after them ([base] to [caret]). Without
/// edits, it only moves the caret.
class MarkdownChange {
  MarkdownChange(this.edits, this.caret, {int? base}) : base = base ?? caret;

  final List<EditorOffsetEdit> edits;
  final int base;
  final int caret;
}

/// Where a caret is: in [unit] of [row], at [offset] of its text.
typedef MarkdownCaret = ({int row, int unit, int offset});

/// [offset] of the document before [edits] (apart), after them: one in a
/// range replaced goes to the end of what replaced it.
int mapThroughEdits(List<EditorOffsetEdit> edits, int offset) {
  var shift = 0;
  for (final edit in edits) {
    if (edit.end <= offset && edit.start < offset) {
      shift += edit.text.length - (edit.end - edit.start);
    } else if (edit.start <= offset && offset < edit.end) {
      return edit.start + shift + edit.text.length;
    }
  }
  return offset + shift;
}

MarkdownChange _change(List<EditorOffsetEdit> edits, int caret) {
  edits.sort((a, b) => a.start.compareTo(b.start));
  return MarkdownChange(edits, caret);
}

/// [edits], the caret at [caret] of the document before them.
MarkdownChange _mapped(List<EditorOffsetEdit> edits, int caret) {
  edits.sort((a, b) => a.start.compareTo(b.start));
  return MarkdownChange(edits, mapThroughEdits(edits, caret));
}

/// The unit before [row]'s [unit], in reading order.
(int, int)? previousMarkdownUnit(
  MarkdownStructure structure,
  int row,
  int unit,
) {
  if (unit > 0) return (row, unit - 1);
  if (row == 0) return null;
  return (row - 1, structure.rows[row - 1].units.length - 1);
}

/// The unit after [row]'s [unit], in reading order.
(int, int)? nextMarkdownUnit(MarkdownStructure structure, int row, int unit) {
  if (unit + 1 < structure.rows[row].units.length) return (row, unit + 1);
  if (row + 1 >= structure.rows.length) return null;
  return (row + 1, 0);
}

bool _flowing(MarkdownRow row) =>
    row.kind == MarkdownRowKind.paragraph ||
    row.kind == MarkdownRowKind.heading;

/// The quotes' marks a row's lines start with (`> > `).
String _quotesOf(MarkdownRow row) => '> ' * row.quotes.length;

/// What separates two paragraphs where [unit] is: an empty line (with its
/// quotes' `>`), then the next line's marks.
String _paragraphBreak(MarkdownStructure structure, MarkdownUnit unit) {
  final prefix = unit.newLine.substring(structure.lineBreak.length);
  return '${structure.lineBreak}${prefix.trimRight()}${unit.newLine}';
}

/// Where, after the marks of the quotes it is in, [line] starts.
int _afterQuotes(MarkdownStructure structure, int line, int quotes) {
  final start = structure.lines.starts[line];
  final text = structure.lines[line];
  var at = 0;
  for (var i = 0; i < quotes; i++) {
    final match = _quoteMark.matchAsPrefix(text, at);
    if (match == null) break;
    at = match.end;
  }
  return start + at;
}

bool _blankLine(MarkdownStructure structure, int line) =>
    structure.lines[line].replaceAll(_quoteMarks, '').trim().isEmpty;

// --- Enter ----------------------------------------------------------------------

/// Enter at [caret] ([soft]: Shift+Enter, a line break in the paragraph).
MarkdownChange? markdownEnter(
  MarkdownStructure structure,
  MarkdownCaret caret, {
  bool soft = false,
}) {
  final row = structure.rows[caret.row];
  final unit = row.units[caret.unit];
  final at = caret.offset;
  MarkdownChange type(String text) {
    final edit = unit.edit(at, at, text);
    return MarkdownChange([edit.edit], edit.end);
  }

  switch (row.kind) {
    case MarkdownRowKind.table:
      return _tableEnter(structure, caret);
    case MarkdownRowKind.code:
      // The line's indent, again.
      final lineStart = at == 0 ? 0 : unit.text.lastIndexOf('\n', at - 1) + 1;
      final indent = _indent.matchAsPrefix(unit.text, lineStart)![0]!;
      return type(
        '\n${indent.length > at - lineStart ? indent.substring(0, at - lineStart) : indent}',
      );
    case MarkdownRowKind.math ||
        MarkdownRowKind.html ||
        MarkdownRowKind.frontMatter ||
        MarkdownRowKind.definition:
      return type('\n');
    case MarkdownRowKind.rule:
      return _paragraphAfter(structure, row);
    case MarkdownRowKind.heading:
      if (unit.text.isEmpty || at == unit.text.length) {
        return _paragraphAfter(structure, row);
      }
      if (at == 0) return _paragraphBefore(structure, row);
      final from = unit.toDocument(at);
      final separator = _paragraphBreak(structure, unit);
      return _change([
        EditorOffsetEdit(from, from, separator),
      ], from + separator.length);
    case MarkdownRowKind.paragraph:
      if (soft) return type('\n');
      if (_openFence(structure, row, unit) case final change?) return change;
      if (row.item != null && caret.unit == 0) {
        return unit.text.isEmpty
            ? _leaveItem(structure, caret.row)
            : _splitItem(structure, row, unit.toDocument(at));
      }
      if (unit.text.isEmpty && row.quotes.isNotEmpty && row.depth == 0) {
        return _leaveQuote(structure, row);
      }
      final from = unit.toDocument(at);
      final separator = _paragraphBreak(structure, unit);
      return _change([
        EditorOffsetEdit(from, from, separator),
      ], from + separator.length);
  }
}

/// An empty paragraph after [row].
MarkdownChange _paragraphAfter(MarkdownStructure structure, MarkdownRow row) {
  final separator = _paragraphBreak(structure, row.units.last);
  return _change([
    EditorOffsetEdit(row.end, row.end, separator),
  ], row.end + separator.length);
}

/// An empty paragraph before [row] (a heading), the caret in it.
MarkdownChange _paragraphBefore(MarkdownStructure structure, MarkdownRow row) {
  final at = row.marker?.$1 ?? row.unit.start;
  final separator = _paragraphBreak(structure, row.unit);
  return _change([EditorOffsetEdit(at, at, separator)], at);
}

/// ```` ```js ```` or `$$` alone on a paragraph's line, then Enter: the
/// code (or TeX) block it opens, closed, the caret in it.
MarkdownChange? _openFence(
  MarkdownStructure structure,
  MarkdownRow row,
  MarkdownUnit unit,
) {
  if (unit.segments.length != 1 || row.item != null) return null;
  final text = unit.text;
  final close = switch (_fenceLine.firstMatch(text)) {
    final match? => match[1]!,
    null => text.trim() == r'$$' ? r'$$' : null,
  };
  if (close == null) return null;
  final end = unit.end;
  final newLine = unit.newLine;
  final insertion = '$newLine$newLine$close';
  return _change([EditorOffsetEdit(end, end, insertion)], end + newLine.length);
}

/// A list item split at [at]: what follows it the next item's.
MarkdownChange _splitItem(
  MarkdownStructure structure,
  MarkdownRow row,
  int at,
) {
  final item = row.item!;
  final text = structure.text;
  final lineStart = structure.lines.starts[row.firstLine];
  final marker = item.ordered
      ? '${item.number! + 1}${item.bullet}'
      : item.bullet;
  final space = text.substring(
    item.markerEnd,
    item.task != null ? item.task! - 1 : item.contentStart,
  );
  final insertion =
      '${structure.lineBreak}${text.substring(lineStart, item.markerStart)}'
      '$marker${space.isEmpty ? ' ' : space}${item.task != null ? '[ ] ' : ''}';
  return _change([EditorOffsetEdit(at, at, insertion)], at + insertion.length);
}

/// Enter on an empty list item: out a level, or out of the list into a
/// paragraph after it.
MarkdownChange? _leaveItem(MarkdownStructure structure, int index) {
  final row = structure.rows[index];
  if (row.depth > 1) {
    return markdownIndentItem(structure, (
      row: index,
      unit: 0,
      offset: 0,
    ), outdent: true);
  }
  final line = row.firstLine;
  final start = structure.lines.starts[line];
  final end = structure.lines.ends[line];
  final marks = _quotesOf(row);
  final blank = marks.trimRight();
  final before = line > 0 && !_blankLine(structure, line - 1);
  final after =
      line + 1 < structure.lines.length && !_blankLine(structure, line + 1);
  final lineBreak = structure.lineBreak;
  final replacement = [
    if (before) blank,
    marks,
    if (after) blank,
  ].join(lineBreak);
  return _change([
    EditorOffsetEdit(start, end, replacement),
  ], start + (before ? blank.length + lineBreak.length : 0) + marks.length);
}

/// Enter on an empty paragraph of a quote: out of it.
MarkdownChange _leaveQuote(MarkdownStructure structure, MarkdownRow row) {
  final line = row.firstLine;
  var start = structure.lines.starts[line];
  final end = structure.lines.ends[line];
  final outer = '> ' * (row.quotes.length - 1);
  // An empty line of the quote before it goes with it.
  if (line > 0 && _blankQuoteLine.hasMatch(structure.lines[line - 1])) {
    start = structure.lines.starts[line - 1];
  }
  final replacement = '${outer.trimRight()}${structure.lineBreak}$outer';
  return _change([
    EditorOffsetEdit(start, end, replacement),
  ], start + replacement.length);
}

// --- Backspace and Delete -----------------------------------------------------

/// Backspace at the start of [caret]'s unit: its row's marks taken off, or
/// the row joined to the one before, or the caret moved there.
MarkdownChange? markdownBackspace(
  MarkdownStructure structure,
  MarkdownCaret caret,
) {
  final row = structure.rows[caret.row];
  final unit = row.units[caret.unit];
  final previous = previousMarkdownUnit(structure, caret.row, caret.unit);
  MarkdownChange? toPrevious() {
    if (previous == null) return null;
    final (r, u) = previous;
    return MarkdownChange(const [], structure.rows[r].units[u].end);
  }

  if (row.kind == MarkdownRowKind.table) return toPrevious();
  if (row.item case final item? when caret.unit == 0) {
    final from = item.task != null ? item.task! - 1 : item.markerStart;
    return _change([EditorOffsetEdit(from, item.contentStart, '')], from);
  }
  if (row.kind == MarkdownRowKind.heading) {
    final (start, end) = row.marker!;
    if (end == unit.start) {
      return _change([EditorOffsetEdit(start, end, '')], start);
    }
    // A setext heading's underline, with the line break before it.
    return _change([EditorOffsetEdit(unit.end, end, '')], unit.start);
  }
  if (row.quotes.isNotEmpty && caret.unit == 0) {
    // Out of the innermost quote, the line.
    final line = structure.lines.lineAt(unit.start);
    final lineStart = structure.lines.starts[line];
    final marks = structure.text.substring(lineStart, unit.start);
    final mark = marks.lastIndexOf('>');
    if (mark >= 0) {
      final from = lineStart + mark;
      final to = from + 1 + (marks.length > mark + 1 ? 1 : 0);
      return _change([EditorOffsetEdit(from, to, '')], from);
    }
  }
  switch (row.kind) {
    case MarkdownRowKind.code ||
        MarkdownRowKind.math ||
        MarkdownRowKind.html ||
        MarkdownRowKind.frontMatter ||
        MarkdownRowKind.definition:
      if (unit.text.isNotEmpty) return toPrevious();
      // An empty block: gone, an empty line for it.
      final start = structure.lines.starts[row.firstLine];
      return _change([
        EditorOffsetEdit(start, structure.lines.ends[row.lastLine], ''),
      ], start);
    case MarkdownRowKind.rule:
      return _change([EditorOffsetEdit(row.start, row.end, '')], row.start);
    case MarkdownRowKind.table || MarkdownRowKind.heading:
      return toPrevious();
    case MarkdownRowKind.paragraph:
      if (previous == null) return null;
      final (r, u) = previous;
      final before = structure.rows[r];
      final end = before.units[u].end;
      if (_flowing(before)) {
        // Joined to it.
        return _change([
          EditorOffsetEdit(end, unit.empty?.end ?? unit.start, ''),
        ], end);
      }
      if (unit.text.isEmpty) {
        // An empty paragraph after a code block (a table…): gone.
        final line = row.firstLine;
        return MarkdownChange([
          EditorOffsetEdit(
            structure.lines.ends[line - 1],
            structure.lines.ends[line],
            '',
          ),
        ], end);
      }
      return toPrevious();
  }
}

/// Delete at the end of [caret]'s unit: the next row joined to it.
MarkdownChange? markdownDelete(
  MarkdownStructure structure,
  MarkdownCaret caret,
) {
  final row = structure.rows[caret.row];
  final unit = row.units[caret.unit];
  final next = nextMarkdownUnit(structure, caret.row, caret.unit);
  if (row.kind == MarkdownRowKind.table || next == null) return null;
  final (r, u) = next;
  final after = structure.rows[r];
  final following = after.units[u];
  if (_flowing(row) && _flowing(after) && after.kind != MarkdownRowKind.table) {
    if (after.kind == MarkdownRowKind.heading &&
        after.marker != null &&
        after.marker!.$2 != following.start) {
      return null;
    }
    return _change([
      EditorOffsetEdit(unit.end, following.empty?.end ?? following.start, ''),
    ], unit.end);
  }
  if (unit.text.isEmpty && row.kind == MarkdownRowKind.paragraph) {
    final line = row.firstLine;
    if (line + 1 >= structure.lines.length) return null;
    final start = structure.lines.starts[line];
    return _change([
      EditorOffsetEdit(start, structure.lines.starts[line + 1], ''),
    ], start);
  }
  return null;
}

// --- Lists ----------------------------------------------------------------------

/// The row starting the list item [index] is in, and the rows after it
/// that are the item's (its other paragraphs, its nested lists).
(int, int)? _itemRows(MarkdownStructure structure, int index) {
  final rows = structure.rows;
  var first = index;
  final depth = rows[index].depth;
  if (depth == 0) return null;
  while (rows[first].item == null || rows[first].depth != depth) {
    if (first == 0 || rows[first].depth < depth) return null;
    first--;
  }
  var last = first;
  while (last + 1 < rows.length) {
    final next = rows[last + 1];
    if (next.depth > depth || (next.depth == depth && next.item == null)) {
      last++;
    } else {
      break;
    }
  }
  return (first, last);
}

/// The column, after its quotes' marks, of [offset] on its line.
int _column(MarkdownStructure structure, MarkdownRow row, int offset) {
  final line = structure.lines.lineAt(offset);
  return offset - _afterQuotes(structure, line, row.quotes.length);
}

/// Tab (Shift+Tab: [outdent]) in a list item: it and what it holds nested
/// in the item before it (out of the item it is in).
MarkdownChange? markdownIndentItem(
  MarkdownStructure structure,
  MarkdownCaret caret, {
  required bool outdent,
}) {
  final rows = structure.rows;
  final range = _itemRows(structure, caret.row);
  if (range == null) return null;
  final (first, last) = range;
  final row = rows[first];
  final item = row.item!;
  final markerColumn = _column(structure, row, item.markerStart);
  int amount;
  if (outdent) {
    if (row.depth < 2) return null;
    var parent = first - 1;
    while (parent >= 0 &&
        (rows[parent].item == null || rows[parent].depth != row.depth - 1)) {
      parent--;
    }
    if (parent < 0) return null;
    amount =
        markerColumn -
        _column(structure, rows[parent], rows[parent].item!.markerStart);
  } else {
    var sibling = first - 1;
    while (sibling >= 0 &&
        !(rows[sibling].item?.list == item.list &&
            rows[sibling].depth == row.depth)) {
      if (rows[sibling].depth < row.depth) return null;
      sibling--;
    }
    if (sibling < 0) return null;
    final previous = rows[sibling].item!;
    amount =
        _column(
          structure,
          rows[sibling],
          previous.task != null ? previous.task! - 1 : previous.contentStart,
        ) -
        markerColumn;
  }
  if (amount <= 0) return null;
  final edits = <EditorOffsetEdit>[];
  for (var line = row.firstLine; line <= rows[last].lastLine; line++) {
    if (structure.lines[line].trim().isEmpty) continue;
    final at = _afterQuotes(structure, line, row.quotes.length);
    if (outdent) {
      final text = structure.text.substring(at, structure.lines.ends[line]);
      final spaces = text.length - text.trimLeft().length;
      final removed = spaces < amount ? spaces : amount;
      if (removed > 0) edits.add(EditorOffsetEdit(at, at + removed, ''));
    } else {
      edits.add(EditorOffsetEdit(at, at, ' ' * amount));
    }
  }
  final unit = rows[caret.row].units[caret.unit];
  return _mapped(edits, unit.toDocument(caret.offset));
}

/// A list's marks for [row] (a paragraph, a heading, an item): a bullet
/// (`- `), a number (`1. `) or a task box (`- [ ] `); taken off when it
/// has them already.
MarkdownChange? markdownToggleList(
  MarkdownStructure structure,
  MarkdownCaret caret, {
  bool ordered = false,
  bool task = false,
}) {
  final row = structure.rows[caret.row];
  final unit = row.units[caret.unit];
  final caretAt = unit.toDocument(caret.offset);
  final marker = ordered ? '1. ' : (task ? '- [ ] ' : '- ');
  final edits = <EditorOffsetEdit>[];
  if (row.item case final item?) {
    final same = item.ordered == ordered && (item.task != null) == task;
    edits.add(
      EditorOffsetEdit(item.markerStart, item.contentStart, same ? '' : marker),
    );
  } else if (_flowing(row)) {
    final start = row.kind == MarkdownRowKind.heading
        ? row.marker!.$1
        : unit.start;
    edits.add(EditorOffsetEdit(start, start, marker));
    // Its other lines, indented to the item's content.
    for (final (from, _) in unit.segments.skip(1)) {
      edits.add(EditorOffsetEdit(from, from, ' ' * marker.length));
    }
  } else {
    return null;
  }
  return _mapped(edits, caretAt);
}

// --- Quotes and headings ----------------------------------------------------------

/// [row] (a paragraph or heading) quoted, or out of its innermost quote.
MarkdownChange? markdownToggleQuote(
  MarkdownStructure structure,
  MarkdownCaret caret,
) {
  final row = structure.rows[caret.row];
  if (!_flowing(row) || row.depth > 0) return null;
  final unit = row.units[caret.unit];
  final caretAt = unit.toDocument(caret.offset);
  final edits = <EditorOffsetEdit>[];
  for (var line = row.firstLine; line <= row.lastLine; line++) {
    final start = structure.lines.starts[line];
    if (row.quotes.isEmpty) {
      edits.add(EditorOffsetEdit(start, start, '> '));
      continue;
    }
    final marks = structure.text.substring(
      start,
      _afterQuotes(structure, line, row.quotes.length),
    );
    final mark = marks.lastIndexOf('>');
    if (mark < 0) continue;
    final to = mark + 1 + (marks.length > mark + 1 ? 1 : 0);
    edits.add(EditorOffsetEdit(start + mark, start + to, ''));
  }
  return _mapped(edits, caretAt);
}

/// [row] (a paragraph or heading) made a heading of [level], or a
/// paragraph (0). Its lines are joined: a heading has one.
MarkdownChange? markdownSetHeading(
  MarkdownStructure structure,
  MarkdownCaret caret,
  int level,
) {
  final row = structure.rows[caret.row];
  if (!_flowing(row) || row.kind == MarkdownRowKind.table) return null;
  if (row.kind == MarkdownRowKind.heading && row.level == level) return null;
  if (row.kind == MarkdownRowKind.paragraph && level == 0) return null;
  final unit = row.units[caret.unit];
  final caretAt = unit.toDocument(caret.offset);
  final marks = level == 0 ? '' : '${'#' * level} ';
  final edits = <EditorOffsetEdit>[];
  if (row.kind == MarkdownRowKind.heading) {
    final (start, end) = row.marker!;
    if (end == unit.start) {
      edits.add(EditorOffsetEdit(start, end, marks));
    } else {
      // Setext: its underline goes, the marks come.
      edits.add(EditorOffsetEdit(unit.end, end, ''));
      edits.add(EditorOffsetEdit(unit.start, unit.start, marks));
    }
  } else {
    edits.add(EditorOffsetEdit(unit.start, unit.start, marks));
  }
  if (level > 0) {
    for (var i = 1; i < unit.segments.length; i++) {
      edits.add(
        EditorOffsetEdit(unit.segments[i - 1].$2, unit.segments[i].$1, ' '),
      );
    }
  }
  return _mapped(edits, caretAt);
}

// --- Inline marks -------------------------------------------------------------------

/// What [mark] (`**`, `*`, `~~`, `` ` ``) makes.
MarkdownInlineKind _markKind(String mark) => switch (mark) {
  '**' => MarkdownInlineKind.strong,
  '*' || '_' => MarkdownInlineKind.emphasis,
  '~~' => MarkdownInlineKind.strike,
  _ => MarkdownInlineKind.code,
};

/// ⌘B and its like: [start, end) of [caret]'s unit wrapped in [mark], or
/// taken out of the element of its kind it is in.
MarkdownChange? markdownToggleInline(
  MarkdownStructure structure,
  MarkdownCaret caret,
  int start,
  int end,
  String mark,
) {
  final row = structure.rows[caret.row];
  if (!_flowing(row) && row.kind != MarkdownRowKind.table) return null;
  final unit = row.units[caret.unit];
  final text = unit.text;
  final kind = _markKind(mark);
  final inlines = flattenMarkdownInlines(
    parseMarkdownInlines(text, references: structure.references),
  );
  MarkdownInline? around;
  for (final inline in inlines) {
    if (inline.kind != kind) continue;
    final within = start >= inline.contentStart && end <= inline.contentEnd;
    final whole = start == inline.start && end == inline.end;
    if (within || whole) around = inline;
  }
  if (around != null) {
    final edits = [
      unit.edit(around.start, around.contentStart, '').edit,
      unit.edit(around.contentEnd, around.end, '').edit,
    ];
    return MarkdownChange(
      edits,
      mapThroughEdits(edits, unit.toDocument(end)),
      base: mapThroughEdits(edits, unit.toDocument(start)),
    );
  }
  // White space at its ends stays out.
  var from = start;
  var to = end;
  while (from < to && text[from].trim().isEmpty) {
    from++;
  }
  while (to > from && text[to - 1].trim().isEmpty) {
    to--;
  }
  final wrap =
      kind == MarkdownInlineKind.code && text.substring(from, to).contains('`')
      ? '``'
      : mark;
  final opening = unit.edit(from, from, wrap).edit;
  final closing = unit.edit(to, to, wrap).edit;
  final edits = [opening, if (from != to) closing];
  if (from == to) {
    // Nothing selected: both marks, the caret between them.
    final both = unit.edit(from, from, '$wrap$wrap').edit;
    return MarkdownChange([both], both.start + wrap.length);
  }
  return MarkdownChange(
    edits,
    closing.start + wrap.length,
    base: opening.start + wrap.length,
  );
}

// --- Blocks -------------------------------------------------------------------------

enum MarkdownBlockInsert { table, code, math, rule }

/// A new block of [kind] where [caret] is: in its empty paragraph, or
/// after its row; the caret in it.
MarkdownChange markdownInsertBlock(
  MarkdownStructure structure,
  MarkdownCaret caret,
  MarkdownBlockInsert kind,
) {
  final row = structure.rows[caret.row];
  final unit = row.units.last;
  final newLine = unit.newLine;
  final lines = switch (kind) {
    MarkdownBlockInsert.table => ['|  |  |', '| --- | --- |', '|  |  |'],
    MarkdownBlockInsert.code => ['```', '```'],
    MarkdownBlockInsert.math => [r'$$', r'$$'],
    MarkdownBlockInsert.rule => ['---', ''],
  };
  final block = lines.join(newLine);
  // Where in it the caret goes.
  final inside = switch (kind) {
    MarkdownBlockInsert.table => 1,
    MarkdownBlockInsert.code ||
    MarkdownBlockInsert.math => lines.first.length + newLine.length,
    MarkdownBlockInsert.rule => block.length,
  };
  final empty =
      row.kind == MarkdownRowKind.paragraph &&
      row.item == null &&
      row.unit.text.isEmpty &&
      row.unit.empty != null;
  if (empty) {
    final at = row.unit.empty!;
    return _change([
      EditorOffsetEdit(at.start, at.end, block),
    ], at.start + inside);
  }
  final separator = _paragraphBreak(structure, unit);
  return _change([
    EditorOffsetEdit(row.end, row.end, '$separator$block'),
  ], row.end + separator.length + inside);
}

// --- Tables -------------------------------------------------------------------------

enum MarkdownTableEdit {
  rowAbove,
  rowBelow,
  columnLeft,
  columnRight,
  deleteRow,
  deleteColumn,
  alignLeft,
  alignCenter,
  alignRight,
  deleteTable,
}

/// The cell [unit] of a table row is: its row (the header's 0) and column.
(int, int) markdownCell(MarkdownTable table, int unit) =>
    (unit ~/ table.columns, unit % table.columns);

/// Enter in a cell: the cell below, a new row's after the last.
MarkdownChange _tableEnter(MarkdownStructure structure, MarkdownCaret caret) {
  final row = structure.rows[caret.row];
  final table = row.table!;
  final (r, c) = markdownCell(table, caret.unit);
  if (r + 1 < table.cells.length) {
    final below = table.cells[r + 1][c];
    return MarkdownChange(const [], below.end);
  }
  return markdownEditTable(structure, caret, MarkdownTableEdit.rowBelow)!;
}

/// [edit] of the table [caret] is in; the caret where the edit leaves it.
/// The table is written anew, its columns lined up.
MarkdownChange? markdownEditTable(
  MarkdownStructure structure,
  MarkdownCaret caret,
  MarkdownTableEdit edit,
) {
  final row = structure.rows[caret.row];
  final table = row.table;
  if (table == null) return null;
  var (r, c) = markdownCell(table, caret.unit);
  final cells = [
    for (final cells in table.cells) [for (final cell in cells) cell.text],
  ];
  final align = [...table.align];
  final columns = table.columns;
  switch (edit) {
    case MarkdownTableEdit.rowAbove:
      // Not above the header: below it.
      final at = r == 0 ? 1 : r;
      cells.insert(at, List.filled(columns, ''));
      r = at;
    case MarkdownTableEdit.rowBelow:
      cells.insert(r + 1, List.filled(columns, ''));
      r++;
    case MarkdownTableEdit.columnLeft || MarkdownTableEdit.columnRight:
      final at = edit == MarkdownTableEdit.columnLeft ? c : c + 1;
      for (final cells in cells) {
        cells.insert(at, '');
      }
      align.insert(at, null);
      c = at;
    case MarkdownTableEdit.deleteRow:
      if (r == 0) {
        return markdownEditTable(
          structure,
          caret,
          MarkdownTableEdit.deleteTable,
        );
      }
      cells.removeAt(r);
      if (r >= cells.length) r = cells.length - 1;
    case MarkdownTableEdit.deleteColumn:
      if (columns == 1) {
        return markdownEditTable(
          structure,
          caret,
          MarkdownTableEdit.deleteTable,
        );
      }
      for (final cells in cells) {
        cells.removeAt(c);
      }
      align.removeAt(c);
      if (c >= align.length) c = align.length - 1;
    case MarkdownTableEdit.alignLeft:
      align[c] = align[c] == 'left' ? null : 'left';
    case MarkdownTableEdit.alignCenter:
      align[c] = align[c] == 'center' ? null : 'center';
    case MarkdownTableEdit.alignRight:
      align[c] = align[c] == 'right' ? null : 'right';
    case MarkdownTableEdit.deleteTable:
      final start = structure.lines.starts[row.firstLine];
      return _change([
        EditorOffsetEdit(start, structure.lines.ends[row.lastLine], ''),
      ], start);
  }
  final (text, offsets) = _writeTable(
    cells,
    align,
    '${structure.lineBreak}${table.prefix}',
  );
  final start = table.lines.first.$1;
  return _change([
    EditorOffsetEdit(start, table.lines.last.$2, text),
  ], start + offsets[r][c]);
}

/// [cells] (the header's first) as a table's lines, joined by [newLine],
/// and where each cell's text ends in it.
(String, List<List<int>>) _writeTable(
  List<List<String>> cells,
  List<String?> align,
  String newLine,
) {
  final columns = align.length;
  final widths = List.filled(columns, 3);
  for (final row in cells) {
    for (var c = 0; c < columns; c++) {
      final width = _displayWidth(row[c]);
      if (width > widths[c]) widths[c] = width;
    }
  }
  final buffer = StringBuffer();
  final offsets = <List<int>>[];
  void writeRow(List<String> row) {
    final ends = <int>[];
    buffer.write('|');
    for (var c = 0; c < columns; c++) {
      buffer.write(' ');
      buffer.write(row[c]);
      ends.add(buffer.length);
      buffer.write(' ' * (widths[c] - _displayWidth(row[c])));
      buffer.write(' |');
    }
    offsets.add(ends);
  }

  for (final (index, row) in cells.indexed) {
    if (index > 0) buffer.write(newLine);
    writeRow(row);
    if (index == 0) {
      buffer.write(newLine);
      buffer.write('|');
      for (var c = 0; c < columns; c++) {
        final width = widths[c];
        buffer.write(' ');
        buffer.write(switch (align[c]) {
          'left' => ':${'-' * (width - 1)}',
          'center' => ':${'-' * (width - 2)}:',
          'right' => '${'-' * (width - 1)}:',
          _ => '-' * width,
        });
        buffer.write(' |');
      }
    }
  }
  return (buffer.toString(), offsets);
}

/// Columns [text] takes in a monospaced font: East Asian wide characters
/// two.
int _displayWidth(String text) {
  var width = 0;
  for (final rune in text.runes) {
    width += _wide(rune) ? 2 : 1;
  }
  return width;
}

bool _wide(int rune) =>
    (rune >= 0x1100 && rune <= 0x115F) ||
    (rune >= 0x2E80 && rune <= 0xA4CF) ||
    (rune >= 0xAC00 && rune <= 0xD7A3) ||
    (rune >= 0xF900 && rune <= 0xFAFF) ||
    (rune >= 0xFE30 && rune <= 0xFE4F) ||
    (rune >= 0xFF00 && rune <= 0xFF60) ||
    (rune >= 0xFFE0 && rune <= 0xFFE6) ||
    (rune >= 0x1F300 && rune <= 0x1FAFF) ||
    (rune >= 0x20000 && rune <= 0x3FFFD);

final _quoteMark = RegExp(r' {0,3}>[ \t]?');
final _quoteMarks = RegExp(r'^(?: {0,3}>[ \t]?)*');
final _blankQuoteLine = RegExp(r'^(?: {0,3}>[ \t]?)+\s*$');
final _indent = RegExp(r'[ \t]*');
final _fenceLine = RegExp(r'^ {0,3}(`{3,}|~{3,})[^`]*$');
