// A markdown file's preview, edited in place as Typora edits: the document
// shows as it renders, and the caret goes into it. Each row (a paragraph,
// a heading, a list item, a table's cells…, see markdown_structure.dart)
// is text typed in, its marks (`**`, `](url)`) hidden until the caret
// comes to them (markdown_live_text.dart); Enter, Backspace and Tab do
// what they do in Typora (markdown_editing.dart). The selection runs
// across rows, and copies the source.
//
// The preview shows the document's text as the editor holds it (unsaved
// changes too) and changes it only through the document's model, so the
// tab's dirty mark, undo, saving, language servers and the agent's change
// review see one text; what it does not change stays as it is written.

import 'dart:async';
import 'dart:math' as math;

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path/path.dart' as p;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../chat/widgets/markdown_math.dart' show MathView;
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/window_controls.dart';
import 'markdown_blocks.dart';
import 'markdown_document.dart';
import 'markdown_editing.dart';
import 'markdown_inline.dart';
import 'markdown_live_text.dart';
import 'markdown_paste.dart';
import 'markdown_structure.dart';

/// Whether [path] is a markdown file the preview shows.
bool isMarkdownPath(String path) {
  final extension = p.extension(path).toLowerCase();
  return extension == '.md' || extension == '.markdown';
}

/// Colors [code] in [language] (a fence's info string) a line at a time;
/// null when the language is not known.
typedef MarkdownCodeColorizer = Future<List<List<TextSpan>>?> Function(
  String language,
  String code,
);

/// The preview of the markdown file at [path], whose text is [model]'s.
class IdeMarkdownPreview extends StatefulWidget {
  const IdeMarkdownPreview({
    super.key,
    required this.path,
    required this.model,
    required this.readBytes,
    this.pathContext,
    this.readOnly = false,
    this.initialLine,
    this.initialColumn,
    this.onLeave,
    this.onEdited,
    this.onOpenFile,
    this.onOpenExternal,
    this.onMessage,
    this.onPaste,
    this.colorize,
  });

  final String path;
  final EditorDocumentModel model;

  /// Reads a file the document shows (an image), on the project's host.
  final Future<Uint8List> Function(String path) readBytes;

  /// How the host writes paths (a remote project's are POSIX); this
  /// machine's when null.
  final p.Context? pathContext;

  /// Shown, not edited (a revision's text).
  final bool readOnly;

  /// The line (one-based) to show first, and the caret there (its
  /// column, one-based).
  final int? initialLine;
  final int? initialColumn;

  /// Told, as the preview goes, the line (one-based) of the row at its
  /// top, to show first when it comes back.
  final ValueChanged<int?>? onLeave;

  /// Told after the preview changed the text.
  final VoidCallback? onEdited;

  /// Opens a file a link goes to, and the part of its address after `#`.
  final void Function(String path, String? fragment)? onOpenFile;

  /// Opens a web or mail link.
  final void Function(Uri uri)? onOpenExternal;

  /// Says something to the user.
  final ValueChanged<String>? onMessage;

  /// What a paste puts in; the clipboard's text when null.
  final Future<MarkdownPasteOutcome> Function()? onPaste;

  /// Colors code blocks; they are plain without.
  final MarkdownCodeColorizer? colorize;

  @override
  State<IdeMarkdownPreview> createState() => IdeMarkdownPreviewState();
}

/// What an edit was, for undo: typing one character after another, or
/// deleting, is one step.
enum _EditKind { typing, deleting, other }

class IdeMarkdownPreviewState extends State<IdeMarkdownPreview> {
  late MarkdownStructure _structure = _parse(widget.model.text);
  StreamSubscription<EditorContentChangeEvent>? _changes;

  /// The preview's own edits, which its change listener skips.
  bool _applying = false;

  final _list = ListController();
  final _scroll = ScrollController();

  /// Around the rows: has the focus while a row's text has it.
  final _focus = FocusNode(debugLabel: 'markdown preview');

  /// The selection, in the document; null before the caret was put in.
  TextSelection? _selection;

  /// The unit the selection's extent is in: its text is [_field]'s.
  ({int row, int unit})? _active;

  /// The unit the caret was put in, where two have its offset (an empty
  /// row after the last, at its end): kept while the text is the same.
  (int, int)? _preferred;
  final _field = MarkdownUnitController();
  TextEditingValue _fieldValue = TextEditingValue.empty;
  bool _settingField = false;

  /// Whether the caret's unit takes the focus as it changes: the preview is
  /// being used.
  bool _wantsFocus = false;

  /// The units laid out, for the pointer and the arrows.
  final Map<(int, int), _UnitHandle> _units = {};

  /// Controls in the rows (task boxes, a table's tools) the pointer is
  /// theirs over.
  final Set<BuildContext> _controls = {};

  /// Where vertical arrows keep the caret, across short lines.
  double? _verticalX;

  int _lastEditVersion = -1;
  _EditKind? _lastEditKind;

  /// The images read, by path: read once while the preview shows.
  final Map<String, Future<Uint8List>> _images = {};

  /// Units' inline elements, by their text.
  final Map<String, List<MarkdownInline>> _inlines = {};
  Map<String, String> _references = const {};

  /// Code blocks colored, by language and code.
  final Map<(String, String), List<List<TextSpan>>?> _colors = {};
  final Set<(String, String)> _coloring = {};

  p.Context get _context => widget.pathContext ?? p.context;

  MarkdownStructure _parse(String text, {int? caretLine}) =>
      MarkdownStructure(text, caretLine: caretLine, trailing: !widget.readOnly);

  /// Whether the caret's unit has the keyboard.
  bool get editing => _active != null && _activeHandle?.focused == true;

  /// Whether the preview has the keyboard.
  bool get hasFocus => _focus.hasFocus;

  @override
  void initState() {
    super.initState();
    _listen();
    _field.addListener(_fieldChanged);
    if (widget.initialLine case final line?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) revealLine(line, widget.initialColumn ?? 1);
      });
    }
  }

  @override
  void didUpdateWidget(IdeMarkdownPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.model, widget.model) ||
        oldWidget.readOnly != widget.readOnly) {
      unawaited(_changes?.cancel());
      _images.clear();
      _selection = null;
      _active = null;
      _structure = _parse(widget.model.text);
      _listen();
    } else if (oldWidget.path != widget.path) {
      _images.clear();
    }
  }

  void _listen() {
    _changes = widget.model.changes.listen(_modelChanged);
  }

  @override
  void dispose() {
    widget.onLeave?.call(topLine);
    unawaited(_changes?.cancel());
    _field.removeListener(_fieldChanged);
    _field.dispose();
    _focus.dispose();
    _scroll.dispose();
    _list.dispose();
    super.dispose();
  }

  // --- The workbench's -----------------------------------------------------

  /// Edits are the document's as they are typed: nothing held back.
  Future<void> flush() async {}

  void focus() {
    _wantsFocus = true;
    if (_activeHandle case final handle?) {
      handle.focus();
    } else {
      _focus.requestFocus();
    }
  }

  /// The line (one-based) of the row at the top of the view.
  int? get topLine {
    final rows = _structure.rows;
    if (rows.isEmpty) return null;
    final range = _list.isAttached ? _list.visibleRange : null;
    final index = (range?.$1 ?? 0).clamp(0, rows.length - 1);
    return rows[index].firstLine + 1;
  }

  /// Where the caret is: its line and column, one-based.
  ({int line, int column})? get caret {
    final selection = _selection;
    if (selection == null) return null;
    final lines = _structure.lines;
    final offset = selection.extentOffset.clamp(0, _structure.text.length);
    final line = lines.lineAt(offset);
    return (line: line + 1, column: offset - lines.starts[line] + 1);
  }

  /// Shows [line] (one-based), the caret at its [column].
  void revealLine(int line, [int column = 1]) {
    final lines = _structure.lines;
    final index = (line - 1).clamp(0, lines.length - 1);
    final offset = (lines.starts[index] + column - 1).clamp(
      lines.starts[index],
      lines.ends[index],
    );
    _jumpTo(_structure.rowAtLine(index));
    _select(TextSelection.collapsed(offset: offset), focus: true);
  }

  void _jumpTo(int index) {
    if (!_list.isAttached || !_scroll.hasClients) return;
    _list.jumpToItem(index: index, scrollController: _scroll, alignment: 0);
  }

  /// Puts [text] (links, a dropped file's) where the caret is, or as a
  /// paragraph of its own after the row at [position] (global), or at the
  /// end.
  void insert(String text, {Offset? position}) {
    if (widget.readOnly || text.isEmpty) return;
    if (position != null) {
      if (_hit(position) case final hit?) {
        _change(markdownParagraphAfter(_structure, hit.row, text));
        return;
      }
    }
    if (_active != null) {
      _replaceSelection(text);
      return;
    }
    _change(
      markdownParagraphAfter(_structure, _structure.rows.length - 1, text),
    );
  }

  // --- Commands --------------------------------------------------------------

  /// Whether the formatting commands apply: the caret is in the document.
  bool get canFormat => !widget.readOnly && _active != null;

  /// Whether the caret is in a table.
  bool get inTable =>
      _active != null &&
      _structure.rows[_active!.row].kind == MarkdownRowKind.table;

  MarkdownCaret? get _caret {
    final active = _active;
    if (active == null) return null;
    return (
      row: active.row,
      unit: active.unit,
      offset: _field.selection.extentOffset.clamp(0, _field.text.length),
    );
  }

  void _command(MarkdownChange? Function(MarkdownCaret caret) run) {
    final caret = _caret;
    if (widget.readOnly || caret == null) return;
    _change(run(caret));
  }

  /// ⌘B, ⌘I and their like: the selection wrapped in [mark] (`**`, `*`,
  /// `~~`, `` ` ``), or out of it.
  void toggleInline(String mark) => _command((caret) {
    if (_multiUnit) return null;
    final selection = _field.selection;
    return markdownToggleInline(
      _structure,
      caret,
      selection.start,
      selection.end,
      mark,
    );
  });

  /// The caret's paragraph a heading of [level], or a paragraph (0).
  void setHeading(int level) =>
      _command((caret) => markdownSetHeading(_structure, caret, level));

  void toggleQuote() =>
      _command((caret) => markdownToggleQuote(_structure, caret));

  void toggleList({bool ordered = false, bool task = false}) => _command(
    (caret) =>
        markdownToggleList(_structure, caret, ordered: ordered, task: task),
  );

  void insertBlock(MarkdownBlockInsert kind) =>
      _command((caret) => markdownInsertBlock(_structure, caret, kind));

  void editTable(MarkdownTableEdit edit) =>
      _command((caret) => markdownEditTable(_structure, caret, edit));

  // --- The document ----------------------------------------------------------

  void _modelChanged(EditorContentChangeEvent event) {
    if (_applying || !mounted) return;
    // Another's edit (the source, the agent, undo): the selection follows.
    var selection = _selection;
    if (selection != null) {
      int map(int offset) {
        for (final change in event.changes) {
          final end = change.rangeOffset + change.rangeLength;
          if (offset >= end) {
            offset += change.text.length - change.rangeLength;
          } else if (offset > change.rangeOffset) {
            offset = change.rangeOffset + change.text.length;
          }
        }
        return offset;
      }

      selection = TextSelection(
        baseOffset: map(selection.baseOffset),
        extentOffset: map(selection.extentOffset),
      );
    }
    _selection = selection;
    _lastEditKind = null;
    _preferred = null;
    _reparse();
  }

  /// The document parsed again, for its text or the caret's line.
  void _reparse() {
    final text = widget.model.text;
    final selection = _selection;
    int? caretLine;
    if (selection != null) {
      caretLine = MarkdownLines(text)
          .lineAt(selection.extentOffset.clamp(0, text.length));
    }
    _structure = _parse(text, caretLine: caretLine);
    if (!identical(_references, _structure.references) &&
        !_sameReferences(_references, _structure.references)) {
      _inlines.clear();
    }
    _references = _structure.references;
    _syncField();
    if (mounted) setState(() {});
  }

  static bool _sameReferences(Map<String, String> a, Map<String, String> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }

  /// [edits], as an edit of the preview's: one undo step, or one with the
  /// edit before it of the same [kind]; the selection [after] them.
  void _apply(
    List<EditorOffsetEdit> edits,
    TextSelection after, {
    _EditKind kind = _EditKind.other,
    bool withLast = false,
  }) {
    final model = widget.model;
    final coalesce =
        withLast ||
        (kind != _EditKind.other &&
            kind == _lastEditKind &&
            model.version == _lastEditVersion);
    if (!coalesce) model.closeUndoGroup();
    final before = _selection;
    _applying = true;
    try {
      model.applyOffsetEdits(
        edits,
        selectionsBefore: [?before],
        selectionsAfter: [after],
        coalesce: coalesce,
      );
    } finally {
      _applying = false;
    }
    _lastEditVersion = model.version;
    _lastEditKind = kind;
    _preferred = null;
    _verticalX = null;
    _selection = after;
    _reparse();
    widget.onEdited?.call();
    _ensureShown();
  }

  void _change(MarkdownChange? change) {
    if (change == null) return;
    final after = TextSelection(
      baseOffset: change.base,
      extentOffset: change.caret,
    );
    if (change.edits.isEmpty) {
      _select(after, focus: true);
    } else {
      _apply(change.edits, after);
    }
  }

  // --- The selection, and the caret's unit -----------------------------------

  MarkdownUnit? get _activeUnit {
    final active = _active;
    if (active == null) return null;
    return _structure.rows[active.row].units[active.unit];
  }

  _UnitHandle? get _activeHandle {
    final active = _active;
    return active == null ? null : _units[(active.row, active.unit)];
  }

  /// Whether the selection runs beyond the caret's unit.
  bool get _multiUnit {
    final selection = _selection;
    final unit = _activeUnit;
    if (selection == null || unit == null || selection.isCollapsed) {
      return false;
    }
    return unit.toText(selection.baseOffset) == null;
  }

  void _select(
    TextSelection selection, {
    bool focus = false,
    (int, int)? unit,
  }) {
    _preferred = unit;
    final text = widget.model.text;
    final clamped = TextSelection(
      baseOffset: selection.baseOffset.clamp(0, text.length),
      extentOffset: selection.extentOffset.clamp(0, text.length),
    );
    final lines = _structure.lines;
    final oldLine = _selection == null
        ? null
        : lines.lineAt(_selection!.extentOffset.clamp(0, text.length));
    _selection = clamped;
    if (focus) _wantsFocus = true;
    if (oldLine != lines.lineAt(clamped.extentOffset)) {
      // The caret's line has its empty paragraph, and fences open on it
      // their paragraph.
      _reparse();
    } else {
      _syncField();
      setState(() {});
    }
    _ensureShown();
  }

  /// [_field] as the caret's unit, its selection the selection's part in
  /// it.
  void _syncField() {
    final selection = _selection;
    if (selection == null || _structure.rows.isEmpty) {
      _active = null;
      return;
    }
    var caret = _structure.caretAt(selection.extentOffset);
    if (_preferred case (final row, final u)?
        when row < _structure.rows.length &&
            u < _structure.rows[row].units.length) {
      if (_structure.rows[row].units[u].toText(selection.extentOffset)
          case final at?) {
        caret = (row: row, unit: u, offset: at);
      }
    }
    _active = (row: caret.row, unit: caret.unit);
    final unit = _structure.rows[caret.row].units[caret.unit];
    // A collapsed caret off the text (on a bullet) is put on it.
    if (selection.isCollapsed) {
      final at = unit.toDocument(caret.offset);
      if (at != selection.extentOffset && unit.text.isNotEmpty) {
        _selection = TextSelection.collapsed(offset: at);
      }
    }
    final base = unit.toTextNear(_selection!.baseOffset);
    var value = TextEditingValue(
      text: unit.text,
      selection: TextSelection(baseOffset: base, extentOffset: caret.offset),
    );
    if (_field.text == unit.text) {
      value = value.copyWith(composing: _field.value.composing);
    }
    _field.spans = _spans(caret.row, caret.unit, active: true);
    if (_field.value != value) {
      _settingField = true;
      try {
        _field.value = value;
      } finally {
        _settingField = false;
      }
    }
    _fieldValue = _field.value;
  }

  /// Shows the caret's unit, and gives it the keyboard when the preview is
  /// being used.
  void _ensureShown() {
    final active = _active;
    if (active == null) return;
    if (!_units.containsKey((active.row, active.unit))) {
      _list.isAttached ? _jumpTo(active.row) : null;
    }
    if (!_wantsFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_wantsFocus) return;
      _activeHandle?.focus();
    });
  }

  void _focusChanged(bool focused) {
    if (!focused) _wantsFocus = false;
    setState(() {});
  }

  // --- Typing -------------------------------------------------------------------

  void _fieldChanged() {
    if (_settingField) return;
    final old = _fieldValue;
    final now = _field.value;
    _fieldValue = now;
    final unit = _activeUnit;
    if (unit == null || _selection == null) return;
    if (old.text == now.text) {
      if (old.selection == now.selection) {
        if (old.composing != now.composing) setState(() {});
        return;
      }
      // Moved in the text (the arrows, Home, a word).
      final extent = unit.toDocument(now.selection.extentOffset);
      final base = now.selection.isCollapsed
          ? extent
          : (_multiUnit
                ? _selection!.baseOffset
                : unit.toDocument(now.selection.baseOffset));
      _verticalX = null;
      _lastEditKind = null;
      final line = _structure.lines.lineAt(_selection!.extentOffset);
      _selection = TextSelection(baseOffset: base, extentOffset: extent);
      if (line != _structure.lines.lineAt(extent)) {
        _reparse();
      } else {
        setState(() {});
      }
      return;
    }
    if (widget.readOnly) {
      _syncField();
      return;
    }
    // What changed: the text between what is the same at both ends.
    var prefix = 0;
    final shorter = math.min(old.text.length, now.text.length);
    while (prefix < shorter &&
        old.text.codeUnitAt(prefix) == now.text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < shorter - prefix &&
        old.text.codeUnitAt(old.text.length - 1 - suffix) ==
            now.text.codeUnitAt(now.text.length - 1 - suffix)) {
      suffix++;
    }
    final end = old.text.length - suffix;
    final inserted = now.text.substring(prefix, now.text.length - suffix);
    if (inserted == '\n' &&
        end == prefix &&
        !now.composing.isValid &&
        old.selection.isCollapsed) {
      // Enter, as the platform's input put it.
      _fieldValue = old;
      _syncField();
      _enter();
      return;
    }
    if (_multiUnit) {
      _fieldValue = old;
      _replaceSelection(inserted);
      return;
    }
    final edit = unit.edit(prefix, end, inserted);
    final caret = now.selection.extentOffset;
    final int after;
    if (caret == prefix + inserted.length) {
      after = edit.end;
    } else if (caret <= prefix) {
      after = unit.toDocument(caret);
    } else {
      after = edit.end + (caret - prefix - inserted.length);
    }
    final kind = inserted.isEmpty
        ? _EditKind.deleting
        : (end == prefix && !inserted.contains('\n')
              ? _EditKind.typing
              : (now.composing.isValid || old.composing.isValid
                    ? _EditKind.typing
                    : _EditKind.other));
    _apply([edit.edit], TextSelection.collapsed(offset: after), kind: kind);
  }

  /// [text] in place of the selection, across units too.
  void _replaceSelection(String text) {
    final selection = _selection;
    if (selection == null || widget.readOnly) return;
    final start = selection.start;
    final end = selection.end;
    if (!_multiUnit) {
      final unit = _activeUnit!;
      final field = _field.selection;
      final edit = unit.edit(field.start, field.end, text);
      _apply([edit.edit], TextSelection.collapsed(offset: edit.end));
      return;
    }
    _apply([
      EditorOffsetEdit(start, end, ''),
    ], TextSelection.collapsed(offset: start));
    if (text.isEmpty) return;
    final caret = _structure.caretAt(start);
    final unit = _structure.rows[caret.row].units[caret.unit];
    final edit = unit.edit(caret.offset, caret.offset, text);
    _apply(
      [edit.edit],
      TextSelection.collapsed(offset: edit.end),
      withLast: true,
    );
  }

  /// The keys a row's text takes before its field: Enter, Tab, and
  /// Backspace and Delete at its ends.
  KeyEventResult _onFieldKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    // An input method composing has the keys.
    if (_field.value.composing.isValid) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final command = keyboard.isMetaPressed || keyboard.isControlPressed;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (command || keyboard.isAltPressed) return KeyEventResult.ignored;
      if (widget.readOnly) return KeyEventResult.handled;
      _enter(soft: keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      if (command || keyboard.isAltPressed) return KeyEventResult.ignored;
      if (!widget.readOnly) _tab(outdent: keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete) {
      if (widget.readOnly) return KeyEventResult.ignored;
      final backward = key == LogicalKeyboardKey.backspace;
      if (_multiUnit) {
        _replaceSelection('');
        return KeyEventResult.handled;
      }
      final selection = _field.selection;
      if (!selection.isCollapsed) return KeyEventResult.ignored;
      final caret = _caret!;
      final MarkdownChange? change;
      if (backward && selection.extentOffset == 0) {
        change = markdownBackspace(_structure, caret);
      } else if (!backward && selection.extentOffset == _field.text.length) {
        change = markdownDelete(_structure, caret);
      } else {
        return KeyEventResult.ignored;
      }
      _change(change);
      return KeyEventResult.handled;
    }
    if (_multiUnit && !command) {
      final character = event.character;
      if (character != null &&
          character.isNotEmpty &&
          character.codeUnitAt(0) >= 0x20 &&
          character.codeUnitAt(0) != 0x7F) {
        if (!widget.readOnly) _replaceSelection(character);
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _enter({bool soft = false}) {
    if (_multiUnit || !_field.selection.isCollapsed) _replaceSelection('');
    final caret = _caret;
    if (caret == null) return;
    _change(markdownEnter(_structure, caret, soft: soft));
  }

  void _tab({required bool outdent}) {
    final caret = _caret;
    if (caret == null) return;
    final row = _structure.rows[caret.row];
    switch (row.kind) {
      case MarkdownRowKind.table:
        final next = outdent
            ? previousMarkdownUnit(_structure, caret.row, caret.unit)
            : nextMarkdownUnit(_structure, caret.row, caret.unit);
        if (next == null) return;
        final (r, u) = next;
        final unit = _structure.rows[r].units[u];
        _select(
          TextSelection(baseOffset: unit.start, extentOffset: unit.end),
          focus: true,
        );
      case MarkdownRowKind.code when !outdent:
        _replaceSelection('    ');
      default:
        _change(markdownIndentItem(_structure, caret, outdent: outdent));
    }
  }

  // --- Moving across units -------------------------------------------------------

  /// The unit above or below [row]'s [unit]: a table's cell in the row
  /// above or below, else the unit before or after.
  (int, int)? _verticalNeighbor(int row, int unit, bool down) {
    final table = _structure.rows[row].table;
    if (table != null) {
      final (r, c) = markdownCell(table, unit);
      final next = r + (down ? 1 : -1);
      if (next >= 0 && next < table.cells.length) {
        return (row, next * table.columns + c);
      }
      if (down) {
        return row + 1 < _structure.rows.length ? (row + 1, 0) : null;
      }
      if (row == 0) return null;
      return (row - 1, _structure.rows[row - 1].units.length - 1);
    }
    if (down) {
      if (row + 1 >= _structure.rows.length) return null;
      return (row + 1, 0);
    }
    if (row == 0) return null;
    final above = _structure.rows[row - 1];
    return (row - 1, above.table != null ? above.units.length - 1 : 0);
  }

  bool _vertical(ExtendSelectionVerticallyToAdjacentLineIntent intent) {
    final active = _active;
    final handle = _activeHandle;
    if (active == null || handle == null) return false;
    final down = intent.forward;
    if (_multiUnit && intent.collapseSelection) {
      final selection = _selection!;
      _select(
        TextSelection.collapsed(offset: down ? selection.end : selection.start),
      );
      return true;
    }
    final extent = _field.selection.extentOffset;
    if (!handle.atEdge(extent, down: down)) return false;
    final target = _verticalNeighbor(active.row, active.unit, down);
    final x = _verticalX ??= handle.caretX(extent);
    if (target == null) {
      // Past the first line, or the last: its start or end.
      final unit = _activeUnit!;
      _moveTo(down ? unit.end : unit.start, intent.collapseSelection);
      _verticalX = x;
      return true;
    }
    final (row, unit) = target;
    final to = _structure.rows[row].units[unit];
    final at = _units[(row, unit)]?.positionAt(x, top: down);
    _moveTo(
      to.toDocument(at ?? (down ? 0 : to.text.length)),
      intent.collapseSelection,
      unit: target,
    );
    _verticalX = x;
    return true;
  }

  bool _horizontal(DirectionalCaretMovementIntent intent) {
    final active = _active;
    if (active == null) return false;
    final selection = _field.selection;
    if (_multiUnit && intent.collapseSelection) {
      final whole = _selection!;
      _select(
        TextSelection.collapsed(
          offset: intent.forward ? whole.end : whole.start,
        ),
      );
      return true;
    }
    if (!selection.isCollapsed && intent.collapseSelection) return false;
    final extent = selection.extentOffset;
    final MarkdownUnit to;
    if (intent.forward && extent == _field.text.length) {
      final next = nextMarkdownUnit(_structure, active.row, active.unit);
      if (next == null) return false;
      to = _structure.rows[next.$1].units[next.$2];
      _moveTo(to.start, intent.collapseSelection, unit: next);
      return true;
    }
    if (!intent.forward && extent == 0) {
      final previous = previousMarkdownUnit(
        _structure,
        active.row,
        active.unit,
      );
      if (previous == null) return false;
      to = _structure.rows[previous.$1].units[previous.$2];
      _moveTo(to.end, intent.collapseSelection, unit: previous);
      return true;
    }
    return false;
  }

  void _moveTo(int offset, bool collapse, {(int, int)? unit}) {
    final selection = _selection!;
    _select(
      unit: unit,
      collapse
          ? TextSelection.collapsed(offset: offset)
          : TextSelection(
              baseOffset: selection.baseOffset,
              extentOffset: offset,
            ),
      focus: true,
    );
  }

  bool _documentBoundary(ExtendSelectionToDocumentBoundaryIntent intent) {
    if (_selection == null) return false;
    final rows = _structure.rows;
    final offset = intent.forward
        ? rows.last.units.last.end
        : rows.first.unit.start;
    _moveTo(offset, intent.collapseSelection);
    if (intent.forward) {
      _jumpTo(rows.length - 1);
    } else {
      _jumpTo(0);
    }
    return true;
  }

  // --- Undo and the clipboard ---------------------------------------------------

  void _undo({bool redo = false}) {
    if (widget.readOnly) return;
    final model = widget.model;
    if (!(redo ? model.redo() : model.undo())) return;
    if (model.restoredSelections case final restored?
        when restored.isNotEmpty) {
      _selection = restored.first;
    }
    _lastEditKind = null;
    _reparse();
    widget.onEdited?.call();
    _ensureShown();
  }

  void _selectAll() {
    final text = widget.model.text;
    _select(
      TextSelection(baseOffset: 0, extentOffset: text.length),
      focus: true,
    );
  }

  Future<void> _copy({required bool cut}) async {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return;
    final text = widget.model.text.substring(selection.start, selection.end);
    await Clipboard.setData(ClipboardData(text: text));
    if (cut && !widget.readOnly && mounted) _replaceSelection('');
  }

  Future<void> _paste() async {
    if (widget.readOnly) return;
    final selection = _selection;
    if (widget.onPaste case final paste?) {
      final outcome = await paste();
      if (!mounted || _selection != selection) return;
      switch (outcome) {
        case MarkdownPasteLinks(:final text):
          _replaceSelection(text);
          return;
        case MarkdownPasteNothing():
          return;
        case MarkdownPasteText():
      }
    }
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted || _selection != selection) return;
    if (data?.text case final text? when text.isNotEmpty) {
      _replaceSelection(text.replaceAll(RegExp('\r\n|\r'), '\n'));
    }
  }

  // --- The pointer ---------------------------------------------------------------

  /// The unit at [global] (or nearest it), and where in its text.
  ({int row, int unit, int offset})? _hit(Offset global) {
    _UnitHandle? best;
    var bestDistance = double.infinity;
    for (final handle in _units.values) {
      final rect = handle.rect;
      if (rect == null) continue;
      final dy = global.dy < rect.top
          ? rect.top - global.dy
          : (global.dy > rect.bottom ? global.dy - rect.bottom : 0.0);
      final dx = global.dx < rect.left
          ? rect.left - global.dx
          : (global.dx > rect.right ? global.dx - rect.right : 0.0);
      final distance = dy * 10000 + dx;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = handle;
      }
    }
    if (best == null) return null;
    final (row, unit) = best.id;
    if (row >= _structure.rows.length ||
        unit >= _structure.rows[row].units.length) {
      return null;
    }
    return (row: row, unit: unit, offset: best.offsetAt(global));
  }

  bool _onControl(Offset global) {
    for (final control in _controls) {
      final box = control.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(global)) return true;
    }
    return false;
  }

  bool _dragging = false;

  void _tapDown(TapDragDownDetails details) {
    _dragging = false;
    if (_onControl(details.globalPosition)) return;
    final hit = _hit(details.globalPosition);
    if (hit == null) return;
    final unit = _structure.rows[hit.row].units[hit.unit];
    final keyboard = HardwareKeyboard.instance;
    // ⌘-click opens a link (any click, when the text is not edited).
    if (keyboard.isMetaPressed ||
        keyboard.isControlPressed ||
        widget.readOnly) {
      if (_linkAt(unit, hit.offset) case final target?) {
        _open(target);
        return;
      }
    }
    final at = unit.toDocument(hit.offset);
    _verticalX = null;
    _lastEditKind = null;
    final count = details.consecutiveTapCount;
    final id = (hit.row, hit.unit);
    if (keyboard.isShiftPressed && _selection != null && count == 1) {
      _moveTo(at, false, unit: id);
      return;
    }
    if (count == 2) {
      final word = _units[(hit.row, hit.unit)]?.wordAt(hit.offset);
      if (word != null) {
        _select(
          TextSelection(
            baseOffset: unit.toDocument(word.start),
            extentOffset: unit.toDocument(word.end),
          ),
          focus: true,
        );
        return;
      }
    }
    if (count >= 3) {
      _select(
        TextSelection(baseOffset: unit.start, extentOffset: unit.end),
        focus: true,
      );
      return;
    }
    _select(TextSelection.collapsed(offset: at), focus: true, unit: id);
  }

  void _dragStart(TapDragStartDetails details) {
    _dragging = !_onControl(details.globalPosition) && _selection != null;
  }

  void _dragUpdate(TapDragUpdateDetails details) {
    if (!_dragging) return;
    final position = details.globalPosition;
    _autoScroll(position);
    final hit = _hit(position);
    if (hit == null) return;
    final unit = _structure.rows[hit.row].units[hit.unit];
    _moveTo(unit.toDocument(hit.offset), false, unit: (hit.row, hit.unit));
  }

  void _dragEnd(TapDragEndDetails details) => _dragging = false;

  /// A drag past the top or bottom scrolls.
  void _autoScroll(Offset global) {
    if (!_scroll.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final local = box.globalToLocal(global);
    const edge = 24.0;
    double delta = 0;
    if (local.dy < edge) delta = local.dy - edge;
    if (local.dy > box.size.height - edge) {
      delta = local.dy - (box.size.height - edge);
    }
    if (delta == 0) return;
    final position = _scroll.position;
    _scroll.jumpTo(
      (position.pixels + delta).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
    );
  }

  Future<void> _contextMenu(TapDownDetails details) async {
    if (!WindowControls.hasNativeMenus) return;
    final hit = _hit(details.globalPosition);
    final selection = _selection;
    final inSelection =
        hit != null &&
        selection != null &&
        !selection.isCollapsed &&
        (() {
          final at = _structure.rows[hit.row].units[hit.unit].toDocument(
            hit.offset,
          );
          return at >= selection.start && at <= selection.end;
        })();
    if (hit != null && !inSelection) {
      final unit = _structure.rows[hit.row].units[hit.unit];
      _select(
        TextSelection.collapsed(offset: unit.toDocument(hit.offset)),
        focus: true,
      );
    }
    final l10n = context.l10n;
    final selected = !(_selection?.isCollapsed ?? true);
    final editable = !widget.readOnly;
    final table = inTable && editable;
    final chosen = await WindowControls.showContextMenu(
      details.globalPosition,
      [
        NativeMenuItem(
          'cut',
          l10n.commonCut,
          key: 'x',
          enabled: selected && editable,
        ),
        NativeMenuItem('copy', l10n.commonCopy, key: 'c', enabled: selected),
        NativeMenuItem('paste', l10n.commonPaste, key: 'v', enabled: editable),
        const NativeMenuItem.separator(),
        NativeMenuItem('selectAll', l10n.commonSelectAll, key: 'a'),
        if (table) ...[
          const NativeMenuItem.separator(),
          for (final (edit, label) in _tableEdits(l10n))
            NativeMenuItem(edit.name, label),
        ],
      ],
    );
    if (!mounted) return;
    switch (chosen) {
      case 'cut':
        await _copy(cut: true);
      case 'copy':
        await _copy(cut: false);
      case 'paste':
        await _paste();
      case 'selectAll':
        _selectAll();
      case final name?:
        for (final edit in MarkdownTableEdit.values) {
          if (edit.name == name) editTable(edit);
        }
    }
  }

  // --- Links and images -------------------------------------------------------------

  /// Where the link at [offset] of [unit]'s text goes.
  MarkdownLinkTarget? _linkAt(MarkdownUnit unit, int offset) {
    String? href;
    for (final inline in flattenMarkdownInlines(_inlinesOf(unit.text))) {
      if (offset < inline.start || offset > inline.end) continue;
      if (const {
        MarkdownInlineKind.link,
        MarkdownInlineKind.autolink,
        MarkdownInlineKind.url,
      }.contains(inline.kind)) {
        href = inline.target;
      }
    }
    return resolveMarkdownLink(href, widget.path, _context);
  }

  void _open(MarkdownLinkTarget target) {
    switch (target) {
      case MarkdownAnchorLink(:final anchor):
        if (_structure.heading(anchor) case final index?) {
          _jumpTo(index);
          final unit = _structure.rows[index].unit;
          _select(TextSelection.collapsed(offset: unit.start));
        }
      case MarkdownExternalLink(:final uri):
        widget.onOpenExternal?.call(uri);
      case MarkdownFileLink(:final path, :final fragment):
        if (_context.equals(path, widget.path)) {
          if (fragment != null) _open(MarkdownAnchorLink(fragment));
        } else {
          widget.onOpenFile?.call(path, fragment);
        }
    }
  }

  /// Opens the anchor [fragment] of the document (a link from another).
  void revealAnchor(String fragment) => _open(MarkdownAnchorLink(fragment));

  Widget _image(MarkdownInline image, String alt) => _MarkdownImage(
    target: resolveMarkdownImage(image.target ?? '', widget.path, _context),
    alt: alt,
    title: image.title,
    read: (path) => _images.putIfAbsent(path, () => widget.readBytes(path)),
  );

  List<MarkdownInline> _inlinesOf(String text) {
    if (_inlines.length > 4000) _inlines.clear();
    return _inlines.putIfAbsent(
      text,
      () => parseMarkdownInlines(text, references: _references),
    );
  }

  /// [code]'s colors in [language], once it has them.
  List<List<TextSpan>>? _codeColors(String language, String code) {
    final colorize = widget.colorize;
    if (colorize == null || language.isEmpty || code.isEmpty) return null;
    final key = (language, code);
    if (_colors.containsKey(key)) return _colors[key];
    if (_coloring.add(key)) {
      unawaited(() async {
        List<List<TextSpan>>? colors;
        try {
          colors = await colorize(language, code);
        } catch (_) {
          colors = null;
        }
        _coloring.remove(key);
        if (!mounted) return;
        if (_colors.length > 400) _colors.clear();
        setState(() => _colors[key] = colors);
      }());
    }
    return null;
  }

  // --- Building ---------------------------------------------------------------------

  static const _width = 880.0;
  static const _indent = 24.0;

  static TextStyle get _base =>
      TextStyle(color: AppColors.text, fontSize: 14, height: 1.65);

  static TextStyle get _mono => TextStyle(
    color: themeColors['editor.foreground'],
    fontFamily: AppFonts.mono,
    fontSize: 13,
    height: 1.5,
  );

  static const _headingSizes = [26.0, 21.0, 17.5, 15.0, 14.0, 13.5];

  TextStyle _styleOf(MarkdownRow row, {bool header = false}) {
    switch (row.kind) {
      case MarkdownRowKind.heading:
        return _base.copyWith(
          color: AppColors.textPrimary,
          fontSize: _headingSizes[row.level - 1],
          fontWeight: FontWeight.w600,
          height: 1.35,
        );
      case MarkdownRowKind.code ||
          MarkdownRowKind.frontMatter ||
          MarkdownRowKind.math:
        return _mono;
      case MarkdownRowKind.html || MarkdownRowKind.definition:
        return _mono.copyWith(color: AppColors.textMuted, fontSize: 12.5);
      case MarkdownRowKind.rule:
        return _base.copyWith(color: AppColors.textFaint);
      case MarkdownRowKind.table when header:
        return _base.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        );
      case MarkdownRowKind.paragraph || MarkdownRowKind.table:
        return row.quotes.isEmpty
            ? _base
            : _base.copyWith(color: AppColors.textMuted);
    }
  }

  static MarkdownTextKind _kindOf(MarkdownRow row) => switch (row.kind) {
    MarkdownRowKind.paragraph ||
    MarkdownRowKind.heading ||
    MarkdownRowKind.table => MarkdownTextKind.inline,
    MarkdownRowKind.code ||
    MarkdownRowKind.frontMatter => MarkdownTextKind.code,
    _ => MarkdownTextKind.plain,
  };

  String? _languageOf(MarkdownRow row) {
    if (row.kind == MarkdownRowKind.frontMatter) return 'yaml';
    final info = row.info;
    if (info == null) return null;
    final text = _structure.text.substring(info.$1, info.$2).trim();
    return text.isEmpty ? null : text.split(RegExp(r'\s')).first;
  }

  /// Builds [row]'s [unit]'s spans (see [markdownLiveSpan]); [active]: its
  /// elements at the caret show their marks.
  TextSpan Function(TextEditingValue value, TextStyle? style) _spans(
    int row,
    int unit, {
    required bool active,
  }) {
    final markdownRow = _structure.rows[row];
    final kind = _kindOf(markdownRow);
    final language = _languageOf(markdownRow);
    return (value, style) {
      final text = value.text;
      return markdownLiveSpan(
        text: text,
        style: style ?? _base,
        kind: kind,
        inlines: kind == MarkdownTextKind.inline ? _inlinesOf(text) : const [],
        reveal: active && value.selection.isValid
            ? TextRange(start: value.selection.start, end: value.selection.end)
            : null,
        composing: value.composing,
        colors: kind == MarkdownTextKind.code && language != null
            ? _codeColors(language, text)
            : null,
        image: _image,
        math: (tex) => MathView(tex),
      );
    };
  }

  /// The part of the selection in [unit], to show selected.
  TextSelection? _selectionIn(MarkdownUnit unit) {
    final selection = _selection;
    if (selection == null || selection.isCollapsed) return null;
    if (selection.end < unit.start || selection.start > unit.end) return null;
    final start = unit.toTextNear(selection.start);
    final end = unit.toTextNear(selection.end);
    if (start == end) return null;
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  Widget _unit(int row, int unit, {bool header = false, TextAlign? align}) {
    final markdownRow = _structure.rows[row];
    final markdownUnit = markdownRow.units[unit];
    final active = _active?.row == row && _active?.unit == unit;
    return _UnitText(
      key: ValueKey(('unit', unit)),
      preview: this,
      id: (row, unit),
      text: markdownUnit.text,
      active: active,
      selection: _selectionIn(markdownUnit),
      spans: active ? null : _spans(row, unit, active: false),
      style: _styleOf(markdownRow, header: header),
      align: align ?? TextAlign.start,
      readOnly: widget.readOnly,
      focused: _focus.hasFocus,
    );
  }

  double _gap(MarkdownGap gap) => switch (gap) {
    MarkdownGap.none => 0,
    MarkdownGap.item => 4,
    MarkdownGap.block => 12,
    MarkdownGap.heading => 18,
  };

  Widget _row(BuildContext context, int index) {
    final rows = _structure.rows;
    if (index >= rows.length) {
      // The room after the rows: a click there is at the last one's end.
      return const SizedBox(height: 160);
    }
    final row = rows[index];
    final active = _active?.row == index;
    Widget content = switch (row.kind) {
      MarkdownRowKind.table => _table(index, row, active),
      MarkdownRowKind.code ||
      MarkdownRowKind.frontMatter => _codeBlock(index, row, active),
      MarkdownRowKind.math => _mathBlock(index, row, active),
      MarkdownRowKind.rule when !active => _Atomic(
        preview: this,
        id: (index, 0),
        offset: row.unit.text.length,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Divider(
            height: 1,
            color: themeColors['textSeparator.foreground'],
          ),
        ),
      ),
      _ => _unit(index, 0),
    };
    if (row.kind == MarkdownRowKind.heading && row.level <= 2) {
      content = Container(
        padding: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: themeColors['textSeparator.foreground']),
          ),
        ),
        child: content,
      );
    }
    if (row.item case final item?) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _gutter(index, row, item),
          Expanded(child: content),
        ],
      );
    }
    final depth = row.depth - (row.item != null ? 1 : 0);
    if (depth > 0) {
      content = Padding(
        padding: EdgeInsets.only(left: depth * _indent),
        child: content,
      );
    }
    var gap = index == 0 ? 0.0 : _gap(row.gap);
    if (row.quotes.isNotEmpty) {
      final previous = index > 0 ? rows[index - 1].quotes : const <int>[];
      final shared = previous.isNotEmpty && previous.first == row.quotes.first;
      content = Padding(
        padding: EdgeInsets.only(top: shared ? gap : 2, bottom: 2),
        child: content,
      );
      if (shared) gap = 0;
      for (var i = 0; i < row.quotes.length; i++) {
        content = Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: i == row.quotes.length - 1
                ? themeColors['textBlockQuote.background']
                : null,
            border: Border(
              left: BorderSide(
                color: themeColors['textBlockQuote.border'],
                width: 3,
              ),
            ),
          ),
          child: content,
        );
      }
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _width),
        child: Padding(
          padding: EdgeInsets.fromLTRB(32, gap, 32, 0),
          child: content,
        ),
      ),
    );
  }

  /// A list item's bullet, number or task box.
  Widget _gutter(int index, MarkdownRow row, MarkdownItem item) {
    final style = _styleOf(row);
    final lineHeight = (style.fontSize ?? 14) * (style.height ?? 1.4);
    if (item.task case final task?) {
      final box = SizedBox(
        width: 24,
        height: lineHeight,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Icon(
            item.checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank,
            size: 16,
            color: item.checked ? AppColors.added : AppColors.textMuted,
          ),
        ),
      );
      if (widget.readOnly) return box;
      return _Control(
        controls: _controls,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toggleTask(task),
            child: box,
          ),
        ),
      );
    }
    final marker = item.ordered
        ? '${item.number}.'
        : const ['•', '◦', '▪'][(row.depth - 1) % 3];
    return SizedBox(
      width: item.ordered ? 28 : 20,
      child: Text(
        marker,
        style: style.copyWith(
          color: AppColors.textMuted,
          fontWeight: FontWeight.normal,
        ),
      ),
    );
  }

  void _toggleTask(int offset) {
    if (widget.readOnly) return;
    final text = widget.model.text;
    if (offset >= text.length) return;
    final mark = text[offset] == ' ' ? 'x' : ' ';
    _apply([
      EditorOffsetEdit(offset, offset + 1, mark),
    ], _selection ?? TextSelection.collapsed(offset: offset + 2));
  }

  Widget _codeBlock(int index, MarkdownRow row, bool active) {
    final language = row.kind == MarkdownRowKind.frontMatter
        ? 'yaml'
        : (row.info == null
              ? null
              : _structure.text.substring(row.info!.$1, row.info!.$2));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: themeColors['textCodeBlock.background'],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Stack(
        children: [
          _unit(index, 0),
          if (row.info != null && (active || (language ?? '').isNotEmpty))
            Positioned(
              top: 0,
              right: 0,
              child: _Control(
                controls: _controls,
                child: _CodeLanguage(
                  language: language ?? '',
                  editable: active && !widget.readOnly,
                  onChanged: (text) => _setLanguage(row, text),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setLanguage(MarkdownRow row, String language) {
    final info = row.info;
    if (info == null || widget.readOnly) return;
    final clean = language.replaceAll(RegExp(r'[`\s]'), '');
    _apply(
      [EditorOffsetEdit(info.$1, info.$2, clean)],
      _selection ?? TextSelection.collapsed(offset: row.unit.start),
      kind: _EditKind.typing,
    );
  }

  Widget _mathBlock(int index, MarkdownRow row, bool active) {
    var tex = row.unit.text.trim();
    if (!row.closed) {
      tex = tex
          .replaceFirst(RegExp(r'^(\$\$|\\\[)'), '')
          .replaceFirst(RegExp(r'(\$\$|\\\])$'), '');
    }
    final shown = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: tex.isEmpty
            ? Text(r'$$', style: _mono.copyWith(color: AppColors.textFaint))
            : MathView(tex, display: true),
      ),
    );
    if (!active) {
      return _Atomic(preview: this, id: (index, 0), offset: 0, child: shown);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: themeColors['textCodeBlock.background'],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_unit(index, 0), shown],
      ),
    );
  }

  List<(MarkdownTableEdit, String)> _tableEdits(AppLocalizations l10n) => [
    (MarkdownTableEdit.rowAbove, l10n.markdownTableRowAbove),
    (MarkdownTableEdit.rowBelow, l10n.markdownTableRowBelow),
    (MarkdownTableEdit.columnLeft, l10n.markdownTableColumnLeft),
    (MarkdownTableEdit.columnRight, l10n.markdownTableColumnRight),
    (MarkdownTableEdit.deleteRow, l10n.markdownTableDeleteRow),
    (MarkdownTableEdit.deleteColumn, l10n.markdownTableDeleteColumn),
    (MarkdownTableEdit.alignLeft, l10n.markdownTableAlignLeft),
    (MarkdownTableEdit.alignCenter, l10n.markdownTableAlignCenter),
    (MarkdownTableEdit.alignRight, l10n.markdownTableAlignRight),
    (MarkdownTableEdit.deleteTable, l10n.markdownTableDelete),
  ];

  static const _tableIcons = {
    MarkdownTableEdit.rowAbove: Icons.vertical_align_top,
    MarkdownTableEdit.rowBelow: Icons.vertical_align_bottom,
    MarkdownTableEdit.columnLeft: Icons.border_left,
    MarkdownTableEdit.columnRight: Icons.border_right,
    MarkdownTableEdit.deleteRow: Icons.table_rows_outlined,
    MarkdownTableEdit.deleteColumn: Icons.view_column_outlined,
    MarkdownTableEdit.alignLeft: Icons.format_align_left,
    MarkdownTableEdit.alignCenter: Icons.format_align_center,
    MarkdownTableEdit.alignRight: Icons.format_align_right,
    MarkdownTableEdit.deleteTable: Icons.delete_outline,
  };

  Widget _table(int index, MarkdownRow row, bool active) {
    final table = row.table!;
    final line = BorderSide(color: themeColors['chat.requestBorder']);
    final grid = Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: line.color),
      children: [
        for (var r = 0; r < table.cells.length; r++)
          TableRow(
            decoration: r == 0
                ? BoxDecoration(color: AppColors.surfaceRaised)
                : null,
            children: [
              for (var c = 0; c < table.columns; c++)
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    child: _unit(
                      index,
                      r * table.columns + c,
                      header: r == 0,
                      align: switch (table.align[c]) {
                        'center' => TextAlign.center,
                        'right' => TextAlign.right,
                        _ => TextAlign.left,
                      },
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
    final scrolled = Align(
      alignment: AlignmentDirectional.centerStart,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: grid,
      ),
    );
    if (!active || widget.readOnly) return scrolled;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Control(
          controls: _controls,
          child: Wrap(
            children: [
              for (final (edit, label) in _tableEdits(l10n))
                IconButton(
                  tooltip: label,
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 26,
                    height: 24,
                  ),
                  color: AppColors.textMuted,
                  onPressed: () => editTable(edit),
                  icon: Icon(_tableIcons[edit]),
                ),
            ],
          ),
        ),
        scrolled,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final count = _structure.rows.length + 1;
    return Actions(
      actions: {
        UndoTextIntent: _Override<UndoTextIntent>((_) {
          _undo();
          return true;
        }),
        RedoTextIntent: _Override<RedoTextIntent>((_) {
          _undo(redo: true);
          return true;
        }),
        SelectAllTextIntent: _Override<SelectAllTextIntent>((_) {
          _selectAll();
          return true;
        }),
        CopySelectionTextIntent: _Override<CopySelectionTextIntent>((intent) {
          unawaited(_copy(cut: intent.collapseSelection));
          return true;
        }),
        PasteTextIntent: _Override<PasteTextIntent>((_) {
          unawaited(_paste());
          return true;
        }),
        ExtendSelectionVerticallyToAdjacentLineIntent:
            _Override<ExtendSelectionVerticallyToAdjacentLineIntent>(_vertical),
        ExtendSelectionByCharacterIntent:
            _Override<ExtendSelectionByCharacterIntent>(_horizontal),
        ExtendSelectionToNextWordBoundaryIntent:
            _Override<ExtendSelectionToNextWordBoundaryIntent>(_horizontal),
        ExtendSelectionToDocumentBoundaryIntent:
            _Override<ExtendSelectionToDocumentBoundaryIntent>(
              _documentBoundary,
            ),
        // The pointer is the preview's: a click elsewhere keeps the caret.
        EditableTextTapOutsideIntent: _Override<EditableTextTapOutsideIntent>(
          (_) => true,
        ),
        EditableTextTapUpOutsideIntent:
            _Override<EditableTextTapUpOutsideIntent>((_) => true),
      },
      child: Focus(
        focusNode: _focus,
        onFocusChange: _focusChanged,
        child: ColoredBox(
          color: themeColors['editor.background'],
          child: MouseRegion(
            cursor: SystemMouseCursors.text,
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: {
                TapAndPanGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      TapAndPanGestureRecognizer
                    >(TapAndPanGestureRecognizer.new, (recognizer) {
                      recognizer
                        ..onTapDown = _tapDown
                        ..onDragStart = _dragStart
                        ..onDragUpdate = _dragUpdate
                        ..onDragEnd = _dragEnd
                        ..dragStartBehavior = DragStartBehavior.down;
                    }),
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                      TapGestureRecognizer.new,
                      (recognizer) {
                        recognizer.onSecondaryTapDown = (details) =>
                            unawaited(_contextMenu(details));
                      },
                    ),
              },
              child: SuperListView.builder(
                listController: _list,
                controller: _scroll,
                padding: const EdgeInsets.only(top: 24),
                itemCount: count,
                itemBuilder: _row,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An action of the preview's in place of a text field's own (see
/// `Action.overridable`): [handle] says whether it took the intent; the
/// field's own does what it does otherwise.
class _Override<T extends Intent> extends Action<T> {
  _Override(this.handle);

  final bool Function(T intent) handle;

  @override
  Object? invoke(T intent) {
    if (handle(intent)) return null;
    return callingAction?.invoke(intent);
  }
}

/// A unit laid out: where it is, and where in its text a point is.
abstract interface class _UnitHandle {
  (int, int) get id;

  /// Its area, in global coordinates.
  Rect? get rect;

  /// The offset of its text at [global].
  int offsetAt(Offset global);

  /// The offset at [x] (global) on its first line ([top]) or last.
  int? positionAt(double x, {required bool top});

  /// Whether [offset] is on its first line ([down]: its last).
  bool atEdge(int offset, {required bool down});

  /// The caret's x (global) at [offset].
  double caretX(int offset);

  /// The word at [offset].
  TextRange? wordAt(int offset);

  bool get focused;
  void focus();
}

/// A unit's text: the caret's (its text in the preview's field, its
/// marks shown at the caret), or another's (drawn, its part of the
/// selection shown).
class _UnitText extends StatefulWidget {
  const _UnitText({
    super.key,
    required this.preview,
    required this.id,
    required this.text,
    required this.active,
    required this.selection,
    required this.spans,
    required this.style,
    required this.align,
    required this.readOnly,
    required this.focused,
  });

  final IdeMarkdownPreviewState preview;
  final (int, int) id;
  final String text;
  final bool active;
  final TextSelection? selection;
  final TextSpan Function(TextEditingValue value, TextStyle? style)? spans;
  final TextStyle style;
  final TextAlign align;
  final bool readOnly;
  final bool focused;

  @override
  State<_UnitText> createState() => _UnitTextState();
}

class _UnitTextState extends State<_UnitText> implements _UnitHandle {
  final _own = MarkdownUnitController();
  late final _focusNode = FocusNode(
    debugLabel: 'markdown text',
    skipTraversal: true,
    onKeyEvent: (node, event) => widget.preview._onFieldKey(node, event),
  );
  final _editable = GlobalKey<EditableTextState>();

  @override
  (int, int) get id => widget.id;

  @override
  void initState() {
    super.initState();
    widget.preview._units[widget.id] = this;
    _syncOwn();
    if (widget.active) _focusSoon();
  }

  @override
  void didUpdateWidget(_UnitText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      if (identical(widget.preview._units[oldWidget.id], this)) {
        widget.preview._units.remove(oldWidget.id);
      }
    }
    widget.preview._units[widget.id] = this;
    _syncOwn();
    if (widget.active && !oldWidget.active) _focusSoon();
  }

  void _syncOwn() {
    if (widget.active) return;
    final value = TextEditingValue(
      text: widget.text,
      selection: widget.selection ?? const TextSelection.collapsed(offset: 0),
    );
    _own.spans = widget.spans;
    if (_own.value != value) _own.value = value;
  }

  void _focusSoon() {
    if (!widget.preview._wantsFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.active && widget.preview._wantsFocus) focus();
    });
  }

  @override
  void dispose() {
    if (identical(widget.preview._units[widget.id], this)) {
      widget.preview._units.remove(widget.id);
    }
    _focusNode.dispose();
    _own.dispose();
    super.dispose();
  }

  RenderEditable? get _render {
    final render = _editable.currentState?.renderEditable;
    return render != null && render.attached && render.hasSize ? render : null;
  }

  @override
  Rect? get rect {
    final render = _render;
    if (render == null) return null;
    return render.localToGlobal(Offset.zero) & render.size;
  }

  @override
  int offsetAt(Offset global) =>
      _render?.getPositionForPoint(global).offset ?? 0;

  @override
  int? positionAt(double x, {required bool top}) {
    final render = _render;
    if (render == null) return null;
    final origin = render.localToGlobal(Offset.zero);
    final y = top ? 2.0 : render.size.height - 2;
    return render.getPositionForPoint(Offset(x, origin.dy + y)).offset;
  }

  @override
  bool atEdge(int offset, {required bool down}) {
    final render = _render;
    if (render == null) return true;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    final edge = render.getLocalRectForCaret(
      TextPosition(offset: down ? widget.text.length : 0),
    );
    return down ? caret.top >= edge.top - 1 : caret.top <= edge.top + 1;
  }

  @override
  double caretX(int offset) {
    final render = _render;
    if (render == null) return 0;
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    return render.localToGlobal(caret.topLeft).dx;
  }

  @override
  TextRange? wordAt(int offset) =>
      _render?.getWordBoundary(TextPosition(offset: offset));

  @override
  bool get focused => _focusNode.hasFocus;

  @override
  void focus() => _focusNode.requestFocus();

  @override
  Widget build(BuildContext context) {
    final preview = widget.preview;
    final active = widget.active;
    final controller = active ? preview._field : _own;
    return EditableText(
      key: _editable,
      controller: controller,
      focusNode: _focusNode,
      readOnly: widget.readOnly || !active,
      showCursor: active && !widget.readOnly,
      style: widget.style,
      textAlign: widget.align,
      cursorColor: themeColors['editorCursor.foreground'],
      backgroundCursorColor: AppColors.textFaint,
      selectionColor: AppColors.textSelection,
      cursorWidth: 1.5,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textInputAction: TextInputAction.newline,
      rendererIgnoresPointer: true,
      // The caret's row comes to the edge, as revealed.
      scrollPadding: EdgeInsets.zero,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      enableInteractiveSelection: true,
    );
  }
}

/// A row shown as it renders, not as text (a TeX block, a rule, while the
/// caret is elsewhere): a click on it puts the caret at [offset] of its
/// unit's text.
class _Atomic extends StatefulWidget {
  const _Atomic({
    required this.preview,
    required this.id,
    required this.offset,
    required this.child,
  });

  final IdeMarkdownPreviewState preview;
  final (int, int) id;
  final int offset;
  final Widget child;

  @override
  State<_Atomic> createState() => _AtomicState();
}

class _AtomicState extends State<_Atomic> implements _UnitHandle {
  @override
  (int, int) get id => widget.id;

  @override
  void initState() {
    super.initState();
    widget.preview._units[widget.id] = this;
  }

  @override
  void didUpdateWidget(_Atomic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id &&
        identical(widget.preview._units[oldWidget.id], this)) {
      widget.preview._units.remove(oldWidget.id);
    }
    widget.preview._units[widget.id] = this;
  }

  @override
  void dispose() {
    if (identical(widget.preview._units[widget.id], this)) {
      widget.preview._units.remove(widget.id);
    }
    super.dispose();
  }

  @override
  Rect? get rect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  int offsetAt(Offset global) => widget.offset;

  @override
  int? positionAt(double x, {required bool top}) => widget.offset;

  @override
  bool atEdge(int offset, {required bool down}) => true;

  @override
  double caretX(int offset) => rect?.left ?? 0;

  @override
  TextRange? wordAt(int offset) => null;

  @override
  bool get focused => false;

  @override
  void focus() => widget.preview._focus.requestFocus();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A control in a row (a task box, a table's tools): the pointer is its,
/// not the text's.
class _Control extends StatefulWidget {
  const _Control({required this.controls, required this.child});

  final Set<BuildContext> controls;
  final Widget child;

  @override
  State<_Control> createState() => _ControlState();
}

class _ControlState extends State<_Control> {
  @override
  void initState() {
    super.initState();
    widget.controls.add(context);
  }

  @override
  void dispose() {
    widget.controls.remove(context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// A code block's language: its name, or a field to type it in while the
/// caret is in the block.
class _CodeLanguage extends StatefulWidget {
  const _CodeLanguage({
    required this.language,
    required this.editable,
    required this.onChanged,
  });

  final String language;
  final bool editable;
  final ValueChanged<String> onChanged;

  @override
  State<_CodeLanguage> createState() => _CodeLanguageState();
}

class _CodeLanguageState extends State<_CodeLanguage> {
  late final _controller = TextEditingController(text: widget.language);
  final _focusNode = FocusNode(debugLabel: 'markdown code language');

  @override
  void didUpdateWidget(_CodeLanguage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && _controller.text != widget.language) {
      _controller.text = widget.language;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: AppColors.textMuted, fontSize: 11.5);
    if (!widget.editable) return Text(widget.language, style: style);
    return SizedBox(
      width: 96,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: style,
        textAlign: TextAlign.right,
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
          hintText: context.l10n.markdownCodeLanguage,
          hintStyle: style.copyWith(color: AppColors.textFaint),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

/// An image of the document: a file of the project's host, read with
/// [read], or a web one; its alt text when it cannot be shown.
class _MarkdownImage extends StatelessWidget {
  const _MarkdownImage({
    required this.target,
    required this.alt,
    required this.title,
    required this.read,
  });

  final ({Uri? url, String? path})? target;
  final String alt;
  final String? title;
  final Future<Uint8List> Function(String path) read;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    final Widget image;
    if (target?.url case final url?) {
      image = Image.network(
        url.toString(),
        errorBuilder: (context, _, _) => _missing(),
      );
    } else if (target?.path case final path?) {
      image = FutureBuilder<Uint8List>(
        future: read(path),
        builder: (context, snapshot) {
          if (snapshot.hasError) return _missing();
          final bytes = snapshot.data;
          if (bytes == null) return const SizedBox(width: 16, height: 16);
          if (p.extension(path).toLowerCase() == '.svg') {
            return SvgPicture.memory(
              bytes,
              errorBuilder: (context, _, _) => _missing(),
            );
          }
          return Image.memory(
            bytes,
            errorBuilder: (context, _, _) => _missing(),
          );
        },
      );
    } else {
      image = _missing();
    }
    final tip = title ?? (alt.isEmpty ? null : alt);
    return tip == null ? image : Tooltip(message: tip, child: image);
  }

  Widget _missing() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      border: Border.all(color: AppColors.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 14, color: AppColors.textMuted),
        if (alt.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(alt, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ],
    ),
  );
}
