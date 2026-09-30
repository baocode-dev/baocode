// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/main.ts (MIT, see LICENSE.md).

import 'dart:typed_data';

import 'grammar/grammar.dart';
import 'grammar/grammar_dependencies.dart';
import 'onig_lib.dart';
import 'raw_grammar.dart';
import 'registry.dart';
import 'theme.dart';

export 'diff_state_stacks.dart'
    show StackDiff, applyStateStackDiff, diffStateStacksRefEq;
export 'encoded_token_attributes.dart'
    show EncodedTokenAttributes, OptionalStandardTokenType, StandardTokenType;
export 'grammar/grammar.dart' show AttributedScopeStackFrame, StateStackFrame;
export 'onig_lib.dart';
export 'parse_raw_grammar.dart' show parseRawGrammar;
export 'raw_grammar.dart';
export 'theme.dart'
    show
        FontStyle,
        IRawTheme,
        IRawThemeSetting,
        IRawThemeSettingStyle,
        IRawThemeSettingStyleWithFont;

/// A registry helper that can locate grammar file paths given scope names.
class RegistryOptions {
  const RegistryOptions({
    required this.onigLib,
    this.theme,
    this.colorMap,
    required this.loadGrammar,
    this.getInjections,
  });

  final Future<IOnigLib> onigLib;
  final IRawTheme? theme;
  final List<String?>? colorMap;
  final Future<IRawGrammar?> Function(ScopeName scopeName) loadGrammar;
  final List<ScopeName>? Function(ScopeName scopeName)? getInjections;
}

/// A map from scope name to a language id. Please do not use language id 0.
typedef IEmbeddedLanguagesMap = Map<String, int>;

/// A map from selectors to token types (`StandardTokenType` values).
typedef ITokenTypeMap = Map<String, int>;

class IGrammarConfiguration {
  const IGrammarConfiguration({
    this.embeddedLanguages,
    this.tokenTypes,
    this.balancedBracketSelectors,
    this.unbalancedBracketSelectors,
  });

  final IEmbeddedLanguagesMap? embeddedLanguages;
  final ITokenTypeMap? tokenTypes;
  final List<String>? balancedBracketSelectors;
  final List<String>? unbalancedBracketSelectors;
}

/// The registry that will hold all grammars.
class Registry {
  Registry(RegistryOptions options)
    : _options = options,
      _syncRegistry = SyncRegistry(
        Theme.createFromRawTheme(options.theme, options.colorMap),
        options.onigLib,
      );

  final RegistryOptions _options;
  final SyncRegistry _syncRegistry;
  final Map<String, Future<void>> _ensureGrammarCache =
      <String, Future<void>>{};

  void dispose() {
    _syncRegistry.dispose();
  }

  /// Change the theme. Once called, no previous `ruleStack` should be used anymore.
  void setTheme(IRawTheme theme, [List<String?>? colorMap]) {
    _syncRegistry.setTheme(Theme.createFromRawTheme(theme, colorMap));
  }

  /// Returns a lookup array for color ids.
  List<String> getColorMap() {
    return _syncRegistry.getColorMap();
  }

  /// Load the grammar for `scopeName` and all referenced included grammars asynchronously.
  /// Please do not use language id 0.
  Future<IGrammar?> loadGrammarWithEmbeddedLanguages(
    ScopeName initialScopeName,
    int initialLanguage,
    IEmbeddedLanguagesMap embeddedLanguages,
  ) {
    return loadGrammarWithConfiguration(
      initialScopeName,
      initialLanguage,
      IGrammarConfiguration(embeddedLanguages: embeddedLanguages),
    );
  }

  /// Load the grammar for `scopeName` and all referenced included grammars asynchronously.
  /// Please do not use language id 0.
  Future<IGrammar?> loadGrammarWithConfiguration(
    ScopeName initialScopeName,
    int initialLanguage,
    IGrammarConfiguration configuration,
  ) {
    return _loadGrammar(
      initialScopeName,
      initialLanguage,
      configuration.embeddedLanguages,
      configuration.tokenTypes,
      BalancedBracketSelectors(
        configuration.balancedBracketSelectors ?? const <String>[],
        configuration.unbalancedBracketSelectors ?? const <String>[],
      ),
    );
  }

  /// Load the grammar for `scopeName` and all referenced included grammars asynchronously.
  Future<IGrammar?> loadGrammar(ScopeName initialScopeName) {
    return _loadGrammar(initialScopeName, 0, null, null, null);
  }

  Future<IGrammar?> _loadGrammar(
    ScopeName initialScopeName,
    int initialLanguage,
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    BalancedBracketSelectors? balancedBracketSelectors,
  ) async {
    final dependencyProcessor = ScopeDependencyProcessor(
      _syncRegistry,
      initialScopeName,
    );
    while (dependencyProcessor.Q.isNotEmpty) {
      await Future.wait(
        dependencyProcessor.Q.map(
          (request) => _loadSingleGrammar(request.scopeName),
        ),
        eagerError: true,
      );
      dependencyProcessor.processQueue();
    }

    return _grammarForScopeName(
      initialScopeName,
      initialLanguage,
      embeddedLanguages,
      tokenTypes,
      balancedBracketSelectors,
    );
  }

  Future<void> _loadSingleGrammar(ScopeName scopeName) {
    return _ensureGrammarCache.putIfAbsent(
      scopeName,
      () => _doLoadSingleGrammar(scopeName),
    );
  }

  Future<void> _doLoadSingleGrammar(ScopeName scopeName) async {
    final grammar = await _options.loadGrammar(scopeName);
    if (grammar != null) {
      final getInjections = _options.getInjections;
      final injections = getInjections != null
          ? getInjections(scopeName)
          : null;
      _syncRegistry.addGrammar(grammar, injections);
    }
  }

  /// Adds a rawGrammar.
  Future<IGrammar> addGrammar(
    IRawGrammar rawGrammar, [
    List<String>? injections = const <String>[],
    int initialLanguage = 0,
    IEmbeddedLanguagesMap? embeddedLanguages,
  ]) async {
    _syncRegistry.addGrammar(rawGrammar, injections);
    return (await _grammarForScopeName(
      rawGrammar.scopeName,
      initialLanguage,
      embeddedLanguages,
    ))!;
  }

  /// Get the grammar for `scopeName`. The grammar must first be created via `loadGrammar` or `addGrammar`.
  Future<IGrammar?> _grammarForScopeName(
    String scopeName, [
    int initialLanguage = 0,
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    BalancedBracketSelectors? balancedBracketSelectors,
  ]) {
    return _syncRegistry.grammarForScopeName(
      scopeName,
      initialLanguage,
      embeddedLanguages,
      tokenTypes,
      balancedBracketSelectors,
    );
  }
}

/// A grammar
abstract interface class IGrammar {
  /// Tokenize `lineText` using previous line state `prevState`.
  ITokenizeLineResult tokenizeLine(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]);

  /// Tokenize `lineText` using previous line state `prevState`.
  /// The result contains the tokens in binary format, resolved with the following information:
  ///  - language
  ///  - token type (regex, string, comment, other)
  ///  - font style
  ///  - foreground color
  ///  - background color
  /// e.g. for getting the languageId: `(metadata & MetadataConsts.LANGUAGEID_MASK) >>> MetadataConsts.LANGUAGEID_OFFSET`
  ITokenizeLineResult2 tokenizeLine2(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]);
}

class ITokenizeLineResult {
  const ITokenizeLineResult({
    required this.tokens,
    required this.fonts,
    required this.ruleStack,
    required this.stoppedEarly,
  });

  final List<IToken> tokens;
  final List<IFontInfo> fonts;

  /// The `prevState` to be passed on to the next line tokenization.
  final StateStack ruleStack;

  /// Did tokenization stop early due to reaching the time limit.
  final bool stoppedEarly;
}

class ITokenizeLineResult2 {
  const ITokenizeLineResult2({
    required this.tokens,
    required this.fonts,
    required this.ruleStack,
    required this.stoppedEarly,
  });

  /// The tokens in binary format. Each token occupies two array indices. For token i:
  ///  - at offset 2*i => startIndex
  ///  - at offset 2*i + 1 => metadata
  final Uint32List tokens;

  /// Variable font information for the tokenized line
  final List<IFontInfo> fonts;

  /// The `prevState` to be passed on to the next line tokenization.
  final StateStack ruleStack;

  /// Did tokenization stop early due to reaching the time limit.
  final bool stoppedEarly;
}

/// Represents variable font information for a segment of text
abstract interface class IFontInfo {
  /// Starting index in the line
  int get startIndex;

  /// End index in the line
  int get endIndex;

  /// Font family specification
  String? get fontFamily;

  /// Font size specification
  num? get fontSizeMultiplier;

  /// Line height specification
  num? get lineHeightMultiplier;
}

class IToken {
  IToken({
    required this.startIndex,
    required this.endIndex,
    required this.scopes,
  });

  int startIndex;
  final int endIndex;
  final List<String> scopes;
}

/// **IMPORTANT** - Immutable!
abstract interface class StateStack {
  int get depth;

  StateStack clone();
  bool equals(StateStack? other);
}

// ignore: non_constant_identifier_names
final StateStack INITIAL = StateStackImpl.NULL;
