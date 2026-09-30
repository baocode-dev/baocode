/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The terminal's clipboard, as VS Code's terminal clipboard contribution:
// copy the selection, paste (the multi-line paste check, then xterm.js'
// paste: line endings as Enter, bracketed when the app turned bracketed
// paste mode on), copy on selection, the Linux primary selection for middle
// click, the right and middle click settings, and the copy and paste
// keybindings that skip the shell.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/clipboard/browser/
// terminalClipboard.ts (`shouldPasteTerminalText`) and
// terminal.clipboard.contribution.ts (`TerminalClipboardContribution`, the
// copy and paste actions' keybindings); and from xterm.js c58ea36
// src/browser/Clipboard.ts (MIT, see lib/ide/terminal/xterm/LICENSE.txt).
//
// Deviations: the dialog is the embedder's [TerminalClipboard.confirmPaste]
// (without it a multi-line paste goes ahead); the primary selection is the
// terminal's own last mouse selection, as Flutter has no X11 selection.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'terminal_mouse.dart';
import 'terminal_selection.dart';
import 'xterm/browser/clipboard.dart' as xterm_clipboard;
import 'xterm/common/lifecycle.dart';
import 'xterm/common/services/services.dart';
import 'xterm/common/types.dart';

/// VS Code's `terminal.integrated.enableMultiLinePasteWarning`.
enum TerminalMultiLinePasteWarning {
  /// Warn, except when the app is in bracketed paste mode; a single line
  /// with a trailing newline is pasted without it.
  auto,

  /// Always warn when the text has a newline.
  always,

  /// Never warn.
  never,
}

/// The multi-line paste warning to show: VS Code's dialog text.
@immutable
class TerminalPastePrompt {
  const TerminalPastePrompt({required this.lineCount, required this.detail});

  final int lineCount;

  /// `Preview:` and the first three lines, cut at 30 characters.
  final String detail;

  String get message =>
      'Are you sure you want to paste $lineCount lines of text into the '
      'terminal?';
}

/// The answer to a [TerminalPastePrompt]: VS Code's Paste, Paste as one
/// line, or cancel, and its "Do not ask me again" checkbox.
enum TerminalPasteChoice { paste, pasteAsOneLine, cancel }

typedef TerminalConfirmPaste =
    Future<({TerminalPasteChoice choice, bool doNotAskAgain})> Function(
      TerminalPastePrompt prompt,
    );

/// VS Code's terminal clipboard commands that have keybindings.
enum TerminalClipboardCommand {
  copySelection,
  copyAndClearSelection,
  paste,
  pasteSelection,
}

final RegExp _lineBreaks = RegExp(r'\r?\n');

/// What VS Code's `shouldPasteTerminalText` decides before a dialog: the
/// text to paste, or the prompt to confirm first.
({String? text, TerminalPastePrompt? prompt}) checkTerminalPaste(
  String text, {
  required bool bracketedPasteMode,
  TerminalMultiLinePasteWarning warning = TerminalMultiLinePasteWarning.auto,
}) {
  // If the clipboard has only one line, a warning should never show
  final textForLines = text.split(_lineBreaks);
  if (textForLines.length == 1) {
    return (text: text, prompt: null);
  }

  // Never show it
  if (warning == TerminalMultiLinePasteWarning.never) {
    return (text: text, prompt: null);
  }

  // Special edge cases to not show for auto
  if (warning == TerminalMultiLinePasteWarning.auto) {
    // Ignore check if the shell is in bracketed paste mode (ie. the shell
    // can handle multi-line text).
    if (bracketedPasteMode) {
      return (text: text, prompt: null);
    }

    // When a command is copied with a trailing new line, strip the trailing
    // newline so the command is not automatically executed on paste. This
    // mitigates a clipboard hijacking scenario where a malicious page
    // replaces clipboard contents with a command followed by a newline;
    // pasting (especially via right click) would otherwise immediately
    // execute it. The user can still review the pasted text and press Enter
    // to run it.
    if (textForLines.length == 2 && textForLines[1].trim().isEmpty) {
      return (text: textForLines[0], prompt: null);
    }
  }

  const displayItemsCount = 3;
  const maxPreviewLineLength = 30;

  final detail = StringBuffer('Preview:');
  for (var i = 0; i < textForLines.length && i < displayItemsCount; i++) {
    final line = textForLines[i];
    final cleanedLine = line.length > maxPreviewLineLength
        ? '${line.substring(0, maxPreviewLineLength)}…'
        : line;
    detail.write('\n$cleanedLine');
  }

  if (textForLines.length > displayItemsCount) {
    detail.write('\n…');
  }

  return (
    text: null,
    prompt: TerminalPastePrompt(
      lineCount: textForLines.length,
      detail: detail.toString(),
    ),
  );
}

/// The data a paste of [text] sends to the process (xterm.js' `paste`): line
/// endings become Enter (`\r`), and the text is bracketed (its ESCs made
/// visible) when the app enabled bracketed paste mode and the
/// `ignoreBracketedPasteMode` option is off.
String terminalPasteData(
  String text, {
  required bool bracketedPasteMode,
  bool ignoreBracketedPasteMode = false,
}) {
  return xterm_clipboard.bracketTextForPaste(
    xterm_clipboard.prepareTextForTerminal(text),
    bracketedPasteMode && !ignoreBracketedPasteMode,
  );
}

/// The clipboard command VS Code binds [ev] to (keybindings that skip the
/// shell), given whether the terminal [hasSelection]: copy is Cmd+C on
/// macOS, Ctrl+Shift+C elsewhere and also Ctrl+C (copy and clear) on
/// Windows, with a selection; paste is Cmd+V on macOS, Ctrl+V or
/// Ctrl+Shift+V on Windows, Ctrl+Shift+V on Linux; Shift+Insert pastes the
/// selection on Linux.
TerminalClipboardCommand? terminalClipboardCommandFor(
  IKeyboardEvent ev, {
  required bool hasSelection,
  required TargetPlatform platform,
}) {
  if (ev.type != 'keydown') {
    return null;
  }
  final isMac = platform == TargetPlatform.macOS;
  final isWindows = platform == TargetPlatform.windows;
  final isLinux = platform == TargetPlatform.linux;
  // KeyMod.CtrlCmd: Cmd on macOS, Ctrl elsewhere; the other modifiers must
  // be up.
  bool chord({bool shift = false}) =>
      (isMac ? ev.metaKey && !ev.ctrlKey : ev.ctrlKey && !ev.metaKey) &&
      !ev.altKey &&
      ev.shiftKey == shift;
  const keyC = 67;
  const keyV = 86;
  const insert = 45;

  if (ev.keyCode == keyC && hasSelection) {
    if (isMac ? chord() : chord(shift: true)) {
      return TerminalClipboardCommand.copySelection;
    }
    if (isWindows && chord()) {
      return TerminalClipboardCommand.copyAndClearSelection;
    }
  }
  if (ev.keyCode == keyV) {
    final paste = isMac
        ? chord()
        : isLinux
        ? chord(shift: true)
        : chord() || (isWindows && chord(shift: true));
    if (paste) {
      return TerminalClipboardCommand.paste;
    }
  }
  if (isLinux &&
      ev.keyCode == insert &&
      ev.shiftKey &&
      !ev.ctrlKey &&
      !ev.altKey &&
      !ev.metaKey) {
    return TerminalClipboardCommand.pasteSelection;
  }
  return null;
}

Future<String?> _readSystemClipboard() async =>
    (await Clipboard.getData(Clipboard.kTextPlain))?.text;

Future<void> _writeSystemClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

/// The terminal's copy and paste.
class TerminalClipboard extends Disposable {
  TerminalClipboard({
    required this.selection,
    required this._coreService,
    required this._optionsService,
    TargetPlatform? platform,
    Future<String?> Function()? readText,
    Future<void> Function(String text)? writeText,
    this.confirmPaste,
    TerminalRightClickBehavior? rightClickBehavior,
    this.middleClickBehavior = TerminalMiddleClickBehavior.platformDefault,
    this.copyOnSelection = false,
    this.multiLinePasteWarning = TerminalMultiLinePasteWarning.auto,
  }) : platform = platform ?? defaultTargetPlatform,
       _readText = readText ?? _readSystemClipboard,
       _writeText = writeText ?? _writeSystemClipboard,
       rightClickBehavior =
           rightClickBehavior ??
           TerminalRightClickBehavior.defaultFor(
             platform ?? defaultTargetPlatform,
           ) {
    register(
      selection.onSelectionChange((_) {
        if (copyOnSelection && selection.hasSelection) {
          unawaited(copySelection());
        }
      }),
    );
    register(
      selection.onLinuxMouseSelection((text) => _primarySelection = text),
    );
  }

  final TerminalSelection selection;
  final ICoreService _coreService;
  final IOptionsService _optionsService;
  final TargetPlatform platform;
  final Future<String?> Function() _readText;
  final Future<void> Function(String text) _writeText;

  /// Shows VS Code's multi-line paste warning; without it such pastes go
  /// ahead.
  TerminalConfirmPaste? confirmPaste;

  /// `terminal.integrated.rightClickBehavior`.
  TerminalRightClickBehavior rightClickBehavior;

  /// `terminal.integrated.middleClickBehavior`.
  TerminalMiddleClickBehavior middleClickBehavior;

  /// `terminal.integrated.copyOnSelection`.
  bool copyOnSelection;

  /// `terminal.integrated.enableMultiLinePasteWarning`; "Do not ask me
  /// again" sets it to `never`.
  TerminalMultiLinePasteWarning multiLinePasteWarning;

  String? _primarySelection;

  /// Runs a keybinding's [command].
  Future<void> run(TerminalClipboardCommand command) async {
    switch (command) {
      case TerminalClipboardCommand.copySelection:
        await copySelection();
      case TerminalClipboardCommand.copyAndClearSelection:
        await copySelection();
        selection.clearSelection();
      case TerminalClipboardCommand.paste:
        await paste();
      case TerminalClipboardCommand.pasteSelection:
        await pasteSelection();
    }
  }

  /// Copies the selected text, if any.
  Future<void> copySelection() async {
    if (!selection.hasSelection) {
      return;
    }
    await _writeText(selection.selectionText);
  }

  /// Pastes the clipboard's text.
  Future<void> paste() async {
    final text = await _readText();
    if (text == null || text.isEmpty) {
      return;
    }
    await pasteText(text);
  }

  /// Pastes the primary selection (the last mouse selection, on Linux).
  Future<void> pasteSelection() async {
    final text = _primarySelection;
    if (text == null || text.isEmpty) {
      return;
    }
    await pasteText(text);
  }

  /// The data pasting [text] sends in the current modes, without the
  /// multi-line check.
  String pasteData(String text) => terminalPasteData(
    text,
    bracketedPasteMode: _coreService.decPrivateModes.bracketedPasteMode,
    ignoreBracketedPasteMode:
        _optionsService.rawOptions.ignoreBracketedPasteMode,
  );

  /// Pastes [text] after the multi-line paste check. Returns whether it was
  /// pasted.
  Future<bool> pasteText(String text) async {
    final bracketedPasteMode = _coreService.decPrivateModes.bracketedPasteMode;
    final check = checkTerminalPaste(
      text,
      bracketedPasteMode: bracketedPasteMode,
      warning: multiLinePasteWarning,
    );
    var currentText = check.text;
    final prompt = check.prompt;
    final confirm = confirmPaste;
    if (prompt != null) {
      if (confirm == null) {
        currentText = text;
      } else {
        final answer = await confirm(prompt);
        if (answer.choice == TerminalPasteChoice.cancel) {
          return false;
        }
        if (answer.doNotAskAgain) {
          multiLinePasteWarning = TerminalMultiLinePasteWarning.never;
        }
        currentText = answer.choice == TerminalPasteChoice.pasteAsOneLine
            ? text.replaceAll(_lineBreaks, '')
            : text;
      }
    }
    xterm_clipboard.paste(currentText!, _coreService, _optionsService);
    return true;
  }
}
