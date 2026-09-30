// Copyright (c) 2016 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Ported from xterm.js src/browser/Clipboard.ts (c58ea36).
//
// Subset: the text preparation and `paste`. The DOM handlers (`copyHandler`,
// `handlePasteEvent`, `moveTextAreaUnderMouseCursor`, `rightClickHandler`)
// work on the ClipboardEvent and the helper textarea and are not ported;
// `paste` has no textarea to clear.

import '../common/services/services.dart';

final RegExp _newlines = RegExp(r'\r?\n');

/// Prepares text to be pasted into the terminal by normalizing the line
/// endings.
String prepareTextForTerminal(String text) {
  return text.replaceAll(_newlines, '\r');
}

/// Bracket text for paste, if necessary, as per
/// https://cirw.in/blog/bracketed-paste
String bracketTextForPaste(String text, bool bracketedPasteMode) {
  if (!bracketedPasteMode) {
    return text;
  }
  // Sanitize pasted text to prevent injected escape sequences (e.g. exiting
  // bracketed paste) by replacing ESC (\x1b) with its visible representation
  // U+241B (␛).
  final sanitizedText = text.replaceAll('\x1b', '␛');
  return '\x1b[200~$sanitizedText\x1b[201~';
}

/// Upstream's `paste(text, textarea, coreService, optionsService)` without
/// the textarea.
void paste(
  String text,
  ICoreService coreService,
  IOptionsService optionsService,
) {
  text = prepareTextForTerminal(text);
  text = bracketTextForPaste(
    text,
    coreService.decPrivateModes.bracketedPasteMode &&
        optionsService.rawOptions.ignoreBracketedPasteMode != true,
  );
  coreService.triggerDataEvent(text, true);
}
