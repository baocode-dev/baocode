import 'package:path/path.dart' as p;

import 'package:bao_editor/monaco/flutter/document_snapshot.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';

import '../lsp/lsp_protocol.dart';

/// The absolute path of a `file:` [uri] (other schemes: null).
String? lspPathOfUri(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return null;
  if (parsed.scheme.isEmpty) return p.normalize(uri);
  if (parsed.scheme != 'file') return null;
  try {
    return p.normalize(parsed.toFilePath());
  } on UnsupportedError {
    return null;
  }
}

/// The `file:` URI of an absolute [path].
String lspUriOfPath(String path) => Uri.file(path).toString();

/// The protocol position (zero-based, UTF-16) of [offset] in [snapshot].
LspPosition lspPositionAt(DocumentSnapshot snapshot, int offset) {
  final position = snapshot.positionAtOffset(
    offset.clamp(0, snapshot.text.length),
  );
  return LspPosition(position.lineNumber - 1, position.column - 1);
}

/// The offset of a protocol [position] in [snapshot], clamped to its line;
/// a line past the last one is the end of the document.
int lspOffsetOf(DocumentSnapshot snapshot, LspPosition position) {
  if (position.line >= snapshot.lineCount) return snapshot.text.length;
  return snapshot.offsetAtPosition(
    Position(
      position.line < 0 ? 1 : position.line + 1,
      position.character < 0 ? 1 : position.character + 1,
    ),
  );
}

/// `(start, end)` offsets of a protocol [range], ordered.
(int, int) lspOffsetsOf(DocumentSnapshot snapshot, LspRange range) {
  final start = lspOffsetOf(snapshot, range.start);
  final end = lspOffsetOf(snapshot, range.end);
  return start <= end ? (start, end) : (end, start);
}

/// The protocol range of `[start, end)` in [snapshot].
LspRange lspRangeOf(DocumentSnapshot snapshot, int start, int end) =>
    LspRange(lspPositionAt(snapshot, start), lspPositionAt(snapshot, end));

/// Text edits as disjoint offset edits against [snapshot], in document order;
/// null when two of them overlap (the protocol forbids it).
List<EditorOffsetEdit>? lspOffsetEdits(
  DocumentSnapshot snapshot,
  List<LspTextEdit> edits,
) {
  final indexed = [
    for (final (index, edit) in edits.indexed)
      (index, lspOffsetsOf(snapshot, edit.range), edit.newText),
  ];
  // Same-position inserts keep their given order (the protocol says so).
  indexed.sort((a, b) {
    final start = a.$2.$1.compareTo(b.$2.$1);
    if (start != 0) return start;
    final end = a.$2.$2.compareTo(b.$2.$2);
    return end != 0 ? end : a.$1.compareTo(b.$1);
  });
  final result = <EditorOffsetEdit>[];
  for (final (_, (start, end), text) in indexed) {
    if (result.isNotEmpty) {
      final last = result.last;
      if (start < last.end) return null;
      if (start == last.start && end == last.end && start == end) {
        // Two inserts at one point: merge so the model sees one edit.
        result[result.length - 1] = EditorOffsetEdit(
          start,
          end,
          last.text + text,
        );
        continue;
      }
    }
    result.add(EditorOffsetEdit(start, end, text));
  }
  return result;
}

/// A place in a file, as navigation targets and panels use it.
class IdeLocation {
  const IdeLocation(this.path, this.range);

  /// The `file:` target of [location]; null for other schemes.
  static IdeLocation? of(LspLocation location) {
    final path = lspPathOfUri(location.uri);
    return path == null ? null : IdeLocation(path, location.revealRange);
  }

  final String path;
  final LspRange range;

  @override
  bool operator ==(Object other) =>
      other is IdeLocation && other.path == path && other.range == range;

  @override
  int get hashCode => Object.hash(path, range);

  @override
  String toString() => '$path$range';
}

const _wordSeparators =
    r'`~!@#$%^&*()-=+[{]}\|;:'
    "'"
    r'",.<>/?';

/// Whether [unit] belongs to a word under Monaco's default word definition
/// (anything but whitespace and `` `~!@#$%^&*()-=+[{]}\|;:'",.<>/? ``).
bool lspIsWordUnit(int unit) =>
    unit != 0x20 &&
    unit != 0x09 &&
    unit != 0x0A &&
    unit != 0x0D &&
    !_wordSeparators.codeUnits.contains(unit);

/// The word around [offset] as `(start, end)` (empty at a non-word spot).
(int, int) lspWordAt(DocumentSnapshot snapshot, int offset) {
  final text = snapshot.text;
  final line = snapshot.positionAtOffset(offset).lineNumber - 1;
  final lineStart = snapshot.lineStarts[line];
  final lineEnd = snapshot.contentEnds[line];
  var start = offset.clamp(lineStart, lineEnd);
  var end = start;
  while (start > lineStart && lspIsWordUnit(text.codeUnitAt(start - 1))) {
    start--;
  }
  while (end < lineEnd && lspIsWordUnit(text.codeUnitAt(end))) {
    end++;
  }
  return (start, end);
}
