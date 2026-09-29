import '../vs/editor/common/core/position.dart';

/// Immutable UTF-16 line geometry for a Flutter text value.
///
/// Line arrays are zero-indexed; [Position] uses one-based line numbers and
/// columns. A CRLF is one newline of length two, while lone CR and LF are each
/// one newline. A final newline creates an empty trailing line.
class DocumentSnapshot {
  factory DocumentSnapshot(String text) {
    final starts = <int>[0];
    final ends = <int>[];
    final newlineLengths = <int>[];

    var offset = 0;
    while (offset < text.length) {
      final unit = text.codeUnitAt(offset);
      if (unit == 0x0D || unit == 0x0A) {
        final length =
            unit == 0x0D &&
                offset + 1 < text.length &&
                text.codeUnitAt(offset + 1) == 0x0A
            ? 2
            : 1;
        ends.add(offset);
        newlineLengths.add(length);
        offset += length;
        starts.add(offset);
      } else {
        offset++;
      }
    }
    ends.add(text.length);
    newlineLengths.add(0);

    return DocumentSnapshot._(
      text,
      List<int>.unmodifiable(starts),
      List<int>.unmodifiable(ends),
      List<int>.unmodifiable(newlineLengths),
    );
  }

  const DocumentSnapshot._(
    this.text,
    this.lineStarts,
    this.contentEnds,
    this.newlineLengths,
  );

  final String text;

  /// UTF-16 offsets of the first code unit on each line.
  final List<int> lineStarts;

  /// Exclusive UTF-16 end of each line's content, before its newline.
  final List<int> contentEnds;

  /// Number of newline code units after each line (0 on the final line).
  final List<int> newlineLengths;

  int get lineCount => lineStarts.length;

  /// Returns the one-based position at [offset], clamped to the document.
  ///
  /// An offset between CR and LF maps to the preceding line's end column.
  /// The binary search takes O(log lineCount) time.
  Position positionAtOffset(int offset) {
    final clamped = offset < 0
        ? 0
        : (offset > text.length ? text.length : offset);
    var low = 0;
    var high = lineCount;
    while (low < high) {
      final middle = low + ((high - low) ~/ 2);
      if (lineStarts[middle] <= clamped) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    final line = low - 1;
    final columnOffset = clamped > contentEnds[line]
        ? contentEnds[line]
        : clamped;
    return Position(line + 1, columnOffset - lineStarts[line] + 1);
  }

  /// Returns the UTF-16 offset of [position], clamping lines and columns.
  ///
  /// Columns count code units (including both halves of a surrogate pair) and
  /// stop at the content end, never inside a newline.
  int offsetAtPosition(IPosition position) {
    final line = position.lineNumber <= 1
        ? 0
        : (position.lineNumber >= lineCount
              ? lineCount - 1
              : position.lineNumber - 1);
    final start = lineStarts[line];
    final end = contentEnds[line];
    if (position.column <= 1) return start;
    if (position.column >= end - start + 1) return end;
    return start + position.column - 1;
  }
}
