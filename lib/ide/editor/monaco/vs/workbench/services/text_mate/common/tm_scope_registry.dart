/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/textMate/common/
// TMScopeRegistry.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: a grammar's location is a path string (resolved by the
// caller's reader) instead of a URI; re-registering a scope name with a
// different location replaces it without upstream's console warning.

/// A grammar contribution checked and converted by
/// `validateGrammarDefinition` (text_mate_tokenization_feature_impl.dart).
class IValidGrammarDefinition {
  const IValidGrammarDefinition({
    required this.location,
    this.language,
    required this.scopeName,
    required this.embeddedLanguages,
    required this.tokenTypes,
    this.injectTo,
    required this.balancedBracketSelectors,
    required this.unbalancedBracketSelectors,
    this.sourceExtensionId,
  });

  final String location;
  final String? language;
  final String scopeName;

  /// Scope name to encoded language id (`IValidEmbeddedLanguagesMap`).
  final Map<String, int> embeddedLanguages;

  /// Scope selector to `StandardTokenType` (`IValidTokenTypeMap`).
  final Map<String, int> tokenTypes;
  final List<String>? injectTo;
  final List<String> balancedBracketSelectors;
  final List<String> unbalancedBracketSelectors;
  final String? sourceExtensionId;
}

class TMScopeRegistry {
  Map<String, IValidGrammarDefinition> _scopeNameToLanguageRegistration = {};

  void reset() {
    _scopeNameToLanguageRegistration = {};
  }

  void register(IValidGrammarDefinition def) {
    _scopeNameToLanguageRegistration[def.scopeName] = def;
  }

  IValidGrammarDefinition? getGrammarDefinition(String scopeName) =>
      _scopeNameToLanguageRegistration[scopeName];
}
