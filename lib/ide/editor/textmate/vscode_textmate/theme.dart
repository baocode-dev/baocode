// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/theme.ts (MIT, see LICENSE.md).

import 'js_semantics.dart';
import 'raw_theme.dart';
import 'utils.dart';

export 'raw_theme.dart';

class Theme {
  Theme(this._colorMap, this._defaults, this._root) {
    _cachedMatchRoot = CachedFn<String, List<ThemeTrieElementRule>>(
      (scopeName) => _root.match(scopeName),
    );
  }

  static Theme createFromRawTheme(
    IRawTheme? source, [
    List<String?>? colorMap,
  ]) {
    return createFromParsedTheme(parseTheme(source), colorMap);
  }

  static Theme createFromParsedTheme(
    List<ParsedThemeRule> source, [
    List<String?>? colorMap,
  ]) {
    return _resolveParsedThemeRules(source, colorMap);
  }

  late final CachedFn<String, List<ThemeTrieElementRule>> _cachedMatchRoot;

  final ColorMap _colorMap;
  final StyleAttributes _defaults;
  final ThemeTrieElement _root;

  List<String> getColorMap() {
    return _colorMap.getColorMap();
  }

  StyleAttributes getDefaults() {
    return _defaults;
  }

  StyleAttributes? match(ScopeStack? scopePath) {
    if (scopePath == null) {
      return _defaults;
    }
    final scopeName = scopePath.scopeName;
    final matchingTrieElements = _cachedMatchRoot.get(scopeName);

    ThemeTrieElementRule? effectiveRule;
    for (final v in matchingTrieElements) {
      if (_scopePathMatchesParentScopes(scopePath.parent, v.parentScopes)) {
        effectiveRule = v;
        break;
      }
    }
    if (effectiveRule == null) {
      return null;
    }

    return StyleAttributes(
      effectiveRule.fontStyle,
      effectiveRule.foreground,
      effectiveRule.background,
      effectiveRule.fontFamily,
      effectiveRule.fontSize,
      effectiveRule.lineHeight,
    );
  }
}

/// Identifiers with a binary dot operator.
/// Examples: `baz` or `foo.bar`
typedef ScopeName = String;

/// An expression language of ScopeNames with a binary space (to indicate nesting) operator.
/// Examples: `foo.bar boo.baz`
typedef ScopePath = String;

/// An expression language of ScopePathStr with a binary comma (to indicate alternatives) operator.
/// Examples: `foo.bar boo.baz,quick quack`
typedef ScopePattern = String;

/// A setting's style with upstream's font fields, which `raw_theme.dart`
/// cannot carry: `fontFamily` counts when it is a string, `fontSize` and
/// `lineHeight` when they are numbers.
class IRawThemeSettingStyleWithFont extends IRawThemeSettingStyle {
  const IRawThemeSettingStyleWithFont({
    super.fontStyle,
    super.foreground,
    super.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  });

  final Object? fontFamily;
  final Object? fontSize;
  final Object? lineHeight;
}

class ScopeStack {
  ScopeStack(this.parent, this.scopeName);

  /// Upstream's static `ScopeStack.push(path, scopeNames)`.
  static ScopeStack? pushAll(ScopeStack? path, List<ScopeName> scopeNames) {
    for (final name in scopeNames) {
      path = ScopeStack(path, name);
    }
    return path;
  }

  static ScopeStack? from(List<ScopeName> segments) {
    ScopeStack? result;
    for (var i = 0; i < segments.length; i++) {
      result = ScopeStack(result, segments[i]);
    }
    return result;
  }

  final ScopeStack? parent;
  final ScopeName scopeName;

  ScopeStack push(ScopeName scopeName) {
    return ScopeStack(this, scopeName);
  }

  List<ScopeName> getSegments() {
    ScopeStack? item = this;
    final result = <ScopeName>[];
    while (item != null) {
      result.add(item.scopeName);
      item = item.parent;
    }
    return result.reversed.toList();
  }

  @override
  String toString() {
    return getSegments().join(' ');
  }

  bool extendsStack(ScopeStack other) {
    if (identical(this, other)) {
      return true;
    }
    if (parent == null) {
      return false;
    }
    return parent!.extendsStack(other);
  }

  /// The scope names from [base] (exclusive) up to this stack, or null when
  /// [base] is not an ancestor (upstream returns `undefined`).
  List<String>? getExtensionIfDefined(ScopeStack? base) {
    final result = <String>[];
    ScopeStack? item = this;
    while (item != null && !identical(item, base)) {
      result.add(item.scopeName);
      item = item.parent;
    }
    return identical(item, base) ? result.reversed.toList() : null;
  }
}

bool _scopePathMatchesParentScopes(
  ScopeStack? scopePath,
  List<ScopeName> parentScopes,
) {
  if (parentScopes.isEmpty) {
    return true;
  }

  // Starting with the deepest parent scope, look for a match in the scope path.
  for (var index = 0; index < parentScopes.length; index++) {
    var scopePattern = parentScopes[index];
    var scopeMustMatch = false;

    // Check for a child combinator (a parent-child relationship)
    if (scopePattern == '>') {
      if (index == parentScopes.length - 1) {
        // Invalid use of child combinator
        return false;
      }
      scopePattern = parentScopes[++index];
      scopeMustMatch = true;
    }

    while (scopePath != null) {
      if (_matchesScope(scopePath.scopeName, scopePattern)) {
        break;
      }
      if (scopeMustMatch) {
        // If a child combinator was used, the parent scope must match.
        return false;
      }
      scopePath = scopePath.parent;
    }

    if (scopePath == null) {
      // No more potential matches
      return false;
    }
    scopePath = scopePath.parent;
  }

  // All parent scopes were matched.
  return true;
}

bool _matchesScope(ScopeName scopeName, ScopeName scopePattern) {
  return scopePattern == scopeName ||
      (scopeName.startsWith(scopePattern) &&
          scopeName.length > scopePattern.length &&
          scopeName.codeUnitAt(scopePattern.length) == 0x2E /* . */ );
}

class StyleAttributes {
  const StyleAttributes(
    this.fontStyle,
    this.foregroundId,
    this.backgroundId,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  );

  final int fontStyle;
  final int foregroundId;
  final int backgroundId;
  final String fontFamily;
  final num fontSize;
  final num lineHeight;
}

/// Parse a raw theme into rules.
List<ParsedThemeRule> parseTheme(IRawTheme? source) {
  if (source == null) {
    return [];
  }
  final settings = source.settings;
  final result = <ParsedThemeRule>[];
  for (var i = 0, len = settings.length; i < len; i++) {
    final entry = settings[i];
    final entrySettings = entry.settings;

    List<Object?> scopes;
    final entryScope = entry.scope;
    if (entryScope is String) {
      var scope = entryScope;

      // remove leading commas
      scope = scope.replaceFirst(_leadingCommas, '');

      // remove trailing commans
      scope = scope.replaceFirst(_trailingCommas, '');

      scopes = jsSplit(scope, ',');
    } else if (entryScope is List) {
      scopes = entryScope;
    } else {
      scopes = [''];
    }

    var fontStyle = FontStyle.notSet;
    final rawFontStyle = entrySettings.fontStyle;
    if (rawFontStyle is String) {
      fontStyle = FontStyle.none;

      final segments = jsSplit(rawFontStyle, ' ');
      for (var j = 0, lenJ = segments.length; j < lenJ; j++) {
        final segment = segments[j];
        switch (segment) {
          case 'italic':
            fontStyle = fontStyle | FontStyle.italic;
            break;
          case 'bold':
            fontStyle = fontStyle | FontStyle.bold;
            break;
          case 'underline':
            fontStyle = fontStyle | FontStyle.underline;
            break;
          case 'strikethrough':
            fontStyle = fontStyle | FontStyle.strikethrough;
            break;
        }
      }
    }

    String? foreground;
    final rawForeground = entrySettings.foreground;
    if (rawForeground is String && isValidHexColor(rawForeground)) {
      foreground = rawForeground;
    }

    String? background;
    final rawBackground = entrySettings.background;
    if (rawBackground is String && isValidHexColor(rawBackground)) {
      background = rawBackground;
    }

    var fontFamily = '';
    num fontSize = 0;
    num lineHeight = 0;
    if (entrySettings is IRawThemeSettingStyleWithFont) {
      final rawFontFamily = entrySettings.fontFamily;
      if (rawFontFamily is String) {
        fontFamily = rawFontFamily;
      }
      final rawFontSize = entrySettings.fontSize;
      if (rawFontSize is num) {
        fontSize = rawFontSize;
      }
      final rawLineHeight = entrySettings.lineHeight;
      if (rawLineHeight is num) {
        lineHeight = rawLineHeight;
      }
    }

    for (var j = 0, lenJ = scopes.length; j < lenJ; j++) {
      final rawScope = scopes[j];
      if (rawScope is! String) {
        jsTypeError('scopes[j].trim is not a function');
      }
      final scopeText = jsTrim(rawScope);

      final segments = jsSplit(scopeText, ' ');

      final scope = segments[segments.length - 1];
      List<String>? parentScopes;
      if (segments.length > 1) {
        parentScopes = segments.sublist(0, segments.length - 1);
        parentScopes = parentScopes.reversed.toList();
      }

      result.add(
        ParsedThemeRule(
          scope,
          parentScopes,
          i,
          fontStyle,
          foreground,
          background,
          fontFamily,
          fontSize,
          lineHeight,
        ),
      );
    }
  }

  return result;
}

final RegExp _leadingCommas = RegExp(r'^[,]+');
final RegExp _trailingCommas = RegExp(r'[,]+$');

class ParsedThemeRule {
  ParsedThemeRule(
    this.scope,
    this.parentScopes,
    this.index,
    this.fontStyle,
    this.foreground,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  );

  final ScopeName scope;
  final List<ScopeName>? parentScopes;
  final int index;
  final int fontStyle;
  final String? foreground;
  final String? background;
  final String fontFamily;
  final num fontSize;
  final num lineHeight;
}

/// Bit flags, combinable with bitwise OR.
abstract final class FontStyle {
  static const int notSet = -1;
  static const int none = 0;
  static const int italic = 1;
  static const int bold = 2;
  static const int underline = 4;
  static const int strikethrough = 8;
}

String fontStyleToString(int fontStyle) {
  if (fontStyle == FontStyle.notSet) {
    return 'not set';
  }

  var style = '';
  if (fontStyle & FontStyle.italic != 0) {
    style += 'italic ';
  }
  if (fontStyle & FontStyle.bold != 0) {
    style += 'bold ';
  }
  if (fontStyle & FontStyle.underline != 0) {
    style += 'underline ';
  }
  if (fontStyle & FontStyle.strikethrough != 0) {
    style += 'strikethrough ';
  }
  if (style == '') {
    style = 'none';
  }
  return jsTrim(style);
}

/// Resolve rules (i.e. inheritance).
Theme _resolveParsedThemeRules(
  List<ParsedThemeRule> parsedThemeRules,
  List<String?>? colorMapSource,
) {
  // Sort rules lexicographically, and then by index if necessary
  jsArraySort<ParsedThemeRule>(parsedThemeRules, (a, b) {
    var r = strcmp(a.scope, b.scope);
    if (r != 0) {
      return r;
    }
    r = strArrCmp(a.parentScopes, b.parentScopes);
    if (r != 0) {
      return r;
    }
    return a.index - b.index;
  });

  // Determine defaults
  var defaultFontStyle = FontStyle.none;
  var defaultForeground = '#000000';
  var defaultBackground = '#ffffff';
  var defaultFontFamily = '';
  num defaultFontSize = 0;
  num defaultLineHeight = 0;

  while (parsedThemeRules.isNotEmpty && parsedThemeRules[0].scope == '') {
    final incomingDefaults = parsedThemeRules.removeAt(0);
    if (incomingDefaults.fontStyle != FontStyle.notSet) {
      defaultFontStyle = incomingDefaults.fontStyle;
    }
    if (incomingDefaults.foreground != null) {
      defaultForeground = incomingDefaults.foreground!;
    }
    if (incomingDefaults.background != null) {
      defaultBackground = incomingDefaults.background!;
    }
    // Upstream compares these non-null values to null, so they always apply.
    defaultFontFamily = incomingDefaults.fontFamily;
    defaultFontSize = incomingDefaults.fontSize;
    defaultLineHeight = incomingDefaults.lineHeight;
  }
  final colorMap = ColorMap(colorMapSource);
  final defaults = StyleAttributes(
    defaultFontStyle,
    colorMap.getId(defaultForeground),
    colorMap.getId(defaultBackground),
    defaultFontFamily,
    defaultFontSize,
    defaultLineHeight,
  );

  final root = ThemeTrieElement(
    ThemeTrieElementRule(
      0,
      null,
      FontStyle.notSet,
      0,
      0,
      defaultFontFamily,
      defaultFontSize,
      defaultLineHeight,
    ),
    [],
  );
  for (var i = 0, len = parsedThemeRules.length; i < len; i++) {
    final rule = parsedThemeRules[i];
    root.insert(
      0,
      rule.scope,
      rule.parentScopes,
      rule.fontStyle,
      colorMap.getId(rule.foreground),
      colorMap.getId(rule.background),
      rule.fontFamily,
      rule.fontSize,
      rule.lineHeight,
    );
  }

  return Theme(colorMap, defaults, root);
}

class ColorMap {
  /// A null entry is a hole of upstream's sparse array, as VS Code's
  /// `tokenColorMap` has at index 0: it names no color.
  ColorMap([List<String?>? colorMap]) {
    if (colorMap != null) {
      _isFrozen = true;
      for (var i = 0, len = colorMap.length; i < len; i++) {
        final color = colorMap[i];
        if (color != null) _color2id[color] = i;
        _setId2Color(i, color);
      }
    } else {
      _isFrozen = false;
    }
  }

  late final bool _isFrozen;
  int _lastColorId = 0;
  final List<String?> _id2color = <String?>[];
  final Map<String, int> _color2id = <String, int>{};

  void _setId2Color(int id, String? color) {
    if (_id2color.length <= id) _id2color.length = id + 1;
    _id2color[id] = color;
  }

  int getId(String? color) {
    if (color == null) {
      return 0;
    }
    color = color.toUpperCase();
    var value = _color2id[color];
    if (value != null && value != 0) {
      return value;
    }
    if (_isFrozen) {
      throw StateError('Missing color in color map - $color');
    }
    value = ++_lastColorId;
    _color2id[color] = value;
    _setId2Color(value, color);
    return value;
  }

  /// Upstream returns a sparse array; the holes (index 0 of an unfrozen map)
  /// are empty strings here.
  List<String> getColorMap() {
    return [for (final color in _id2color) color ?? ''];
  }
}

const List<ScopeName> _emptyParentScopes = <ScopeName>[];

class ThemeTrieElementRule {
  ThemeTrieElementRule(
    this.scopeDepth,
    List<ScopeName>? parentScopes,
    this.fontStyle,
    this.foreground,
    this.background,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  ) : parentScopes = parentScopes ?? _emptyParentScopes;

  int scopeDepth;
  List<ScopeName> parentScopes;
  int fontStyle;
  int foreground;
  int background;
  String fontFamily;
  num fontSize;
  num lineHeight;

  ThemeTrieElementRule clone() {
    return ThemeTrieElementRule(
      scopeDepth,
      parentScopes,
      fontStyle,
      foreground,
      background,
      fontFamily,
      fontSize,
      lineHeight,
    );
  }

  static List<ThemeTrieElementRule> cloneArr(List<ThemeTrieElementRule> arr) {
    final r = <ThemeTrieElementRule>[];
    for (var i = 0, len = arr.length; i < len; i++) {
      r.add(arr[i].clone());
    }
    return r;
  }

  void acceptOverwrite(
    int scopeDepth,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    num fontSize,
    num lineHeight,
  ) {
    if (this.scopeDepth > scopeDepth) {
      // Upstream logs 'how did this happen?'.
    } else {
      this.scopeDepth = scopeDepth;
    }
    if (fontStyle != FontStyle.notSet) {
      this.fontStyle = fontStyle;
    }
    if (foreground != 0) {
      this.foreground = foreground;
    }
    if (background != 0) {
      this.background = background;
    }
    if (fontFamily != '') {
      this.fontFamily = fontFamily;
    }
    if (fontSize != 0) {
      this.fontSize = fontSize;
    }
    if (lineHeight != 0) {
      this.lineHeight = lineHeight;
    }
  }
}

class ThemeTrieElement {
  ThemeTrieElement(
    this._mainRule, [
    List<ThemeTrieElementRule>? rulesWithParentScopes,
    Map<String, ThemeTrieElement>? children,
  ]) : _rulesWithParentScopes = rulesWithParentScopes ?? [],
       _children = children ?? <String, ThemeTrieElement>{};

  final ThemeTrieElementRule _mainRule;
  final List<ThemeTrieElementRule> _rulesWithParentScopes;
  final Map<String, ThemeTrieElement> _children;

  static int _cmpBySpecificity(ThemeTrieElementRule a, ThemeTrieElementRule b) {
    // First, compare the scope depths of both rules. The “scope depth” of a rule is
    // the number of segments (delimited by dots) in the rule's deepest scope name
    // (i.e. the final scope name in the scope path delimited by spaces).
    if (a.scopeDepth != b.scopeDepth) {
      return b.scopeDepth - a.scopeDepth;
    }

    // Traverse the parent scopes depth-first, comparing the specificity of both
    // rules' parent scopes, which matches the behavior described by ”Ranking Matches”
    // in TextMate 1.5's manual: https://macromates.com/manual/en/scope_selectors
    // Start at index 0 for both rules, since the parent scopes were reversed
    // beforehand (i.e. index 0 is the deepest parent scope).
    var aParentIndex = 0;
    var bParentIndex = 0;

    while (true) {
      // Child combinators don't affect specificity.
      if (aParentIndex < a.parentScopes.length &&
          a.parentScopes[aParentIndex] == '>') {
        aParentIndex++;
      }
      if (bParentIndex < b.parentScopes.length &&
          b.parentScopes[bParentIndex] == '>') {
        bParentIndex++;
      }

      // This is a scope-by-scope comparison, so we need to stop once a rule runs
      // out of parent scopes.
      if (aParentIndex >= a.parentScopes.length ||
          bParentIndex >= b.parentScopes.length) {
        break;
      }

      // When sorting by scope name specificity, it's safe to treat a longer parent
      // scope as more specific. If both rules' parent scopes match a given scope
      // path, the longer parent scope will always be more specific.
      final parentScopeLengthDiff =
          b.parentScopes[bParentIndex].length -
          a.parentScopes[aParentIndex].length;

      if (parentScopeLengthDiff != 0) {
        return parentScopeLengthDiff;
      }

      aParentIndex++;
      bParentIndex++;
    }

    // If a depth-first, scope-by-scope comparison resulted in a tie, the rule with
    // more parent scopes is considered more specific.
    return b.parentScopes.length - a.parentScopes.length;
  }

  List<ThemeTrieElementRule> match(ScopeName scope) {
    if (scope != '') {
      final dotIndex = scope.indexOf('.');
      String head;
      String tail;
      if (dotIndex == -1) {
        head = scope;
        tail = '';
      } else {
        head = scope.substring(0, dotIndex);
        tail = scope.substring(dotIndex + 1);
      }

      final child = _children[head];
      if (child != null) {
        return child.match(tail);
      }
    }

    final rules = [..._rulesWithParentScopes, _mainRule];
    jsArraySort<ThemeTrieElementRule>(rules, _cmpBySpecificity);
    return rules;
  }

  void insert(
    int scopeDepth,
    ScopeName scope,
    List<ScopeName>? parentScopes,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    num fontSize,
    num lineHeight,
  ) {
    if (scope == '') {
      _doInsertHere(
        scopeDepth,
        parentScopes,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      );
      return;
    }

    final dotIndex = scope.indexOf('.');
    String head;
    String tail;
    if (dotIndex == -1) {
      head = scope;
      tail = '';
    } else {
      head = scope.substring(0, dotIndex);
      tail = scope.substring(dotIndex + 1);
    }

    var child = _children[head];
    if (child == null) {
      child = ThemeTrieElement(
        _mainRule.clone(),
        ThemeTrieElementRule.cloneArr(_rulesWithParentScopes),
      );
      _children[head] = child;
    }

    child.insert(
      scopeDepth + 1,
      tail,
      parentScopes,
      fontStyle,
      foreground,
      background,
      fontFamily,
      fontSize,
      lineHeight,
    );
  }

  void _doInsertHere(
    int scopeDepth,
    List<ScopeName>? parentScopes,
    int fontStyle,
    int foreground,
    int background,
    String fontFamily,
    num fontSize,
    num lineHeight,
  ) {
    if (parentScopes == null) {
      // Merge into the main rule
      _mainRule.acceptOverwrite(
        scopeDepth,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      );
      return;
    }

    // Try to merge into existing rule
    for (var i = 0, len = _rulesWithParentScopes.length; i < len; i++) {
      final rule = _rulesWithParentScopes[i];

      if (strArrCmp(rule.parentScopes, parentScopes) == 0) {
        // bingo! => we get to merge this into an existing one
        rule.acceptOverwrite(
          scopeDepth,
          fontStyle,
          foreground,
          background,
          fontFamily,
          fontSize,
          lineHeight,
        );
        return;
      }
    }

    // Must add a new rule

    // Inherit from main rule
    if (fontStyle == FontStyle.notSet) {
      fontStyle = _mainRule.fontStyle;
    }
    if (foreground == 0) {
      foreground = _mainRule.foreground;
    }
    if (background == 0) {
      background = _mainRule.background;
    }
    if (fontFamily == '') {
      fontFamily = _mainRule.fontFamily;
    }
    if (fontSize == 0) {
      fontSize = _mainRule.fontSize;
    }
    if (lineHeight == 0) {
      lineHeight = _mainRule.lineHeight;
    }

    _rulesWithParentScopes.add(
      ThemeTrieElementRule(
        scopeDepth,
        parentScopes,
        fontStyle,
        foreground,
        background,
        fontFamily,
        fontSize,
        lineHeight,
      ),
    );
  }
}
