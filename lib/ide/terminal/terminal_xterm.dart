/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// A terminal's xterm, as VS Code's XtermTerminal wraps xterm.js' browser
// Terminal: the public terminal over the core, with the browser terminal's
// selection and decorations, which the search addon and VS Code's
// contributions use.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/browser/xterm/xtermTerminal.ts, and
// xterm.js (c58ea36) src/browser/public/Terminal.ts (`hasSelection`,
// `getSelection`, `getSelectionPosition`, `clearSelection`, `select`,
// `registerDecoration`, `onSelectionChange`).

import 'terminal_selection.dart';
import 'xterm/addons/addon_search/typings/addon_search.dart';
import 'xterm/common/event.dart';
import 'xterm/common/services/decoration_service.dart';
import 'xterm/headless/public/terminal.dart';
import 'xterm/typings/xterm.dart'
    show IBufferCellPosition, IBufferRange, IDecoration, IDecorationOptions;

class TerminalXterm extends Terminal implements ISearchTerminal {
  TerminalXterm([super.options]) {
    decorationService = register(
      DecorationService(core.logService, core.bufferService),
    );
    selection = register(
      TerminalSelection(
        bufferService: core.bufferService,
        coreService: core.coreService,
        optionsService: core.optionsService,
        mouseStateService: core.mouseStateService,
      ),
    );
  }

  /// The marks drawn on the screen and its scrollbar.
  late final DecorationService decorationService;

  late final TerminalSelection selection;

  @override
  IEvent<void> get onSelectionChange => selection.onSelectionChange;

  @override
  IDecoration? registerDecoration(IDecorationOptions decorationOptions) =>
      decorationService.registerDecoration(decorationOptions);

  @override
  bool hasSelection() => selection.hasSelection;

  @override
  String getSelection() => selection.selectionText;

  @override
  IBufferRange? getSelectionPosition() {
    final start = selection.selectionStart;
    final end = selection.selectionEnd;
    if (!selection.hasSelection || start == null || end == null) return null;
    return IBufferRange(
      start: IBufferCellPosition(x: start[0], y: start[1]),
      end: IBufferCellPosition(x: end[0], y: end[1]),
    );
  }

  @override
  void clearSelection() => selection.clearSelection();

  @override
  void select(int column, int row, int length) =>
      selection.setSelection(column, row, length);
}
