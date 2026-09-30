/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/themes/common/colorThemeData.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971: the token style resolution of
// `ColorThemeData` (`getTokenStyle`, `resolveTokenStyleValue`,
// `getTokenStyleMetadata`, `resolveScopes` with
// `findTokenStyleForScopeInScopes`, `getScopeMatcher`, `nameMatcher`,
// `scopesAreMatching`, `readSemanticTokenRule`,
// `isSemanticTokenColorizationSetting`, `TokenStyleDefinitions`,
// `TextMateThemingRuleDefinitions`), plus `ITokenStyle` from
// platform/theme/common/themeService.ts.
//
// Upstream these are members of ColorThemeData; here [ColorThemeTokenStyles]
// computes them from a loaded [ColorThemeData] through its public API: the
// theme's `semanticTokenColors` (parsed into [SemanticTokenRule]s as
// `readSemanticTokenRule` does while loading), its raw `themeTokenColors`
// (what `resolveScopes` matches), `type`, and the token color index
// (`getTokenColorId`). It is a snapshot: build a new one after the theme
// reloads.
//
// Not ported: user customizations (`customSemanticTokenRules`,
// `customTokenColors`; a theme reads as with default settings),
// `getTokenStylingRuleScope`, and `findMetadata` (TextMate tokens are styled
// by vscode-textmate's own theme).
//
// Deviations: the TextMate rules are the theme's raw JSON values, so
// `TextMateThemingRuleDefinitions` holds those. Where upstream throws a
// TypeError on a malformed rule (a `null` rule, a foreground that is neither
// a string nor an array), the rule or its foreground is ignored; a scope that
// is not a string is converted as JavaScript's `RegExp.exec` converts it. A
// semantic rule's foreground is the one [SemanticTokenColor] parsed while
// loading, which is `Color.fromHex` of it as upstream.

import '../../../../base/common/color.dart';
import '../../../../platform/theme/common/token_classification_registry.dart';
import 'color_theme_data.dart';
import 'text_mate_scope_matcher.dart';
import 'token_classification_extension_point.dart';

/// platform/theme/common/themeService.ts `ITokenStyle`: a style with its
/// foreground as a token color id (`ColorThemeData.tokenColorMap`).
class ITokenStyle {
  const ITokenStyle({
    this.foreground,
    this.bold,
    this.underline,
    this.strikethrough,
    this.italic,
  });

  final int? foreground;
  final bool? bold;
  final bool? underline;
  final bool? strikethrough;
  final bool? italic;
}

/// Where each property of a resolved style came from: a
/// [SemanticTokenRule], the scopes a default rule probed
/// (`List<ProbeScope>`), or a [TokenStyleValue].
class TokenStyleDefinitions {
  Object? foreground;
  Object? bold;
  Object? underline;
  Object? strikethrough;
  Object? italic;
}

/// The TextMate rules (the theme's raw JSON values) a scope resolved to.
class TextMateThemingRuleDefinitions {
  Object? foreground;
  Object? bold;
  Object? underline;
  Object? strikethrough;
  Object? italic;
  ProbeScope? scope;
}

/// The token styles of a loaded [ColorThemeData], as upstream's
/// ColorThemeData resolves them.
class ColorThemeTokenStyles {
  /// [registry] defaults to the workbench's, with the built-in extensions'
  /// contributions ([getWorkbenchTokenClassificationRegistry]).
  ColorThemeTokenStyles(this.theme, {TokenClassificationRegistry? registry})
    : registry = registry ?? getWorkbenchTokenClassificationRegistry();

  final ColorThemeData theme;
  final TokenClassificationRegistry registry;

  /// The theme's `semanticTokenColors` as rules, in load order.
  late final List<SemanticTokenRule> semanticTokenRules = [
    for (final rule in theme.semanticTokenColors)
      ?readSemanticTokenRule(registry, rule),
  ];

  late final List<Object?> _themeTokenColors = theme.themeTokenColors;
  List<Matcher<ProbeScope>>? _themeTokenScopeMatchers;

  TokenStyle? getTokenStyle(
    String type,
    List<String> modifiers,
    String language, {
    bool useDefault = true,
    TokenStyleDefinitions? definitions,
  }) {
    definitions ??= TokenStyleDefinitions();
    Color? foreground;
    final flags = <String, bool?>{
      'bold': null,
      'underline': null,
      'strikethrough': null,
      'italic': null,
    };
    // Upstream also scores fontFamily, fontSize and lineHeight, which no
    // style sets: some property always stays undefined.
    final score = <String, num>{
      'foreground': -1,
      'bold': -1,
      'underline': -1,
      'strikethrough': -1,
      'italic': -1,
      'fontFamily': -1,
      'fontSize': -1,
      'lineHeight': -1,
    };

    void processStyle(num matchScore, TokenStyle style, Object definition) {
      if (style.foreground != null && score['foreground']! <= matchScore) {
        score['foreground'] = matchScore;
        foreground = style.foreground;
        definitions!.foreground = definition;
      }
      for (final (property, info) in [
        ('bold', style.bold),
        ('underline', style.underline),
        ('strikethrough', style.strikethrough),
        ('italic', style.italic),
      ]) {
        if (info != null) {
          if (score[property]! <= matchScore) {
            score[property] = matchScore;
            flags[property] = info;
            switch (property) {
              case 'bold':
                definitions!.bold = definition;
              case 'underline':
                definitions!.underline = definition;
              case 'strikethrough':
                definitions!.strikethrough = definition;
              case 'italic':
                definitions!.italic = definition;
            }
          }
        }
      }
    }

    for (final rule in semanticTokenRules) {
      final matchScore = rule.selector.match(type, modifiers, language);
      if (matchScore >= 0) {
        processStyle(matchScore, rule.style, rule);
      }
    }

    var hasUndefinedStyleProperty = false;
    for (final key in score.keys.toList()) {
      if (score[key] == -1) {
        hasUndefinedStyleProperty = true;
      } else {
        // set it to the max, so it won't be replaced by a default
        score[key] = double.maxFinite;
      }
    }
    if (hasUndefinedStyleProperty) {
      for (final rule in registry.getTokenStylingDefaultRules()) {
        final matchScore = rule.selector.match(type, modifiers, language);
        if (matchScore >= 0) {
          TokenStyle? style;
          final scopesToProbe = rule.defaults.scopesToProbe;
          if (scopesToProbe != null) {
            style = resolveScopes(scopesToProbe);
            if (style != null) {
              processStyle(matchScore, style, scopesToProbe);
            }
          }
          if (style == null && useDefault) {
            final tokenStyleValue = rule.defaults[theme.type];
            style = resolveTokenStyleValue(tokenStyleValue);
            if (style != null) {
              processStyle(matchScore, style, tokenStyleValue!);
            }
          }
        }
      }
    }
    return TokenStyle.fromData(
      foreground: foreground,
      bold: flags['bold'],
      underline: flags['underline'],
      strikethrough: flags['strikethrough'],
      italic: flags['italic'],
    );
  }

  /// Resolves [tokenStyleValue] in the context of the theme.
  TokenStyle? resolveTokenStyleValue(TokenStyleValue? tokenStyleValue) {
    if (tokenStyleValue == null) {
      return null;
    } else if (tokenStyleValue is String) {
      final (:type, :modifiers, :language) = parseClassifierString(
        tokenStyleValue,
        '',
      );
      return getTokenStyle(type, modifiers, language!);
    } else if (tokenStyleValue is TokenStyle) {
      return tokenStyleValue;
    }
    return null;
  }

  /// The style of a semantic token; [typeWithLanguage] may name a language
  /// (`type:language`), else [defaultLanguage] applies. Modifiers written in
  /// [typeWithLanguage] are ignored, as upstream.
  ITokenStyle? getTokenStyleMetadata(
    String typeWithLanguage,
    List<String> modifiers,
    String defaultLanguage, {
    bool useDefault = true,
    TokenStyleDefinitions? definitions,
  }) {
    final (:type, modifiers: _, :language) = parseClassifierString(
      typeWithLanguage,
      defaultLanguage,
    );
    final style = getTokenStyle(
      type,
      modifiers,
      language!,
      useDefault: useDefault,
      definitions: definitions,
    );
    if (style == null) {
      return null;
    }

    return ITokenStyle(
      foreground: theme.getTokenColorId(style.foreground),
      bold: style.bold,
      underline: style.underline,
      strikethrough: style.strikethrough,
      italic: style.italic,
    );
  }

  /// The style of the first of [scopes] some TextMate rule of the theme
  /// matches.
  TokenStyle? resolveScopes(
    List<ProbeScope> scopes, [
    TextMateThemingRuleDefinitions? definitions,
  ]) {
    final matchers = _themeTokenScopeMatchers ??= [
      for (final rule in _themeTokenColors) _getScopeMatcher(rule),
    ];

    for (final scope in scopes) {
      String? foreground;
      String? fontStyle;
      var foregroundScore = -1;
      var fontStyleScore = -1;
      Object? fontStyleThemingRule;
      Object? foregroundThemingRule;

      void findTokenStyleForScopeInScopes(
        List<Matcher<ProbeScope>> scopeMatchers,
        List<Object?> themingRules,
      ) {
        for (var i = 0; i < scopeMatchers.length; i++) {
          final score = scopeMatchers[i](scope);
          if (score >= 0) {
            final themingRule = themingRules[i];
            final settings = (themingRule as Map<String, Object?>)['settings'];
            if (settings is! Map<String, Object?>) {
              continue;
            }
            final ruleForeground = _foregroundOf(settings['foreground']);
            if (score >= foregroundScore && ruleForeground != null) {
              foreground = ruleForeground;
              foregroundScore = score;
              foregroundThemingRule = themingRule;
            }
            final ruleFontStyle = settings['fontStyle'];
            if (score >= fontStyleScore && ruleFontStyle is String) {
              fontStyle = ruleFontStyle;
              fontStyleScore = score;
              fontStyleThemingRule = themingRule;
            }
          }
        }
      }

      findTokenStyleForScopeInScopes(matchers, _themeTokenColors);
      if (foreground != null || fontStyle != null) {
        if (definitions != null) {
          definitions.foreground = foregroundThemingRule;
          definitions.bold = definitions.italic = definitions.underline =
              definitions.strikethrough = fontStyleThemingRule;
          definitions.scope = scope;
        }

        return TokenStyle.fromSettings(
          foreground,
          fontStyle ?? TokenStyle.absent,
        );
      }
    }
    return null;
  }
}

/// A TextMate rule's truthy foreground, as `Color.fromHex` reads it: an empty
/// array reads as an invalid color (red); other values that are not strings
/// make upstream throw, and are ignored.
String? _foregroundOf(Object? value) => switch (value) {
  String s when s.isNotEmpty => s,
  List<Object?> list when list.isEmpty => '',
  _ => null,
};

int _noMatch(ProbeScope scope) => -1;

int nameMatcher(List<String> identifiers, ProbeScope scopes) {
  if (scopes.length < identifiers.length) {
    return -1;
  }

  int? score;
  final every = identifiers.every((identifier) {
    for (var i = scopes.length - 1; i >= 0; i--) {
      if (_scopesAreMatching(scopes[i], identifier)) {
        score = (i + 1) * 0x10000 + identifier.length;
        return true;
      }
    }
    return false;
  });
  return every && score != null ? score! : -1;
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

Matcher<ProbeScope> _getScopeMatcher(Object? rule) {
  if (rule is! Map<String, Object?>) {
    return _noMatch;
  }
  final ruleScope = rule['scope'];
  if (!_isTruthy(ruleScope) || !_isTruthy(rule['settings'])) {
    return _noMatch;
  }
  final matchers = <MatcherWithPriority<ProbeScope>>[];
  if (ruleScope is List<Object?>) {
    for (final rs in ruleScope) {
      createMatchers(jsToString(rs), nameMatcher, matchers);
    }
  } else {
    createMatchers(jsToString(ruleScope), nameMatcher, matchers);
  }

  if (matchers.isEmpty) {
    return _noMatch;
  }
  return (scope) {
    var max = matchers[0].matcher(scope);
    for (var i = 1; i < matchers.length; i++) {
      final score = matchers[i].matcher(scope);
      if (score > max) max = score;
    }
    return max;
  };
}

/// `readSemanticTokenRule` over a rule the loader kept: a color string, or a
/// setting with a string foreground/fontStyle or a boolean flag.
SemanticTokenRule? readSemanticTokenRule(
  TokenClassificationRegistry registry,
  SemanticTokenColor rule,
) {
  final selector = registry.parseTokenSelector(rule.selector);
  final settings = rule.value;
  TokenStyle? style;
  if (settings is String) {
    style = TokenStyle(rule.foreground, null, null, null, null);
  } else if (isSemanticTokenColorizationSetting(settings)) {
    final map = settings as Map<String, Object?>;
    Object? value(String key) =>
        map.containsKey(key) ? map[key] : TokenStyle.absent;
    // The foreground is parsed already.
    final parsed = TokenStyle.fromSettings(
      null,
      value('fontStyle'),
      value('bold'),
      value('underline'),
      value('strikethrough'),
      value('italic'),
    );
    style = TokenStyle(
      rule.foreground,
      parsed.bold,
      parsed.underline,
      parsed.strikethrough,
      parsed.italic,
    );
  }
  if (style != null) {
    return SemanticTokenRule(style, selector);
  }
  return null;
}

bool isSemanticTokenColorizationSetting(Object? style) =>
    style is Map<String, Object?> &&
    (style['foreground'] is String ||
        style['fontStyle'] is String ||
        style['italic'] is bool ||
        style['underline'] is bool ||
        style['strikethrough'] is bool ||
        style['bold'] is bool);

/// JavaScript truthiness of a JSON value.
bool _isTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  num n => n != 0 && !n.isNaN,
  _ => true,
};
