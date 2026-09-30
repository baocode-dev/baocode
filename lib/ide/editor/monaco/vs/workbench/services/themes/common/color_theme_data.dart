/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/workbench/services/themes/common/colorThemeData.ts
// at 6a598d4a13031703d483d103c1d934a36ad27971: loading a color theme file
// with its `include` chain (`load`, `_loadColorTheme`, `_loadSyntaxTokens`),
// `fromExtensionTheme`, `type`, `semanticHighlighting`, `getColor`,
// `defines`, the `tokenColors` getter with its default rule and
// `defaultThemeColors`, and `tokenColorMap` (`getTokenColorIndex`,
// `TokenColorIndex`, `normalizeColor`). The default colors come from
// platform/theme/common/colors/editorColors.ts (`editor.foreground`,
// `editor.background`) and colors/baseColors.ts (`foreground`), resolved as
// colorUtils.ts `resolveDefaultColor`/`resolveColorValue` do.
//
// Not ported: user customizations (`setCustomizations` and the custom token,
// color and semantic rules; a theme reads as with default settings),
// transient colors, storage, token style resolution (`resolveScopes`,
// `getTokenStyle`, `findMetadata`), the font index and the rest of the color
// registry: [ColorThemeData.getDefault] knows only the three colors above.
//
// Deviations: files are read through a [ThemeResourceReader] from path
// strings (joined like `resources.joinPath`) instead of URIs; [colors] keeps
// the theme's strings, where upstream stores `Color.fromHex` of them (the
// conversion happens when a color is read); semantic token rules are kept as
// their raw selector and value ([semanticTokenColors]) plus the foreground
// the color index needs, not as parsed `SemanticTokenRule`s. Where upstream
// throws a TypeError on a malformed value (a non-string, non-Color token
// color; a rule that is not an object), the value is ignored. Load failures
// are [FormatException]s with upstream's messages. JSON object keys keep
// their order, where JavaScript's `for...in` visits integer-like keys first.

import 'package:path/path.dart' as p;

import '../../../../base/common/color.dart';
import '../../../../base/common/json.dart' as json;
import '../../../../base/common/json_error_messages.dart';
import '../../../../platform/theme/common/theme.dart';
import 'plist_parser.dart' as plist;
import 'theme_compatibility.dart';
import 'workbench_theme_service.dart';

/// Reads a theme file (a path as [ColorThemeData.location] and the theme's
/// `include`/`tokenColors` references resolve it).
typedef ThemeResourceReader = Future<String> Function(String path);

/// platform/theme/common/colorUtils.ts L89.
// ignore: constant_identifier_names
const String DEFAULT_COLOR_CONFIG_VALUE = 'default';

/// platform/theme/common/colors/editorColors.ts.
const String editorBackground = 'editor.background';
const String editorForeground = 'editor.foreground';

/// platform/theme/common/colors/baseColors.ts.
const String foreground = 'foreground';

/// The registry defaults of the colors `tokenColors` reads, per color scheme:
/// a hex string, a [Color], or another color's id.
final Map<String, Map<ColorScheme, Object>> _colorDefaults = {
  editorBackground: {
    ColorScheme.light: '#ffffff',
    ColorScheme.dark: '#1E1E1E',
    ColorScheme.highContrastDark: Color.black,
    ColorScheme.highContrastLight: Color.white,
  },
  editorForeground: {
    ColorScheme.light: '#333333',
    ColorScheme.dark: '#BBBBBB',
    ColorScheme.highContrastDark: Color.white,
    ColorScheme.highContrastLight: foreground,
  },
  foreground: {
    ColorScheme.dark: '#CCCCCC',
    ColorScheme.light: '#616161',
    ColorScheme.highContrastDark: '#FFFFFF',
    ColorScheme.highContrastLight: '#292929',
  },
};

/// A semantic token rule of the theme: its selector and value as written,
/// and the foreground upstream's `TokenStyle.fromSettings` parses from it.
class SemanticTokenColor {
  const SemanticTokenColor(this.selector, this.value, this.foreground);

  final String selector;
  final Object? value;
  final Color? foreground;
}

class ColorThemeData {
  ColorThemeData._(this.id, this.label, this.settingsId);

  final String id;
  final String label;
  final String settingsId;
  String? description;
  bool isLoaded = false;

  /// Only set for a theme from an extension.
  String? location;

  /// The contributing extension's id (`ExtensionData.extensionId`).
  String? extensionId;

  bool _themeSemanticHighlighting = false;
  List<Object?> _themeTokenColors = [];
  Map<String, String> _colorMap = {};
  List<SemanticTokenColor> _semanticTokenRules = [];

  List<ITextMateThemingRule>? _textMateThemingRules; // created on demand
  _TokenColorIndex? _tokenColorIndex; // created on demand

  bool get semanticHighlighting => _themeSemanticHighlighting;

  /// The colors the theme defines (its `colors`, or a TextMate theme's global
  /// settings), as written.
  Map<String, String> get colors => Map.unmodifiable(_colorMap);

  /// The theme's `semanticTokenColors` that upstream turns into rules, in
  /// load order (included files first).
  List<SemanticTokenColor> get semanticTokenColors =>
      List.unmodifiable(_semanticTokenRules);

  /// The theme's TextMate rules as loaded (`tokenColors` entries or a
  /// TextMate theme's `settings`), before [tokenColors] normalizes them.
  List<Object?> get themeTokenColors => List.unmodifiable(_themeTokenColors);

  List<ITextMateThemingRule> get tokenColors {
    final cached = _textMateThemingRules;
    if (cached != null) {
      return cached;
    }
    final result = <ITextMateThemingRule>[];

    // the default rule (scope empty) is always the first rule. Ignore all
    // other default rules.
    final foreground =
        getColor(editorForeground) ?? getDefault(editorForeground)!;
    final background =
        getColor(editorBackground) ?? getDefault(editorBackground)!;
    result.add(
      ITextMateThemingRule(
        settings: ITokenColorizationSetting(
          foreground: normalizeColor(foreground),
          background: normalizeColor(background),
        ),
      ),
    );

    var hasDefaultTokens = false;

    void addRule(Object? rule) {
      if (rule is! Map<String, Object?>) {
        return;
      }
      final scope = rule['scope'];
      final ruleSettings = rule['settings'];
      if (_isTruthy(scope) && _isTruthy(ruleSettings)) {
        if (scope == 'token.info-token') {
          hasDefaultTokens = true;
        }
        Object? setting(String key) =>
            ruleSettings is Map<String, Object?> ? ruleSettings[key] : null;
        result.add(
          ITextMateThemingRule(
            scope: scope,
            settings: ITokenColorizationSetting(
              foreground: normalizeColor(setting('foreground')),
              background: normalizeColor(setting('background')),
              fontStyle: setting('fontStyle'),
              fontSize: setting('fontSize'),
              fontFamily: setting('fontFamily'),
              lineHeight: setting('lineHeight'),
            ),
          ),
        );
      }
    }

    _themeTokenColors.forEach(addRule);

    if (!hasDefaultTokens) {
      defaultThemeColors[type]!.forEach(addRule);
    }
    return _textMateThemingRules = List.unmodifiable(result);
  }

  Color? getColor(String colorId, [bool? useDefault]) {
    final color = _colorMap[colorId];
    if (color != null) {
      return Color.fromHex(color);
    }
    if (useDefault != false) {
      return getDefault(colorId);
    }
    return null;
  }

  bool defines(String colorId) => _colorMap.containsKey(colorId);

  /// The color registry's default: known only for `editor.foreground`,
  /// `editor.background` and `foreground`.
  Color? getDefault(String colorId) {
    final colorValue = _colorDefaults[colorId]?[type];
    if (colorValue == null) {
      return null;
    }
    if (colorValue is Color) {
      return colorValue;
    }
    final value = colorValue as String;
    return value.startsWith('#') ? Color.fromHex(value) : getColor(value);
  }

  _TokenColorIndex _getTokenColorIndex() {
    // collect all colors that tokens can have
    var index = _tokenColorIndex;
    if (index == null) {
      index = _TokenColorIndex();
      for (final rule in tokenColors) {
        index.add(rule.settings.foreground);
        index.add(rule.settings.background);
      }

      for (final rule in _semanticTokenRules) {
        index.add(rule.foreground);
      }
      // The registry's default semantic rules (tokenClassificationRegistry.ts)
      // only probe TextMate scopes; none has a color of its own to add.

      _tokenColorIndex = index;
    }
    return index;
  }

  /// Color id to normalized color (`#RRGGBB` or `#RRGGBBAA`); index 0 is
  /// null, as upstream's array has a hole there.
  List<String?> get tokenColorMap => _getTokenColorIndex().asArray();

  /// The id of a color in [tokenColorMap], 0 if absent.
  int getTokenColorId(Object? color) => _getTokenColorIndex().get(color);

  Future<void> ensureLoaded(ThemeResourceReader reader) =>
      !isLoaded ? _load(reader) : Future.value();

  Future<void> reload(ThemeResourceReader reader) => _load(reader);

  Future<void> _load(ThemeResourceReader reader) async {
    final location = this.location;
    if (location == null) {
      return;
    }
    _themeTokenColors = [];
    clearCaches();

    final result = _ColorThemeLoadResult();
    await _loadColorTheme(reader, location, result);
    isLoaded = true;
    _semanticTokenRules = result.semanticTokenRules;
    _colorMap = result.colors;
    _themeTokenColors = result.textMateRules;
    _themeSemanticHighlighting = result.semanticHighlighting;
  }

  void clearCaches() {
    _tokenColorIndex = null;
    _textMateThemingRules = null;
  }

  ThemeTypeSelector? get themeTypeSelector =>
      ThemeTypeSelector.fromValue(classNames[0]);

  List<String> get classNames => id.split(' ');

  ColorScheme get type {
    switch (themeTypeSelector) {
      case ThemeTypeSelector.vs:
        return ColorScheme.light;
      case ThemeTypeSelector.hcBlack:
        return ColorScheme.highContrastDark;
      case ThemeTypeSelector.hcLight:
        return ColorScheme.highContrastLight;
      default:
        return ColorScheme.dark;
    }
  }

  static ColorThemeData createLoadedEmptyTheme(String id, String settingsId) {
    final themeData = ColorThemeData._(id, '', settingsId);
    themeData.isLoaded = true;
    return themeData;
  }

  /// [colorThemeLocation] is the path [ThemeResourceReader] reads the theme
  /// file from.
  static ColorThemeData fromExtensionTheme(
    IThemeExtensionPoint theme,
    String colorThemeLocation, {
    required String extensionId,
  }) {
    final uiTheme = theme.uiTheme;
    final baseTheme = uiTheme == null || uiTheme.isEmpty ? 'vs-dark' : uiTheme;
    final themeSelector = _toCSSSelector(extensionId, theme.path);
    final id = '$baseTheme $themeSelector';
    final themeLabel = theme.label;
    final label = themeLabel == null || themeLabel.isEmpty
        ? p.posix.basename(theme.path)
        : themeLabel;
    final settingsId = theme.id.isEmpty ? label : theme.id;
    final themeData = ColorThemeData._(id, label, settingsId);
    themeData.description = theme.description;
    themeData.location = colorThemeLocation;
    themeData.extensionId = extensionId;
    themeData.isLoaded = false;
    return themeData;
  }
}

String _toCSSSelector(String extensionId, String path) {
  if (path.startsWith('./')) {
    path = path.substring(2);
  }
  var str = '$extensionId-$path';

  //remove all characters that are not allowed in css
  str = str.replaceAll(RegExp(r'[^_a-zA-Z0-9-]'), '-');
  if (RegExp(r'[0-9-]').hasMatch(str[0])) {
    str = '_$str';
  }
  return str;
}

class _ColorThemeLoadResult {
  final List<Object?> textMateRules = [];
  final Map<String, String> colors = {};
  final List<SemanticTokenColor> semanticTokenRules = [];
  bool semanticHighlighting = false;
}

/// `resources.extname`: the extension of the last path segment.
String _extname(String path) => p.posix.extension(path);

/// `resources.joinPath(resources.dirname(location), relative)`: joined and
/// normalized; unlike `package:path`'s `join`, an absolute [relative] does not
/// replace the directory.
String _joinDirname(String location, String relative) {
  final dirname = p.posix.dirname(location);
  return p.posix.normalize('$dirname/$relative');
}

Future<void> _loadColorTheme(
  ThemeResourceReader reader,
  String themeLocation,
  _ColorThemeLoadResult result,
) async {
  if (_extname(themeLocation) != '.json') {
    return _loadSyntaxTokens(reader, themeLocation, result);
  }
  final content = await reader(themeLocation);
  final errors = <json.ParseError>[];
  final contentValue = json.parse(content, errors);
  if (errors.isNotEmpty) {
    throw FormatException(
      'Problems parsing JSON theme file: '
      '${errors.map((e) => getParseErrorMessage(e.error)).join(', ')}',
    );
  } else if (json.getNodeType(contentValue) != 'object') {
    throw const FormatException(
      'Invalid format for JSON theme file: Object expected.',
    );
  }
  final value = contentValue as Map<String, Object?>;
  final include = value['include'];
  if (_isTruthy(include)) {
    if (include is! String) {
      throw FormatException(
        'Problem parsing color theme file: $themeLocation. '
        "Property 'include' is not a path.",
      );
    }
    await _loadColorTheme(reader, _joinDirname(themeLocation, include), result);
  }
  final settings = value['settings'];
  if (settings is List<Object?>) {
    convertSettings(
      settings,
      textMateRules: result.textMateRules,
      colors: result.colors,
    );
    return;
  }
  result.semanticHighlighting =
      result.semanticHighlighting || _isTruthy(value['semanticHighlighting']);
  final colors = value['colors'];
  if (_isTruthy(colors)) {
    if (colors is! Map<String, Object?> && colors is! List<Object?>) {
      throw FormatException(
        'Problem parsing color theme file: $themeLocation. '
        "Property 'colors' is not of type 'object'.",
      );
    }
    // new JSON color themes format
    for (final MapEntry(key: colorId, value: colorVal) in _forIn(colors!)) {
      if (colorVal == DEFAULT_COLOR_CONFIG_VALUE) {
        // ignore colors that are set to to default
        result.colors.remove(colorId);
      } else if (colorVal is String) {
        result.colors[colorId] = colorVal;
      }
    }
  }
  final tokenColors = value['tokenColors'];
  if (_isTruthy(tokenColors)) {
    if (tokenColors is List<Object?>) {
      result.textMateRules.addAll(tokenColors);
    } else if (tokenColors is String) {
      await _loadSyntaxTokens(
        reader,
        _joinDirname(themeLocation, tokenColors),
        result,
      );
    } else {
      throw FormatException(
        'Problem parsing color theme file: $themeLocation. '
        "Property 'tokenColors' should be either an array specifying colors "
        'or a path to a TextMate theme file',
      );
    }
  }
  final semanticTokenColors = value['semanticTokenColors'];
  if (_isTruthy(semanticTokenColors) &&
      (semanticTokenColors is Map<String, Object?> ||
          semanticTokenColors is List<Object?>)) {
    for (final MapEntry(:key, :value) in _forIn(semanticTokenColors!)) {
      final SemanticTokenColor? rule;
      try {
        rule = _readSemanticTokenRule(key, value);
      } on FormatException {
        throw FormatException(
          'Problem parsing color theme file: $themeLocation. '
          "Property 'semanticTokenColors' contains a invalid selector",
        );
      }
      if (rule != null) {
        result.semanticTokenRules.add(rule);
      }
    }
  }
}

Future<void> _loadSyntaxTokens(
  ThemeResourceReader reader,
  String themeLocation,
  _ColorThemeLoadResult result,
) async {
  final String content;
  try {
    content = await reader(themeLocation);
  } catch (error) {
    throw FormatException(
      'Problems loading tmTheme file $themeLocation: $error',
    );
  }
  try {
    final contentValue = plist.parse(content);
    final settings = contentValue is Map<String, Object?>
        ? contentValue['settings']
        : null;
    if (settings is! List<Object?>) {
      throw const FormatException(
        "Problem parsing tmTheme file: {0}. 'settings' is not array.",
      );
    }
    convertSettings(
      settings,
      textMateRules: result.textMateRules,
      colors: result.colors,
    );
  } on FormatException catch (error) {
    throw FormatException('Problems parsing tmTheme file: ${error.message}');
  }
}

/// `readSemanticTokenRule` (L936-948) as far as the color index needs it:
/// the style's foreground. `tokenClassificationRegistry.parseTokenSelector`
/// accepts every selector.
SemanticTokenColor? _readSemanticTokenRule(String selector, Object? settings) {
  if (settings is String) {
    return SemanticTokenColor(selector, settings, Color.fromHex(settings));
  }
  if (_isSemanticTokenColorizationSetting(settings)) {
    final style = settings as Map<String, Object?>;
    Color? foreground;
    if (style.containsKey('foreground')) {
      final value = style['foreground'];
      if (value is String) {
        foreground = Color.fromHex(value);
      } else if (value is List && value.isEmpty) {
        // `parseHex` sees length 0.
        foreground = Color.red;
      } else {
        // Upstream's `parseHex` throws a TypeError.
        throw const FormatException('invalid foreground');
      }
    }
    return SemanticTokenColor(selector, settings, foreground);
  }
  return null;
}

bool _isSemanticTokenColorizationSetting(Object? style) =>
    style is Map<String, Object?> &&
    (style['foreground'] is String ||
        style['fontStyle'] is String ||
        style['italic'] is bool ||
        style['underline'] is bool ||
        style['strikethrough'] is bool ||
        style['bold'] is bool);

const Map<ColorScheme, List<Map<String, Object?>>> defaultThemeColors = {
  ColorScheme.light: [
    {
      'scope': 'token.info-token',
      'settings': {'foreground': '#316bcd'},
    },
    {
      'scope': 'token.warn-token',
      'settings': {'foreground': '#cd9731'},
    },
    {
      'scope': 'token.error-token',
      'settings': {'foreground': '#cd3131'},
    },
    {
      'scope': 'token.debug-token',
      'settings': {'foreground': '#800080'},
    },
  ],
  ColorScheme.dark: [
    {
      'scope': 'token.info-token',
      'settings': {'foreground': '#6796e6'},
    },
    {
      'scope': 'token.warn-token',
      'settings': {'foreground': '#cd9731'},
    },
    {
      'scope': 'token.error-token',
      'settings': {'foreground': '#f44747'},
    },
    {
      'scope': 'token.debug-token',
      'settings': {'foreground': '#b267e6'},
    },
  ],
  ColorScheme.highContrastLight: [
    {
      'scope': 'token.info-token',
      'settings': {'foreground': '#316bcd'},
    },
    {
      'scope': 'token.warn-token',
      'settings': {'foreground': '#cd9731'},
    },
    {
      'scope': 'token.error-token',
      'settings': {'foreground': '#cd3131'},
    },
    {
      'scope': 'token.debug-token',
      'settings': {'foreground': '#800080'},
    },
  ],
  ColorScheme.highContrastDark: [
    {
      'scope': 'token.info-token',
      'settings': {'foreground': '#6796e6'},
    },
    {
      'scope': 'token.warn-token',
      'settings': {'foreground': '#008000'},
    },
    {
      'scope': 'token.error-token',
      'settings': {'foreground': '#FF0000'},
    },
    {
      'scope': 'token.debug-token',
      'settings': {'foreground': '#b267e6'},
    },
  ],
};

class _TokenColorIndex {
  int _lastColorId = 0;
  final List<String?> _id2color = [null];
  final Map<String, int> _color2id = {};

  int add(Object? color) {
    final normalized = normalizeColor(color);
    if (normalized == null) {
      return 0;
    }

    final value = _color2id[normalized];
    if (value != null) {
      return value;
    }
    final id = ++_lastColorId;
    _color2id[normalized] = id;
    _id2color.add(normalized);
    return id;
  }

  int get(Object? color) {
    final normalized = normalizeColor(color);
    if (normalized == null) {
      return 0;
    }
    return _color2id[normalized] ?? 0;
  }

  List<String?> asArray() => List.of(_id2color);
}

/// Normalizes a color to upper-case `#RRGGBB` or `#RRGGBBAA` (an opaque
/// alpha dropped); null for a missing or malformed color. A [Color] is
/// formatted first.
String? normalizeColor(Object? color) {
  if (!_isTruthy(color)) {
    return null;
  }
  final String value;
  if (color is Color) {
    value = ColorFormatCSS.formatHexA(color, true);
  } else if (color is String) {
    value = color;
  } else {
    return null;
  }
  final len = value.length;
  if (value.codeUnitAt(0) != 0x23 /* # */ ||
      (len != 4 && len != 5 && len != 7 && len != 9)) {
    return null;
  }
  final result = <int>[0x23];

  for (var i = 1; i < len; i++) {
    final upper = _hexUpper(value.codeUnitAt(i));
    if (upper == 0) {
      return null;
    }
    result.add(upper);
    if (len == 4 || len == 5) {
      result.add(upper);
    }
  }

  if (result.length == 9 && result[7] == 0x46 && result[8] == 0x46) {
    result.length = 7;
  }
  return String.fromCharCodes(result);
}

int _hexUpper(int charCode) {
  if (charCode >= 0x30 && charCode <= 0x39 ||
      charCode >= 0x41 && charCode <= 0x46) {
    return charCode;
  } else if (charCode >= 0x61 && charCode <= 0x66) {
    return charCode - 0x61 + 0x41;
  }
  return 0;
}

/// JavaScript truthiness of a JSON value.
bool _isTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  num n => n != 0 && !n.isNaN,
  _ => true,
};

/// JavaScript's `for...in` over a JSON object or array.
Iterable<MapEntry<String, Object?>> _forIn(Object value) sync* {
  if (value is Map<String, Object?>) {
    yield* value.entries;
  } else if (value is List<Object?>) {
    for (var i = 0; i < value.length; i++) {
      yield MapEntry('$i', value[i]);
    }
  }
}
