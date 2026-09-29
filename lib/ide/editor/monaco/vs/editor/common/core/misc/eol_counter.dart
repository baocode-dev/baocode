/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/core/misc/eolCounter.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.

enum StringEOL {
  unknown(0),
  lf(1),
  crlf(2),
  invalid(3);

  const StringEOL(this.value);
  final int value;
}

/// Counts line endings and UTF-16 code units on the first and last lines.
/// A bare CR or a mixture of LF and CRLF gives [StringEOL.invalid].
(int, int, int, StringEOL) countEOL(String text) {
  var eolCount = 0;
  var firstLineLength = 0;
  var lastLineStart = 0;
  var eol = 0;
  for (var i = 0; i < text.length; i++) {
    final chr = text.codeUnitAt(i);
    if (chr == 13) {
      if (eolCount == 0) {
        firstLineLength = i;
      }
      eolCount++;
      if (i + 1 < text.length && text.codeUnitAt(i + 1) == 10) {
        eol |= StringEOL.crlf.value;
        i++;
      } else {
        eol |= StringEOL.invalid.value;
      }
      lastLineStart = i + 1;
    } else if (chr == 10) {
      eol |= StringEOL.lf.value;
      if (eolCount == 0) {
        firstLineLength = i;
      }
      eolCount++;
      lastLineStart = i + 1;
    }
  }
  if (eolCount == 0) {
    firstLineLength = text.length;
  }
  return (
    eolCount,
    firstLineLength,
    text.length - lastLineStart,
    StringEOL.values[eol],
  );
}
