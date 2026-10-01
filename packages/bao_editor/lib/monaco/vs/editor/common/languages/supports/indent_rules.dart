/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/supports/indentRules.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971.

import '../language_configuration.dart';

abstract final class IndentConsts {
  static const int increaseMask = 0x1;
  static const int decreaseMask = 0x2;
  static const int indentNextLineMask = 0x4;
  static const int unindentMask = 0x8;
}

class IndentRulesSupport {
  const IndentRulesSupport(this._indentationRules);

  final IndentationRule _indentationRules;

  bool shouldIncrease(String text) =>
      _indentationRules.increaseIndentPattern.hasMatch(text);

  bool shouldDecrease(String text) =>
      _indentationRules.decreaseIndentPattern.hasMatch(text);

  bool shouldIndentNextLine(String text) =>
      _indentationRules.indentNextLinePattern?.hasMatch(text) ?? false;

  bool shouldIgnore(String text) =>
      _indentationRules.unIndentedLinePattern?.hasMatch(text) ?? false;

  int getIndentMetadata(String text) {
    var ret = 0;
    if (shouldIncrease(text)) ret += IndentConsts.increaseMask;
    if (shouldDecrease(text)) ret += IndentConsts.decreaseMask;
    if (shouldIndentNextLine(text)) ret += IndentConsts.indentNextLineMask;
    if (shouldIgnore(text)) ret += IndentConsts.unindentMask;
    return ret;
  }
}
