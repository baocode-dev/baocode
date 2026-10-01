// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/BufferReflow.ts (c58ea36).

import '../circular_list.dart';
import 'buffer_line.dart';
import 'types.dart';

class INewLayoutResult {
  INewLayoutResult({required this.layout, required this.countRemoved});

  List<int> layout;
  int countRemoved;
}

/// Evaluates and returns indexes to be removed after a reflow larger occurs.
/// Lines will be removed when a wrapped line unwraps.
///
/// [lines] are the buffer lines, [oldCols] the columns before resize,
/// [newCols] the columns after resize, [bufferAbsoluteY] the absolute y
/// position of the cursor (baseY + cursorY), [nullCell] the cell data to use
/// when filling in empty cells and [reflowCursorLine] whether to reflow the
/// line containing the cursor.
List<int> reflowLargerGetLinesToRemove(
  CircularList<IBufferLine> lines,
  int oldCols,
  int newCols,
  int bufferAbsoluteY,
  ICellData nullCell,
  bool reflowCursorLine,
) {
  // Gather all BufferLines that need to be removed from the Buffer here so
  // that they can be batched up and only committed once
  final toRemove = <int>[];

  for (var y = 0; y < lines.length - 1; y++) {
    // Check if this row is wrapped
    var i = y;
    var nextLine = lines.get(++i) as BufferLine?;
    if (!nextLine!.isWrapped) {
      continue;
    }

    // Check how many lines it's wrapped for
    final wrappedLines = <BufferLine>[lines.get(y) as BufferLine];
    while (i < lines.length && nextLine!.isWrapped) {
      wrappedLines.add(nextLine);
      nextLine = lines.get(++i) as BufferLine?;
    }

    if (!reflowCursorLine) {
      // If these lines contain the cursor don't touch them, the program will
      // handle fixing up wrapped lines with the cursor
      if (bufferAbsoluteY >= y && bufferAbsoluteY < i) {
        y += wrappedLines.length - 1;
        continue;
      }
    }

    // Copy buffer data to new locations
    var destLineIndex = 0;
    var destCol = getWrappedLineTrimmedLength(
      wrappedLines,
      destLineIndex,
      oldCols,
    );
    var srcLineIndex = 1;
    var srcCol = 0;
    while (srcLineIndex < wrappedLines.length) {
      final srcTrimmedTineLength = getWrappedLineTrimmedLength(
        wrappedLines,
        srcLineIndex,
        oldCols,
      );
      final srcRemainingCells = srcTrimmedTineLength - srcCol;
      final destRemainingCells = newCols - destCol;
      final cellsToCopy = srcRemainingCells < destRemainingCells
          ? srcRemainingCells
          : destRemainingCells;

      wrappedLines[destLineIndex].copyCellsFrom(
        wrappedLines[srcLineIndex],
        srcCol,
        destCol,
        cellsToCopy,
        false,
      );

      destCol += cellsToCopy;
      if (destCol == newCols) {
        destLineIndex++;
        destCol = 0;
      }
      srcCol += cellsToCopy;
      if (srcCol == srcTrimmedTineLength) {
        srcLineIndex++;
        srcCol = 0;
      }

      // Make sure the last cell isn't wide, if it is copy it to the current
      // dest
      if (destCol == 0 && destLineIndex != 0) {
        if (wrappedLines[destLineIndex - 1].getWidth(newCols - 1) == 2) {
          wrappedLines[destLineIndex].copyCellsFrom(
            wrappedLines[destLineIndex - 1],
            newCols - 1,
            destCol++,
            1,
            false,
          );
          // Null out the end of the last row
          wrappedLines[destLineIndex - 1].setCell(newCols - 1, nullCell);
        }
      }
    }

    // Clear out remaining cells or fragments could remain;
    wrappedLines[destLineIndex].replaceCells(destCol, newCols, nullCell);

    // Work backwards and remove any rows at the end that only contain null
    // cells
    var countToRemove = 0;
    for (var i = wrappedLines.length - 1; i > 0; i--) {
      if (i > destLineIndex || wrappedLines[i].getTrimmedLength() == 0) {
        countToRemove++;
      } else {
        break;
      }
    }

    if (countToRemove > 0) {
      toRemove.add(y + wrappedLines.length - countToRemove); // index
      toRemove.add(countToRemove);
    }

    y += wrappedLines.length - 1;
  }
  return toRemove;
}

/// Creates and return the new layout for [lines] given a list of indexes to
/// be removed, [toRemove].
INewLayoutResult reflowLargerCreateNewLayout(
  CircularList<IBufferLine> lines,
  List<int> toRemove,
) {
  final layout = <int>[];
  // Upstream reads past the end of toRemove as undefined, never equal to i.
  int toRemoveAt(int index) => index < toRemove.length ? toRemove[index] : -1;
  // First iterate through the list and get the actual indexes to use for rows
  var nextToRemoveIndex = 0;
  var nextToRemoveStart = toRemoveAt(nextToRemoveIndex);
  var countRemovedSoFar = 0;
  for (var i = 0; i < lines.length; i++) {
    if (nextToRemoveStart == i) {
      final countToRemove = toRemove[++nextToRemoveIndex];

      // Tell markers that there was a deletion
      lines.onDeleteEmitter.fire(
        IDeleteEvent(index: i - countRemovedSoFar, amount: countToRemove),
      );

      i += countToRemove - 1;
      countRemovedSoFar += countToRemove;
      nextToRemoveStart = toRemoveAt(++nextToRemoveIndex);
    } else {
      layout.add(i);
    }
  }
  return INewLayoutResult(layout: layout, countRemoved: countRemovedSoFar);
}

/// Applies a new layout to the buffer. This essentially does the same as
/// many splice calls but it's done all at once in a single iteration through
/// the list since splice is very expensive.
///
/// [lines] are the buffer lines, [newLayout] the new layout to apply.
void reflowLargerApplyNewLayout(
  CircularList<IBufferLine> lines,
  List<int> newLayout,
) {
  // Record original lines so they don't get overridden when we rearrange the
  // list
  final newLayoutLines = <BufferLine>[];
  for (var i = 0; i < newLayout.length; i++) {
    newLayoutLines.add(lines.get(newLayout[i]) as BufferLine);
  }

  // Rearrange the list
  for (var i = 0; i < newLayoutLines.length; i++) {
    lines.set(i, newLayoutLines[i]);
  }
  lines.length = newLayout.length;
}

/// Gets the new line lengths for a given wrapped line. The purpose of this
/// function it to pre-compute the wrapping points since wide characters may
/// need to be wrapped onto the following line. This function will return an
/// array of numbers of where each line wraps to, the resulting array will
/// only contain the values `newCols` (when the line does not end with a wide
/// character) and `newCols - 1` (when the line does end with a wide
/// character), except for the last value which will contain the remaining
/// items to fill the line.
///
/// Calling this with a `newCols` value of `1` will lock up.
///
/// [wrappedLines] are the wrapped lines to evaluate, [oldCols] the columns
/// before resize and [newCols] the columns after resize.
List<int> reflowSmallerGetNewLineLengths(
  List<BufferLine> wrappedLines,
  int oldCols,
  int newCols,
) {
  final newLineLengths = <int>[];
  var cellsNeeded = 0;
  for (var i = 0; i < wrappedLines.length; i++) {
    cellsNeeded += getWrappedLineTrimmedLength(wrappedLines, i, oldCols);
  }

  // Use srcCol and srcLine to find the new wrapping point, use that to get
  // the cellsAvailable and linesNeeded
  var srcCol = 0;
  var srcLine = 0;
  var cellsAvailable = 0;
  while (cellsAvailable < cellsNeeded) {
    if (cellsNeeded - cellsAvailable < newCols) {
      // Add the final line and exit the loop
      newLineLengths.add(cellsNeeded - cellsAvailable);
      break;
    }
    srcCol += newCols;
    final oldTrimmedLength = getWrappedLineTrimmedLength(
      wrappedLines,
      srcLine,
      oldCols,
    );
    if (srcCol > oldTrimmedLength) {
      srcCol -= oldTrimmedLength;
      srcLine++;
    }
    final endsWithWide = wrappedLines[srcLine].getWidth(srcCol - 1) == 2;
    if (endsWithWide) {
      srcCol--;
    }
    final lineLength = endsWithWide ? newCols - 1 : newCols;
    newLineLengths.add(lineLength);
    cellsAvailable += lineLength;
  }

  return newLineLengths;
}

int getWrappedLineTrimmedLength(List<BufferLine> lines, int i, int cols) {
  // If this is the last row in the wrapped line, get the actual trimmed
  // length
  if (i == lines.length - 1) {
    return lines[i].getTrimmedLength();
  }
  // Detect whether the following line starts with a wide character and the
  // end of the current line is null, if so then we can be pretty sure the
  // null character should be excluded from the line length]
  final endsInNull =
      lines[i].hasContent(cols - 1) == 0 && lines[i].getWidth(cols - 1) == 1;
  final followingLineStartsWithWide = lines[i + 1].getWidth(0) == 2;
  if (endsInNull && followingLineStartsWithWide) {
    return cols - 1;
  }
  return cols;
}
