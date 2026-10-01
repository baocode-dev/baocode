/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/editor/common/languages/supports/tokenization.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971.
// dart:ui Color replaces VS Code's Color; FontTokenOptions is the narrow
// IFontTokenOptions adapter. Metadata constants are shared with the editor port.

import 'dart:ui' show Color;

import '../../encoded_token_attributes.dart';

final class TokenThemeRule {
  const TokenThemeRule({
    required this.token,
    this.foreground,
    this.background,
    this.fontStyle,
  });

  final String token;
  final String? foreground;
  final String? background;
  final String? fontStyle;
}

final class ParsedTokenThemeRule {
  const ParsedTokenThemeRule(
    this.token,
    this.index,
    this.fontStyle,
    this.foreground,
    this.background,
  );

  final String token;
  final int index;

  /// -1 when unset; otherwise an OR mask of [FontStyle] flags.
  final int fontStyle;
  final String? foreground;
  final String? background;
}

List<ParsedTokenThemeRule> parseTokenTheme(List<TokenThemeRule> source) {
  final result = <ParsedTokenThemeRule>[];
  for (var i = 0; i < source.length; i++) {
    final entry = source[i];
    var fontStyle = FontStyle.notSet;
    if (entry.fontStyle != null) {
      fontStyle = FontStyle.none;
      for (final segment in entry.fontStyle!.split(' ')) {
        switch (segment) {
          case 'italic':
            fontStyle |= FontStyle.italic;
          case 'bold':
            fontStyle |= FontStyle.bold;
          case 'underline':
            fontStyle |= FontStyle.underline;
          case 'strikethrough':
            fontStyle |= FontStyle.strikethrough;
        }
      }
    }
    result.add(
      ParsedTokenThemeRule(
        entry.token,
        i,
        fontStyle,
        entry.foreground,
        entry.background,
      ),
    );
  }
  return result;
}

TokenTheme _resolveParsedTokenThemeRules(
  List<ParsedTokenThemeRule> parsedThemeRules,
  List<String> customTokenColors,
) {
  // Sorting by scope, then source index, makes parent rules precede children
  // and preserves the priority of later rules for the same scope.
  final rules = List<ParsedTokenThemeRule>.of(parsedThemeRules)
    ..sort((a, b) {
      final r = strcmp(a.token, b.token);
      return r != 0 ? r : a.index.compareTo(b.index);
    });

  var defaultFontStyle = FontStyle.none;
  var defaultForeground = '000000';
  var defaultBackground = 'ffffff';
  var firstRule = 0;
  while (firstRule < rules.length && rules[firstRule].token == '') {
    final incoming = rules[firstRule++];
    if (incoming.fontStyle != FontStyle.notSet) {
      defaultFontStyle = incoming.fontStyle;
    }
    if (incoming.foreground != null) defaultForeground = incoming.foreground!;
    if (incoming.background != null) defaultBackground = incoming.background!;
  }

  final colorMap = ColorMap();
  for (final color in customTokenColors) {
    colorMap.getId(color);
  }
  final foregroundId = colorMap.getId(defaultForeground);
  final backgroundId = colorMap.getId(defaultBackground);
  final root = ThemeTrieElement(
    ThemeTrieElementRule(defaultFontStyle, foregroundId, backgroundId),
  );
  for (var i = firstRule; i < rules.length; i++) {
    final rule = rules[i];
    root.insert(
      rule.token,
      rule.fontStyle,
      colorMap.getId(rule.foreground),
      colorMap.getId(rule.background),
    );
  }
  return TokenTheme(colorMap, root);
}

final _colorRegExp = RegExp(r'^#?([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$');

/// IDs start at 1. Index 0 is reserved for an unspecified color.
final class ColorMap {
  final List<Color?> _id2color = [null];
  final Map<String, int> _color2id = {};

  int getId(String? color) {
    if (color == null) return ColorId.none;
    final match = _colorRegExp.firstMatch(color);
    if (match == null) {
      throw FormatException('Illegal value for token color: $color');
    }
    // Upstream discards the optional alpha component before creating Color.
    final rgb = match.group(1)!.toUpperCase();
    final previous = _color2id[rgb];
    if (previous != null) return previous;
    final id = _id2color.length;
    _color2id[rgb] = id;
    _id2color.add(Color(0xff000000 | int.parse(rgb, radix: 16)));
    return id;
  }

  List<Color?> getColorMap() => List<Color?>.of(_id2color);
}

final class TokenTheme {
  TokenTheme(this._colorMap, this._root);

  static TokenTheme createFromRawTokenTheme(
    List<TokenThemeRule> source,
    List<String> customTokenColors,
  ) => createFromParsedTokenTheme(parseTokenTheme(source), customTokenColors);

  static TokenTheme createFromParsedTokenTheme(
    List<ParsedTokenThemeRule> source,
    List<String> customTokenColors,
  ) => _resolveParsedTokenThemeRules(source, customTokenColors);

  final ColorMap _colorMap;
  final ThemeTrieElement _root;
  final Map<String, int> _cache = {};

  List<Color?> getColorMap() => _colorMap.getColorMap();

  /// Exposes the trie for upstream-parity tests.
  ExternalThemeTrieElement getThemeTrieElement() =>
      _root.toExternalThemeTrieElement();

  ThemeTrieElementRule matchRule(String token) => _root.match(token);

  int match(int languageId, String token) {
    // Cache only the language-independent metadata, just as upstream does.
    final result = _cache.putIfAbsent(token, () {
      final rule = matchRule(token);
      return (rule.metadata |
              (toStandardTokenType(token) << MetadataConsts.tokenTypeOffset)) &
          0xffffffff;
    });
    return (result | (languageId << MetadataConsts.languageIdOffset)) &
        0xffffffff;
  }
}

final _standardTokenTypeRegExp = RegExp(r'\b(comment|string|regex|regexp)\b');

int toStandardTokenType(String tokenType) {
  switch (_standardTokenTypeRegExp.firstMatch(tokenType)?.group(1)) {
    case 'comment':
      return StandardTokenType.comment;
    case 'string':
      return StandardTokenType.string;
    case 'regex':
    case 'regexp':
      return StandardTokenType.regEx;
    default:
      return StandardTokenType.other;
  }
}

int strcmp(String a, String b) => a.compareTo(b);

final class ThemeTrieElementRule {
  ThemeTrieElementRule(this._fontStyle, this._foreground, this._background)
    : metadata = _metadata(_fontStyle, _foreground, _background);

  int _fontStyle;
  int _foreground;
  int _background;
  int metadata;

  static int _metadata(int fontStyle, int foreground, int background) =>
      ((fontStyle << MetadataConsts.fontStyleOffset) |
          (foreground << MetadataConsts.foregroundOffset) |
          (background << MetadataConsts.backgroundOffset)) &
      0xffffffff;

  ThemeTrieElementRule clone() =>
      ThemeTrieElementRule(_fontStyle, _foreground, _background);

  void acceptOverwrite(int fontStyle, int foreground, int background) {
    if (fontStyle != FontStyle.notSet) _fontStyle = fontStyle;
    if (foreground != ColorId.none) _foreground = foreground;
    if (background != ColorId.none) _background = background;
    metadata = _metadata(_fontStyle, _foreground, _background);
  }
}

final class ExternalThemeTrieElement {
  ExternalThemeTrieElement(
    this.mainRule, [
    Map<String, ExternalThemeTrieElement>? children,
  ]) : children = children ?? {};

  final ThemeTrieElementRule mainRule;
  final Map<String, ExternalThemeTrieElement> children;
}

final class ThemeTrieElement {
  ThemeTrieElement(this._mainRule);

  final ThemeTrieElementRule _mainRule;
  final Map<String, ThemeTrieElement> _children = {};

  ExternalThemeTrieElement toExternalThemeTrieElement() =>
      ExternalThemeTrieElement(_mainRule, {
        for (final entry in _children.entries)
          entry.key: entry.value.toExternalThemeTrieElement(),
      });

  ThemeTrieElementRule match(String token) {
    if (token == '') return _mainRule;
    final dotIndex = token.indexOf('.');
    final head = dotIndex == -1 ? token : token.substring(0, dotIndex);
    final tail = dotIndex == -1 ? '' : token.substring(dotIndex + 1);
    final child = _children[head];
    return child == null ? _mainRule : child.match(tail);
  }

  void insert(String token, int fontStyle, int foreground, int background) {
    if (token == '') {
      _mainRule.acceptOverwrite(fontStyle, foreground, background);
      return;
    }
    final dotIndex = token.indexOf('.');
    final head = dotIndex == -1 ? token : token.substring(0, dotIndex);
    final tail = dotIndex == -1 ? '' : token.substring(dotIndex + 1);
    final child = _children.putIfAbsent(
      head,
      () => ThemeTrieElement(_mainRule.clone()),
    );
    child.insert(tail, fontStyle, foreground, background);
  }
}

String generateTokensCSSForColorMap(List<Color?> colorMap) {
  final rules = List<String>.filled(colorMap.length, '', growable: true);
  for (var i = 1; i < colorMap.length; i++) {
    final argb = colorMap[i]!.toARGB32();
    final rgb = argb & 0xffffff;
    final cssColor = (argb >>> 24) == 255
        ? '#${rgb.toRadixString(16).padLeft(6, '0')}'
        : 'rgba(${(rgb >>> 16) & 255}, ${(rgb >>> 8) & 255}, ${rgb & 255}, ${_jsNumber(num.parse(((argb >>> 24) / 255).toStringAsFixed(2)))})';
    rules[i] = '.mtk$i { color: $cssColor; }';
  }
  rules.addAll([
    '.mtki { font-style: italic; }',
    '.mtkb { font-weight: bold; }',
    '.mtku { text-decoration: underline; text-underline-position: under; }',
    '.mtks { text-decoration: line-through; }',
    '.mtks.mtku { text-decoration: underline line-through; text-underline-position: under; }',
  ]);
  return rules.join('\n');
}

/// The fields read by upstream generateTokensCSSForFontMap (line height is unused).
final class FontTokenOptions {
  const FontTokenOptions({
    this.fontFamily,
    this.fontSizeMultiplier,
    this.lineHeightMultiplier,
  });

  final String? fontFamily;
  final num? fontSizeMultiplier;
  final num? lineHeightMultiplier;
}

String generateTokensCSSForFontMap(List<FontTokenOptions?> fontMap) {
  final rules = <String>[];
  final fonts = <String>{};
  for (var i = 1; i < fontMap.length; i++) {
    final font = fontMap[i]!;
    final family = font.fontFamily ?? '';
    final size = font.fontSizeMultiplier ?? 0;
    if (family.isEmpty && size == 0) continue;
    final className = classNameForFontTokenDecorations(family, size);
    if (!fonts.add(className)) continue;
    var rule = '.$className {';
    if (family.isNotEmpty) rule += 'font-family: $family;';
    if (size != 0) {
      rule += 'font-size: calc(var(--editor-font-size)*${_jsNumber(size)});';
    }
    rule += '}';
    rules.add(rule);
  }
  return rules.join('\n');
}

String classNameForFontTokenDecorations(String fontFamily, num fontSize) {
  final normalized = fontFamily.toLowerCase().trim();
  final safeFontFamily = normalized.isEmpty
      ? 'default'
      : _cleanClassName(normalized);
  return _cleanClassName(
    'font-decoration-$safeFontFamily-${_jsNumber(fontSize)}',
  );
}

String _jsNumber(num value) =>
    value.isFinite && value == value.truncateToDouble()
    ? value.toInt().toString()
    : value.toString();

String _cleanClassName(String className) =>
    className.replaceAll(RegExp(r'[^a-z0-9_-]', caseSensitive: false), '-');
