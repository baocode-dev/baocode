// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/browser/public/Terminal.ts and
// src/browser/services/SelectionService.ts (c58ea36).
//
// A helper, not a test: the browser terminal the search addon's tests run
// on. It is the headless public terminal plus a SelectionModel and a
// DecorationService, which CoreBrowserTerminal's selection and decoration
// methods forward to. Only what the tests need of SelectionService is here:
// `setSelection`, `clearSelection`, `hasSelection` and `selectionText` (not
// in column mode); no mouse, trimming or clearing on input.

import 'package:monad/ide/terminal/xterm/addons/addon_search/typings/addon_search.dart';
import 'package:monad/ide/terminal/xterm/browser/selection/selection_model.dart';
import 'package:monad/ide/terminal/xterm/common/event.dart';
import 'package:monad/ide/terminal/xterm/common/services/decoration_service.dart';
import 'package:monad/ide/terminal/xterm/headless/public/terminal.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm.dart'
    show IBufferCellPosition, IBufferRange, IDecoration, IDecorationOptions;

final RegExp _allNonBreakingSpace = RegExp('\u00a0');

class SearchTestTerminal extends Terminal implements ISearchTerminal {
  SearchTestTerminal([super.options]) {
    _model = SelectionModel(core.bufferService);
    decorationService = register(
      DecorationService(core.logService, core.bufferService),
    );
    _onSelectionChange = register(Emitter<void>());
  }

  late final SelectionModel _model;

  /// The decorations registered, as the renderer would draw them.
  late final DecorationService decorationService;

  late final Emitter<void> _onSelectionChange;

  /// Replaces [getSelectionPosition] while set, as upstream's tests assign
  /// `terminal.getSelectionPosition`.
  IBufferRange? Function()? getSelectionPositionMock;

  /// Replaces [registerDecoration] while set, as upstream's tests assign
  /// `terminal.registerDecoration`; [decorationService] is the original.
  IDecoration? Function(IDecorationOptions options)? registerDecorationMock;

  @override
  IEvent<void> get onSelectionChange => _onSelectionChange.event;

  @override
  IDecoration? registerDecoration(IDecorationOptions decorationOptions) {
    final mock = registerDecorationMock;
    if (mock != null) {
      return mock(decorationOptions);
    }
    return decorationService.registerDecoration(decorationOptions);
  }

  @override
  bool hasSelection() {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    if (start == null || end == null) {
      return false;
    }
    return start[0] != end[0] || start[1] != end[1];
  }

  @override
  String getSelection() {
    final start = _model.finalSelectionStart;
    final end = _model.finalSelectionEnd;
    if (start == null || end == null) {
      return '';
    }

    final buffer = core.buffer;
    final result = <String>[];

    // Get first row
    final startRowEndCol = start[1] == end[1] ? end[0] : null;
    result.add(
      buffer.translateBufferLineToString(
        start[1],
        true,
        start[0],
        startRowEndCol,
      ),
    );

    // Get middle rows
    for (var i = start[1] + 1; i <= end[1] - 1; i++) {
      final bufferLine = buffer.lines.get(i);
      final lineText = buffer.translateBufferLineToString(i, true);
      if (bufferLine?.isWrapped ?? false) {
        result[result.length - 1] += lineText;
      } else {
        result.add(lineText);
      }
    }

    // Get final row
    if (start[1] != end[1]) {
      final bufferLine = buffer.lines.get(end[1]);
      final lineText = buffer.translateBufferLineToString(
        end[1],
        true,
        0,
        end[0],
      );
      if (bufferLine != null && bufferLine.isWrapped) {
        result[result.length - 1] += lineText;
      } else {
        result.add(lineText);
      }
    }

    return result
        .map((line) => line.replaceAll(_allNonBreakingSpace, ' '))
        .join('\n');
  }

  @override
  IBufferRange? getSelectionPosition() {
    final mock = getSelectionPositionMock;
    if (mock != null) {
      return mock();
    }
    if (!hasSelection()) {
      return null;
    }
    final start = _model.finalSelectionStart!;
    final end = _model.finalSelectionEnd!;
    return IBufferRange(
      start: IBufferCellPosition(x: start[0], y: start[1]),
      end: IBufferCellPosition(x: end[0], y: end[1]),
    );
  }

  @override
  void clearSelection() {
    _model.clearSelection();
    _onSelectionChange.fire(null);
  }

  @override
  void select(int column, int row, int length) {
    _model.clearSelection();
    _model.selectionStart = <int>[column, row];
    _model.selectionStartLength = length;
    _onSelectionChange.fire(null);
  }
}

/// Upstream's `{ start: { x, y }, end: { x, y } }` selection positions.
IBufferRange bufferRange(int startX, int startY, int endX, int endY) {
  return IBufferRange(
    start: IBufferCellPosition(x: startX, y: startY),
    end: IBufferCellPosition(x: endX, y: endY),
  );
}
