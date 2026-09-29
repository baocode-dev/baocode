/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 6a598d4a,
// src/vs/editor/common/cursor/cursorAtomicMoveOperations.ts.

import '../core/cursor_columns.dart';

enum Direction { left, right, nearest }

class AtomicTabMoveOperations {
  /// Gets the visible column at [position]. If a non-whitespace character is
  /// reached first, or the position is past the string, returns (-1, -1, -1).
  ///
  /// Returns (previous tab-stop position, previous tab-stop visible column,
  /// visible column). All positions and columns are zero-based.
  static (int, int, int) whitespaceVisibleColumn(
    String lineContent,
    int position,
    int tabSize,
  ) {
    final lineLength = lineContent.length;
    var visibleColumn = 0;
    var prevTabStopPosition = -1;
    var prevTabStopVisibleColumn = -1;
    for (var i = 0; i < lineLength; i++) {
      if (i == position) {
        return (prevTabStopPosition, prevTabStopVisibleColumn, visibleColumn);
      }
      if (visibleColumn % tabSize == 0) {
        prevTabStopPosition = i;
        prevTabStopVisibleColumn = visibleColumn;
      }
      switch (lineContent.codeUnitAt(i)) {
        case 0x20: // CharCode.Space
          visibleColumn += 1;
          break;
        case 0x09: // CharCode.Tab
          // Skip to the next multiple of tabSize.
          visibleColumn = CursorColumns.nextRenderTabStop(
            visibleColumn,
            tabSize,
          );
          break;
        default:
          return (-1, -1, -1);
      }
    }
    if (position == lineLength) {
      return (prevTabStopPosition, prevTabStopVisibleColumn, visibleColumn);
    }
    return (-1, -1, -1);
  }

  /// Returns the position after a move left, right, or to the nearest tab when
  /// atomic tabs are enabled. Left and right serve arrow-key movements; nearest
  /// serves mouse selection. Returns -1 when normal movement should be used.
  ///
  /// [position] and the return value are zero-based UTF-16 offsets.
  static int atomicPosition(
    String lineContent,
    int position,
    int tabSize,
    Direction direction,
  ) {
    final lineLength = lineContent.length;

    // Get the visible column, or -1 if not in the initial whitespace.
    final (prevTabStopPosition, prevTabStopVisibleColumn, visibleColumn) =
        whitespaceVisibleColumn(lineContent, position, tabSize);

    if (visibleColumn == -1) {
      return -1;
    }

    // Whether the output is left or right of the input position. The nearest
    // case that stays at the current position is handled in the switch.
    final bool left;
    switch (direction) {
      case Direction.left:
        left = true;
        break;
      case Direction.right:
        left = false;
        break;
      case Direction.nearest:
        if (visibleColumn % tabSize == 0) {
          return position;
        }
        // Go to the nearest indentation, choosing left on a tie.
        left = visibleColumn % tabSize <= tabSize / 2;
        break;
    }

    // Going left can reuse the last tab stop found in the first walk.
    if (left) {
      if (prevTabStopPosition == -1) {
        return -1;
      }
      // Keep scanning right to ensure a full tabSize precedes non-whitespace.
      // At the end of a partial indent, ordinary movement must be used:
      // '      foo' at position 6 with tabSize 4 goes to 5, not 4.
      var currentVisibleColumn = prevTabStopVisibleColumn;
      for (var i = prevTabStopPosition; i < lineLength; ++i) {
        if (currentVisibleColumn == prevTabStopVisibleColumn + tabSize) {
          return prevTabStopPosition;
        }

        switch (lineContent.codeUnitAt(i)) {
          case 0x20: // CharCode.Space
            currentVisibleColumn += 1;
            break;
          case 0x09: // CharCode.Tab
            currentVisibleColumn = CursorColumns.nextRenderTabStop(
              currentVisibleColumn,
              tabSize,
            );
            break;
          default:
            return -1;
        }
      }
      if (currentVisibleColumn == prevTabStopVisibleColumn + tabSize) {
        return prevTabStopPosition;
      }
      // A partial indentation.
      return -1;
    }

    // Going right can continue from where whitespaceVisibleColumn stopped.
    final targetVisibleColumn = CursorColumns.nextRenderTabStop(
      visibleColumn,
      tabSize,
    );
    var currentVisibleColumn = visibleColumn;
    for (var i = position; i < lineLength; i++) {
      if (currentVisibleColumn == targetVisibleColumn) {
        return i;
      }

      switch (lineContent.codeUnitAt(i)) {
        case 0x20: // CharCode.Space
          currentVisibleColumn += 1;
          break;
        case 0x09: // CharCode.Tab
          currentVisibleColumn = CursorColumns.nextRenderTabStop(
            currentVisibleColumn,
            tabSize,
          );
          break;
        default:
          return -1;
      }
    }
    // The target column may be at the end of the line.
    if (currentVisibleColumn == targetVisibleColumn) {
      return lineLength;
    }
    return -1;
  }
}
