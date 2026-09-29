/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/common/cursorCommon.ts plus the undo-stop
// helpers at the end of cursor/cursorTypeEditOperations.ts, at
// 6a598d4a13031703d483d103c1d934a36ad27971, and normalizeIndentation from
// core/misc/indentation.ts. CursorConfiguration keeps only the options the
// ported operations read (with upstream defaults); cursor states and the view
// model are not ported. `standardTokenTypeAt` replaces tokenization lookups.

import '../core/cursor_columns.dart';
import '../core/position.dart';
import '../core/word_character_classifier.dart';
import '../languages/language_configuration.dart';
import '../languages/language_configuration_registry.dart';

/// The read-only line access that cursor operations need.
abstract interface class ICursorSimpleModel {
  int getLineCount();
  String getLineContent(int lineNumber);
  int getLineMinColumn(int lineNumber);
  int getLineMaxColumn(int lineNumber);
  int getLineFirstNonWhitespaceColumn(int lineNumber);
  int getLineLastNonWhitespaceColumn(int lineNumber);
}

enum EditOperationType {
  other,
  deletingLeft,
  deletingRight,
  typingOther,
  typingFirstSpace,
  typingConsecutiveSpace,
}

bool isQuote(String ch) => ch == "'" || ch == '"' || ch == '`';

bool isTypingOperation(EditOperationType type) =>
    type == EditOperationType.typingOther ||
    type == EditOperationType.typingFirstSpace ||
    type == EditOperationType.typingConsecutiveSpace;

EditOperationType getTypingOperation(
  String typedText,
  EditOperationType previousTypingOperation,
) {
  if (typedText == ' ') {
    return previousTypingOperation == EditOperationType.typingFirstSpace ||
            previousTypingOperation == EditOperationType.typingConsecutiveSpace
        ? EditOperationType.typingConsecutiveSpace
        : EditOperationType.typingFirstSpace;
  }
  return EditOperationType.typingOther;
}

bool shouldPushStackElementBetween(
  EditOperationType previousTypingOperation,
  EditOperationType typingOperation,
) {
  if (isTypingOperation(previousTypingOperation) &&
      !isTypingOperation(typingOperation)) {
    // Always set an undo stop before non-type operations
    return true;
  }
  if (previousTypingOperation == EditOperationType.typingFirstSpace) {
    // `abc |d`: No undo stop
    // `abc  |d`: Undo stop
    return false;
  }
  // Insert undo stop between different operation types
  return _normalize(previousTypingOperation) != _normalize(typingOperation);
}

Object _normalize(EditOperationType type) =>
    type == EditOperationType.typingConsecutiveSpace ||
        type == EditOperationType.typingFirstSpace
    ? 'space'
    : type;

/// Leading whitespace (spaces and tabs) of [text], like strings.getLeadingWhitespace.
String getLeadingWhitespace(String text, [int start = 0, int? end]) {
  end ??= text.length;
  for (var i = start; i < end; i++) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return text.substring(start, i);
  }
  return text.substring(start, end);
}

/// strings.firstNonWhitespaceIndex: -1 when [text] is only spaces/tabs.
int firstNonWhitespaceIndex(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return i;
  }
  return -1;
}

/// strings.lastNonWhitespaceIndex, scanning backwards from [startIndex].
int lastNonWhitespaceIndex(String text, [int? startIndex]) {
  for (var i = startIndex ?? text.length - 1; i >= 0; i--) {
    final c = text.codeUnitAt(i);
    if (c != 0x20 && c != 0x09) return i;
  }
  return -1;
}

/// normalizeIndentation (core/misc/indentation.ts): rewrites the leading
/// whitespace of [str] with tabs/spaces for [indentSize]/[insertSpaces].
String normalizeIndentation(String str, int indentSize, bool insertSpaces) {
  var firstNonWhitespace = firstNonWhitespaceIndex(str);
  if (firstNonWhitespace == -1) firstNonWhitespace = str.length;
  var spacesCnt = 0;
  for (var i = 0; i < firstNonWhitespace; i++) {
    spacesCnt = str.codeUnitAt(i) == 0x09
        ? CursorColumns.nextIndentTabStop(spacesCnt, indentSize)
        : spacesCnt + 1;
  }
  final result = StringBuffer();
  if (!insertSpaces) {
    result.write('\t' * (spacesCnt ~/ indentSize));
    spacesCnt = spacesCnt % indentSize;
  }
  result.write(' ' * spacesCnt);
  return result.toString() + str.substring(firstNonWhitespace);
}

/// Upstream EditorAutoClosingStrategy / EditorAutoClosingEditStrategy /
/// EditorAutoSurroundStrategy values.
enum AutoClosingStrategy { always, languageDefined, beforeWhitespace, never }

enum AutoClosingEditStrategy { always, auto, never }

enum AutoSurroundStrategy { languageDefined, quotes, brackets, never }

/// Returns a StandardTokenType for the character before one-based [column].
typedef StandardTokenTypeAt = int? Function(
  ICursorSimpleModel model,
  int lineNumber,
  int column,
);

class CursorConfiguration {
  CursorConfiguration({
    this.tabSize = 4,
    int? indentSize,
    this.insertSpaces = true,
    this.useTabStops = true,
    this.autoIndent = EditorAutoIndentStrategy.full,
    this.wordSeparators = usualWordSeparators,
    this.language,
    this.autoClosingBrackets = AutoClosingStrategy.languageDefined,
    this.autoClosingQuotes = AutoClosingStrategy.languageDefined,
    this.autoClosingComments = AutoClosingStrategy.languageDefined,
    this.autoClosingOvertype = AutoClosingEditStrategy.auto,
    this.autoClosingDelete = AutoClosingEditStrategy.auto,
    this.autoSurround = AutoSurroundStrategy.languageDefined,
    this.trimWhitespaceOnDelete = false,
    this.emptySelectionClipboard = true,
    this.multiCursorPasteSpread = true,
    this.standardTokenTypeAt,
  }) : indentSize = indentSize ?? tabSize;

  final int tabSize;
  final int indentSize;
  final bool insertSpaces;
  final bool useTabStops;
  final EditorAutoIndentStrategy autoIndent;
  final String wordSeparators;

  /// Null means no language rules: no auto-closing, surrounding, electric
  /// characters or enter rules (unlike upstream, which always has plaintext).
  final ResolvedLanguageConfiguration? language;
  final AutoClosingStrategy autoClosingBrackets;
  final AutoClosingStrategy autoClosingQuotes;
  final AutoClosingStrategy autoClosingComments;
  final AutoClosingEditStrategy autoClosingOvertype;
  final AutoClosingEditStrategy autoClosingDelete;
  final AutoSurroundStrategy autoSurround;
  final bool trimWhitespaceOnDelete;
  final bool emptySelectionClipboard;
  final bool multiCursorPasteSpread;
  final StandardTokenTypeAt? standardTokenTypeAt;

  late final WordCharacterClassifier wordClassifier = getMapForWordSeparators(
    wordSeparators,
  );

  late final AutoClosingPairs autoClosingPairs =
      language?.autoClosingPairs ?? AutoClosingPairs(const []);

  Map<String, String> get surroundingPairs =>
      language?.surroundingPairs ?? const {};

  Map<String, String> get electricChars =>
      language?.electricCharacters ?? const {};

  String? get blockCommentStartToken =>
      language?.comments?.blockCommentStartToken;

  bool shouldAutoCloseBefore(String ch, {required bool quote}) {
    final strategy = quote ? autoClosingQuotes : autoClosingBrackets;
    return switch (strategy) {
      AutoClosingStrategy.always => true,
      AutoClosingStrategy.never => false,
      AutoClosingStrategy.beforeWhitespace =>
        CharacterPairSupportDefaults.whitespace.contains(ch),
      AutoClosingStrategy.languageDefined =>
        (language?.getAutoCloseBeforeSet(quote) ?? '').contains(ch),
    };
  }

  String normalize(String indentation) =>
      normalizeIndentation(indentation, indentSize, insertSpaces);

  int visibleColumnFromColumn(ICursorSimpleModel model, Position position) =>
      CursorColumns.visibleColumnFromColumn(
        model.getLineContent(position.lineNumber),
        position.column,
        tabSize,
      );

  int columnFromVisibleColumn(
    ICursorSimpleModel model,
    int lineNumber,
    int visibleColumn,
  ) {
    final result = CursorColumns.columnFromVisibleColumn(
      model.getLineContent(lineNumber),
      visibleColumn,
      tabSize,
    );
    final minColumn = model.getLineMinColumn(lineNumber);
    if (result < minColumn) return minColumn;
    final maxColumn = model.getLineMaxColumn(lineNumber);
    return result > maxColumn ? maxColumn : result;
  }
}

abstract final class CharacterPairSupportDefaults {
  static const whitespace = ' \n\t';
}
