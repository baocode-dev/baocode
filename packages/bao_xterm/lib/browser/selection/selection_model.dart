// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/browser/selection/SelectionModel.ts (c58ea36).

import 'dart:math' as math;

import '../../common/services/services.dart';

/// Represents a selection within the buffer. This model only cares about
/// column and row coordinates, not wide characters.
///
/// Positions are `[x, y]` lists (upstream's `[number, number]` tuples).
class SelectionModel {
  SelectionModel(this._bufferService);

  final IBufferService _bufferService;

  /// Whether select all is currently active.
  bool isSelectAllActive = false;

  /// The minimal length of the selection from the start position. When double
  /// clicking on a word, the word will be selected which makes the selection
  /// start at the start of the word and makes this variable the length.
  int selectionStartLength = 0;

  /// The [x, y] position the selection starts at.
  List<int>? selectionStart;

  /// The [x, y] position the selection ends at.
  List<int>? selectionEnd;

  /// Clears the current selection.
  void clearSelection() {
    selectionStart = null;
    selectionEnd = null;
    isSelectAllActive = false;
    selectionStartLength = 0;
  }

  /// The final selection start, taking into consideration select all.
  List<int>? get finalSelectionStart {
    if (isSelectAllActive) {
      return <int>[0, 0];
    }

    if (selectionEnd == null || selectionStart == null) {
      return selectionStart;
    }

    return areSelectionValuesReversed() ? selectionEnd : selectionStart;
  }

  /// The final selection end, taking into consideration select all, double
  /// click word selection and triple click line selection.
  List<int>? get finalSelectionEnd {
    final cols = _bufferService.cols;
    if (isSelectAllActive) {
      return <int>[cols, _bufferService.buffer.ybase + _bufferService.rows - 1];
    }

    final start = selectionStart;
    if (start == null) {
      return null;
    }

    // Use the selection start + length if the end doesn't exist or they're
    // reversed
    final end = selectionEnd;
    if (end == null || areSelectionValuesReversed()) {
      final startPlusLength = start[0] + selectionStartLength;
      if (startPlusLength > cols) {
        // Ensure the trailing EOL isn't included when the selection ends on
        // the right edge
        if (startPlusLength % cols == 0) {
          return <int>[cols, start[1] + (startPlusLength / cols).floor() - 1];
        }
        return <int>[
          startPlusLength % cols,
          start[1] + (startPlusLength / cols).floor(),
        ];
      }
      return <int>[startPlusLength, start[1]];
    }

    // Ensure the the word/line is selected after a double/triple click
    if (selectionStartLength != 0) {
      // Select the larger of the two when start and end are on the same line
      if (end[1] == start[1]) {
        // Keep the whole wrapped word/line selected if the content wraps
        // multiple lines
        final startPlusLength = start[0] + selectionStartLength;
        if (startPlusLength > cols) {
          return <int>[
            startPlusLength % cols,
            start[1] + (startPlusLength / cols).floor(),
          ];
        }
        return <int>[math.max(startPlusLength, end[0]), end[1]];
      }
    }
    return end;
  }

  /// Returns whether the selection start and end are reversed.
  bool areSelectionValuesReversed() {
    final start = selectionStart;
    final end = selectionEnd;
    if (start == null || end == null) {
      return false;
    }
    return start[1] > end[1] || (start[1] == end[1] && start[0] > end[0]);
  }

  /// Handle the buffer being trimmed, adjust the selection position.
  ///
  /// [amount] is the amount the buffer is being trimmed. Returns whether a
  /// refresh is necessary.
  bool handleTrim(int amount) {
    // Adjust the selection position based on the trimmed amount.
    final start = selectionStart;
    if (start != null) {
      start[1] -= amount;
    }
    final end = selectionEnd;
    if (end != null) {
      end[1] -= amount;
    }

    // The selection has moved off the buffer, clear it.
    if (end != null && end[1] < 0) {
      clearSelection();
      return true;
    }

    // If the selection start row is trimmed away, reset to the buffer origin.
    if (start != null && start[1] < 0) {
      selectionStart = <int>[0, 0];
      return true;
    }
    return false;
  }
}
