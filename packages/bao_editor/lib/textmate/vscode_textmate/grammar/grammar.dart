// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/grammar/grammar.ts (MIT, see LICENSE.md).

import 'dart:typed_data';

import '../encoded_token_attributes.dart';
import '../js_semantics.dart';
import '../main.dart';
import '../matcher.dart';
import '../rule.dart';
import '../theme.dart';
import '../utils.dart';
import 'basic_scopes_attribute_provider.dart';
import 'tokenize_string.dart';

Grammar createGrammar(
  ScopeName scopeName,
  IRawGrammar grammar,
  int initialLanguage,
  IEmbeddedLanguagesMap? embeddedLanguages,
  ITokenTypeMap? tokenTypes,
  BalancedBracketSelectors? balancedBracketSelectors,
  IGrammarRepositoryAndThemeProvider grammarRepository,
  IOnigLib onigLib,
) {
  return Grammar(
    scopeName,
    grammar,
    initialLanguage,
    embeddedLanguages,
    tokenTypes,
    balancedBracketSelectors,
    grammarRepository,
    onigLib,
  ); //TODO
}

abstract interface class IThemeProvider {
  StyleAttributes? themeMatch(ScopeStack scopePath);
  StyleAttributes getDefaults();
}

abstract interface class IGrammarRepository {
  IRawGrammar? lookup(ScopeName scopeName);

  /// Upstream types this as non-null but returns `undefined` for scopes
  /// without injections.
  List<ScopeName>? injections(ScopeName scopeName);
}

/// Upstream's `IGrammarRepository & IThemeProvider`.
abstract interface class IGrammarRepositoryAndThemeProvider
    implements IGrammarRepository, IThemeProvider {}

class Injection {
  Injection({
    required this.debugSelector,
    required this.matcher,
    required this.priority,
    required this.ruleId,
    required this.grammar,
  });

  final String debugSelector;
  final Matcher<List<String>> matcher;

  /// 0 is the default. -1 for 'L' and 1 for 'R'
  final int priority;
  final RuleId ruleId;

  /// The initialized raw grammar the rule comes from.
  final Map<String, Object?> grammar;
}

void _collectInjections(
  List<Injection> result,
  String selector,
  Object? rule,
  IRuleFactoryHelper ruleFactoryHelper,
  Map<String, Object?> grammar,
) {
  final matchers = createMatchers<List<String>>(selector, _nameMatcher);
  final ruleId = RuleFactory.getCompiledRuleId(
    rule,
    ruleFactoryHelper,
    grammar['repository'] as Map<String, Object?>,
  );
  for (final matcher in matchers) {
    result.add(
      Injection(
        debugSelector: selector,
        matcher: matcher.matcher,
        ruleId: ruleId,
        grammar: grammar,
        priority: matcher.priority,
      ),
    );
  }
}

bool _nameMatcher(List<ScopeName> identifers, List<ScopeName> scopes) {
  if (scopes.length < identifers.length) {
    return false;
  }
  var lastIndex = 0;
  return identifers.every((identifier) {
    for (var i = lastIndex; i < scopes.length; i++) {
      if (_scopesAreMatching(scopes[i], identifier)) {
        lastIndex = i + 1;
        return true;
      }
    }
    return false;
  });
}

bool _scopesAreMatching(String thisScopeName, String scopeName) {
  if (thisScopeName.isEmpty) {
    return false;
  }
  if (thisScopeName == scopeName) {
    return true;
  }
  final len = scopeName.length;
  return thisScopeName.length > len &&
      thisScopeName.startsWith(scopeName) &&
      thisScopeName.codeUnitAt(len) == 0x2E /* . */;
}

class Grammar implements IGrammar, IRuleFactoryHelper, IRuleRegistryAndOnigLib {
  Grammar(
    this._rootScopeName,
    IRawGrammar grammar,
    int initialLanguage,
    IEmbeddedLanguagesMap? embeddedLanguages,
    ITokenTypeMap? tokenTypes,
    this.balancedBracketSelectors,
    IGrammarRepositoryAndThemeProvider grammarRepository,
    this._onigLib,
  ) : _basicScopeAttributesProvider = BasicScopeAttributesProvider(
        initialLanguage,
        embeddedLanguages,
      ),
      _grammarRepository = grammarRepository {
    _grammar = initGrammar(grammar.map, null);

    if (tokenTypes != null) {
      for (final selector in jsObjectKeys(tokenTypes)) {
        final matchers = createMatchers<List<String>>(selector, _nameMatcher);
        for (final matcher in matchers) {
          _tokenTypeMatchers.add(
            TokenTypeMatcher(matcher.matcher, tokenTypes[selector]!),
          );
        }
      }
    }
  }

  RuleId _rootId = -1;
  int _lastRuleId = 0;
  final List<Rule?> _ruleId2desc = <Rule?>[null];
  final Map<String, Map<String, Object?>> _includedGrammars =
      <String, Map<String, Object?>>{};
  final IGrammarRepositoryAndThemeProvider _grammarRepository;
  late final Map<String, Object?> _grammar;
  List<Injection>? _injections;
  final BasicScopeAttributesProvider _basicScopeAttributesProvider;
  final List<TokenTypeMatcher> _tokenTypeMatchers = <TokenTypeMatcher>[];
  final ScopeName _rootScopeName;
  final BalancedBracketSelectors? balancedBracketSelectors;
  final IOnigLib _onigLib;

  IThemeProvider get themeProvider {
    return _grammarRepository;
  }

  void dispose() {
    for (final rule in _ruleId2desc) {
      if (rule != null) {
        rule.dispose();
      }
    }
  }

  @override
  OnigScanner createOnigScanner(List<String> sources) {
    return _onigLib.createOnigScanner(sources);
  }

  @override
  OnigString createOnigString(String sources) {
    return _onigLib.createOnigString(sources);
  }

  BasicScopeAttributes getMetadataForScope(String scope) {
    return _basicScopeAttributesProvider.getBasicScopeAttributes(scope);
  }

  List<Injection> _collectInjectionsList() {
    Map<String, Object?>? lookup(String scopeName) {
      if (scopeName == _rootScopeName) {
        return _grammar;
      }
      return getExternalGrammar(scopeName);
    }

    final result = <Injection>[];

    final scopeName = _rootScopeName;

    final grammar = lookup(scopeName);
    if (grammar != null) {
      // add injections from the current grammar
      final rawInjections = grammar['injections'];
      if (jsTruthy(rawInjections)) {
        for (final entry in jsForInEntries(rawInjections)) {
          _collectInjections(result, entry.key, entry.value, this, grammar);
        }
      }

      // add injection grammars contributed for the current scope

      final injectionScopeNames = _grammarRepository.injections(scopeName);
      if (injectionScopeNames != null) {
        for (final injectionScopeName in injectionScopeNames) {
          final injectionGrammar = getExternalGrammar(injectionScopeName);
          if (injectionGrammar != null) {
            final selector = injectionGrammar['injectionSelector'];
            if (jsTruthy(selector)) {
              _collectInjections(
                result,
                jsToString(selector),
                injectionGrammar,
                this,
                injectionGrammar,
              );
            }
          }
        }
      }
    }

    // sort by priority
    jsArraySort<Injection>(result, (i1, i2) => i1.priority - i2.priority);

    return result;
  }

  List<Injection> getInjections() {
    return _injections ??= _collectInjectionsList();
  }

  @override
  T registerRule<T extends Rule>(T Function(RuleId id) factory) {
    final id = ++_lastRuleId;
    final result = factory(ruleIdFromNumber(id));
    if (_ruleId2desc.length <= id) {
      _ruleId2desc.length = id + 1;
    }
    _ruleId2desc[id] = result;
    return result;
  }

  @override
  Rule? getRule(RuleId ruleId) {
    final id = ruleIdToNumber(ruleId);
    return (id >= 0 && id < _ruleId2desc.length) ? _ruleId2desc[id] : null;
  }

  @override
  Map<String, Object?>? getExternalGrammar(
    String scopeName, [
    Map<String, Object?>? repository,
  ]) {
    final included = _includedGrammars[scopeName];
    if (included != null) {
      return included;
    } else {
      final rawIncludedGrammar = _grammarRepository.lookup(scopeName);
      if (rawIncludedGrammar != null) {
        // console.log('LOADED GRAMMAR ' + pattern.include);
        return _includedGrammars[scopeName] = initGrammar(
          rawIncludedGrammar.map,
          repository?[r'$base'],
        );
      }
    }
    return null;
  }

  @override
  ITokenizeLineResult tokenizeLine(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]) {
    final r = _tokenize(
      lineText,
      prevState as StateStackImpl?,
      false,
      timeLimit,
    );
    return ITokenizeLineResult(
      tokens: r.lineTokens.getResult(r.ruleStack, r.lineLength),
      ruleStack: r.ruleStack,
      stoppedEarly: r.stoppedEarly,
      fonts: r.lineFonts.getResult(),
    );
  }

  @override
  ITokenizeLineResult2 tokenizeLine2(
    String lineText,
    StateStack? prevState, [
    int timeLimit = 0,
  ]) {
    final r = _tokenize(
      lineText,
      prevState as StateStackImpl?,
      true,
      timeLimit,
    );
    return ITokenizeLineResult2(
      tokens: r.lineTokens.getBinaryResult(r.ruleStack, r.lineLength),
      ruleStack: r.ruleStack,
      stoppedEarly: r.stoppedEarly,
      fonts: r.lineFonts.getResult(),
    );
  }

  _TokenizeResult _tokenize(
    String lineText,
    StateStackImpl? prevState,
    bool emitBinaryTokens,
    int timeLimit,
  ) {
    if (_rootId == -1) {
      final repository = _grammar['repository'] as Map<String, Object?>;
      _rootId = RuleFactory.getCompiledRuleId(
        repository[r'$self'],
        this,
        repository,
      );
      // This ensures ids are deterministic, and thus equal in renderer and webworker.
      getInjections();
    }

    bool isFirstLine;
    StateStackImpl state;
    if (prevState == null || identical(prevState, StateStackImpl.NULL)) {
      isFirstLine = true;
      final rawDefaultMetadata = _basicScopeAttributesProvider
          .getDefaultAttributes();
      final defaultStyle = themeProvider.getDefaults();
      final defaultMetadata = EncodedTokenAttributes.set(
        0,
        rawDefaultMetadata.languageId,
        rawDefaultMetadata.tokenType,
        null,
        defaultStyle.fontStyle,
        defaultStyle.foregroundId,
        defaultStyle.backgroundId,
      );
      final fontAttribute = FontAttribute.from(
        defaultStyle.fontFamily,
        defaultStyle.fontSize,
        defaultStyle.lineHeight,
      );

      final rootScopeName = getRule(_rootId)!.getName(null, null);

      AttributedScopeStack scopeList;
      if (rootScopeName != null && rootScopeName.isNotEmpty) {
        scopeList = AttributedScopeStack.createRootAndLookUpScopeName(
          rootScopeName,
          defaultMetadata,
          fontAttribute,
          this,
        );
      } else {
        scopeList = AttributedScopeStack.createRoot(
          'unknown',
          defaultMetadata,
          fontAttribute,
        );
      }

      state = StateStackImpl(
        null,
        _rootId,
        -1,
        -1,
        false,
        null,
        scopeList,
        scopeList,
      );
    } else {
      isFirstLine = false;
      prevState.reset();
      state = prevState;
    }

    lineText = '$lineText\n';
    final onigLineText = createOnigString(lineText);
    final lineLength = onigLineText.content.length;
    final lineTokens = LineTokens(
      emitBinaryTokens,
      lineText,
      _tokenTypeMatchers,
      balancedBracketSelectors,
    );
    final lineFonts = LineFonts();
    final r = tokenizeStringImpl(
      this,
      onigLineText,
      isFirstLine,
      0,
      state,
      lineTokens,
      lineFonts,
      true,
      timeLimit,
    );

    disposeOnigString(onigLineText);

    return _TokenizeResult(
      lineLength,
      lineTokens,
      lineFonts,
      r.stack,
      r.stoppedEarly,
    );
  }
}

class _TokenizeResult {
  _TokenizeResult(
    this.lineLength,
    this.lineTokens,
    this.lineFonts,
    this.ruleStack,
    this.stoppedEarly,
  );

  final int lineLength;
  final LineTokens lineTokens;
  final LineFonts lineFonts;
  final StateStackImpl ruleStack;
  final bool stoppedEarly;
}

/// Copies [grammar] and adds `$self` and `$base` to its repository.
Map<String, Object?> initGrammar(Map<String, Object?> grammar, Object? base) {
  grammar = clone(grammar);

  final rawRepository = grammar['repository'];
  final Map<String, Object?> repository;
  if (!jsTruthy(rawRepository)) {
    repository = <String, Object?>{};
  } else if (rawRepository is Map<String, Object?>) {
    repository = rawRepository;
  } else if (rawRepository is List) {
    // JavaScript sets `$self` on the array; its for…in keys are the
    // indices, as in this map.
    repository = <String, Object?>{
      for (final entry in jsForInEntries(rawRepository)) entry.key: entry.value,
    };
  } else {
    jsTypeError("Cannot create property '\$self' on $rawRepository");
  }
  grammar['repository'] = repository;
  final self = <String, Object?>{
    if (grammar.containsKey(r'$vscodeTextmateLocation'))
      r'$vscodeTextmateLocation': grammar[r'$vscodeTextmateLocation'],
    if (grammar.containsKey('patterns')) 'patterns': grammar['patterns'],
    if (grammar.containsKey('scopeName')) 'name': grammar['scopeName'],
  };
  repository[r'$self'] = self;
  repository[r'$base'] = jsTruthy(base) ? base : self;
  return grammar;
}

class AttributedScopeStack {
  static AttributedScopeStack? fromExtension(
    AttributedScopeStack? namesScopeList,
    List<AttributedScopeStackFrame> contentNameScopesList,
  ) {
    var current = namesScopeList;
    var scopeNames = namesScopeList?.scopePath;
    for (final frame in contentNameScopesList) {
      scopeNames = ScopeStack.pushAll(scopeNames, frame.scopeNames);
      current = AttributedScopeStack._(
        current,
        scopeNames!,
        frame.encodedTokenAttributes,
        null,
        null,
      );
    }
    return current;
  }

  static AttributedScopeStack createRoot(
    ScopeName scopeName,
    int tokenAttributes,
    FontAttribute fontAttribute,
  ) {
    return AttributedScopeStack._(
      null,
      ScopeStack(null, scopeName),
      tokenAttributes,
      fontAttribute,
      null,
    );
  }

  static AttributedScopeStack createRootAndLookUpScopeName(
    ScopeName scopeName,
    int tokenAttributes,
    FontAttribute fontAttribute,
    Grammar grammar,
  ) {
    final rawRootMetadata = grammar.getMetadataForScope(scopeName);
    final scopePath = ScopeStack(null, scopeName);
    final rootStyle = grammar.themeProvider.themeMatch(scopePath);

    final resolvedTokenAttributes = AttributedScopeStack._mergeAttributes(
      tokenAttributes,
      rawRootMetadata,
      rootStyle,
    );
    final resolvedFontAttributes = fontAttribute.withStyle(rootStyle);

    return AttributedScopeStack._(
      null,
      scopePath,
      resolvedTokenAttributes,
      resolvedFontAttributes,
      rootStyle,
    );
  }

  ScopeName get scopeName {
    return scopePath.scopeName;
  }

  /// Invariant:
  /// ```
  /// if (parent && !scopePath.extends(parent.scopePath)) {
  /// 	throw new Error();
  /// }
  /// ```
  AttributedScopeStack._(
    this.parent,
    this.scopePath,
    this.tokenAttributes,
    this.fontAttributes,
    this.styleAttributes,
  );

  final AttributedScopeStack? parent;
  final ScopeStack scopePath;
  final int tokenAttributes;
  final FontAttribute? fontAttributes;
  final StyleAttributes? styleAttributes;

  @override
  String toString() {
    return getScopeNames().join(' ');
  }

  bool equals(AttributedScopeStack other) {
    return AttributedScopeStack.equalsStacks(this, other);
  }

  /// Upstream's static `AttributedScopeStack.equals(a, b)`.
  static bool equalsStacks(AttributedScopeStack? a, AttributedScopeStack? b) {
    do {
      if (identical(a, b)) {
        return true;
      }

      if (a == null && b == null) {
        // End of list reached for both
        return true;
      }

      if (a == null || b == null) {
        // End of list reached only for one
        return false;
      }

      if (a.scopeName != b.scopeName ||
          a.tokenAttributes != b.tokenAttributes) {
        return false;
      }

      // Go to previous pair
      a = a.parent;
      b = b.parent;
    } while (true);
  }

  static int _mergeAttributes(
    int existingTokenAttributes,
    BasicScopeAttributes basicScopeAttributes,
    StyleAttributes? styleAttributes,
  ) {
    var fontStyle = FontStyle.notSet;
    var foreground = 0;
    var background = 0;

    if (styleAttributes != null) {
      fontStyle = styleAttributes.fontStyle;
      foreground = styleAttributes.foregroundId;
      background = styleAttributes.backgroundId;
    }

    return EncodedTokenAttributes.set(
      existingTokenAttributes,
      basicScopeAttributes.languageId,
      basicScopeAttributes.tokenType,
      null,
      fontStyle,
      foreground,
      background,
    );
  }

  AttributedScopeStack pushAttributed(ScopePath? scopePath, Grammar grammar) {
    if (scopePath == null) {
      return this;
    }

    if (!scopePath.contains(' ')) {
      // This is the common case and much faster

      return AttributedScopeStack._pushAttributed(this, scopePath, grammar);
    }

    final scopes = scopePath.split(' ');
    var result = this;
    for (final scope in scopes) {
      result = AttributedScopeStack._pushAttributed(result, scope, grammar);
    }
    return result;
  }

  static AttributedScopeStack _pushAttributed(
    AttributedScopeStack target,
    ScopeName scopeName,
    Grammar grammar,
  ) {
    final rawMetadata = grammar.getMetadataForScope(scopeName);

    final newPath = target.scopePath.push(scopeName);
    final scopeThemeMatchResult = grammar.themeProvider.themeMatch(newPath);
    final metadata = AttributedScopeStack._mergeAttributes(
      target.tokenAttributes,
      rawMetadata,
      scopeThemeMatchResult,
    );
    final fontAttributes = target.fontAttributes?.withStyle(
      scopeThemeMatchResult,
    );
    return AttributedScopeStack._(
      target,
      newPath,
      metadata,
      fontAttributes,
      scopeThemeMatchResult,
    );
  }

  List<String> getScopeNames() {
    return scopePath.getSegments();
  }

  /// The frames from [base] (exclusive) up to this stack, or null when
  /// [base] is not an ancestor (upstream returns `undefined`).
  List<AttributedScopeStackFrame>? getExtensionIfDefined(
    AttributedScopeStack? base,
  ) {
    final result = <AttributedScopeStackFrame>[];
    AttributedScopeStack? self = this;

    while (self != null && !identical(self, base)) {
      result.add(
        AttributedScopeStackFrame(
          encodedTokenAttributes: self.tokenAttributes,
          scopeNames: self.scopePath.getExtensionIfDefined(
            self.parent?.scopePath,
          )!,
        ),
      );
      self = self.parent;
    }
    return identical(self, base) ? result.reversed.toList() : null;
  }
}

class AttributedScopeStackFrame {
  const AttributedScopeStackFrame({
    required this.encodedTokenAttributes,
    required this.scopeNames,
  });

  final int encodedTokenAttributes;
  final List<String> scopeNames;
}

/// Represents a "pushed" state on the stack (as a linked list element).
class StateStackImpl implements StateStack {
  // TODO remove me
  // ignore: non_constant_identifier_names
  static final StateStackImpl NULL = StateStackImpl(
    null,
    0,
    0,
    0,
    false,
    null,
    null,
    null,
  );

  /// Invariant:
  /// ```
  /// if (contentNameScopesList !== nameScopesList && contentNameScopesList?.parent !== nameScopesList) {
  /// 	throw new Error();
  /// }
  /// if (this.parent && !nameScopesList.extends(this.parent.contentNameScopesList)) {
  /// 	throw new Error();
  /// }
  /// ```
  StateStackImpl(
    this.parent,
    this._ruleId,
    int enterPos,
    int anchorPos,
    this.beginRuleCapturedEOL,
    this.endRule,
    this.nameScopesList,
    this.contentNameScopesList,
  ) : depth = parent != null ? parent.depth + 1 : 1,
      _enterPos = enterPos,
      _anchorPos = anchorPos;

  /// The previous state on the stack (or null for the root state).
  final StateStackImpl? parent;

  /// The state (rule) that this element represents.
  final RuleId _ruleId;

  /// The position on the current line where this state was pushed.
  /// This is relevant only while tokenizing a line, to detect endless loops.
  /// Its value is meaningless across lines.
  int _enterPos;

  /// The captured anchor position when this stack element was pushed.
  /// This is relevant only while tokenizing a line, to restore the anchor position when popping.
  /// Its value is meaningless across lines.
  int _anchorPos;

  /// The depth of the stack.
  @override
  final int depth;

  /// The state has entered and captured \n. This means that the next line should have an anchorPosition of 0.
  final bool beginRuleCapturedEOL;

  /// The "pop" (end) condition for this state in case that it was dynamically generated through captured text.
  final String? endRule;

  /// The list of scopes containing the "name" for this state.
  final AttributedScopeStack? nameScopesList;

  /// The list of scopes containing the "contentName" (besides "name") for this state.
  /// This list **must** contain as an element `scopeName`.
  final AttributedScopeStack? contentNameScopesList;

  @override
  bool equals(StateStack? other) {
    if (other == null) {
      return false;
    }
    return StateStackImpl._equals(this, other as StateStackImpl);
  }

  static bool _equals(StateStackImpl a, StateStackImpl b) {
    if (identical(a, b)) {
      return true;
    }
    if (!_structuralEquals(a, b)) {
      return false;
    }
    return AttributedScopeStack.equalsStacks(
      a.contentNameScopesList,
      b.contentNameScopesList,
    );
  }

  /// A structural equals check. Does not take into account `scopes`.
  static bool _structuralEquals(StateStackImpl? a, StateStackImpl? b) {
    do {
      if (identical(a, b)) {
        return true;
      }

      if (a == null && b == null) {
        // End of list reached for both
        return true;
      }

      if (a == null || b == null) {
        // End of list reached only for one
        return false;
      }

      if (a.depth != b.depth ||
          a._ruleId != b._ruleId ||
          a.endRule != b.endRule) {
        return false;
      }

      // Go to previous pair
      a = a.parent;
      b = b.parent;
    } while (true);
  }

  @override
  StateStackImpl clone() {
    return this;
  }

  static void _reset(StateStackImpl? el) {
    while (el != null) {
      el._enterPos = -1;
      el._anchorPos = -1;
      el = el.parent;
    }
  }

  void reset() {
    StateStackImpl._reset(this);
  }

  StateStackImpl? pop() {
    return parent;
  }

  StateStackImpl safePop() {
    if (parent != null) {
      return parent!;
    }
    return this;
  }

  StateStackImpl push(
    RuleId ruleId,
    int enterPos,
    int anchorPos,
    bool beginRuleCapturedEOL,
    String? endRule,
    AttributedScopeStack? nameScopesList,
    AttributedScopeStack? contentNameScopesList,
  ) {
    return StateStackImpl(
      this,
      ruleId,
      enterPos,
      anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopesList,
    );
  }

  int getEnterPos() {
    return _enterPos;
  }

  int getAnchorPos() {
    return _anchorPos;
  }

  Rule? getRule(IRuleRegistry grammar) {
    return grammar.getRule(_ruleId);
  }

  @override
  String toString() {
    final r = <String>[];
    _writeString(r, 0);
    return '[${r.join(',')}]';
  }

  int _writeString(List<String> res, int outIndex) {
    if (parent != null) {
      outIndex = parent!._writeString(res, outIndex);
    }

    final entry =
        '($_ruleId, ${nameScopesList?.toString() ?? 'undefined'}, ${contentNameScopesList?.toString() ?? 'undefined'})';
    if (outIndex < res.length) {
      res[outIndex] = entry;
    } else {
      res.add(entry);
    }
    outIndex++;

    return outIndex;
  }

  StateStackImpl withContentNameScopesList(
    AttributedScopeStack contentNameScopeStack,
  ) {
    if (identical(contentNameScopesList, contentNameScopeStack)) {
      return this;
    }
    return parent!.push(
      _ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopeStack,
    );
  }

  StateStackImpl withEndRule(String endRule) {
    if (this.endRule == endRule) {
      return this;
    }
    return StateStackImpl(
      parent,
      _ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopesList,
    );
  }

  // Used to warn of endless loops
  bool hasSameRuleAs(StateStackImpl other) {
    StateStackImpl? el = this;
    while (el != null && el._enterPos == other._enterPos) {
      if (el._ruleId == other._ruleId) {
        return true;
      }
      el = el.parent;
    }
    return false;
  }

  StateStackFrame toStateStackFrame() {
    return StateStackFrame(
      ruleId: ruleIdToNumber(_ruleId),
      beginRuleCapturedEOL: beginRuleCapturedEOL,
      endRule: endRule,
      nameScopesList:
          nameScopesList?.getExtensionIfDefined(parent?.nameScopesList) ??
          <AttributedScopeStackFrame>[],
      contentNameScopesList:
          contentNameScopesList?.getExtensionIfDefined(nameScopesList) ??
          <AttributedScopeStackFrame>[],
    );
  }

  static StateStackImpl pushFrame(StateStackImpl? self, StateStackFrame frame) {
    final namesScopeList = AttributedScopeStack.fromExtension(
      self?.nameScopesList,
      frame.nameScopesList,
    );
    return StateStackImpl(
      self,
      ruleIdFromNumber(frame.ruleId),
      frame.enterPos ?? -1,
      frame.anchorPos ?? -1,
      frame.beginRuleCapturedEOL,
      frame.endRule,
      namesScopeList,
      AttributedScopeStack.fromExtension(
        namesScopeList,
        frame.contentNameScopesList,
      ),
    );
  }
}

class StateStackFrame {
  const StateStackFrame({
    required this.ruleId,
    this.enterPos,
    this.anchorPos,
    required this.beginRuleCapturedEOL,
    required this.endRule,
    required this.nameScopesList,
    required this.contentNameScopesList,
  });

  final int ruleId;
  final int? enterPos;
  final int? anchorPos;
  final bool beginRuleCapturedEOL;
  final String? endRule;
  final List<AttributedScopeStackFrame> nameScopesList;

  /// on top of nameScopesList
  final List<AttributedScopeStackFrame> contentNameScopesList;
}

class TokenTypeMatcher {
  const TokenTypeMatcher(this.matcher, this.type);

  final Matcher<List<String>> matcher;

  /// A `StandardTokenType`.
  final int type;
}

class BalancedBracketSelectors {
  BalancedBracketSelectors(
    List<String> balancedBracketScopes,
    List<String> unbalancedBracketScopes,
  ) {
    for (final selector in balancedBracketScopes) {
      if (selector == '*') {
        _allowAny = true;
        continue;
      }
      for (final m in createMatchers<List<String>>(selector, _nameMatcher)) {
        _balancedBracketScopes.add(m.matcher);
      }
    }
    for (final selector in unbalancedBracketScopes) {
      for (final m in createMatchers<List<String>>(selector, _nameMatcher)) {
        _unbalancedBracketScopes.add(m.matcher);
      }
    }
  }

  final List<Matcher<List<String>>> _balancedBracketScopes =
      <Matcher<List<String>>>[];
  final List<Matcher<List<String>>> _unbalancedBracketScopes =
      <Matcher<List<String>>>[];

  bool _allowAny = false;

  bool get matchesAlways {
    return _allowAny && _unbalancedBracketScopes.isEmpty;
  }

  bool get matchesNever {
    return _balancedBracketScopes.isEmpty && !_allowAny;
  }

  bool match(List<String> scopes) {
    for (final excluder in _unbalancedBracketScopes) {
      if (excluder(scopes)) {
        return false;
      }
    }

    for (final includer in _balancedBracketScopes) {
      if (includer(scopes)) {
        return true;
      }
    }
    return _allowAny;
  }
}

class LineTokens {
  LineTokens(
    this._emitBinaryTokens,
    String lineText,
    this._tokenTypeOverrides,
    this.balancedBracketSelectors,
  ) : // Don't merge tokens if the line contains RTL characters
      _mergeConsecutiveTokensWithEqualMetadata = !containsRTL(lineText);

  final bool _emitBinaryTokens;

  /// used only if `_emitBinaryTokens` is false.
  final List<IToken> _tokens = <IToken>[];

  /// used only if `_emitBinaryTokens` is true.
  final List<int> _binaryTokens = <int>[];

  int _lastTokenEndIndex = 0;

  final List<TokenTypeMatcher> _tokenTypeOverrides;
  final bool _mergeConsecutiveTokensWithEqualMetadata;
  final BalancedBracketSelectors? balancedBracketSelectors;

  void produce(StateStackImpl stack, int endIndex) {
    produceFromScopes(stack.contentNameScopesList, endIndex);
  }

  void produceFromScopes(AttributedScopeStack? scopesList, int endIndex) {
    if (_lastTokenEndIndex >= endIndex) {
      return;
    }

    if (_emitBinaryTokens) {
      var metadata = scopesList?.tokenAttributes ?? 0;
      var containsBalancedBrackets = false;
      final balancedBracketSelectors = this.balancedBracketSelectors;
      if (balancedBracketSelectors?.matchesAlways ?? false) {
        containsBalancedBrackets = true;
      }

      if (_tokenTypeOverrides.isNotEmpty ||
          (balancedBracketSelectors != null &&
              !balancedBracketSelectors.matchesAlways &&
              !balancedBracketSelectors.matchesNever)) {
        // Only generate scope array when required to improve performance
        final scopes = scopesList?.getScopeNames() ?? <String>[];
        for (final tokenType in _tokenTypeOverrides) {
          if (tokenType.matcher(scopes)) {
            metadata = EncodedTokenAttributes.set(
              metadata,
              0,
              toOptionalTokenType(tokenType.type),
              null,
              FontStyle.notSet,
              0,
              0,
            );
          }
        }
        if (balancedBracketSelectors != null) {
          containsBalancedBrackets = balancedBracketSelectors.match(scopes);
        }
      }

      if (containsBalancedBrackets) {
        metadata = EncodedTokenAttributes.set(
          metadata,
          0,
          OptionalStandardTokenType.notSet,
          containsBalancedBrackets,
          FontStyle.notSet,
          0,
          0,
        );
      }

      if (_mergeConsecutiveTokensWithEqualMetadata &&
          _binaryTokens.isNotEmpty &&
          _binaryTokens[_binaryTokens.length - 1] == metadata) {
        // no need to push a token with the same metadata
        _lastTokenEndIndex = endIndex;
        return;
      }

      _binaryTokens.add(_lastTokenEndIndex);
      _binaryTokens.add(metadata);

      _lastTokenEndIndex = endIndex;
      return;
    }

    final scopes = scopesList?.getScopeNames() ?? <String>[];

    _tokens.add(
      IToken(
        startIndex: _lastTokenEndIndex,
        endIndex: endIndex,
        // value: lineText.substring(lastTokenEndIndex, endIndex),
        scopes: scopes,
      ),
    );

    _lastTokenEndIndex = endIndex;
  }

  List<IToken> getResult(StateStackImpl stack, int lineLength) {
    if (_tokens.isNotEmpty &&
        _tokens[_tokens.length - 1].startIndex == lineLength - 1) {
      // pop produced token for newline
      _tokens.removeLast();
    }

    if (_tokens.isEmpty) {
      _lastTokenEndIndex = -1;
      produce(stack, lineLength);
      _tokens[_tokens.length - 1].startIndex = 0;
    }

    return _tokens;
  }

  Uint32List getBinaryResult(StateStackImpl stack, int lineLength) {
    if (_binaryTokens.isNotEmpty &&
        _binaryTokens[_binaryTokens.length - 2] == lineLength - 1) {
      // pop produced token for newline
      _binaryTokens.removeLast();
      _binaryTokens.removeLast();
    }

    if (_binaryTokens.isEmpty) {
      _lastTokenEndIndex = -1;
      produce(stack, lineLength);
      _binaryTokens[_binaryTokens.length - 2] = 0;
    }

    return Uint32List.fromList(_binaryTokens);
  }
}

class FontInfo implements IFontInfo {
  FontInfo(
    this.startIndex,
    this.endIndex,
    this.fontFamily,
    this.fontSizeMultiplier,
    this.lineHeightMultiplier,
  );

  @override
  int startIndex;
  @override
  int endIndex;
  @override
  String? fontFamily;
  @override
  num? fontSizeMultiplier;
  @override
  num? lineHeightMultiplier;

  bool optionsEqual(IFontInfo other) {
    return fontFamily == other.fontFamily &&
        fontSizeMultiplier == other.fontSizeMultiplier &&
        lineHeightMultiplier == other.lineHeightMultiplier;
  }
}

class LineFonts {
  final List<FontInfo> _fonts = <FontInfo>[];

  int _lastIndex = 0;

  void produce(StateStackImpl stack, int endIndex) {
    produceFromScopes(stack.contentNameScopesList, endIndex);
  }

  void produceFromScopes(AttributedScopeStack? scopesList, int endIndex) {
    final fontAttributes = scopesList?.fontAttributes;
    if (fontAttributes == null) {
      _lastIndex = endIndex;
      return;
    }
    final fontFamily = fontAttributes.fontFamily;
    final fontSizeMultiplier = fontAttributes.fontSize;
    final lineHeightMultiplier = fontAttributes.lineHeight;
    if (!jsTruthy(fontFamily) &&
        !jsTruthy(fontSizeMultiplier) &&
        !jsTruthy(lineHeightMultiplier)) {
      _lastIndex = endIndex;
      return;
    }
    final font = FontInfo(
      _lastIndex,
      endIndex,
      fontFamily,
      fontSizeMultiplier,
      lineHeightMultiplier,
    );
    final lastFont = _fonts.isEmpty ? null : _fonts[_fonts.length - 1];
    if (lastFont != null &&
        lastFont.endIndex == _lastIndex &&
        lastFont.optionsEqual(font)) {
      lastFont.endIndex = font.endIndex;
    } else {
      _fonts.add(font);
    }
    _lastIndex = endIndex;
  }

  List<IFontInfo> getResult() {
    return _fonts;
  }
}
