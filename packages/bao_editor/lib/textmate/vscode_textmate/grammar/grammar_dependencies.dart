// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/grammar/grammarDependencies.ts (MIT, see LICENSE.md).

import 'dart:collection';

import '../js_semantics.dart';
import '../utils.dart';
import 'grammar.dart';

sealed class AbsoluteRuleReference {
  String get scopeName;

  String toKey();
}

/// References the top level rule of a grammar with the given scope name.
class TopLevelRuleReference implements AbsoluteRuleReference {
  TopLevelRuleReference(this.scopeName);

  @override
  final String scopeName;

  @override
  String toKey() {
    return scopeName;
  }
}

/// References a rule of a grammar in the top level repository section with the given name.
class TopLevelRepositoryRuleReference implements AbsoluteRuleReference {
  TopLevelRepositoryRuleReference(this.scopeName, this.ruleName);

  @override
  final String scopeName;
  final String ruleName;

  @override
  String toKey() {
    return '$scopeName#$ruleName';
  }
}

class ExternalReferenceCollector {
  final List<AbsoluteRuleReference> _references = <AbsoluteRuleReference>[];
  final Set<String> _seenReferenceKeys = <String>{};

  List<AbsoluteRuleReference> get references {
    return _references;
  }

  /// Raw rules already visited, by identity (upstream: a `Set<IRawRule>`).
  final Set<Object?> visitedRule = LinkedHashSet<Object?>.identity();

  void add(AbsoluteRuleReference reference) {
    final key = reference.toKey();
    if (_seenReferenceKeys.contains(key)) {
      return;
    }
    _seenReferenceKeys.add(key);
    _references.add(reference);
  }
}

class ScopeDependencyProcessor {
  ScopeDependencyProcessor(this.repo, this.initialScopeName) {
    seenFullScopeRequests.add(initialScopeName);
    Q = [TopLevelRuleReference(initialScopeName)];
  }

  final Set<String> seenFullScopeRequests = <String>{};
  final Set<String> seenPartialScopeRequests = <String>{};
  // ignore: non_constant_identifier_names
  late List<AbsoluteRuleReference> Q;

  final IGrammarRepository repo;
  final String initialScopeName;

  void processQueue() {
    final q = Q;
    Q = [];

    final deps = ExternalReferenceCollector();
    for (final dep in q) {
      _collectReferencesOfReference(dep, initialScopeName, repo, deps);
    }

    for (final dep in deps.references) {
      if (dep is TopLevelRuleReference) {
        if (seenFullScopeRequests.contains(dep.scopeName)) {
          // already processed
          continue;
        }
        seenFullScopeRequests.add(dep.scopeName);
        Q.add(dep);
      } else {
        if (seenFullScopeRequests.contains(dep.scopeName)) {
          // already processed in full
          continue;
        }
        if (seenPartialScopeRequests.contains(dep.toKey())) {
          // already processed
          continue;
        }
        seenPartialScopeRequests.add(dep.toKey());
        Q.add(dep);
      }
    }
  }
}

void _collectReferencesOfReference(
  AbsoluteRuleReference reference,
  String baseGrammarScopeName,
  IGrammarRepository repo,
  ExternalReferenceCollector result,
) {
  final selfGrammar = repo.lookup(reference.scopeName);
  if (selfGrammar == null) {
    if (reference.scopeName == baseGrammarScopeName) {
      throw StateError('No grammar provided for <$baseGrammarScopeName>');
    }
    return;
  }

  final baseGrammar = repo.lookup(baseGrammarScopeName)?.map;

  if (reference is TopLevelRuleReference) {
    _collectExternalReferencesInTopLevelRule(
      _Context(baseGrammar, selfGrammar.map, null),
      result,
    );
  } else if (reference is TopLevelRepositoryRuleReference) {
    _collectExternalReferencesInTopLevelRepositoryRule(
      reference.ruleName,
      _Context(
        baseGrammar,
        selfGrammar.map,
        jsGet(selfGrammar.map, 'repository'),
      ),
      result,
    );
  }

  final injections = repo.injections(reference.scopeName);
  if (injections != null) {
    for (final injection in injections) {
      result.add(TopLevelRuleReference(injection));
    }
  }
}

/// Upstream's `Context` / `ContextWithRepository`. The grammars are raw
/// (as registered, not copied); `baseGrammar` is null when upstream's is
/// `undefined`.
class _Context {
  _Context(this.baseGrammar, this.selfGrammar, this.repository);

  final Object? baseGrammar;
  final Object? selfGrammar;
  final Object? repository;
}

void _collectExternalReferencesInTopLevelRepositoryRule(
  String ruleName,
  _Context context,
  ExternalReferenceCollector result,
) {
  final repository = context.repository;
  if (jsTruthy(repository) && jsTruthy(jsGet(repository, ruleName))) {
    final rule = jsGet(repository, ruleName);
    _collectExternalReferencesInRules([rule], context, result);
  }
}

void _collectExternalReferencesInTopLevelRule(
  _Context context,
  ExternalReferenceCollector result,
) {
  final selfGrammar = context.selfGrammar;
  final patterns = jsGet(selfGrammar, 'patterns');
  if (jsTruthy(patterns) && patterns is List) {
    _collectExternalReferencesInRules(
      patterns,
      _Context(
        context.baseGrammar,
        selfGrammar,
        jsGet(selfGrammar, 'repository'),
      ),
      result,
    );
  }
  final injections = jsGet(selfGrammar, 'injections');
  if (jsTruthy(injections)) {
    _collectExternalReferencesInRules(
      [for (final entry in jsForInEntries(injections)) entry.value],
      _Context(
        context.baseGrammar,
        selfGrammar,
        jsGet(selfGrammar, 'repository'),
      ),
      result,
    );
  }
}

void _collectExternalReferencesInRules(
  List<Object?> rules,
  _Context context,
  ExternalReferenceCollector result,
) {
  for (final rule in rules) {
    if (result.visitedRule.contains(rule)) {
      continue;
    }
    result.visitedRule.add(rule);

    final ruleRepository = jsGet(rule, 'repository');
    final patternRepository = jsTruthy(ruleRepository)
        ? mergeObjects(<String, Object?>{}, [
            context.repository,
            ruleRepository,
          ])
        : context.repository;

    final rulePatterns = jsGet(rule, 'patterns');
    if (rulePatterns is List) {
      _collectExternalReferencesInRules(
        rulePatterns,
        _Context(context.baseGrammar, context.selfGrammar, patternRepository),
        result,
      );
    }

    final include = jsGet(rule, 'include');

    if (!jsTruthy(include)) {
      continue;
    }
    if (include is! String) {
      jsTypeError('include.indexOf is not a function');
    }

    final reference = parseInclude(include);

    switch (reference) {
      case BaseReference():
        _collectExternalReferencesInTopLevelRule(
          _Context(
            context.baseGrammar,
            context.baseGrammar,
            context.repository,
          ),
          result,
        );
        break;
      case SelfReference():
        _collectExternalReferencesInTopLevelRule(context, result);
        break;
      case RelativeReference(:final ruleName):
        _collectExternalReferencesInTopLevelRepositoryRule(
          ruleName,
          _Context(context.baseGrammar, context.selfGrammar, patternRepository),
          result,
        );
        break;
      case TopLevelReference(:final scopeName):
      case TopLevelRepositoryReference(:final scopeName):
        final Object? selfGrammar =
            scopeName == jsGet(context.selfGrammar, 'scopeName')
            ? context.selfGrammar
            : scopeName == jsGet(context.baseGrammar, 'scopeName')
            ? context.baseGrammar
            : null;
        if (selfGrammar != null) {
          final newContext = _Context(
            context.baseGrammar,
            selfGrammar,
            patternRepository,
          );
          if (reference is TopLevelRepositoryReference) {
            _collectExternalReferencesInTopLevelRepositoryRule(
              reference.ruleName,
              newContext,
              result,
            );
          } else {
            _collectExternalReferencesInTopLevelRule(newContext, result);
          }
        } else {
          if (reference is TopLevelRepositoryReference) {
            result.add(
              TopLevelRepositoryRuleReference(scopeName, reference.ruleName),
            );
          } else {
            result.add(TopLevelRuleReference(scopeName));
          }
        }
        break;
    }
  }
}

sealed class IncludeReference {
  const IncludeReference();
}

class BaseReference extends IncludeReference {
  const BaseReference();
}

class SelfReference extends IncludeReference {
  const SelfReference();
}

class RelativeReference extends IncludeReference {
  const RelativeReference(this.ruleName);

  final String ruleName;
}

class TopLevelReference extends IncludeReference {
  const TopLevelReference(this.scopeName);

  final String scopeName;
}

class TopLevelRepositoryReference extends IncludeReference {
  const TopLevelRepositoryReference(this.scopeName, this.ruleName);

  final String scopeName;
  final String ruleName;
}

IncludeReference parseInclude(String include) {
  if (include == r'$base') {
    return const BaseReference();
  } else if (include == r'$self') {
    return const SelfReference();
  }

  final indexOfSharp = include.indexOf('#');
  if (indexOfSharp == -1) {
    return TopLevelReference(include);
  } else if (indexOfSharp == 0) {
    return RelativeReference(include.substring(1));
  } else {
    final scopeName = include.substring(0, indexOfSharp);
    final ruleName = include.substring(indexOfSharp + 1);
    return TopLevelRepositoryReference(scopeName, ruleName);
  }
}
