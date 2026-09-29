/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/enterAction.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The before/after/previous line
// texts are raw lines: upstream's IndentationContextProcessor token cleanup
// (dropping string and comment contents) needs tokenization.

import '../core/range.dart';
import '../cursor/cursor_common.dart';
import 'language_configuration.dart';
import 'language_configuration_registry.dart';

CompleteEnterAction? getEnterAction(
  EditorAutoIndentStrategy autoIndent,
  ICursorSimpleModel model,
  Range range,
  ResolvedLanguageConfiguration richEditSupport,
) {
  final startLine = model.getLineContent(range.startLineNumber);
  final previousLineText = range.startLineNumber > 1
      ? model.getLineContent(range.startLineNumber - 1)
      : '';
  final beforeEnterText = startLine.substring(0, range.startColumn - 1);
  final afterEnterText = model
      .getLineContent(range.endLineNumber)
      .substring(range.endColumn - 1);
  final enterResult = richEditSupport.onEnter(
    autoIndent,
    previousLineText,
    beforeEnterText,
    afterEnterText,
  );
  if (enterResult == null) return null;
  final indentAction = enterResult.indentAction;
  var appendText = enterResult.appendText;
  final removeText = enterResult.removeText ?? 0;
  // Here we add `\t` to appendText first because enterAction is leveraging
  // appendText and removeText to change indentation.
  if (appendText == null || appendText.isEmpty) {
    appendText =
        indentAction == IndentAction.indent ||
            indentAction == IndentAction.indentOutdent
        ? '\t'
        : '';
  } else if (indentAction == IndentAction.indent) {
    appendText = '\t$appendText';
  }
  // getIndentationAtPosition: the leading whitespace, cut at the column.
  var indentation = getLeadingWhitespace(startLine);
  if (indentation.length > range.startColumn - 1) {
    indentation = indentation.substring(0, range.startColumn - 1);
  }
  if (removeText > 0) {
    indentation = indentation.substring(
      0,
      (indentation.length - removeText).clamp(0, indentation.length),
    );
  }
  return CompleteEnterAction(
    indentAction: indentAction,
    appendText: appendText,
    removeText: removeText,
    indentation: indentation,
  );
}
