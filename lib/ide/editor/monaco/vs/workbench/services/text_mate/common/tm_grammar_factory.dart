/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/textMate/common/
// TMGrammarFactory.ts at 6a598d4a13031703d483d103c1d934a36ad27971.
// Deviations: the host's `readFile` takes the grammar's location as a path
// string; vscode-textmate is imported rather than passed in; a
// `StateError` stands in for upstream's `Error` (see
// [missingTMGrammarErrorMessage]).

import '../../../../../../textmate/vscode_textmate/main.dart';
import 'tm_scope_registry.dart';

abstract interface class ITMGrammarFactoryHost {
  void logTrace(String msg);
  void logError(String msg, Object? err);
  Future<String> readFile(String resource);
}

class ICreateGrammarResult {
  const ICreateGrammarResult({
    required this.languageId,
    required this.grammar,
    required this.initialState,
    required this.containsEmbeddedLanguages,
    this.sourceExtensionId,
  });

  final String languageId;
  final IGrammar? grammar;
  final StateStack initialState;
  final bool containsEmbeddedLanguages;
  final String? sourceExtensionId;
}

const String missingTMGrammarErrorMessage =
    'No TM Grammar registered for this language.';

class TMGrammarFactory {
  TMGrammarFactory(
    ITMGrammarFactoryHost host,
    List<IValidGrammarDefinition> grammarDefinitions,
    Future<IOnigLib> onigLib,
  ) : _host = host,
      _initialState = INITIAL {
    _grammarRegistry = Registry(
      RegistryOptions(
        onigLib: onigLib,
        loadGrammar: (scopeName) async {
          final grammarDefinition = _scopeRegistry.getGrammarDefinition(
            scopeName,
          );
          if (grammarDefinition == null) {
            _host.logTrace('No grammar found for scope $scopeName');
            return null;
          }
          final location = grammarDefinition.location;
          try {
            final content = await _host.readFile(location);
            return parseRawGrammar(content, location);
          } catch (e) {
            _host.logError(
              'Unable to load and parse grammar for scope $scopeName from '
              '$location',
              e,
            );
            return null;
          }
        },
        getInjections: (scopeName) {
          final scopeParts = scopeName.split('.');
          var injections = <String>[];
          for (var i = 1; i <= scopeParts.length; i++) {
            final subScopeName = scopeParts.sublist(0, i).join('.');
            injections = [...injections, ...?_injections[subScopeName]];
          }
          return injections;
        },
      ),
    );

    for (final validGrammar in grammarDefinitions) {
      _scopeRegistry.register(validGrammar);

      final injectTo = validGrammar.injectTo;
      if (injectTo != null) {
        for (final injectScope in injectTo) {
          (_injections[injectScope] ??= []).add(validGrammar.scopeName);
        }

        // Always an object once validated, so always taken, as upstream.
        for (final injectScope in injectTo) {
          (_injectedEmbeddedLanguages[injectScope] ??= []).add(
            validGrammar.embeddedLanguages,
          );
        }
      }

      final language = validGrammar.language;
      if (language != null) {
        _languageToScope[language] = validGrammar.scopeName;
      }
    }
  }

  final ITMGrammarFactoryHost _host;
  final StateStack _initialState;
  final TMScopeRegistry _scopeRegistry = TMScopeRegistry();
  final Map<String, List<String>> _injections = {};
  final Map<String, List<Map<String, int>>> _injectedEmbeddedLanguages = {};
  final Map<String, String> _languageToScope = {};
  late final Registry _grammarRegistry;

  bool has(String languageId) => _languageToScope.containsKey(languageId);

  /// [colorMap] is VS Code's `tokenColorMap`: its index 0 is a hole (null).
  void setTheme(IRawTheme theme, List<String?> colorMap) {
    _grammarRegistry.setTheme(theme, colorMap);
  }

  List<String> getColorMap() => _grammarRegistry.getColorMap();

  Future<ICreateGrammarResult> createGrammar(
    String languageId,
    int encodedLanguageId,
  ) async {
    final scopeName = _languageToScope[languageId];
    if (scopeName == null) {
      // No TM grammar defined
      throw StateError(missingTMGrammarErrorMessage);
    }

    final grammarDefinition = _scopeRegistry.getGrammarDefinition(scopeName);
    if (grammarDefinition == null) {
      // No TM grammar defined
      throw StateError(missingTMGrammarErrorMessage);
    }

    // Upstream adds the injected languages to the definition's own map.
    final embeddedLanguages = grammarDefinition.embeddedLanguages;
    final injectedEmbeddedLanguages = _injectedEmbeddedLanguages[scopeName];
    if (injectedEmbeddedLanguages != null) {
      for (final injected in injectedEmbeddedLanguages) {
        for (final scope in injected.keys) {
          embeddedLanguages[scope] = injected[scope]!;
        }
      }
    }

    final containsEmbeddedLanguages = embeddedLanguages.isNotEmpty;

    IGrammar? grammar;

    try {
      grammar = await _grammarRegistry.loadGrammarWithConfiguration(
        scopeName,
        encodedLanguageId,
        IGrammarConfiguration(
          embeddedLanguages: embeddedLanguages,
          tokenTypes: grammarDefinition.tokenTypes,
          balancedBracketSelectors: grammarDefinition.balancedBracketSelectors,
          unbalancedBracketSelectors:
              grammarDefinition.unbalancedBracketSelectors,
        ),
      );
    } on StateError catch (err) {
      if (err.message.startsWith('No grammar provided for')) {
        // No TM grammar defined
        throw StateError(missingTMGrammarErrorMessage);
      }
      rethrow;
    }

    return ICreateGrammarResult(
      languageId: languageId,
      grammar: grammar,
      initialState: _initialState,
      containsEmbeddedLanguages: containsEmbeddedLanguages,
      sourceExtensionId: grammarDefinition.sourceExtensionId,
    );
  }

  void dispose() => _grammarRegistry.dispose();
}
