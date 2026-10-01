/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/
// Source-derived subset of model/textModel.ts, model.ts, textModelEvents.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// Omitted upstream subsystems: tokenization/embedded languages, bracket pairs,
// guides, search/word navigation, injected text/rendering decorations, raw view
// events, attached views, large-file safeguards, language configuration service,
// indentation detection/normalization, unusual terminator removal, BOM-sensitive
// heap safeguards, and external undo snapshots. No placeholder APIs for these.
// Unbound models retain local history; explicitly bound models use resource-wide
// EditStack. Without upstream ModelService detachment, dispose clears only the
// bound resource; restored selections are exposed as cursorState, not raw events.
// Restore events are emitted per operation; this subset keeps EOL undo flags.

import 'dart:math' as math;

import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../core/text_change.dart';
import '../text_model_edit_source.dart';
import '../text_model_events.dart';
import 'interval_tree.dart';
import 'edit_stack.dart';
import '../../../platform/undo_redo/common/undo_redo_service.dart';
import 'piece_tree_text_buffer/piece_tree_base.dart' show PieceTreeSnapshot;
import 'piece_tree_text_buffer/piece_tree_text_buffer.dart';
import 'piece_tree_text_buffer/piece_tree_text_buffer_builder.dart';
import 'text_model_contracts.dart';

export 'text_model_contracts.dart';

class _Snapshot implements TextSnapshot {
  _Snapshot(this._snapshot);
  final PieceTreeSnapshot _snapshot;
  @override
  String? read() => _snapshot.read();
}

class _EditRecord {
  _EditRecord(
    this.forward,
    this.reverse,
    this.beforeAlternative,
    this.afterAlternative, {
    this.previousEOL,
    this.nextEOL,
  });
  final List<TextModelEditOperation> forward;
  final List<ValidEditOperation> reverse;
  final int beforeAlternative;
  final int afterAlternative;
  final EndOfLineSequence? previousEOL;
  final EndOfLineSequence? nextEOL;
}

class TextModel {
  TextModel(
    String value, {
    this._languageId = 'plaintext',
    TextModelOptions options = const TextModelOptions(),
  }) : id = '\$model${++_nextId}',
       _options = _resolveOptions(options) {
    _buffer = _makeBuffer(value, options.defaultEOL);
  }

  static int _nextId = 0;
  final String id;
  late PieceTreeTextBuffer _buffer;
  TextModelResolvedOptions _options;
  String _languageId;
  int _versionId = 1;
  int _alternativeVersionId = 1;
  bool _disposed = false;
  bool _undoing = false;
  bool _redoing = false;
  IntervalTree _decorations = IntervalTree();
  final Map<String, IntervalNode> _decorationIds = {};
  int _nextDecorationId = 0;
  final List<void Function(ModelContentChangedEvent)> _contentListeners = [];
  final List<void Function()> _decorationListeners = [];
  final List<void Function(ModelOptionsChangedEvent)> _optionListeners = [];
  final List<void Function(ModelLanguageChangedEvent)> _languageListeners = [];
  final List<void Function()> _disposeListeners = [];
  final List<List<_EditRecord>> _undoStack = [];
  final List<List<_EditRecord>> _redoStack = [];
  List<_EditRecord> _pending = [];
  List<int>? _trimAutoWhitespaceLines;
  EditStack? _editStack;
  List<Selection>? _cursorState;
  List<ModelContentChangedEvent>? _deferredRestoreEvents;
  bool _deferredRestoreDecorations = false;

  /// Opt in to resource-wide history. A service can bind only one live model
  /// per resource; the unbound model retains its local undo behavior.
  EditStack bindUndoRedo(Uri resource, UndoRedoService service) {
    _assertAlive();
    if (_editStack != null) throw StateError('Model is already bound');
    if (_pending.isNotEmpty || _undoStack.isNotEmpty || _redoStack.isNotEmpty) {
      throw StateError('Cannot bind a model with local undo history');
    }
    service.claimResource(resource, this);
    try {
      final stack = EditStack(this, service, resource);
      _editStack = stack;
      _undoStack.clear();
      _redoStack.clear();
      _pending.clear();
      return stack;
    } catch (_) {
      service.releaseResource(resource, this);
      rethrow;
    }
  }

  List<Selection>? get cursorState =>
      _cursorState == null ? null : List.unmodifiable(_cursorState!);

  /// Used by the bound stack after computing the directional after-selection.
  void setEditStackCursorState(List<Selection>? selections) {
    _assertAlive();
    if (_editStack == null) throw StateError('Model is not bound');
    _cursorState = selections == null ? null : List.of(selections);
  }

  static PieceTreeTextBuffer _makeBuffer(String value, DefaultEndOfLine eol) {
    final builder = PieceTreeTextBufferBuilder()..acceptChunk(value);
    return builder.finish().create(eol);
  }

  static TextModelResolvedOptions _resolveOptions(TextModelOptions options) {
    final tab = math.max(1, options.tabSize);
    final indent = options.indentSize == null
        ? tab
        : math.max(1, options.indentSize!);
    return TextModelResolvedOptions(
      tabSize: tab,
      indentSize: indent,
      originalIndentSize: options.indentSize,
      insertSpaces: options.insertSpaces,
      trimAutoWhitespace: options.trimAutoWhitespace,
      defaultEOL: options.defaultEOL,
    );
  }

  void _assertAlive() {
    if (_disposed) throw StateError('Model is disposed!');
  }

  bool isDisposed() => _disposed;
  void dispose() {
    if (_disposed) return;
    for (final listener in List<void Function()>.of(_disposeListeners)) {
      listener();
    }
    final stack = _editStack;
    if (stack != null) {
      stack.clear();
      stack.undoRedoService.releaseResource(stack.resource, this);
      _editStack = null;
    }
    _disposed = true;
    _buffer.dispose();
    _contentListeners.clear();
    _decorationListeners.clear();
    _optionListeners.clear();
    _languageListeners.clear();
    _disposeListeners.clear();
    _undoStack.clear();
    _redoStack.clear();
    _pending.clear();
    _cursorState = null;
    _decorationIds.clear();
    _decorations = IntervalTree();
  }

  void Function() onWillDispose(void Function() listener) =>
      _listen(_disposeListeners, listener);
  void Function() onDidChangeContent(
    void Function(ModelContentChangedEvent) listener,
  ) => _listen(_contentListeners, listener);
  void Function() onDidChangeDecorations(void Function() listener) =>
      _listen(_decorationListeners, listener);
  void Function() onDidChangeOptions(
    void Function(ModelOptionsChangedEvent) listener,
  ) => _listen(_optionListeners, listener);
  void Function() onDidChangeLanguage(
    void Function(ModelLanguageChangedEvent) listener,
  ) => _listen(_languageListeners, listener);
  void Function() _listen<T>(List<T> listeners, T listener) {
    _assertAlive();
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void _emitContent(
    List<InternalModelContentChange> changes, {
    bool flush = false,
    bool eolChange = false,
    TextModelEditSource reason = EditSources.applyEdits,
  }) {
    final event = ModelContentChangedEvent(
      changes: List.unmodifiable(changes),
      eol: getEOL(),
      versionId: _versionId,
      isUndoing: _undoing,
      isRedoing: _redoing,
      isFlush: flush,
      isEolChange: eolChange,
      detailedReasons: [reason],
    );
    if (_deferredRestoreEvents case final events?) {
      events.add(event);
      return;
    }
    for (final listener in List.of(_contentListeners)) {
      listener(event);
    }
  }

  void _emitDecorations() {
    if (_deferredRestoreEvents != null) {
      _deferredRestoreDecorations = true;
      return;
    }
    for (final listener in List.of(_decorationListeners)) {
      listener();
    }
  }

  int getVersionId() {
    _assertAlive();
    return _versionId;
  }

  int getAlternativeVersionId() {
    _assertAlive();
    return _alternativeVersionId;
  }

  void _increaseVersion() {
    _alternativeVersionId = ++_versionId;
  }

  String getLanguageId() {
    _assertAlive();
    return _languageId;
  }

  void setLanguage(String languageId, {String source = 'api'}) {
    _assertAlive();
    if (_languageId == languageId) return;
    final old = _languageId;
    _languageId = languageId;
    final event = ModelLanguageChangedEvent(old, languageId, source);
    for (final listener in List.of(_languageListeners)) {
      listener(event);
    }
  }

  TextModelResolvedOptions getOptions() {
    _assertAlive();
    return _options;
  }

  void updateOptions({
    int? tabSize,
    int? indentSize,
    bool? insertSpaces,
    bool? trimAutoWhitespace,
  }) {
    _assertAlive();
    final previous = _options;
    final tab = math.max(1, tabSize ?? previous.tabSize);
    final originalIndent = indentSize ?? previous.originalIndentSize;
    final next = TextModelResolvedOptions(
      tabSize: tab,
      indentSize: originalIndent == null ? tab : math.max(1, originalIndent),
      originalIndentSize: originalIndent,
      insertSpaces: insertSpaces ?? previous.insertSpaces,
      trimAutoWhitespace: trimAutoWhitespace ?? previous.trimAutoWhitespace,
      defaultEOL: previous.defaultEOL,
    );
    if (next.tabSize == previous.tabSize &&
        next.indentSize == previous.indentSize &&
        next.originalIndentSize == previous.originalIndentSize &&
        next.insertSpaces == previous.insertSpaces &&
        next.trimAutoWhitespace == previous.trimAutoWhitespace) {
      return;
    }
    _options = next;
    final event = ModelOptionsChangedEvent(
      tabSize: previous.tabSize != next.tabSize,
      indentSize: previous.indentSize != next.indentSize,
      insertSpaces: previous.insertSpaces != next.insertSpaces,
      trimAutoWhitespace:
          previous.trimAutoWhitespace != next.trimAutoWhitespace,
    );
    for (final listener in List.of(_optionListeners)) {
      listener(event);
    }
  }

  String getValue([
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
    bool preserveBOM = false,
  ]) =>
      (preserveBOM ? _buffer.getBOM() : '') +
      getValueInRange(getFullModelRange(), eol);
  int getValueLength([
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
    bool preserveBOM = false,
  ]) =>
      (preserveBOM ? _buffer.getBOM().length : 0) +
      getValueLengthInRange(getFullModelRange(), eol);
  String getValueInRange(
    IRange range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) {
    _assertAlive();
    return _buffer.getValueInRange(validateRange(range), eol);
  }

  int getValueLengthInRange(
    IRange range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) {
    _assertAlive();
    return _buffer.getValueLengthInRange(validateRange(range), eol);
  }

  int getCharacterCountInRange(
    IRange range, [
    EndOfLinePreference eol = EndOfLinePreference.textDefined,
  ]) {
    _assertAlive();
    return _buffer.getCharacterCountInRange(validateRange(range), eol);
  }

  TextSnapshot createSnapshot([bool preserveBOM = false]) {
    _assertAlive();
    return _Snapshot(_buffer.createSnapshot(preserveBOM));
  }

  int getLineCount() {
    _assertAlive();
    return _buffer.getLineCount();
  }

  String getLineContent(int lineNumber) {
    _checkLine(lineNumber);
    return _buffer.getLineContent(lineNumber);
  }

  int getLineLength(int lineNumber) {
    _checkLine(lineNumber);
    return _buffer.getLineLength(lineNumber);
  }

  List<String> getLinesContent() {
    _assertAlive();
    return _buffer.getLinesContent();
  }

  int getLineMaxColumn(int lineNumber) {
    _checkLine(lineNumber);
    return _buffer.getLineMaxColumn(lineNumber);
  }

  int getLineMinColumn(int lineNumber) {
    _assertAlive();
    return 1;
  }

  int getLineFirstNonWhitespaceColumn(int lineNumber) {
    _checkLine(lineNumber);
    return _buffer.getLineFirstNonWhitespaceColumn(lineNumber);
  }

  int getLineLastNonWhitespaceColumn(int lineNumber) {
    _checkLine(lineNumber);
    return _buffer.getLineLastNonWhitespaceColumn(lineNumber);
  }

  void _checkLine(int line) {
    _assertAlive();
    if (line < 1 || line > _buffer.getLineCount()) {
      throw RangeError.value(line, 'lineNumber');
    }
  }

  String getEOL() {
    _assertAlive();
    return _buffer.getEOL();
  }

  EndOfLineSequence getEndOfLineSequence() =>
      getEOL() == '\n' ? EndOfLineSequence.lf : EndOfLineSequence.crlf;
  bool mightContainRTL() {
    _assertAlive();
    return _buffer.mightContainRTL();
  }

  bool mightContainNonBasicASCII() {
    _assertAlive();
    return _buffer.mightContainNonBasicASCII();
  }

  bool mightContainUnusualLineTerminators() {
    _assertAlive();
    return _buffer.mightContainUnusualLineTerminators();
  }

  Range getFullModelRange() {
    final line = getLineCount();
    return Range(1, 1, line, getLineMaxColumn(line));
  }

  Position getPositionAt(int offset) {
    _assertAlive();
    return _buffer.getPositionAt(offset.clamp(0, _buffer.getLength()));
  }

  int getOffsetAt(IPosition position) {
    _assertAlive();
    final valid = _validatePosition(
      position.lineNumber,
      position.column,
      false,
    );
    return _buffer.getOffsetAt(valid.lineNumber, valid.column);
  }

  Position modifyPosition(IPosition position, int offset) =>
      getPositionAt(getOffsetAt(position) + offset);
  Position _validatePosition(int line, int col, bool surrogatePairs) {
    final count = _buffer.getLineCount();
    if (line < 1) return const Position(1, 1);
    if (line > count) return Position(count, _buffer.getLineMaxColumn(count));
    final column = col.clamp(1, _buffer.getLineMaxColumn(line));
    if (surrogatePairs &&
        column > 1 &&
        column < _buffer.getLineMaxColumn(line) &&
        _isHighSurrogate(_buffer.getLineCharCode(line, column - 2))) {
      return Position(line, column - 1);
    }
    return Position(line, column);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xd800 && unit <= 0xdbff;
  Position validatePosition(IPosition position) {
    _assertAlive();
    return _validatePosition(position.lineNumber, position.column, true);
  }

  bool isValidRange(Range range) {
    _assertAlive();
    for (final position in [range.getStartPosition(), range.getEndPosition()]) {
      if (position.lineNumber < 1 ||
          position.lineNumber > getLineCount() ||
          position.column < 1 ||
          position.column > getLineMaxColumn(position.lineNumber)) {
        return false;
      }
      if (position.column > 1 &&
          position.column < getLineMaxColumn(position.lineNumber) &&
          _isHighSurrogate(
            _buffer.getLineCharCode(position.lineNumber, position.column - 2),
          )) {
        return false;
      }
    }
    return true;
  }

  Range validateRange(IRange range) {
    _assertAlive();
    if (range is Range && range is! Selection && isValidRange(range)) {
      return range;
    }
    final start = _validatePosition(
      range.startLineNumber,
      range.startColumn,
      false,
    );
    final end = _validatePosition(range.endLineNumber, range.endColumn, false);
    final insideStart =
        start.column > 1 &&
        start.column < getLineMaxColumn(start.lineNumber) &&
        _isHighSurrogate(
          _buffer.getLineCharCode(start.lineNumber, start.column - 2),
        );
    final insideEnd =
        end.column > 1 &&
        end.column < getLineMaxColumn(end.lineNumber) &&
        _isHighSurrogate(
          _buffer.getLineCharCode(end.lineNumber, end.column - 2),
        );
    if (insideStart && Position.equalsPositions(start, end)) {
      return Range(
        start.lineNumber,
        start.column - 1,
        end.lineNumber,
        end.column - 1,
      );
    }
    return Range(
      start.lineNumber,
      start.column - (insideStart ? 1 : 0),
      end.lineNumber,
      end.column + (insideEnd ? 1 : 0),
    );
  }

  Range _validateRangeRelaxed(IRange range) {
    final start = _validatePosition(
      range.startLineNumber,
      range.startColumn,
      false,
    );
    final end = _validatePosition(range.endLineNumber, range.endColumn, false);
    return Range(start.lineNumber, start.column, end.lineNumber, end.column);
  }

  static String _snapshotText(TextSnapshot snapshot) {
    final chunks = <String>[];
    String? chunk;
    while ((chunk = snapshot.read()) != null) {
      chunks.add(chunk!);
    }
    return chunks.join();
  }

  void setValue(
    Object value, {
    TextModelEditSource reason = EditSources.setValue,
  }) {
    _assertAlive();
    final text = switch (value) {
      String text => text,
      TextSnapshot snapshot => _snapshotText(snapshot),
      _ => throw ArgumentError.value(
        value,
        'value',
        'Expected a string or TextSnapshot',
      ),
    };
    final oldRange = getFullModelRange();
    final oldLength = getValueLength();
    final replacement = _makeBuffer(text, _options.defaultEOL);
    try {
      _editStack?.clear();
    } catch (_) {
      replacement.dispose();
      rethrow;
    }
    _buffer.dispose();
    _buffer = replacement;
    _decorations = IntervalTree();
    _decorationIds.clear();
    _undoStack.clear();
    _redoStack.clear();
    _pending.clear();
    _cursorState = null;
    _trimAutoWhitespaceLines = null;
    _increaseVersion();
    _emitContent(
      [InternalModelContentChange(oldRange, oldLength, getValue(), 0, false)],
      flush: true,
      reason: reason,
    );
  }

  void setEOL(EndOfLineSequence sequence) {
    _assertAlive();
    final eol = sequence == EndOfLineSequence.crlf ? '\r\n' : '\n';
    if (getEOL() == eol) return;
    final oldRange = getFullModelRange();
    final oldLength = getValueLength();
    final nodes = _decorations.search(0, false, false, _versionId, false);
    final ranges = {
      for (final node in nodes) node: getDecorationRange(node.id!)!,
    };
    _buffer.setEOL(eol);
    _increaseVersion();
    for (final node in nodes) {
      final range = ranges[node]!;
      _decorations.delete(node);
      node.reset(
        _versionId,
        _buffer.getOffsetAt(range.startLineNumber, range.startColumn),
        _buffer.getOffsetAt(range.endLineNumber, range.endColumn),
        range,
      );
      _decorations.insert(node);
    }
    _emitContent(
      [InternalModelContentChange(oldRange, oldLength, getValue(), 0, false)],
      eolChange: true,
      reason: EditSources.eolChange,
    );
  }

  List<ValidEditOperation>? applyEdits(
    List<TextModelEditOperation> operations, {
    bool computeUndoEdits = false,
    TextModelEditSource reason = EditSources.applyEdits,
  }) {
    _assertAlive();
    final validated = <ValidAnnotatedEditOperation>[];
    for (final op in operations) {
      final range = validateRange(op.range);
      var text = op.text;
      if (text != null &&
          text.endsWith('\r') &&
          getEOL() == '\r\n' &&
          range.endColumn == getLineMaxColumn(range.endLineNumber)) {
        text = text.substring(0, text.length - 1);
      }
      validated.add(
        ValidAnnotatedEditOperation(
          op.identifier,
          range,
          text,
          forceMoveMarkers: op.forceMoveMarkers,
          isAutoWhitespaceEdit: op.isAutoWhitespaceEdit,
          isTracked: op.isTracked,
        ),
      );
    }
    final result = _buffer.applyEdits(
      validated,
      _options.trimAutoWhitespace,
      computeUndoEdits,
    );
    _trimAutoWhitespaceLines = result.trimAutoWhitespaceLineNumbers;
    if (result.changes.isNotEmpty) {
      for (final change in result.changes) {
        _decorations.acceptReplace(
          change.rangeOffset,
          change.rangeLength,
          change.text.length,
          change.forceMoveMarkers,
        );
      }
      _increaseVersion();
      _emitDecorations();
      _emitContent(result.changes, reason: reason);
    }
    return result.reverseEdits;
  }

  /// Restore a bound stack entry through the same edit/EOL pipeline used for
  /// forward changes. Offsets and source text are checked before any mutation;
  /// a stale entry must leave the model and the resource stack untouched.
  void restoreEditStack(
    List<TextChange> changes, {
    required bool undoing,
    required String eol,
    required int version,
    required List<Selection>? selections,
  }) {
    _assertAlive();
    if (_editStack == null) throw StateError('Model is not bound');
    if (_undoing || _redoing) throw StateError('Undo/redo is in progress');
    if (changes.isNotEmpty && getEOL() != eol) {
      throw StateError('Edit history EOL does not match the model');
    }
    final text = getValue();
    final operations = <TextModelEditOperation>[];
    for (final change in changes) {
      final offset = undoing ? change.newPosition : change.oldPosition;
      final from = undoing ? change.newText : change.oldText;
      final to = undoing ? change.oldText : change.newText;
      if (offset < 0 ||
          offset + from.length > text.length ||
          text.substring(offset, offset + from.length) != from) {
        throw StateError('Edit history does not match the current model');
      }
      final start = getPositionAt(offset);
      final end = getPositionAt(offset + from.length);
      if (getOffsetAt(start) != offset ||
          getOffsetAt(end) != offset + from.length) {
        throw StateError('Edit history splits a line ending');
      }
      final range = Range.fromPositions(start, end);
      if (!isValidRange(range)) {
        throw StateError('Edit history splits a surrogate pair');
      }
      operations.add(TextModelEditOperation(range, to));
    }
    _undoing = undoing;
    _redoing = !undoing;
    _deferredRestoreEvents = [];
    var completed = false;
    try {
      if (operations.isNotEmpty) {
        applyEdits(operations);
      } else if (getEOL() != eol) {
        setEOL(eol == '\r\n' ? EndOfLineSequence.crlf : EndOfLineSequence.lf);
      }
      _alternativeVersionId = version;
      _cursorState = selections == null ? null : List.of(selections);
      completed = true;
    } finally {
      final events = _deferredRestoreEvents!;
      final decorationsChanged = _deferredRestoreDecorations;
      _deferredRestoreEvents = null;
      _deferredRestoreDecorations = false;
      _undoing = false;
      _redoing = false;
      if (completed) {
        if (decorationsChanged) _emitDecorations();
        for (final event in events) {
          for (final listener in List.of(_contentListeners)) {
            listener(event);
          }
        }
      }
    }
  }

  /// Unlike setEOL, this EOL change participates in the local undo history.
  void pushEOL(EndOfLineSequence sequence) {
    _assertAlive();
    final previous = getEndOfLineSequence();
    if (previous == sequence) return;
    if (_editStack case final stack?) {
      stack.pushEOL(sequence);
      return;
    }
    final before = _alternativeVersionId;
    setEOL(sequence);
    _pending.add(
      _EditRecord(
        [],
        [],
        before,
        _alternativeVersionId,
        previousEOL: previous,
        nextEOL: sequence,
      ),
    );
    _redoStack.clear();
  }

  /// Local undo groups: repeated pushes coalesce until pushStackElement; applyEdits is not undoable.
  void pushStackElement() {
    _assertAlive();
    if (_editStack case final stack?) {
      stack.pushStackElement();
    } else {
      _closeGroup();
    }
  }

  void popStackElement() {
    _assertAlive();
    if (_editStack case final stack?) {
      stack.popStackElement();
      return;
    }
    if (_pending.isEmpty && _undoStack.isNotEmpty) {
      _pending = _undoStack.removeLast();
    }
  }

  void _closeGroup() {
    if (_pending.isNotEmpty) {
      _undoStack.add(_pending);
      _pending = [];
    }
  }

  void _appendTrimAutoWhitespaceEdits(
    List<TextModelEditOperation> edits,
    List<Selection>? beforeCursorState,
  ) {
    final lines = _trimAutoWhitespaceLines;
    _trimAutoWhitespaceLines = null;
    if (!_options.trimAutoWhitespace || lines == null) return;
    if (beforeCursorState != null &&
        beforeCursorState.any(
          (selection) => !edits.any(
            (edit) =>
                edit.range.startLineNumber <= selection.endLineNumber &&
                selection.startLineNumber <= edit.range.endLineNumber,
          ),
        )) {
      return;
    }
    for (final line in lines) {
      if (line < 1 || line > getLineCount()) continue;
      final maxColumn = getLineMaxColumn(line);
      var allowTrim = true;
      for (final edit in edits) {
        final range = edit.range;
        if (line < range.startLineNumber || line > range.endLineNumber) {
          continue;
        }
        final text = edit.text ?? '';
        if (line == range.startLineNumber &&
            range.startColumn == maxColumn &&
            range.isEmpty() &&
            text.startsWith('\n')) {
          continue;
        }
        if (line == range.startLineNumber &&
            range.startColumn == 1 &&
            range.isEmpty() &&
            text.endsWith('\n')) {
          continue;
        }
        allowTrim = false;
        break;
      }
      if (allowTrim) {
        edits.add(
          TextModelEditOperation(Range(line, 1, line, maxColumn), null),
        );
      }
    }
  }

  List<Selection>? pushEditOperations(
    List<Selection>? beforeCursorState,
    List<TextModelEditOperation> operations,
    List<Selection>? Function(List<ValidEditOperation>)? cursorStateComputer, {
    UndoRedoGroup? group,
  }) {
    _assertAlive();
    if (_editStack case final stack?) {
      final forward = [
        for (final op in operations)
          TextModelEditOperation(
            validateRange(op.range),
            op.text,
            identifier: op.identifier,
            forceMoveMarkers: op.forceMoveMarkers,
            isAutoWhitespaceEdit: op.isAutoWhitespaceEdit,
            isTracked: op.isTracked,
          ),
      ];
      _appendTrimAutoWhitespaceEdits(forward, beforeCursorState);
      return stack.pushEditOperation(
        beforeCursorState,
        forward,
        cursorStateComputer: cursorStateComputer,
        group: group,
      );
    }
    if (group != null) {
      throw StateError('Grouped edits require a bound undo/redo service');
    }
    final before = _alternativeVersionId;
    final forward = [
      for (final op in operations)
        TextModelEditOperation(
          validateRange(op.range),
          op.text,
          identifier: op.identifier,
          forceMoveMarkers: op.forceMoveMarkers,
          isAutoWhitespaceEdit: op.isAutoWhitespaceEdit,
          isTracked: op.isTracked,
        ),
    ];
    _appendTrimAutoWhitespaceEdits(forward, beforeCursorState);
    final reverse = applyEdits(forward, computeUndoEdits: true)!;
    if (_alternativeVersionId != before) {
      _pending.add(
        _EditRecord(forward, reverse, before, _alternativeVersionId),
      );
      _redoStack.clear();
    }
    return cursorStateComputer?.call(reverse);
  }

  bool canUndo() {
    _assertAlive();
    if (_editStack case final stack?) {
      return stack.undoRedoService.canUndo(stack.resource);
    }
    return _pending.isNotEmpty || _undoStack.isNotEmpty;
  }

  bool canRedo() {
    _assertAlive();
    if (_editStack case final stack?) {
      return stack.undoRedoService.canRedo(stack.resource);
    }
    return _redoStack.isNotEmpty;
  }

  void undo() {
    _assertAlive();
    if (_editStack case final stack?) {
      stack.undoRedoService.undo(stack.resource);
      return;
    }
    _closeGroup();
    if (_undoStack.isEmpty) return;
    final group = _undoStack.removeLast();
    _undoing = true;
    try {
      for (final record in group.reversed) {
        if (record.previousEOL case final previous?) {
          setEOL(previous);
        } else {
          applyEdits([
            for (final op in record.reverse)
              TextModelEditOperation(op.range, op.text),
          ]);
        }
        _alternativeVersionId = record.beforeAlternative;
      }
    } finally {
      _undoing = false;
    }
    _redoStack.add(group);
  }

  void redo() {
    _assertAlive();
    if (_editStack case final stack?) {
      stack.undoRedoService.redo(stack.resource);
      return;
    }
    if (_redoStack.isEmpty) return;
    final group = _redoStack.removeLast();
    _redoing = true;
    try {
      for (final record in group) {
        if (record.nextEOL case final next?) {
          setEOL(next);
        } else {
          applyEdits(record.forward);
        }
        _alternativeVersionId = record.afterAlternative;
      }
    } finally {
      _redoing = false;
    }
    _undoStack.add(group);
  }

  List<String> deltaDecorations(
    List<String> oldIds,
    List<ModelDeltaDecoration> newDecorations, {
    int ownerId = 0,
  }) {
    _assertAlive();
    if (oldIds.isEmpty && newDecorations.isEmpty) return [];
    final ids = <String>[];
    var changed = false;
    for (var i = 0; i < math.max(oldIds.length, newDecorations.length); i++) {
      IntervalNode? node = i < oldIds.length ? _decorationIds[oldIds[i]] : null;
      if (node != null) {
        _decorations.delete(node);
        changed = true;
      }
      if (i < newDecorations.length) {
        final decoration = newDecorations[i];
        final range = _validateRangeRelaxed(decoration.range);
        node ??= IntervalNode('$id;${++_nextDecorationId}', 0, 0);
        node.ownerId = ownerId;
        node.reset(
          _versionId,
          _buffer.getOffsetAt(range.startLineNumber, range.startColumn),
          _buffer.getOffsetAt(range.endLineNumber, range.endColumn),
          range,
        );
        node.setOptions(decoration.options);
        _decorationIds[node.id!] = node;
        _decorations.insert(node);
        ids.add(node.id!);
        changed = true;
      } else if (node != null) {
        _decorationIds.remove(node.id);
      }
    }
    if (changed) _emitDecorations();
    return ids;
  }

  Range? getDecorationRange(String id) {
    _assertAlive();
    final node = _decorationIds[id];
    if (node == null) return null;
    _decorations.resolveNode(node, _versionId);
    return node.range ??= Range(
      getPositionAt(node.cachedAbsoluteStart).lineNumber,
      getPositionAt(node.cachedAbsoluteStart).column,
      getPositionAt(node.cachedAbsoluteEnd).lineNumber,
      getPositionAt(node.cachedAbsoluteEnd).column,
    );
  }

  IntervalNodeOptions? getDecorationOptions(String id) {
    _assertAlive();
    return _decorationIds[id]?.options;
  }

  List<ModelDecoration> getAllDecorations({
    int ownerId = 0,
    bool filterOutValidation = false,
  }) {
    _assertAlive();
    return [
      for (final node in _decorations.search(
        ownerId,
        filterOutValidation,
        false,
        _versionId,
        false,
      ))
        ModelDecoration(
          node.id!,
          getDecorationRange(node.id!)!,
          node.options!,
          node.ownerId,
        ),
    ];
  }

  List<ModelDecoration> getDecorationsInRange(
    IRange range, {
    int ownerId = 0,
    bool filterOutValidation = false,
  }) {
    _assertAlive();
    final valid = validateRange(range);
    return [
      for (final node in _decorations.intervalSearch(
        getOffsetAt(valid.getStartPosition()),
        getOffsetAt(valid.getEndPosition()),
        ownerId,
        filterOutValidation,
        false,
        _versionId,
        false,
      ))
        ModelDecoration(
          node.id!,
          getDecorationRange(node.id!)!,
          node.options!,
          node.ownerId,
        ),
    ];
  }

  void removeAllDecorationsWithOwnerId(int ownerId) {
    if (_disposed) return;
    final nodes = _decorations.collectNodesFromOwner(ownerId);
    for (final node in nodes) {
      _decorations.delete(node);
      _decorationIds.remove(node.id);
    }
    if (nodes.isNotEmpty) _emitDecorations();
  }
}
