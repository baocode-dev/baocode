/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/common/languages/autoIndent.ts
// (getInheritIndentForLine, getIndentForEnter, getIndentActionForType) at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: lines are matched raw. Upstream's IndentationContextProcessor
// first removes string/comment/regex token contents using tokenization, and
// embedded-language boundaries are checked per token; neither is available.

import '../core/range.dart';
import '../cursor/cursor_common.dart';
import 'language_configuration.dart';
import 'language_configuration_registry.dart';
import 'supports/indent_rules.dart';

/// Upstream IIndentConverter.
abstract interface class IndentConverter {
  String shiftIndent(String indentation);
  String unshiftIndent(String indentation);
  String normalizeIndentation(String indentation);
}

class InheritedIndent {
  const InheritedIndent(this.indentation, this.action, [this.line]);

  final String indentation;
  final IndentAction? action;
  final int? line;
}

bool _isBlank(String text) => text.trim().isEmpty;

/// Nearest preceding line which isn't ignored or whitespace only; 0 when
/// every line above is invalid and -1 at the start of the document.
int _getPrecedingValidLine(
  ICursorSimpleModel model,
  int lineNumber,
  IndentRulesSupport rules,
) {
  if (lineNumber > 1) {
    var resultLineNumber = -1;
    for (var last = lineNumber - 1; last >= 1; last--) {
      final text = model.getLineContent(last);
      if (rules.shouldIgnore(text) || _isBlank(text)) {
        resultLineNumber = last;
        continue;
      }
      return last;
    }
    // Upstream returns -1 here only across a language boundary; with a
    // single language every line above is invalid.
    return resultLineNumber < 0 ? -1 : 0;
  }
  return -1;
}

InheritedIndent? getInheritIndentForLine(
  EditorAutoIndentStrategy autoIndent,
  ICursorSimpleModel model,
  int lineNumber,
  ResolvedLanguageConfiguration config, {
  bool honorIntentialIndent = true,
}) {
  if (autoIndent.index < EditorAutoIndentStrategy.full.index) return null;
  final rules = config.indentRulesSupport;
  if (rules == null) return null;
  if (lineNumber <= 1) return const InheritedIndent('', null);
  // Use no indent if this is the first non-blank line
  for (var prior = lineNumber - 1; prior > 0; prior--) {
    if (model.getLineContent(prior) != '') break;
    if (prior == 1) return const InheritedIndent('', null);
  }
  final preceding = _getPrecedingValidLine(model, lineNumber, rules);
  if (preceding < 0) {
    return null;
  } else if (preceding < 1) {
    return const InheritedIndent('', null);
  }
  final precedingContent = model.getLineContent(preceding);
  if (rules.shouldIncrease(precedingContent) ||
      rules.shouldIndentNextLine(precedingContent)) {
    return InheritedIndent(
      getLeadingWhitespace(precedingContent),
      IndentAction.indent,
      preceding,
    );
  } else if (rules.shouldDecrease(precedingContent)) {
    return InheritedIndent(
      getLeadingWhitespace(precedingContent),
      null,
      preceding,
    );
  }
  if (preceding == 1) {
    return InheritedIndent(getLeadingWhitespace(precedingContent), null, 1);
  }
  final previousLine = preceding - 1;
  final metadata = rules.getIndentMetadata(model.getLineContent(previousLine));
  if ((metadata & (IndentConsts.increaseMask | IndentConsts.decreaseMask)) ==
          0 &&
      (metadata & IndentConsts.indentNextLineMask) != 0) {
    var stopLine = 0;
    for (var i = previousLine - 1; i > 0; i--) {
      if (rules.shouldIndentNextLine(model.getLineContent(i))) continue;
      stopLine = i;
      break;
    }
    return InheritedIndent(
      getLeadingWhitespace(model.getLineContent(stopLine + 1)),
      null,
      stopLine + 1,
    );
  }
  if (honorIntentialIndent) {
    return InheritedIndent(
      getLeadingWhitespace(precedingContent),
      null,
      preceding,
    );
  }
  // search from preceding until we find one whose indent is not temporary
  for (var i = preceding; i > 0; i--) {
    final text = model.getLineContent(i);
    if (rules.shouldIncrease(text)) {
      return InheritedIndent(
        getLeadingWhitespace(text),
        IndentAction.indent,
        i,
      );
    } else if (rules.shouldIndentNextLine(text)) {
      var stopLine = 0;
      for (var j = i - 1; j > 0; j--) {
        // Upstream checks line `i` here (not `j`); kept for parity.
        if (rules.shouldIndentNextLine(text)) continue;
        stopLine = j;
        break;
      }
      return InheritedIndent(
        getLeadingWhitespace(model.getLineContent(stopLine + 1)),
        null,
        stopLine + 1,
      );
    } else if (rules.shouldDecrease(text)) {
      return InheritedIndent(getLeadingWhitespace(text), null, i);
    }
  }
  return InheritedIndent(
    getLeadingWhitespace(model.getLineContent(1)),
    null,
    1,
  );
}

/// Indentation of the line before and after Enter at [range].
({String beforeEnter, String afterEnter})? getIndentForEnter(
  EditorAutoIndentStrategy autoIndent,
  ICursorSimpleModel model,
  Range range,
  IndentConverter indentConverter,
  ResolvedLanguageConfiguration config,
) {
  if (autoIndent.index < EditorAutoIndentStrategy.full.index) return null;
  final rules = config.indentRulesSupport;
  if (rules == null) return null;
  final startLine = model.getLineContent(range.startLineNumber);
  final beforeEnterText = startLine.substring(0, range.startColumn - 1);
  final endLine = model.getLineContent(range.endLineNumber);
  final afterEnterText = endLine.substring(range.endColumn - 1);
  final beforeEnterIndent = getLeadingWhitespace(beforeEnterText);
  final virtualModel = _ReplacedLineModel(
    model,
    range.startLineNumber,
    beforeEnterText,
  );
  final afterEnterAction = getInheritIndentForLine(
    autoIndent,
    virtualModel,
    range.startLineNumber + 1,
    config,
  );
  if (afterEnterAction == null) {
    return (beforeEnter: beforeEnterIndent, afterEnter: beforeEnterIndent);
  }
  var afterEnterIndent = afterEnterAction.indentation;
  if (afterEnterAction.action == IndentAction.indent) {
    afterEnterIndent = indentConverter.shiftIndent(afterEnterIndent);
  }
  if (rules.shouldDecrease(afterEnterText)) {
    afterEnterIndent = indentConverter.unshiftIndent(afterEnterIndent);
  }
  return (beforeEnter: beforeEnterIndent, afterEnter: afterEnterIndent);
}

/// The indentation the line at [range] should get after typing [ch], or null
/// to leave it unchanged.
String? getIndentActionForType(
  EditorAutoIndentStrategy autoIndent,
  ICursorSimpleModel model,
  Range range,
  String ch,
  IndentConverter indentConverter,
  ResolvedLanguageConfiguration config,
) {
  if (autoIndent.index < EditorAutoIndentStrategy.full.index) return null;
  final rules = config.indentRulesSupport;
  if (rules == null) return null;
  final beforeRangeText = model
      .getLineContent(range.startLineNumber)
      .substring(0, range.startColumn - 1);
  final afterRangeText = model
      .getLineContent(range.endLineNumber)
      .substring(range.endColumn - 1);
  final textAroundRange = beforeRangeText + afterRangeText;
  final textAroundRangeWithCharacter = beforeRangeText + ch + afterRangeText;
  // If previous content already matches decreaseIndentPattern, the user may
  // have changed the indentation on purpose; honor that.
  if (!rules.shouldDecrease(textAroundRange) &&
      rules.shouldDecrease(textAroundRangeWithCharacter)) {
    final r = getInheritIndentForLine(
      autoIndent,
      model,
      range.startLineNumber,
      config,
      honorIntentialIndent: false,
    );
    if (r == null) return null;
    var indentation = r.indentation;
    if (r.action != IndentAction.indent) {
      indentation = indentConverter.unshiftIndent(indentation);
    }
    return indentation;
  }
  final previousLineNumber = range.startLineNumber - 1;
  if (range.isEmpty() && previousLineNumber > 0) {
    final previousLine = model.getLineContent(previousLineNumber);
    if (rules.shouldIndentNextLine(previousLine) &&
        rules.shouldIncrease(textAroundRangeWithCharacter)) {
      final inherited = getInheritIndentForLine(
        autoIndent,
        model,
        range.startLineNumber,
        config,
        honorIntentialIndent: false,
      )?.indentation;
      if (inherited != null) {
        final actual = getLeadingWhitespace(
          model.getLineContent(range.startLineNumber),
        );
        final inferred = indentConverter.shiftIndent(inherited);
        final onlyWhitespace = _isBlank(textAroundRange);
        final pairs = config.autoClosingPairs.autoClosingPairsOpenByEnd[ch];
        if (inferred == actual &&
            pairs != null &&
            pairs.isNotEmpty &&
            onlyWhitespace) {
          return inherited;
        }
      }
    }
  }
  return null;
}

/// A model whose [lineNumber] reads as [content] (upstream virtual model).
class _ReplacedLineModel implements ICursorSimpleModel {
  _ReplacedLineModel(this._model, this._lineNumber, this._content);

  final ICursorSimpleModel _model;
  final int _lineNumber;
  final String _content;

  @override
  int getLineCount() => _model.getLineCount();

  @override
  String getLineContent(int lineNumber) =>
      lineNumber == _lineNumber ? _content : _model.getLineContent(lineNumber);

  @override
  int getLineMinColumn(int lineNumber) => 1;

  @override
  int getLineMaxColumn(int lineNumber) => getLineContent(lineNumber).length + 1;

  @override
  int getLineFirstNonWhitespaceColumn(int lineNumber) =>
      firstNonWhitespaceIndex(getLineContent(lineNumber)) + 1;

  @override
  int getLineLastNonWhitespaceColumn(int lineNumber) {
    final text = getLineContent(lineNumber);
    final i = lastNonWhitespaceIndex(text);
    return i == -1 ? 0 : i + 2;
  }
}
