import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, listEquals;
import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../md_blocks.dart';
import '../md_controller.dart';
import '../md_format.dart';
import '../md_inline.dart';
import 'md_display.dart';
import 'md_editor.dart';
import 'md_embeds.dart';
import 'md_style.dart';

/// A table's rows (its head first; not its delimiter row), each its
/// cells' text, and how each column is aligned.
({List<List<String>> rows, List<TextAlign> aligns}) parseTable(String source) {
  final lines = source
      .split('\n')
      .map((line) => line.trimRight())
      .where((line) => line.isNotEmpty)
      .toList();
  final rows = <List<String>>[];
  var aligns = <TextAlign>[];
  for (var i = 0; i < lines.length; i++) {
    final cells = tableCells(lines[i]);
    if (i == 1) {
      aligns = [
        for (final cell in cells)
          switch ((cell.startsWith(':'), cell.endsWith(':'))) {
            (true, true) => TextAlign.center,
            (false, true) => TextAlign.right,
            _ => TextAlign.left,
          },
      ];
      continue;
    }
    rows.add(cells);
  }
  return (rows: rows, aligns: aligns);
}

/// A table's row split at its `|`s (not an escaped one, nor one in
/// code), the cells trimmed.
List<String> tableCells(String row) {
  var text = row.trim();
  if (text.startsWith('|')) text = text.substring(1);
  if (text.endsWith('|') && !text.endsWith(r'\|')) {
    text = text.substring(0, text.length - 1);
  }
  final cells = <String>[];
  final cell = StringBuffer();
  var code = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == r'\' && i + 1 < text.length && text[i + 1] == '|') {
      cell.write('|');
      i++;
      continue;
    }
    if (char == '`') {
      var ticks = 0;
      while (i + ticks < text.length && text[i + ticks] == '`') {
        ticks++;
      }
      cell.write('`' * ticks);
      i += ticks - 1;
      code = code == 0 ? ticks : (code == ticks ? 0 : code);
      continue;
    }
    if (char == '|' && code == 0) {
      cells.add(cell.toString().trim());
      cell.clear();
      continue;
    }
    cell.write(char);
  }
  cells.add(cell.toString().trim());
  return cells;
}

/// Where each cell's text is in [row] (from [from] on: before it what is
/// not the table's, a quote's `>`), trimmed; an empty one's just after
/// the space after its `|`.
List<TextRange> tableCellRanges(String row, [int from = 0]) {
  final pipes = <int>[];
  var code = 0;
  for (var i = from; i < row.length; i++) {
    final char = row[i];
    if (char == r'\') {
      i++;
      continue;
    }
    if (char == '`') {
      var ticks = 0;
      while (i + ticks < row.length && row[i + ticks] == '`') {
        ticks++;
      }
      i += ticks - 1;
      code = code == 0 ? ticks : (code == ticks ? 0 : code);
      continue;
    }
    if (char == '|' && code == 0) pipes.add(i);
  }
  bool blank(int at) => row[at] == ' ' || row[at] == '\t';
  var first = from;
  while (first < row.length && blank(first)) {
    first++;
  }
  var last = row.length;
  while (last > first && blank(last - 1)) {
    last--;
  }
  var start = from;
  var end = row.length;
  if (pipes.isNotEmpty && pipes.first == first) start = pipes.removeAt(0) + 1;
  if (pipes.isNotEmpty && pipes.last == last - 1) end = pipes.removeLast();
  final ranges = <TextRange>[];
  var segment = start;
  for (final pipe in [...pipes, end]) {
    var a = segment;
    var b = pipe;
    while (a < b && blank(a)) {
      a++;
    }
    while (b > a && blank(b - 1)) {
      b--;
    }
    if (a == b) a = b = math.min(segment + 1, pipe);
    ranges.add(TextRange(start: a, end: b));
    segment = pipe + 1;
  }
  return ranges;
}

/// What a table's menus do, to a row, a column or the table.
enum MdTableAction {
  insertRowAbove,
  insertRowBelow,
  duplicateRow,
  moveRowUp,
  moveRowDown,
  clearRow,
  deleteRow,
  insertColumnLeft,
  insertColumnRight,
  duplicateColumn,
  moveColumnLeft,
  moveColumnRight,
  alignLeft,
  alignCenter,
  alignRight,
  clearColumn,
  deleteColumn,
  deleteTable;

  /// Its name, in English (see [MarkdownEmbeds.tableMenu]).
  String get label => switch (this) {
    insertRowAbove => 'Insert row above',
    insertRowBelow => 'Insert row below',
    duplicateRow => 'Duplicate row',
    moveRowUp => 'Move row up',
    moveRowDown => 'Move row down',
    clearRow => 'Clear row',
    deleteRow => 'Delete row',
    insertColumnLeft => 'Insert column left',
    insertColumnRight => 'Insert column right',
    duplicateColumn => 'Duplicate column',
    moveColumnLeft => 'Move column left',
    moveColumnRight => 'Move column right',
    alignLeft => 'Align left',
    alignCenter => 'Align center',
    alignRight => 'Align right',
    clearColumn => 'Clear column',
    deleteColumn => 'Delete column',
    deleteTable => 'Delete table',
  };
}

/// A table of a [MarkdownController]'s text, as written: its lines, what
/// is before its rows (a quote's `> `), its rows' cells (its head first,
/// not its delimiter row) and its columns' alignments (null: none).
class MdTableData {
  MdTableData._(this.first, this.last, this.prefix, this.rows, this.aligns);

  /// The table whose head is the line of id [lineId]; null where there is
  /// none.
  static MdTableData? read(MarkdownController controller, int lineId) {
    final first = controller.lines.indexOfId(lineId);
    if (first < 0 || controller.infoOf(first).kind != MdLineKind.tableHead) {
      return null;
    }
    final (_, last) = controller.blockOf(first);
    final info = controller.infoOf(first);
    final head = controller.lines.content(first);
    final prefix = head.substring(0, info.contentStart);
    final rows = <List<String>>[];
    var aligns = <TextAlign?>[];
    for (var line = first; line <= last; line++) {
      final text = controller.lines.content(line);
      final from = controller.infoOf(line).contentStart;
      final cells = [
        for (final range in tableCellRanges(text, from))
          text.substring(range.start, range.end),
      ];
      if (line == first + 1) {
        aligns = [
          for (final cell in cells)
            switch ((cell.startsWith(':'), cell.endsWith(':'))) {
              (true, true) => TextAlign.center,
              (true, false) => TextAlign.left,
              (false, true) => TextAlign.right,
              _ => null,
            },
        ];
        continue;
      }
      rows.add(cells);
    }
    return MdTableData._(first, last, prefix, rows, aligns);
  }

  final int first;
  final int last;
  final String prefix;
  final List<List<String>> rows;
  final List<TextAlign?> aligns;

  int get columns => rows.fold(
    aligns.length,
    (most, row) => row.length > most ? row.length : most,
  );

  /// The line of row [row] (its head's 0).
  int lineOf(int row) => row == 0 ? first : first + 1 + row;

  /// Every row as many cells as there are columns, every column an
  /// alignment (null).
  void fill() {
    final count = columns;
    for (final cells in rows) {
      while (cells.length < count) {
        cells.add('');
      }
    }
    while (aligns.length < count) {
      aligns.add(null);
    }
  }

  /// Written again: every row as many cells as there are columns.
  String write(String newline) {
    fill();
    String row(List<String> cells) => '$prefix| ${cells.join(' | ')} |';
    final delimiter = [
      for (final align in aligns)
        switch (align) {
          TextAlign.left => ':---',
          TextAlign.center => ':---:',
          TextAlign.right => '---:',
          _ => '---',
        },
    ];
    return [
      row(rows.first),
      '$prefix| ${delimiter.join(' | ')} |',
      for (final cells in rows.skip(1)) row(cells),
    ].join(newline);
  }
}

/// A table's cells and its rows and columns edited in a controller's text,
/// each change a step of Undo's. Rows count from the head's 0: one put
/// before it, or moved there, is the head then.
extension MarkdownTableEditing on MarkdownController {
  /// Where the text of row [row]'s cell [column] is, in the table whose
  /// head is the line of id [lineId]; null where it has none.
  TextRange? tableCellRange(int lineId, int row, int column) {
    final first = lines.indexOfId(lineId);
    if (first < 0 || infoOf(first).kind != MdLineKind.tableHead) return null;
    final (_, last) = blockOf(first);
    final line = row == 0 ? first : first + 1 + row;
    if (row < 0 || line > last || column < 0) return null;
    final ranges = tableCellRanges(
      lines.content(line),
      infoOf(line).contentStart,
    );
    if (column >= ranges.length) return null;
    final start = lineStart(line);
    return TextRange(
      start: start + ranges[column].start,
      end: start + ranges[column].end,
    );
  }

  /// The table changed by [change] (its rows and alignments, filled out
  /// first), written again in one step.
  void _changeTable(int lineId, void Function(MdTableData table) change) {
    final table = MdTableData.read(this, lineId);
    if (table == null) return;
    table.fill();
    change(table);
    final text = table.write(lines.newline);
    final start = lineStart(table.first);
    breakUndo();
    replace(
      start,
      lineEnd(table.last),
      text,
      selection: TextSelection.collapsed(offset: start),
    );
    breakUndo();
  }

  /// An empty row put in as row [row].
  void insertTableRow(int lineId, int row) => _changeTable(lineId, (table) {
    table.rows.insert(
      row.clamp(0, table.rows.length),
      List.filled(table.columns, ''),
    );
  });

  /// Row [row] taken out (not the last one left).
  void deleteTableRow(int lineId, int row) => _changeTable(lineId, (table) {
    if (table.rows.length > 1 && row >= 0 && row < table.rows.length) {
      table.rows.removeAt(row);
    }
  });

  /// Row [from] put in as row [to].
  void moveTableRow(int lineId, int from, int to) =>
      _changeTable(lineId, (table) {
        final rows = table.rows;
        if (from < 0 || from >= rows.length) return;
        rows.insert(to.clamp(0, rows.length - 1), rows.removeAt(from));
      });

  /// A copy of row [row] after it.
  void duplicateTableRow(int lineId, int row) => _changeTable(lineId, (table) {
    if (row < 0 || row >= table.rows.length) return;
    table.rows.insert(row + 1, [...table.rows[row]]);
  });

  /// Row [row]'s cells emptied.
  void clearTableRow(int lineId, int row) => _changeTable(lineId, (table) {
    if (row < 0 || row >= table.rows.length) return;
    table.rows[row] = List.filled(table.columns, '');
  });

  /// An empty column put in as column [column].
  void insertTableColumn(int lineId, int column) =>
      _changeTable(lineId, (table) {
        final at = column.clamp(0, table.columns);
        for (final cells in table.rows) {
          cells.insert(at, '');
        }
        table.aligns.insert(at, null);
      });

  /// Column [column] taken out; the table, with its last.
  void deleteTableColumn(int lineId, int column) {
    final table = MdTableData.read(this, lineId);
    if (table == null) return;
    if (table.columns <= 1) return deleteTable(lineId);
    _changeTable(lineId, (table) {
      if (column < 0 || column >= table.columns) return;
      for (final cells in table.rows) {
        cells.removeAt(column);
      }
      table.aligns.removeAt(column);
    });
  }

  /// Column [from] put in as column [to].
  void moveTableColumn(int lineId, int from, int to) =>
      _changeTable(lineId, (table) {
        final count = table.columns;
        if (from < 0 || from >= count) return;
        final at = to.clamp(0, count - 1);
        for (final cells in table.rows) {
          cells.insert(at, cells.removeAt(from));
        }
        table.aligns.insert(at, table.aligns.removeAt(from));
      });

  /// A copy of column [column] after it.
  void duplicateTableColumn(int lineId, int column) =>
      _changeTable(lineId, (table) {
        if (column < 0 || column >= table.columns) return;
        for (final cells in table.rows) {
          cells.insert(column + 1, cells[column]);
        }
        table.aligns.insert(column + 1, table.aligns[column]);
      });

  /// Column [column]'s cells emptied.
  void clearTableColumn(int lineId, int column) =>
      _changeTable(lineId, (table) {
        if (column < 0 || column >= table.columns) return;
        for (final cells in table.rows) {
          cells[column] = '';
        }
      });

  /// The cells from row [top]'s column [left] to row [bottom]'s column
  /// [right] emptied.
  void clearTableCells(int lineId, int top, int left, int bottom, int right) =>
      _changeTable(lineId, (table) {
        for (var r = math.max(0, top); r <= bottom; r++) {
          if (r >= table.rows.length) break;
          for (var c = math.max(0, left); c <= right; c++) {
            if (c >= table.columns) break;
            table.rows[r][c] = '';
          }
        }
      });

  /// [cells] (rows of a cell's text each, as copied: a `|` in it not
  /// escaped) put in over those from row [row]'s column [column] on; rows
  /// and columns put in first where the table ends before them.
  void pasteTableCells(
    int lineId,
    int row,
    int column,
    List<List<String>> cells,
  ) => _changeTable(lineId, (table) {
    if (row < 0 || column < 0) return;
    final width = cells.fold(0, (most, cells) => math.max(most, cells.length));
    final columns = math.max(table.columns, column + width);
    while (table.rows.length < row + cells.length) {
      table.rows.add([]);
    }
    for (final cells in table.rows) {
      while (cells.length < columns) {
        cells.add('');
      }
    }
    while (table.aligns.length < columns) {
      table.aligns.add(null);
    }
    for (var r = 0; r < cells.length; r++) {
      for (var c = 0; c < cells[r].length; c++) {
        table.rows[row + r][column + c] = cells[r][c]
            .replaceAll(RegExp(r'[\r\n]+'), ' ')
            .trim()
            .replaceAll(r'\|', '|')
            .replaceAll('|', r'\|');
      }
    }
  });

  /// Column [column] aligned [align].
  void alignTableColumn(int lineId, int column, TextAlign align) =>
      _changeTable(lineId, (table) {
        if (column >= 0 && column < table.columns) {
          table.aligns[column] = align;
        }
      });

  /// The table taken out, the lines around it kept.
  void deleteTable(int lineId) {
    final table = MdTableData.read(this, lineId);
    if (table == null) return;
    // From its start to the next line's, or from the end of the line
    // before it at the text's end.
    final end = table.last + 1 < lines.lineCount
        ? lineStart(table.last + 1)
        : length;
    final start = end == length && table.first > 0
        ? lineEnd(table.first - 1)
        : lineStart(table.first);
    breakUndo();
    replace(start, end, '', selection: TextSelection.collapsed(offset: start));
    breakUndo();
  }

  /// Row [row] given as many cells as the table has columns, where it has
  /// fewer (a step of its own).
  void _fillTableRow(int lineId, int row) {
    final table = MdTableData.read(this, lineId);
    if (table == null || row >= table.rows.length) return;
    if (table.rows[row].length >= table.columns) return;
    final line = table.lineOf(row);
    final cells = [
      for (var c = 0; c < table.columns; c++)
        c < table.rows[row].length ? table.rows[row][c] : '',
    ];
    final text = '${table.prefix}| ${cells.join(' | ')} |';
    breakUndo();
    replace(lineStart(line), lineEnd(line), text, selection: selection);
    breakUndo();
  }
}

/// A table being edited: the caret put in it (by the keys, Undo…) goes
/// into the cell it is in (see [MarkdownEditorState.attachTable]).
abstract interface class MdTableEditing {
  /// Into the cell [offset] (of the editor's text) is in.
  void focusAt(int offset);

  /// The editor of the cell being typed in; none while none is.
  MarkdownEditorState? get cellEditor;

  /// While held, the cell being typed in stays open without the keyboard.
  set cellHeld(bool held);
}

/// A table as it shows. With [embed] (in an editor that may change its
/// text), edited as one: a cell clicked is typed in, as it shows; Tab and
/// Enter go on to the next, the arrows across. Over it, a row's and a
/// column's handles: clicked, their menu; dragged, the row (column) moved.
/// Beside it, bars that add a row and a column; a cell right-clicked, a
/// menu of both.
class MdTable extends StatefulWidget {
  const MdTable({
    super.key,
    required this.source,
    required this.style,
    this.cell,
    this.embed,
  });

  /// Its markdown.
  final String source;
  final MarkdownEditorStyle style;

  /// What a cell's text shows as; its runs without their marks by default.
  final InlineSpan Function(String text, TextStyle style)? cell;

  /// Where it is in its editor's text, to edit it there.
  final MdBlockEmbed? embed;

  @override
  State<MdTable> createState() => _MdTableState();
}

/// A row's or a column's handle being dragged: which, and where it would
/// go (before row or column [to]).
typedef _Drag = ({bool row, int from, int to});

/// Cells outlined as one, from row [top]'s column [left] to row
/// [bottom]'s column [right]; their ground tinted where [tint].
typedef _Region = ({int top, int left, int bottom, int right, bool tint});

/// Where the columns of [widths] start, and the last ends.
List<double> _edges(List<double> widths) {
  final edges = [0.0];
  for (final width in widths) {
    edges.add(edges.last + width);
  }
  return edges;
}

class _MdTableState extends State<MdTable> implements MdTableEditing {
  MarkdownEditorState? _host;
  int? _attachedId;

  /// The cell being typed in: its row (the head's 0) and column.
  (int, int)? _cell;
  MarkdownController? _cellController;
  final _cellFocus = FocusNode(debugLabel: 'table cell');
  final _cellKey = GlobalKey<MarkdownEditorState>();
  final _tableKey = GlobalKey();

  /// Cells picked as a spreadsheet's are, the mouse dragged across them
  /// (or the arrows with Shift): from [_from]'s row and column to [_to]'s,
  /// none of them typed in.
  (int, int)? _from;
  (int, int)? _to;
  late final _cellsFocus = FocusNode(
    debugLabel: 'table cells',
    onKeyEvent: _cellsKeyEvent,
  );

  /// The mouse pressed in the table: the cell it went down in, and whether
  /// that was opened by it (its text picked as it is dragged on then).
  int? _pressPointer;
  (int, int)? _pressCell;
  bool _pressOpened = false;

  /// The caret not put in the cell opened yet (see [_open]).
  bool _placing = false;

  /// The row and column the pointer is over, for their handles.
  int? _hoverRow;
  int? _hoverColumn;
  bool _hovered = false;

  /// The row or column a menu is open for (shown picked), or dragged.
  ({bool row, int index})? _picked;
  _Drag? _drag;
  bool _menuOpen = false;

  /// The columns' widths, as last laid out.
  List<double> _widths = const [];

  /// The table scrolled sideways, where it is wider than its room.
  final _sideways = ScrollController();

  static const _padding = EdgeInsets.symmetric(horizontal: 12, vertical: 7);

  /// Above the table: room for the columns' handles, on its edge.
  static const _top = 8.0;

  /// Left of it: room for the rows' handles, on its edge.
  static const _side = 6.0;

  /// The bars beside it, and the room between them and it.
  static const _bar = 14.0;
  static const _barGap = 6.0;

  MarkdownController? get _controller => widget.embed?.controller;
  int? get _id => widget.embed?.lineId;

  bool get _editable {
    final host = _host;
    return widget.embed != null && host != null && !host.widget.readOnly;
  }

  @override
  void initState() {
    super.initState();
    _cellFocus.addListener(_cellFocusChanged);
    _cellsFocus.addListener(_cellsFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attach();
  }

  @override
  void didUpdateWidget(MdTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _attach();
    // Its row (or the table) gone: nothing typed in.
    if (_cell case (final row, final column)?) {
      final controller = _controller;
      final id = _id;
      if (controller == null ||
          id == null ||
          controller.tableCellRange(id, row, column) == null) {
        _closeCell();
      }
    }
    // Cells gone from under those picked: none picked.
    if ((_from, _to) case ((final r0, final c0)?, (final r1, final c1)?)) {
      final table = _read();
      if (table == null ||
          math.max(r0, r1) >= table.rows.length ||
          math.max(c0, c1) >= table.columns) {
        _from = _to = null;
      }
    }
  }

  void _attach() {
    final host = context.findAncestorStateOfType<MarkdownEditorState>();
    final id = _id;
    if (identical(host, _host) && id == _attachedId) return;
    if (_attachedId case final old?) _host?.detachTable(old, this);
    _host = host;
    _attachedId = id;
    if (id != null) host?.attachTable(id, this);
  }

  @override
  void dispose() {
    if (_attachedId case final id?) _host?.detachTable(id, this);
    _cellFocus.dispose();
    _cellsFocus.dispose();
    _sideways.dispose();
    final controller = _cellController;
    if (controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    }
    super.dispose();
  }

  MdTableData? _read() {
    final controller = _controller;
    final id = _id;
    if (controller == null || id == null) return null;
    return MdTableData.read(controller, id);
  }

  // --- The cell typed in ------------------------------------------------------------

  @override
  MarkdownEditorState? get cellEditor {
    final editor = _cellKey.currentState;
    final cell = _cellController;
    return cell != null && identical(editor?.controller, cell) ? editor : null;
  }

  /// The cell kept open without the keyboard (see [cellHeld]).
  bool _held = false;

  @override
  set cellHeld(bool held) {
    if (_held == held) return;
    _held = held;
    if (!held) _cellFocusChanged();
  }

  void _cellChanged() => _host?.tableCellChanged();

  @override
  void focusAt(int offset) {
    final controller = _controller;
    final table = _read();
    if (controller == null || table == null || !_editable) return;
    final line = controller.lineAt(offset).clamp(table.first, table.last);
    // On the delimiter row: the head's.
    final row = line == table.first
        ? 0
        : math.max(0, math.min(line - table.first - 1, table.rows.length - 1));
    final text = controller.lines.content(table.lineOf(row));
    final ranges = tableCellRanges(
      text,
      controller.infoOf(table.lineOf(row)).contentStart,
    );
    final column = offset - controller.lineStart(table.lineOf(row));
    var index = ranges.indexWhere((range) => column <= range.end);
    if (index < 0) index = math.max(0, ranges.length - 1);
    final range = ranges.isEmpty ? null : ranges[index];
    _open(
      row,
      index,
      caret: range == null
          ? 0
          : (column - range.start).clamp(0, range.end - range.start),
    );
  }

  /// Row [row]'s cell [column] typed in, the caret at [caret] (its end
  /// with [end]; where [at] is, on the screen).
  void _open(int row, int column, {int? caret, bool end = false, Offset? at}) {
    final controller = _controller;
    final id = _id;
    if (controller == null || id == null) return;
    var range = controller.tableCellRange(id, row, column);
    if (range == null) {
      controller._fillTableRow(id, row);
      range = controller.tableCellRange(id, row, column);
      if (range == null) return;
    }
    if (_from != null) setState(() => _from = _to = null);
    final moved = _cell != (row, column) || _cellController == null;
    if (moved) {
      final old = _cellController;
      _cellController = MarkdownController.of(
        _CellSource(controller, id, row, column),
        inline: true,
      )..addListener(_cellChanged);
      if (old != null) {
        old.removeListener(_cellChanged);
        WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
      }
      setState(() => _cell = (row, column));
      _cellChanged();
    }
    final cell = _cellController!;
    void place() {
      if (!mounted || _cell != (row, column)) return;
      _placing = false;
      var offset = caret ?? (end ? cell.length : 0);
      if (at != null) offset = _cellKey.currentState?.offsetAt(at) ?? offset;
      cell.selection = TextSelection.collapsed(
        offset: offset.clamp(0, cell.length),
      );
      _cellFocus.requestFocus();
    }

    // Into another cell: placed once its editor is laid out there (the
    // one it was in, until then).
    if (moved || _cellKey.currentState == null) {
      _placing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => place());
    } else {
      place();
    }
  }

  void _closeCell() {
    final old = _cellController;
    if (old == null && _cell == null) return;
    _cellController = null;
    _cell = null;
    _held = false;
    if (old != null) {
      old.removeListener(_cellChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    if (mounted) setState(() {});
    _cellChanged();
  }

  /// The cell left (clicked elsewhere): shown again.
  void _cellFocusChanged() {
    _cellChanged();
    if (_cellFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_cellFocus.hasFocus && !_menuOpen && !_held) {
        _closeCell();
      }
    });
  }

  /// Out of the table, the caret before it or after it ([after]; a line
  /// made for it where there is none).
  void _leave({required bool after}) {
    final controller = _controller;
    final host = _host;
    final table = _read();
    if (controller == null || host == null || table == null) return;
    int offset;
    if (after) {
      if (table.last + 1 < controller.lines.lineCount) {
        offset = controller.lineStart(table.last + 1);
      } else {
        offset = controller.length;
        controller.replace(offset, offset, controller.lines.newline);
        offset = controller.length;
      }
    } else {
      if (table.first == 0) return;
      offset = controller.lineEnd(table.first - 1);
    }
    controller.selection = TextSelection.collapsed(offset: offset);
    host.requestFocus();
    _closeCell();
  }

  /// The cell [by] cells on (across, then down), a row put in after the
  /// last where [grow].
  void _step(int by, {bool grow = false}) {
    final (row, column) = _cell!;
    final table = _read();
    if (table == null) return;
    final columns = table.columns;
    var index = row * columns + column + by;
    if (index < 0) return;
    if (index >= table.rows.length * columns) {
      if (!grow) return;
      _controller!.insertTableRow(_id!, table.rows.length);
      index = table.rows.length * columns;
    }
    _open(index ~/ columns, index % columns, end: by < 0);
  }

  /// The cell above or below ([by] rows on); out of the table past its
  /// ends, or a row put in after the last where [grow].
  void _vertical(int by, {bool grow = false}) {
    final (row, column) = _cell!;
    final table = _read();
    if (table == null) return;
    final next = row + by;
    if (next < 0) return _leave(after: false);
    if (next >= table.rows.length) {
      if (!grow) return _leave(after: true);
      _controller!.insertTableRow(_id!, table.rows.length);
    }
    _open(next, column, end: true);
  }

  KeyEventResult _cellKeyEvent(KeyEvent event) {
    final cell = _cellController;
    if (event is KeyUpEvent || cell == null || cell.isComposing) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    if (command && !keyboard.isShiftPressed && !keyboard.isAltPressed) {
      switch (key) {
        case LogicalKeyboardKey.keyB:
          cell.toggleInline(MdInlineKind.strong);
        case LogicalKeyboardKey.keyI:
          cell.toggleInline(MdInlineKind.emphasis);
        case LogicalKeyboardKey.keyU:
          cell.toggleUnderline();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final selection = cell.selection;
    final collapsed = selection.isValid && selection.isCollapsed;
    switch (key) {
      case LogicalKeyboardKey.tab:
        _step(keyboard.isShiftPressed ? -1 : 1, grow: !keyboard.isShiftPressed);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        // No line breaks in a cell.
        if (!keyboard.isShiftPressed) _vertical(1, grow: true);
      case LogicalKeyboardKey.escape:
        _leave(after: true);
      case LogicalKeyboardKey.arrowUp when !keyboard.isShiftPressed:
        if (!_onEdgeLine(first: true)) return KeyEventResult.ignored;
        _vertical(-1);
      case LogicalKeyboardKey.arrowDown when !keyboard.isShiftPressed:
        if (!_onEdgeLine(first: false)) return KeyEventResult.ignored;
        _vertical(1);
      case LogicalKeyboardKey.arrowLeft
          when collapsed &&
              !keyboard.isShiftPressed &&
              selection.baseOffset == 0:
        _step(-1);
      case LogicalKeyboardKey.arrowRight
          when collapsed &&
              !keyboard.isShiftPressed &&
              selection.baseOffset == cell.length:
        _step(1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --- Cells picked ------------------------------------------------------------------

  /// The cell at [global] (on the screen); with [clamp], the nearest
  /// where it is past the table's edges.
  (int, int)? _cellAt(Offset global, {bool clamp = false}) {
    final table = _renderTable;
    if (table == null || table.rows == 0 || _widths.isEmpty) return null;
    final local = table.globalToLocal(global);
    if (!clamp && !(Offset.zero & table.size).contains(local)) return null;
    var row = table.rows - 1;
    for (var r = 0; r < table.rows; r++) {
      if (local.dy < table.getRowBox(r).bottom) {
        row = r;
        break;
      }
    }
    var column = _widths.length - 1;
    var x = 0.0;
    for (var c = 0; c < _widths.length; c++) {
      x += _widths[c];
      if (local.dx < x) {
        column = c;
        break;
      }
    }
    return (row, column);
  }

  /// A mouse's press: the cell it is in typed in there at once (its text
  /// picked as it is dragged on), or, with Shift, the cells from the one
  /// typed in (picked) to it picked.
  void _pointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse ||
        event.buttons != kPrimaryButton ||
        !_editable) {
      return;
    }
    final cell = _cellAt(event.position);
    if (cell == null) return;
    _pressPointer = event.pointer;
    _pressCell = cell;
    _pressOpened = false;
    // In the cell typed in: its editor's.
    if (_cell == cell) return;
    if (HardwareKeyboard.instance.isShiftPressed) {
      if (_from ?? _cell case final from?) {
        _pressCell = from;
        return _pick(from, cell);
      }
    }
    _pressOpened = true;
    _open(cell.$1, cell.$2, at: event.position);
  }

  /// Dragged on: out of the cell it was pressed in, the cells from that
  /// to the one under it picked; in it, its text from where it was
  /// pressed.
  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer != _pressPointer) return;
    final from = _pressCell!;
    final cell = _cellAt(event.position, clamp: true);
    if (cell == null) return;
    if (_from != null || cell != from) return _pick(from, cell);
    final editor = _cellKey.currentState;
    final controller = _cellController;
    if (!_pressOpened || _placing || editor == null || controller == null) {
      return;
    }
    final at = editor.offsetAt(event.position);
    if (at == null) return;
    final selection = controller.selection;
    controller.selection = TextSelection(
      baseOffset: selection.isValid ? selection.baseOffset : at,
      extentOffset: at,
    );
  }

  void _pointerUp(PointerEvent event) {
    if (event.pointer == _pressPointer) _pressPointer = null;
  }

  /// The cells from [from] to [to] picked, none typed in.
  void _pick((int, int) from, (int, int) to) {
    if (_cell != null) _closeCell();
    if (!_cellsFocus.hasPrimaryFocus) _cellsFocus.requestFocus();
    if (_from == from && _to == to) return;
    setState(() {
      _from = from;
      _to = to;
    });
  }

  void _unpick() {
    if (_from == null) return;
    setState(() => _from = _to = null);
  }

  /// Clicked elsewhere: none picked.
  void _cellsFocusChanged() {
    if (_cellsFocus.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_cellsFocus.hasFocus && !_menuOpen) _unpick();
    });
  }

  /// The cells picked: their top row, left column, bottom row and right
  /// column.
  (int, int, int, int)? get _picks {
    if ((_from, _to) case ((final r0, final c0)?, (final r1, final c1)?)) {
      return (
        math.min(r0, r1),
        math.min(c0, c1),
        math.max(r0, r1),
        math.max(c0, c1),
      );
    }
    return null;
  }

  KeyEventResult _cellsKeyEvent(FocusNode node, KeyEvent event) {
    final picks = _picks;
    final table = _read();
    if (event is KeyUpEvent ||
        picks == null ||
        table == null ||
        !_cellsFocus.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final (top, left, bottom, right) = picks;
    final keyboard = HardwareKeyboard.instance;
    final command = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final key = event.logicalKey;
    if (command && !keyboard.isAltPressed) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          _copyCells();
        case LogicalKeyboardKey.keyX:
          _copyCells();
          _controller!.clearTableCells(_id!, top, left, bottom, right);
        case LogicalKeyboardKey.keyV:
          _pasteCells();
        case LogicalKeyboardKey.keyA:
          _pick((0, 0), (table.rows.length - 1, table.columns - 1));
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    // Shift and an arrow: the far corner moved; an arrow, the one cell
    // picked.
    (int, int) moved((int, int) cell, int rows, int columns) => (
      (cell.$1 + rows).clamp(0, table.rows.length - 1),
      (cell.$2 + columns).clamp(0, table.columns - 1),
    );
    void arrow(int rows, int columns) {
      if (keyboard.isShiftPressed) {
        _pick(_from!, moved(_to!, rows, columns));
      } else {
        final cell = moved(_from!, rows, columns);
        _pick(cell, cell);
      }
    }

    switch (key) {
      case LogicalKeyboardKey.escape:
        _unpick();
        _leave(after: true);
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        _controller!.clearTableCells(_id!, top, left, bottom, right);
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _open(_from!.$1, _from!.$2, end: true);
      case LogicalKeyboardKey.arrowUp:
        arrow(-1, 0);
      case LogicalKeyboardKey.arrowDown:
        arrow(1, 0);
      case LogicalKeyboardKey.arrowLeft:
        arrow(0, -1);
      case LogicalKeyboardKey.arrowRight:
        arrow(0, 1);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  /// The cells picked copied as a spreadsheet's are: a row a line, its
  /// cells apart by tabs.
  void _copyCells() {
    final picks = _picks;
    final table = _read();
    if (picks == null || table == null) return;
    table.fill();
    final (top, left, bottom, right) = picks;
    final text = [
      for (var r = top; r <= bottom && r < table.rows.length; r++)
        [
          for (var c = left; c <= right && c < table.columns; c++)
            table.rows[r][c].replaceAll(r'\|', '|'),
        ].join('\t'),
    ].join('\n');
    unawaited(Clipboard.setData(ClipboardData(text: text)));
  }

  /// What was copied put in from the first cell picked on (one cell's
  /// text, in each picked), what it went over picked then.
  Future<void> _pasteCells() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    final picks = _picks;
    if (text == null || text.isEmpty || picks == null || !mounted) return;
    final (top, left, bottom, right) = picks;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
    var cells = [for (final line in lines) line.split('\t')];
    if (cells.length == 1 && cells.first.length == 1) {
      cells = [
        for (var r = top; r <= bottom; r++)
          [for (var c = left; c <= right; c++) cells.first.first],
      ];
    }
    _controller!.pasteTableCells(_id!, top, left, cells);
    final width = cells.fold(0, (most, cells) => math.max(most, cells.length));
    _pick((top, left), (top + cells.length - 1, left + width - 1));
  }

  /// Whether the caret is on the cell's first (or last) line as laid out.
  bool _onEdgeLine({required bool first}) {
    final editor = _cellKey.currentState;
    final cell = _cellController;
    if (editor == null || cell == null) return true;
    final caret = editor.caretRect();
    final edge = editor.caretRect(first ? 0 : cell.length);
    if (caret == null || edge == null) return true;
    return (caret.center.dy - edge.center.dy).abs() < caret.height / 2;
  }

  // --- Rows and columns -------------------------------------------------------------

  RenderTable? get _renderTable {
    final table = _tableKey.currentContext?.findRenderObject();
    return table is RenderTable && table.hasSize ? table : null;
  }

  /// Row [row]'s box, in the table's.
  Rect? _rowBox(int row) {
    final table = _renderTable;
    if (table == null || row < 0 || row >= table.rows) return null;
    return table.getRowBox(row);
  }

  /// Column [column]'s left edge and width, in the table's.
  (double, double)? _columnSpan(int column) {
    if (column < 0 || column >= _widths.length) return null;
    var left = 0.0;
    for (var c = 0; c < column; c++) {
      left += _widths[c];
    }
    return (left, _widths[column]);
  }

  void _hover(Offset global) {
    final table = _renderTable;
    if (table == null) return;
    final local = table.globalToLocal(global);
    int? row;
    for (var r = 0; r < table.rows; r++) {
      final box = table.getRowBox(r);
      if (local.dy >= box.top && local.dy < box.bottom) row = r;
    }
    int? column;
    var x = 0.0;
    for (var c = 0; c < _widths.length; c++) {
      if (local.dx >= x && local.dx < x + _widths[c]) column = c;
      x += _widths[c];
    }
    // Keeps the last while over the room around the table (its handles).
    row ??= local.dy < 0 ? _hoverRow : null;
    column ??= local.dx < 0 ? _hoverColumn : null;
    if (row != _hoverRow || column != _hoverColumn || !_hovered) {
      setState(() {
        _hovered = true;
        _hoverRow = row ?? _hoverRow;
        _hoverColumn = column ?? _hoverColumn;
      });
    }
  }

  /// Where a row (or a column) dragged to [global] would go: before the
  /// one whose middle is past it.
  int _dropAt(bool row, Offset global) {
    final table = _renderTable;
    if (table == null) return 0;
    final local = table.globalToLocal(global);
    if (row) {
      for (var r = 0; r < table.rows; r++) {
        if (local.dy < table.getRowBox(r).center.dy) return r;
      }
      return table.rows;
    }
    var x = 0.0;
    for (var c = 0; c < _widths.length; c++) {
      if (local.dx < x + _widths[c] / 2) return c;
      x += _widths[c];
    }
    return _widths.length;
  }

  void _dragUpdate(bool row, int from, Offset global) {
    final to = _dropAt(row, global);
    if (_drag != (row: row, from: from, to: to)) {
      setState(() => _drag = (row: row, from: from, to: to));
    }
  }

  void _dragEnd() {
    final drag = _drag;
    setState(() => _drag = null);
    if (drag == null || drag.to == drag.from || drag.to == drag.from + 1) {
      return;
    }
    final to = drag.to > drag.from ? drag.to - 1 : drag.to;
    _closeCell();
    if (drag.row) {
      _controller!.moveTableRow(_id!, drag.from, to);
    } else {
      _controller!.moveTableColumn(_id!, drag.from, to);
    }
  }

  /// A menu of [sections] at [anchor] (on the screen), what it is for
  /// shown [picked] while it is open; the action picked, applied.
  Future<void> _menu(
    BuildContext from,
    Rect anchor,
    List<List<MdTableAction>> sections, {
    ({bool row, int index})? picked,
    Set<MdTableAction> checked = const {},
    required void Function(MdTableAction action) apply,
  }) async {
    final host = _host;
    if (host == null) return;
    _menuOpen = true;
    setState(() => _picked = picked);
    final MdTableAction? action;
    try {
      action = await host.widget.embeds.tableMenu(from, anchor, [
        for (final section in sections)
          if (section.isNotEmpty) section,
      ], checked: checked);
    } finally {
      _menuOpen = false;
      if (mounted) setState(() => _picked = null);
    }
    if (action == null || !mounted) return;
    _closeCell();
    apply(action);
  }

  List<List<MdTableAction>> _rowSections(int row, int rows) => [
    [
      MdTableAction.insertRowAbove,
      MdTableAction.insertRowBelow,
      MdTableAction.duplicateRow,
    ],
    [
      if (row > 0) MdTableAction.moveRowUp,
      if (row < rows - 1) MdTableAction.moveRowDown,
    ],
    [MdTableAction.clearRow, if (rows > 1) MdTableAction.deleteRow],
  ];

  List<List<MdTableAction>> _columnSections(int column, int columns) => [
    [
      MdTableAction.insertColumnLeft,
      MdTableAction.insertColumnRight,
      MdTableAction.duplicateColumn,
    ],
    [
      if (column > 0) MdTableAction.moveColumnLeft,
      if (column < columns - 1) MdTableAction.moveColumnRight,
    ],
    [
      MdTableAction.alignLeft,
      MdTableAction.alignCenter,
      MdTableAction.alignRight,
    ],
    [MdTableAction.clearColumn, MdTableAction.deleteColumn],
  ];

  Set<MdTableAction> _alignOf(int column, List<TextAlign> aligns) => {
    switch (column < aligns.length ? aligns[column] : TextAlign.left) {
      TextAlign.center => MdTableAction.alignCenter,
      TextAlign.right => MdTableAction.alignRight,
      _ => MdTableAction.alignLeft,
    },
  };

  /// [action] on row [row] and column [column] (the menus' and a cell's);
  /// the cell to type in then, typed in.
  void _apply(MdTableAction action, int row, int column) {
    final controller = _controller!;
    final id = _id!;
    (int, int)? next;
    switch (action) {
      case MdTableAction.insertRowAbove:
        controller.insertTableRow(id, row);
        next = (row, 0);
      case MdTableAction.insertRowBelow:
        controller.insertTableRow(id, row + 1);
        next = (row + 1, 0);
      case MdTableAction.duplicateRow:
        controller.duplicateTableRow(id, row);
      case MdTableAction.moveRowUp:
        controller.moveTableRow(id, row, row - 1);
      case MdTableAction.moveRowDown:
        controller.moveTableRow(id, row, row + 1);
      case MdTableAction.clearRow:
        controller.clearTableRow(id, row);
      case MdTableAction.deleteRow:
        controller.deleteTableRow(id, row);
      case MdTableAction.insertColumnLeft:
        controller.insertTableColumn(id, column);
        next = (0, column);
      case MdTableAction.insertColumnRight:
        controller.insertTableColumn(id, column + 1);
        next = (0, column + 1);
      case MdTableAction.duplicateColumn:
        controller.duplicateTableColumn(id, column);
      case MdTableAction.moveColumnLeft:
        controller.moveTableColumn(id, column, column - 1);
      case MdTableAction.moveColumnRight:
        controller.moveTableColumn(id, column, column + 1);
      case MdTableAction.alignLeft:
        controller.alignTableColumn(id, column, TextAlign.left);
      case MdTableAction.alignCenter:
        controller.alignTableColumn(id, column, TextAlign.center);
      case MdTableAction.alignRight:
        controller.alignTableColumn(id, column, TextAlign.right);
      case MdTableAction.clearColumn:
        controller.clearTableColumn(id, column);
      case MdTableAction.deleteColumn:
        controller.deleteTableColumn(id, column);
      case MdTableAction.deleteTable:
        controller.deleteTable(id);
    }
    if (next case (final r, final c)?) _open(r, c);
  }

  void _addRow() {
    final table = _read();
    if (table == null) return;
    _closeCell();
    _controller!.insertTableRow(_id!, table.rows.length);
    _open(table.rows.length, 0);
  }

  void _addColumn() {
    final table = _read();
    if (table == null) return;
    _closeCell();
    _controller!.insertTableColumn(_id!, table.columns);
    _open(0, table.columns);
  }

  // --- Building ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final (:rows, :aligns) = parseTable(widget.source);
    if (rows.isEmpty) return const SizedBox.shrink();
    final columns = rows.fold(
      0,
      (most, row) => row.length > most ? row.length : most,
    );
    final style = widget.style;
    final look = style.tableStyle;
    final text = style.text;
    final line = BorderSide(color: look.border);
    final embeds =
        _host?.widget.embeds ??
        context.findAncestorWidgetOfExactType<MarkdownEditor>()?.embeds ??
        const MarkdownEmbeds();
    final embed = widget.embed;
    // Its formulas and pictures as its editor's show them, not typed in
    // as well (as wide as their markdown where [shown] is not).
    InlineSpan spanOf(String value, TextStyle textStyle, {bool shown = true}) =>
        widget.cell?.call(value, textStyle) ??
        buildInlineSpan(
          value,
          style: style,
          textStyle: textStyle,
          isAtomic: (run) => embeds.isAtomic(run, value),
          atomic: !shown || embed == null
              ? null
              : (run, runStyle) => embeds.inline(
                  context,
                  MdEmbed(
                    controller: embed.controller,
                    lineId: embed.lineId,
                    run: run,
                    line: value,
                    style: runStyle,
                  ),
                ),
        );
    TextStyle styleOf(int row) => row == 0 ? text.merge(style.bold) : text;

    // Its edge drawn over the cells, its head's ground clipped to its
    // corners.
    Widget frame(Widget table) => Container(
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(look.radius),
        border: Border.fromBorderSide(line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(look.radius),
        child: table,
      ),
    );
    TableRow rowOf(int r, Widget Function(int r, int c) cell) => TableRow(
      decoration: r == 0 ? BoxDecoration(color: look.head) : null,
      children: [for (var c = 0; c < columns; c++) cell(r, c)],
    );
    String valueOf(int r, int c) => c < rows[r].length ? rows[r][c] : '';
    TextAlign alignOf(int c) => c < aligns.length ? aligns[c] : TextAlign.left;

    // Its scrollbar, over its bottom edge, while the mouse is over it.
    Widget scrolled(EdgeInsets padding, Widget child) => embeds.tableScrollbar(
      context,
      _sideways,
      hovered: _hovered || _drag != null,
      padding: padding,
      style: style,
      child: SingleChildScrollView(
        controller: _sideways,
        scrollDirection: Axis.horizontal,
        child: child,
      ),
    );

    if (!_editable) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: scrolled(
          const EdgeInsets.fromLTRB(4, 0, 4, 2),
          frame(
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.symmetric(inside: line),
              children: [
                for (var r = 0; r < rows.length; r++)
                  rowOf(
                    r,
                    (r, c) => Padding(
                      padding: _padding,
                      child: Text.rich(
                        spanOf(valueOf(r, c), styleOf(r)),
                        textAlign: alignOf(c),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // As wide as their widest text, in bounds: a cell's editor has no
    // width of its own to give.
    final scaler = MediaQuery.textScalerOf(context);
    final widths = List.filled(columns, 0.0);
    for (var r = 0; r < rows.length; r++) {
      for (var c = 0; c < columns; c++) {
        final painter = TextPainter(
          text: TextSpan(
            text: spanOf(
              valueOf(r, c),
              styleOf(r),
              shown: false,
            ).toPlainText(includeSemanticsLabels: false),
            style: styleOf(r),
          ),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        widths[c] = math.max(widths[c], painter.maxIntrinsicWidth);
        painter.dispose();
      }
    }
    for (var c = 0; c < columns; c++) {
      widths[c] = (widths[c] + _padding.horizontal + 6).clamp(80.0, 360.0);
    }
    _widths = widths;

    Widget cellOf(int r, int c) {
      final cell = _cellController;
      Widget child;
      if (_cell == (r, c) && cell != null) {
        final host = _host!;
        child = Padding(
          padding: _padding,
          child: MarkdownEditor(
            key: _cellKey,
            controller: cell,
            style: style.copyWith(text: styleOf(r)),
            embeds: host.widget.embeds,
            focusNode: _cellFocus,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onKey: _cellKeyEvent,
            // A link shows as its editor's do (a bar over it, say).
            revealsLinks: host.widget.revealsLinks,
            keyboardAppearance: host.widget.keyboardAppearance,
            textAlign: alignOf(c),
          ),
        );
      } else {
        // A mouse's press opens it at once (see [_pointerDown]); a
        // finger's tap, as it lifts (its drag the page's).
        child = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            if (details.kind == PointerDeviceKind.mouse) return;
            _open(r, c, at: details.globalPosition, end: true);
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: Padding(
              padding: _padding,
              child: Text.rich(
                spanOf(valueOf(r, c), styleOf(r)),
                textAlign: alignOf(c),
              ),
            ),
          ),
        );
      }
      // Right-clicked: what there is to do with its row and column.
      return Builder(
        builder: (context) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onSecondaryTapUp: (details) =>
              _menu(context, details.globalPosition & Size.zero, [
                [
                  MdTableAction.insertRowAbove,
                  MdTableAction.insertRowBelow,
                  MdTableAction.insertColumnLeft,
                  MdTableAction.insertColumnRight,
                ],
                [
                  if (rows.length > 1) MdTableAction.deleteRow,
                  MdTableAction.deleteColumn,
                  MdTableAction.deleteTable,
                ],
              ], apply: (action) => _apply(action, r, c)),
          child: child,
        ),
      );
    }

    // What is picked, outlined as one: a row or a column (its menu's, or
    // dragged), the cells dragged across, or the cell typed in.
    final drag = _drag;
    final picked =
        _picked ?? (drag == null ? null : (row: drag.row, index: drag.from));
    _Region? region;
    if (picked != null) {
      region = picked.row
          ? (
              top: picked.index,
              left: 0,
              bottom: picked.index,
              right: columns - 1,
              tint: true,
            )
          : (
              top: 0,
              left: picked.index,
              bottom: rows.length - 1,
              right: picked.index,
              tint: true,
            );
    } else if (_picks
        case (final top, final left, final bottom, final right)?) {
      region = (top: top, left: left, bottom: bottom, right: right, tint: true);
    } else if (_cell case (final r, final c)?) {
      region = (top: r, left: c, bottom: r, right: c, tint: false);
    }
    if (region != null &&
        (region.bottom >= rows.length || region.right >= columns)) {
      region = null;
    }

    // What is picked outlined over its lines and its edge (on them, not
    // beside them).
    final table = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _pointerDown,
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerUp,
      child: CustomPaint(
        foregroundPainter: _PickedPainter(
          table: () => _renderTable,
          widths: widths,
          region: region,
          color: look.accent,
          radius: look.radius,
        ),
        child: frame(
          Table(
            key: _tableKey,
            columnWidths: {
              for (var c = 0; c < columns; c++) c: FixedColumnWidth(widths[c]),
            },
            border: TableBorder.symmetric(inside: line),
            children: [for (var r = 0; r < rows.length; r++) rowOf(r, cellOf)],
          ),
        ),
      ),
    );

    // Over the table, in its box (the stack's less the room above it).
    final over = <Widget>[];
    Widget positioned(Rect rect, Widget child) => Positioned(
      left: rect.left + _side,
      top: rect.top + _top,
      width: rect.width,
      height: rect.height,
      child: child,
    );
    if (drag != null) {
      final size = _renderTable?.size;
      if (size != null) {
        final Rect rect;
        if (drag.row) {
          final y = drag.to < rows.length ? _rowBox(drag.to)!.top : size.height;
          rect = Rect.fromLTWH(0, y - 1, size.width, 2);
        } else {
          var x = 0.0;
          for (var c = 0; c < drag.to && c < widths.length; c++) {
            x += widths[c];
          }
          rect = Rect.fromLTWH(x - 1, 0, 2, size.height);
        }
        over.add(
          positioned(
            rect,
            IgnorePointer(child: ColoredBox(color: look.accent)),
          ),
        );
      }
    }
    final showHandles = (_hovered || _menuOpen || drag != null);
    if (showHandles) {
      final row = drag != null && drag.row ? drag.from : _hoverRow;
      final column = drag != null && !drag.row ? drag.from : _hoverColumn;
      if (_rowBox(row ?? -1) case final box?) {
        final r = row!;
        over.add(
          Positioned(
            // The same while it is dragged, what is drawn under it come
            // and gone.
            key: const ValueKey('row handle'),
            left: _side - 6,
            top: box.center.dy + _top - 10,
            child: _Handle(
              look: look,
              dots: style.marks,
              vertical: true,
              active: _picked?.row == true && _picked?.index == r,
              onTap: (from) => _menu(
                from,
                _anchorOf(from),
                _rowSections(r, rows.length),
                picked: (row: true, index: r),
                apply: (action) => _apply(action, r, 0),
              ),
              onDrag: (global) => _dragUpdate(true, r, global),
              onDragEnd: _dragEnd,
            ),
          ),
        );
      }
      if (_columnSpan(column ?? -1) case (final left, final width)?) {
        final c = column!;
        over.add(
          Positioned(
            key: const ValueKey('column handle'),
            left: _side + left + width / 2 - 10,
            top: _top - 6,
            child: _Handle(
              look: look,
              dots: style.marks,
              vertical: false,
              active: _picked?.row == false && _picked?.index == c,
              onTap: (from) => _menu(
                from,
                _anchorOf(from),
                _columnSections(c, columns),
                picked: (row: false, index: c),
                checked: _alignOf(c, aligns),
                apply: (action) => _apply(action, 0, c),
              ),
              onDrag: (global) => _dragUpdate(false, c, global),
              onDragEnd: _dragEnd,
            ),
          ),
        );
      }
    }

    final framed = Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: _side,
            top: _top,
            right: _bar + _barGap,
          ),
          child: table,
        ),
        Positioned(
          top: _top,
          right: 0,
          bottom: 0,
          width: _bar,
          child: _AddBar(
            look: look,
            plus: style.marks,
            shown: _hovered,
            onTap: _addColumn,
          ),
        ),
        ...over,
      ],
    );
    // Under the table and out of its scroll: as wide as the table, or
    // as what of it is in view.
    final tableWidth = widths.fold(0.0, (sum, width) => sum + width);
    final addRow = LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.only(left: _side, top: _barGap),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: math.max(
              0.0,
              math.min(tableWidth, constraints.maxWidth - _side),
            ),
            height: _bar,
            child: _AddBar(
              look: look,
              plus: style.marks,
              shown: _hovered,
              onTap: _addRow,
            ),
          ),
        ),
      ),
    );
    return MdEmbedRegion(
      child: Focus(
        focusNode: _cellsFocus,
        child: MouseRegion(
          onHover: (event) => _hover(event.position),
          onExit: (_) {
            if (_hovered && _drag == null) {
              setState(() {
                _hovered = false;
                _hoverRow = null;
                _hoverColumn = null;
              });
            }
          },
          // Over the table's bottom edge.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              scrolled(const EdgeInsets.fromLTRB(_side + 4, 0, 4, 2), framed),
              addRow,
            ],
          ),
        ),
      ),
    );
  }

  static Rect _anchorOf(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// What is picked in a table, outlined on the lines around it (as round
/// as the table's edge at its corners), its ground tinted.
class _PickedPainter extends CustomPainter {
  _PickedPainter({
    required this.table,
    required this.widths,
    required this.region,
    required this.color,
    required this.radius,
  });

  /// The table, laid out by when it is painted.
  final RenderTable? Function() table;
  final List<double> widths;
  final _Region? region;
  final Color color;

  /// The table's edge's.
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final region = this.region;
    final render = table();
    if (region == null ||
        render == null ||
        region.bottom >= render.rows ||
        region.right >= widths.length) {
      return;
    }
    final xs = _edges(widths);
    final lastRow = render.rows - 1;
    final lastColumn = widths.length - 1;
    // On the table's edge, on the middle of its line (inside it).
    final left = region.left == 0 ? 0.5 : xs[region.left];
    final right = region.right == lastColumn
        ? size.width - 0.5
        : xs[region.right + 1];
    final top = region.top == 0 ? 0.5 : render.getRowBox(region.top).top;
    final bottom = region.bottom == lastRow
        ? size.height - 0.5
        : render.getRowBox(region.bottom).bottom;
    final round = Radius.circular(math.max(0, radius - 0.5));
    Radius corner(bool row, bool column) => row && column ? round : Radius.zero;
    final box = RRect.fromLTRBAndCorners(
      left,
      top,
      right,
      bottom,
      topLeft: corner(region.top == 0, region.left == 0),
      topRight: corner(region.top == 0, region.right == lastColumn),
      bottomLeft: corner(region.bottom == lastRow, region.left == 0),
      bottomRight: corner(region.bottom == lastRow, region.right == lastColumn),
    );
    if (region.tint) {
      canvas.drawRRect(box, Paint()..color = color.withValues(alpha: 0.08));
    }
    canvas.drawRRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_PickedPainter old) =>
      old.region != region ||
      old.color != color ||
      old.radius != radius ||
      !listEquals(old.widths, widths);
}

/// A cell's text in its table's: what the cell's editor edits, there.
/// Its Undo is the table's editor's; a `|` typed in it is escaped, a line
/// break a space.
class _CellSource implements MarkdownTextSource {
  _CellSource(this.table, this.lineId, this.row, this.column);

  final MarkdownController table;
  final int lineId;
  final int row;
  final int column;

  TextRange? get _range => table.tableCellRange(lineId, row, column);

  @override
  String get text {
    final range = _range;
    return range == null ? '' : table.substring(range.start, range.end);
  }

  @override
  void Function() listen(void Function(List<MdTextEdit> edits) onEdits) {
    var seen = text;
    void changed() {
      final now = text;
      if (now == seen) return;
      final old = seen;
      seen = now;
      var start = 0;
      while (start < old.length &&
          start < now.length &&
          old.codeUnitAt(start) == now.codeUnitAt(start)) {
        start++;
      }
      var end = 0;
      while (end < old.length - start &&
          end < now.length - start &&
          old.codeUnitAt(old.length - 1 - end) ==
              now.codeUnitAt(now.length - 1 - end)) {
        end++;
      }
      onEdits([
        MdTextEdit(
          start,
          old.length - end,
          now.substring(start, now.length - end),
        ),
      ]);
    }

    table.addListener(changed);
    return () => table.removeListener(changed);
  }

  @override
  void edit(
    int start,
    int end,
    String text, {
    required TextSelection before,
    required TextSelection after,
    required bool join,
  }) {
    final range = _range;
    if (range == null) return;
    final cleaned = text
        .replaceAll(RegExp('\r\n|\r|\n'), ' ')
        .replaceAllMapped(RegExp(r'(?<!\\)\|'), (_) => r'\|');
    final at = range.start;
    final selection = TextSelection(
      baseOffset: at + after.baseOffset + cleaned.length - text.length,
      extentOffset: at + after.extentOffset + cleaned.length - text.length,
    );
    if (join) {
      table.amend(at + start, at + end, cleaned, selection: selection);
    } else {
      table.breakUndo();
      table.replace(at + start, at + end, cleaned, selection: selection);
    }
  }

  @override
  void breakStep() => table.breakUndo();

  @override
  bool get canUndo => table.canUndo;

  @override
  bool get canRedo => table.canRedo;

  @override
  bool undo() => table.undo();

  @override
  bool redo() => table.redo();

  @override
  TextSelection? get restoredSelection {
    final range = _range;
    final selection = table.selection;
    if (range == null || !selection.isValid) return null;
    bool inside(int offset) => offset >= range.start && offset <= range.end;
    if (!inside(selection.baseOffset) || !inside(selection.extentOffset)) {
      return null;
    }
    return TextSelection(
      baseOffset: selection.baseOffset - range.start,
      extentOffset: selection.extentOffset - range.start,
    );
  }
}

/// A row's or a column's handle: clicked, its menu; dragged, it moved.
class _Handle extends StatefulWidget {
  const _Handle({
    required this.look,
    required this.dots,
    required this.vertical,
    required this.active,
    required this.onTap,
    required this.onDrag,
    required this.onDragEnd,
  });

  final MdTableStyle look;
  final Color dots;
  final bool vertical;
  final bool active;
  final void Function(BuildContext from) onTap;
  final void Function(Offset global) onDrag;
  final VoidCallback onDragEnd;

  @override
  State<_Handle> createState() => _HandleState();
}

class _HandleState extends State<_Handle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final lit = _hovered || _dragging || widget.active;
    return MouseRegion(
      cursor: _dragging ? SystemMouseCursors.grabbing : SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onTap(context),
        onPanStart: (details) {
          setState(() => _dragging = true);
          widget.onDrag(details.globalPosition);
        },
        onPanUpdate: (details) => widget.onDrag(details.globalPosition),
        onPanEnd: (_) {
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        onPanCancel: () {
          if (!_dragging) return;
          setState(() => _dragging = false);
          widget.onDragEnd();
        },
        child: Container(
          width: widget.vertical ? 12 : 20,
          height: widget.vertical ? 20 : 12,
          decoration: BoxDecoration(
            color: widget.active
                ? look.accent
                : Color.alphaBlend(
                    lit ? look.control : const Color(0x00000000),
                    look.surface,
                  ),
            border: Border.all(
              color: widget.active ? look.accent : look.border,
              width: 0.8,
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: look.shadow,
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _DotsPainter(
              widget.active ? look.surface : widget.dots,
              vertical: widget.vertical,
            ),
          ),
        ),
      ),
    );
  }
}

/// A handle's six dots, in two lines along it.
class _DotsPainter extends CustomPainter {
  _DotsPainter(this.color, {required this.vertical});

  final Color color;
  final bool vertical;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final center = size.center(Offset.zero);
    for (var i = -1; i <= 1; i++) {
      for (final side in [-1.75, 1.75]) {
        final offset = vertical ? Offset(side, i * 3.5) : Offset(i * 3.5, side);
        canvas.drawCircle(center + offset, 1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) =>
      old.color != color || old.vertical != vertical;
}

/// Beside the table while the pointer is over it: a row (or a column) put
/// in after the last.
class _AddBar extends StatefulWidget {
  const _AddBar({
    required this.look,
    required this.plus,
    required this.shown,
    required this.onTap,
  });

  final MdTableStyle look;
  final Color plus;
  final bool shown;
  final VoidCallback onTap;

  @override
  State<_AddBar> createState() => _AddBarState();
}

class _AddBarState extends State<_AddBar> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final look = widget.look;
    final shown = widget.shown || _hovered;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: look.control.withValues(
                alpha: look.control.a * (_hovered ? 1 : 0.55),
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              painter: _PlusPainter(
                widget.plus.withValues(
                  alpha: widget.plus.a * (_hovered ? 1 : 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small `+`, in the middle.
class _PlusPainter extends CustomPainter {
  _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    const arm = 4.0;
    canvas
      ..drawLine(
        center - const Offset(arm, 0),
        center + const Offset(arm, 0),
        paint,
      )
      ..drawLine(
        center - const Offset(0, arm),
        center + const Offset(0, arm),
        paint,
      );
  }

  @override
  bool shouldRepaint(_PlusPainter old) => old.color != color;
}

/// A plain menu of [sections] of actions under [anchor] (see
/// [MarkdownEmbeds.tableMenu]): the one picked, or null.
Future<MdTableAction?> showMdTableMenu(
  BuildContext context,
  Rect anchor,
  List<List<MdTableAction>> sections,
  MarkdownEditorStyle style, {
  Set<MdTableAction> checked = const {},
}) {
  final overlay = Overlay.maybeOf(context);
  if (overlay == null) return Future.value();
  final look = style.tableStyle;
  final done = Completer<MdTableAction?>();
  late final OverlayEntry entry;
  void close([MdTableAction? action]) {
    if (done.isCompleted) return;
    entry.remove();
    done.complete(action);
  }

  final box = overlay.context.findRenderObject() as RenderBox?;
  final origin = box?.globalToLocal(anchor.bottomLeft) ?? anchor.bottomLeft;
  entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: close,
          ),
        ),
        Positioned(
          left: origin.dx,
          top: origin.dy + 4,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: look.surface,
              border: Border.all(color: look.border),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [BoxShadow(color: look.shadow, blurRadius: 10)],
            ),
            // As wide as its widest item.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, section) in sections.indexed) ...[
                    if (i > 0)
                      Container(
                        height: 1,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: look.border,
                      ),
                    for (final action in section)
                      GestureDetector(
                        onTap: () => close(action),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 5,
                          ),
                          child: Text(
                            checked.contains(action)
                                ? '✓ ${action.label}'
                                : action.label,
                            style: style.text,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
  overlay.insert(entry);
  return done.future;
}
