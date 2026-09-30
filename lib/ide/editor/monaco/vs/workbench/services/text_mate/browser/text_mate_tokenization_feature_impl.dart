/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/workbench/services/textMate/browser/
// textMateTokenizationFeatureImpl.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `_validateGrammarDefinition`
// (with `validateGrammarExtensionPoint`'s language check) as
// [validateGrammarDefinition], and the theme `_updateTheme` hands to
// vscode-textmate as [toRawTheme]. The service itself is not ported: the
// tokenization supports are in tokenization_support/, the background
// tokenizer in background_tokenization/, and lib/ide/editor/textmate/
// textmate_worker.dart creates grammars as the service does.
// Deviations: the language service is two callbacks; the grammar's location
// is its path, already resolved against the extension; an unregistered
// language rejects the grammar without reporting it.

import '../../../../../../textmate/vscode_textmate/raw_theme.dart';
import '../../../../editor/common/encoded_token_attributes.dart';
import '../../themes/common/color_theme_data.dart';
import '../common/tm_grammars.dart';
import '../common/tm_scope_registry.dart';

/// The default of `editor.maxTokenizationLineLength`
/// (editorConfigurationSchema.ts). `TokenizationSupportWithLineLimit` returns
/// `nullTokenizeEncoded(languageId, state)` for a line at least this long;
/// otherwise `TextMateTokenizationSupport` calls
/// `grammar.tokenizeLine2(line, state, 500)` and, when that stops early at
/// the time limit, keeps its tokens but tokenizes the next line from `state`.
const int maxTokenizationLineLength = 20000;

/// The time limit, in milliseconds, of `tokenizeLine2` in
/// `TextMateTokenizationSupport.tokenizeEncoded`.
const int tokenizationTimeLimitMs = 500;

/// Checks a `contributes.grammars` entry and converts it for the grammar
/// factory: embedded languages to encoded ids (dropping unregistered ones),
/// token types to [StandardTokenType]s, and the bracket selectors'
/// defaults (`['*']` balanced, `[]` unbalanced). Null when the grammar's
/// language is not registered.
IValidGrammarDefinition? validateGrammarDefinition(
  ITMSyntaxExtensionPoint grammar, {
  required bool Function(String languageId) isRegisteredLanguageId,
  required int Function(String languageId) encodeLanguageId,
  String? sourceExtensionId,
}) {
  final language = grammar.language;
  if (language != null && !isRegisteredLanguageId(language)) {
    return null;
  }

  final embeddedLanguages = <String, int>{};
  grammar.embeddedLanguages?.forEach((scope, language) {
    if (isRegisteredLanguageId(language)) {
      embeddedLanguages[scope] = encodeLanguageId(language);
    }
  });

  final tokenTypes = <String, int>{};
  grammar.tokenTypes?.forEach((scope, tokenType) {
    switch (tokenType) {
      case 'string':
        tokenTypes[scope] = StandardTokenType.string;
      case 'other':
        tokenTypes[scope] = StandardTokenType.other;
      case 'comment':
        tokenTypes[scope] = StandardTokenType.comment;
      case 'regex':
        tokenTypes[scope] = StandardTokenType.regEx;
    }
  });

  return IValidGrammarDefinition(
    location: grammar.path,
    language: language,
    scopeName: grammar.scopeName,
    embeddedLanguages: embeddedLanguages,
    tokenTypes: tokenTypes,
    injectTo: grammar.injectTo,
    balancedBracketSelectors: grammar.balancedBracketScopes ?? const ['*'],
    unbalancedBracketSelectors: grammar.unbalancedBracketScopes ?? const [],
    sourceExtensionId: sourceExtensionId,
  );
}

/// `{ name: colorTheme.label, settings: colorTheme.tokenColors }`, which
/// `_updateTheme` passes to `setTheme` with `colorTheme.tokenColorMap`.
/// vscode-textmate reads no rule `name`; a rule's font family, size and line
/// height do not fit [IRawThemeSettingStyle] and are dropped.
IRawTheme toRawTheme(ColorThemeData colorTheme) => IRawTheme(
  name: colorTheme.label,
  settings: [
    for (final rule in colorTheme.tokenColors)
      IRawThemeSetting(
        scope: rule.scope,
        settings: IRawThemeSettingStyle(
          fontStyle: rule.settings.fontStyle,
          foreground: rule.settings.foreground,
          background: rule.settings.background,
        ),
      ),
  ],
);
