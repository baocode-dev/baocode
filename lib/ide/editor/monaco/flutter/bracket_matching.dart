import '../vs/editor/common/languages/language_configuration.dart'
    show CharacterPair;
import 'document_snapshot.dart';

/// Default bracket pairs, like Monaco's fallback language configuration.
const List<CharacterPair> defaultBracketPairs = [
  ('(', ')'),
  ('[', ']'),
  ('{', '}'),
];

/// UTF-16 offsets of a matched bracket pair; each bracket spans its length.
typedef BracketMatch = ({int open, int openLength, int close, int closeLength});

/// Finds the bracket touching [offset] and its partner, like Monaco's legacy
/// `BracketPairsTextModelPart._matchBracket`: a bracket that ends or starts
/// at [offset] qualifies; when both do and both match, the one to the right
/// wins. Only brackets of the same pair are counted when searching.
///
/// Deviations: without standard token types, brackets inside strings and
/// comments are not ignored; the search is bounded by [maxLines] lines in
/// each direction instead of a time budget. Brackets may be multi-character.
BracketMatch? matchBracket(
  DocumentSnapshot snapshot,
  int offset, {
  List<CharacterPair> pairs = defaultBracketPairs,
  int maxLines = 2000,
}) {
  final text = snapshot.text;
  if (text.isEmpty || pairs.isEmpty) return null;
  offset = offset.clamp(0, text.length);
  final position = snapshot.positionAtOffset(offset);
  final line = position.lineNumber - 1;
  final lineStart = snapshot.lineStarts[line];
  final lineEnd = snapshot.contentEnds[line];
  if (offset > lineEnd) offset = lineEnd;

  BracketMatch? best;
  // Candidates start at or before the caret and end at or after it. Scan
  // left to right; a later (more right-side) successful match wins.
  var maxLength = 1;
  for (final (open, close) in pairs) {
    if (open.length > maxLength) maxLength = open.length;
    if (close.length > maxLength) maxLength = close.length;
  }
  final from = (offset - maxLength).clamp(lineStart, lineEnd);
  for (var start = from; start <= offset && start < lineEnd; start++) {
    for (final (open, close) in pairs) {
      if (open.isEmpty || close.isEmpty) continue;
      if (_matchesAt(text, start, open, lineEnd) &&
          start + open.length >= offset) {
        final partner = _searchForward(
          snapshot,
          start + open.length,
          open,
          close,
          (line + maxLines).clamp(0, snapshot.lineCount - 1),
        );
        if (partner != null) {
          best = (
            open: start,
            openLength: open.length,
            close: partner,
            closeLength: close.length,
          );
        }
      } else if (_matchesAt(text, start, close, lineEnd) &&
          start + close.length >= offset) {
        final partner = _searchBackward(
          snapshot,
          start,
          open,
          close,
          (line - maxLines).clamp(0, snapshot.lineCount - 1),
        );
        if (partner != null) {
          best = (
            open: partner,
            openLength: open.length,
            close: start,
            closeLength: close.length,
          );
        }
      }
    }
  }
  return best;
}

bool _matchesAt(String text, int offset, String token, int limit) {
  if (offset + token.length > limit) return false;
  for (var i = 0; i < token.length; i++) {
    if (text.codeUnitAt(offset + i) != token.codeUnitAt(i)) return false;
  }
  return true;
}

int? _searchForward(
  DocumentSnapshot snapshot,
  int from,
  String open,
  String close,
  int lastLine,
) {
  final text = snapshot.text;
  final limit = snapshot.contentEnds[lastLine];
  var depth = 1;
  for (var i = from; i < limit; i++) {
    if (_matchesAt(text, i, close, limit)) {
      if (--depth == 0) return i;
      i += close.length - 1;
    } else if (_matchesAt(text, i, open, limit)) {
      depth++;
      i += open.length - 1;
    }
  }
  return null;
}

int? _searchBackward(
  DocumentSnapshot snapshot,
  int before,
  String open,
  String close,
  int firstLine,
) {
  final text = snapshot.text;
  final limit = snapshot.lineStarts[firstLine];
  var depth = 1;
  for (var i = before - 1; i >= limit; i--) {
    final openStart = i - open.length + 1;
    final closeStart = i - close.length + 1;
    if (openStart >= limit && _matchesAt(text, openStart, open, before)) {
      if (--depth == 0) return openStart;
      i = openStart;
    } else if (closeStart >= limit &&
        _matchesAt(text, closeStart, close, before)) {
      depth++;
      i = closeStart;
    }
  }
  return null;
}
