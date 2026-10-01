/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/platform/theme/common/tokenClassificationRegistry.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971: token types and modifiers,
// `TokenStyle`, `SemanticTokenRule`, selector parsing and scoring
// (`parseTokenSelector`, `parseClassifierString`) and the default registry
// with its TextMate scope fallbacks (`createDefaultTokenClassificationRegistry`).
//
// Not ported: the JSON schema of styling rules (`getTokenStylingSchema`,
// `onDidChangeSchema`, the schema registration and its scheduler), `toString`,
// and the storage round trip (`TokenStyle.toJSONObject`/`fromJSONObject`,
// `SemanticTokenRule.fromJSONObject`/`toJSONObject`). `nls.localize` strings
// are their English defaults.
//
// Deviations: `TokenStyleValue` (`TokenStyle | string`) is an [Object];
// `TokenSelector` is an interface implemented by a private class instead of an
// object literal; invalid ids throw [ArgumentError] where upstream throws an
// `Error`; the `try`/`console.log` around `registerTokenStyleDefault` is
// dropped, as `parseTokenSelector` never throws. `TokenStyle.fromSettings`
// takes the JSON values of a rule: a font style that is not a string is
// matched as JavaScript's `RegExp.exec` converts it ([jsToString]), and a
// `bold`/`underline`/`strikethrough`/`italic` value that is not a boolean
// becomes its JavaScript truthiness (upstream keeps the value, and every
// reader only tests its truthiness).

import '../../../base/common/color.dart';
import 'theme.dart';

// ignore_for_file: constant_identifier_names

const String TOKEN_TYPE_WILDCARD = '*';
const String TOKEN_CLASSIFIER_LANGUAGE_SEPARATOR = ':';
const String CLASSIFIER_MODIFIER_SEPARATOR = '.';

const String _idPattern = r'\w+[-_\w+]*';
const String typeAndModifierIdPattern = '^$_idPattern\$';

/// Selects tokens by type, modifiers and language.
abstract interface class TokenSelector {
  /// The match score, or -1 when the token is not selected.
  int match(String type, List<String> modifiers, String language);

  String get id;
}

class TokenTypeOrModifierContribution {
  const TokenTypeOrModifierContribution({
    required this.num,
    required this.id,
    this.superType,
    required this.description,
    this.deprecationMessage,
  });

  final int num;
  final String id;
  final String? superType;
  final String description;
  final String? deprecationMessage;
}

class TokenStyle {
  const TokenStyle(
    this.foreground,
    this.bold,
    this.underline,
    this.strikethrough,
    this.italic,
  );

  final Color? foreground;
  final bool? bold;
  final bool? underline;
  final bool? strikethrough;
  final bool? italic;

  static bool equals(TokenStyle? s1, TokenStyle? s2) {
    if (identical(s1, s2)) {
      return true;
    }
    return s1 != null &&
        s2 != null &&
        (s1.foreground != null
            ? s1.foreground!.equals(s2.foreground)
            : s2.foreground == null) &&
        s1.bold == s2.bold &&
        s1.underline == s2.underline &&
        s1.strikethrough == s2.strikethrough &&
        s1.italic == s2.italic;
  }

  static TokenStyle fromData({
    Color? foreground,
    bool? bold,
    bool? underline,
    bool? strikethrough,
    bool? italic,
  }) => TokenStyle(foreground, bold, underline, strikethrough, italic);

  /// [foreground] is a hex string; [fontStyle] and the flags are the JSON
  /// values of a rule, [absent] where the rule has no such key.
  static TokenStyle fromSettings(
    String? foreground,
    Object? fontStyle, [
    Object? bold = absent,
    Object? underline = absent,
    Object? strikethrough = absent,
    Object? italic = absent,
  ]) {
    Color? foregroundColor;
    if (foreground != null) {
      foregroundColor = Color.fromHex(foreground);
    }
    bool? flag(Object? value) =>
        identical(value, absent) ? null : _isTruthy(value);
    var boldValue = flag(bold);
    var italicValue = flag(italic);
    var underlineValue = flag(underline);
    var strikethroughValue = flag(strikethrough);
    if (!identical(fontStyle, absent)) {
      boldValue = italicValue = underlineValue = strikethroughValue = false;
      final expression = RegExp('italic|bold|underline|strikethrough');
      for (final match in expression.allMatches(jsToString(fontStyle))) {
        switch (match[0]) {
          case 'bold':
            boldValue = true;
          case 'italic':
            italicValue = true;
          case 'underline':
            underlineValue = true;
          case 'strikethrough':
            strikethroughValue = true;
        }
      }
    }
    return TokenStyle(
      foregroundColor,
      boldValue,
      underlineValue,
      strikethroughValue,
      italicValue,
    );
  }

  /// A JSON key that is not there (JavaScript's `undefined`).
  static const Object absent = _Absent();
}

class _Absent {
  const _Absent();
}

/// A TextMate scope path, outermost first.
typedef ProbeScope = List<String>;

/// A [TokenStyle], or a `TokenClassificationString` of the form
/// `(type|*)(.modifier)*(:language)?`.
typedef TokenStyleValue = Object;

class TokenStyleDefaults {
  const TokenStyleDefaults({
    this.scopesToProbe,
    this.light,
    this.dark,
    this.hcDark,
    this.hcLight,
  });

  final List<ProbeScope>? scopesToProbe;
  final TokenStyleValue? light;
  final TokenStyleValue? dark;
  final TokenStyleValue? hcDark;
  final TokenStyleValue? hcLight;

  /// `defaults[theme.type]`.
  TokenStyleValue? operator [](ColorScheme scheme) => switch (scheme) {
    ColorScheme.light => light,
    ColorScheme.dark => dark,
    ColorScheme.highContrastDark => hcDark,
    ColorScheme.highContrastLight => hcLight,
  };
}

class SemanticTokenDefaultRule {
  const SemanticTokenDefaultRule(this.selector, this.defaults);

  final TokenSelector selector;
  final TokenStyleDefaults defaults;
}

class SemanticTokenRule {
  const SemanticTokenRule(this.style, this.selector);

  final TokenStyle style;
  final TokenSelector selector;

  static bool equals(SemanticTokenRule? r1, SemanticTokenRule? r2) {
    if (identical(r1, r2)) {
      return true;
    }
    return r1 != null &&
        r2 != null &&
        r1.selector.id == r2.selector.id &&
        TokenStyle.equals(r1.style, r2.style);
  }
}

class TokenClassificationRegistry {
  int _currentTypeNumber = 0;
  int _currentModifierBit = 1;

  final Map<String, TokenTypeOrModifierContribution> _tokenTypeById = {};
  final Map<String, TokenTypeOrModifierContribution> _tokenModifierById = {};

  List<SemanticTokenDefaultRule> _tokenStylingDefaultRules = [];

  Map<String, List<String>> _typeHierarchy = {};

  void registerTokenType(
    String id,
    String description, [
    String? superType,
    String? deprecationMessage,
  ]) {
    if (!RegExp(typeAndModifierIdPattern).hasMatch(id)) {
      throw ArgumentError('Invalid token type id.');
    }
    if (superType != null &&
        superType.isNotEmpty &&
        !RegExp(typeAndModifierIdPattern).hasMatch(superType)) {
      throw ArgumentError('Invalid token super type id.');
    }

    final num = _currentTypeNumber++;
    final tokenStyleContribution = TokenTypeOrModifierContribution(
      num: num,
      id: id,
      superType: superType,
      description: description,
      deprecationMessage: deprecationMessage,
    );
    _tokenTypeById[id] = tokenStyleContribution;
    _typeHierarchy = {};
  }

  void registerTokenModifier(
    String id,
    String description, [
    String? deprecationMessage,
  ]) {
    if (!RegExp(typeAndModifierIdPattern).hasMatch(id)) {
      throw ArgumentError('Invalid token modifier id.');
    }

    final num = _currentModifierBit;
    _currentModifierBit = _currentModifierBit * 2;
    final tokenStyleContribution = TokenTypeOrModifierContribution(
      num: num,
      id: id,
      description: description,
      deprecationMessage: deprecationMessage,
    );
    _tokenModifierById[id] = tokenStyleContribution;
  }

  /// Parses `(*|type)(.modifier)*(:language)?`; [language] applies when the
  /// string names none. A selector without a type matches nothing.
  TokenSelector parseTokenSelector(String selectorString, [String? language]) {
    final selector = parseClassifierString(selectorString, language);

    if (selector.type.isEmpty) {
      return _TokenSelector('\$invalid', (type, modifiers, language) => -1);
    }

    final modifiers = selector.modifiers..sort();
    final id =
        '${[selector.type, ...modifiers].join('.')}'
        '${selector.language != null ? ':${selector.language}' : ''}';
    return _TokenSelector(id, (type, tokenModifiers, language) {
      var score = 0;
      if (selector.language != null) {
        if (selector.language != language) {
          return -1;
        }
        score += 10;
      }
      if (selector.type != TOKEN_TYPE_WILDCARD) {
        final hierarchy = _getTypeHierarchy(type);
        final level = hierarchy.indexOf(selector.type);
        if (level == -1) {
          return -1;
        }
        score += 100 - level;
      }
      // all selector modifiers must be present
      for (final selectorModifier in modifiers) {
        if (!tokenModifiers.contains(selectorModifier)) {
          return -1;
        }
      }
      return score + modifiers.length * 100;
    });
  }

  void registerTokenStyleDefault(
    TokenSelector selector,
    TokenStyleDefaults defaults,
  ) {
    _tokenStylingDefaultRules.add(SemanticTokenDefaultRule(selector, defaults));
  }

  void deregisterTokenStyleDefault(TokenSelector selector) {
    final selectorString = selector.id;
    _tokenStylingDefaultRules = _tokenStylingDefaultRules
        .where((r) => r.selector.id != selectorString)
        .toList();
  }

  void deregisterTokenType(String id) {
    _tokenTypeById.remove(id);
    _typeHierarchy = {};
  }

  void deregisterTokenModifier(String id) {
    _tokenModifierById.remove(id);
  }

  List<TokenTypeOrModifierContribution> getTokenTypes() =>
      _tokenTypeById.values.toList();

  List<TokenTypeOrModifierContribution> getTokenModifiers() =>
      _tokenModifierById.values.toList();

  /// The styling rules to use when a theme does not define any.
  List<SemanticTokenDefaultRule> getTokenStylingDefaultRules() =>
      _tokenStylingDefaultRules;

  List<String> _getTypeHierarchy(String typeId) {
    var hierarchy = _typeHierarchy[typeId];
    if (hierarchy == null) {
      _typeHierarchy[typeId] = hierarchy = [typeId];
      var type = _tokenTypeById[typeId];
      while (type != null && _isTruthy(type.superType)) {
        hierarchy.add(type.superType!);
        type = _tokenTypeById[type.superType];
      }
    }
    return hierarchy;
  }
}

class _TokenSelector implements TokenSelector {
  _TokenSelector(this.id, this._match);

  @override
  final String id;
  final int Function(String type, List<String> modifiers, String language)
  _match;

  @override
  int match(String type, List<String> modifiers, String language) =>
      _match(type, modifiers, language);
}

const int _charLanguage = 0x3A; // ':'
const int _charModifier = 0x2E; // '.'

/// Splits `type(.modifier)*(:language)?`, scanning from the end; the
/// modifiers come out last first. [defaultLanguage] applies when [s] names
/// no language.
({String type, List<String> modifiers, String? language}) parseClassifierString(
  String s,
  String? defaultLanguage,
) {
  var k = s.length;
  var language = defaultLanguage;
  final modifiers = <String>[];

  for (var i = k - 1; i >= 0; i--) {
    final ch = s.codeUnitAt(i);
    if (ch == _charLanguage || ch == _charModifier) {
      final segment = s.substring(i + 1, k);
      k = i;
      if (ch == _charLanguage) {
        language = segment;
      } else {
        modifiers.add(segment);
      }
    }
  }
  final type = s.substring(0, k);
  return (type: type, modifiers: modifiers, language: language);
}

final TokenClassificationRegistry _tokenClassificationRegistry =
    createDefaultTokenClassificationRegistry();

TokenClassificationRegistry createDefaultTokenClassificationRegistry() {
  final registry = TokenClassificationRegistry();

  void registerTokenStyleDefault(
    String selectorString,
    List<ProbeScope> scopesToProbe,
  ) {
    final selector = registry.parseTokenSelector(selectorString);
    registry.registerTokenStyleDefault(
      selector,
      TokenStyleDefaults(scopesToProbe: scopesToProbe),
    );
  }

  String registerTokenType(
    String id,
    String description, [
    List<ProbeScope> scopesToProbe = const [],
    String? superType,
    String? deprecationMessage,
  ]) {
    registry.registerTokenType(id, description, superType, deprecationMessage);
    registerTokenStyleDefault(id, scopesToProbe);
    return id;
  }

  // default token types

  registerTokenType('comment', 'Style for comments.', [
    ['comment'],
  ]);
  registerTokenType('string', 'Style for strings.', [
    ['string'],
  ]);
  registerTokenType('keyword', 'Style for keywords.', [
    ['keyword.control'],
  ]);
  registerTokenType('number', 'Style for numbers.', [
    ['constant.numeric'],
  ]);
  registerTokenType('regexp', 'Style for expressions.', [
    ['constant.regexp'],
  ]);
  registerTokenType('operator', 'Style for operators.', [
    ['keyword.operator'],
  ]);

  registerTokenType('namespace', 'Style for namespaces.', [
    ['entity.name.namespace'],
  ]);

  registerTokenType('type', 'Style for types.', [
    ['entity.name.type'],
    ['support.type'],
  ]);
  registerTokenType('struct', 'Style for structs.', [
    ['entity.name.type.struct'],
  ]);
  registerTokenType('class', 'Style for classes.', [
    ['entity.name.type.class'],
    ['support.class'],
  ]);
  registerTokenType('interface', 'Style for interfaces.', [
    ['entity.name.type.interface'],
  ]);
  registerTokenType('enum', 'Style for enums.', [
    ['entity.name.type.enum'],
  ]);
  registerTokenType('typeParameter', 'Style for type parameters.', [
    ['entity.name.type.parameter'],
  ]);

  registerTokenType('function', 'Style for functions', [
    ['entity.name.function'],
    ['support.function'],
  ]);
  registerTokenType(
    'member',
    'Style for member functions',
    [],
    'method',
    'Deprecated use `method` instead',
  );
  registerTokenType('method', 'Style for method (member functions)', [
    ['entity.name.function.member'],
    ['support.function'],
  ]);
  registerTokenType('macro', 'Style for macros.', [
    ['entity.name.function.preprocessor'],
  ]);

  registerTokenType('variable', 'Style for variables.', [
    ['variable.other.readwrite'],
    ['entity.name.variable'],
  ]);
  registerTokenType('parameter', 'Style for parameters.', [
    ['variable.parameter'],
  ]);
  registerTokenType('property', 'Style for properties.', [
    ['variable.other.property'],
  ]);
  registerTokenType('enumMember', 'Style for enum members.', [
    ['variable.other.enummember'],
  ]);
  registerTokenType('event', 'Style for events.', [
    ['variable.other.event'],
  ]);
  registerTokenType('decorator', 'Style for decorators & annotations.', [
    ['entity.name.decorator'],
    ['entity.name.function'],
  ]);

  // `undefined` upstream, which takes the parameter's default `[]`.
  registerTokenType('label', 'Style for labels. ');

  // default token modifiers

  registry.registerTokenModifier(
    'declaration',
    'Style for all symbol declarations.',
  );
  registry.registerTokenModifier(
    'documentation',
    'Style to use for references in documentation.',
  );
  registry.registerTokenModifier(
    'static',
    'Style to use for symbols that are static.',
  );
  registry.registerTokenModifier(
    'abstract',
    'Style to use for symbols that are abstract.',
  );
  registry.registerTokenModifier(
    'deprecated',
    'Style to use for symbols that are deprecated.',
  );
  registry.registerTokenModifier(
    'modification',
    'Style to use for write accesses.',
  );
  registry.registerTokenModifier(
    'async',
    'Style to use for symbols that are async.',
  );
  registry.registerTokenModifier(
    'readonly',
    'Style to use for symbols that are read-only.',
  );

  registerTokenStyleDefault('variable.readonly', [
    ['variable.other.constant'],
  ]);
  registerTokenStyleDefault('property.readonly', [
    ['variable.other.constant.property'],
  ]);
  registerTokenStyleDefault('type.defaultLibrary', [
    ['support.type'],
  ]);
  registerTokenStyleDefault('class.defaultLibrary', [
    ['support.class'],
  ]);
  registerTokenStyleDefault('interface.defaultLibrary', [
    ['support.class'],
  ]);
  registerTokenStyleDefault('variable.defaultLibrary', [
    ['support.variable'],
    ['support.other.variable'],
  ]);
  registerTokenStyleDefault('variable.defaultLibrary.readonly', [
    ['support.constant'],
  ]);
  registerTokenStyleDefault('property.defaultLibrary', [
    ['support.variable.property'],
  ]);
  registerTokenStyleDefault('property.defaultLibrary.readonly', [
    ['support.constant.property'],
  ]);
  registerTokenStyleDefault('function.defaultLibrary', [
    ['support.function'],
  ]);
  registerTokenStyleDefault('member.defaultLibrary', [
    ['support.function'],
  ]);
  return registry;
}

/// The registry every theme resolves against (upstream's module singleton).
TokenClassificationRegistry getTokenClassificationRegistry() =>
    _tokenClassificationRegistry;

/// JavaScript's `String(value)` for a JSON value, as `RegExp.exec` and the
/// scope tokenizer convert what they are given.
String jsToString(Object? value) => switch (value) {
  null => 'null',
  String s => s,
  bool b => '$b',
  int i => '$i',
  double d =>
    d == d.truncateToDouble() && d.abs() < 1e21 ? '${d.toInt()}' : '$d',
  List<Object?> list =>
    list.map((e) => e == null ? '' : jsToString(e)).join(','),
  _ => '[object Object]',
};

/// JavaScript truthiness of a JSON value.
bool _isTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  num n => n != 0 && !n.isNaN,
  _ => true,
};
