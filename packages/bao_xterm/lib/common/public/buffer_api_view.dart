// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/common/public/BufferApiView.ts (c58ea36).

import '../../typings/xterm.dart' as api;
import '../buffer/cell_data.dart';
import '../buffer/types.dart';
import 'buffer_line_api_view.dart';

class BufferApiView implements api.IBuffer {
  BufferApiView(this._buffer, this.type);

  IBuffer _buffer;

  /// `'normal'` or `'alternate'`.
  @override
  final String type;

  BufferApiView init(IBuffer buffer) {
    _buffer = buffer;
    return this;
  }

  @override
  int get cursorY => _buffer.y;
  @override
  int get cursorX => _buffer.x;
  @override
  int get viewportY => _buffer.ydisp;
  @override
  int get baseY => _buffer.ybase;
  @override
  int get length => _buffer.lines.length;
  @override
  api.IBufferLine? getLine(int y) {
    final line = _buffer.lines.get(y);
    if (line == null) {
      return null;
    }
    return BufferLineApiView(line);
  }

  @override
  api.IBufferCell getNullCell() => CellData();
}
