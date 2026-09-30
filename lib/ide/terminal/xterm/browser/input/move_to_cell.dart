// Copyright (c) 2018 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/browser/input/MoveToCell.ts (c58ea36).

import '../../common/data/escape_sequences.dart';
import '../../common/services/services.dart';

/// Upstream's string `const enum Direction`.
abstract final class _Direction {
  static const String up = 'A';
  static const String down = 'B';
  static const String right = 'C';
  static const String left = 'D';
}

/// Concatenates all the arrow sequences together.
///
/// Resets the starting row to an unwrapped row, moves to the requested row,
/// then moves to requested col.
String moveToCellSequence(
  int targetX,
  int targetY,
  IBufferService bufferService,
  bool applicationCursor,
) {
  final startX = bufferService.buffer.x;
  final startY = bufferService.buffer.y;

  // The alt buffer should try to navigate between rows
  if (!bufferService.buffer.hasScrollback) {
    return _resetStartingRow(
          startX,
          startY,
          targetX,
          targetY,
          bufferService,
          applicationCursor,
        ) +
        _moveToRequestedRow(startY, targetY, bufferService, applicationCursor) +
        _moveToRequestedCol(
          startX,
          startY,
          targetX,
          targetY,
          bufferService,
          applicationCursor,
        );
  }

  // Only move horizontally for the normal buffer
  String direction;
  if (startY == targetY) {
    direction = startX > targetX ? _Direction.left : _Direction.right;
    return _repeat(
      (startX - targetX).abs(),
      _sequence(direction, applicationCursor),
    );
  }
  direction = startY > targetY ? _Direction.left : _Direction.right;
  final rowDifference = (startY - targetY).abs();
  final cellsToMove =
      _colsFromRowEnd(startY > targetY ? targetX : startX, bufferService) +
      (rowDifference - 1) * bufferService.cols +
      1 /* wrap around 1 row */ +
      _colsFromRowBeginning(startY > targetY ? startX : targetX, bufferService);
  return _repeat(cellsToMove, _sequence(direction, applicationCursor));
}

/// Find the number of cols from a row beginning to a col.
int _colsFromRowBeginning(int currX, IBufferService bufferService) {
  return currX - 1;
}

/// Find the number of cols from a col to row end.
int _colsFromRowEnd(int currX, IBufferService bufferService) {
  return bufferService.cols - currX;
}

/// If the initial position of the cursor is on a row that is wrapped, move
/// the cursor up to the first row that is not wrapped to have accurate
/// vertical positioning.
String _resetStartingRow(
  int startX,
  int startY,
  int targetX,
  int targetY,
  IBufferService bufferService,
  bool applicationCursor,
) {
  if (_moveToRequestedRow(
    startY,
    targetY,
    bufferService,
    applicationCursor,
  ).isEmpty) {
    return '';
  }
  return _repeat(
    _bufferLine(
      startX,
      startY,
      startX,
      startY - _wrappedRowsForRow(startY, bufferService),
      false,
      bufferService,
    ).length,
    _sequence(_Direction.left, applicationCursor),
  );
}

/// Using the reset starting and ending row, move to the requested row,
/// ignoring wrapped rows
String _moveToRequestedRow(
  int startY,
  int targetY,
  IBufferService bufferService,
  bool applicationCursor,
) {
  final startRow = startY - _wrappedRowsForRow(startY, bufferService);
  final endRow = targetY - _wrappedRowsForRow(targetY, bufferService);

  final rowsToMove =
      (startRow - endRow).abs() -
      _wrappedRowsCount(startY, targetY, bufferService);

  return _repeat(
    rowsToMove,
    _sequence(_verticalDirection(startY, targetY), applicationCursor),
  );
}

/// Move to the requested col on the ending row
String _moveToRequestedCol(
  int startX,
  int startY,
  int targetX,
  int targetY,
  IBufferService bufferService,
  bool applicationCursor,
) {
  int startRow;
  if (_moveToRequestedRow(
    startY,
    targetY,
    bufferService,
    applicationCursor,
  ).isNotEmpty) {
    startRow = targetY - _wrappedRowsForRow(targetY, bufferService);
  } else {
    startRow = startY;
  }

  final endRow = targetY;
  final direction = _horizontalDirection(
    startX,
    startY,
    targetX,
    targetY,
    bufferService,
    applicationCursor,
  );

  return _repeat(
    _bufferLine(
      startX,
      startRow,
      targetX,
      endRow,
      direction == _Direction.right,
      bufferService,
    ).length,
    _sequence(direction, applicationCursor),
  );
}

// Utility functions

/// Calculates the number of wrapped rows between the unwrapped starting and
/// ending rows. These rows need to ignored since the cursor skips over them.
int _wrappedRowsCount(int startY, int targetY, IBufferService bufferService) {
  var wrappedRows = 0;
  final startRow = startY - _wrappedRowsForRow(startY, bufferService);
  final endRow = targetY - _wrappedRowsForRow(targetY, bufferService);

  for (var i = 0; i < (startRow - endRow).abs(); i++) {
    final direction = _verticalDirection(startY, targetY) == _Direction.up
        ? -1
        : 1;
    final line = bufferService.buffer.lines.get(startRow + (direction * i));
    if (line?.isWrapped ?? false) {
      wrappedRows++;
    }
  }

  return wrappedRows;
}

/// Calculates the number of wrapped rows that make up a given row.
///
/// [currentRow] is the row to determine how many wrapped rows make it up.
int _wrappedRowsForRow(int currentRow, IBufferService bufferService) {
  var rowCount = 0;
  var line = bufferService.buffer.lines.get(currentRow);
  var lineWraps = line?.isWrapped ?? false;

  while (lineWraps && currentRow >= 0 && currentRow < bufferService.rows) {
    rowCount++;
    line = bufferService.buffer.lines.get(--currentRow);
    lineWraps = line?.isWrapped ?? false;
  }

  return rowCount;
}

// Direction determiners

/// Determines if the right or left arrow is needed
String _horizontalDirection(
  int startX,
  int startY,
  int targetX,
  int targetY,
  IBufferService bufferService,
  bool applicationCursor,
) {
  int startRow;
  if (_moveToRequestedRow(
    startY,
    targetY,
    bufferService,
    applicationCursor,
  ).isNotEmpty) {
    startRow = targetY - _wrappedRowsForRow(targetY, bufferService);
  } else {
    startRow = startY;
  }

  if ((startX < targetX &&
          startRow <= targetY) || // down/right or same y/right
      (startX >= targetX && startRow < targetY)) {
    // down/left or same y/left
    return _Direction.right;
  }
  return _Direction.left;
}

/// Determines if the up or down arrow is needed
String _verticalDirection(int startY, int targetY) {
  return startY > targetY ? _Direction.up : _Direction.down;
}

/// Constructs the string of chars in the buffer from a starting row and col
/// to an ending row and col, moving [forward] or backwards.
String _bufferLine(
  int startCol,
  int startRow,
  int endCol,
  int endRow,
  bool forward,
  IBufferService bufferService,
) {
  var currentCol = startCol;
  var currentRow = startRow;
  var bufferStr = '';

  while ((currentCol != endCol || currentRow != endRow) &&
      currentRow >= 0 &&
      currentRow < bufferService.buffer.lines.length) {
    currentCol += forward ? 1 : -1;

    if (forward && currentCol > bufferService.cols - 1) {
      bufferStr += bufferService.buffer.translateBufferLineToString(
        currentRow,
        false,
        startCol,
        currentCol,
      );
      currentCol = 0;
      startCol = 0;
      currentRow++;
    } else if (!forward && currentCol < 0) {
      bufferStr += bufferService.buffer.translateBufferLineToString(
        currentRow,
        false,
        0,
        startCol + 1,
      );
      currentCol = bufferService.cols - 1;
      startCol = currentCol;
      currentRow--;
    }
  }

  return bufferStr +
      bufferService.buffer.translateBufferLineToString(
        currentRow,
        false,
        startCol,
        currentCol,
      );
}

/// Constructs the escape sequence for clicking an arrow in [direction].
String _sequence(String direction, bool applicationCursor) {
  final mod = applicationCursor ? 'O' : '[';
  return C0.esc + mod + direction;
}

/// Returns [str] repeated [count] times (none for a negative count).
String _repeat(int count, String str) {
  var rpt = '';
  for (var i = 0; i < count; i++) {
    rpt += str;
  }
  return rpt;
}
