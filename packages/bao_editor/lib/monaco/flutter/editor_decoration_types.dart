// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License. See lib/monaco/LICENSE.txt.
//
// VS Code's text editor decoration types, adapted from VS Code 1.135.0
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5):
// - src/vs/editor/browser/services/abstractCodeEditorService.ts:
//   `registerDecorationType`/`removeDecorationType`/`resolveDecorationOptions`
//   ([EditorDecorationTypeRegistry]), `DecorationTypeOptionsProvider`,
//   `DecorationSubTypeOptionsProvider` and `DecorationCSSRules`
//   ([resolveDecorationType]): which properties go to the `className` rule
//   (background, outline, border), the `inlineClassName` rule (font, text
//   decoration, color, opacity, letter spacing), the glyph margin rule
//   (gutter icon) and the `::before`/`::after` content rules; a theme kind's
//   `light`/`dark` value beats the plain one (its selector is more
//   specific); a `ThemeColor` is the theme's color or transparent; the
//   overview ruler takes `overviewRulerColor` in `overviewRulerLane`
//   (center by default).
// - src/vs/editor/browser/widget/codeEditor/codeEditorWidget.ts
//   `setDecorationsByType`/`removeDecorationsByType` and
//   src/vs/workbench/api/browser/mainThreadEditor.ts `setDecorations`/
//   `setDecorationsFast` ([EditorDecorationsController]).
//
// Deviations: CSS is not involved; the properties become [EditorDecoration]
// values, so only what the painters draw is kept: no `cursor`,
// `borderSpacing`, `verticalAlign`, `lineHeight` or `contentIconPath`; a
// `fontFamily`/`fontSize` on a range applies to the text but the row keeps
// its height; `border` shorthands with per-side widths take the first width.
// `before`/`after` content is laid out as injected text that the caret steps
// over (upstream it is a pseudo-element: the caret is measured around it in
// the DOM); `before` stops right of it and `after` left of it.

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../vs/base/common/color.dart' as vs;
import '../vs/editor/common/decoration_render_options.dart';
import 'editor_decorations.dart';
import 'editor_document_model.dart';
import 'editor_tracked_decorations.dart';

export '../vs/editor/common/decoration_render_options.dart';

/// The colors a decoration type resolves against: the theme kind (`light`
/// or `dark` options) and its colors by id (for `ThemeColor`s).
@immutable
class EditorDecorationTheme {
  const EditorDecorationTheme({
    required this.isDark,
    required this.colors,
    this.key,
  });

  final bool isDark;
  final Color? Function(String id) colors;

  /// Identifies the theme; themes with equal keys and kinds resolve alike.
  final Object? key;

  @override
  bool operator ==(Object other) =>
      other is EditorDecorationTheme &&
      other.isDark == isDark &&
      (key != null ? other.key == key : identical(other.colors, colors));

  @override
  int get hashCode => Object.hash(isDark, key ?? colors);
}

class _DecorationType {
  _DecorationType(this.description, this.options, this.parentTypeKey);

  final String description;
  final DecorationRenderOptions options;
  final String? parentTypeKey;
}

/// The application's decoration types (the code editor service's part that
/// `MainThreadTextEditors.$registerTextEditorDecorationType` and
/// `$removeTextEditorDecorationType` use). Listeners hear when types come
/// and go.
class EditorDecorationTypeRegistry extends ChangeNotifier {
  final Map<String, _DecorationType> _types = {};
  final Map<(String, EditorDecorationTheme), ResolvedDecorationType> _resolved =
      {};
  int _version = 0;

  /// Bumps when a type is registered or removed.
  int get version => _version;

  Iterable<String> get keys => _types.keys;

  bool contains(String key) => _types.containsKey(key);

  DecorationRenderOptions? optionsOf(String key) => _types[key]?.options;

  /// `registerDecorationType(description, key, options, parentTypeKey)`.
  void registerDecorationType(
    String key,
    DecorationRenderOptions options, {
    String description = '',
    String? parentTypeKey,
  }) {
    _types[key] = _DecorationType(description, options, parentTypeKey);
    _resolved.removeWhere((entry, _) => entry.$1 == key);
    _version++;
    notifyListeners();
  }

  /// `removeDecorationType(key)`: editors drop its decorations.
  void removeDecorationType(String key) {
    if (_types.remove(key) == null) return;
    _resolved.removeWhere((entry, _) => entry.$1 == key);
    _version++;
    notifyListeners();
  }

  /// The decoration [key] paints with in [theme], or null for an unknown
  /// type (`resolveDecorationOptions` throws there).
  ResolvedDecorationType? resolve(String key, EditorDecorationTheme theme) {
    final type = _types[key];
    if (type == null) return null;
    return _resolved[(key, theme)] ??= resolveDecorationType(
      type.options,
      theme,
    );
  }
}

/// What a decoration type paints: [decoration] (at no range), the
/// stickiness of its ranges, and its `before`/`after` content options for
/// instances to override.
@immutable
class ResolvedDecorationType {
  const ResolvedDecorationType({
    required this.decoration,
    required this.stickiness,
    this.before,
    this.after,
  });

  final EditorDecoration decoration;
  final TrackedRangeStickiness stickiness;
  final ContentDecorationRenderOptions? before;
  final ContentDecorationRenderOptions? after;
}

/// One theme kind's view of [options]: each property its `light`/`dark`
/// value, else its own.
class _Themed {
  _Themed(this.options, this.themed);

  final ThemeDecorationRenderOptions options;
  final ThemeDecorationRenderOptions? themed;

  T? pick<T>(T? Function(ThemeDecorationRenderOptions o) property) {
    final themed = this.themed;
    return (themed == null ? null : property(themed)) ?? property(options);
  }
}

/// `DecorationTypeOptionsProvider` with `DecorationCSSRules`, resolving
/// [options] for [theme].
ResolvedDecorationType resolveDecorationType(
  DecorationRenderOptions options,
  EditorDecorationTheme theme,
) {
  final o = _Themed(options, theme.isDark ? options.dark : options.light);
  Color? color(CssColorValue? value) => resolveCssColor(value, theme);

  // className: background, outline, border.
  final background = color(o.pick((o) => o.backgroundColor));
  final textColor = color(o.pick((o) => o.color));
  // CSS draws a border only with a style; its color defaults to the text's
  // (`currentColor`) and its width to `medium`.
  final currentColor = textColor ?? theme.colors('editor.foreground');
  final border = parseCssBorder(o.pick((o) => o.border));
  final borderStyle =
      parseCssBorderStyle(o.pick((o) => o.borderStyle)) ?? border?.style;
  final borderColor =
      borderStyle == null || borderStyle == EditorBorderStyle.none
      ? null
      : color(o.pick((o) => o.borderColor)) ?? border?.color ?? currentColor;
  final borderWidth =
      parseCssLength(o.pick((o) => o.borderWidth)) ?? border?.width;
  final borderRadius = parseCssLength(o.pick((o) => o.borderRadius));
  final outline = parseCssBorder(o.pick((o) => o.outline));
  final outlineStyle =
      parseCssBorderStyle(o.pick((o) => o.outlineStyle)) ?? outline?.style;
  final outlineColor =
      outlineStyle == null || outlineStyle == EditorBorderStyle.none
      ? null
      : color(o.pick((o) => o.outlineColor)) ?? outline?.color ?? currentColor;
  final outlineWidth =
      parseCssLength(o.pick((o) => o.outlineWidth)) ?? outline?.width;

  // inlineClassName: the text's style.
  final textStyle = cssTextStyle(
    color: textColor,
    fontStyle: o.pick((o) => o.fontStyle),
    fontWeight: o.pick((o) => o.fontWeight),
    fontFamily: o.pick((o) => o.fontFamily),
    fontSize: o.pick((o) => o.fontSize),
    textDecoration: o.pick((o) => o.textDecoration),
    letterSpacing: o.pick((o) => o.letterSpacing),
    theme: theme,
  );
  final opacity = parseCssOpacity(o.pick((o) => o.opacity));

  // Glyph margin.
  final gutterPath = o.pick((o) => o.gutterIconPath);
  final gutterIcon = gutterPath == null
      ? null
      : EditorGutterIcon(
          gutterPath.scheme == 'file'
              ? gutterPath.fsPath
              : gutterPath.toString(),
          size: o.pick((o) => o.gutterIconSize),
        );

  // Overview ruler: `light.overviewRulerColor || overviewRulerColor`.
  final ruler = color(o.pick((o) => o.overviewRulerColor));

  final before = _themedContent(options, theme, (o) => o.before);
  final after = _themedContent(options, theme, (o) => o.after);
  final rangeBehavior = options.rangeBehavior;
  return ResolvedDecorationType(
    decoration: EditorDecoration(
      start: 0,
      end: 0,
      backgroundColor: background,
      borderColor: borderColor,
      borderWidth: _px(borderWidth) ?? 3,
      borderStyle: borderStyle ?? EditorBorderStyle.solid,
      borderRadius: _px(borderRadius) ?? 0,
      outlineColor: outlineColor,
      outlineWidth: _px(outlineWidth) ?? 3,
      outlineStyle: outlineStyle ?? EditorBorderStyle.solid,
      textStyle: textStyle,
      opacity: opacity,
      isWholeLine: options.isWholeLine ?? false,
      gutterIcon: gutterIcon,
      overviewRulerColor: ruler,
      overviewRulerLane: ruler == null
          ? null
          : options.overviewRulerLane ?? OverviewRulerLane.center,
      before: before == null
          ? null
          : contentInjectedText(before, theme, isBefore: true),
      after: after == null
          ? null
          : contentInjectedText(after, theme, isBefore: false),
    ),
    stickiness:
        rangeBehavior != null &&
            rangeBehavior >= 0 &&
            rangeBehavior < TrackedRangeStickiness.values.length
        ? TrackedRangeStickiness.values[rangeBehavior]
        : TrackedRangeStickiness.alwaysGrowsWhenTypingAtEdges,
    before: before,
    after: after,
  );
}

/// The `before`/`after` content of [options] for [theme]: the themed
/// rule's properties over the plain one's.
ContentDecorationRenderOptions? _themedContent(
  ThemeDecorationRenderOptions options,
  EditorDecorationTheme theme,
  ContentDecorationRenderOptions? Function(ThemeDecorationRenderOptions)
  content,
) {
  final themedOptions = theme.isDark
      ? (options is DecorationRenderOptions ? options.dark : null)
      : (options is DecorationRenderOptions ? options.light : null);
  final plain = content(options);
  final themed = themedOptions == null ? null : content(themedOptions);
  if (plain == null) return themed;
  return plain.overriddenBy(themed);
}

double? _px(EditorCssLength? length) => length?.resolve(fontSize: 14);

/// A decoration of [type] over `[start, end)` with [instance]'s own
/// `before`/`after` (a `DecorationSubTypeOptionsProvider`, whose rules are
/// more specific than the type's) and [hoverMessage].
EditorDecoration decorationOfType(
  ResolvedDecorationType type,
  EditorDecorationTheme theme, {
  required int start,
  required int end,
  DecorationInstanceRenderOptions? instance,
  Object? hoverMessage,
}) {
  var decoration = type.decoration;
  if (instance != null) {
    ContentDecorationRenderOptions? merged(
      ContentDecorationRenderOptions? parent,
      ContentDecorationRenderOptions? Function(
        ThemeDecorationInstanceRenderOptions,
      )
      pick,
    ) {
      final themed = theme.isDark ? instance.dark : instance.light;
      var own = pick(instance);
      if (themed != null) {
        final themedOwn = pick(themed);
        own = own == null ? themedOwn : own.overriddenBy(themedOwn);
      }
      if (own == null) return parent;
      return parent == null ? own : parent.overriddenBy(own);
    }

    final before = merged(type.before, (o) => o.before);
    final after = merged(type.after, (o) => o.after);
    decoration = _withContent(
      decoration,
      before: before == null
          ? null
          : contentInjectedText(before, theme, isBefore: true),
      after: after == null
          ? null
          : contentInjectedText(after, theme, isBefore: false),
    );
  }
  if (hoverMessage != null) decoration = _withHover(decoration, hoverMessage);
  return decoration.withRange(start, end);
}

EditorDecoration _withContent(
  EditorDecoration d, {
  EditorInjectedText? before,
  EditorInjectedText? after,
}) => EditorDecoration(
  start: d.start,
  end: d.end,
  kind: d.kind,
  backgroundColor: d.backgroundColor,
  borderColor: d.borderColor,
  borderWidth: d.borderWidth,
  borderStyle: d.borderStyle,
  borderRadius: d.borderRadius,
  outlineColor: d.outlineColor,
  outlineWidth: d.outlineWidth,
  outlineStyle: d.outlineStyle,
  textStyle: d.textStyle,
  opacity: d.opacity,
  isWholeLine: d.isWholeLine,
  gutterIcon: d.gutterIcon,
  overviewRulerColor: d.overviewRulerColor,
  overviewRulerLane: d.overviewRulerLane,
  before: before,
  after: after,
  hoverMessage: d.hoverMessage,
);

EditorDecoration _withHover(EditorDecoration d, Object hoverMessage) =>
    EditorDecoration(
      start: d.start,
      end: d.end,
      kind: d.kind,
      backgroundColor: d.backgroundColor,
      borderColor: d.borderColor,
      borderWidth: d.borderWidth,
      borderStyle: d.borderStyle,
      borderRadius: d.borderRadius,
      outlineColor: d.outlineColor,
      outlineWidth: d.outlineWidth,
      outlineStyle: d.outlineStyle,
      textStyle: d.textStyle,
      opacity: d.opacity,
      isWholeLine: d.isWholeLine,
      gutterIcon: d.gutterIcon,
      overviewRulerColor: d.overviewRulerColor,
      overviewRulerLane: d.overviewRulerLane,
      before: d.before,
      after: d.after,
      hoverMessage: hoverMessage,
    );

/// `getCSSTextForModelDecorationContentClassName`: the content's text with
/// its style and box. Null without `contentText` (an icon only, which is not
/// drawn).
EditorInjectedText? contentInjectedText(
  ContentDecorationRenderOptions options,
  EditorDecorationTheme theme, {
  required bool isBefore,
}) {
  final text = options.contentText;
  if (text == null || text.isEmpty) return null;
  // Only the first line (`/^.*$/m`).
  final firstLine = text.split(RegExp(r'\r\n|\r|\n')).first;
  if (firstLine.isEmpty) return null;
  final border = parseCssBorder(options.border);
  final textColor = resolveCssColor(options.color, theme);
  // A border needs a style (from the shorthand); its color defaults to
  // the text's.
  final hasBorder =
      border?.style != null && border!.style != EditorBorderStyle.none;
  final borderColor = hasBorder
      ? resolveCssColor(options.borderColor, theme) ??
            border.color ??
            textColor ??
            theme.colors('editor.foreground')
      : null;
  return EditorInjectedText(
    // CSS `content` keeps spaces (the element is `white-space: pre`).
    firstLine,
    style: cssTextStyle(
      color: textColor,
      fontStyle: options.fontStyle,
      fontWeight: options.fontWeight,
      fontFamily: options.fontFamily,
      textDecoration: options.textDecoration,
      theme: theme,
    ),
    fontSize: parseCssLength(options.fontSize),
    opacity: parseCssOpacity(options.opacity) ?? 1,
    backgroundColor: resolveCssColor(options.backgroundColor, theme),
    margin: parseCssEdges(options.margin) ?? EditorCssEdges.zero,
    padding: parseCssEdges(options.padding) ?? EditorCssEdges.zero,
    width: parseCssLength(options.width),
    height: parseCssLength(options.height),
    borderColor: borderColor,
    borderWidth: hasBorder
        ? border.width ?? const EditorCssLength(3)
        : EditorCssLength.zero,
    borderStyle: border?.style ?? EditorBorderStyle.solid,
    borderRadius: parseCssLength(options.borderRadius) ?? EditorCssLength.zero,
    cursorStops: isBefore
        ? InjectedTextCursorStops.right
        : InjectedTextCursorStops.left,
  );
}

// ---- CSS values -------------------------------------------------------------

/// `resolveValue`: a theme color (transparent when the theme has none), or
/// a parsed CSS color.
Color? resolveCssColor(CssColorValue? value, EditorDecorationTheme theme) =>
    switch (value) {
      null => null,
      ThemeColorValue(:final id) => theme.colors(id) ?? const Color(0x00000000),
      CssColor(:final css) => parseCssColor(css),
    };

/// A CSS color: `#rgb[a]`, `#rrggbb[aa]`, `rgb()`, `rgba()`, `hsl[a]()`,
/// a named color or `transparent`; null when it is none of these.
Color? parseCssColor(String css) {
  final value = css.trim().toLowerCase();
  if (value.isEmpty) return null;
  final hsl = RegExp(
    r'^hsla?\(\s*([\d.+-]+)(?:deg)?\s*[, ]\s*([\d.]+)%\s*[, ]\s*([\d.]+)%\s*(?:[,/]\s*([\d.]+%?))?\s*\)$',
  ).firstMatch(value);
  if (hsl != null) {
    final alpha = hsl[4] == null ? 1.0 : _alpha(hsl[4]!);
    final rgba = vs.HSLA.toRGBA(
      vs.HSLA(
        double.parse(hsl[1]!) % 360,
        double.parse(hsl[2]!) / 100,
        double.parse(hsl[3]!) / 100,
        alpha,
      ),
    );
    return _fromRgba(rgba);
  }
  final rgb = RegExp(
    r'^rgba?\(\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*[, ]\s*([\d.]+%?)\s*(?:[,/]\s*([\d.]+%?))?\s*\)$',
  ).firstMatch(value);
  if (rgb != null) {
    int channel(String s) => s.endsWith('%')
        ? (double.parse(s.substring(0, s.length - 1)) * 2.55).round()
        : double.parse(s).round();
    return Color.fromARGB(
      (_alpha(rgb[4] ?? '1') * 255).round().clamp(0, 255),
      channel(rgb[1]!).clamp(0, 255),
      channel(rgb[2]!).clamp(0, 255),
      channel(rgb[3]!).clamp(0, 255),
    );
  }
  try {
    final parsed = vs.ColorFormatCSS.parse(value);
    return parsed == null ? null : _fromRgba(parsed.rgba);
  } on FormatException {
    return null;
  }
}

double _alpha(String s) => s.endsWith('%')
    ? double.parse(s.substring(0, s.length - 1)) / 100
    : double.parse(s);

Color _fromRgba(vs.RGBA rgba) =>
    Color.fromARGB((rgba.a * 255).round(), rgba.r, rgba.g, rgba.b);

final _lengthPattern = RegExp(r'^([+-]?(?:\d+\.?\d*|\.\d+))(px|em|rem|ch|%)?$');

/// A CSS length (`3px`, `1.5em`, `2ch`, `50%`, `0`); `thin`/`medium`/`thick`
/// for borders.
EditorCssLength? parseCssLength(String? css) {
  if (css == null) return null;
  final value = css.trim().toLowerCase();
  switch (value) {
    case 'thin':
      return const EditorCssLength(1);
    case 'medium':
      return const EditorCssLength(3);
    case 'thick':
      return const EditorCssLength(5);
  }
  final match = _lengthPattern.firstMatch(value);
  if (match == null) return null;
  final number = double.parse(match[1]!);
  return EditorCssLength(number, switch (match[2]) {
    'em' => EditorCssUnit.em,
    'rem' => EditorCssUnit.rem,
    'ch' => EditorCssUnit.ch,
    '%' => EditorCssUnit.percent,
    _ => EditorCssUnit.px,
  });
}

/// `margin`/`padding`: one to four lengths (top, right, bottom, left).
EditorCssEdges? parseCssEdges(String? css) {
  if (css == null) return null;
  final parts = css.trim().split(RegExp(r'\s+'));
  final lengths = [for (final part in parts) parseCssLength(part)];
  if (lengths.isEmpty || lengths.length > 4 || lengths.contains(null)) {
    return null;
  }
  final l = lengths.cast<EditorCssLength>();
  return switch (l.length) {
    1 => EditorCssEdges(top: l[0], right: l[0], bottom: l[0], left: l[0]),
    2 => EditorCssEdges(top: l[0], right: l[1], bottom: l[0], left: l[1]),
    3 => EditorCssEdges(top: l[0], right: l[1], bottom: l[2], left: l[1]),
    _ => EditorCssEdges(top: l[0], right: l[1], bottom: l[2], left: l[3]),
  };
}

EditorBorderStyle? parseCssBorderStyle(String? css) =>
    switch (css?.trim().toLowerCase()) {
      'solid' ||
      'groove' ||
      'ridge' ||
      'inset' ||
      'outset' => EditorBorderStyle.solid,
      'dashed' => EditorBorderStyle.dashed,
      'dotted' => EditorBorderStyle.dotted,
      'double' => EditorBorderStyle.double,
      'none' || 'hidden' => EditorBorderStyle.none,
      _ => null,
    };

/// Space-separated CSS tokens, keeping `rgba(1, 2, 3)` whole.
List<String> _cssTokens(String css) {
  final tokens = <String>[];
  final current = StringBuffer();
  var depth = 0;
  for (final char in css.trim().split('')) {
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (depth == 0 && (char == ' ' || char == '\t')) {
      if (current.isNotEmpty) tokens.add(current.toString());
      current.clear();
    } else {
      current.write(char);
    }
  }
  if (current.isNotEmpty) tokens.add(current.toString());
  return tokens;
}

/// A `border`/`outline` shorthand: `1px solid red`, in any order.
({EditorCssLength? width, EditorBorderStyle? style, Color? color})?
parseCssBorder(String? css) {
  if (css == null) return null;
  EditorCssLength? width;
  EditorBorderStyle? style;
  Color? color;
  for (final token in _cssTokens(css)) {
    final asStyle = parseCssBorderStyle(token);
    if (asStyle != null) {
      style = asStyle;
      continue;
    }
    final asLength = parseCssLength(token);
    if (asLength != null) {
      width ??= asLength;
      continue;
    }
    color ??= parseCssColor(token);
  }
  if (width == null && style == null && color == null) return null;
  return (
    width:
        width ??
        (style == EditorBorderStyle.none ? null : const EditorCssLength(3)),
    style: style,
    color: color,
  );
}

FontWeight? parseCssFontWeight(String? css) {
  final value = css?.trim().toLowerCase();
  switch (value) {
    case null:
      return null;
    case 'normal':
      return FontWeight.w400;
    case 'bold':
    case 'bolder':
      return FontWeight.w700;
    case 'lighter':
      return FontWeight.w300;
  }
  final number = int.tryParse(value);
  if (number == null) return null;
  return FontWeight.values[((number.clamp(100, 900) / 100).round() - 1)];
}

FontStyle? parseCssFontStyle(String? css) =>
    switch (css?.trim().toLowerCase()) {
      'italic' || 'oblique' => FontStyle.italic,
      'normal' => FontStyle.normal,
      _ => null,
    };

/// `opacity`: a number or a percentage.
double? parseCssOpacity(String? css) {
  final value = css?.trim();
  if (value == null || value.isEmpty) return null;
  final parsed = value.endsWith('%')
      ? double.tryParse(value.substring(0, value.length - 1))
            .let((v) => v / 100)
      : double.tryParse(value);
  return parsed?.clamp(0.0, 1.0);
}

extension on double? {
  double? let(double Function(double) f) => this == null ? null : f(this!);
}

/// `text-decoration`: lines (`underline`, `overline`, `line-through`),
/// style (`solid`, `double`, `dotted`, `dashed`, `wavy`), color and
/// thickness, in any order; `none` clears.
({
  TextDecoration decoration,
  TextDecorationStyle? style,
  Color? color,
  double? thickness,
})?
parseCssTextDecoration(String? css, EditorDecorationTheme? theme) {
  if (css == null) return null;
  final lines = <TextDecoration>[];
  TextDecorationStyle? style;
  Color? color;
  double? thickness;
  for (final token in _cssTokens(css.toLowerCase())) {
    switch (token) {
      case 'none':
        lines.clear();
        lines.add(TextDecoration.none);
      case 'underline':
        lines.add(TextDecoration.underline);
      case 'overline':
        lines.add(TextDecoration.overline);
      case 'line-through':
        lines.add(TextDecoration.lineThrough);
      case 'solid':
        style = TextDecorationStyle.solid;
      case 'double':
        style = TextDecorationStyle.double;
      case 'dotted':
        style = TextDecorationStyle.dotted;
      case 'dashed':
        style = TextDecorationStyle.dashed;
      case 'wavy':
        style = TextDecorationStyle.wavy;
      default:
        final length = parseCssLength(token);
        if (length != null) {
          thickness = length.resolve(fontSize: 14);
        } else {
          color ??= parseCssColor(token);
        }
    }
  }
  if (lines.isEmpty) return null;
  return (
    decoration: TextDecoration.combine(lines),
    style: style,
    color: color,
    thickness: thickness,
  );
}

/// The `inlineClassName` style: color, font, text decoration and letter
/// spacing. Null when none is set.
TextStyle? cssTextStyle({
  Color? color,
  String? fontStyle,
  String? fontWeight,
  String? fontFamily,
  String? fontSize,
  String? textDecoration,
  String? letterSpacing,
  EditorDecorationTheme? theme,
}) {
  final decoration = parseCssTextDecoration(textDecoration, theme);
  final family = fontFamily
      ?.split(',')
      .first
      .trim()
      .replaceAll(RegExp(r'''^["']|["']$'''), '');
  final size = parseCssLength(fontSize);
  final spacing = parseCssLength(letterSpacing);
  final style = TextStyle(
    color: color,
    fontStyle: parseCssFontStyle(fontStyle),
    fontWeight: parseCssFontWeight(fontWeight),
    fontFamily: family == null || family.isEmpty ? null : family,
    fontSize: size == null || size.unit != EditorCssUnit.px ? null : size.value,
    decoration: decoration?.decoration,
    decorationStyle: decoration?.style,
    decorationColor: decoration?.color,
    decorationThickness: decoration?.thickness,
    letterSpacing: spacing?.resolve(fontSize: 14),
  );
  return style == const TextStyle() ? null : style;
}

// ---- Per editor ------------------------------------------------------------

class _TypeKey {
  const _TypeKey(this.key);

  final String key;

  @override
  bool operator ==(Object other) => other is _TypeKey && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// One editor's decorations by type: `setDecorationsByType` and
/// `removeDecorationsByType` of the code editor widget, which
/// `MainThreadTextEditor.setDecorations`/`setDecorationsFast` call. Its
/// [decorations] follow edits with each type's `rangeBehavior`, and follow
/// [theme] and [types] (a removed type's decorations go).
class EditorDecorationsController extends ChangeNotifier
    implements EditorDecorationProvider {
  EditorDecorationsController({
    required this.document,
    required this.types,
    required EditorDecorationTheme theme,
  }) : tracked = EditorTrackedDecorations(document),
       // ignore: prefer_initializing_formals
       _theme = theme {
    tracked.addListener(notifyListeners);
    types.addListener(_typesChanged);
  }

  final EditorDocumentModel document;
  final EditorDecorationTypeRegistry types;

  /// The decorations, tracked through edits; give `tracked.decorations` to
  /// the surface (or the controller itself as a provider).
  final EditorTrackedDecorations tracked;
  EditorDecorationTheme _theme;
  int _typesVersion = -1;

  EditorDecorationTheme get theme => _theme;

  @override
  EditorDecorationSet get decorations => tracked.decorations;

  @override
  bool get affectsLayout => tracked.affectsLayout;

  set theme(EditorDecorationTheme value) {
    if (value == _theme) return;
    _theme = value;
    _restyleAll();
  }

  /// The type keys with decorations here.
  Iterable<String> get typeKeys =>
      tracked.owners.whereType<_TypeKey>().map((owner) => owner.key);

  /// `setDecorationsByType(description, key, ranges)`: replaces [key]'s
  /// decorations. Unknown types are ignored, as upstream throws.
  void setDecorations(String key, List<DecorationOptions> decorations) {
    final type = types.resolve(key, _theme);
    if (type == null) {
      tracked.clear(_TypeKey(key));
      return;
    }
    final snapshot = document.snapshot;
    tracked.set(_TypeKey(key), [
      for (final options in decorations)
        () {
          final range = options.range;
          final start = snapshot.offsetAtPosition(range.getStartPosition());
          final end = snapshot.offsetAtPosition(range.getEndPosition());
          return EditorTrackedDecoration(
            start: start,
            end: end < start ? start : end,
            decoration: decorationOfType(
              type,
              _theme,
              start: start,
              end: end < start ? start : end,
              instance: options.renderOptions,
              hoverMessage: options.hoverMessage,
            ),
            stickiness: type.stickiness,
            data: options,
          );
        }(),
    ]);
  }

  /// `setDecorationsFast(key, ranges)`: four numbers per range.
  void setDecorationsFast(String key, List<num> ranges) =>
      setDecorations(key, DecorationOptions.fromFastJson(ranges));

  /// `removeDecorationsByType(key)`.
  void removeDecorationsByType(String key) => tracked.clear(_TypeKey(key));

  void _typesChanged() {
    if (_typesVersion == types.version) return;
    _typesVersion = types.version;
    for (final key in typeKeys.toList()) {
      if (!types.contains(key)) tracked.clear(_TypeKey(key));
    }
    _restyleAll();
  }

  void _restyleAll() {
    for (final owner in tracked.owners.whereType<_TypeKey>().toList()) {
      final type = types.resolve(owner.key, _theme);
      if (type == null) continue;
      tracked.restyle(owner, (decoration, data) {
        final options = data is DecorationOptions ? data : null;
        return decorationOfType(
          type,
          _theme,
          start: decoration.start,
          end: decoration.end,
          instance: options?.renderOptions,
          hoverMessage: options?.hoverMessage,
        );
      });
    }
  }

  @override
  void dispose() {
    types.removeListener(_typesChanged);
    tracked.removeListener(notifyListeners);
    tracked.dispose();
    super.dispose();
  }
}
