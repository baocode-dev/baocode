import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../vs/base/common/strings_cursor.dart' show GraphemeIterator;
import '../vs/editor/common/commands/cursor_command.dart';
import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
import '../vs/editor/common/core/selection.dart';
import '../vs/editor/common/cursor/cursor_column_selection.dart';
import '../vs/editor/common/cursor/cursor_common.dart';
import '../vs/editor/common/cursor/cursor_delete_operations.dart';
import '../vs/editor/common/cursor/cursor_type_operations.dart';
import '../vs/editor/common/cursor/cursor_word_operations.dart';
import '../vs/editor/common/encoded_token_attributes.dart';
import '../vs/editor/common/languages/language_configuration.dart';
import '../vs/editor/common/languages/language_configuration_registry.dart';
import '../vs/editor/common/model/indentation_guesser.dart';
import '../vs/editor/common/model/search/piece_tree_search.dart'
    show SearchParams;
import '../vs/editor/contrib/comment/browser/block_comment_command.dart';
import '../vs/editor/contrib/comment/browser/line_comment_command.dart';
import '../vs/editor/contrib/linesOperations/browser/lines_operations.dart';
import '../vs/editor/contrib/multicursor/browser/multicursor.dart';
import '../vs/editor/contrib/smartSelect/browser/smart_select.dart';
import '../vs/editor/contrib/snippet/browser/snippet_session.dart';
import 'bracket_matching.dart' show defaultBracketPairs;
import 'document_snapshot.dart';
import 'editor_document_model.dart';

/// Returns the offset [rows] visual rows from [offset], keeping [preferredX]
/// (see `EditorViewHost.verticalTarget`).
typedef EditorVerticalTarget = ({int offset, double x}) Function(
  int offset,
  int rows, {
  double? preferredX,
});

/// Editing state for the opt-in painted surface: Monaco's cursor engine
/// (multiple cursors, word navigation, language-aware typing, comments, line
/// operations and grouped undo) over an [EditorDocumentModel].
///
/// [value] is the primary cursor as the platform text input sees it;
/// [selections] lists every cursor, primary first, then in creation order.
/// Assigning [value] is the platform input path: a plain insertion at the
/// primary cursor is typed (replicated to every cursor, with auto-closing),
/// other changes are applied raw. After such an assignment [value] may differ
/// from what was assigned; the input client must then send it back to the
/// platform. The caller owns an injected [document]; this controller owns its
/// default one. Inserted line breaks use the document's dominant EOL.
class EditorSurfaceController extends ValueNotifier<TextEditingValue> {
  EditorSurfaceController({EditorDocumentModel? document})
    : document = document ?? EditorDocumentModel(''),
      _ownsDocument = document == null,
      super(
        TextEditingValue(
          text: document?.text ?? '',
          selection: TextSelection.collapsed(
            offset: (document?.text ?? '').length,
          ),
        ),
      );

  final EditorDocumentModel document;
  final bool _ownsDocument;
  bool _disposed = false;

  /// Secondary cursors in creation order (the primary is [value]'s).
  List<TextSelection> _secondary = const [];

  /// Sticky x per cursor (same order as [selections]) for vertical moves.
  List<double?>? _preferredXs;
  int? _revealOffset;
  EditOperationType _prevEditType = EditOperationType.other;
  int _lastEditVersion = -1;

  /// Auto-inserted closing characters (offsets into the current text).
  List<_AutoClosed> _autoClosed = const [];
  MultiCursorSession? _multiCursorSession;
  _ClipboardMetadata? _clipboardMetadata;

  /// Told what [copy] and [cut] put on the clipboard, and the lines (from
  /// 1) it is from, when it is from one place: one selection, or one
  /// cursor's line.
  void Function(String text, int startLine, int endLine)? onCopy;

  /// Takes a paste before the clipboard's text is read (files and pictures
  /// in a markdown document): completes with whether it pasted, and then
  /// the text is not. Every paste comes here: the keys, the Edit menu, the
  /// context menu.
  Future<bool> Function()? onPaste;
  final List<List<TextSelection>> _cursorUndoStack = [];
  ColumnSelectResult? _columnSelectData;
  (int, String?)? _eolCache;

  /// Document version after the latest edit made while the input method was
  /// composing; the commit coalesces with it into one undo step.
  int _compositionEditVersion = -1;

  /// The text of the latest keyboard typing and the version it produced.
  String? _typedText;
  String? _typing;
  int _typedVersion = -1;

  /// The active snippet session (upstream SnippetController2), if any.
  SnippetSession? _snippet;
  bool _snippetBusy = false;

  // ---- options ---------------------------------------------------------------

  /// Language rules for comments, brackets and indentation. Null disables
  /// language-aware typing (auto-closing, surrounding, enter rules, electric
  /// characters); use [plainTextLanguageConfiguration] for Monaco's defaults.
  LanguageConfiguration? get languageConfiguration => _languageConfiguration;
  LanguageConfiguration? _languageConfiguration;
  set languageConfiguration(LanguageConfiguration? value) {
    if (identical(value, _languageConfiguration)) return;
    _languageConfiguration = value;
    _resolvedLanguage = value == null
        ? null
        : ResolvedLanguageConfiguration(value);
    _config = null;
  }

  ResolvedLanguageConfiguration? _resolvedLanguage;

  int get tabSize => _tabSize;
  int _tabSize = 4;
  set tabSize(int value) {
    if (value < 1 || value == _tabSize) return;
    _tabSize = value;
    _config = null;
  }

  bool get insertSpaces => _insertSpaces;
  bool _insertSpaces = true;
  set insertSpaces(bool value) {
    if (value == _insertSpaces) return;
    _insertSpaces = value;
    _config = null;
  }

  /// Monaco `editor.autoIndent` (default full).
  EditorAutoIndentStrategy get autoIndent => _autoIndent;
  EditorAutoIndentStrategy _autoIndent = EditorAutoIndentStrategy.full;
  set autoIndent(EditorAutoIndentStrategy value) {
    _autoIndent = value;
    _config = null;
  }

  CursorConfiguration? _config;

  /// The options used by the ported cursor operations.
  CursorConfiguration get cursorConfig => _config ??= CursorConfiguration(
    tabSize: _tabSize,
    insertSpaces: _insertSpaces,
    autoIndent: _autoIndent,
    language: _resolvedLanguage,
    standardTokenTypeAt: _resolvedLanguage == null ? null : _tokenTypeAt,
  );

  /// Guesses [tabSize]/[insertSpaces] from the document (upstream
  /// `editor.detectIndentation`), keeping the current values as defaults.
  void detectIndentation() {
    final model = DocumentCursorModel(document.snapshot);
    final guess = guessIndentation(
      model.getLineCount(),
      model.getLineContent,
      _tabSize,
      _insertSpaces,
    );
    tabSize = guess.tabSize;
    insertSpaces = guess.insertSpaces;
  }

  // ---- selection state -------------------------------------------------------

  /// Every selection, primary first. The primary is always [value]'s selection
  /// (the one the platform text input sees); views paint all of them.
  List<TextSelection> get selections => [value.selection, ..._secondary];

  bool get hasMultipleSelections => _secondary.isNotEmpty;

  /// The offset a view should reveal: the most recently added cursor (e.g.
  /// after add-next-occurrence) or the primary cursor's extent.
  int get revealOffset {
    final offset = _revealOffset;
    if (offset != null && offset <= value.text.length) return offset;
    return value.selection.isValid ? value.selection.extentOffset : 0;
  }

  /// Replaces every cursor; the first becomes the primary. Overlapping
  /// selections merge.
  void setSelections(List<TextSelection> selections) {
    if (_disposed || selections.isEmpty) return;
    _pushCursorUndo();
    _setSelections(selections, reveal: selections.last.extentOffset);
  }

  void select(int base, int extent) {
    if (_disposed) return;
    _setSelections([TextSelection(baseOffset: base, extentOffset: extent)]);
  }

  void selectAll() => select(0, value.text.length);

  /// Adds a collapsed secondary cursor (alt/option+click). Clicking an
  /// existing collapsed cursor removes it instead, unless it is the last one.
  void addCursor(int offset) {
    if (_disposed) return;
    offset = offset.clamp(0, value.text.length);
    final current = selections;
    final existing = current.indexWhere(
      (s) => s.isCollapsed && s.extentOffset == offset,
    );
    _pushCursorUndo();
    if (existing >= 0 && current.length > 1) {
      _setSelections([...current]..removeAt(existing));
      return;
    }
    _setSelections([
      ...current,
      TextSelection.collapsed(offset: offset),
    ], reveal: offset);
  }

  /// The word (or run of whitespace/separators) that a double click at
  /// [offset] selects, like Monaco's word selection.
  TextRange wordRangeAt(int offset) {
    final snapshot = document.snapshot;
    final position = snapshot.positionAtOffset(offset);
    final range = WordOperations.word(
      cursorConfig.wordClassifier,
      DocumentCursorModel(snapshot),
      position,
    );
    return TextRange(
      start: snapshot.offsetAtPosition(range.getStartPosition()),
      end: snapshot.offsetAtPosition(range.getEndPosition()),
    );
  }

  /// Double click: selects the word at [offset].
  void selectWordAt(int offset) {
    final range = wordRangeAt(offset);
    setSelections([
      TextSelection(baseOffset: range.start, extentOffset: range.end),
    ]);
  }

  /// Triple click / gutter click: selects the full line at [offset],
  /// including its line break. With [anchorOffset] (gutter drag), selects
  /// every line from the anchor's to [offset]'s, oriented towards [offset].
  void selectLineAt(int offset, {int? anchorOffset}) {
    final snapshot = document.snapshot;
    final line = snapshot.positionAtOffset(offset).lineNumber - 1;
    final anchor =
        snapshot.positionAtOffset(anchorOffset ?? offset).lineNumber - 1;
    final first = line < anchor ? line : anchor;
    final last = line < anchor ? anchor : line;
    final start = snapshot.lineStarts[first];
    final end = snapshot.contentEnds[last] + snapshot.newlineLengths[last];
    setSelections([
      line < anchor
          ? TextSelection(baseOffset: end, extentOffset: start)
          : TextSelection(baseOffset: start, extentOffset: end),
    ]);
  }

  /// Column (box) selection between two offsets, e.g. for shift+alt+drag.
  /// Visible columns may exceed the line ends (pointer beyond the text).
  void columnSelect(
    int anchorOffset,
    int activeOffset, {
    int? anchorVisibleColumn,
    int? activeVisibleColumn,
  }) {
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final config = cursorConfig;
    final from = snapshot.positionAtOffset(anchorOffset);
    final to = snapshot.positionAtOffset(activeOffset);
    final result = ColumnSelection.columnSelect(
      config,
      model,
      from.lineNumber,
      anchorVisibleColumn ?? config.visibleColumnFromColumn(model, from),
      to.lineNumber,
      activeVisibleColumn ?? config.visibleColumnFromColumn(model, to),
    );
    _applyColumnSelect(result);
  }

  /// Extends the current column selection (shift+alt+arrows).
  void columnSelectMove({int columns = 0, int lines = 0}) {
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final config = cursorConfig;
    var data = _columnSelectData;
    if (data == null) {
      final s = value.selection;
      final from = snapshot.positionAtOffset(s.isValid ? s.baseOffset : 0);
      final to = snapshot.positionAtOffset(s.isValid ? s.extentOffset : 0);
      data = ColumnSelection.columnSelect(
        config,
        model,
        from.lineNumber,
        config.visibleColumnFromColumn(model, from),
        to.lineNumber,
        config.visibleColumnFromColumn(model, to),
      );
    }
    if (columns < 0) {
      data = ColumnSelection.columnSelectLeft(config, model, data);
    }
    if (columns > 0) {
      data = ColumnSelection.columnSelectRight(config, model, data);
    }
    if (lines < 0) {
      data = ColumnSelection.columnSelectUp(config, model, data, -lines);
    }
    if (lines > 0) {
      data = ColumnSelection.columnSelectDown(config, model, data, lines);
    }
    _applyColumnSelect(data);
  }

  void _applyColumnSelect(ColumnSelectResult result) {
    final snapshot = document.snapshot;
    _pushCursorUndo();
    final selections = [
      for (final s in result.selections) _toTextSelection(snapshot, s),
    ];
    _setSelections(
      result.reversed ? selections.reversed.toList() : selections,
      reveal: selections.last.extentOffset,
    );
    _columnSelectData = result;
  }

  /// Requests that a listening surface reveal the current selection, even when
  /// its offsets have not changed. Does not alter text, composing, or history.
  void revealSelection() {
    if (!_disposed) notifyListeners();
  }

  /// Sets cursors (normalized: clamped, overlapping ones merged) and, when
  /// given, a new [text] that the document already contains.
  void _setSelections(
    List<TextSelection> requested, {
    bool fromEdit = false,
    List<double?>? preferredXs,
    int? reveal,
    TextRange composing = TextRange.empty,
    bool keepColumnSelect = false,
    bool keepSession = false,
  }) {
    if (_disposed) return;
    final text = document.text;
    final normalized = _normalize(requested, text.length, preferredXs);
    final primary = normalized.first.$1;
    final secondary = [for (final entry in normalized.skip(1)) entry.$1];
    _preferredXs = preferredXs == null
        ? null
        : [for (final entry in normalized) entry.$2];
    _revealOffset = reveal;
    if (!keepColumnSelect) _columnSelectData = null;
    if (!keepSession) _multiCursorSession = null;
    if (!fromEdit) {
      _prevEditType = EditOperationType.other;
      document.closeUndoGroup();
    }
    final next = TextEditingValue(
      text: text,
      selection: primary,
      composing: composing,
    );
    final secondaryChanged = !listEquals(secondary, _secondary);
    _secondary = secondary;
    _pruneAutoClosed([primary, ...secondary]);
    final snippetCancelled = _updateSnippetState([primary, ...secondary]);
    if (next == super.value) {
      if (snippetCancelled) notifyListeners();
      if (secondaryChanged || reveal != null) notifyListeners();
    } else {
      super.value = next;
    }
  }

  /// Monaco's cursor merge: sort by start; merge overlapping (or touching,
  /// when one is collapsed) selections; the older cursor wins direction.
  static List<(TextSelection, double?)> _normalize(
    List<TextSelection> requested,
    int length,
    List<double?>? xs,
  ) {
    final entries = <(int, TextSelection, double?)>[];
    for (var i = 0; i < requested.length; i++) {
      final s = requested[i];
      final base = s.isValid ? s.baseOffset.clamp(0, length) : 0;
      final extent = s.isValid ? s.extentOffset.clamp(0, length) : 0;
      entries.add((
        i,
        TextSelection(
          baseOffset: base,
          extentOffset: extent,
          affinity: s.affinity,
        ),
        xs != null && i < xs.length ? xs[i] : null,
      ));
    }
    if (entries.length > 1) {
      final sorted = List.of(entries)
        ..sort((a, b) {
          final start = a.$2.start.compareTo(b.$2.start);
          return start != 0 ? start : a.$2.end.compareTo(b.$2.end);
        });
      final removed = <int>{};
      final replaced = <int, (TextSelection, double?)>{};
      // Upstream gives the last added cursor's direction precedence.
      var lastAdded = entries.length - 1;
      var i = 0;
      while (i < sorted.length - 1) {
        final current = sorted[i];
        final next = sorted[i + 1];
        final a = replaced[current.$1]?.$1 ?? current.$2;
        final b = next.$2;
        final merge = a.isCollapsed || b.isCollapsed
            ? b.start <= a.end
            : b.start < a.end;
        if (!merge) {
          i++;
          continue;
        }
        final winnerIsCurrent = current.$1 < next.$1;
        final winner = winnerIsCurrent ? current : next;
        final loser = winnerIsCurrent ? next : current;
        final winnerSelection = replaced[winner.$1]?.$1 ?? winner.$2;
        final loserSelection = replaced[loser.$1]?.$1 ?? loser.$2;
        final start = a.start < b.start ? a.start : b.start;
        final end = a.end > b.end ? a.end : b.end;
        final directionFrom = loser.$1 == lastAdded
            ? loserSelection
            : winnerSelection;
        if (loser.$1 == lastAdded) lastAdded = winner.$1;
        final ltr = directionFrom.baseOffset <= directionFrom.extentOffset;
        final merged = start == end
            ? TextSelection.collapsed(offset: start)
            : TextSelection(
                baseOffset: ltr ? start : end,
                extentOffset: ltr ? end : start,
              );
        replaced[winner.$1] = (merged, replaced[winner.$1]?.$2 ?? winner.$3);
        removed.add(loser.$1);
        // Keep the winner at position i and compare it with the following.
        sorted[i] = (winner.$1, merged, winner.$3);
        sorted.removeAt(i + 1);
      }
      return [
        for (final entry in entries)
          if (!removed.contains(entry.$1))
            replaced[entry.$1] ?? (entry.$2, entry.$3),
      ];
    }
    return [for (final entry in entries) (entry.$2, entry.$3)];
  }

  void _pushCursorUndo() {
    _cursorUndoStack.add(selections);
    if (_cursorUndoStack.length > 50) _cursorUndoStack.removeAt(0);
  }

  /// Monaco `cursorUndo` (Cmd/Ctrl+U): restores the previous cursor state.
  bool cursorUndo() {
    if (_disposed || _cursorUndoStack.isEmpty) return false;
    final previous = _cursorUndoStack.removeLast();
    if (previous.any((s) => s.end > value.text.length)) return false;
    _setSelections(previous, reveal: previous.first.extentOffset);
    return true;
  }

  /// removeSecondaryCursors: keeps only the primary cursor, with its
  /// selection. False when there was one cursor.
  bool removeSecondaryCursors() {
    if (_disposed || _secondary.isEmpty) return false;
    _pushCursorUndo();
    _setSelections([value.selection]);
    return true;
  }

  /// cancelSelection: keeps only the primary cursor, collapsed to its
  /// active end. False when there was no selection to cancel.
  bool collapseSelection() {
    if (_disposed) return false;
    final s = value.selection;
    if (_secondary.isEmpty && (!s.isValid || s.isCollapsed)) return false;
    final offset = s.isValid ? s.extentOffset : 0;
    _pushCursorUndo();
    _setSelections([TextSelection.collapsed(offset: offset)]);
    return true;
  }

  /// Escape: removes secondary cursors, or else collapses the selection to
  /// its active end. Returns false when there was nothing to do.
  bool cancelSelection() {
    if (_disposed) return false;
    if (_secondary.isNotEmpty) {
      _setSelections([value.selection]);
      return true;
    }
    final s = value.selection;
    if (s.isValid && !s.isCollapsed) {
      select(s.extentOffset, s.extentOffset);
      return true;
    }
    return false;
  }

  // ---- platform input ----------------------------------------------------------

  /// Assign the complete platform value, including its raw UTF-16 text,
  /// selection orientation, and composing range, as one atomic notification.
  @override
  set value(TextEditingValue next) {
    if (_disposed) return;
    final prev = super.value;
    if (next.text == prev.text) {
      if (next.selection == prev.selection) {
        if (next != prev) super.value = next;
        return;
      }
      // A platform selection change replaces every cursor.
      _setSelections([next.selection], composing: next.composing);
      if (super.value != next) super.value = next;
      return;
    }
    final wasComposing = _isComposing(prev.composing, prev.text.length);
    final isComposing = _isComposing(next.composing, next.text.length);
    if (!wasComposing && !isComposing) {
      final inserted = _plainInsertion(prev, next);
      // Multi-line platform text (e.g. semantics setText) stays raw.
      if (inserted != null &&
          (inserted == '\n' ||
              (!inserted.contains('\n') && !inserted.contains('\r')))) {
        type(inserted);
        return;
      }
    }
    _applyRawValue(
      prev,
      next,
      wasComposing: wasComposing,
      isComposing: isComposing,
    );
  }

  static bool _isComposing(TextRange composing, int length) =>
      composing.isValid && !composing.isCollapsed && composing.end <= length;

  /// The text that replaced [prev]'s selection, when [next] is exactly that
  /// replacement with a caret after it.
  static String? _plainInsertion(TextEditingValue prev, TextEditingValue next) {
    final selection = prev.selection;
    if (!selection.isValid || !next.selection.isValid) return null;
    if (!next.selection.isCollapsed) return null;
    final start = selection.start;
    final end = selection.end;
    final caret = next.selection.extentOffset;
    if (end > prev.text.length || caret < start) return null;
    if (next.text.length - caret != prev.text.length - end) return null;
    if (caret > next.text.length) return null;
    for (var i = 0; i < start; i++) {
      if (prev.text.codeUnitAt(i) != next.text.codeUnitAt(i)) return null;
    }
    for (var i = end, j = caret; i < prev.text.length; i++, j++) {
      if (prev.text.codeUnitAt(i) != next.text.codeUnitAt(j)) return null;
    }
    final inserted = next.text.substring(start, caret);
    return inserted.isEmpty && start == end ? null : inserted;
  }

  void _applyRawValue(
    TextEditingValue prev,
    TextEditingValue next, {
    required bool wasComposing,
    required bool isComposing,
  }) {
    final before = prev.text;
    var prefix = 0;
    while (prefix < before.length &&
        prefix < next.text.length &&
        before.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < next.text.length - prefix &&
        before.codeUnitAt(before.length - suffix - 1) ==
            next.text.codeUnitAt(next.text.length - suffix - 1)) {
      suffix++;
    }
    // Replacing the whole document avoids splitting a surrogate across edit
    // pieces; CRLF interiors are fine for raw offset edits.
    bool splitsPair(String text, int offset) =>
        offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF;
    var end = before.length - suffix;
    if (splitsPair(before, prefix) ||
        splitsPair(before, end) ||
        splitsPair(next.text, prefix) ||
        splitsPair(next.text, next.text.length - suffix)) {
      prefix = 0;
      end = before.length;
      suffix = 0;
    }
    final inserted = next.text.substring(prefix, next.text.length - suffix);
    final composition = wasComposing || isComposing;
    final canCoalesce =
        wasComposing && document.version == _compositionEditVersion;
    _eolCache = null;
    if (!canCoalesce) document.closeUndoGroup();
    final beforeSelections = selections;
    document.applyOffsetEdits(
      [EditorOffsetEdit(prefix, end, inserted)],
      selectionsBefore: beforeSelections,
      coalesce: canCoalesce,
    );
    assert(document.text == next.text);
    _lastEditVersion = document.version;
    _compositionEditVersion = isComposing ? document.version : -1;
    _prevEditType = composition
        ? EditOperationType.typingOther
        : EditOperationType.other;
    _mapAutoClosed([(prefix, end, inserted.length)]);
    _snippet?.acceptEdits([(prefix, end, inserted.length)]);
    // Secondary cursors follow the edit; those inside it are dropped.
    final delta = inserted.length - (end - prefix);
    int? map(int offset) =>
        offset <= prefix ? offset : (offset >= end ? offset + delta : null);
    final secondary = <TextSelection>[];
    for (final s in _secondary) {
      final base = map(s.baseOffset);
      final extent = map(s.extentOffset);
      if (base != null && extent != null) {
        secondary.add(TextSelection(baseOffset: base, extentOffset: extent));
      }
    }
    _secondary = secondary;
    _updateSnippetState([next.selection, ...secondary]);
    // Keep the raw platform value (selection/composing) exactly.
    super.value = next;
    document.setUndoSelectionsAfter(selections);
    if (!composition) document.closeUndoGroup();
    if (wasComposing && !isComposing) {
      _finishComposition(prev.composing.start, next);
    }
  }

  /// On composition commit, replicate the committed text to the secondary
  /// cursors and run the auto-closing interceptors for a single character.
  void _finishComposition(int compositionStart, TextEditingValue committed) {
    final caret = committed.selection;
    if (!caret.isValid ||
        !caret.isCollapsed ||
        caret.extentOffset < compositionStart) {
      return;
    }
    final text = committed.text.substring(compositionStart, caret.extentOffset);
    if (text.isEmpty) return;
    if (_secondary.isNotEmpty) {
      final snapshot = document.snapshot;
      final commands = <CursorCommand?>[
        NoopCursorCommand(_toSelection(snapshot, caret)),
        for (final s in _secondary)
          ReplaceCommand(_toSelection(snapshot, s), text),
      ];
      _executeCommands(
        commands,
        type: EditOperationType.typingOther,
        pushBefore: false,
        pushAfter: false,
      );
    }
    if (_resolvedLanguage != null && text.length == 1) {
      final snapshot = document.snapshot;
      final result = TypeOperations.compositionEndWithInterceptors(
        cursorConfig,
        DocumentCursorModel(snapshot),
        _cursorSelections(snapshot),
        _autoClosedRanges(snapshot),
        text,
      );
      if (result != null) _runResult(result);
    }
  }

  // ---- typing & editing ----------------------------------------------------------

  /// Types [text] at every cursor, as the keyboard does: a single character
  /// goes through Monaco's typing interceptors (enter rules, auto-closing,
  /// overtyping, surrounding, electric characters); longer text is inserted
  /// as is.
  ///
  /// [typeOverride] sees it first, as upstream's editor runs the `type`
  /// command an extension may override.
  void type(String text) {
    if (_disposed || text.isEmpty) return;
    if (typeOverride?.call(text) ?? false) return;
    _typeInternal(text, fromKeyboard: true);
  }

  /// Takes the keyboard's typed text before the editor does (the `type`
  /// command when an extension registered it): true when it took it.
  bool Function(String text)? typeOverride;

  /// `default:type`: types [text] as the keyboard does, past
  /// [typeOverride].
  void typeDefault(String text) => _typeInternal(text, fromKeyboard: true);

  /// `compositionType` (`replacePreviousChar` is its [replaceNextCharCnt]
  /// and [positionDelta] 0): at each caret, [text] replaces the characters
  /// around it; the caret ends [positionDelta] columns from its end.
  void compositionType(
    String text, {
    int replacePrevCharCnt = 0,
    int replaceNextCharCnt = 0,
    int positionDelta = 0,
  }) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    _runResult(
      TypeOperations.compositionType(
        _prevEditType,
        DocumentCursorModel(snapshot),
        _cursorSelections(snapshot),
        text,
        replacePrevCharCnt,
        replaceNextCharCnt,
        positionDelta,
      ),
    );
  }

  void _typeInternal(String text, {required bool fromKeyboard}) {
    if (_disposed || text.isEmpty) return;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final sels = _cursorSelections(snapshot);
    final single =
        text.length == 1 ||
        (text.length == 2 &&
            text.codeUnitAt(0) >= 0xD800 &&
            text.codeUnitAt(0) <= 0xDBFF);
    final normalized = text == '\r\n' || text == '\r' ? '\n' : text;
    final EditOperationResult result;
    if (fromKeyboard && (single || normalized == '\n')) {
      result = TypeOperations.typeWithInterceptors(
        false,
        _prevEditType,
        cursorConfig,
        model,
        sels,
        _autoClosedRanges(snapshot),
        normalized,
      );
    } else {
      result = TypeOperations.typeWithoutInterceptors(
        _prevEditType,
        sels,
        text,
      );
    }
    final version = document.version;
    // Listeners notified by this edit already see what was typed.
    if (fromKeyboard) _typing = text;
    try {
      _runResult(result);
    } finally {
      _typing = null;
    }
    if (fromKeyboard && document.version != version) {
      _typedText = text;
      _typedVersion = document.version;
    }
  }

  /// Enter at every cursor (with auto-indentation and enter rules).
  void newline() => type('\n');

  /// Replaces every selection with [replacement] (no typing interceptors).
  void replaceSelection(String replacement) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    _executeCommands(
      [
        for (final s in _cursorSelections(snapshot))
          ReplaceCommand(s, replacement),
      ],
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  /// Deletes the preceding pinned grapheme (or the exact nonempty selection)
  /// at every cursor. A caret inside a cluster deletes that entire cluster.
  /// In leading indentation, deletes to the previous indent stop; between an
  /// auto-closed pair, deletes both characters.
  void deleteBackward() {
    if (_disposed || !value.selection.isValid) return;
    final snapshot = document.snapshot;
    final result = DeleteOperations.deleteLeft(
      _prevEditType,
      cursorConfig,
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
      _autoClosedRanges(snapshot),
      (position) => snapshot.positionAtOffset(
        _adjacentGrapheme(
          snapshot.offsetAtPosition(position),
          forward: false,
        ).start,
      ),
    );
    _runDelete(result, EditOperationType.deletingLeft, snapshot);
  }

  /// Deletes the following pinned grapheme (or the exact nonempty selection)
  /// at every cursor. A caret inside a cluster deletes that entire cluster.
  void deleteForward() {
    if (_disposed || !value.selection.isValid) return;
    final snapshot = document.snapshot;
    final result = DeleteOperations.deleteRight(
      _prevEditType,
      cursorConfig,
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
      (position) => snapshot.positionAtOffset(
        _adjacentGrapheme(
          snapshot.offsetAtPosition(position),
          forward: true,
        ).end,
      ),
    );
    _runDelete(result, EditOperationType.deletingRight, snapshot);
  }

  void _runDelete(
    DeleteResult result,
    EditOperationType type,
    DocumentSnapshot snapshot,
  ) {
    // Raw platform carets may sit inside a grapheme or CRLF; Selection
    // positions cannot. Delete such clusters by offsets instead.
    final raw = selections;
    final commands = List<CursorCommand?>.of(result.commands);
    for (var i = 0; i < raw.length; i++) {
      final s = raw[i];
      if (!s.isCollapsed) continue;
      final range = _adjacentGrapheme(
        s.extentOffset,
        forward: type == EditOperationType.deletingRight,
      );
      final aligned =
          snapshot.offsetAtPosition(
            snapshot.positionAtOffset(s.extentOffset),
          ) ==
          s.extentOffset;
      final inside = range.start < s.extentOffset && s.extentOffset < range.end;
      if (inside || !aligned) {
        commands[i] = _OffsetReplaceCommand(range.start, range.end, '');
      }
    }
    for (var i = 0; i < raw.length; i++) {
      commands[i] ??= NoopCursorCommand(_toSelection(snapshot, raw[i]));
    }
    _executeCommands(
      commands,
      type: type,
      pushBefore: result.shouldPushStackElementBefore,
      pushAfter: false,
    );
  }

  TextRange _adjacentGrapheme(int offset, {required bool forward}) {
    final text = value.text;
    offset = offset.clamp(0, text.length);
    if ((forward && offset == text.length) || (!forward && offset == 0)) {
      return TextRange.collapsed(offset);
    }
    // Platform values can put a UTF-16 caret inside a surrogate pair. Keep the
    // raw value unchanged, but begin traversal at a complete code point.
    if (offset > 0 &&
        offset < text.length &&
        text.codeUnitAt(offset - 1) >= 0xD800 &&
        text.codeUnitAt(offset - 1) <= 0xDBFF &&
        text.codeUnitAt(offset) >= 0xDC00 &&
        text.codeUnitAt(offset) <= 0xDFFF) {
      offset += forward ? -1 : 1;
    }
    final iterator = GraphemeIterator(text, offset);
    // Walk back from the discovered boundary to include a cluster's other half
    // when the original caret is inside it, including the interior of CRLF.
    if (forward) {
      iterator.nextGraphemeLength();
      final end = iterator.offset;
      iterator.prevGraphemeLength();
      return TextRange(start: iterator.offset, end: end);
    }
    iterator.prevGraphemeLength();
    final start = iterator.offset;
    iterator.nextGraphemeLength();
    return TextRange(start: start, end: iterator.offset);
  }

  /// deleteWordLeft (Alt/Ctrl+Backspace); with [type] wordStart and no
  /// [whitespaceHeuristics], deleteWordStartLeft; with wordEnd,
  /// deleteWordEndLeft.
  void deleteWordLeft({
    WordNavigationType type = WordNavigationType.wordStart,
    bool whitespaceHeuristics = true,
  }) => _deleteRanges((model, config, s, autoClosed) {
    final isPairDelete = DeleteOperations.isAutoClosingPairDelete(
      config,
      model,
      [s],
      autoClosed,
    );
    return WordOperations.deleteWordLeft(
      config.wordClassifier,
      model,
      s,
      type,
      whitespaceHeuristics: whitespaceHeuristics,
      isAutoClosingPairDelete: isPairDelete,
    );
  }, EditOperationType.deletingLeft);

  /// deleteWordRight (Alt/Ctrl+Delete); deleteWordStartRight and
  /// deleteWordEndRight as for [deleteWordLeft].
  void deleteWordRight({
    WordNavigationType type = WordNavigationType.wordEnd,
    bool whitespaceHeuristics = true,
  }) => _deleteRanges(
    (model, config, s, _) => WordOperations.deleteWordRight(
      config.wordClassifier,
      model,
      s,
      type,
      whitespaceHeuristics: whitespaceHeuristics,
    ),
    EditOperationType.deletingRight,
  );

  /// deleteWordPartLeft (⌃⌥Backspace on macOS): to the nearest word start,
  /// word end or camelCase/snake_case boundary.
  void deleteWordPartLeft() => _deleteRanges((model, config, s, autoClosed) {
    final isPairDelete = DeleteOperations.isAutoClosingPairDelete(
      config,
      model,
      [s],
      autoClosed,
    );
    return WordPartOperations.deleteWordPartLeft(
      config.wordClassifier,
      model,
      s,
      isAutoClosingPairDelete: isPairDelete,
    );
  }, EditOperationType.deletingLeft);

  /// deleteWordPartRight (⌃⌥Delete on macOS).
  void deleteWordPartRight() => _deleteRanges(
    (model, config, s, _) =>
        WordPartOperations.deleteWordPartRight(config.wordClassifier, model, s),
    EditOperationType.deletingRight,
  );

  /// deleteAllLeft (Cmd+Backspace on macOS).
  void deleteAllLeft() => _deleteRanges(
    (model, config, s, _) =>
        LinesOperations.deleteAllLeftRanges(model, [s]).firstOrNull,
    EditOperationType.other,
  );

  /// deleteAllRight (Ctrl+K on macOS).
  void deleteAllRight() => _deleteRanges(
    (model, config, s, _) =>
        LinesOperations.deleteAllRightRanges(model, [s]).firstOrNull,
    EditOperationType.other,
  );

  void _deleteRanges(
    Range? Function(
      ICursorSimpleModel model,
      CursorConfiguration config,
      Selection selection,
      List<Range> autoClosed,
    )
    rangeFor,
    EditOperationType type,
  ) {
    if (_disposed || !value.selection.isValid) return;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final autoClosed = _autoClosedRanges(snapshot);
    final commands = <CursorCommand?>[
      for (final s in _cursorSelections(snapshot))
        switch (rangeFor(model, cursorConfig, s, autoClosed)) {
          final range? when !range.isEmpty() => ReplaceCommand(range, ''),
          _ => NoopCursorCommand(s),
        },
    ];
    _executeCommands(commands, type: type, pushBefore: true, pushAfter: true);
  }

  /// Tab: indents multi-line selections, else inserts spaces/tab to the next
  /// indent stop (or the language's indentation on a blank line).
  void tab() {
    if (_disposed) return;
    final snapshot = document.snapshot;
    _executeCommands(
      TypeOperations.tab(
        cursorConfig,
        DocumentCursorModel(snapshot),
        _cursorSelections(snapshot),
      ),
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  /// Shift+Tab / Cmd+[: outdents the lines of every selection.
  void outdentLines() => _shift(unshift: true);

  /// Cmd+]: indents the lines of every selection.
  void indentLines() => _shift(unshift: false);

  void _shift({required bool unshift}) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    final sels = _cursorSelections(snapshot);
    _executeCommands(
      unshift
          ? TypeOperations.outdent(cursorConfig, sels)
          : TypeOperations.indent(cursorConfig, sels),
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  /// Cmd+Enter: inserts a line below each cursor's line.
  void insertLineAfter() => _lineInsert(before: false);

  /// Cmd+Shift+Enter: inserts a line above each cursor's line.
  void insertLineBefore() => _lineInsert(before: true);

  /// lineBreakInsert (⌃O on macOS): breaks the line at each cursor, keeping
  /// the cursors before the break.
  void lineBreakInsert() {
    if (_disposed) return;
    final snapshot = document.snapshot;
    _executeCommands(
      TypeOperations.lineBreakInsert(
        cursorConfig,
        DocumentCursorModel(snapshot),
        _cursorSelections(snapshot),
      ),
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  void _lineInsert({required bool before}) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final sels = _cursorSelections(snapshot);
    _executeCommands(
      before
          ? TypeOperations.lineInsertBefore(cursorConfig, model, sels)
          : TypeOperations.lineInsertAfter(cursorConfig, model, sels),
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  /// editor.action.commentLine (Cmd+/). Falls back to block comments for
  /// languages without a line comment token.
  bool toggleLineComment() {
    final comments = _resolvedLanguage?.comments;
    if (_disposed || comments == null) return false;
    final snapshot = document.snapshot;
    final sels = _cursorSelections(snapshot);
    // Remove selections that would result in commenting the same line twice
    final order = List<int>.generate(sels.length, (i) => i)
      ..sort((a, b) => Range.compareRangesUsingStarts(sels[a], sels[b]));
    final ignoreFirstLine = List<bool>.filled(sels.length, false);
    var prev = order.first;
    for (final curr in order.skip(1)) {
      if (sels[prev].endLineNumber == sels[curr].startLineNumber) {
        if (prev < curr) {
          ignoreFirstLine[curr] = true;
        } else {
          ignoreFirstLine[prev] = true;
          prev = curr;
        }
      }
    }
    _executeCommands(
      [
        for (var i = 0; i < sels.length; i++)
          LineCommentCommand(
            comments,
            sels[i],
            cursorConfig.indentSize,
            LineCommentType.toggle,
            true,
            true,
            ignoreFirstLine: ignoreFirstLine[i],
          ),
      ],
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
    return true;
  }

  /// editor.action.blockComment (Shift+Alt+A).
  bool toggleBlockComment() {
    final comments = _resolvedLanguage?.comments;
    if (_disposed ||
        comments?.blockCommentStartToken == null ||
        comments?.blockCommentEndToken == null) {
      return false;
    }
    final snapshot = document.snapshot;
    _executeCommands(
      [
        for (final s in _cursorSelections(snapshot))
          BlockCommentCommand(s, true, comments),
      ],
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
    return true;
  }

  /// Alt+Up/Down.
  void moveLines({required bool down}) => _runLinesEdit(
    (model, sels) => LinesOperations.moveLines(model, sels, down: down),
  );

  /// Shift+Alt+Up/Down.
  void copyLines({required bool down}) => _runLinesEdit(
    (model, sels) => LinesOperations.copyLines(model, sels, down: down),
  );

  /// Cmd+Shift+K.
  void deleteLines() => _runLinesEdit(LinesOperations.deleteLines);

  /// editor.action.joinLines (⌃J on macOS). False when there was no line to
  /// join.
  bool joinLines() {
    if (_disposed) return false;
    final version = document.version;
    _runLinesEdit(LinesOperations.joinLines);
    return document.version != version;
  }

  /// editor.action.duplicateSelection: a copy of each selection after it
  /// (selected), or of an empty selection's line below it.
  void duplicateSelection() {
    if (_disposed) return;
    final snapshot = document.snapshot;
    _executeCommands(
      [
        for (final s in _cursorSelections(snapshot))
          if (s.isEmpty())
            CopyLineDownCommand(s)
          else
            ReplaceCommandThatSelectsText(
              Range(s.endLineNumber, s.endColumn, s.endLineNumber, s.endColumn),
              _valueInRange(snapshot, s),
            ),
      ],
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  void _runLinesEdit(
    LinesEditResult? Function(ICursorSimpleModel, List<Selection>) operation,
  ) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    final result = operation(
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
    );
    if (result == null) return;
    _executeEdits(result.edits, result.selections);
  }

  /// Cmd+L: selects the current line, then one more line per repeat.
  void expandLineSelection() {
    if (_disposed) return;
    final snapshot = document.snapshot;
    final expanded = LinesOperations.expandLineSelection(
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
    );
    _pushCursorUndo();
    _setSelections([for (final s in expanded) _toTextSelection(snapshot, s)]);
  }

  /// editor.action.transformToUppercase / transformToLowercase. An empty
  /// selection transforms the word at the cursor.
  void transformCase({required bool upper}) {
    if (_disposed) return;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final commands = <CursorCommand?>[];
    for (final s in _cursorSelections(snapshot)) {
      if (s.isEmpty()) {
        final word = WordOperations.getWordAtPosition(
          model,
          cursorConfig.wordClassifier,
          s.getStartPosition(),
        );
        if (word == null) {
          commands.add(NoopCursorCommand(s));
          continue;
        }
        final range = Range(
          s.startLineNumber,
          word.startColumn,
          s.startLineNumber,
          word.endColumn,
        );
        commands.add(
          ReplaceCommandThatPreservesSelection(
            range,
            upper ? word.word.toUpperCase() : word.word.toLowerCase(),
            s,
          ),
        );
      } else {
        final text = _valueInRange(snapshot, s);
        commands.add(
          ReplaceCommandThatSelectsText(
            s,
            upper ? text.toUpperCase() : text.toLowerCase(),
          ),
        );
      }
    }
    _executeCommands(
      commands,
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  // ---- navigation ------------------------------------------------------------------

  /// Move to the next/previous pinned grapheme boundary, keeping CRLF atomic.
  /// Uses VS Code's pinned approximation, not full Unicode segmentation: for
  /// example, consecutive regional indicators are one cluster, not flag pairs.
  /// Explicit selection edges and incoming platform values remain raw UTF-16.
  /// Set [collapseSelection] false to move from a range's extent instead of
  /// collapsing to its edge, as required by accessibility cursor actions.
  void moveHorizontal(
    int direction, {
    bool extend = false,
    bool collapseSelection = true,
  }) {
    if (_disposed || !value.selection.isValid || direction == 0) return;
    _moveEach((s) {
      if (collapseSelection && !extend && !s.isCollapsed) {
        final edge = direction < 0 ? s.start : s.end;
        return TextSelection.collapsed(offset: edge);
      }
      final range = _adjacentGrapheme(s.extentOffset, forward: direction > 0);
      final target = direction < 0 ? range.start : range.end;
      return TextSelection(
        baseOffset: extend ? s.baseOffset : target,
        extentOffset: target,
      );
    });
  }

  /// cursorWordLeft / cursorWordLeftSelect (Alt+Left on macOS, Ctrl+Left
  /// elsewhere): moves to word starts. With [type] wordStart,
  /// cursorWordStartLeft; with wordEnd, cursorWordEndLeft.
  void moveWordLeft({
    bool extend = false,
    WordNavigationType type = WordNavigationType.wordStartFast,
  }) {
    final hasMulticursor = _secondary.isNotEmpty;
    _movePositions(
      (model, position) => WordOperations.moveWordLeft(
        cursorConfig.wordClassifier,
        model,
        position,
        type,
        hasMulticursor,
      ),
      extend: extend,
    );
  }

  /// cursorWordEndRight / cursorWordEndRightSelect: moves to word ends. With
  /// [type] wordStart, cursorWordStartRight (cursorWordRight is wordEnd).
  void moveWordRight({
    bool extend = false,
    WordNavigationType type = WordNavigationType.wordEnd,
  }) => _movePositions(
    (model, position) => WordOperations.moveWordRight(
      cursorConfig.wordClassifier,
      model,
      position,
      type,
    ),
    extend: extend,
  );

  /// cursorWordPartLeft / cursorWordPartRight (+Select; ⌃⌥←/→ on macOS):
  /// moves to the nearest word start, word end or camelCase/snake_case
  /// boundary.
  void moveWordPart({required bool left, bool extend = false}) {
    final hasMulticursor = _secondary.isNotEmpty;
    _movePositions(
      (model, position) => left
          ? WordPartOperations.moveWordPartLeft(
              cursorConfig.wordClassifier,
              model,
              position,
              hasMulticursor,
            )
          : WordPartOperations.moveWordPartRight(
              cursorConfig.wordClassifier,
              model,
              position,
            ),
      extend: extend,
    );
  }

  /// cursorHome: toggles between the first non-whitespace character and the
  /// start of the line.
  void moveToLineStart({bool extend = false}) => _movePositions((
    model,
    position,
  ) {
    final line = position.lineNumber;
    var firstNonBlank = model.getLineFirstNonWhitespaceColumn(line);
    if (firstNonBlank == 0) firstNonBlank = 1;
    return Position(line, position.column == firstNonBlank ? 1 : firstNonBlank);
  }, extend: extend);

  /// cursorLineStart (⌃A on macOS): column 1 (cursorHome alternates with
  /// the first non-whitespace character).
  void moveToLineFirstColumn({bool extend = false}) => _movePositions(
    (model, position) => Position(position.lineNumber, 1),
    extend: extend,
  );

  /// cursorEnd and cursorLineEnd.
  void moveToLineEnd({bool extend = false}) => _movePositions(
    (model, position) => Position(
      position.lineNumber,
      model.getLineMaxColumn(position.lineNumber),
    ),
    extend: extend,
  );

  /// cursorTop (Cmd+Up / Ctrl+Home).
  void moveToDocumentStart({bool extend = false}) =>
      _moveEach((s) => _moveTo(s, 0, extend));

  /// cursorBottom (Cmd+Down / Ctrl+End).
  void moveToDocumentEnd({bool extend = false}) =>
      _moveEach((s) => _moveTo(s, value.text.length, extend));

  static TextSelection _moveTo(TextSelection s, int offset, bool extend) =>
      TextSelection(
        baseOffset: extend ? s.baseOffset : offset,
        extentOffset: offset,
      );

  void _movePositions(
    Position Function(ICursorSimpleModel model, Position position) move, {
    required bool extend,
  }) {
    if (_disposed || !value.selection.isValid) return;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    _moveEach((s) {
      final target = snapshot.offsetAtPosition(
        move(model, snapshot.positionAtOffset(s.extentOffset)),
      );
      return _moveTo(s, target, extend);
    });
  }

  void _moveEach(TextSelection Function(TextSelection) move) {
    final moved = [for (final s in selections) move(s)];
    _setSelections(moved);
  }

  /// Arrow up/down and page up/down for every cursor. Consecutive vertical
  /// moves keep each cursor's preferred x.
  void moveVertical(
    int rows,
    EditorVerticalTarget target, {
    bool extend = false,
  }) {
    if (_disposed || rows == 0 || !value.selection.isValid) return;
    final current = selections;
    final xs = _preferredXs != null && _preferredXs!.length == current.length
        ? _preferredXs!
        : List<double?>.filled(current.length, null);
    final snapshot = document.snapshot;
    final moved = <TextSelection>[];
    final nextXs = <double?>[];
    for (var i = 0; i < current.length; i++) {
      final s = current[i];
      // Without shift, a selection moves from its start (up) or end (down).
      final origin = !extend && !s.isCollapsed
          ? (rows < 0 ? s.start : s.end)
          : s.extentOffset;
      final result = target(origin, rows, preferredX: xs[i]);
      var offset = result.offset;
      if (offset == origin) {
        // At the first/last row, move to the start/end of the document line.
        final line = snapshot.positionAtOffset(origin).lineNumber;
        if (rows < 0 && line == 1) offset = 0;
        if (rows > 0 && line == snapshot.lineCount) {
          offset = snapshot.text.length;
        }
      }
      moved.add(_moveTo(s, offset, extend));
      nextXs.add(result.x);
    }
    _setSelections(moved, preferredXs: nextXs);
  }

  /// editor.action.insertCursorAbove/Below (Cmd+Alt+Up/Down): adds a cursor
  /// one row above/below every cursor.
  void addCursorsVertically(int rows, EditorVerticalTarget target) {
    if (_disposed || rows == 0 || !value.selection.isValid) return;
    final current = selections;
    final xs = _preferredXs != null && _preferredXs!.length == current.length
        ? _preferredXs!
        : List<double?>.filled(current.length, null);
    final added = <TextSelection>[];
    final addedXs = <double?>[];
    for (var i = 0; i < current.length; i++) {
      final result = target(current[i].extentOffset, rows, preferredX: xs[i]);
      if (result.offset == current[i].extentOffset) continue;
      added.add(TextSelection.collapsed(offset: result.offset));
      addedXs.add(result.x);
    }
    if (added.isEmpty) return;
    _pushCursorUndo();
    _setSelections(
      [...current, ...added],
      preferredXs: [...xs, ...addedXs],
      reveal: (rows < 0 ? added.first : added.last).extentOffset,
    );
  }

  /// editor.action.addSelectionToNextFindMatch (Cmd/Ctrl+D). Returns false
  /// when there is nothing to add.
  bool addSelectionToNextFindMatch() => _nextFindMatch(move: false);

  /// editor.action.moveSelectionToNextFindMatch (Cmd+K Cmd+D).
  bool moveSelectionToNextFindMatch() => _nextFindMatch(move: true);

  bool _nextFindMatch({required bool move}) {
    if (_disposed || !value.selection.isValid) return false;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final sels = _cursorSelections(snapshot);
    final session =
        _multiCursorSession ??
        MultiCursorSession.create(
          model,
          cursorConfig.wordClassifier,
          sels,
          (range) => _valueInRange(snapshot, range),
        );
    if (session == null) return false;
    final result = move
        ? session.moveSelectionToNextFindMatch(sels, _findNext)
        : session.addSelectionToNextFindMatch(sels, _findNext);
    _multiCursorSession = session;
    if (result == null) return false;
    _pushCursorUndo();
    final next = [for (final s in result) _toTextSelection(snapshot, s)];
    _setSelections(next, reveal: next.last.extentOffset, keepSession: true);
    return true;
  }

  Range? _findNext(
    String searchText,
    Position start, {
    required bool matchCase,
    required bool wholeWord,
  }) => document
      .findNextMatch(
        SearchParams(
          searchText,
          matchCase: matchCase,
          wordSeparators: wholeWord ? cursorConfig.wordSeparators : null,
        ),
        start,
      )
      ?.range;

  /// editor.action.selectHighlights (Cmd/Ctrl+Shift+L): selects every
  /// occurrence of the selection (or of the word at the cursor).
  bool selectAllOccurrences() {
    if (_disposed || !value.selection.isValid) return false;
    final snapshot = document.snapshot;
    final model = DocumentCursorModel(snapshot);
    final sels = _cursorSelections(snapshot);
    final session =
        _multiCursorSession ??
        MultiCursorSession.create(
          model,
          cursorConfig.wordClassifier,
          sels,
          (range) => _valueInRange(snapshot, range),
        );
    if (session == null) return false;
    final matches = document.findMatches(
      SearchParams(
        session.searchText,
        matchCase: session.matchCase,
        wordSeparators: session.wholeWord ? cursorConfig.wordSeparators : null,
      ),
      limitResultCount: 1 << 30,
    );
    if (matches.isEmpty) return false;
    // Upstream keeps the primary on the match containing it.
    final primary = value.selection;
    final ranges = [
      for (final match in matches)
        TextSelection(
          baseOffset: snapshot.offsetAtPosition(match.range.getStartPosition()),
          extentOffset: snapshot.offsetAtPosition(match.range.getEndPosition()),
        ),
    ];
    final primaryIndex = ranges.indexWhere(
      (r) => r.start <= primary.start && primary.end <= r.end,
    );
    if (primaryIndex > 0) ranges.insert(0, ranges.removeAt(primaryIndex));
    _pushCursorUndo();
    _setSelections(ranges, reveal: ranges.first.extentOffset);
    return true;
  }

  /// editor.action.insertCursorAtEndOfEachLineSelected (Shift+Alt+I): a
  /// cursor at the end of each selected line. False without a selection.
  bool insertCursorAtEndOfEachLineSelected() {
    if (_disposed || !value.selection.isValid) return false;
    final snapshot = document.snapshot;
    final cursors = cursorsAtEndOfEachLineSelected(
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
    );
    if (cursors.isEmpty) return false;
    _pushCursorUndo();
    _setSelections([for (final s in cursors) _toTextSelection(snapshot, s)]);
    return true;
  }

  // Upstream SmartSelectController state: the ranges of each cursor, kept
  // while the selections are the ones it set.
  List<SelectionRanges>? _smartSelect;
  List<TextSelection>? _smartSelectSelections;
  int _smartSelectVersion = -1;

  /// editor.action.smartSelect.expand / shrink: selects the next larger (or
  /// smaller) syntactic range at each cursor (see [SmartSelect]).
  bool smartSelect({required bool expand}) {
    if (_disposed || !value.selection.isValid) return false;
    final snapshot = document.snapshot;
    var state = _smartSelect;
    if (state == null ||
        _smartSelectVersion != document.version ||
        !listEquals(_smartSelectSelections, selections)) {
      final sels = _cursorSelections(snapshot);
      final ranges = SmartSelect.provideSelectionRanges(
        DocumentCursorModel(snapshot),
        cursorConfig.wordClassifier,
        [for (final s in sels) s.getPosition()],
        brackets: _languageConfiguration?.brackets ?? defaultBracketPairs,
      );
      state = [
        for (var i = 0; i < sels.length; i++)
          SelectionRanges(0, [
            // prepend current selection
            sels[i],
            // filter ranges inside the selection
            for (final range in ranges[i])
              if (range.containsPosition(sels[i].getStartPosition()) &&
                  range.containsPosition(sels[i].getEndPosition()))
                range,
          ]),
      ];
    }
    state = [for (final ranges in state) ranges.mov(expand)];
    _pushCursorUndo();
    _setSelections([
      for (final ranges in state)
        TextSelection(
          baseOffset: snapshot.offsetAtPosition(
            ranges.current.getStartPosition(),
          ),
          extentOffset: snapshot.offsetAtPosition(
            ranges.current.getEndPosition(),
          ),
        ),
    ]);
    _smartSelect = state;
    _smartSelectSelections = selections;
    _smartSelectVersion = document.version;
    return true;
  }

  /// The occurrences of the word at the primary selection's start, in
  /// document order (upstream `TextualOccurrences`: case-sensitive whole
  /// words); empty when no word is there.
  List<TextRange> wordHighlights() {
    final selection = value.selection;
    if (_disposed || !selection.isValid) return const [];
    final snapshot = document.snapshot;
    final word = WordOperations.getWordAtPosition(
      DocumentCursorModel(snapshot),
      cursorConfig.wordClassifier,
      snapshot.positionAtOffset(selection.start),
    );
    if (word == null) return const [];
    return [
      for (final match in document.findMatches(
        SearchParams(
          word.word,
          matchCase: true,
          wordSeparators: cursorConfig.wordSeparators,
        ),
        limitResultCount: 1 << 30,
      ))
        TextRange(
          start: snapshot.offsetAtPosition(match.range.getStartPosition()),
          end: snapshot.offsetAtPosition(match.range.getEndPosition()),
        ),
    ];
  }

  /// The word touching [offset] (upstream `getWordAtPosition` with the
  /// editor's word separators), or null.
  String? wordAt(int offset) {
    if (_disposed) return null;
    final snapshot = document.snapshot;
    return WordOperations.getWordAtPosition(
      DocumentCursorModel(snapshot),
      cursorConfig.wordClassifier,
      snapshot.positionAtOffset(offset.clamp(0, snapshot.text.length)),
    )?.word;
  }

  /// Whether the primary selection's start touches a word (upstream
  /// `hasWordHighlights`).
  bool get hasWordHighlights {
    final selection = value.selection;
    if (_disposed || !selection.isValid) return false;
    final snapshot = document.snapshot;
    return WordOperations.getWordAtPosition(
          DocumentCursorModel(snapshot),
          cursorConfig.wordClassifier,
          snapshot.positionAtOffset(selection.start),
        ) !=
        null;
  }

  /// editor.action.wordHighlight.next / prev (upstream
  /// `WordHighlighter.moveNext` / `moveBack`): puts the caret at the start of
  /// the next (previous) occurrence of the word, wrapping around. Returns
  /// that occurrence, or null when there is none.
  TextRange? moveToWordHighlight({required bool next}) {
    final highlights = wordHighlights();
    if (highlights.isEmpty) return null;
    final caret = value.selection.extentOffset;
    final index = highlights.indexWhere(
      (range) => range.start <= caret && caret <= range.end,
    );
    final length = highlights.length;
    final dest =
        highlights[next ? (index + 1) % length : (index - 1 + length) % length];
    _pushCursorUndo();
    _setSelections([TextSelection.collapsed(offset: dest.start)]);
    return dest;
  }

  // ---- undo / clipboard ---------------------------------------------------------

  bool undo() {
    if (!document.undo()) return false;
    _afterHistoryChange();
    return true;
  }

  bool redo() {
    if (!document.redo()) return false;
    _afterHistoryChange();
    return true;
  }

  void _afterHistoryChange() {
    _snippet = null;
    _lastEditVersion = -1;
    _eolCache = null;
    _autoClosed = const [];
    final restored = document.restoredSelections;
    if (restored != null && restored.isNotEmpty) {
      _setSelections(restored, reveal: restored.first.extentOffset);
    } else {
      syncFromDocument();
    }
  }

  /// Refresh after an external edit to the supplied document. Callers of an
  /// injected document must explicitly sync because it has no notifications.
  /// Restores the cursors recorded by the latest undo/redo when it is the
  /// newest change; otherwise clamps the current cursors.
  void syncFromDocument() {
    if (_disposed) return;
    if (super.value.text != document.text) _snippet = null;
    final restored = document.restoredSelections;
    if (restored != null &&
        restored.isNotEmpty &&
        super.value.text != document.text) {
      _lastEditVersion = -1;
      _autoClosed = const [];
      _eolCache = null;
      _setSelections(restored, reveal: restored.first.extentOffset);
      return;
    }
    if (super.value.text != document.text) {
      _autoClosed = const [];
      _eolCache = null;
    }
    _setSelections(selections);
  }

  Future<void> copy() async {
    final text = _copyText();
    if (text == null) return;
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Text for the clipboard (Monaco: an empty selection copies its line).
  String? _copyText() {
    if (_disposed || !value.selection.isValid) return null;
    final snapshot = document.snapshot;
    final eol = _eol(snapshot) ?? '\n';
    final sels = selections;
    final sorted = List.of(sels)..sort((a, b) => a.start.compareTo(b.start));
    final allEmpty = sorted.every((s) => s.isCollapsed);
    if (allEmpty) {
      final lines = <int>{};
      final buffer = StringBuffer();
      for (final s in sorted) {
        final line = snapshot.positionAtOffset(s.extentOffset).lineNumber - 1;
        if (!lines.add(line)) continue;
        buffer
          ..write(
            snapshot.text.substring(
              snapshot.lineStarts[line],
              snapshot.contentEnds[line],
            ),
          )
          ..write(eol);
      }
      final text = buffer.toString();
      _clipboardMetadata = _ClipboardMetadata(text, true, null);
      if (lines.length == 1) {
        onCopy?.call(text, lines.first + 1, lines.first + 1);
      }
      return text;
    }
    final parts = [
      for (final s in sorted)
        if (!s.isCollapsed) snapshot.text.substring(s.start, s.end),
    ];
    final text = parts.join(eol);
    _clipboardMetadata = _ClipboardMetadata(
      text,
      false,
      parts.length > 1 ? parts : null,
    );
    if (parts.length == 1) {
      final selection = sorted.firstWhere((s) => !s.isCollapsed);
      final start = snapshot.positionAtOffset(selection.start);
      final end = snapshot.positionAtOffset(selection.end);
      // A selection to the start of a line ends on the line before.
      final endLine = end.column == 1 && end.lineNumber > start.lineNumber
          ? end.lineNumber - 1
          : end.lineNumber;
      onCopy?.call(text, start.lineNumber, endLine);
    }
    return text;
  }

  /// [canEdit] lets a surface cancel a pending cut after losing editability.
  Future<void> cut({bool Function()? canEdit}) async {
    if (_disposed || canEdit?.call() == false) return;
    final before = value;
    final beforeSelections = selections;
    final text = _copyText();
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    // A clipboard round trip must not delete a selection that has since moved.
    if (_disposed ||
        canEdit?.call() == false ||
        value.text != before.text ||
        !listEquals(selections, beforeSelections)) {
      return;
    }
    final snapshot = document.snapshot;
    final sels = _cursorSelections(snapshot);
    final ranges = DeleteOperations.cut(
      cursorConfig,
      DocumentCursorModel(snapshot),
      sels,
    );
    _executeCommands(
      [
        for (var i = 0; i < sels.length; i++)
          ranges[i] == null
              ? NoopCursorCommand(sels[i])
              : ReplaceCommand(ranges[i]!, ''),
      ],
      type: EditOperationType.other,
      pushBefore: true,
      pushAfter: true,
    );
  }

  /// A clipboard round trip must not insert into a different editing state.
  /// [canEdit] is checked before and after the request (e.g. for focus/read-only).
  Future<void> paste({bool Function()? canEdit}) async {
    if (_disposed || canEdit?.call() == false) return;
    if (onPaste case final hook?) {
      if (await hook()) return;
      if (_disposed || canEdit?.call() == false) return;
    }
    final before = value;
    final beforeSelections = selections;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (_disposed ||
        canEdit?.call() == false ||
        value.text != before.text ||
        !listEquals(selections, beforeSelections)) {
      return;
    }
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    pasteText(text);
  }

  /// Pastes [text] at every cursor like Monaco: one line per cursor when the
  /// line count matches, whole-line clipboard text above the cursor line.
  void pasteText(String text) {
    if (_disposed || !value.selection.isValid) return;
    final metadata = _clipboardMetadata;
    final fromUs = metadata != null && metadata.text == text;
    final snapshot = document.snapshot;
    final result = TypeOperations.paste(
      cursorConfig,
      DocumentCursorModel(snapshot),
      _cursorSelections(snapshot),
      text,
      fromUs && metadata.isFromEmptySelections,
      fromUs ? metadata.multicursorText : null,
    );
    _runResult(result);
  }

  // ---- command execution ----------------------------------------------------------

  void _runResult(EditOperationResult result) {
    final snapshot = document.snapshot;
    final sels = _cursorSelections(snapshot);
    final commands = [
      for (var i = 0; i < sels.length; i++)
        (i < result.commands.length ? result.commands[i] : null) ??
            NoopCursorCommand(sels[i]),
    ];
    _executeCommands(
      commands,
      type: result.type,
      pushBefore: result.shouldPushStackElementBefore,
      pushAfter: result.shouldPushStackElementAfter,
    );
  }

  /// Applies explicit edits and sets explicit post-edit selections (Monaco
  /// `executeEdits(edits, cursorState)`), as one undo step.
  void _executeEdits(List<CursorCommandEdit> edits, List<Selection> after) {
    final snapshot = document.snapshot;
    final eol = _eol(snapshot);
    final offsetEdits = [
      for (final edit in edits)
        EditorOffsetEdit(
          snapshot.offsetAtPosition(edit.range.getStartPosition()),
          snapshot.offsetAtPosition(edit.range.getEndPosition()),
          _withEol(edit.text, eol),
        ),
    ];
    final beforeSelections = selections;
    document.closeUndoGroup();
    final changed = document.applyOffsetEdits(
      offsetEdits,
      selectionsBefore: beforeSelections,
    );
    final post = document.snapshot;
    final next = [for (final s in after) _toTextSelection(post, s)];
    if (changed) {
      final sorted = [
        for (final e in offsetEdits) (e.start, e.end, e.text.length),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      _mapAutoClosed(sorted);
      _snippet?.acceptEdits(sorted);
      document.setUndoSelectionsAfter(_normalizedList(next, post.text.length));
      document.closeUndoGroup();
      _lastEditVersion = document.version;
    }
    _prevEditType = EditOperationType.other;
    _setSelections(next, fromEdit: true, reveal: next.first.extentOffset);
  }

  /// Runs one command per cursor (same order as [selections]) as a single
  /// document edit, then sets the cursors the commands compute. Commands
  /// whose edits overlap an earlier cursor's edits are dropped (their cursor
  /// is kept, tracked through the edit), like upstream's loser cursors.
  void _executeCommands(
    List<CursorCommand?> commands, {
    required EditOperationType type,
    required bool pushBefore,
    required bool pushAfter,
  }) {
    if (_disposed) return;
    final pre = document.snapshot;
    final model = DocumentCursorModel(pre);
    final eol = _eol(pre);
    final sels = _cursorSelections(pre);
    final raw = selections;
    final perCommand = <List<_PlannedEdit>>[];
    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      final planned = <_PlannedEdit>[];
      if (command is _OffsetReplaceCommand) {
        planned.add(
          _PlannedEdit(i, 0, command.start, command.end, command.text),
        );
      } else if (command != null) {
        final edits = command.getEditOperations(model);
        for (var j = 0; j < edits.length; j++) {
          final range = edits[j].range;
          planned.add(
            _PlannedEdit(
              i,
              j,
              pre.offsetAtPosition(range.getStartPosition()),
              pre.offsetAtPosition(range.getEndPosition()),
              _withEol(edits[j].text, eol),
            ),
          );
        }
      }
      perCommand.add(planned);
    }
    // Drop commands whose edits overlap an earlier command's edits.
    final losers = <int>{};
    while (true) {
      final all = [
        for (var i = 0; i < perCommand.length; i++)
          if (!losers.contains(i)) ...perCommand[i],
      ]..sort(_PlannedEdit.compare);
      int? loser;
      for (var k = 1; k < all.length; k++) {
        if (all[k].start < all[k - 1].end) {
          final a = all[k - 1].command;
          final b = all[k].command;
          loser = a > b ? a : b;
          break;
        }
      }
      if (loser == null) break;
      losers.add(loser);
    }
    final applied = [
      for (var i = 0; i < perCommand.length; i++)
        if (!losers.contains(i))
          for (final edit in perCommand[i])
            if (edit.start != edit.end || edit.text.isNotEmpty) edit,
    ]..sort(_PlannedEdit.compare);
    final coalesce =
        !pushBefore &&
        document.version == _lastEditVersion &&
        applied.isNotEmpty;
    if (!coalesce) document.closeUndoGroup();
    final changed = document.applyOffsetEdits(
      [for (final e in applied) EditorOffsetEdit(e.start, e.end, e.text)],
      selectionsBefore: raw,
      coalesce: coalesce,
    );
    final post = document.snapshot;
    final postModel = DocumentCursorModel(post);
    // Post-edit start of every applied edit, and deltas before each edit.
    final deltaBefore = List<int>.filled(applied.length + 1, 0);
    for (var k = 0; k < applied.length; k++) {
      final edit = applied[k];
      edit.newStart = edit.start + deltaBefore[k];
      deltaBefore[k + 1] =
          deltaBefore[k] + edit.text.length - (edit.end - edit.start);
    }
    // Upstream decoration tracking (intervalTree nodeAcceptEdit): edits are
    // applied last to first; only edits touching the offset need handling.
    int mapOffset(int offset, {required bool stickToPrevious}) {
      var lo = 0, hi = applied.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (applied[mid].end < offset) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      var touching = lo;
      while (touching < applied.length && applied[touching].start <= offset) {
        touching++;
      }
      var mapped = offset;
      for (var k = touching - 1; k >= lo; k--) {
        final e = applied[k];
        mapped = _acceptEdit(
          mapped,
          stickToPrevious,
          e.start,
          e.end,
          e.text.length,
        );
      }
      return mapped + deltaBefore[lo];
    }

    Position mapPosition(Position position, {required bool stickToPrevious}) =>
        post.positionAtOffset(
          mapOffset(
            pre.offsetAtPosition(position),
            stickToPrevious: stickToPrevious,
          ),
        );

    Selection track(Selection s, bool? trackPreviousOnEmpty) {
      if (s.isEmpty()) {
        final stickToPrevious =
            trackPreviousOnEmpty ??
            s.startColumn == model.getLineMaxColumn(s.startLineNumber);
        final p = mapPosition(
          s.getStartPosition(),
          stickToPrevious: stickToPrevious,
        );
        return Selection(p.lineNumber, p.column, p.lineNumber, p.column);
      }
      // NeverGrowsWhenTypingAtEdges.
      final start = mapPosition(s.getStartPosition(), stickToPrevious: false);
      var end = mapPosition(s.getEndPosition(), stickToPrevious: true);
      if (Position.isBeforePositions(end, start)) end = start;
      return s.getDirection() == SelectionDirection.ltr
          ? Selection(
              start.lineNumber,
              start.column,
              end.lineNumber,
              end.column,
            )
          : Selection(
              end.lineNumber,
              end.column,
              start.lineNumber,
              start.column,
            );
    }

    final result = <TextSelection>[];
    final newAutoClosed = <_AutoClosed>[];
    for (var i = 0; i < commands.length; i++) {
      final command = commands[i];
      final original = i < sels.length ? sels[i] : null;
      if (command == null || losers.contains(i)) {
        if (original != null) {
          result.add(_toTextSelection(post, track(original, null)));
        }
        continue;
      }
      if (command is _OffsetReplaceCommand) {
        final e = perCommand[i].first;
        result.add(TextSelection.collapsed(offset: e.newStart + e.text.length));
        continue;
      }
      final own = perCommand[i];
      final helper = _StateComputerData(
        [
          for (final e in own)
            Range.fromPositions(
              post.positionAtOffset(e.newStart),
              post.positionAtOffset(e.newStart + e.text.length),
            ),
        ],
        () {
          final tracked = command.selectionToTrack;
          if (tracked == null) {
            throw StateError('Command did not track a selection');
          }
          return track(tracked, command.trackPreviousOnEmpty);
        },
      );
      // Edits that were no-ops were not applied; they still report a range.
      for (final e in own) {
        if (e.start == e.end && e.text.isEmpty) {
          e.newStart = mapOffset(e.start, stickToPrevious: true);
        }
      }
      final selection = clampSelection(
        postModel,
        command.computeCursorState(postModel, helper),
      );
      result.add(_toTextSelection(post, selection));
      if (command is TypeWithAutoClosingCommand) {
        final close = command.closeCharacterRange;
        final enclosing = command.enclosingRange;
        if (close != null && enclosing != null) {
          newAutoClosed.add(
            _AutoClosed(
              post.offsetAtPosition(close.getStartPosition()),
              post.offsetAtPosition(close.getEndPosition()),
              post.offsetAtPosition(enclosing.getStartPosition()),
              post.offsetAtPosition(enclosing.getEndPosition()),
            ),
          );
        }
      }
    }
    if (changed) {
      final mapped = [for (final e in applied) (e.start, e.end, e.text.length)];
      _mapAutoClosed(mapped);
      _snippet?.acceptEdits(mapped);
      document.setUndoSelectionsAfter(
        _normalizedList(result, post.text.length),
      );
      if (pushAfter) document.closeUndoGroup();
      _lastEditVersion = document.version;
    }
    if (newAutoClosed.isNotEmpty) {
      _autoClosed = [..._autoClosed, ...newAutoClosed];
    }
    _prevEditType = type;
    _setSelections(
      result,
      fromEdit: true,
      reveal: result.isEmpty ? null : result.first.extentOffset,
    );
  }

  static List<TextSelection> _normalizedList(
    List<TextSelection> selections,
    int length,
  ) => [for (final entry in _normalize(selections, length, null)) entry.$1];

  /// Upstream `nodeAcceptEdit` for one marker (forceMoveMarkers false):
  /// markers before the edit or inside the part of a replacement that is
  /// covered by the new text stay; others move to its end.
  static int _acceptEdit(
    int marker,
    bool stickToPrevious,
    int start,
    int end,
    int length,
  ) {
    final deleting = end - start;
    final common = deleting < length ? deleting : length;
    bool before(int check, {required bool forceStay}) {
      if (marker != check) return marker < check;
      return forceStay || stickToPrevious;
    }

    if (before(start, forceStay: deleting > 0)) return marker;
    if (common > 0 && before(start + common, forceStay: deleting > length)) {
      return marker;
    }
    if (before(end, forceStay: false)) return start + length;
    return marker + length - deleting;
  }

  static Selection clampSelection(ICursorSimpleModel model, Selection s) {
    final start = clampPosition(
      model,
      Position(s.selectionStartLineNumber, s.selectionStartColumn),
    );
    final end = clampPosition(
      model,
      Position(s.positionLineNumber, s.positionColumn),
    );
    return Selection(
      start.lineNumber,
      start.column,
      end.lineNumber,
      end.column,
    );
  }

  // ---- language features ---------------------------------------------------------

  /// The text the latest keyboard typing inserted (see [type]), while no
  /// other mutation happened since; null otherwise. Completion and signature
  /// help triggers read it after each text change.
  String? get lastTypedText =>
      _typing ?? (_typedVersion == document.version ? _typedText : null);

  /// Applies disjoint [edits] (pre-edit offsets) as one undo step and maps
  /// every cursor through them, like Monaco's `executeEdits` for formatting
  /// and rename. Returns whether the text changed.
  bool applyEdits(List<EditorOffsetEdit> edits) {
    if (_disposed || edits.isEmpty) return false;
    final sorted = List.of(edits)
      ..sort((a, b) {
        final start = a.start.compareTo(b.start);
        return start != 0 ? start : a.end.compareTo(b.end);
      });
    final before = selections;
    document.closeUndoGroup();
    final changed = document.applyOffsetEdits(sorted, selectionsBefore: before);
    if (!changed) return false;
    final mapped = [for (final e in sorted) (e.start, e.end, e.text.length)];
    _eolCache = null;
    _mapAutoClosed(mapped);
    _snippet?.acceptEdits(mapped);
    final after = [
      for (final s in before)
        s.isCollapsed
            ? TextSelection.collapsed(
                offset: _mapThrough(mapped, s.extentOffset, true),
              )
            : TextSelection(
                baseOffset: _mapThrough(
                  mapped,
                  s.baseOffset,
                  s.baseOffset > s.extentOffset,
                ),
                extentOffset: _mapThrough(
                  mapped,
                  s.extentOffset,
                  s.extentOffset > s.baseOffset,
                ),
              ),
    ];
    final length = document.text.length;
    document.setUndoSelectionsAfter(_normalizedList(after, length));
    document.closeUndoGroup();
    _lastEditVersion = document.version;
    _prevEditType = EditOperationType.other;
    _setSelections(after, fromEdit: true);
    return true;
  }

  /// Maps [offset] through sorted pre-edit `(start, end, insertedLength)`
  /// edits (upstream `nodeAcceptEdit`, applied last to first).
  static int _mapThrough(
    List<(int, int, int)> edits,
    int offset,
    bool stickToPrevious,
  ) {
    var mapped = offset;
    for (final (start, end, length) in edits.reversed) {
      mapped = _acceptEdit(mapped, stickToPrevious, start, end, length);
    }
    return mapped;
  }

  /// Whether a snippet session is active (Monaco `inSnippetMode`).
  bool get inSnippetMode => _snippet != null;

  /// Every placeholder range of the active snippet, for painting:
  /// `(start, end, active, isFinalTabstop)`.
  List<(int, int, bool, bool)> get snippetPlaceholders =>
      _snippet?.placeholderRanges ?? const [];

  /// The active placeholder's choices, if it has any.
  SnippetActiveChoice? get snippetChoice => _snippet?.activeChoice;

  /// Inserts [template] (TextMate snippet syntax) at every cursor, replacing
  /// [overwriteBefore]/[overwriteAfter] UTF-16 units around each caret, plus
  /// [additionalEdits] (pre-edit offsets, e.g. a completion's imports) in the
  /// same undo step. Starts a snippet session when the template has
  /// placeholders (upstream SnippetController2.insert). Additional edits that
  /// overlap an insertion are dropped. With [undoStopBefore] false the edit
  /// joins the previous undo step when that is still open.
  void insertSnippet(
    String template, {
    int overwriteBefore = 0,
    int overwriteAfter = 0,
    List<EditorOffsetEdit> additionalEdits = const [],
    bool adjustWhitespace = true,
    bool undoStopBefore = true,
    SnippetVariableValues? variables,
  }) {
    if (_disposed || !value.selection.isValid) return;
    final snapshot = document.snapshot;
    final text = snapshot.text;
    final current = selections;
    final primary = current.first;
    int lineStartOf(int offset) =>
        snapshot.lineStarts[snapshot.positionAtOffset(offset).lineNumber - 1];
    int lineEndOf(int offset) =>
        snapshot.contentEnds[snapshot.positionAtOffset(offset).lineNumber - 1];
    String before(TextSelection s) => text.substring(
      (s.extentOffset - overwriteBefore).clamp(
        lineStartOf(s.extentOffset),
        s.extentOffset,
      ),
      s.extentOffset,
    );
    String after(TextSelection s) => text.substring(
      s.extentOffset,
      (s.extentOffset + overwriteAfter).clamp(
        s.extentOffset,
        lineEndOf(s.extentOffset),
      ),
    );
    // Secondary cursors only extend over the same text as the primary.
    final firstBefore = before(primary);
    final firstAfter = after(primary);
    final targets = <SnippetTarget>[];
    for (final (index, s) in current.indexed) {
      var start = s.start;
      var end = s.end;
      final b = before(s);
      final a = after(s);
      if (b == firstBefore) start = s.extentOffset - b.length;
      if (a == firstAfter) end = s.extentOffset + a.length;
      if (start > s.start) start = s.start;
      if (end < s.end) end = s.end;
      final line = snapshot.positionAtOffset(start).lineNumber - 1;
      final lineStart = snapshot.lineStarts[line];
      targets.add((
        start: start,
        end: end,
        lineText: text.substring(lineStart, snapshot.contentEnds[line]),
        column: start - lineStart,
        cursorIndex: index,
      ));
    }
    final eol = this.eol;
    final insertion = SnippetSession.create(
      template,
      targets,
      normalizeIndentation: (s) =>
          normalizeIndentation(s, tabSize, insertSpaces),
      eol: eol,
      variables: variables,
      adjustWhitespace: adjustWhitespace,
    );
    final main = [
      for (final e in insertion.edits) EditorOffsetEdit(e.start, e.end, e.text),
    ];
    final extra = <EditorOffsetEdit>[];
    for (final e in List.of(
      additionalEdits,
    )..sort((a, b) => a.start.compareTo(b.start))) {
      final overlaps =
          main.any((m) => e.start < m.end && m.start < e.end) ||
          extra.any((x) => e.start < x.end && x.start < e.end);
      if (!overlaps) {
        extra.add(EditorOffsetEdit(e.start, e.end, _withEol(e.text, eol)));
      }
    }
    final all = [...main, ...extra]
      ..sort((a, b) {
        final start = a.start.compareTo(b.start);
        return start != 0 ? start : a.end.compareTo(b.end);
      });
    // Where each snippet starts once the additional edits are applied too.
    final extraBefore = [
      for (final m in main)
        extra
            .where((e) => e.end <= m.start)
            .fold<int>(0, (sum, e) => sum + e.text.length - (e.end - e.start)),
    ];
    final coalesce = !undoStopBefore && document.version == _lastEditVersion;
    if (!coalesce) document.closeUndoGroup();
    _snippetBusy = true;
    try {
      _snippet = null;
      final changed = document.applyOffsetEdits(
        all,
        selectionsBefore: current,
        coalesce: coalesce,
      );
      final mapped = [for (final e in all) (e.start, e.end, e.text.length)];
      if (changed) {
        _eolCache = null;
        _mapAutoClosed(mapped);
      }
      final session = insertion.session;
      if (extraBefore.any((shift) => shift != 0)) {
        session.shiftStarts(extraBefore);
      }
      final post = document.snapshot;
      List<TextSelection> next;
      var delta = 0;
      final ends = <TextSelection>[];
      for (final e in all) {
        final newEnd = e.start + delta + e.text.length;
        delta += e.text.length - (e.end - e.start);
        if (main.contains(e)) ends.add(TextSelection.collapsed(offset: newEnd));
      }
      // Keep the primary cursor's snippet first.
      final order = [
        for (final t in targets) main.indexWhere((m) => m.start == t.start),
      ];
      next = [for (final i in order) ends[i]];
      if (session.hasPlaceholder) {
        _snippet = session;
        final moved = session.move(
          true,
          textIn: (start, end) => post.text.substring(start, end),
          transform: _applySnippetTransform,
          normalizeIndentation: (s) =>
              normalizeIndentation(s, tabSize, insertSpaces),
          eol: eol,
        );
        if (moved.isNotEmpty) {
          next = [
            for (final m in moved)
              TextSelection(baseOffset: m.base, extentOffset: m.extent),
          ];
        }
      }
      if (changed) {
        document.setUndoSelectionsAfter(
          _normalizedList(next, post.text.length),
        );
        document.closeUndoGroup();
        _lastEditVersion = document.version;
      }
      _prevEditType = EditOperationType.other;
      _setSelections(next, fromEdit: true, reveal: next.first.extentOffset);
    } finally {
      _snippetBusy = false;
    }
    _updateSnippetState(selections);
    notifyListeners();
  }

  void _applySnippetTransform(List<SnippetEdit> edits) {
    final offsetEdits = [
      for (final e in edits) EditorOffsetEdit(e.start, e.end, e.text),
    ];
    final changed = document.applyOffsetEdits(
      offsetEdits,
      coalesce: document.version == _lastEditVersion,
    );
    if (!changed) return;
    final mapped = [for (final e in edits) (e.start, e.end, e.text.length)];
    _mapAutoClosed(mapped);
    _snippet?.acceptEdits(mapped);
    _lastEditVersion = document.version;
    // The caller sets selections from the session afterwards.
    super.value = super.value.copyWith(
      text: document.text,
      selection: TextSelection.collapsed(
        offset: value.selection.extentOffset.clamp(0, document.text.length),
      ),
      composing: TextRange.empty,
    );
  }

  /// Tab in snippet mode: selects the next placeholder (upstream
  /// `jumpToNextSnippetPlaceholder`). Returns false outside snippet mode.
  bool nextSnippetPlaceholder() => _moveSnippet(true);

  /// Shift+Tab in snippet mode (`jumpToPrevSnippetPlaceholder`); false when
  /// already at the first placeholder or outside snippet mode.
  bool prevSnippetPlaceholder() {
    final session = _snippet;
    if (session == null || session.isAtFirstPlaceholder) return false;
    return _moveSnippet(false);
  }

  bool _moveSnippet(bool fwd) {
    final session = _snippet;
    if (_disposed || session == null) return false;
    _snippetBusy = true;
    List<SnippetSelection> moved;
    try {
      moved = session.move(
        fwd,
        textIn: (start, end) => document.text.substring(start, end),
        transform: _applySnippetTransform,
        normalizeIndentation: (s) =>
            normalizeIndentation(s, tabSize, insertSpaces),
        eol: eol,
      );
      if (moved.isNotEmpty) {
        _setSelections([
          for (final m in moved)
            TextSelection(baseOffset: m.base, extentOffset: m.extent),
        ], reveal: moved.first.extent);
      }
    } finally {
      _snippetBusy = false;
    }
    if (_updateSnippetState(selections)) notifyListeners();
    return true;
  }

  /// Whether Tab moves to another placeholder (upstream `hasNextTabstop`).
  bool get snippetHasNextTabstop =>
      _snippet != null && !_snippet!.isAtLastPlaceholder;

  /// Whether Shift+Tab moves to another placeholder (`hasPrevTabstop`).
  bool get snippetHasPrevTabstop =>
      _snippet != null && !_snippet!.isAtFirstPlaceholder;

  /// Escape in snippet mode (`leaveSnippet`). With [resetSelection] the
  /// cursors collapse to the primary's extent.
  bool cancelSnippet({bool resetSelection = false}) {
    if (_snippet == null) return false;
    _snippet = null;
    document.closeUndoGroup();
    if (resetSelection) {
      final s = value.selection;
      _setSelections([TextSelection.collapsed(offset: s.extentOffset)]);
    }
    notifyListeners();
    return true;
  }

  /// Upstream SnippetController2._updateState: leaves snippet mode at the
  /// final tabstop or when a cursor leaves the placeholders. Returns
  /// whether it did.
  bool _updateSnippetState(List<TextSelection> current) {
    final session = _snippet;
    if (session == null || _snippetBusy) return false;
    if (!session.hasPlaceholder ||
        session.isAtLastPlaceholder ||
        !session.isSelectionWithinPlaceholders([
          for (final s in current) (s.start, s.end),
        ])) {
      _snippet = null;
      document.closeUndoGroup();
      return true;
    }
    return false;
  }

  // ---- helpers ---------------------------------------------------------------------

  /// Every cursor as a line/column selection (same order as [selections]).
  List<Selection> _cursorSelections(DocumentSnapshot snapshot) => [
    for (final s in selections) _toSelection(snapshot, s),
  ];

  static Selection _toSelection(DocumentSnapshot snapshot, TextSelection s) {
    final base = snapshot.positionAtOffset(s.isValid ? s.baseOffset : 0);
    final extent = snapshot.positionAtOffset(s.isValid ? s.extentOffset : 0);
    return Selection.fromPositions(base, extent);
  }

  static TextSelection _toTextSelection(
    DocumentSnapshot snapshot,
    Selection s,
  ) => TextSelection(
    baseOffset: snapshot.offsetAtPosition(
      Position(s.selectionStartLineNumber, s.selectionStartColumn),
    ),
    extentOffset: snapshot.offsetAtPosition(
      Position(s.positionLineNumber, s.positionColumn),
    ),
  );

  static String _valueInRange(DocumentSnapshot snapshot, Range range) =>
      snapshot.text
          .substring(
            snapshot.offsetAtPosition(range.getStartPosition()),
            snapshot.offsetAtPosition(range.getEndPosition()),
          )
          .replaceAll('\r\n', '\n');

  /// The document's dominant line break (LF when it has none).
  String get eol => _eol(document.snapshot) ?? '\n';

  /// The dominant line break, or null when the document has none (inserted
  /// text is then kept as is). Edits made here insert the dominant break, so
  /// it is computed once and only reset by raw input, history and external
  /// syncs; a document without breaks is rechecked when its line count grows.
  String? _eol(DocumentSnapshot snapshot) {
    final cached = _eolCache;
    if (cached != null &&
        (cached.$2 != null || cached.$1 == snapshot.lineCount)) {
      return cached.$2;
    }
    var lf = 0, crlf = 0, cr = 0;
    final text = snapshot.text;
    for (var i = 0; i < snapshot.lineCount - 1; i++) {
      if (snapshot.newlineLengths[i] == 2) {
        crlf++;
      } else if (text.codeUnitAt(snapshot.contentEnds[i]) == 0x0D) {
        cr++;
      } else {
        lf++;
      }
    }
    final String? eol;
    if (lf + crlf + cr == 0) {
      eol = null;
    } else if (crlf > lf && crlf >= cr) {
      eol = '\r\n';
    } else if (cr > lf && cr > crlf) {
      eol = '\r';
    } else {
      eol = '\n';
    }
    _eolCache = (snapshot.lineCount, eol);
    return eol;
  }

  static final RegExp _lineBreak = RegExp(r'\r\n|\r|\n');

  static String _withEol(String text, String? eol) {
    if (eol == null || (!text.contains('\n') && !text.contains('\r'))) {
      return text;
    }
    return text.replaceAll(_lineBreak, eol);
  }

  List<Range> _autoClosedRanges(DocumentSnapshot snapshot) => [
    for (final a in _autoClosed)
      if (a.closeEnd <= snapshot.text.length)
        Range.fromPositions(
          snapshot.positionAtOffset(a.closeStart),
          snapshot.positionAtOffset(a.closeEnd),
        ),
  ];

  /// Shifts auto-closed records through sorted (start, end, insertedLength)
  /// edits, dropping records an edit touched.
  void _mapAutoClosed(List<(int, int, int)> edits) {
    if (_autoClosed.isEmpty) return;
    int? map(int offset) {
      var shift = 0;
      for (final (start, end, length) in edits) {
        if (offset < start) break;
        if (offset > end) {
          shift += length - (end - start);
          continue;
        }
        if (start == end && offset == start) return offset + shift + length;
        return null;
      }
      return offset + shift;
    }

    _autoClosed = [
      for (final a in _autoClosed)
        if ((
              map(a.closeStart),
              map(a.closeEnd),
              map(a.enclosingStart),
              map(a.enclosingEnd),
            )
            case (final cs?, final ce?, final es?, final ee?))
          if (ce - cs == a.closeEnd - a.closeStart) _AutoClosed(cs, ce, es, ee),
    ];
  }

  /// Upstream AutoClosedAction.isValid: forget records once no cursor is
  /// inside their enclosing range.
  void _pruneAutoClosed(List<TextSelection> cursors) {
    if (_autoClosed.isEmpty) return;
    _autoClosed = [
      for (final a in _autoClosed)
        if (cursors.any(
          (s) => s.start >= a.enclosingStart + 1 && s.end <= a.enclosingEnd,
        ))
          a,
    ];
  }

  /// Heuristic standard token type before one-based [column]: inside a
  /// quoted string or after the line comment token on the same line.
  int? _tokenTypeAt(ICursorSimpleModel model, int lineNumber, int column) {
    final line = model.getLineContent(lineNumber);
    final lineComment = _resolvedLanguage?.comments?.lineCommentToken;
    final end = column - 1 < line.length ? column - 1 : line.length;
    int? quote;
    for (var i = 0; i < end; i++) {
      final c = line.codeUnitAt(i);
      if (quote != null) {
        if (c == 0x5C) {
          i++;
        } else if (c == quote) {
          quote = null;
        }
        continue;
      }
      if (c == 0x22 || c == 0x27 || c == 0x60) {
        quote = c;
      } else if (lineComment != null &&
          lineComment.isNotEmpty &&
          line.startsWith(lineComment, i)) {
        return StandardTokenType.comment;
      }
    }
    return quote != null ? StandardTokenType.string : StandardTokenType.other;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_ownsDocument) document.dispose();
    super.dispose();
  }
}

class _AutoClosed {
  const _AutoClosed(
    this.closeStart,
    this.closeEnd,
    this.enclosingStart,
    this.enclosingEnd,
  );

  final int closeStart;
  final int closeEnd;
  final int enclosingStart;
  final int enclosingEnd;
}

class _ClipboardMetadata {
  const _ClipboardMetadata(
    this.text,
    this.isFromEmptySelections,
    this.multicursorText,
  );

  final String text;
  final bool isFromEmptySelections;
  final List<String>? multicursorText;
}

class _PlannedEdit {
  _PlannedEdit(this.command, this.index, this.start, this.end, this.text);

  final int command;
  final int index;
  final int start;
  final int end;
  final String text;
  int newStart = 0;

  static int compare(_PlannedEdit a, _PlannedEdit b) {
    final start = a.start.compareTo(b.start);
    if (start != 0) return start;
    final end = a.end.compareTo(b.end);
    if (end != 0) return end;
    final command = a.command.compareTo(b.command);
    return command != 0 ? command : a.index.compareTo(b.index);
  }
}

class _StateComputerData implements CursorStateComputerData {
  _StateComputerData(this._inverse, this._tracked);

  final List<Range> _inverse;
  final Selection Function() _tracked;

  @override
  List<Range> getInverseEditOperations() => _inverse;

  @override
  Selection getTrackedSelection() => _tracked();
}

/// A raw UTF-16 replacement for carets that line/column positions cannot
/// express (inside a surrogate pair, grapheme cluster, or CRLF).
class _OffsetReplaceCommand extends CursorCommand {
  _OffsetReplaceCommand(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) =>
      const [];

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) => throw UnsupportedError('Executed by offsets');
}
