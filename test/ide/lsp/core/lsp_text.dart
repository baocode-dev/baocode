/// A reference for how a language server applies `contentChanges`: lines
/// broken at CRLF, CR and LF; a character past a line's end means its end.
library;

import 'package:baocode/ide/editor/monaco/flutter/editor_document_model.dart';

int lspOffset(String text, int line, int character) {
  var offset = 0;
  for (var i = 0; i < line; i++) {
    var next = offset;
    while (next < text.length &&
        text.codeUnitAt(next) != 0x0A &&
        text.codeUnitAt(next) != 0x0D) {
      next++;
    }
    if (next >= text.length) return text.length;
    offset =
        next +
        (text.codeUnitAt(next) == 0x0D &&
                next + 1 < text.length &&
                text.codeUnitAt(next + 1) == 0x0A
            ? 2
            : 1);
  }
  var end = offset;
  while (end < text.length &&
      text.codeUnitAt(end) != 0x0A &&
      text.codeUnitAt(end) != 0x0D) {
    end++;
  }
  return offset + character > end ? end : offset + character;
}

String applyLspChanges(String text, Iterable<EditorContentChange> changes) {
  for (final change in changes) {
    final start = lspOffset(text, change.startLine, change.startCharacter);
    final end = lspOffset(text, change.endLine, change.endCharacter);
    text = text.replaceRange(start, end, change.text);
  }
  return text;
}
