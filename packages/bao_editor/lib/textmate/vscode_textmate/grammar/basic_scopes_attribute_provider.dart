// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/grammar/basicScopesAttributeProvider.ts (MIT, see LICENSE.md).

import '../encoded_token_attributes.dart';
import '../js_semantics.dart';
import '../utils.dart';

class BasicScopeAttributes {
  const BasicScopeAttributes(this.languageId, this.tokenType);

  final int languageId;

  /// An `OptionalStandardTokenType`.
  final int tokenType;
}

class BasicScopeAttributesProvider {
  BasicScopeAttributesProvider(
    int initialLanguageId,
    Map<String, int>? embeddedLanguages,
  ) : _defaultAttributes = BasicScopeAttributes(
        initialLanguageId,
        OptionalStandardTokenType.notSet,
      ),
      _embeddedLanguagesMatcher = _ScopeMatcher<int>([
        if (embeddedLanguages != null)
          for (final key in jsObjectKeys(embeddedLanguages))
            MapEntry(key, embeddedLanguages[key]!),
      ]) {
    _getBasicScopeAttributes = CachedFn<String, BasicScopeAttributes>((
      scopeName,
    ) {
      final languageId = _scopeToLanguage(scopeName);
      final standardTokenType = _toStandardTokenType(scopeName);
      return BasicScopeAttributes(languageId, standardTokenType);
    });
  }

  final BasicScopeAttributes _defaultAttributes;
  final _ScopeMatcher<int> _embeddedLanguagesMatcher;

  BasicScopeAttributes getDefaultAttributes() {
    return _defaultAttributes;
  }

  BasicScopeAttributes getBasicScopeAttributes(String? scopeName) {
    if (scopeName == null) {
      return _nullScopeMetadata;
    }
    return _getBasicScopeAttributes.get(scopeName);
  }

  static const BasicScopeAttributes _nullScopeMetadata = BasicScopeAttributes(
    0,
    0,
  );

  late final CachedFn<String, BasicScopeAttributes> _getBasicScopeAttributes;

  /// Given a produced TM scope, return the language that token describes or null if unknown.
  /// e.g. source.html => html, source.css.embedded.html => css, punctuation.definition.tag.html => null
  int _scopeToLanguage(String scope) {
    final value = _embeddedLanguagesMatcher.match(scope);
    return (value == null || value == 0) ? 0 : value;
  }

  int _toStandardTokenType(String scopeName) {
    final m = _standardTokenTypeRegExp.firstMatch(scopeName);
    if (m == null) {
      return OptionalStandardTokenType.notSet;
    }
    switch (m[1]) {
      case 'comment':
        return OptionalStandardTokenType.comment;
      case 'string':
        return OptionalStandardTokenType.string;
      case 'regex':
        return OptionalStandardTokenType.regEx;
      case 'meta.embedded':
        return OptionalStandardTokenType.other;
    }
    throw StateError('Unexpected match for standard token type!');
  }

  static final RegExp _standardTokenTypeRegExp = RegExp(
    r'\b(comment|string|regex|meta\.embedded)\b',
  );
}

class _ScopeMatcher<TValue> {
  factory _ScopeMatcher(List<MapEntry<String, TValue>> values) {
    if (values.isEmpty) {
      return _ScopeMatcher<TValue>._(null, null);
    }
    final map = <String, TValue>{
      for (final entry in values) entry.key: entry.value,
    };

    // create the regex
    final escapedScopes = [
      for (final entry in values) escapeRegExpCharacters(entry.key),
    ];

    escapedScopes.sort();
    final reversed = escapedScopes.reversed.toList(); // Longest scope first
    return _ScopeMatcher<TValue>._(
      map,
      RegExp('^((${reversed.join(')|(')}))(\$|\\.)'),
    );
  }

  _ScopeMatcher._(this.values, this.scopesRegExp);

  final Map<String, TValue>? values;
  final RegExp? scopesRegExp;

  TValue? match(String scope) {
    final scopesRegExp = this.scopesRegExp;
    if (scopesRegExp == null) {
      return null;
    }
    final m = scopesRegExp.firstMatch(scope);
    if (m == null) {
      // no scopes matched
      return null;
    }
    return values![m[1]];
  }
}
