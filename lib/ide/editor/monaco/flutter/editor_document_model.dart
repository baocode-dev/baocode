import '../vs/editor/common/core/position.dart';
import '../vs/editor/common/core/range.dart';
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

class _OffsetEdit {
  const _OffsetEdit(this.start, this.end, this.text, this.range);

  final int start;
  final int end;
  final String text;
  final Range? range;
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

  static final RegExp _lineEnding = RegExp(r'\r\n|\r|\n');

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
  final List<List<_OffsetEdit>> _undo = [];
  final List<List<_OffsetEdit>> _redo = [];

  String get text => _snapshot.text;
  DocumentSnapshot get snapshot => _snapshot;
  String get savedText => _savedText;
  bool get isDirty => text != _savedText;
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  bool get mightContainRTL => _buffer.mightContainRTL();
  bool get mightContainNonBasicASCII => _buffer.mightContainNonBasicASCII();
  bool get mightContainUnusualLineTerminators =>
      _buffer.mightContainUnusualLineTerminators();

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
    _apply(
      _OffsetEdit(
        prefix,
        previous.length - suffix,
        value.substring(prefix, value.length - suffix),
        null,
      ),
    );
    _undo.clear();
    _redo.clear();
  }

  /// Apply disjoint edits against the same pre-edit snapshot as one undo step.
  /// Out-of-bounds coordinates clamp like [DocumentSnapshot]. Overlaps fail
  /// without mutating the document; ranges touching at an endpoint are allowed.
  void applyEdits(List<EditorDocumentEdit> edits) {
    final before = _snapshot;
    final resolved = <_OffsetEdit>[
      for (final edit in edits)
        _OffsetEdit(
          before.offsetAtPosition(edit.range.getStartPosition()),
          before.offsetAtPosition(edit.range.getEndPosition()),
          edit.text,
          edit.range,
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

    final inverses = <_OffsetEdit>[];
    for (final edit in resolved.reversed) {
      final inverse = _apply(edit);
      if (inverse != null) inverses.add(inverse);
    }
    if (inverses.isEmpty) return;
    _undo.add(inverses.reversed.toList());
    _redo.clear();
  }

  bool undo() {
    if (_undo.isEmpty) return false;
    _redo.add(_applyGroup(_undo.removeLast()));
    return true;
  }

  bool redo() {
    if (_redo.isEmpty) return false;
    _undo.add(_applyGroup(_redo.removeLast()));
    return true;
  }

  List<_OffsetEdit> _applyGroup(List<_OffsetEdit> edits) {
    final inverses = <_OffsetEdit>[];
    for (final edit in edits) {
      final inverse = _apply(edit);
      if (inverse != null) inverses.add(inverse);
    }
    return inverses.reversed.toList();
  }

  _OffsetEdit? _apply(_OffsetEdit edit) {
    final before = _snapshot;
    final removed = before.text.substring(edit.start, edit.end);
    if (removed == edit.text) return null;
    final start = before.positionAtOffset(edit.start);
    final end = before.positionAtOffset(edit.end);
    final canonicalRange = Range.fromPositions(start, end);
    // The piece tree does not clamp columns on the first line. Never pass an
    // out-of-bounds caller range through merely because its snapshot offsets
    // happened to clamp to the same values.
    final range = edit.range != null && edit.range!.equalsRange(canonicalRange)
        ? edit.range!
        : canonicalRange;
    final canUseRange =
        before.offsetAtPosition(start) == edit.start &&
        before.offsetAtPosition(end) == edit.end;
    final eol = _buffer.getEOL();
    final canUseUpstream =
        canUseRange &&
        removed.replaceAll(_lineEnding, eol) == removed &&
        edit.text.replaceAll(_lineEnding, eol) == edit.text;

    ValidEditOperation? reverse;
    if (canUseUpstream) {
      final result = _buffer.applyEdits(
        [ValidAnnotatedEditOperation(null, range, edit.text)],
        false,
        true,
      );
      reverse = result.reverseEdits!.single;
    } else {
      // applyEdits normalizes both inserted text and deleted text used for its
      // inverse on an unnormalized buffer. Raw piece-tree edits are necessary
      // to round-trip lone CR, LF/CRLF mixtures, and CRLF boundary changes.
      final tree = _buffer.getPieceTree();
      tree.delete(edit.start, edit.end - edit.start);
      if (edit.text.isNotEmpty) tree.insert(edit.start, edit.text);
      _buffer.refreshContentFlags();
    }
    _snapshot = DocumentSnapshot(_buffer.getValue());
    final inverseEnd = edit.start + edit.text.length;
    final reverseRange = reverse?.range;
    final usableReverse =
        reverse != null &&
        reverse.text == removed &&
        _snapshot.offsetAtPosition(reverseRange!.getStartPosition()) ==
            edit.start &&
        _snapshot.offsetAtPosition(reverseRange.getEndPosition()) == inverseEnd;
    return _OffsetEdit(
      edit.start,
      inverseEnd,
      removed,
      usableReverse ? reverseRange : null,
    );
  }

  void dispose() => _buffer.dispose();
}
