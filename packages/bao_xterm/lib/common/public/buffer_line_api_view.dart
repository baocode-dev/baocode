// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/common/public/BufferLineApiView.ts (c58ea36).

import '../../typings/xterm.dart' as api;
import '../buffer/cell_data.dart';
import '../buffer/types.dart';

class BufferLineApiView implements api.IBufferLine {
  BufferLineApiView(this._line);

  final IBufferLine _line;

  @override
  bool get isWrapped => _line.isWrapped;
  @override
  int get length => _line.length;

  /// [cell] must be one this API handed out (a `CellData`), as upstream
  /// assumes too.
  @override
  api.IBufferCell? getCell(int x, [api.IBufferCell? cell]) {
    if (x < 0 || x >= _line.length) {
      return null;
    }

    if (cell != null) {
      _line.loadCell(x, cell as ICellData);
      return cell;
    }
    return _line.loadCell(x, CellData()) as api.IBufferCell;
  }

  @override
  String translateToString([
    bool? trimRight,
    int? startColumn,
    int? endColumn,
  ]) {
    return _line.translateToString(trimRight, startColumn, endColumn);
  }
}
