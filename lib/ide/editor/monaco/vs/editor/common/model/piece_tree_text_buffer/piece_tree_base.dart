/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Port of VS Code src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// Search (findMatchesInNode/findMatchesLineByLine/_findMatchesInLine) is not
// ported: those APIs require textModelSearch's Searcher, SearchData and FindMatch.
// Cursor-based pieces share the upstream append-only change buffer; their
// line metadata derives from the underlying buffer's line-start index.
import '../../core/position.dart';
import '../../core/range.dart';
import 'rb_tree_base.dart';

const int averageBufferSize = 65535;

List<int> createLineStartsFast(String str, [bool readonly = true]) {
  final result = <int>[0];
  for (var i = 0; i < str.length; i++) {
    final c = str.codeUnitAt(i);
    if (c == 13) {
      if (i + 1 < str.length && str.codeUnitAt(i + 1) == 10) i++;
      result.add(i + 1);
    } else if (c == 10) {
      result.add(i + 1);
    }
  }
  return result;
}

class LineStarts {
  LineStarts(this.lineStarts, this.cr, this.lf, this.crlf, this.isBasicASCII);
  final List<int> lineStarts;
  final int cr;
  final int lf;
  final int crlf;
  final bool isBasicASCII;
}

LineStarts createLineStarts(List<int> scratch, String str) {
  scratch.clear();
  scratch.add(0);
  var cr = 0;
  var lf = 0;
  var crlf = 0;
  var ascii = true;
  for (var i = 0; i < str.length; i++) {
    final c = str.codeUnitAt(i);
    if (c == 13) {
      if (i + 1 < str.length && str.codeUnitAt(i + 1) == 10) {
        crlf++;
        i++;
      } else {
        cr++;
      }
      scratch.add(i + 1);
    } else if (c == 10) {
      lf++;
      scratch.add(i + 1);
    } else if (c != 9 && (c < 32 || c > 126)) {
      ascii = false;
    }
  }
  final result = LineStarts(List<int>.of(scratch), cr, lf, crlf, ascii);
  scratch.clear();
  return result;
}

class BufferCursor {
  const BufferCursor(this.line, this.column);
  final int line;
  final int column;
}

class Piece {
  Piece(
    this.bufferIndex,
    this.start,
    this.end,
    this.lineFeedCnt,
    this.length, [
    List<int>? lineStarts,
    this.backingBuffer,
  ]) : _lineStarts = lineStarts;

  final int bufferIndex;
  final BufferCursor start;
  final BufferCursor end;
  final int lineFeedCnt;
  final int length;
  // Retained for Dart callers inspecting pieces. Internal navigation uses
  // buffer cursors directly: slicing a long piece does not re-scan its text.
  final StringBuffer? backingBuffer;
  List<int>? _lineStarts;
  List<int> get lineStarts => _lineStarts ??= createLineStartsFast(
    backingBuffer!.buffer.substring(
      backingBuffer!.lineStarts[start.line] + start.column,
      backingBuffer!.lineStarts[start.line] + start.column + length,
    ),
  );
}

class StringBuffer {
  StringBuffer(this.buffer, this.lineStarts);
  String buffer;
  List<int> lineStarts;
}

class NodePosition {
  const NodePosition(this.node, this.remainder, this.nodeStartOffset);
  final TreeNode node;
  final int remainder;
  final int nodeStartOffset;
}

class _CacheEntry {
  _CacheEntry(this.node, this.nodeStartOffset);
  final TreeNode node;
  final int nodeStartOffset;
}

// As in upstream, the most recently visited node is retained for repeated
// cursor operations and invalidated when edits shift offsets or detach nodes.
class _PieceTreeSearchCache {
  _CacheEntry? _entry;

  NodePosition? get(int offset) {
    final hit = _entry;
    if (hit == null ||
        hit.node.isDetached ||
        offset < hit.nodeStartOffset ||
        offset > hit.nodeStartOffset + hit.node.piece!.length) {
      return null;
    }
    return NodePosition(
      hit.node,
      offset - hit.nodeStartOffset,
      hit.nodeStartOffset,
    );
  }

  void set(TreeNode node, int start) => _entry = _CacheEntry(node, start);

  void validate(int offset) {
    final hit = _entry;
    if (hit != null && (hit.node.isDetached || hit.nodeStartOffset >= offset)) {
      _entry = null;
    }
  }
}

/// A snapshot holds the piece strings, not live nodes (edits may delete nodes).
class PieceTreeSnapshot {
  PieceTreeSnapshot(this._chunks);
  final List<String> _chunks;
  int _index = 0;

  String? read() => _index < _chunks.length ? _chunks[_index++] : null;
}

class PieceTreeBase {
  PieceTreeBase(List<StringBuffer> chunks, String eol, bool eolNormalized) {
    create(chunks, eol, eolNormalized);
  }

  TreeNode root = sentinel;
  late List<StringBuffer> _buffers;
  late int _lineCnt;
  late int _length;
  late String _eol;
  late bool _eolNormalized;
  late BufferCursor _lastChangeBufferPos;
  late _PieceTreeSearchCache _searchCache;
  int _lastVisitedLineNumber = 0;
  String _lastVisitedLineValue = '';

  void create(List<StringBuffer> chunks, String eol, bool eolNormalized) {
    if (eol != '\n' && eol != '\r\n') {
      throw ArgumentError.value(eol, 'eol', 'Expected LF or CRLF');
    }
    _buffers = [
      StringBuffer('', [0]),
    ];
    _lastChangeBufferPos = const BufferCursor(0, 0);
    _searchCache = _PieceTreeSearchCache();
    _lastVisitedLineNumber = 0;
    _lastVisitedLineValue = '';
    root = sentinel;
    _lineCnt = 1;
    _length = 0;
    _eol = eol;
    _eolNormalized = eolNormalized;
    TreeNode? last;
    for (final chunk in chunks) {
      if (chunk.buffer.isEmpty) continue;
      // The supplied line starts can be computed by callers, or omitted.
      final starts = chunk.lineStarts.isEmpty
          ? createLineStartsFast(chunk.buffer)
          : chunk.lineStarts;
      _buffers.add(StringBuffer(chunk.buffer, starts));
      last = _rbInsertRight(
        last,
        _makePiece(_buffers.length - 1, 0, chunk.buffer.length),
      );
    }
    _computeBufferMetadata();
    // Original chunks can end between CR and LF. Normalize that boundary
    // without flattening or changing the document text.
    final boundaries = <int>[];
    var offset = 0;
    var node = identical(root, sentinel) ? sentinel : leftest(root);
    while (!identical(node, sentinel)) {
      offset += node.piece!.length;
      if (!identical(node.next(), sentinel)) boundaries.add(offset - 1);
      node = node.next();
    }
    for (final boundary in boundaries) {
      _repairAt(boundary);
      _computeBufferMetadata();
    }
  }

  int _offsetInBuffer(int index, BufferCursor cursor) =>
      _buffers[index].lineStarts[cursor.line] + cursor.column;

  BufferCursor _cursorAt(int index, int offset) {
    final starts = _buffers[index].lineStarts;
    var lo = 0;
    var hi = starts.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (starts[mid] <= offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final line = lo - 1;
    return BufferCursor(line, offset - starts[line]);
  }

  // Source's getLineFeedCnt accounts for a cursor placed *between* CR and LF
  // in an existing buffer: the CR still belongs to the preceding piece.
  int _getLineFeedCnt(int index, BufferCursor start, BufferCursor end) {
    if (end.column == 0) return end.line - start.line;
    final starts = _buffers[index].lineStarts;
    if (end.line == starts.length - 1) return end.line - start.line;
    final endOffset = starts[end.line] + end.column;
    if (starts[end.line + 1] == endOffset + 1 &&
        _buffers[index].buffer.codeUnitAt(endOffset - 1) == 13) {
      return end.line - start.line + 1;
    }
    return end.line - start.line;
  }

  Piece _makePiece(int index, int start, int end) {
    final first = _cursorAt(index, start);
    final last = _cursorAt(index, end);
    return Piece(
      index,
      first,
      last,
      _getLineFeedCnt(index, first, last),
      end - start,
      null,
      _buffers[index],
    );
  }

  Piece _slice(Piece piece, int start, int end) {
    final base = _offsetInBuffer(piece.bufferIndex, piece.start);
    return _makePiece(piece.bufferIndex, base + start, base + end);
  }

  void _replace(TreeNode node, Piece piece) {
    final old = node.piece!;
    node.piece = piece;
    updateTreeMetadata(
      this,
      node,
      piece.length - old.length,
      piece.lineFeedCnt - old.lineFeedCnt,
    );
  }

  TreeNode _rbInsertRight(TreeNode? node, Piece piece) {
    final z = TreeNode(piece, NodeColor.red);
    if (identical(root, sentinel)) {
      root = z;
      z.color = NodeColor.black;
    } else if (identical(node!.right, sentinel)) {
      node.right = z;
      z.parent = node;
    } else {
      final next = leftest(node.right);
      next.left = z;
      z.parent = next;
    }
    fixInsert(this, z);
    return z;
  }

  TreeNode _rbInsertLeft(TreeNode? node, Piece piece) {
    final z = TreeNode(piece, NodeColor.red);
    if (identical(root, sentinel)) {
      root = z;
      z.color = NodeColor.black;
    } else if (identical(node!.left, sentinel)) {
      node.left = z;
      z.parent = node;
    } else {
      final prev = righttest(node.left);
      prev.right = z;
      z.parent = prev;
    }
    fixInsert(this, z);
    return z;
  }

  /// Locate by UTF-16 offset; boundaries belong to the piece on the left.
  NodePosition? nodeAt(int offset) {
    if (offset < 0 || offset > _length) return null;
    final cached = _searchCache.get(offset);
    if (cached != null) return cached;
    var x = root;
    var start = 0;
    var remaining = offset;
    while (!identical(x, sentinel)) {
      if (x.sizeLeft > remaining) {
        x = x.left;
      } else if (x.sizeLeft + x.piece!.length >= remaining) {
        start += x.sizeLeft;
        _searchCache.set(x, start);
        return NodePosition(x, remaining - x.sizeLeft, start);
      } else {
        remaining -= x.sizeLeft + x.piece!.length;
        start += x.sizeLeft + x.piece!.length;
        x = x.right;
      }
    }
    return null;
  }

  List<Piece> _newPieces(String text) {
    // Large inserts get immutable chunks; the final short chunk follows the
    // original implementation's append-only change-buffer path.
    if (text.length > averageBufferSize) {
      final pieces = <Piece>[];
      while (text.isNotEmpty) {
        var end = text.length < averageBufferSize
            ? text.length
            : averageBufferSize;
        if (end < text.length) {
          final last = text.codeUnitAt(end - 1);
          if (last == 13 || (last >= 0xd800 && last <= 0xdbff)) end--;
        }
        final chunk = text.substring(0, end);
        _buffers.add(StringBuffer(chunk, createLineStartsFast(chunk)));
        pieces.add(_makePiece(_buffers.length - 1, 0, chunk.length));
        text = text.substring(end);
      }
      return pieces;
    }

    final buffer = _buffers[0];
    var startOffset = buffer.buffer.length;
    final starts = createLineStartsFast(text);
    var start = _lastChangeBufferPos;
    if (buffer.lineStarts.last == startOffset &&
        startOffset != 0 &&
        text.codeUnitAt(0) == 10 &&
        buffer.buffer.codeUnitAt(startOffset - 1) == 13) {
      // The new LF must not retroactively change existing buffer cursors.
      // Like upstream, place a never-referenced placeholder before the LF.
      start = BufferCursor(start.line, start.column + 1);
      _lastChangeBufferPos = start;
      for (var i = 0; i < starts.length; i++) {
        starts[i] += startOffset + 1;
      }
      buffer.lineStarts.addAll(starts.skip(1));
      buffer.buffer += '_$text';
      startOffset++;
    } else {
      for (var i = 0; i < starts.length; i++) {
        starts[i] += startOffset;
      }
      buffer.lineStarts.addAll(starts.skip(1));
      buffer.buffer += text;
    }
    final endOffset = buffer.buffer.length;
    final end = BufferCursor(
      buffer.lineStarts.length - 1,
      endOffset - buffer.lineStarts.last,
    );
    final piece = Piece(
      0,
      start,
      end,
      _getLineFeedCnt(0, start, end),
      endOffset - startOffset,
      null,
      buffer,
    );
    _lastChangeBufferPos = end;
    return [piece];
  }

  // Source's appendToNode fast path: repeated typing extends the most recent
  // change-buffer piece instead of inserting a new red-black node every time.
  void _appendToNode(TreeNode node, String text) {
    final buffer = _buffers[0];
    final old = node.piece!;
    final offset = buffer.buffer.length;
    final hitCRLF =
        old.length > 0 &&
        text.codeUnitAt(0) == 10 &&
        buffer.buffer.codeUnitAt(offset - 1) == 13;
    buffer.buffer += text;
    final starts = createLineStartsFast(text);
    for (var i = 0; i < starts.length; i++) {
      starts[i] += offset;
    }
    if (hitCRLF) buffer.lineStarts.removeLast();
    buffer.lineStarts.addAll(starts.skip(1));
    final end = BufferCursor(
      buffer.lineStarts.length - 1,
      buffer.buffer.length - buffer.lineStarts.last,
    );
    final piece = Piece(
      0,
      old.start,
      end,
      _getLineFeedCnt(0, old.start, end),
      old.length + text.length,
      null,
      buffer,
    );
    _replace(node, piece);
    _lastChangeBufferPos = end;
  }

  // Repair a CR at the end of one piece followed by LF in the next. Keeping
  // both characters in one piece makes each piece's LF count additive.
  void _repairAt(int crOffset) {
    if (crOffset < 0 || crOffset + 1 >= _length) return;
    final pos = nodeAt(crOffset);
    if (pos == null) return;
    var prev = pos.node;
    var remainder = pos.remainder;
    if (remainder == prev.piece!.length) {
      prev = prev.next();
      remainder = 0;
    }
    // The CR and LF are already in the same piece, or this is not a boundary.
    if (identical(prev, sentinel) || remainder != prev.piece!.length - 1) {
      return;
    }
    final next = prev.next();
    if (identical(next, sentinel) ||
        !getPieceContent(prev.piece!).endsWith('\r') ||
        !getPieceContent(next.piece!).startsWith('\n')) {
      return;
    }
    final before = prev.piece!;
    final after = next.piece!;
    _replace(prev, _slice(before, 0, before.length - 1));
    _replace(next, _slice(after, 1, after.length));
    final joined = _newPieces('\r\n').single;
    _rbInsertRight(prev, joined);
    if (prev.piece!.length == 0) rbDelete(this, prev);
    if (next.piece!.length == 0) rbDelete(this, next);
  }

  // Splits at an offset if needed; the returned node starts there, or is the
  // sentinel at EOF. Empty split pieces are never retained.
  TreeNode _split(int offset) {
    if (offset == _length) return sentinel;
    final at = nodeAt(offset)!;
    final node = at.node;
    if (at.remainder == 0) return node;
    if (at.remainder == node.piece!.length) return node.next();
    final old = node.piece!;
    _replace(node, _slice(old, 0, at.remainder));
    return _rbInsertRight(node, _slice(old, at.remainder, old.length));
  }

  void insert(int offset, String value, [bool eolNormalized = false]) {
    if (offset < 0 || offset > _length) {
      throw RangeError.range(offset, 0, _length);
    }
    if (value.isEmpty) return;
    _eolNormalized = _eolNormalized && eolNormalized;
    _lastVisitedLineNumber = 0;
    _searchCache.validate(offset);
    final hit = nodeAt(offset);
    if (hit != null &&
        hit.node.piece!.bufferIndex == 0 &&
        hit.node.piece!.end.line == _lastChangeBufferPos.line &&
        hit.node.piece!.end.column == _lastChangeBufferPos.column &&
        hit.nodeStartOffset + hit.node.piece!.length == offset &&
        value.length < averageBufferSize) {
      _appendToNode(hit.node, value);
      _computeBufferMetadata();
      _searchCache.validate(offset);
      _repairAt(offset - 1);
      _repairAt(offset + value.length - 1);
      _computeBufferMetadata();
      _searchCache.validate(offset);
      return;
    }
    final next = _split(offset);
    TreeNode? prev = identical(next, sentinel)
        ? (identical(root, sentinel) ? null : righttest(root))
        : next.prev();
    if (identical(prev, sentinel)) prev = null;
    for (final piece in _newPieces(value)) {
      prev = prev == null && !identical(root, sentinel)
          ? _rbInsertLeft(next, piece)
          : _rbInsertRight(prev, piece);
    }
    _computeBufferMetadata();
    _searchCache.validate(offset);
    _repairAt(offset - 1);
    _repairAt(offset + value.length - 1);
    _computeBufferMetadata();
    _searchCache.validate(offset);
  }

  void delete(int offset, int count) {
    if (count <= 0) return;
    if (offset < 0 || offset + count > _length) {
      throw RangeError.range(offset + count, 0, _length);
    }
    _lastVisitedLineNumber = 0;
    _searchCache.validate(offset);
    final end = _split(offset + count);
    var current = _split(offset);
    while (!identical(current, end)) {
      final next = current.next();
      rbDelete(this, current);
      current = next;
    }
    _computeBufferMetadata();
    _searchCache.validate(offset);
    _repairAt(offset - 1);
    _computeBufferMetadata();
    _searchCache.validate(offset);
  }

  void _computeBufferMetadata() {
    var node = root;
    var length = 0;
    var lines = 1;
    while (!identical(node, sentinel)) {
      length += node.sizeLeft + node.piece!.length;
      lines += node.lfLeft + node.piece!.lineFeedCnt;
      node = node.right;
    }
    _length = length;
    _lineCnt = lines;
    _searchCache.validate(_length);
  }

  int getLength() => _length;
  int getLineCount() => _lineCnt;
  String getEOL() => _eol;

  void normalizeEOL(String eol) {
    if (eol != '\n' && eol != '\r\n') throw ArgumentError.value(eol, 'eol');
    final text = getLinesRawContent().replaceAll(RegExp(r'\r\n|\r|\n'), eol);
    final chunks = <StringBuffer>[];
    var start = 0;
    while (start < text.length) {
      var end = start + averageBufferSize;
      if (end >= text.length) end = text.length;
      if (end < text.length) {
        final last = text.codeUnitAt(end - 1);
        if (last == 13 || (last >= 0xd800 && last <= 0xdbff)) end--;
      }
      final chunk = text.substring(start, end);
      chunks.add(StringBuffer(chunk, createLineStartsFast(chunk)));
      start = end;
    }
    create(chunks, eol, true);
  }

  void setEOL(String eol) => normalizeEOL(eol);

  // Mirrors upstream's getAccumulatedValue: line starts are held once per
  // backing buffer and pieces carry only a pair of cursors into that buffer.
  int _getAccumulatedValue(Piece piece, int index) {
    if (index < 0) return 0;
    final starts = _buffers[piece.bufferIndex].lineStarts;
    final expected = piece.start.line + index + 1;
    if (expected > piece.end.line) return piece.length;
    return starts[expected] - starts[piece.start.line] - piece.start.column;
  }

  // The nth break ends at this offset. Tree metadata gives logarithmic node
  // navigation, while shared buffer lineStarts gives constant-time local lookup.
  int _afterBreak(int n) {
    if (n == 0) return 0;
    var node = root;
    var offset = 0;
    while (!identical(node, sentinel)) {
      if (n <= node.lfLeft) {
        node = node.left;
      } else {
        offset += node.sizeLeft;
        n -= node.lfLeft;
        if (n <= node.piece!.lineFeedCnt) {
          return offset + _getAccumulatedValue(node.piece!, n - 1);
        }
        n -= node.piece!.lineFeedCnt;
        offset += node.piece!.length;
        node = node.right;
      }
    }
    return _length;
  }

  int getOffsetAt(int lineNumber, int column) {
    if (lineNumber <= 1) return column - 1;
    if (lineNumber > _lineCnt) return _length;
    return _afterBreak(lineNumber - 1) + column - 1;
  }

  Position getPositionAt(int offset) {
    offset = offset.clamp(0, _length);
    var node = root;
    var remaining = offset;
    var breaks = 0;
    while (!identical(node, sentinel)) {
      if (remaining < node.sizeLeft) {
        node = node.left;
      } else {
        remaining -= node.sizeLeft;
        breaks += node.lfLeft;
        if (remaining <= node.piece!.length) {
          final piece = node.piece!;
          final start = _offsetInBuffer(piece.bufferIndex, piece.start);
          final cursor = _cursorAt(piece.bufferIndex, start + remaining);
          var inPiece = cursor.line - piece.start.line;
          if (remaining == piece.length) {
            inPiece = _getLineFeedCnt(piece.bufferIndex, piece.start, cursor);
          }
          breaks += inPiece;
          final lineNumber = breaks + 1;
          return Position(lineNumber, offset - _afterBreak(breaks) + 1);
        }
        remaining -= node.piece!.length;
        breaks += node.piece!.lineFeedCnt;
        node = node.right;
      }
    }
    return Position(1, 1);
  }

  String getPieceContent(Piece piece) {
    final start = _offsetInBuffer(piece.bufferIndex, piece.start);
    return _buffers[piece.bufferIndex].buffer.substring(
      start,
      start + piece.length,
    );
  }

  bool iterate(TreeNode node, bool Function(TreeNode) callback) {
    if (identical(node, sentinel)) return callback(sentinel);
    if (!iterate(node.left, callback)) return false;
    return callback(node) && iterate(node.right, callback);
  }

  String getLinesRawContent() {
    final result = StringBufferSink();
    iterate(root, (node) {
      if (!identical(node, sentinel)) {
        result.write(getPieceContent(node.piece!));
      }
      return true;
    });
    return result.toString();
  }

  // The sink is distinct from this module's StringBuffer (an upstream chunk).
  String _getText(int start, int end) {
    if (start >= end) return '';
    final at = nodeAt(start)!;
    var node = at.node;
    var remaining = end - start;
    var inside = at.remainder;
    final result = StringBufferSink();
    while (remaining > 0 && !identical(node, sentinel)) {
      final piece = node.piece!;
      final len = (piece.length - inside).clamp(0, remaining);
      if (len > 0) {
        result.write(getPieceContent(piece).substring(inside, inside + len));
      }
      remaining -= len;
      inside = 0;
      node = node.next();
    }
    return result.toString();
  }

  String getValueInRange2(NodePosition start, NodePosition end) => _getText(
    start.nodeStartOffset + start.remainder,
    end.nodeStartOffset + end.remainder,
  );

  String getValueInRange(Range range, [String? eol]) {
    final start = getOffsetAt(range.startLineNumber, range.startColumn);
    final end = getOffsetAt(range.endLineNumber, range.endColumn);
    final value = _getText(start.clamp(0, _length), end.clamp(0, _length));
    return eol != null && (eol != _eol || !_eolNormalized)
        ? value.replaceAll(RegExp(r'\r\n|\r|\n'), eol)
        : value;
  }

  String getLineRawContent(int lineNumber, [int endOffset = 0]) {
    if (lineNumber < 1 || lineNumber > _lineCnt) return '';
    final start = _afterBreak(lineNumber - 1);
    final end = lineNumber == _lineCnt ? _length : _afterBreak(lineNumber);
    return _getText(start, (end - endOffset).clamp(start, end));
  }

  String getLineContent(int lineNumber) {
    if (_lastVisitedLineNumber == lineNumber) return _lastVisitedLineValue;
    _lastVisitedLineNumber = lineNumber;
    return _lastVisitedLineValue = getLineRawContent(lineNumber)
        .replaceFirst(RegExp(r'\r\n$|\r$|\n$'), '');
  }

  List<String> getLinesContent() =>
      List<String>.generate(_lineCnt, (i) => getLineContent(i + 1));

  int getLineLength(int lineNumber) => getLineContent(lineNumber).length;

  int getCharCode(int offset) {
    if (offset < 0 || offset >= _length) return -1;
    final at = nodeAt(offset)!;
    var node = at.node;
    var inside = at.remainder;
    if (inside == node.piece!.length) {
      node = node.next();
      inside = 0;
    }
    return identical(node, sentinel)
        ? -1
        : _buffers[node.piece!.bufferIndex].buffer.codeUnitAt(
            _offsetInBuffer(node.piece!.bufferIndex, node.piece!.start) +
                inside,
          );
  }

  int getLineCharCode(int lineNumber, int index) =>
      getCharCode(getOffsetAt(lineNumber, index + 1));

  String getNearestChunk(int offset) {
    if (offset < 0 || offset >= _length) return '';
    final at = nodeAt(offset)!;
    final node = at.remainder == at.node.piece!.length
        ? at.node.next()
        : at.node;
    if (identical(node, sentinel)) return '';
    return getPieceContent(node.piece!)
        .substring(identical(node, at.node) ? at.remainder : 0);
  }

  PieceTreeSnapshot createSnapshot(String bom) {
    final chunks = <String>[];
    iterate(root, (node) {
      if (!identical(node, sentinel)) chunks.add(getPieceContent(node.piece!));
      return true;
    });
    if (chunks.isEmpty) chunks.add('');
    chunks[0] = bom + chunks[0];
    return PieceTreeSnapshot(chunks);
  }

  bool equal(PieceTreeBase other) =>
      getLength() == other.getLength() &&
      getLineCount() == other.getLineCount() &&
      getLinesRawContent() == other.getLinesRawContent();
}

// Avoid clashing with VS Code's StringBuffer chunk class.
class StringBufferSink {
  final List<String> _parts = [];
  void write(String value) => _parts.add(value);
  @override
  String toString() => _parts.join();
}
