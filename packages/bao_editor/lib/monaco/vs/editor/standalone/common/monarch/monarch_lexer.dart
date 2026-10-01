/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/standalone/common/monarch/monarchLexer.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
//
// The stack, line-state, collectors, nested-language and action algorithms are
// ported, not a regex-scanning substitute. Offsets are UTF-16 code units.
// VS Code's global registry, theme/language/configuration services, automatic
// registry-change propagation and Disposable lifecycle are NOT provided. Hosts
// supply the explicit adapters below, update maxTokenizationLineLength, and
// invalidate tokenization when a dependency changes. Token theme construction,
// font metadata and language loading themselves belong to those hosts.
// As upstream, action.transform is unsupported. Fractional/non-finite goBack
// values are rejected rather than allowing non-integral string/token offsets.

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../../common/encoded_token_attributes.dart';
import 'monarch_common.dart' as monarch;

/// The portion of languages.IState needed at a tokenization boundary.
abstract interface class IState {
  IState clone();
  bool equals(IState other);
}

final class _NullState implements IState {
  const _NullState();

  @override
  IState clone() => this;

  @override
  bool equals(IState other) => identical(this, other);
}

const IState nullState = _NullState();

/// A classic token start, scope and language (not an end-offset LineTokens).
final class Token {
  const Token(this.offset, this.type, this.language);

  final int offset;
  final String type;
  final String language;

  @override
  String toString() => '($offset, $type)';
}

final class TokenizationResult {
  const TokenizationResult(this.tokens, this.endState);

  final List<Token> tokens;
  final IState endState;
}

final class EncodedTokenizationResult {
  const EncodedTokenizationResult(this.tokens, this.endState);

  /// Interleaved start offset / metadata pairs, as in upstream (not end offsets).
  final Uint32List tokens;
  final IState endState;

  /// Monarch does not produce font overrides, including for embedded tokens.
  List<Never> get fontInfo => const [];
}

abstract interface class ITokenizationSupport {
  IState getInitialState();
  TokenizationResult tokenize(String line, bool hasEOL, IState lineState);
  EncodedTokenizationResult tokenizeEncoded(
    String line,
    bool hasEOL,
    IState lineState,
  );
}

/// No theme or language IDs are invented by the lexer. Encoded tokenization
/// requires the caller's actual codec and token-theme matcher.
final class MonarchTokenTheme {
  const MonarchTokenTheme({
    required this.encodeLanguageId,
    required this.match,
  });

  final int Function(String languageId) encodeLanguageId;
  final int Function(int encodedLanguageId, String token) match;
}

/// Narrow, instance-local replacement for the global TokenizationRegistry and
/// the language-service operations used by Monarch. A synchronous lookup is
/// sufficient for preloaded languages; asynchronous loaders are optional.
final class MonarchEmbeddingSupport {
  const MonarchEmbeddingSupport({
    required this.getTokenizationSupport,
    this.languageIdByName,
    this.languageIdByMimeType,
    this.isRegisteredLanguageId,
    this.requestBasicLanguageFeatures,
    this.isResolved,
    this.loadLanguage,
  });

  final ITokenizationSupport? Function(String languageId)
  getTokenizationSupport;
  final String? Function(String name)? languageIdByName;
  final String? Function(String mimeType)? languageIdByMimeType;
  final bool Function(String languageId)? isRegisteredLanguageId;
  final void Function(String languageId)? requestBasicLanguageFeatures;
  final bool Function(String languageId)? isResolved;

  /// Must be idempotent, like upstream getOrCreate. On completion the support
  /// should be available through getTokenizationSupport, or resolved as absent.
  final Future<void> Function(String languageId)? loadLanguage;

  bool _isRegistered(String id) =>
      isRegisteredLanguageId?.call(id) ?? getTokenizationSupport(id) != null;

  bool _isResolved(String id) =>
      isResolved?.call(id) ??
      (loadLanguage == null || getTokenizationSupport(id) != null);

  String _resolve(String name) {
    final byName = languageIdByName?.call(name);
    if (byName != null && byName.isNotEmpty) return byName;
    final byMime = languageIdByMimeType?.call(name);
    return byMime != null && byMime.isNotEmpty ? byMime : name;
  }
}

final class MonarchLoadStatus {
  const MonarchLoadStatus.loaded() : promise = null;
  const MonarchLoadStatus.loading(this.promise);

  final Future<void>? promise;
  bool get loaded => promise == null;
}

const _cacheStackDepth = 5;

final class _MonarchStackElementFactory {
  static final _entries = <String, MonarchStackElement>{};

  static MonarchStackElement create(MonarchStackElement? parent, String state) {
    if (parent != null && parent.depth >= _cacheStackDepth) {
      return MonarchStackElement(parent, state);
    }
    var id = MonarchStackElement.getStackElementId(parent);
    if (id.isNotEmpty) id += '|';
    id += state;
    return _entries.putIfAbsent(id, () => MonarchStackElement(parent, state));
  }
}

final class MonarchStackElement {
  MonarchStackElement(this.parent, this.state)
    : depth = (parent?.depth ?? 0) + 1;

  final MonarchStackElement? parent;
  final String state;
  final int depth;

  static String getStackElementId(MonarchStackElement? element) {
    final states = <String>[];
    while (element != null) {
      states.add(element.state);
      element = element.parent;
    }
    return states.join('|');
  }

  bool equals(MonarchStackElement other) {
    MonarchStackElement? a = this;
    MonarchStackElement? b = other;
    while (a != null && b != null) {
      if (identical(a, b)) return true;
      if (a.state != b.state) return false;
      a = a.parent;
      b = b.parent;
    }
    return a == null && b == null;
  }

  MonarchStackElement push(String state) =>
      _MonarchStackElementFactory.create(this, state);

  MonarchStackElement? pop() => parent;

  MonarchStackElement popall() {
    var result = this;
    while (result.parent != null) {
      result = result.parent!;
    }
    return result;
  }

  MonarchStackElement switchTo(String state) =>
      _MonarchStackElementFactory.create(parent, state);
}

final class EmbeddedLanguageData {
  const EmbeddedLanguageData(this.languageId, this.state);

  final String languageId;
  final IState state;

  bool equals(EmbeddedLanguageData other) =>
      languageId == other.languageId && state.equals(other.state);

  EmbeddedLanguageData clone() {
    final stateClone = state.clone();
    if (identical(stateClone, state)) return this;
    // Pinned upstream calls clone but retains the original embedded state.
    return EmbeddedLanguageData(languageId, state);
  }
}

final class _MonarchLineStateFactory {
  static final _entries = <String, MonarchLineState>{};

  static MonarchLineState create(
    MonarchStackElement stack,
    EmbeddedLanguageData? embeddedLanguageData,
  ) {
    if (embeddedLanguageData != null || stack.depth >= _cacheStackDepth) {
      return MonarchLineState(stack, embeddedLanguageData);
    }
    final id = MonarchStackElement.getStackElementId(stack);
    return _entries.putIfAbsent(id, () => MonarchLineState(stack, null));
  }
}

final class MonarchLineState implements IState {
  const MonarchLineState(this.stack, this.embeddedLanguageData);

  final MonarchStackElement stack;
  final EmbeddedLanguageData? embeddedLanguageData;

  @override
  MonarchLineState clone() {
    final embeddedClone = embeddedLanguageData?.clone();
    if (identical(embeddedClone, embeddedLanguageData)) return this;
    // Deliberately retains the pinned upstream clone behavior (see above).
    return _MonarchLineStateFactory.create(stack, embeddedLanguageData);
  }

  @override
  bool equals(IState other) {
    if (other is! MonarchLineState || !stack.equals(other.stack)) return false;
    final embedded = embeddedLanguageData;
    final otherEmbedded = other.embeddedLanguageData;
    if (embedded == null && otherEmbedded == null) return true;
    return embedded != null &&
        otherEmbedded != null &&
        embedded.equals(otherEmbedded);
  }
}

abstract interface class _MonarchTokensCollector {
  void enterLanguage(String languageId);
  void emit(int startOffset, String type);
  IState nestedLanguageTokenize(
    String line,
    bool hasEOL,
    EmbeddedLanguageData data,
    int offsetDelta,
  );
}

final class _MonarchClassicTokensCollector implements _MonarchTokensCollector {
  _MonarchClassicTokensCollector(this.embeddingSupport);

  final MonarchEmbeddingSupport? embeddingSupport;
  final _tokens = <Token>[];
  String? _languageId;
  String? _lastTokenType;
  String? _lastTokenLanguage;

  @override
  void enterLanguage(String languageId) => _languageId = languageId;

  @override
  void emit(int startOffset, String type) {
    if (_lastTokenType == type && _lastTokenLanguage == _languageId) return;
    _lastTokenType = type;
    _lastTokenLanguage = _languageId;
    _tokens.add(Token(startOffset, type, _languageId!));
  }

  @override
  IState nestedLanguageTokenize(
    String line,
    bool hasEOL,
    EmbeddedLanguageData data,
    int offsetDelta,
  ) {
    final support = embeddingSupport?.getTokenizationSupport(data.languageId);
    if (support == null) {
      enterLanguage(data.languageId);
      emit(offsetDelta, '');
      return data.state;
    }
    final result = support.tokenize(line, hasEOL, data.state);
    if (offsetDelta != 0) {
      for (final token in result.tokens) {
        _tokens.add(
          Token(token.offset + offsetDelta, token.type, token.language),
        );
      }
    } else {
      _tokens.addAll(result.tokens);
    }
    _lastTokenType = null;
    _lastTokenLanguage = null;
    _languageId = null;
    return result.endState;
  }

  TokenizationResult finalize(MonarchLineState endState) =>
      TokenizationResult(_tokens, endState);
}

final class _MonarchModernTokensCollector implements _MonarchTokensCollector {
  _MonarchModernTokensCollector(this.embeddingSupport, this.theme);

  final MonarchEmbeddingSupport? embeddingSupport;
  final MonarchTokenTheme theme;
  Uint32List? _prependTokens;
  List<int> _tokens = [];
  int _currentLanguageId = LanguageId.nullId;
  int _lastTokenMetadata = 0;

  @override
  void enterLanguage(String languageId) {
    _currentLanguageId = theme.encodeLanguageId(languageId);
  }

  @override
  void emit(int startOffset, String type) {
    final metadata =
        (theme.match(_currentLanguageId, type) |
            MetadataConsts.balancedBracketsMask) &
        0xffffffff;
    if (_lastTokenMetadata == metadata) return;
    _lastTokenMetadata = metadata;
    _tokens.addAll([startOffset, metadata]);
  }

  static Uint32List _merge(Uint32List? a, List<int> b, Uint32List? c) {
    final aLen = a?.length ?? 0;
    final bLen = b.length;
    final cLen = c?.length ?? 0;
    if (aLen == 0 && bLen == 0 && cLen == 0) return Uint32List(0);
    if (aLen == 0 && bLen == 0) return c!;
    if (bLen == 0 && cLen == 0) return a!;
    final result = Uint32List(aLen + bLen + cLen);
    if (a != null) result.setAll(0, a);
    result.setAll(aLen, b);
    if (c != null) result.setAll(aLen + bLen, c);
    return result;
  }

  @override
  IState nestedLanguageTokenize(
    String line,
    bool hasEOL,
    EmbeddedLanguageData data,
    int offsetDelta,
  ) {
    final support = embeddingSupport?.getTokenizationSupport(data.languageId);
    if (support == null) {
      enterLanguage(data.languageId);
      emit(offsetDelta, '');
      return data.state;
    }
    final result = support.tokenizeEncoded(line, hasEOL, data.state);
    if (offsetDelta != 0) {
      for (var i = 0; i < result.tokens.length; i += 2) {
        result.tokens[i] += offsetDelta;
      }
    }
    _prependTokens = _merge(_prependTokens, _tokens, result.tokens);
    _tokens = [];
    _currentLanguageId = 0;
    _lastTokenMetadata = 0;
    return result.endState;
  }

  EncodedTokenizationResult finalize(MonarchLineState endState) =>
      EncodedTokenizationResult(
        _merge(_prependTokens, _tokens, null),
        endState,
      );
}

final class _GroupMatching {
  _GroupMatching(this.matches, this.rule, this.groups);

  final List<String?> matches;
  final monarch.IRule? rule;
  final List<({monarch.FuzzyAction action, String matched})> groups;
}

/// The pinned Monarch execution engine. Service integration is intentionally
/// explicit and per instance; classic tokenization needs no theme adapter.
final class MonarchTokenizer implements ITokenizationSupport {
  MonarchTokenizer(
    this.languageId,
    this.lexer, {
    this.embeddingSupport,
    this.tokenTheme,
    this.maxTokenizationLineLength = 20000,
    this.onLog,
  });

  final String languageId;
  final monarch.ILexer lexer;
  final MonarchEmbeddingSupport? embeddingSupport;
  final MonarchTokenTheme? tokenTheme;
  final void Function(String message)? onLog;
  int maxTokenizationLineLength;
  final _embeddedLanguages = <String>{};

  /// Registered languages encountered through nextEmbedded. The host can use
  /// this to invalidate this tokenizer when an embedded tokenizer changes.
  Set<String> get embeddedLanguages => Set.unmodifiable(_embeddedLanguages);

  MonarchLoadStatus getLoadStatus() {
    final support = embeddingSupport;
    if (support == null) return const MonarchLoadStatus.loaded();
    final promises = <Future<void>>[];
    for (final id in _embeddedLanguages) {
      final nested = support.getTokenizationSupport(id);
      if (nested != null) {
        if (nested is MonarchTokenizer) {
          final status = nested.getLoadStatus();
          if (!status.loaded) promises.add(status.promise!);
        }
        continue;
      }
      if (!support._isResolved(id) && support.loadLanguage != null) {
        promises.add(support.loadLanguage!(id));
      }
    }
    if (promises.isEmpty) return const MonarchLoadStatus.loaded();
    return MonarchLoadStatus.loading(Future.wait(promises).then((_) {}));
  }

  @override
  MonarchLineState getInitialState() => _MonarchLineStateFactory.create(
    _MonarchStackElementFactory.create(null, lexer.start!),
    null,
  );

  @override
  TokenizationResult tokenize(String line, bool hasEOL, IState lineState) {
    if (line.length >= maxTokenizationLineLength) {
      return TokenizationResult([Token(0, '', languageId)], lineState);
    }
    final collector = _MonarchClassicTokensCollector(embeddingSupport);
    return collector.finalize(
      _tokenize(line, hasEOL, lineState as MonarchLineState, collector),
    );
  }

  @override
  EncodedTokenizationResult tokenizeEncoded(
    String line,
    bool hasEOL,
    IState lineState,
  ) {
    final theme = tokenTheme;
    if (theme == null) {
      throw StateError('tokenizeEncoded requires a MonarchTokenTheme adapter');
    }
    if (line.length >= maxTokenizationLineLength) {
      final metadata =
          (theme.encodeLanguageId(languageId) <<
              MetadataConsts.languageIdOffset) |
          (ColorId.defaultForeground << MetadataConsts.foregroundOffset) |
          (ColorId.defaultBackground << MetadataConsts.backgroundOffset);
      return EncodedTokenizationResult(
        Uint32List.fromList([0, metadata]),
        lineState,
      );
    }
    final collector = _MonarchModernTokensCollector(embeddingSupport, theme);
    return collector.finalize(
      _tokenize(line, hasEOL, lineState as MonarchLineState, collector),
    );
  }

  MonarchLineState _tokenize(
    String line,
    bool hasEOL,
    MonarchLineState state,
    _MonarchTokensCollector collector,
  ) => state.embeddedLanguageData != null
      ? _nestedTokenize(line, hasEOL, state, 0, collector)
      : _myTokenize(line, hasEOL, state, 0, collector);

  List<monarch.IRule> _rules(String state) {
    final rules = lexer.tokenizer[state] ?? monarch.findRules(lexer, state);
    if (rules == null) {
      throw monarch.createError(
        lexer,
        'tokenizer state is not defined: $state',
      );
    }
    return rules;
  }

  int _findLeavingNestedLanguageOffset(String line, MonarchLineState state) {
    var popOffset = -1;
    var hasEmbeddedPopRule = false;
    for (final rule in _rules(state.stack.state)) {
      final action = rule.action;
      if (action is! monarch.IAction ||
          !(action.nextEmbedded == '@pop' ||
              action.hasEmbeddedEndInCases == true)) {
        continue;
      }
      hasEmbeddedPopRule = true;
      var regex = rule.resolveRegex(state.stack.state);
      final source = regex.pattern;
      if (source.startsWith('^(?:') && source.endsWith(')')) {
        regex = RegExp(
          source.substring(4, source.length - 1),
          caseSensitive: regex.isCaseSensitive,
          unicode: regex.isUnicode,
        );
      }
      final result = regex.firstMatch(line)?.start ?? -1;
      if (result == -1 || (result != 0 && rule.matchOnlyAtLineStart)) continue;
      if (popOffset == -1 || result < popOffset) popOffset = result;
    }
    if (!hasEmbeddedPopRule) {
      throw monarch.createError(
        lexer,
        'no rule containing nextEmbedded: "@pop" in tokenizer embedded state: '
        '${state.stack.state}',
      );
    }
    return popOffset;
  }

  MonarchLineState _nestedTokenize(
    String line,
    bool hasEOL,
    MonarchLineState lineState,
    int offsetDelta,
    _MonarchTokensCollector collector,
  ) {
    final popOffset = _findLeavingNestedLanguageOffset(line, lineState);
    if (popOffset == -1) {
      final nestedEndState = collector.nestedLanguageTokenize(
        line,
        hasEOL,
        lineState.embeddedLanguageData!,
        offsetDelta,
      );
      return _MonarchLineStateFactory.create(
        lineState.stack,
        EmbeddedLanguageData(
          lineState.embeddedLanguageData!.languageId,
          nestedEndState,
        ),
      );
    }
    final nestedLine = line.substring(0, popOffset);
    if (nestedLine.isNotEmpty) {
      collector.nestedLanguageTokenize(
        nestedLine,
        false,
        lineState.embeddedLanguageData!,
        offsetDelta,
      );
    }
    return _myTokenize(
      line.substring(popOffset),
      hasEOL,
      lineState,
      offsetDelta + popOffset,
      collector,
    );
  }

  String _safeRuleName(monarch.IRule? rule) => rule?.name ?? '(unknown)';

  MonarchLineState _myTokenize(
    String lineWithoutLF,
    bool hasEOL,
    MonarchLineState lineState,
    int offsetDelta,
    _MonarchTokensCollector collector,
  ) {
    collector.enterLanguage(languageId);
    final lineWithoutLFLength = lineWithoutLF.length;
    final line = hasEOL && lexer.includeLF ? '$lineWithoutLF\n' : lineWithoutLF;
    final lineLength = line.length;
    var embeddedLanguageData = lineState.embeddedLanguageData;
    var stack = lineState.stack;
    var pos = 0;
    _GroupMatching? groupMatching;
    // Upstream #1235: evaluate rules once even for an empty line.
    var forceEvaluation = true;

    while (forceEvaluation || pos < lineLength) {
      final pos0 = pos;
      final stackLen0 = stack.depth;
      final groupLen0 = groupMatching?.groups.length ?? 0;
      final state = stack.state;
      List<String?>? matches;
      String? matched;
      Object? action;
      monarch.IRule? rule;
      String? enteringEmbeddedLanguage;

      if (groupMatching != null) {
        matches = groupMatching.matches;
        final entry = groupMatching.groups.removeAt(0);
        matched = entry.matched;
        action = entry.action;
        rule = groupMatching.rule;
        if (groupMatching.groups.isEmpty) groupMatching = null;
      } else {
        if (!forceEvaluation && pos >= lineLength) break;
        forceEvaluation = false;
        final restOfLine = line.substring(pos);
        for (final candidate in _rules(state)) {
          if (pos == 0 || !candidate.matchOnlyAtLineStart) {
            final match = candidate.resolveRegex(state).firstMatch(restOfLine);
            if (match != null) {
              matches = [
                for (var i = 0; i <= match.groupCount; i++) match.group(i),
              ];
              matched = matches[0];
              action = candidate.action;
              // Upstream shadows `rule` in this loop; diagnostic names remain
              // (unknown). Preserve this rather than changing error semantics.
              break;
            }
          }
        }
      }

      if (matches == null) {
        matches = [''];
        matched = '';
      }
      if (action == null || action == '') {
        if (pos < lineLength) {
          matched = line.substring(pos, pos + 1);
          matches = [matched];
        }
        action = lexer.defaultToken;
      }
      if (matched == null) break;
      pos += matched.length;

      while (action is monarch.IAction && action.test != null) {
        action = action.test!(matched, matches, state, pos == lineLength);
      }

      Object? result;
      if (action is String || action is List) {
        result = action;
      } else if (action is monarch.IAction) {
        if (action.group != null) {
          result = action.group;
        } else if (action.token != null) {
          result = action.tokenSubst == true
              ? monarch.substituteMatches(
                  lexer,
                  action.token!,
                  matched,
                  matches,
                  state,
                )
              : action.token;
          if (_nonEmpty(action.nextEmbedded)) {
            if (action.nextEmbedded == '@pop') {
              if (embeddedLanguageData == null) {
                throw monarch.createError(
                  lexer,
                  'cannot pop embedded language if not inside one',
                );
              }
              embeddedLanguageData = null;
            } else if (embeddedLanguageData != null) {
              throw monarch.createError(
                lexer,
                'cannot enter embedded language from within an embedded language',
              );
            } else {
              enteringEmbeddedLanguage = monarch.substituteMatches(
                lexer,
                action.nextEmbedded!,
                matched,
                matches,
                state,
              );
            }
          }
          final goBack = action.goBack;
          if (goBack != null && goBack != 0) {
            if (!goBack.isFinite || goBack != goBack.truncateToDouble()) {
              throw monarch.createError(
                lexer,
                'goBack must be a finite integer',
              );
            }
            pos = math.max(0, pos - goBack.toInt());
          }
          if (_nonEmpty(action.switchTo)) {
            var nextState = monarch.substituteMatches(
              lexer,
              action.switchTo!,
              matched,
              matches,
              state,
            );
            if (nextState.startsWith('@')) nextState = nextState.substring(1);
            if (monarch.findRules(lexer, nextState) == null) {
              throw monarch.createError(
                lexer,
                "trying to switch to a state '$nextState' that is undefined in "
                'rule: ${_safeRuleName(rule)}',
              );
            }
            stack = stack.switchTo(nextState);
          } else if (action.transform != null) {
            throw monarch.createError(lexer, 'action.transform not supported');
          } else if (_nonEmpty(action.next)) {
            final next = action.next!;
            if (next == '@push') {
              if (stack.depth >= lexer.maxStack) {
                throw monarch.createError(
                  lexer,
                  'maximum tokenizer stack size reached: '
                  '[${stack.state},${stack.parent?.state},...]',
                );
              }
              stack = stack.push(state);
            } else if (next == '@pop') {
              if (stack.depth <= 1) {
                throw monarch.createError(
                  lexer,
                  'trying to pop an empty stack in rule: ${_safeRuleName(rule)}',
                );
              }
              stack = stack.pop()!;
            } else if (next == '@popall') {
              stack = stack.popall();
            } else {
              var nextState = monarch.substituteMatches(
                lexer,
                next,
                matched,
                matches,
                state,
              );
              if (nextState.startsWith('@')) nextState = nextState.substring(1);
              if (monarch.findRules(lexer, nextState) == null) {
                throw monarch.createError(
                  lexer,
                  "trying to set a next state '$nextState' that is undefined "
                  'in rule: ${_safeRuleName(rule)}',
                );
              }
              stack = stack.push(nextState);
            }
          }
          if (_nonEmpty(action.log)) {
            final message =
                '${lexer.languageId}: '
                '${monarch.substituteMatches(lexer, action.log!, matched, matches, state)}';
            if (onLog != null) {
              // monarch.log prepends the language id again in pinned upstream.
              onLog!('${lexer.languageId}: $message');
            } else {
              monarch.log(lexer, message);
            }
          }
        }
      }
      if (result == null) {
        throw monarch.createError(
          lexer,
          'lexer rule has no well-defined action in rule: ${_safeRuleName(rule)}',
        );
      }

      MonarchLineState computeNewStateForEmbeddedLanguage(String entering) {
        final id = embeddingSupport?._resolve(entering) ?? entering;
        final embedded = _getNestedEmbeddedLanguageData(id);
        if (pos < lineLength) {
          // String.substr in upstream clamps starts beyond the physical EOL.
          final rest = lineWithoutLF.substring(
            math.min(pos, lineWithoutLFLength),
          );
          return _nestedTokenize(
            rest,
            hasEOL,
            _MonarchLineStateFactory.create(stack, embedded),
            offsetDelta + pos,
            collector,
          );
        }
        return _MonarchLineStateFactory.create(stack, embedded);
      }

      if (result is List) {
        if (groupMatching != null && groupMatching.groups.isNotEmpty) {
          throw monarch.createError(
            lexer,
            'groups cannot be nested: ${_safeRuleName(rule)}',
          );
        }
        if (matches.length != result.length + 1) {
          throw monarch.createError(
            lexer,
            'matched number of groups does not match the number of actions '
            'in rule: ${_safeRuleName(rule)}',
          );
        }
        var totalLen = 0;
        for (var i = 1; i < matches.length; i++) {
          // Upstream also rejects a nonparticipating capture (accessing length
          // of undefined). Empty participating captures remain valid.
          totalLen += matches[i]!.length;
        }
        if (totalLen != matched.length) {
          throw monarch.createError(
            lexer,
            'with groups, all characters should be matched in consecutive '
            'groups in rule: ${_safeRuleName(rule)}',
          );
        }
        groupMatching = _GroupMatching(matches, rule, [
          for (var i = 0; i < result.length; i++)
            (
              action: result[i] as monarch.FuzzyAction,
              matched: matches[i + 1]!,
            ),
        ]);
        pos -= matched.length;
        continue;
      } else {
        if (result == '@rematch') {
          pos -= matched.length;
          matched = '';
          result = '';
          if (enteringEmbeddedLanguage != null) {
            return computeNewStateForEmbeddedLanguage(enteringEmbeddedLanguage);
          }
        }
        if (matched.isEmpty) {
          if (lineLength == 0 ||
              stackLen0 != stack.depth ||
              state != stack.state ||
              (groupMatching?.groups.length ?? 0) != groupLen0) {
            continue;
          }
          throw monarch.createError(
            lexer,
            'no progress in tokenizer in rule: ${_safeRuleName(rule)}',
          );
        }
        String tokenType;
        if (result is String && result.startsWith('@brackets')) {
          final rest = result.substring('@brackets'.length);
          final bracket = _findBracket(lexer, matched);
          if (bracket == null) {
            throw monarch.createError(
              lexer,
              '@brackets token returned but no bracket defined as: $matched',
            );
          }
          tokenType = monarch.sanitize('${bracket.token}$rest');
        } else {
          final token = result == '' ? '' : '$result${lexer.tokenPostfix}';
          tokenType = monarch.sanitize(token);
        }
        if (pos0 < lineWithoutLFLength) {
          collector.emit(pos0 + offsetDelta, tokenType);
        }
      }
      if (enteringEmbeddedLanguage != null) {
        return computeNewStateForEmbeddedLanguage(enteringEmbeddedLanguage);
      }
    }
    return _MonarchLineStateFactory.create(stack, embeddedLanguageData);
  }

  EmbeddedLanguageData _getNestedEmbeddedLanguageData(String id) {
    final support = embeddingSupport;
    if (support == null || !support._isRegistered(id)) {
      return EmbeddedLanguageData(id, nullState);
    }
    if (id != languageId) {
      support.requestBasicLanguageFeatures?.call(id);
      if (support.loadLanguage != null) unawaited(support.loadLanguage!(id));
      _embeddedLanguages.add(id);
    }
    return EmbeddedLanguageData(
      id,
      support.getTokenizationSupport(id)?.getInitialState() ?? nullState,
    );
  }
}

bool _nonEmpty(String? value) => value != null && value.isNotEmpty;

({String token, monarch.MonarchBracket bracketType})? _findBracket(
  monarch.ILexer lexer,
  String matched,
) {
  if (matched.isEmpty) return null;
  matched = monarch.fixCase(lexer, matched);
  for (final bracket in lexer.brackets) {
    if (bracket.open == matched) {
      return (token: bracket.token, bracketType: monarch.MonarchBracket.open);
    } else if (bracket.close == matched) {
      return (token: bracket.token, bracketType: monarch.MonarchBracket.close);
    }
  }
  return null;
}
