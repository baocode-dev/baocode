// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
// Ported from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/editor/standalone/common/monarch/monarchCommon.ts.
//
// Dart adaptations: structural interfaces become classes; FuzzyAction's union
// is Object (String or IAction). Optional RegExp captures are String? (JS
// undefined); substitution converts a present-but-unmatched capture to the
// string "undefined", as JS String.replace does. Strings/offsets remain UTF-16.
// Console logging uses print, and Error is a language-prefixed Exception.
// All upstream functions are retained. escapeRegExpCharacters is the one small
// helper copied from vs/base/common/strings.ts, including its exact character
// set (Dart RegExp.escape escapes a slightly different set).

/// The numeric values match the upstream const enum.
enum MonarchBracket {
  none(0),
  open(1),
  close(-1);

  const MonarchBracket(this.value);
  final int value;
}

class ILexerMin {
  ILexerMin({
    required this.languageId,
    this.includeLF = false,
    this.noThrow = false,
    this.ignoreCase = false,
    this.unicode = false,
    this.usesEmbedded = false,
    this.defaultToken = 'source',
    Map<String, Object?>? stateNames,
    Map<String, Object?>? attributes,
  }) : stateNames = stateNames ?? <String, Object?>{},
       attributes = attributes ?? <String, Object?>{};

  String languageId;
  bool includeLF;
  bool noThrow;
  bool ignoreCase;
  bool unicode;
  bool usesEmbedded;
  String defaultToken;
  Map<String, Object?> stateNames;
  final Map<String, Object?> attributes;

  Object? operator [](String key) => switch (key) {
    'languageId' => languageId,
    'includeLF' => includeLF,
    'noThrow' => noThrow,
    'ignoreCase' => ignoreCase,
    'unicode' => unicode,
    'usesEmbedded' => usesEmbedded,
    'defaultToken' => defaultToken,
    'stateNames' => stateNames,
    _ => attributes[key],
  };

  bool hasAttribute(String key) =>
      const {
        'languageId',
        'includeLF',
        'noThrow',
        'ignoreCase',
        'unicode',
        'usesEmbedded',
        'defaultToken',
        'stateNames',
      }.contains(key) ||
      attributes.containsKey(key);
}

class ILexer extends ILexerMin {
  ILexer({
    required super.languageId,
    super.includeLF,
    super.noThrow,
    super.ignoreCase,
    super.unicode,
    super.usesEmbedded,
    super.defaultToken,
    super.stateNames,
    super.attributes,
    this.maxStack = 100,
    this.start,
    required this.tokenPostfix,
    Map<String, List<IRule>>? tokenizer,
    List<IBracket>? brackets,
  }) : tokenizer = tokenizer ?? <String, List<IRule>>{},
       brackets = brackets ?? <IBracket>[];

  int maxStack;
  String? start;
  String tokenPostfix;
  Map<String, List<IRule>> tokenizer;
  List<IBracket> brackets;

  @override
  Object? operator [](String key) => switch (key) {
    'maxStack' => maxStack,
    'start' => start,
    'tokenPostfix' => tokenPostfix,
    'tokenizer' => tokenizer,
    'brackets' => brackets,
    _ => super[key],
  };

  @override
  bool hasAttribute(String key) =>
      const {
        'maxStack',
        'start',
        'tokenPostfix',
        'tokenizer',
        'brackets',
      }.contains(key) ||
      super.hasAttribute(key);
}

class IBracket {
  const IBracket({
    required this.token,
    required this.open,
    required this.close,
  });

  final String token;
  final String open;
  final String close;
}

/// A compiled action is either a [String] token or an [IAction].
typedef FuzzyAction = Object;
typedef ActionTest = FuzzyAction Function(
  String id,
  List<String?> matches,
  String state,
  bool eos,
);
typedef BranchTest = bool Function(
  String id,
  List<String?> matches,
  String state,
  bool eos,
);

bool isFuzzyActionArr(Object? what) => what is List;
bool isFuzzyAction(Object? what) => !isFuzzyActionArr(what);
bool isString(Object? what) => what is String;
bool isIAction(Object? what) => !isString(what);

abstract interface class IRule {
  FuzzyAction get action;
  bool get matchOnlyAtLineStart;
  String get name;
  RegExp resolveRegex(String state);
}

class IAction {
  const IAction({
    this.group,
    this.hasEmbeddedEndInCases,
    this.test,
    this.token,
    this.tokenSubst,
    this.next,
    this.nextEmbedded,
    this.bracket,
    this.log,
    this.switchTo,
    this.goBack,
    this.transform,
  });

  final List<FuzzyAction>? group;
  final bool? hasEmbeddedEndInCases;
  final ActionTest? test;
  final String? token;
  final bool? tokenSubst;
  final String? next;
  final String? nextEmbedded;
  final MonarchBracket? bracket;
  final String? log;
  final String? switchTo;
  final num? goBack;
  final List<String> Function(List<String> states)? transform;
}

class IBranch {
  const IBranch({required this.name, required this.value, this.test});

  final String name;
  final FuzzyAction value;
  final BranchTest? test;
}

bool empty(String? s) => s == null || s.isEmpty;

String fixCase(ILexerMin lexer, String str) =>
    lexer.ignoreCase && str.isNotEmpty ? str.toLowerCase() : str;

String sanitize(String s) => s.replaceAll(RegExp('[&<>\'"_]'), '-');

void log(ILexerMin lexer, String msg) {
  // ignore: avoid_print
  print('${lexer.languageId}: $msg');
}

class MonarchError implements Exception {
  const MonarchError(this.message);
  final String message;

  @override
  String toString() => message;
}

MonarchError createError(ILexerMin lexer, String msg) =>
    MonarchError('${lexer.languageId}: $msg');

final _substitution = RegExp(r'\$((\$)|(#)|(\d\d?)|[sS](\d\d?)|@(\w+))');
final _stateSubstitution = RegExp(r'\$[sS](\d\d?)');
final _regExpCharacters = RegExp(r'[\\\{\}\*\+\?\|\^\$\.\[\]\(\)]');

String substituteMatches(
  ILexerMin lexer,
  String str,
  String id,
  List<String?> matches,
  String state,
) {
  List<String>? stateMatches;
  return str.replaceAllMapped(_substitution, (match) {
    if (!empty(match[2])) return r'$';
    if (!empty(match[3])) return fixCase(lexer, id);
    final n = int.tryParse(match[4] ?? '');
    if (n != null && n < matches.length) {
      final captured = matches[n];
      return captured == null ? 'undefined' : fixCase(lexer, captured);
    }
    final attr = match[6];
    if (!empty(attr) && lexer[attr!] is String) {
      return lexer[attr] as String;
    }
    stateMatches ??= <String>[state, ...state.split('.')];
    final s = int.tryParse(match[5] ?? '');
    if (s != null && s < stateMatches!.length) {
      return fixCase(lexer, stateMatches![s]);
    }
    return '';
  });
}

String substituteMatchesRe(ILexerMin lexer, String str, String state) {
  List<String>? stateMatches;
  return str.replaceAllMapped(_stateSubstitution, (match) {
    stateMatches ??= <String>[state, ...state.split('.')];
    final s = int.parse(match[1]!);
    if (s < stateMatches!.length) {
      return fixCase(
        lexer,
        stateMatches![s],
      ).replaceAllMapped(_regExpCharacters, (character) => '\\${character[0]}');
    }
    return '';
  });
}

List<IRule>? findRules(ILexer lexer, String inState) {
  var state = inState;
  while (state.isNotEmpty) {
    final rules = lexer.tokenizer[state];
    if (rules != null) return rules;
    final index = state.lastIndexOf('.');
    if (index < 0) return null;
    state = state.substring(0, index);
  }
  return null;
}

bool stateExists(ILexerMin lexer, String inState) {
  var state = inState;
  while (state.isNotEmpty) {
    final value = lexer.stateNames[state];
    // JavaScript considers empty arrays and objects truthy.
    if (value != null &&
        value != false &&
        value != '' &&
        !(value is num && (value == 0 || value.isNaN))) {
      return true;
    }
    final index = state.lastIndexOf('.');
    if (index < 0) return false;
    state = state.substring(0, index);
  }
  return false;
}
