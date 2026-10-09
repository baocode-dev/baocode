import 'dart:isolate';

import 'package:bao_editor/monaco/flutter/lines_diff.dart';
import 'package:bao_editor/monaco/vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';

import '../chat_models.dart' show DiffLineType;

/// One line of a file's diff as the side panel shows it: the whole file,
/// the lines removed before those added in their place.
class FileDiffRow {
  const FileDiffRow(this.type, this.text, {this.original, this.modified});

  final DiffLineType type;
  final String text;

  /// Its number (from 1) in the text before, and in the text now; null on
  /// the side it is not in.
  final int? original;
  final int? modified;
}

/// [text]'s lines, a last line break ending the last rather than starting
/// another.
List<String> diffLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.last.isEmpty) lines.removeLast();
  return [
    for (final line in lines)
      line.endsWith('\r') ? line.substring(0, line.length - 1) : line,
  ];
}

/// [fileDiff] off the caller's isolate unless the texts are small
/// ([linesDiffInlineCharacters]): what changed throughout takes seconds to compare,
/// however short the file.
Future<List<FileDiffRow>> fileDiffAsync(String original, String modified) {
  if (original.length + modified.length <= linesDiffInlineCharacters) {
    return Future.value(fileDiff(original, modified));
  }
  return Isolate.run(() => fileDiff(original, modified));
}

/// [original] to [modified], line by line (as the IDE's diff editor finds
/// it), every line of both.
List<FileDiffRow> fileDiff(String original, String modified) {
  final before = diffLines(original);
  final after = diffLines(modified);
  final rows = <FileDiffRow>[];
  var o = 1, m = 1;
  void context(int untilModified) {
    while (m < untilModified && m <= after.length) {
      rows.add(
        FileDiffRow(
          DiffLineType.context,
          after[m - 1],
          original: o,
          modified: m,
        ),
      );
      o++;
      m++;
    }
  }

  if (before.isNotEmpty && after.isNotEmpty) {
    final diff = DefaultLinesDiffComputer().computeDiff(
      before,
      after,
      const LinesDiffComputerOptions(maxComputationTimeMs: 3000),
    );
    for (final change in diff.changes) {
      context(change.modified.startLineNumber);
      o = change.original.startLineNumber;
      for (var i = o; i < change.original.endLineNumberExclusive; i++) {
        rows.add(FileDiffRow(DiffLineType.removed, before[i - 1], original: i));
      }
      for (
        var i = change.modified.startLineNumber;
        i < change.modified.endLineNumberExclusive;
        i++
      ) {
        rows.add(FileDiffRow(DiffLineType.added, after[i - 1], modified: i));
      }
      o = change.original.endLineNumberExclusive;
      m = change.modified.endLineNumberExclusive;
    }
    context(after.length + 1);
    return rows;
  }
  // All of one replaced by the other (added or deleted).
  for (final (i, line) in before.indexed) {
    rows.add(FileDiffRow(DiffLineType.removed, line, original: i + 1));
  }
  for (final (i, line) in after.indexed) {
    rows.add(FileDiffRow(DiffLineType.added, line, modified: i + 1));
  }
  return rows;
}
