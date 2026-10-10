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

/// The language configurations the app and its extensions registered, by
/// language id.
///
/// VS Code's `LanguageConfigurationRegistry` keeps one configuration per
/// language (the built-in one, then extension contributions merged in as
/// they load); the editor reads it when it creates or changes a document's
/// language. BaoCode resolves one configuration per document instead, so
/// this holds the extension-contributed ones (`contributes.languages`'
/// `configuration`) for the caller to pick.
///
/// Ported from VS Code 1.135.0 (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5):
/// src/vs/editor/common/languages/languageConfigurationRegistry.ts
/// (`LanguageConfigurationRegistry.register`, `getLanguageConfiguration`).
///
/// Deviations: nothing is merged with a built-in default here (the caller
/// merges a contribution over the bundled configuration); a re-registration
/// under the same language and source replaces it.
class LanguageConfigurationRegistry {
  final Map<String, Map<String, _RegisteredLanguageConfiguration>> _byLanguage =
      {};

  int _version = 0;

  /// Bumps on every registration, so callers can tell when to resolve
  /// their documents' configurations again.
  int get version => _version;

  /// Languages with at least one registered configuration.
  Iterable<String> get languageIds => _byLanguage.keys;

  /// `register(languageId, configuration, source)`. [source] names what
  /// registered it (an extension id, or `''` for the app); a second
  /// registration under the same pair replaces the first.
  void register(
    String languageId,
    LanguageConfiguration configuration, {
    String source = '',
  }) {
    (_byLanguage[languageId] ??= {})[source] = _RegisteredLanguageConfiguration(
      configuration,
      source,
    );
    _version++;
  }

  /// Forgets what [source] registered for [languageId].
  void unregister(String languageId, {String source = ''}) {
    final sources = _byLanguage[languageId];
    if (sources == null || sources.remove(source) == null) return;
    if (sources.isEmpty) _byLanguage.remove(languageId);
    _version++;
  }

  /// The configuration [source] registered for [languageId], if any.
  LanguageConfiguration? get(String languageId, {String source = ''}) =>
      _byLanguage[languageId]?[source]?.configuration;

  /// The configuration for [languageId], an extension's winning over the
  /// app's (the most recently registered source).
  LanguageConfiguration? forLanguage(String languageId) {
    final sources = _byLanguage[languageId];
    if (sources == null || sources.isEmpty) return null;
    return sources.values.last.configuration;
  }

  /// Which source [forLanguage] would take its configuration from.
  String? sourceFor(String languageId) =>
      _byLanguage[languageId]?.values.last.source;
}

class _RegisteredLanguageConfiguration {
  const _RegisteredLanguageConfiguration(this.configuration, this.source);

  final LanguageConfiguration configuration;
  final String source;
}
