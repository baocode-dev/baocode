/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/workbench/services/textMate/common/TMGrammars.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971: `ITMSyntaxExtensionPoint`, a
// `contributes.grammars` entry. The extension point registration is not
// ported.
// Deviation: [ITMSyntaxExtensionPoint.fromJson] checks the shapes
// `validateGrammarExtensionPoint` (textMateTokenizationFeatureImpl.ts)
// rejects and throws a [FormatException] for them; like upstream's
// `asStringArray`, a bracket scope list that is not all strings reads as
// absent, and like `_validateGrammarDefinition`, embedded languages and
// token types that are not strings are dropped.

class ITMSyntaxExtensionPoint {
  const ITMSyntaxExtensionPoint({
    this.language,
    required this.scopeName,
    required this.path,
    this.embeddedLanguages,
    this.tokenTypes,
    this.injectTo,
    this.balancedBracketScopes,
    this.unbalancedBracketScopes,
  });

  factory ITMSyntaxExtensionPoint.fromJson(Map<String, Object?> json) {
    final language = json['language'];
    final scopeName = json['scopeName'];
    final path = json['path'];
    final injectTo = json['injectTo'];
    if (language != null && language is! String) {
      throw FormatException('Invalid grammar language: $language');
    }
    if (scopeName is! String || scopeName.isEmpty) {
      throw FormatException('Expected string in scopeName: $scopeName');
    }
    if (path is! String || path.isEmpty) {
      throw FormatException('Expected string in path: $path');
    }
    if (injectTo != null &&
        (injectTo is! List || injectTo.any((scope) => scope is! String))) {
      throw FormatException('Invalid injectTo: $injectTo');
    }
    return ITMSyntaxExtensionPoint(
      language: language as String?,
      scopeName: scopeName,
      path: path,
      embeddedLanguages: _stringMap(
        json['embeddedLanguages'],
        'embeddedLanguages',
      ),
      tokenTypes: _stringMap(json['tokenTypes'], 'tokenTypes'),
      injectTo: (injectTo as List?)?.cast<String>(),
      balancedBracketScopes: _stringList(json['balancedBracketScopes']),
      unbalancedBracketScopes: _stringList(json['unbalancedBracketScopes']),
    );
  }

  /// Undefined if the grammar is only included by other grammars.
  final String? language;
  final String scopeName;
  final String path;

  /// Scope name to language id, for grammars with embedded languages.
  final Map<String, String>? embeddedLanguages;

  /// Scope selector to token type: `string`, `comment`, `other` or `regex`.
  final Map<String, String>? tokenTypes;

  /// Scope names this grammar is injected into.
  final List<String>? injectTo;

  /// Scope selectors whose brackets are balanced; absent means `['*']`.
  final List<String>? balancedBracketScopes;

  /// Scope selectors whose brackets are not balanced; absent means `[]`.
  final List<String>? unbalancedBracketScopes;

  Map<String, Object?> toJson() => {
    if (language != null) 'language': language,
    'scopeName': scopeName,
    'path': path,
    if (embeddedLanguages != null) 'embeddedLanguages': embeddedLanguages,
    if (tokenTypes != null) 'tokenTypes': tokenTypes,
    if (injectTo != null) 'injectTo': injectTo,
    if (balancedBracketScopes != null)
      'balancedBracketScopes': balancedBracketScopes,
    if (unbalancedBracketScopes != null)
      'unbalancedBracketScopes': unbalancedBracketScopes,
  };
}

Map<String, String>? _stringMap(Object? value, String name) {
  if (value == null) return null;
  if (value is! Map) {
    throw FormatException('Invalid $name: must be an object map: $value');
  }
  return {
    for (final MapEntry(:key, :value) in value.entries)
      if (key is String && value is String) key: value,
  };
}

List<String>? _stringList(Object? value) =>
    value is List && value.every((item) => item is String)
    ? value.cast<String>()
    : null;
