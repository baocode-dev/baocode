/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/editor/common/languages/languageConfigurationRegistry.ts
// (ResolvedLanguageConfiguration and the plaintext registration) and the
// EditorAutoIndentStrategy enum from config/editorOptions.ts, at
// 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: there is no registry/service or per-token language lookup; the
// caller resolves one configuration per document. Upstream RichEditBrackets
// is not ported: electric characters only consider the configured brackets'
// last close character, see `electricCharacters`.

import 'language_configuration.dart';
import 'supports/character_pair.dart';
import 'supports/indent_rules.dart';
import 'supports/on_enter.dart';

enum EditorAutoIndentStrategy { none, keep, brackets, advanced, full }

/// Upstream ICommentsConfiguration.
class CommentsConfiguration {
  const CommentsConfiguration({
    this.lineCommentToken,
    this.lineCommentNoIndent = false,
    this.blockCommentStartToken,
    this.blockCommentEndToken,
  });

  final String? lineCommentToken;
  final bool lineCommentNoIndent;
  final String? blockCommentStartToken;
  final String? blockCommentEndToken;
}

/// The configuration upstream registers for `plaintext`.
const LanguageConfiguration plainTextLanguageConfiguration =
    LanguageConfiguration(
      brackets: [('(', ')'), ('[', ']'), ('{', '}')],
      surroundingPairs: [
        AutoClosingPair('{', '}'),
        AutoClosingPair('[', ']'),
        AutoClosingPair('(', ')'),
        AutoClosingPair('<', '>'),
        AutoClosingPair('"', '"'),
        AutoClosingPair("'", "'"),
        AutoClosingPair('`', '`'),
      ],
      colorizedBracketPairs: [],
      folding: FoldingRules(offSide: true),
    );

/// Immutable.
class ResolvedLanguageConfiguration {
  ResolvedLanguageConfiguration(this.underlyingConfig)
    : comments = _handleComments(underlyingConfig),
      characterPair = CharacterPairSupport(underlyingConfig),
      indentRulesSupport = underlyingConfig.indentationRules == null
          ? null
          : IndentRulesSupport(underlyingConfig.indentationRules!),
      _onEnterSupport =
          underlyingConfig.brackets != null ||
              underlyingConfig.indentationRules != null ||
              underlyingConfig.onEnterRules != null
          ? OnEnterSupport(
              brackets: underlyingConfig.brackets,
              rules: underlyingConfig.onEnterRules,
            )
          : null;

  final LanguageConfiguration underlyingConfig;
  final CommentsConfiguration? comments;
  final CharacterPairSupport characterPair;
  final IndentRulesSupport? indentRulesSupport;
  final OnEnterSupport? _onEnterSupport;

  late final AutoClosingPairs autoClosingPairs = AutoClosingPairs(
    characterPair.getAutoClosingPairs(),
  );

  /// Upstream config.surroundingPairs, keyed by open character.
  late final Map<String, String> surroundingPairs = {
    for (final pair in characterPair.getSurroundingPairs())
      pair.open: pair.close,
  };

  /// Last character of each bracket's close, like upstream
  /// BracketElectricCharacterSupport.getElectricCharacters.
  late final Map<String, String> electricCharacters = {
    for (final bracket in underlyingConfig.brackets ?? const <CharacterPair>[])
      if (bracket.$2.isNotEmpty) bracket.$2[bracket.$2.length - 1]: bracket.$1,
  };

  EnterAction? onEnter(
    EditorAutoIndentStrategy autoIndent,
    String previousLineText,
    String beforeEnterText,
    String afterEnterText,
  ) => _onEnterSupport?.onEnter(
    autoIndent,
    previousLineText,
    beforeEnterText,
    afterEnterText,
  );

  String getAutoCloseBeforeSet(bool forQuotes) =>
      characterPair.getAutoCloseBeforeSet(forQuotes);

  static CommentsConfiguration? _handleComments(LanguageConfiguration conf) {
    final commentRule = conf.comments;
    if (commentRule == null) return null;
    return CommentsConfiguration(
      lineCommentToken: commentRule.lineComment?.comment,
      lineCommentNoIndent: commentRule.lineComment?.noIndent ?? false,
      blockCommentStartToken: commentRule.blockComment?.$1,
      blockCommentEndToken: commentRule.blockComment?.$2,
    );
  }
}
