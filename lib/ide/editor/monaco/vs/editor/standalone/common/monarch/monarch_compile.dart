// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/standalone/common/monarch/monarchCompile.ts.
//
// Dart/JS differences and scope:
// - Definitions use the map/list aliases in monarch_types.dart. Compilation
//   does not mutate the input (upstream annotates json, adds default brackets,
//   and writes a shorthand rule's next into its action). Const maps work here.
// - Dart RegExp implements ECMAScript syntax; ignoreCase/unicode map to its
//   caseSensitive/unicode options. Pattern flags are discarded, as upstream
//   takes only RegExp.source; Dart RegExp.pattern is normalized to JS .source
//   (empty patterns, slashes, line terminators) at the input boundary. Invalid
//   syntax throws FormatException rather than JS SyntaxError. Captures/offsets
//   use UTF-16; there is no JS lastIndex state.
// - Object properties are Map entries, without JavaScript prototype lookup.
//   Integer-index keys retain JS enumeration order for states and cases.
// - Malformed containers and cyclic includes raise MonarchError instead of
//   incidental JS TypeError/stack overflow. Valid grammar behavior is unchanged.
// - No compiler functions are omitted. Action functions and {group: ...} maps
//   are not accepted by the pinned upstream compileAction either. transform
//   is not copied. The dynamic !~ case guard intentionally retains upstream's
//   behavior (it tests positively when the pattern contains '$').

import 'monarch_common.dart' as common;
import 'monarch_types.dart';

bool _isArrayOf(bool Function(Object?) elemType, Object? obj) =>
    obj is List && obj.every(elemType);

bool _bool(Object? prop, bool defaultValue) =>
    prop is bool ? prop : defaultValue;

String _string(Object? prop, String defaultValue) =>
    prop is String ? prop : defaultValue;

Set<String> _arrayToHash(List<String> array) => array.toSet();

bool Function(String) _createKeywordMatcher(
  List<String> array, [
  bool caseInsensitive = false,
]) {
  final hash = _arrayToHash(
    caseInsensitive ? array.map((x) => x.toLowerCase()).toList() : array,
  );
  return caseInsensitive
      ? (word) => hash.contains(word.toLowerCase())
      : hash.contains;
}

bool _truthy(Object? value) =>
    value != null &&
    value != false &&
    value != '' &&
    !(value is num && (value == 0 || value.isNaN));

Object? _property(Object? object, String key) =>
    object is Map ? object[key] : null;

// JS Object.keys/for-in visits integer indices first, in ascending order.
Iterable<String> _orderedKeys(Map<String, Object?> object) sync* {
  final indices = <int>[];
  final others = <String>[];
  for (final key in object.keys) {
    final index = int.tryParse(key);
    if (index != null &&
        index >= 0 &&
        index < 0xFFFFFFFF &&
        index.toString() == key) {
      indices.add(index);
    } else {
      others.add(key);
    }
  }
  indices.sort();
  yield* indices.map((index) => index.toString());
  yield* others;
}

Map<String, Object?>? _stringMap(Object? object) =>
    object is Map && object.keys.every((key) => key is String)
    ? Map<String, Object?>.from(object)
    : null;

typedef _DynamicRegExp = RegExp Function(String state);

/// JS RegExp.source escapes line terminators/slashes and writes (?:) for an
/// empty pattern. Dart RegExp.pattern returns the original, unescaped string.
/// Only RegExp attributes/rules go through this function; string patterns do not.
String _regExpSource(RegExp expression) {
  final pattern = expression.pattern;
  if (pattern.isEmpty) return '(?:)';
  final result = StringBuffer();
  var inCharacterClass = false;
  for (var index = 0; index < pattern.length; index++) {
    final unit = pattern.codeUnitAt(index);
    if (unit == 0x5c && index + 1 < pattern.length) {
      final next = pattern.codeUnitAt(index + 1);
      if (next == 0x0a || next == 0x0d || next == 0x2028 || next == 0x2029) {
        // Identity-escaped line terminators serialize with one escape, not two.
        continue;
      }
      result.writeCharCode(unit);
      result.writeCharCode(next);
      index++;
      continue;
    }
    if (unit == 0x5b) inCharacterClass = true;
    if (unit == 0x5d) inCharacterClass = false;
    if (unit == 0x2f && !inCharacterClass) {
      result.write(r'\/');
    } else if (unit == 0x0a) {
      result.write(r'\n');
    } else if (unit == 0x0d) {
      result.write(r'\r');
    } else if (unit == 0x2028) {
      result.write(r'\u' '2028');
    } else if (unit == 0x2029) {
      result.write(r'\u' '2029');
    } else {
      result.writeCharCode(unit);
    }
  }
  return result.toString();
}

/// Returns a static regexp or a state-dependent regexp with a one-state cache.
Object _compileRegExp(common.ILexerMin lexer, String str, bool handleSn) {
  // Protect escaped @@ before expanding attribute references (five passes).
  str = str.replaceAll('@@', '\x01');
  var n = 0;
  bool hadExpansion;
  do {
    hadExpansion = false;
    str = str.replaceAllMapped(RegExp(r'@(\w+)'), (match) {
      hadExpansion = true;
      final attr = match[1]!;
      final value = lexer[attr];
      final String sub;
      if (value is String) {
        sub = value;
      } else if (value is RegExp) {
        sub = _regExpSource(value);
      } else if (!lexer.hasAttribute(attr)) {
        throw common.createError(
          lexer,
          "language definition does not contain attribute '$attr', used at: $str",
        );
      } else {
        throw common.createError(
          lexer,
          "attribute reference '$attr' must be a string, used at: $str",
        );
      }
      return sub.isEmpty ? '' : '(?:$sub)';
    });
    n++;
  } while (hadExpansion && n < 5);
  str = str.replaceAll('\x01', '@');

  // Snapshot flags as upstream does before creating a dynamic resolver.
  final ignoreCase = lexer.ignoreCase;
  final unicode = lexer.unicode;
  RegExp makeRegex(String pattern) =>
      RegExp(pattern, caseSensitive: !ignoreCase, unicode: unicode);

  if (handleSn && RegExp(r'\$[sS](\d\d?)').hasMatch(str)) {
    String? lastState;
    RegExp? lastRegExp;
    return (String state) {
      if (lastRegExp != null && lastState == state) return lastRegExp!;
      lastState = state;
      lastRegExp = makeRegex(common.substituteMatchesRe(lexer, str, state));
      return lastRegExp!;
    };
  }
  return makeRegex(str);
}

String? _selectScrutinee(
  String id,
  List<String?> matches,
  String state,
  int num,
) {
  if (num < 0) return id;
  if (num < matches.length) return matches[num];
  if (num >= 100) {
    num -= 100;
    final parts = <String>[state, ...state.split('.')];
    if (num < parts.length) return parts[num];
  }
  return null;
}

typedef _GuardTester = bool Function(
  String scrutinee,
  String id,
  List<String?> matches,
  String state,
  bool eos,
);

common.IBranch _createGuard(
  common.ILexerMin lexer,
  String ruleName,
  String tkey,
  common.FuzzyAction value,
) {
  var scrut = -1;
  var oppat = tkey;
  var match = RegExp(r'^\$(([sS]?)(\d\d?)|#)(.*)$').firstMatch(tkey);
  if (match != null) {
    if (!common.empty(match[3])) {
      scrut = int.parse(match[3]!);
      if (!common.empty(match[2])) scrut += 100;
    }
    oppat = match[4]!;
  }

  var op = '~';
  var pat = oppat;
  if (oppat.isEmpty) {
    op = '!=';
    pat = '';
  } else if (RegExp(r'^\w*$').hasMatch(pat)) {
    op = '==';
  } else {
    match = RegExp(r'^(@|!@|~|!~|==|!=)(.*)$').firstMatch(oppat);
    if (match != null) {
      op = match[1]!;
      pat = match[2]!;
    }
  }

  final _GuardTester tester;
  if ((op == '~' || op == '!~') && RegExp(r'^(\w|\|)*$').hasMatch(pat)) {
    final inWords = _createKeywordMatcher(pat.split('|'), lexer.ignoreCase);
    tester = (s, id, matches, state, eos) =>
        op == '~' ? inWords(s) : !inWords(s);
  } else if (op == '@' || op == '!@') {
    final words = lexer[pat];
    if (!_truthy(words)) {
      throw common.createError(
        lexer,
        "the @ match target '$pat' is not defined, in rule: $ruleName",
      );
    }
    if (!_isArrayOf((element) => element is String, words)) {
      throw common.createError(
        lexer,
        "the @ match target '$pat' must be an array of strings, in rule: $ruleName",
      );
    }
    final inWords = _createKeywordMatcher(
      (words as List).cast<String>(),
      lexer.ignoreCase,
    );
    tester = (s, id, matches, state, eos) =>
        op == '@' ? inWords(s) : !inWords(s);
  } else if (op == '~' || op == '!~') {
    if (!pat.contains(r'$')) {
      final re = _compileRegExp(lexer, '^$pat\$', false) as RegExp;
      tester = (s, id, matches, state, eos) =>
          op == '~' ? re.hasMatch(s) : !re.hasMatch(s);
    } else {
      tester = (s, id, matches, state, eos) {
        final expanded = common.substituteMatches(
          lexer,
          pat,
          id,
          matches,
          state,
        );
        final re = _compileRegExp(lexer, '^$expanded\$', false) as RegExp;
        // Deliberately no !~ inversion: this is the pinned source's behavior.
        return re.hasMatch(s);
      };
    }
  } else {
    final patx = common.fixCase(lexer, pat);
    if (!pat.contains(r'$')) {
      tester = (s, id, matches, state, eos) =>
          op == '==' ? s == patx : s != patx;
    } else {
      tester = (s, id, matches, state, eos) {
        final expanded = common.substituteMatches(
          lexer,
          patx,
          id,
          matches,
          state,
        );
        return op == '==' ? s == expanded : s != expanded;
      };
    }
  }

  return common.IBranch(
    name: tkey,
    value: value,
    test: scrut == -1
        ? (id, matches, state, eos) => tester(id, id, matches, state, eos)
        : (id, matches, state, eos) => tester(
            _selectScrutinee(id, matches, state, scrut) ?? '',
            id,
            matches,
            state,
            eos,
          ),
  );
}

common.FuzzyAction _compileAction(
  common.ILexerMin lexer,
  String ruleName,
  Object? action,
) {
  if (!_truthy(action)) return const common.IAction(token: '');
  if (action is String) return action;

  final token = _property(action, 'token');
  if (_truthy(token) || token == '') {
    if (token is! String) {
      throw common.createError(
        lexer,
        "a 'token' attribute must be of type string, in rule: $ruleName",
      );
    }
    common.MonarchBracket? bracket;
    final rawBracket = _property(action, 'bracket');
    if (rawBracket is String) {
      if (rawBracket == '@open') {
        bracket = common.MonarchBracket.open;
      } else if (rawBracket == '@close') {
        bracket = common.MonarchBracket.close;
      } else {
        throw common.createError(
          lexer,
          "a 'bracket' attribute must be either '@open' or '@close', in rule: $ruleName",
        );
      }
    }

    String? next;
    final rawNext = _property(action, 'next');
    if (_truthy(rawNext)) {
      if (rawNext is! String) {
        throw common.createError(
          lexer,
          'the next state must be a string value in rule: $ruleName',
        );
      }
      next = rawNext;
      if (!RegExp(r'^(@pop|@push|@popall)$').hasMatch(next)) {
        if (next.startsWith('@')) next = next.substring(1);
        if (!next.contains(r'$') &&
            !common.stateExists(
              lexer,
              common.substituteMatches(lexer, next, '', const [], ''),
            )) {
          throw common.createError(
            lexer,
            "the next state '$rawNext' is not defined in rule: $ruleName",
          );
        }
      }
    }
    final goBack = _property(action, 'goBack');
    final switchTo = _property(action, 'switchTo');
    final log = _property(action, 'log');
    final nextEmbedded = _property(action, 'nextEmbedded');
    if (nextEmbedded is String) lexer.usesEmbedded = true;
    return common.IAction(
      token: token,
      tokenSubst: token.contains(r'$') ? true : null,
      bracket: bracket,
      next: next,
      goBack: goBack is num ? goBack : null,
      switchTo: switchTo is String ? switchTo : null,
      log: log is String ? log : null,
      nextEmbedded: nextEmbedded is String ? nextEmbedded : null,
    );
  }
  if (action is List) {
    return common.IAction(
      group: action
          .map((item) => _compileAction(lexer, ruleName, item))
          .toList(),
    );
  }
  final rawCases = _property(action, 'cases');
  if (_truthy(rawCases)) {
    final caseMap = _stringMap(rawCases);
    if (caseMap == null) {
      throw common.createError(
        lexer,
        "a 'cases' attribute must be an object, in rule: $ruleName",
      );
    }
    final cases = <common.IBranch>[];
    var hasEmbeddedEndInCases = false;
    for (final tkey in _orderedKeys(caseMap)) {
      final value = _compileAction(lexer, ruleName, caseMap[tkey]);
      if (tkey == '@default' || tkey == '@' || tkey.isEmpty) {
        cases.add(common.IBranch(name: tkey, value: value));
      } else if (tkey == '@eos') {
        cases.add(
          common.IBranch(
            name: tkey,
            value: value,
            test: (id, matches, state, eos) => eos,
          ),
        );
      } else {
        cases.add(_createGuard(lexer, ruleName, tkey, value));
      }
      if (!hasEmbeddedEndInCases && value is common.IAction) {
        hasEmbeddedEndInCases =
            value.hasEmbeddedEndInCases == true ||
            value.nextEmbedded == '@pop' ||
            value.nextEmbedded == '@popall';
      }
    }
    final defaultToken = lexer.defaultToken;
    return common.IAction(
      hasEmbeddedEndInCases: hasEmbeddedEndInCases,
      test: (id, matches, state, eos) {
        for (final branch in cases) {
          if (branch.test == null || branch.test!(id, matches, state, eos)) {
            return branch.value;
          }
        }
        return defaultToken;
      },
    );
  }
  throw common.createError(
    lexer,
    "an action must be a string, an object with a 'token' or 'cases' attribute, or an array of actions; in rule: $ruleName",
  );
}

class _Rule implements common.IRule {
  _Rule(this.name);

  Object _regex = RegExp('');
  @override
  common.FuzzyAction action = const common.IAction(token: '');
  @override
  bool matchOnlyAtLineStart = false;
  @override
  String name;

  void setRegex(common.ILexerMin lexer, Object? re) {
    final String pattern;
    if (re is String) {
      pattern = re;
    } else if (re is RegExp) {
      pattern = _regExpSource(re);
    } else {
      throw common.createError(
        lexer,
        'rules must start with a match string or regular expression: $name',
      );
    }
    matchOnlyAtLineStart = pattern.startsWith('^');
    name = '$name: $pattern';
    _regex = _compileRegExp(
      lexer,
      '^(?:${matchOnlyAtLineStart ? pattern.substring(1) : pattern})',
      true,
    );
  }

  void setAction(common.ILexerMin lexer, Object? value) {
    action = _compileAction(lexer, name, value);
  }

  @override
  RegExp resolveRegex(String state) =>
      _regex is RegExp ? _regex as RegExp : (_regex as _DynamicRegExp)(state);
}

/// Compiles an [IMonarchLanguage] JSON-style definition into checked lexer data.
///
/// [json] is nullable/untyped to retain the upstream runtime validation at this
/// public boundary. A valid definition is a map with a `tokenizer` state map.
common.ILexer compile(String languageId, Object? json) {
  final definition = _stringMap(json);
  if (definition == null) {
    throw const common.MonarchError(
      'Monarch: expecting a language definition object',
    );
  }
  final lexer = common.ILexer(
    languageId: languageId,
    includeLF: _bool(definition['includeLF'], false),
    noThrow: false,
    maxStack: 100,
    start: definition['start'] is String ? definition['start'] as String : null,
    ignoreCase: _bool(definition['ignoreCase'], false),
    unicode: _bool(definition['unicode'], false),
    tokenPostfix: _string(definition['tokenPostfix'], '.$languageId'),
    defaultToken: _string(definition['defaultToken'], 'source'),
    usesEmbedded: false,
  );

  final tokenizer = _stringMap(definition['tokenizer']);
  if (tokenizer == null) {
    throw common.createError(
      lexer,
      "a language definition must define the 'tokenizer' attribute as an object",
    );
  }
  final lexerMin = common.ILexerMin(
    languageId: languageId,
    includeLF: lexer.includeLF,
    ignoreCase: lexer.ignoreCase,
    unicode: lexer.unicode,
    noThrow: lexer.noThrow,
    usesEmbedded: lexer.usesEmbedded,
    stateNames: tokenizer,
    defaultToken: lexer.defaultToken,
    attributes: definition,
  );

  void addRules(
    String state,
    List<common.IRule> newRules,
    Object? rules,
    Set<String> includeStack,
  ) {
    if (rules is! List) {
      throw common.createError(lexer, 'rules must be an array at: $state');
    }
    for (final rule in rules) {
      final rawInclude = _property(rule, 'include');
      if (_truthy(rawInclude)) {
        if (rawInclude is! String) {
          throw common.createError(
            lexer,
            "an 'include' attribute must be a string at: $state",
          );
        }
        final include = rawInclude.startsWith('@')
            ? rawInclude.substring(1)
            : rawInclude;
        if (!_truthy(tokenizer[include])) {
          throw common.createError(
            lexer,
            "include target '$include' is not defined at: $state",
          );
        }
        if (!includeStack.add(include)) {
          throw common.createError(
            lexer,
            "cyclic include of '$include' at: $state",
          );
        }
        addRules('$state.$include', newRules, tokenizer[include], includeStack);
        includeStack.remove(include);
      } else {
        final newRule = _Rule(state);
        if (rule is List && rule.isNotEmpty && rule.length <= 3) {
          newRule.setRegex(lexerMin, rule[0]);
          if (rule.length >= 3) {
            final action = rule[1];
            if (action is String) {
              newRule.setAction(lexerMin, {'token': action, 'next': rule[2]});
            } else if (action is Map) {
              newRule.setAction(lexerMin, {...action, 'next': rule[2]});
            } else if (action is List) {
              // In JS an array's added .next does not affect compileAction.
              newRule.setAction(lexerMin, action);
            } else {
              throw common.createError(
                lexer,
                'a next state as the last element of a rule can only be given if the action is either an object or a string, at: $state',
              );
            }
          } else {
            newRule.setAction(lexerMin, rule.length == 2 ? rule[1] : null);
          }
        } else {
          final regex = _property(rule, 'regex');
          if (!_truthy(regex)) {
            throw common.createError(
              lexer,
              "a rule must either be an array, or an object with a 'regex' or 'include' field at: $state",
            );
          }
          final name = _property(rule, 'name');
          if (_truthy(name) && name is String) newRule.name = name;
          if (_truthy(_property(rule, 'matchOnlyAtStart'))) {
            newRule.matchOnlyAtLineStart = _bool(
              _property(rule, 'matchOnlyAtLineStart'),
              false,
            );
          }
          // setRegex overwrites matchOnlyAtLineStart, exactly as upstream.
          newRule.setRegex(lexerMin, regex);
          newRule.setAction(lexerMin, _property(rule, 'action'));
        }
        newRules.add(newRule);
      }
    }
  }

  for (final key in _orderedKeys(tokenizer)) {
    if (common.empty(lexer.start)) lexer.start = key;
    final rules = <common.IRule>[];
    lexer.tokenizer[key] = rules;
    addRules('tokenizer.$key', rules, tokenizer[key], {key});
  }
  lexer.usesEmbedded = lexerMin.usesEmbedded;

  Object? rawBrackets = definition['brackets'];
  if (_truthy(rawBrackets)) {
    if (rawBrackets is! List) {
      throw common.createError(
        lexer,
        "the 'brackets' attribute must be defined as an array",
      );
    }
  } else {
    rawBrackets = const [
      {'open': '{', 'close': '}', 'token': 'delimiter.curly'},
      {'open': '[', 'close': ']', 'token': 'delimiter.square'},
      {'open': '(', 'close': ')', 'token': 'delimiter.parenthesis'},
      {'open': '<', 'close': '>', 'token': 'delimiter.angle'},
    ];
  }
  final brackets = <common.IBracket>[];
  for (final element in rawBrackets as List) {
    final Object? desc = element is List && element.length == 3
        ? {'open': element[0], 'close': element[1], 'token': element[2]}
        : element;
    final open = _property(desc, 'open');
    final close = _property(desc, 'close');
    final token = _property(desc, 'token');
    if (open == close) {
      throw common.createError(
        lexer,
        "open and close brackets in a 'brackets' attribute must be different: ${open ?? 'undefined'}"
        "\n hint: use the 'bracket' attribute if matching on equal brackets is required.",
      );
    }
    if (open is String && token is String && close is String) {
      brackets.add(
        common.IBracket(
          token: token + lexer.tokenPostfix,
          open: common.fixCase(lexer, open),
          close: common.fixCase(lexer, close),
        ),
      );
    } else {
      throw common.createError(
        lexer,
        "every element in the 'brackets' array must be a '{open,close,token}' object or array",
      );
    }
  }
  lexer.brackets = brackets;
  lexer.noThrow = true;
  return lexer;
}
