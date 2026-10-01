// Copyright (c) 2019 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/WindowsMode.ts (c58ea36).

import 'buffer/constants.dart';
import 'services/services.dart';

void updateWindowsModeWrappedState(IBufferService bufferService) {
  // Winpty does not support wraparound mode which means that lines will never
  // be marked as wrapped. This causes issues for things like copying a line
  // retaining the wrapped new line characters or if consumers are listening
  // in on the data stream.
  //
  // The workaround for this is to listen to every incoming line feed and mark
  // the line as wrapped if the last character in the previous line is not a
  // space. This is certainly not without its problems, but generally on
  // Windows when text reaches the end of the terminal it's likely going to be
  // wrapped.
  final line = bufferService.buffer.lines.get(
    bufferService.buffer.ybase + bufferService.buffer.y - 1,
  );
  final lastChar = line?.get(bufferService.cols - 1);

  final nextLine = bufferService.buffer.lines.get(
    bufferService.buffer.ybase + bufferService.buffer.y,
  );
  if (nextLine != null && lastChar != null) {
    // lastChar.$4 is lastChar[CHAR_DATA_CODE_INDEX].
    nextLine.isWrapped =
        lastChar.$4 != nullCellCode && lastChar.$4 != whitespaceCellCode;
  }
}
