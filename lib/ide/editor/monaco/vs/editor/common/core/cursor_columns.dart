// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
// Ported from pinned VS Code src/vs/editor/common/core/cursorColumns.ts.

import '../../../base/common/strings_cursor.dart' as strings;

/// One-based UTF-16 columns and zero-based approximate visual positions.
/// Visual positions are not reliable for RTL text or variable-width fonts.
class CursorColumns {
  CursorColumns._();

  static int _nextVisibleColumn(int point, int visibleColumn, int tabSize) {
    if (point == 9) return nextRenderTabStop(visibleColumn, tabSize);
    if (strings.isFullWidthCharacter(point) ||
        strings.isEmojiImprecise(point)) {
      return visibleColumn + 2;
    }
    return visibleColumn + 1;
  }

  static int visibleColumnFromColumn(
    String lineContent,
    int column,
    int tabSize,
  ) {
    final textLength = (column - 1).clamp(0, lineContent.length);
    final text = lineContent.substring(0, textLength);
    final iterator = strings.GraphemeIterator(text);
    var result = 0;
    while (!iterator.eol()) {
      final point = strings.getNextCodePoint(text, textLength, iterator.offset);
      iterator.nextGraphemeLength();
      result = _nextVisibleColumn(point, result, tabSize);
    }
    return result;
  }

  /// Status bar width counts code points rather than graphemes or screen cells.
  static int toStatusbarColumn(String lineContent, int column, int tabSize) {
    final text = lineContent.substring(
      0,
      (column - 1).clamp(0, lineContent.length),
    );
    final iterator = strings.CodePointIterator(text);
    var result = 0;
    while (!iterator.eol()) {
      final point = iterator.nextCodePoint();
      result = point == 9 ? nextRenderTabStop(result, tabSize) : result + 1;
    }
    return result + 1;
  }

  static int columnFromVisibleColumn(
    String lineContent,
    int visibleColumn,
    int tabSize,
  ) {
    if (visibleColumn <= 0) return 1;
    final iterator = strings.GraphemeIterator(lineContent);
    var beforeVisibleColumn = 0;
    var beforeColumn = 1;
    while (!iterator.eol()) {
      final point = strings.getNextCodePoint(
        lineContent,
        lineContent.length,
        iterator.offset,
      );
      iterator.nextGraphemeLength();
      final afterVisibleColumn = _nextVisibleColumn(
        point,
        beforeVisibleColumn,
        tabSize,
      );
      final afterColumn = iterator.offset + 1;
      if (afterVisibleColumn >= visibleColumn) {
        final beforeDelta = visibleColumn - beforeVisibleColumn;
        final afterDelta = afterVisibleColumn - visibleColumn;
        return afterDelta < beforeDelta ? afterColumn : beforeColumn;
      }
      beforeVisibleColumn = afterVisibleColumn;
      beforeColumn = afterColumn;
    }
    return lineContent.length + 1;
  }

  /// All tab-stop methods accept zero-based visual positions.
  static int nextRenderTabStop(int visibleColumn, int tabSize) =>
      visibleColumn + tabSize - visibleColumn % tabSize;

  static int nextIndentTabStop(int visibleColumn, int indentSize) =>
      nextRenderTabStop(visibleColumn, indentSize);

  static int prevRenderTabStop(int column, int tabSize) {
    final previous = column - 1 - (column - 1) % tabSize;
    return previous < 0 ? 0 : previous;
  }

  static int prevIndentTabStop(int column, int indentSize) =>
      prevRenderTabStop(column, indentSize);
}
