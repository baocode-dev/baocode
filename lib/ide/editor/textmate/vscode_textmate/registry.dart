// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/registry.ts (MIT, see LICENSE.md).

import 'grammar/grammar.dart';
import 'main.dart';
import 'theme.dart';

class SyncRegistry implements IGrammarRepositoryAndThemeProvider {
  SyncRegistry(Theme theme, this._onigLibPromise) : _theme = theme;

  final Map<ScopeName, Grammar> _grammars = <ScopeName, Grammar>{};
  final Map<ScopeName, IRawGrammar> _rawGrammars = <ScopeName, IRawGrammar>{};
  final Map<ScopeName, List<ScopeName>> _injectionGrammars =
      <ScopeName, List<ScopeName>>{};
  Theme _theme;
  final Future<IOnigLib> _onigLibPromise;

  void dispose() {
    for (final grammar in _grammars.values) {
      grammar.dispose();
    }
  }

  void setTheme(Theme theme) {
    _theme = theme;
  }

  List<String> getColorMap() {
    return _theme.getColorMap();
  }

  /// Add `grammar` to registry and return a list of referenced scope names
  void addGrammar(IRawGrammar grammar, [List<ScopeName>? injectionScopeNames]) {
    _rawGrammars[grammar.scopeName] = grammar;

    if (injectionScopeNames != null) {
      _injectionGrammars[grammar.scopeName] = injectionScopeNames;
    }
  }

  /// Lookup a raw grammar.
  @override
  IRawGrammar? lookup(ScopeName scopeName) {
    return _rawGrammars[scopeName];
  }

  /// Returns the injections for the given grammar
  @override
  List<ScopeName>? injections(ScopeName targetScope) {
    return _injectionGrammars[targetScope];
  }

  /// Get the default theme settings
  @override
  StyleAttributes getDefaults() {
    return _theme.getDefaults();
  }

  /// Match a scope in the theme.
  @override
  StyleAttributes? themeMatch(ScopeStack scopePath) {
    return _theme.match(scopePath);
  }

  /// Lookup a grammar.
  Future<IGrammar?> grammarForScopeName(
    ScopeName scopeName,
    int initialLanguage,
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    BalancedBracketSelectors? balancedBracketSelectors,
  ) async {
    if (!_grammars.containsKey(scopeName)) {
      final rawGrammar = _rawGrammars[scopeName];
      if (rawGrammar == null) {
        return null;
      }
      final onigLib = await _onigLibPromise;
      _grammars[scopeName] = createGrammar(
        scopeName,
        rawGrammar,
        initialLanguage,
        embeddedLanguages,
        tokenTypes,
        balancedBracketSelectors,
        this,
        onigLib,
      );
    }
    return _grammars[scopeName]!;
  }
}
