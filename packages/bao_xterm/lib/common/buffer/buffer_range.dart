// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/buffer/BufferRange.ts (c58ea36).

import '../../typings/xterm.dart';

int getRangeLength(IBufferRange range, int bufferCols) {
  if (range.start.y > range.end.y) {
    throw ArgumentError(
      'Buffer range end (${range.end.x}, ${range.end.y}) cannot be before '
      'start (${range.start.x}, ${range.start.y})',
    );
  }
  return bufferCols * (range.end.y - range.start.y) +
      (range.end.x - range.start.x + 1);
}
