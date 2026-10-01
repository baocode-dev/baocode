// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/LICENSE.txt.
// Ported from xterm.js src/browser/selection/Types.ts (c58ea36).

/// Positions are `[x, y]` lists (upstream's `[number, number]` tuples).
class ISelectionRedrawRequestEvent {
  ISelectionRedrawRequestEvent({
    required this.start,
    required this.end,
    required this.columnSelectMode,
  });

  List<int>? start;
  List<int>? end;
  bool columnSelectMode;
}

class ISelectionRequestScrollLinesEvent {
  ISelectionRequestScrollLinesEvent({
    required this.amount,
    required this.suppressScrollEvent,
  });

  int amount;
  bool suppressScrollEvent;
}
