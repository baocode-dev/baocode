// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/browser/input/Mouse.ts (c58ea36).
//
// Subset: `getCoordsRelativeToElement` reads the element's bounding rect and
// computed padding, so it is not ported; `getCoords` takes the event's
// position relative to the element's content box instead of the window, the
// event and the element.

import 'dart:math' as math;

/// Gets coordinates within the terminal for a particular mouse event. The
/// result is returned as a list in the form [x, y] (1-based cells) instead of
/// an object as it's a little faster and this function is used in some low
/// level code.
///
/// [x] and [y] are the event's position relative to the terminal's content
/// box. [colCount] and [rowCount] are the number of columns and rows in the
/// terminal. [hasValidCharSize] is whether there is a valid character size
/// available. [cssCellWidth] and [cssCellHeight] are the cell's CSS (logical)
/// size. [isSelection] is whether the request is for the selection or not.
/// This will apply an offset to the x value such that the left half of the
/// cell will select that cell and the right half will select the next cell.
List<int>? getCoords(
  double x,
  double y,
  int colCount,
  int rowCount,
  bool hasValidCharSize,
  double cssCellWidth,
  double cssCellHeight, [
  bool? isSelection,
]) {
  // Coordinates cannot be measured if there is no valid character size.
  if (!hasValidCharSize) {
    return null;
  }

  final selection = isSelection ?? false;
  var col = ((x + (selection ? cssCellWidth / 2 : 0)) / cssCellWidth).ceil();
  var row = (y / cssCellHeight).ceil();

  // Ensure coordinates are within the terminal viewport. Note that selections
  // need an additional point of precision to cover the end point (as
  // characters cover half of one char and half of the next).
  col = math.min(math.max(col, 1), colCount + (selection ? 1 : 0));
  row = math.min(math.max(row, 1), rowCount);

  return <int>[col, row];
}
