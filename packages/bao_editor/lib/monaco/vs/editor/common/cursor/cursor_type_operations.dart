/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/cursor/cursorTypeOperations.ts and
// cursorTypeEditOperations.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
//
// Deviations:
// - Commands use the local CursorCommand contract (commands/cursor_command.dart).
// - Tokenization is replaced by [CursorConfiguration.standardTokenTypeAt]
//   (null: every position is "other"); `isCheapToTokenize` is always true.
// - `bracketPairs.hasUnmatchedClosingBracketAfter` only scans the rest of the
//   current line, and electric characters find the matching open bracket by
//   counting brackets backwards (no string/comment awareness, at most
//   [_maxBracketSearchLines] lines) for non-word brackets only.
// - Overtype input mode and the composition "overtype" operations are absent.

import '../commands/cursor_command.dart';
import '../commands/shift_command.dart';
import '../core/position.dart';
import '../core/range.dart';
import '../core/selection.dart';
import '../core/word_character_classifier.dart';
import '../languages/auto_indent.dart';
import '../languages/enter_action.dart';
import '../languages/language_configuration.dart';
import '../languages/language_configuration_registry.dart';
import 'cursor_common.dart';

class EditOperationResult {
  EditOperationResult(
    this.type,
    this.commands, {
    required this.shouldPushStackElementBefore,
    required this.shouldPushStackElementAfter,
  });

  final EditOperationType type;
  final List<CursorCommand?> commands;
  final bool shouldPushStackElementBefore;
  final bool shouldPushStackElementAfter;
}

String shiftIndent(
  CursorConfiguration config,
  String indentation, [
  int count = 1,
]) => ShiftCommand.shiftIndent(
  indentation,
  indentation.length + count,
  config.tabSize,
  config.indentSize,
  config.insertSpaces,
);

String unshiftIndent(
  CursorConfiguration config,
  String indentation, [
  int count = 1,
]) => ShiftCommand.unshiftIndent(
  indentation,
  indentation.length + count,
  config.tabSize,
  config.indentSize,
  config.insertSpaces,
);

class _IndentConverter implements IndentConverter {
  _IndentConverter(this.config);

  final CursorConfiguration config;

  @override
  String shiftIndent(String indentation) => _shift(config, indentation);

  @override
  String unshiftIndent(String indentation) => _unshift(config, indentation);

  @override
  String normalizeIndentation(String indentation) =>
      config.normalize(indentation);
}

String _shift(CursorConfiguration c, String i) => shiftIndent(c, i);
String _unshift(CursorConfiguration c, String i) => unshiftIndent(c, i);

bool shouldSurroundChar(CursorConfiguration config, String ch) {
  if (isQuote(ch)) {
    return config.autoSurround == AutoSurroundStrategy.quotes ||
        config.autoSurround == AutoSurroundStrategy.languageDefined;
  }
  // Character is a bracket
  return config.autoSurround == AutoSurroundStrategy.brackets ||
      config.autoSurround == AutoSurroundStrategy.languageDefined;
}

CursorCommand _typeCommand(Range range, String text, bool keepPosition) =>
    keepPosition
    ? ReplaceCommandWithoutChangingPosition(
        range,
        text,
        insertsAutoWhitespace: true,
      )
    : ReplaceCommand(range, text, insertsAutoWhitespace: true);

String _valueInRange(ICursorSimpleModel model, Range range) {
  if (range.startLineNumber == range.endLineNumber) {
    return model
        .getLineContent(range.startLineNumber)
        .substring(range.startColumn - 1, range.endColumn - 1);
  }
  final result = StringBuffer(
    model
        .getLineContent(range.startLineNumber)
        .substring(range.startColumn - 1),
  );
  for (
    var line = range.startLineNumber + 1;
    line < range.endLineNumber;
    line++
  ) {
    result
      ..write('\n')
      ..write(model.getLineContent(line));
  }
  result
    ..write('\n')
    ..write(
      model
          .getLineContent(range.endLineNumber)
          .substring(0, range.endColumn - 1),
    );
  return result.toString();
}

abstract final class TypeOperations {
  static List<CursorCommand> indent(
    CursorConfiguration config,
    List<Selection> selections,
  ) => [
    for (final selection in selections)
      ShiftCursorCommand(selection, _shiftOptions(config, isUnshift: false)),
  ];

  static List<CursorCommand> outdent(
    CursorConfiguration config,
    List<Selection> selections,
  ) => [
    for (final selection in selections)
      ShiftCursorCommand(selection, _shiftOptions(config, isUnshift: true)),
  ];

  static ShiftCommandOptions _shiftOptions(
    CursorConfiguration config, {
    required bool isUnshift,
  }) => ShiftCommandOptions(
    isUnshift: isUnshift,
    tabSize: config.tabSize,
    indentSize: config.indentSize,
    insertSpaces: config.insertSpaces,
    useTabStops: config.useTabStops,
  );

  // ---- paste ---------------------------------------------------------------

  static EditOperationResult paste(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    String text,
    bool pasteOnNewLine,
    List<String>? multicursorText,
  ) {
    final distributed = _distributePasteToCursors(
      config,
      selections,
      text,
      pasteOnNewLine,
      multicursorText,
    );
    final commands = <CursorCommand?>[];
    if (distributed != null) {
      // Upstream sorts the selections; the i-th text goes to the i-th
      // selection in document order.
      final order = List<int>.generate(selections.length, (i) => i)
        ..sort(
          (a, b) =>
              Range.compareRangesUsingStarts(selections[a], selections[b]),
        );
      commands.length = selections.length;
      for (var i = 0; i < order.length; i++) {
        commands[order[i]] = ReplaceCommand(
          selections[order[i]],
          distributed[i],
        );
      }
    } else {
      for (final selection in selections) {
        final position = selection.getPosition();
        var onNewLine = pasteOnNewLine;
        if (onNewLine && !selection.isEmpty()) onNewLine = false;
        if (onNewLine && text.indexOf('\n') != text.length - 1) {
          onNewLine = false;
        }
        if (onNewLine) {
          // Paste entire line at the beginning of line
          commands.add(
            ReplaceCommandThatPreservesSelection(
              Range(position.lineNumber, 1, position.lineNumber, 1),
              text,
              selection,
            ),
          );
        } else {
          commands.add(ReplaceCommand(selection, text));
        }
      }
    }
    return EditOperationResult(
      EditOperationType.other,
      commands,
      shouldPushStackElementBefore: true,
      shouldPushStackElementAfter: true,
    );
  }

  static List<String>? _distributePasteToCursors(
    CursorConfiguration config,
    List<Selection> selections,
    String text,
    bool pasteOnNewLine,
    List<String>? multicursorText,
  ) {
    if (selections.length == 1) return null;
    if (multicursorText != null &&
        multicursorText.length == selections.length) {
      return multicursorText;
    }
    if (pasteOnNewLine) return null;
    if (config.multiCursorPasteSpread) {
      // Try to spread the pasted text in case the line count matches the
      // cursor count. Remove trailing \n and \r if present.
      if (text.endsWith('\n')) text = text.substring(0, text.length - 1);
      if (text.endsWith('\r')) text = text.substring(0, text.length - 1);
      final lines = text.split(RegExp(r'\r\n|\r|\n'));
      if (lines.length == selections.length) return lines;
    }
    return null;
  }

  // ---- tab -----------------------------------------------------------------

  static List<CursorCommand> tab(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
  ) {
    final commands = <CursorCommand>[];
    for (final selection in selections) {
      if (selection.isEmpty()) {
        final lineText = model.getLineContent(selection.startLineNumber);
        if (lineText.trim().isEmpty) {
          final goodIndent =
              _goodIndentForLine(config, model, selection.startLineNumber) ??
              '\t';
          final possibleTypeText = config.normalize(goodIndent);
          if (!lineText.startsWith(possibleTypeText)) {
            commands.add(
              ReplaceCommand(
                Range(
                  selection.startLineNumber,
                  1,
                  selection.startLineNumber,
                  lineText.length + 1,
                ),
                possibleTypeText,
                insertsAutoWhitespace: true,
              ),
            );
            continue;
          }
        }
        commands.add(_replaceJumpToNextIndent(config, model, selection, true));
      } else {
        if (selection.startLineNumber == selection.endLineNumber) {
          final lineMaxColumn = model.getLineMaxColumn(
            selection.startLineNumber,
          );
          if (selection.startColumn != 1 ||
              selection.endColumn != lineMaxColumn) {
            // This is a single line selection that is not the entire line
            commands.add(
              _replaceJumpToNextIndent(config, model, selection, false),
            );
            continue;
          }
        }
        commands.add(
          ShiftCursorCommand(
            selection,
            _shiftOptions(config, isUnshift: false),
          ),
        );
      }
    }
    return commands;
  }

  static String? _goodIndentForLine(
    CursorConfiguration config,
    ICursorSimpleModel model,
    int lineNumber,
  ) {
    final language = config.language;
    if (language == null) return null;
    IndentAction? action;
    var indentation = '';
    final expected = getInheritIndentForLine(
      config.autoIndent,
      model,
      lineNumber,
      language,
      honorIntentialIndent: false,
    );
    if (expected != null) {
      action = expected.action;
      indentation = expected.indentation;
    } else if (lineNumber > 1) {
      var lastLineNumber = lineNumber - 1;
      for (; lastLineNumber >= 1; lastLineNumber--) {
        if (lastNonWhitespaceIndex(model.getLineContent(lastLineNumber)) >= 0) {
          break;
        }
      }
      if (lastLineNumber < 1) {
        // No previous line with content found
        return null;
      }
      final maxColumn = model.getLineMaxColumn(lastLineNumber);
      final expectedEnterAction = getEnterAction(
        config.autoIndent,
        model,
        Range(lastLineNumber, maxColumn, lastLineNumber, maxColumn),
        language,
      );
      if (expectedEnterAction != null) {
        indentation =
            expectedEnterAction.indentation + expectedEnterAction.appendText;
      }
    }
    if (action != null) {
      if (action == IndentAction.indent) {
        indentation = shiftIndent(config, indentation);
      }
      if (action == IndentAction.outdent) {
        indentation = unshiftIndent(config, indentation);
      }
      indentation = config.normalize(indentation);
    }
    return indentation.isEmpty ? null : indentation;
  }

  static ReplaceCommand _replaceJumpToNextIndent(
    CursorConfiguration config,
    ICursorSimpleModel model,
    Selection selection,
    bool insertsAutoWhitespace,
  ) {
    var typeText = '';
    final position = selection.getStartPosition();
    if (config.insertSpaces) {
      final visibleColumn = config.visibleColumnFromColumn(model, position);
      final indentSize = config.indentSize;
      typeText = ' ' * (indentSize - (visibleColumn % indentSize));
    } else {
      typeText = '\t';
    }
    return ReplaceCommand(
      selection,
      typeText,
      insertsAutoWhitespace: insertsAutoWhitespace,
    );
  }

  // ---- enter ---------------------------------------------------------------

  static CursorCommand enter(
    CursorConfiguration config,
    ICursorSimpleModel model,
    bool keepPosition,
    Range range,
  ) {
    if (config.autoIndent == EditorAutoIndentStrategy.none) {
      return _typeCommand(range, '\n', keepPosition);
    }
    final language = config.language;
    if (language == null ||
        config.autoIndent == EditorAutoIndentStrategy.keep) {
      final lineText = model.getLineContent(range.startLineNumber);
      var indentation = getLeadingWhitespace(lineText);
      if (indentation.length > range.startColumn - 1) {
        indentation = indentation.substring(0, range.startColumn - 1);
      }
      return _typeCommand(
        range,
        '\n${config.normalize(indentation)}',
        keepPosition,
      );
    }
    final r = getEnterAction(config.autoIndent, model, range, language);
    if (r != null) {
      switch (r.indentAction) {
        case IndentAction.none:
        case IndentAction.indent:
          return _typeCommand(
            range,
            '\n${config.normalize(r.indentation + r.appendText)}',
            keepPosition,
          );
        case IndentAction.indentOutdent:
          final normalIndent = config.normalize(r.indentation);
          final increasedIndent = config.normalize(
            r.indentation + r.appendText,
          );
          final typeText = '\n$increasedIndent\n$normalIndent';
          if (keepPosition) {
            return ReplaceCommandWithoutChangingPosition(
              range,
              typeText,
              insertsAutoWhitespace: true,
            );
          }
          return ReplaceCommandWithOffsetCursorState(
            range,
            typeText,
            -1,
            increasedIndent.length - normalIndent.length,
            insertsAutoWhitespace: true,
          );
        case IndentAction.outdent:
          final actualIndentation = unshiftIndent(config, r.indentation);
          return _typeCommand(
            range,
            '\n${config.normalize(actualIndentation + r.appendText)}',
            keepPosition,
          );
      }
    }
    final lineText = model.getLineContent(range.startLineNumber);
    var indentation = getLeadingWhitespace(lineText);
    if (indentation.length > range.startColumn - 1) {
      indentation = indentation.substring(0, range.startColumn - 1);
    }
    if (config.autoIndent.index >= EditorAutoIndentStrategy.full.index) {
      final ir = getIndentForEnter(
        config.autoIndent,
        model,
        range,
        _IndentConverter(config),
        language,
      );
      if (ir != null) {
        var oldEndViewColumn = config.visibleColumnFromColumn(
          model,
          range.getEndPosition(),
        );
        final oldEndColumn = range.endColumn;
        final newLineContent = model.getLineContent(range.endLineNumber);
        final firstNonWhitespace = firstNonWhitespaceIndex(newLineContent);
        if (firstNonWhitespace >= 0) {
          range = range.setEndPosition(
            range.endLineNumber,
            range.endColumn > firstNonWhitespace + 1
                ? range.endColumn
                : firstNonWhitespace + 1,
          );
        } else {
          range = range.setEndPosition(
            range.endLineNumber,
            model.getLineMaxColumn(range.endLineNumber),
          );
        }
        final afterEnter = config.normalize(ir.afterEnter);
        if (keepPosition) {
          return ReplaceCommandWithoutChangingPosition(
            range,
            '\n$afterEnter',
            insertsAutoWhitespace: true,
          );
        }
        var offset = 0;
        if (oldEndColumn <= firstNonWhitespace + 1) {
          if (!config.insertSpaces) {
            oldEndViewColumn = (oldEndViewColumn / config.indentSize).ceil();
          }
          offset = oldEndViewColumn + 1 - afterEnter.length - 1;
          if (offset > 0) offset = 0;
        }
        return ReplaceCommandWithOffsetCursorState(
          range,
          '\n$afterEnter',
          0,
          offset,
          insertsAutoWhitespace: true,
        );
      }
    }
    return _typeCommand(
      range,
      '\n${config.normalize(indentation)}',
      keepPosition,
    );
  }

  static List<CursorCommand> lineInsertBefore(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
  ) => [
    for (final selection in selections)
      if (selection.positionLineNumber == 1)
        ReplaceCommandWithoutChangingPosition(Range(1, 1, 1, 1), '\n')
      else
        enter(
          config,
          model,
          false,
          Range(
            selection.positionLineNumber - 1,
            model.getLineMaxColumn(selection.positionLineNumber - 1),
            selection.positionLineNumber - 1,
            model.getLineMaxColumn(selection.positionLineNumber - 1),
          ),
        ),
  ];

  static List<CursorCommand> lineInsertAfter(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
  ) => [
    for (final selection in selections)
      enter(
        config,
        model,
        false,
        Range(
          selection.positionLineNumber,
          model.getLineMaxColumn(selection.positionLineNumber),
          selection.positionLineNumber,
          model.getLineMaxColumn(selection.positionLineNumber),
        ),
      ),
  ];

  /// lineBreakInsert (upstream `EnterOperation.lineBreakInsert`): an enter
  /// at each selection that keeps the cursor before the break.
  static List<CursorCommand> lineBreakInsert(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
  ) => [
    for (final selection in selections) enter(config, model, true, selection),
  ];

  // ---- typing --------------------------------------------------------------

  static EditOperationResult typeWithInterceptors(
    bool isDoingComposition,
    EditOperationType prevEditOperationType,
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    List<Range> autoClosedCharacters,
    String ch,
  ) {
    if (!isDoingComposition && ch == '\n') {
      return EditOperationResult(
        EditOperationType.typingOther,
        [for (final s in selections) enter(config, model, false, s)],
        shouldPushStackElementBefore: true,
        shouldPushStackElementAfter: false,
      );
    }
    if (!isDoingComposition) {
      final autoIndentEdits = _autoIndentEdits(config, model, selections, ch);
      if (autoIndentEdits != null) return autoIndentEdits;
    }
    if (_isAutoClosingOvertype(
      config,
      model,
      selections,
      autoClosedCharacters,
      ch,
    )) {
      return EditOperationResult(
        EditOperationType.typingOther,
        [
          for (final selection in selections)
            ReplaceCommand(
              Range(
                selection.positionLineNumber,
                selection.positionColumn,
                selection.positionLineNumber,
                selection.positionColumn + 1,
              ),
              ch,
            ),
        ],
        shouldPushStackElementBefore: shouldPushStackElementBetween(
          prevEditOperationType,
          EditOperationType.typingOther,
        ),
        shouldPushStackElementAfter: false,
      );
    }
    if (!isDoingComposition) {
      final close = getAutoClosingPairClose(
        config,
        model,
        selections,
        ch,
        false,
      );
      if (close != null) {
        return EditOperationResult(
          EditOperationType.typingOther,
          [
            for (final selection in selections)
              TypeWithAutoClosingCommand(selection, ch, true, close),
          ],
          shouldPushStackElementBefore: true,
          shouldPushStackElementAfter: false,
        );
      }
      if (_isSurroundSelectionType(config, model, selections, ch)) {
        return EditOperationResult(
          EditOperationType.other,
          [
            for (final selection in selections)
              SurroundSelectionCursorCommand(
                selection,
                ch,
                config.surroundingPairs[ch]!,
              ),
          ],
          shouldPushStackElementBefore: true,
          shouldPushStackElementAfter: true,
        );
      }
      // Electric characters make sense only when dealing with a single
      // cursor, as multiple cursors typing brackets would interfere with
      // bracket matching.
      if (selections.length == 1) {
        final electric = _typeInterceptorElectricChar(
          prevEditOperationType,
          config,
          model,
          selections.first,
          ch,
        );
        if (electric != null) return electric;
      }
    }
    return typeWithoutInterceptors(prevEditOperationType, selections, ch);
  }

  /// `compositionType` (`CompositionOperation.getEdits`): at each empty
  /// selection, [text] replaces [replacePrevCharCnt] characters before the
  /// caret and [replaceNextCharCnt] after it (within the line), the caret
  /// ending [positionDelta] columns from the inserted text's end. What the
  /// `replacePreviousChar` and `compositionType` commands do.
  static EditOperationResult compositionType(
    EditOperationType prevEditOperationType,
    ICursorSimpleModel model,
    List<Selection> selections,
    String text,
    int replacePrevCharCnt,
    int replaceNextCharCnt,
    int positionDelta,
  ) {
    CursorCommand? compositionType(Selection selection) {
      // A cursor operation before a canceled composition
      // (microsoft/vscode#2773): ignored.
      if (!selection.isEmpty()) return null;
      final pos = selection.getPosition();
      final startColumn = (pos.column - replacePrevCharCnt) < 1
          ? 1
          : pos.column - replacePrevCharCnt;
      final maxColumn = model.getLineMaxColumn(pos.lineNumber);
      final endColumn = pos.column + replaceNextCharCnt > maxColumn
          ? maxColumn
          : pos.column + replaceNextCharCnt;
      return ReplaceCommandWithOffsetCursorState(
        Range(pos.lineNumber, startColumn, pos.lineNumber, endColumn),
        text,
        0,
        positionDelta,
      );
    }

    return EditOperationResult(
      EditOperationType.typingOther,
      [for (final selection in selections) compositionType(selection)],
      shouldPushStackElementBefore: shouldPushStackElementBetween(
        prevEditOperationType,
        EditOperationType.typingOther,
      ),
      shouldPushStackElementAfter: false,
    );
  }

  static EditOperationResult typeWithoutInterceptors(
    EditOperationType prevEditOperationType,
    List<Selection> selections,
    String str,
  ) {
    final opType = getTypingOperation(str, prevEditOperationType);
    return EditOperationResult(
      opType,
      [for (final selection in selections) ReplaceCommand(selection, str)],
      shouldPushStackElementBefore: shouldPushStackElementBetween(
        prevEditOperationType,
        opType,
      ),
      shouldPushStackElementAfter: false,
    );
  }

  /// After a composition committed [ch] (already in the buffer before each
  /// caret), apply auto-closing overtype/open-char interceptors. Upstream
  /// compositionEndWithInterceptors without its surround and overtype modes.
  static EditOperationResult? compositionEndWithInterceptors(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    List<Range> autoClosedCharacters,
    String ch,
  ) {
    if (ch.length != 1) return null;
    // AutoClosingOvertypeWithInterceptorsOperation: the close character is
    // now "doubled"; check against the position before the typed character.
    final before = [
      for (final s in selections)
        Selection(
          s.positionLineNumber,
          s.positionColumn - 1,
          s.positionLineNumber,
          s.positionColumn - 1,
        ),
    ];
    final shifted = [
      for (final r in autoClosedCharacters)
        Range(
          r.startLineNumber,
          r.startColumn - 1,
          r.endLineNumber,
          r.endColumn,
        ),
    ];
    if (selections.every((s) => s.isEmpty() && s.positionColumn > 1) &&
        _isAutoClosingOvertypeAfterTyped(config, model, before, shifted, ch)) {
      return EditOperationResult(
        EditOperationType.typingOther,
        [
          for (final s in selections)
            ReplaceCommand(
              Range(
                s.positionLineNumber,
                s.positionColumn,
                s.positionLineNumber,
                s.positionColumn + 1,
              ),
              '',
            ),
        ],
        shouldPushStackElementBefore: true,
        shouldPushStackElementAfter: false,
      );
    }
    final close = getAutoClosingPairClose(config, model, selections, ch, true);
    if (close != null) {
      return EditOperationResult(
        EditOperationType.typingOther,
        [
          for (final selection in selections)
            TypeWithAutoClosingCommand(selection, ch, false, close),
        ],
        shouldPushStackElementBefore: true,
        shouldPushStackElementAfter: false,
      );
    }
    return null;
  }

  static bool _isAutoClosingOvertypeAfterTyped(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> before,
    List<Range> autoClosed,
    String ch,
  ) {
    // With `ch` already typed, the character after the caret is the old
    // auto-closed character: compare against the line without `ch`.
    for (final s in before) {
      final line = model.getLineContent(s.positionLineNumber);
      if (s.positionColumn + 1 > line.length || line[s.positionColumn] != ch) {
        return false;
      }
    }
    final virtual = [
      for (final s in before)
        Selection(
          s.positionLineNumber,
          s.positionColumn + 1,
          s.positionLineNumber,
          s.positionColumn + 1,
        ),
    ];
    return _isAutoClosingOvertype(
      config,
      model,
      virtual,
      [
        for (final r in autoClosed)
          Range(
            r.startLineNumber,
            r.startColumn + 1,
            r.endLineNumber,
            r.endColumn + 1,
          ),
      ],
      ch,
      beforeCharacterColumnDelta: -1,
    );
  }

  static EditOperationResult? _autoIndentEdits(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    String ch,
  ) {
    final language = config.language;
    if (language == null ||
        config.autoIndent.index < EditorAutoIndentStrategy.full.index ||
        language.indentRulesSupport == null) {
      return null;
    }
    final indentationForSelections = <(Selection, String)>[];
    for (final selection in selections) {
      final actualIndentation = getIndentActionForType(
        config.autoIndent,
        model,
        selection,
        ch,
        _IndentConverter(config),
        language,
      );
      if (actualIndentation == null) return null;
      var currentIndentation = getLeadingWhitespace(
        model.getLineContent(selection.startLineNumber),
      );
      if (currentIndentation.length > selection.startColumn - 1) {
        currentIndentation = currentIndentation.substring(
          0,
          selection.startColumn - 1,
        );
      }
      if (actualIndentation == config.normalize(currentIndentation)) {
        return null;
      }
      indentationForSelections.add((selection, actualIndentation));
    }
    final autoClosingPairClose = getAutoClosingPairClose(
      config,
      model,
      selections,
      ch,
      false,
    );
    final commands = <CursorCommand>[
      for (final (selection, indentation) in indentationForSelections)
        if (autoClosingPairClose != null)
          TypeWithIndentationAndAutoClosingCommand(
            _indentationEdit(config, model, indentation, selection, ch, false),
            selection,
            ch,
            autoClosingPairClose,
          )
        else
          () {
            final edit = _indentationEdit(
              config,
              model,
              indentation,
              selection,
              ch,
              true,
            );
            return _typeCommand(edit.range, edit.text, false);
          }(),
    ];
    return EditOperationResult(
      EditOperationType.typingOther,
      commands,
      shouldPushStackElementBefore: true,
      shouldPushStackElementAfter: false,
    );
  }

  static CursorCommandEdit _indentationEdit(
    CursorConfiguration config,
    ICursorSimpleModel model,
    String indentation,
    Selection selection,
    String ch,
    bool includeChInEdit,
  ) {
    final startLineNumber = selection.startLineNumber;
    final firstNonWhitespaceColumn = model.getLineFirstNonWhitespaceColumn(
      startLineNumber,
    );
    var text = config.normalize(indentation);
    if (firstNonWhitespaceColumn != 0) {
      final startLine = model.getLineContent(startLineNumber);
      text += startLine.substring(
        firstNonWhitespaceColumn - 1,
        selection.startColumn - 1,
      );
    }
    if (includeChInEdit) text += ch;
    return CursorCommandEdit(
      Range(startLineNumber, 1, selection.endLineNumber, selection.endColumn),
      text,
    );
  }

  static bool _isAutoClosingOvertype(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    List<Range> autoClosedCharacters,
    String ch, {
    int beforeCharacterColumnDelta = 0,
  }) {
    if (config.autoClosingOvertype == AutoClosingEditStrategy.never) {
      return false;
    }
    if (!config.autoClosingPairs.autoClosingPairsCloseSingleChar.containsKey(
      ch,
    )) {
      return false;
    }
    for (final selection in selections) {
      if (!selection.isEmpty()) return false;
      final position = selection.getPosition();
      final lineText = model.getLineContent(position.lineNumber);
      if (position.column - 1 >= lineText.length ||
          lineText[position.column - 1] != ch) {
        return false;
      }
      // Do not over-type quotes after a backslash
      final beforeIndex = position.column - 2 + beforeCharacterColumnDelta;
      final beforeCharacter = position.column > 2 && beforeIndex >= 0
          ? lineText.codeUnitAt(beforeIndex)
          : 0;
      if (beforeCharacter == 0x5C && isQuote(ch)) return false;
      // Must over-type a closing character typed by the editor
      if (config.autoClosingOvertype == AutoClosingEditStrategy.auto) {
        var found = false;
        for (final autoClosed in autoClosedCharacters) {
          if (position.lineNumber == autoClosed.startLineNumber &&
              position.column == autoClosed.startColumn) {
            found = true;
            break;
          }
        }
        if (!found) return false;
      }
    }
    return true;
  }

  static String? getAutoClosingPairClose(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    String ch,
    bool chIsAlreadyTyped,
  ) {
    if (config.language == null) return null;
    for (final selection in selections) {
      if (!selection.isEmpty()) return null;
    }
    // Work with two conceptual positions, before and after `ch`.
    final positions = [
      for (final s in selections)
        (
          lineNumber: s.positionLineNumber,
          beforeColumn: chIsAlreadyTyped
              ? s.positionColumn - ch.length
              : s.positionColumn,
          afterColumn: s.positionColumn,
        ),
    ];
    // Find the longest auto-closing open pair in case of multiple ending in `ch`
    final pair = _findAutoClosingPairOpen(config, model, [
      for (final p in positions) Position(p.lineNumber, p.beforeColumn),
    ], ch);
    if (pair == null) return null;
    AutoClosingStrategy autoCloseConfig;
    bool quote;
    var shouldCheckBracketBalance = false;
    final chIsQuote = isQuote(ch);
    if (chIsQuote) {
      autoCloseConfig = config.autoClosingQuotes;
      quote = true;
    } else {
      final blockStart = config.blockCommentStartToken;
      final pairIsForComments =
          blockStart != null && pair.open.contains(blockStart);
      if (pairIsForComments) {
        autoCloseConfig = config.autoClosingComments;
        quote = false;
      } else {
        autoCloseConfig = config.autoClosingBrackets;
        quote = false;
        shouldCheckBracketBalance = true;
      }
    }
    if (autoCloseConfig == AutoClosingStrategy.never) return null;
    // Two auto-closing pairs can contain each other, e.g. [(,)] and [(*,*)]
    final containedPair = _findContainedAutoClosingPair(config, pair);
    final containedPairClose = containedPair?.close ?? '';
    var isContainedPairPresent = true;
    for (final position in positions) {
      final lineText = model.getLineContent(position.lineNumber);
      final lineBefore = lineText.substring(0, position.beforeColumn - 1);
      final lineAfter = lineText.substring(position.afterColumn - 1);
      if (!lineAfter.startsWith(containedPairClose)) {
        isContainedPairPresent = false;
      }
      // Only consider auto closing the pair if an allowed character follows
      // or if another autoclosed pair closing brace follows
      if (lineAfter.isNotEmpty) {
        final characterAfter = lineAfter[0];
        final isBeforeCloseBrace = _isBeforeClosingBrace(config, lineAfter);
        if (!isBeforeCloseBrace &&
            !_shouldAutoCloseBefore(
              config,
              autoCloseConfig,
              characterAfter,
              quote,
            )) {
          return null;
        }
      }
      if (shouldCheckBracketBalance &&
          autoCloseConfig != AutoClosingStrategy.always &&
          !chIsAlreadyTyped &&
          _hasUnmatchedClosingBracketAfter(lineAfter, pair.open, pair.close)) {
        return null;
      }
      // Do not auto-close ' or " after a word character
      if (pair.open.length == 1 &&
          (ch == "'" || ch == '"') &&
          autoCloseConfig != AutoClosingStrategy.always) {
        if (lineBefore.isNotEmpty) {
          final characterBefore = lineBefore.codeUnitAt(lineBefore.length - 1);
          if (config.wordClassifier.get(characterBefore) ==
              WordCharacterClass.regular) {
            return null;
          }
        }
      }
      final tokenType = config.standardTokenTypeAt?.call(
        model,
        position.lineNumber,
        position.beforeColumn,
      );
      if (!pair.shouldAutoClose(tokenType)) return null;
    }
    return isContainedPairPresent
        ? pair.close.substring(0, pair.close.length - containedPairClose.length)
        : pair.close;
  }

  static bool _shouldAutoCloseBefore(
    CursorConfiguration config,
    AutoClosingStrategy strategy,
    String ch,
    bool quote,
  ) => switch (strategy) {
    AutoClosingStrategy.always => true,
    AutoClosingStrategy.never => false,
    AutoClosingStrategy.beforeWhitespace =>
      CharacterPairSupportDefaults.whitespace.contains(ch),
    AutoClosingStrategy.languageDefined =>
      (config.language?.getAutoCloseBeforeSet(quote) ?? '').contains(ch),
  };

  /// Approximates `bracketPairs.hasUnmatchedClosingBracketAfter` on the rest
  /// of the line only.
  static bool _hasUnmatchedClosingBracketAfter(
    String lineAfter,
    String open,
    String close,
  ) {
    if (open == close) return false;
    var depth = 0;
    for (var i = 0; i < lineAfter.length; i++) {
      if (lineAfter.startsWith(open, i)) {
        depth++;
        i += open.length - 1;
      } else if (lineAfter.startsWith(close, i)) {
        if (depth == 0) return true;
        depth--;
        i += close.length - 1;
      }
    }
    return false;
  }

  static StandardAutoClosingPairConditional? _findContainedAutoClosingPair(
    CursorConfiguration config,
    StandardAutoClosingPairConditional pair,
  ) {
    if (pair.open.length <= 1) return null;
    final lastChar = pair.close[pair.close.length - 1];
    final candidates =
        config.autoClosingPairs.autoClosingPairsCloseByEnd[lastChar] ??
        const [];
    StandardAutoClosingPairConditional? result;
    for (final candidate in candidates) {
      if (candidate.open != pair.open &&
          pair.open.contains(candidate.open) &&
          pair.close.endsWith(candidate.close)) {
        if (result == null || candidate.open.length > result.open.length) {
          result = candidate;
        }
      }
    }
    return result;
  }

  static StandardAutoClosingPairConditional? _findAutoClosingPairOpen(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Position> positions,
    String ch,
  ) {
    final candidates = config.autoClosingPairs.autoClosingPairsOpenByEnd[ch];
    if (candidates == null) return null;
    StandardAutoClosingPairConditional? result;
    for (final candidate in candidates) {
      if (result == null || candidate.open.length > result.open.length) {
        var candidateIsMatch = true;
        for (final position in positions) {
          final start = position.column - candidate.open.length + 1;
          final line = model.getLineContent(position.lineNumber);
          final relevantText = start < 1
              ? null
              : line.substring(start - 1, position.column - 1);
          if (relevantText == null || relevantText + ch != candidate.open) {
            candidateIsMatch = false;
            break;
          }
        }
        if (candidateIsMatch) result = candidate;
      }
    }
    return result;
  }

  static bool _isBeforeClosingBrace(
    CursorConfiguration config,
    String lineAfter,
  ) {
    // If the start of lineAfter can be interpreted as both a starting or
    // ending brace, default to returning false
    final nextChar = lineAfter[0];
    final potentialStartingBraces =
        config.autoClosingPairs.autoClosingPairsOpenByStart[nextChar] ??
        const [];
    final potentialClosingBraces =
        config.autoClosingPairs.autoClosingPairsCloseByStart[nextChar] ??
        const [];
    final isBeforeStartingBrace = potentialStartingBraces.any(
      (x) => lineAfter.startsWith(x.open),
    );
    final isBeforeClosingBrace = potentialClosingBraces.any(
      (x) => lineAfter.startsWith(x.close),
    );
    return !isBeforeStartingBrace && isBeforeClosingBrace;
  }

  static bool _isSurroundSelectionType(
    CursorConfiguration config,
    ICursorSimpleModel model,
    List<Selection> selections,
    String ch,
  ) {
    if (!shouldSurroundChar(config, ch) ||
        !config.surroundingPairs.containsKey(ch)) {
      return false;
    }
    final isTypingAQuoteCharacter = isQuote(ch);
    for (final selection in selections) {
      if (selection.isEmpty()) return false;
      var selectionContainsOnlyWhitespace = true;
      for (
        var lineNumber = selection.startLineNumber;
        lineNumber <= selection.endLineNumber;
        lineNumber++
      ) {
        final lineText = model.getLineContent(lineNumber);
        final startIndex = lineNumber == selection.startLineNumber
            ? selection.startColumn - 1
            : 0;
        final endIndex = lineNumber == selection.endLineNumber
            ? selection.endColumn - 1
            : lineText.length;
        if (RegExp(r'[^ \t]')
            .hasMatch(lineText.substring(startIndex, endIndex))) {
          // this selected text contains something other than whitespace
          selectionContainsOnlyWhitespace = false;
          break;
        }
      }
      if (selectionContainsOnlyWhitespace) return false;
      if (isTypingAQuoteCharacter &&
          selection.startLineNumber == selection.endLineNumber &&
          selection.startColumn + 1 == selection.endColumn) {
        if (isQuote(_valueInRange(model, selection))) {
          // Typing a quote character on top of another quote character
          return false;
        }
      }
    }
    return true;
  }

  static const int _maxBracketSearchLines = 5000;

  static EditOperationResult? _typeInterceptorElectricChar(
    EditOperationType prevEditOperationType,
    CursorConfiguration config,
    ICursorSimpleModel model,
    Selection selection,
    String ch,
  ) {
    final open = config.electricChars[ch];
    if (open == null || !selection.isEmpty()) return null;
    final position = selection.getPosition();
    final lineText = model.getLineContent(position.lineNumber);
    // onElectricCharacter: the typed text must complete a closing bracket
    // that is the first non-whitespace text on the line.
    String? close;
    for (final bracket in config.language!.underlyingConfig.brackets!) {
      final candidate = bracket.$2;
      if (bracket.$1 != open || !candidate.endsWith(ch)) continue;
      if (RegExp(r'\w').hasMatch(candidate) ||
          RegExp(r'\w').hasMatch(bracket.$1)) {
        continue;
      }
      final text = lineText.substring(0, position.column - 1) + ch;
      if (text.endsWith(candidate) &&
          text.substring(0, text.length - candidate.length).trim().isEmpty) {
        close = candidate;
        break;
      }
    }
    if (close == null) return null;
    if (config.standardTokenTypeAt?.call(
          model,
          position.lineNumber,
          position.column,
        )
        case final type? when type != 0) {
      return null;
    }
    final matchLine = _findMatchingBracketUp(
      model,
      open,
      close,
      Position(position.lineNumber, position.column - (close.length - 1)),
    );
    if (matchLine == null || matchLine == position.lineNumber) return null;
    final matchLineIndentation = getLeadingWhitespace(
      model.getLineContent(matchLine),
    );
    final newIndentation = config.normalize(matchLineIndentation);
    final lineFirstNonBlankColumn =
        model.getLineFirstNonWhitespaceColumn(position.lineNumber) == 0
        ? position.column
        : model.getLineFirstNonWhitespaceColumn(position.lineNumber);
    final prefix = lineText.substring(
      lineFirstNonBlankColumn - 1,
      position.column - 1,
    );
    final typeText = newIndentation + prefix + ch;
    return EditOperationResult(
      getTypingOperation(typeText, prevEditOperationType),
      [
        ReplaceCommand(
          Range(position.lineNumber, 1, position.lineNumber, position.column),
          typeText,
        ),
      ],
      shouldPushStackElementBefore: false,
      shouldPushStackElementAfter: true,
    );
  }

  /// The line of the open bracket matching a close bracket typed at
  /// [position] (the start column of the close text), or null.
  static int? _findMatchingBracketUp(
    ICursorSimpleModel model,
    String open,
    String close,
    Position position,
  ) {
    var depth = 0;
    final firstLine = position.lineNumber - _maxBracketSearchLines;
    for (
      var line = position.lineNumber;
      line >= 1 && line > firstLine;
      line--
    ) {
      final text = model.getLineContent(line);
      var end = line == position.lineNumber ? position.column - 1 : text.length;
      for (var i = end - 1; i >= 0; i--) {
        if (i + close.length <= end && text.startsWith(close, i)) {
          depth++;
        } else if (i + open.length <= end && text.startsWith(open, i)) {
          if (depth == 0) return line;
          depth--;
        }
      }
      end = 0;
    }
    return null;
  }
}

/// Upstream BaseTypeWithAutoClosingCommand + TypeWithAutoClosingCommand.
class TypeWithAutoClosingCommand extends ReplaceCommandWithOffsetCursorState {
  TypeWithAutoClosingCommand(
    Selection selection,
    this.openCharacter,
    bool insertOpenCharacter,
    this.closeCharacter,
  ) : super(
        selection,
        (insertOpenCharacter ? openCharacter : '') + closeCharacter,
        0,
        -closeCharacter.length,
      );

  final String openCharacter;
  final String closeCharacter;

  /// Post-edit range of the inserted close text, once the command ran.
  Range? closeCharacterRange;

  /// Post-edit range from the open text to the close text, once it ran.
  Range? enclosingRange;

  Selection computeCursorStateWithRange(
    ICursorSimpleModel model,
    Range range,
    CursorStateComputerData helper,
  ) {
    closeCharacterRange = Range(
      range.startLineNumber,
      range.endColumn - closeCharacter.length,
      range.endLineNumber,
      range.endColumn,
    );
    enclosingRange = Range(
      range.startLineNumber,
      range.endColumn - openCharacter.length - closeCharacter.length,
      range.endLineNumber,
      range.endColumn,
    );
    return super.computeCursorState(model, helper);
  }

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) => computeCursorStateWithRange(
    model,
    helper.getInverseEditOperations().first,
    helper,
  );
}

class TypeWithIndentationAndAutoClosingCommand
    extends TypeWithAutoClosingCommand {
  TypeWithIndentationAndAutoClosingCommand(
    this._autoIndentationEdit,
    Selection selection,
    String openCharacter,
    String closeCharacter,
  ) : _selection = selection,
      super(selection, openCharacter, true, closeCharacter);

  final CursorCommandEdit _autoIndentationEdit;
  final Selection _selection;

  @override
  List<CursorCommandEdit> getEditOperations(ICursorSimpleModel model) => [
    _autoIndentationEdit,
    CursorCommandEdit(_selection, openCharacter + closeCharacter),
  ];

  @override
  Selection computeCursorState(
    ICursorSimpleModel model,
    CursorStateComputerData helper,
  ) {
    final ops = helper.getInverseEditOperations();
    final range = ops[0].plusRange(ops[1]);
    closeCharacterRange = Range(
      range.startLineNumber,
      range.endColumn - closeCharacter.length,
      range.endLineNumber,
      range.endColumn,
    );
    enclosingRange = Range(
      range.startLineNumber,
      range.endColumn - openCharacter.length - closeCharacter.length,
      range.endLineNumber,
      range.endColumn,
    );
    // Upstream: columnDeltaOffset = openCharacter.length from the start of
    // the second edit (the cursor lands between the pair).
    final second = ops[1];
    return Selection(
      second.startLineNumber,
      second.startColumn + openCharacter.length,
      second.startLineNumber,
      second.startColumn + openCharacter.length,
    );
  }
}
