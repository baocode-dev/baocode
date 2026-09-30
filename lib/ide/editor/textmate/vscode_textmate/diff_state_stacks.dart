// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/diffStateStacks.ts (MIT, see LICENSE.md).

import 'grammar/grammar.dart';
import 'main.dart';

StackDiff diffStateStacksRefEq(StateStack first, StateStack second) {
  var pops = 0;
  final newFrames = <StateStackFrame>[];

  var curFirst = first as StateStackImpl?;
  var curSecond = second as StateStackImpl?;

  while (!identical(curFirst, curSecond)) {
    if (curFirst != null &&
        (curSecond == null || curFirst.depth >= curSecond.depth)) {
      // curFirst is certainly not contained in curSecond
      pops++;
      curFirst = curFirst.parent;
    } else {
      // curSecond is certainly not contained in curFirst.
      // Also, curSecond must be defined, as otherwise a previous case would match
      newFrames.add(curSecond!.toStateStackFrame());
      curSecond = curSecond.parent;
    }
  }
  return StackDiff(pops: pops, newFrames: newFrames.reversed.toList());
}

StateStackImpl? applyStateStackDiff(StateStack? stack, StackDiff diff) {
  var curStack = stack as StateStackImpl?;
  for (var i = 0; i < diff.pops; i++) {
    curStack = curStack!.parent;
  }
  for (final frame in diff.newFrames) {
    curStack = StateStackImpl.pushFrame(curStack, frame);
  }
  return curStack;
}

class StackDiff {
  const StackDiff({required this.pops, required this.newFrames});

  final int pops;
  final List<StateStackFrame> newFrames;
}
