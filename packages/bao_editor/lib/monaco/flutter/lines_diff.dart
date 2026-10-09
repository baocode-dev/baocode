// Where a lines diff is computed: VS Code computes it in its editor worker
// (src/vs/editor/browser/services/editorWorkerService.ts), off the window's
// thread; here, past a few thousand characters, on another isolate.
//
// Its cost is that of what changed, not of the length: the inner changes of
// a block of changed lines are found character by character, so a 50-line
// file changed throughout takes longer than a frame, and a 1000-line one
// its whole time limit.

import 'dart:isolate';

import '../vs/editor/common/diff/default_lines_diff_computer/default_lines_diff_computer.dart';

/// At most this many characters on both sides together are compared on the
/// caller's isolate: the longest that takes, changed throughout, is a few
/// milliseconds.
const linesDiffInlineCharacters = 2000;

/// Whether [original] and [modified] are small enough to compare on the
/// caller's isolate ([linesDiffInlineCharacters]).
bool isSmallLinesDiff(List<String> original, List<String> modified) {
  var characters = 0;
  for (final lines in [original, modified]) {
    for (final line in lines) {
      // And its line break.
      characters += line.length + 1;
      if (characters > linesDiffInlineCharacters) return false;
    }
  }
  return true;
}

/// `computeDiff` of [original] and [modified] on another isolate, from a
/// closure that holds the lines and the options only.
Future<LinesDiff> computeLinesDiffOnIsolate(
  List<String> original,
  List<String> modified,
  LinesDiffComputerOptions options,
) => Isolate.run(
  () => DefaultLinesDiffComputer().computeDiff(original, modified, options),
);
