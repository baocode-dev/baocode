import 'dart:async';

import 'package:flutter/services.dart' show TextSelection;

import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
import '../vs/editor/common/cursor/cursor_common.dart';
import '../vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer.dart';
import '../vs/editor/common/model/piece_tree_text_buffer/piece_tree_text_buffer_builder.dart';
import '../vs/editor/common/model/search/piece_tree_search.dart';
import 'document_snapshot.dart';

/// A range replacement in one document state, using one-based UTF-16 columns.
class EditorDocumentEdit {
  const EditorDocumentEdit(this.range, this.text);

  final Range range;
  final String text;
}

/// A replacement of the UTF-16 range [start, end) in one document state.
/// Offsets address raw text, so they can split a CRLF or a surrogate pair.
class EditorOffsetEdit {
  const EditorOffsetEdit(this.start, this.end, this.text)
    : assert(start <= end);

  final int start;
  final int end;
  final String text;

  @override
  String toString() => 'EditorOffsetEdit($start, $end, ${text.length})';
}

/// One replacement in a text change, as the Language Server Protocol's
/// `TextDocumentContentChangeEvent` has it: [text] replaces the range from
/// ([startLine], [startCharacter]) to ([endLine], [endCharacter]) of the
/// document as the event's previous changes left it.
///
/// Lines are zero-based and broken at CRLF, lone CR and lone LF (as in
/// [DocumentSnapshot]); characters count UTF-16 code units. A range never
/// ends between the CR and LF of a pair: such an edit is widened over the
/// pair (and [text] gains the CR or LF it keeps).
class EditorContentChange {
  const EditorContentChange({
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
    required this.rangeOffset,
    required this.rangeLength,
    required this.text,
  });

  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;

  /// UTF-16 offset and length of the replaced range.
  final int rangeOffset;
  final int rangeLength;
  final String text;

  @override
  String toString() =>
      'EditorContentChange($startLine:$startCharacter-$endLine:$endCharacter, '
      '${text.length})';
}

/// A mutation of an [EditorDocumentModel]: applying [changes] in order to
/// the previous text gives [text], the text at [version].
class EditorContentChangeEvent {
  const EditorContentChangeEvent(this.version, this.changes, this.text);

  final int version;
  final List<EditorContentChange> changes;
  final String text;
}

class _OffsetEdit {
  const _OffsetEdit(this.start, this.end, this.text);

  final int start;
  final int end;
  final String text;
}

/// One undo step. [groups] are applied in order; each group is a list of
/// sequential inverse edits (see [EditorDocumentModel._applyBatch]).
class _HistoryEntry {
  _HistoryEntry(this.groups, this.selectionsBefore, this.selectionsAfter);

  final List<List<_OffsetEdit>> groups;
  List<TextSelection>? selectionsBefore;
  List<TextSelection>? selectionsAfter;
}

/// Flutter-facing, in-memory document state. File loading/saving and painting
/// remain the responsibility of the IDE workspace and editor respectively.
///
/// Unlike a Monaco TextModel, this bridge preserves the decoded file's exact
/// text, including mixed line endings and a leading U+FEFF if present. Its
/// positions and offsets include that U+FEFF, just like [DocumentSnapshot].
class EditorDocumentModel {
  EditorDocumentModel(String text)
    : _buffer = _createBuffer(text),
      _snapshot = DocumentSnapshot(text),
      _savedText = text;

  static PieceTreeTextBuffer _createBuffer(String text) {
    // The upstream builder extracts a leading BOM into metadata, and
    // getValue() omits it. IdeFileService's decoded text does NOT omit it.
    // Keep it as an editable code unit so offsets and workspace baselines
    // continue to refer to the same exact string.
    final hasBom = text.startsWith('﻿');
    final builder = PieceTreeTextBufferBuilder()
      ..acceptChunk(hasBom ? text.substring(1) : text);
    final buffer = builder.finish(false).create(DefaultEndOfLine.lf);
    if (hasBom) {
      buffer.getPieceTree().insert(0, '﻿');
      buffer.refreshContentFlags();
    }
    return buffer;
  }

  final PieceTreeTextBuffer _buffer;
  DocumentSnapshot _snapshot;
  String _savedText;
  final List<_HistoryEntry> _undo = [];
  final List<_HistoryEntry> _redo = [];
  bool _contentFlagsStale = false;
  int _version = 0;

  /// Whether the next coalescing edit may join the newest undo entry.
  bool _undoOpen = false;
  List<TextSelection>? _restoredSelections;
  int _restoredVersion = -1;
  final _changes = StreamController<EditorContentChangeEvent>.broadcast(
    sync: true,
  );

  /// Changes being gathered for [_changes] during a mutation; null when no
  /// one listens.
  List<EditorContentChange>? _pendingChanges;

  /// Every text mutation (edits, undo, redo, [replaceText]), delivered
  /// synchronously once the model holds the new text.
  Stream<EditorContentChangeEvent> get changes => _changes.stream;

  String get text => _snapshot.text;
  DocumentSnapshot get snapshot => _snapshot;
  String get savedText => _savedText;
  bool get isDirty => text != _savedText;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Increments on every text mutation (edit, undo, redo, [replaceText]).
  int get version => _version;

  /// Cursor state recorded with the undo entry that the latest [undo]/[redo]
  /// applied (before-edit selections for undo, after-edit ones for redo).
  /// Null once any later mutation happened or when none was recorded.
  List<TextSelection>? get restoredSelections =>
      _restoredVersion == _version ? _restoredSelections : null;

  bool get mightContainRTL {
    _refreshContentFlags();
    return _buffer.mightContainRTL();
  }

  bool get mightContainNonBasicASCII {
    _refreshContentFlags();
    return _buffer.mightContainNonBasicASCII();
  }

  bool get mightContainUnusualLineTerminators {
    _refreshContentFlags();
    return _buffer.mightContainUnusualLineTerminators();
  }

  void _refreshContentFlags() {
    if (!_contentFlagsStale) return;
    _contentFlagsStale = false;
    _buffer.refreshContentFlags();
  }

  Position positionAtOffset(int offset) => _snapshot.positionAtOffset(offset);
  int offsetAtPosition(IPosition position) =>
      _snapshot.offsetAtPosition(position);

  List<FindMatch> findMatches(
    SearchParams params, {
    Range? searchRange,
    bool captureMatches = false,
    int limitResultCount = 999,
  }) {
    final lastLine = _snapshot.lineCount;
    final fullRange = Range(
      1,
      1,
      lastLine,
      _snapshot.contentEnds.last - _snapshot.lineStarts.last + 1,
    );
    return PieceTreeSearch.findMatches(
      _buffer.getPieceTree(),
      params,
      searchRange ?? fullRange,
      captureMatches: captureMatches,
      limitResultCount: limitResultCount,
    );
  }

  FindMatch? findNextMatch(
    SearchParams params,
    Position start, {
    bool captureMatches = false,
  }) => PieceTreeSearch.findNextMatch(
    _buffer.getPieceTree(),
    params,
    start,
    captureMatches,
  );

  FindMatch? findPreviousMatch(
    SearchParams params,
    Position start, {
    bool captureMatches = false,
  }) => PieceTreeSearch.findPreviousMatch(
    _buffer.getPieceTree(),
    params,
    start,
    captureMatches,
  );

  /// Set the baseline after a successful save. Pass the text captured at the
  /// start of an asynchronous save if the document changed while it was saved.
  void markSaved([String? savedText]) => _savedText = savedText ?? text;

  void applyEdit(Range range, String text) =>
      applyEdits([EditorDocumentEdit(range, text)]);

  /// Synchronize a complete value supplied by Flutter's current TextField.
  ///
  /// TextField owns undo while it is the input surface. External updates
  /// invalidate this model's history; once the native surface owns editing,
  /// use [applyEdit] or [applyEdits] instead.
  void replaceText(String value) {
    final previous = text;
    if (previous == value) return;
    var prefix = 0;
    while (prefix < previous.length &&
        prefix < value.length &&
        previous.codeUnitAt(prefix) == value.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < previous.length - prefix &&
        suffix < value.length - prefix &&
        previous.codeUnitAt(previous.length - suffix - 1) ==
            value.codeUnitAt(value.length - suffix - 1)) {
      suffix++;
    }
    _applyBatch([
      _OffsetEdit(
        prefix,
        previous.length - suffix,
        value.substring(prefix, value.length - suffix),
      ),
    ]);
    _undo.clear();
    _redo.clear();
    _undoOpen = false;
  }

  /// Apply disjoint edits against the same pre-edit snapshot as one undo step.
  /// Out-of-bounds coordinates clamp like [DocumentSnapshot]. Overlaps fail
  /// without mutating the document; ranges touching at an endpoint are allowed.
  void applyEdits(List<EditorDocumentEdit> edits) {
    final before = _snapshot;
    applyOffsetEdits([
      for (final edit in edits)
        EditorOffsetEdit(
          before.offsetAtPosition(edit.range.getStartPosition()),
          before.offsetAtPosition(edit.range.getEndPosition()),
          edit.text,
        ),
    ]);
  }

  /// Apply disjoint raw UTF-16 edits against the current text as one undo
  /// step, or append them to the newest step when [coalesce] is true and no
  /// other mutation, undo, redo or [closeUndoGroup] happened in between.
  ///
  /// [selectionsBefore]/[selectionsAfter] are cursor states (primary first)
  /// restored by [undo]/[redo]; a coalesced step keeps its first "before" and
  /// takes the latest "after". Offsets are clamped; overlaps throw
  /// [StateError] without mutating the document. Returns whether text changed.
  bool applyOffsetEdits(
    List<EditorOffsetEdit> edits, {
    List<TextSelection>? selectionsBefore,
    List<TextSelection>? selectionsAfter,
    bool coalesce = false,
  }) {
    final length = text.length;
    final resolved = <_OffsetEdit>[
      for (final edit in edits)
        _OffsetEdit(
          edit.start.clamp(0, length),
          edit.end.clamp(edit.start.clamp(0, length), length),
          edit.text,
        ),
    ];
    resolved.sort((a, b) {
      final start = a.start.compareTo(b.start);
      return start == 0 ? a.end.compareTo(b.end) : start;
    });
    for (var i = 1; i < resolved.length; i++) {
      if (resolved[i].start < resolved[i - 1].end) {
        throw StateError('Overlapping ranges are not allowed');
      }
    }
    final inverses = _applyBatch(resolved);
    if (inverses.isEmpty) {
      if (coalesce && _undoOpen && selectionsAfter != null) {
        _undo.last.selectionsAfter = selectionsAfter;
      }
      return false;
    }
    if (coalesce && _undoOpen && _undo.isNotEmpty) {
      final entry = _undo.last;
      entry.groups.insert(0, inverses);
      entry.selectionsAfter = selectionsAfter ?? entry.selectionsAfter;
    } else {
      _undo.add(_HistoryEntry([inverses], selectionsBefore, selectionsAfter));
    }
    _undoOpen = true;
    _redo.clear();
    return true;
  }

  /// Records [selections] as the cursor state after the newest undo step
  /// when that step is still the latest mutation (see [applyOffsetEdits]).
  void setUndoSelectionsAfter(List<TextSelection> selections) {
    if (_undoOpen && _undo.isNotEmpty) _undo.last.selectionsAfter = selections;
  }

  /// Ends the current undo step: the next coalescing edit starts a new one.
  void closeUndoGroup() => _undoOpen = false;

  bool undo() {
    if (_undo.isEmpty) return false;
    final entry = _undo.removeLast();
    _redo.add(
      _HistoryEntry(
        _applyGroups(entry.groups),
        entry.selectionsBefore,
        entry.selectionsAfter,
      ),
    );
    _restore(entry.selectionsBefore);
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    final entry = _redo.removeLast();
    _undo.add(
      _HistoryEntry(
        _applyGroups(entry.groups),
        entry.selectionsBefore,
        entry.selectionsAfter,
      ),
    );
    _restore(entry.selectionsAfter);
    return true;
  }

  void _restore(List<TextSelection>? selections) {
    _undoOpen = false;
    _restoredSelections = selections;
    _restoredVersion = _version;
  }

  /// Applies [groups] in order and returns the groups that reverse them, in
  /// the order they must be applied. Every edit is sequential (valid against
  /// the state left by the previous one); the snapshot is rebuilt only once.
  List<List<_OffsetEdit>> _applyGroups(List<List<_OffsetEdit>> groups) {
    final tree = _buffer.getPieceTree();
    String read(int start, int end) => start >= end
        ? ''
        : tree.getValueInRange2(tree.nodeAt(start)!, tree.nodeAt(end)!);
    final reversed = <List<_OffsetEdit>>[];
    var changed = false;
    _beginChanges();
    for (final group in groups) {
      final inverses = <_OffsetEdit>[];
      for (final edit in group) {
        final length = tree.getLength();
        final start = edit.start.clamp(0, length);
        final end = edit.end.clamp(start, length);
        final removed = read(start, end);
        if (removed == edit.text) continue;
        _recordChange(start, end, edit.text);
        if (end > start) tree.delete(start, end - start);
        if (edit.text.isNotEmpty) tree.insert(start, edit.text);
        inverses.add(_OffsetEdit(start, start + edit.text.length, removed));
        changed = true;
      }
      reversed.insert(0, inverses.reversed.toList());
    }
    if (changed) _commitTreeChange();
    _endChanges();
    return reversed;
  }

  void _commitTreeChange() {
    _contentFlagsStale = true;
    _snapshot = DocumentSnapshot(_buffer.getValue());
    _version++;
  }

  /// Applies sorted, disjoint [edits] (pre-edit offsets) from last to first
  /// and returns sequential inverses: applying them in order to the result,
  /// each against the state left by the previous one, restores the text.
  ///
  /// Raw piece-tree edits are used because the upstream buffer's applyEdits
  /// normalizes inserted text and the deleted text of its inverse edits;
  /// lone CR, LF/CRLF mixtures and CRLF boundary changes must round-trip.
  /// The snapshot is rebuilt once per batch, not once per edit.
  List<_OffsetEdit> _applyBatch(List<_OffsetEdit> edits) {
    final before = _snapshot.text;
    final tree = _buffer.getPieceTree();
    final inverses = <_OffsetEdit>[];
    _beginChanges();
    for (final edit in edits.reversed) {
      final removed = before.substring(edit.start, edit.end);
      if (removed == edit.text) continue;
      // Edits go last to first, so pre-edit offsets hold in the tree.
      _recordChange(edit.start, edit.end, edit.text);
      if (edit.end > edit.start) tree.delete(edit.start, edit.end - edit.start);
      if (edit.text.isNotEmpty) tree.insert(edit.start, edit.text);
      inverses.add(
        _OffsetEdit(edit.start, edit.start + edit.text.length, removed),
      );
    }
    if (inverses.isEmpty) {
      _pendingChanges = null;
      return const [];
    }
    _commitTreeChange();
    _endChanges();
    // Inverses were produced last-to-first, so the lowest edit is last. Its
    // offsets are valid in the final text; each earlier inverse is valid once
    // every lower edit has been reverted.
    return inverses.reversed.toList();
  }

  void _beginChanges() =>
      _pendingChanges = _changes.hasListener ? <EditorContentChange>[] : null;

  /// Records replacing [start, end) of the tree's current text with [text]
  /// as a protocol change, before the tree is edited.
  void _recordChange(int start, int end, String text) {
    final changes = _pendingChanges;
    if (changes == null) return;
    final tree = _buffer.getPieceTree();
    final length = tree.getLength();
    bool insideCrlf(int offset) =>
        offset > 0 &&
        offset < length &&
        tree.getCharCode(offset - 1) == 0x0D &&
        tree.getCharCode(offset) == 0x0A;
    // A position cannot fall between CR and LF: take in the whole pair.
    if (insideCrlf(start)) {
      start--;
      text = '\r$text';
    }
    if (insideCrlf(end)) {
      end++;
      text = '$text\n';
    }
    final from = tree.getPositionAt(start);
    final to = tree.getPositionAt(end);
    changes.add(
      EditorContentChange(
        startLine: from.lineNumber - 1,
        startCharacter: from.column - 1,
        endLine: to.lineNumber - 1,
        endCharacter: to.column - 1,
        rangeOffset: start,
        rangeLength: end - start,
        text: text,
      ),
    );
  }

  void _endChanges() {
    final changes = _pendingChanges;
    _pendingChanges = null;
    if (changes == null || changes.isEmpty || _changes.isClosed) return;
    _changes.add(EditorContentChangeEvent(_version, changes, text));
  }

  void dispose() {
    _buffer.dispose();
    unawaited(_changes.close());
  }
}

/// Line access for the ported cursor operations over one immutable snapshot.
class DocumentCursorModel implements ICursorSimpleModel {
  DocumentCursorModel(this.snapshot);

  final DocumentSnapshot snapshot;

  @override
  int getLineCount() => snapshot.lineCount;

  @override
  String getLineContent(int lineNumber) => snapshot.text.substring(
    snapshot.lineStarts[lineNumber - 1],
    snapshot.contentEnds[lineNumber - 1],
  );

  @override
  int getLineMinColumn(int lineNumber) => 1;

  @override
  int getLineMaxColumn(int lineNumber) =>
      snapshot.contentEnds[lineNumber - 1] -
      snapshot.lineStarts[lineNumber - 1] +
      1;

  @override
  int getLineFirstNonWhitespaceColumn(int lineNumber) {
    final text = snapshot.text;
    final start = snapshot.lineStarts[lineNumber - 1];
    final end = snapshot.contentEnds[lineNumber - 1];
    for (var i = start; i < end; i++) {
      final c = text.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) return i - start + 1;
    }
    return 0;
  }

  @override
  int getLineLastNonWhitespaceColumn(int lineNumber) {
    final text = snapshot.text;
    final start = snapshot.lineStarts[lineNumber - 1];
    for (var i = snapshot.contentEnds[lineNumber - 1] - 1; i >= start; i--) {
      final c = text.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) return i - start + 2;
    }
    return 0;
  }
}
