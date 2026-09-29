/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/supports/onEnter.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. Dart RegExp has no `lastIndex`
// state, so upstream's reset of global patterns is unnecessary.

import '../language_configuration.dart';
import '../language_configuration_registry.dart' show EditorAutoIndentStrategy;

class _ProcessedBracketPair {
  const _ProcessedBracketPair(this.openRegExp, this.closeRegExp);

  final RegExp openRegExp;
  final RegExp closeRegExp;
}

class OnEnterSupport {
  OnEnterSupport({List<CharacterPair>? brackets, List<OnEnterRule>? rules})
    : _regExpRules = rules ?? const [] {
    for (final bracket
        in brackets ?? const [('(', ')'), ('{', '}'), ('[', ']')]) {
      final openRegExp = _createOpenBracketRegExp(bracket.$1);
      final closeRegExp = _createCloseBracketRegExp(bracket.$2);
      if (openRegExp != null && closeRegExp != null) {
        _brackets.add(_ProcessedBracketPair(openRegExp, closeRegExp));
      }
    }
  }

  final List<_ProcessedBracketPair> _brackets = [];
  final List<OnEnterRule> _regExpRules;

  EnterAction? onEnter(
    EditorAutoIndentStrategy autoIndent,
    String previousLineText,
    String beforeEnterText,
    String afterEnterText,
  ) {
    // (1): `regExpRules`
    if (autoIndent.index >= EditorAutoIndentStrategy.advanced.index) {
      for (final rule in _regExpRules) {
        if (rule.beforeText.hasMatch(beforeEnterText) &&
            (rule.afterText?.hasMatch(afterEnterText) ?? true) &&
            (rule.previousLineText?.hasMatch(previousLineText) ?? true)) {
          return rule.action;
        }
      }
    }
    // (2): Special indent-outdent
    if (autoIndent.index >= EditorAutoIndentStrategy.brackets.index) {
      if (beforeEnterText.isNotEmpty && afterEnterText.isNotEmpty) {
        for (final bracket in _brackets) {
          if (bracket.openRegExp.hasMatch(beforeEnterText) &&
              bracket.closeRegExp.hasMatch(afterEnterText)) {
            return const EnterAction(IndentAction.indentOutdent);
          }
        }
      }
    }
    // (4): Open bracket based logic
    if (autoIndent.index >= EditorAutoIndentStrategy.brackets.index) {
      if (beforeEnterText.isNotEmpty) {
        for (final bracket in _brackets) {
          if (bracket.openRegExp.hasMatch(beforeEnterText)) {
            return const EnterAction(IndentAction.indent);
          }
        }
      }
    }
    return null;
  }

  static final RegExp _nonWordBoundary = RegExp(r'\B');

  static RegExp? _createOpenBracketRegExp(String bracket) {
    var str = RegExp.escape(bracket);
    if (!_nonWordBoundary.hasMatch(str[0])) str = '\\b$str';
    str += r'\s*$';
    return _safeRegExp(str);
  }

  static RegExp? _createCloseBracketRegExp(String bracket) {
    var str = RegExp.escape(bracket);
    if (!_nonWordBoundary.hasMatch(str[str.length - 1])) str = '$str\\b';
    str = '^\\s*$str';
    return _safeRegExp(str);
  }

  static RegExp? _safeRegExp(String def) {
    try {
      return RegExp(def);
    } on FormatException {
      return null;
    }
  }
}
