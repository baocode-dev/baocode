/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Port of the decoration render option types of VS Code 1.135.0
// (08d4889f9ec4a1685d257b9b95de036c8e1ce1e5)
// src/vs/editor/common/editorCommon.ts: `IThemeDecorationRenderOptions`,
// `IContentDecorationRenderOptions`, `IDecorationRenderOptions`,
// `IThemeDecorationInstanceRenderOptions`, `IDecorationInstanceRenderOptions`
// and `IDecorationOptions`, with `fromJson` reading exactly the JSON the
// extension host sends to `MainThreadTextEditorsShape`
// (`$registerTextEditorDecorationType`, `$trySetDecorations`), which
// src/vs/workbench/api/common/extHostTypeConverters.ts
// (`DecorationRenderOptions.from`, `ThemableDecorationRenderOptions.from`,
// `ThemableDecorationAttachmentRenderOptions.from`) builds: CSS strings,
// `ThemeColor`s as `{id}`, URIs as `UriComponents`.
//
// Deviations: values stay as the strings upstream puts in CSS; Dart types
// are classes with nullable fields instead of optional properties. A field
// of the wrong JSON type reads as absent.

import '../../base/common/uri.dart';
import 'core/range.dart';

/// `string | ThemeColor`: a CSS color, or a color of the theme by id.
sealed class CssColorValue {
  const CssColorValue();

  /// A JSON string, or a `ThemeColor` object `{id}`; null otherwise.
  static CssColorValue? fromJson(Object? json) => switch (json) {
    final String css => CssColor(css),
    {'id': final String id} => ThemeColorValue(id),
    _ => null,
  };

  Object toJson();
}

/// A CSS color string, as written (`'rgba(255,0,0,0.3)'`, `'#f00'`, `'red'`).
final class CssColor extends CssColorValue {
  const CssColor(this.css);

  final String css;

  @override
  Object toJson() => css;

  @override
  bool operator ==(Object other) => other is CssColor && other.css == css;

  @override
  int get hashCode => css.hashCode;

  @override
  String toString() => css;
}

/// vscode.ThemeColor: a color of the theme (`editorError.foreground`).
final class ThemeColorValue extends CssColorValue {
  const ThemeColorValue(this.id);

  final String id;

  @override
  Object toJson() => {'id': id};

  @override
  bool operator ==(Object other) => other is ThemeColorValue && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ThemeColor($id)';
}

String? _string(Object? json) => json is String ? json : null;
bool? _bool(Object? json) => json is bool ? json : null;
int? _int(Object? json) => json is num ? json.toInt() : null;

/// `UriComponents` (`{scheme, authority, path, query, fragment}`, as sent
/// with `$mid`), or a URI string.
URI? uriFromJson(Object? json) => switch (json) {
  final String value => URI.parse(value),
  {'scheme': final String scheme} => URI.from(
    scheme: scheme,
    authority: _string(json['authority']),
    path: _string(json['path']),
    query: _string(json['query']),
    fragment: _string(json['fragment']),
  ),
  _ => null,
};

Map<String, Object?> _uriToJson(URI uri) => {
  'scheme': uri.scheme,
  'authority': uri.authority,
  'path': uri.path,
  'query': uri.query,
  'fragment': uri.fragment,
};

/// `IContentDecorationRenderOptions`: a `before`/`after` attachment.
class ContentDecorationRenderOptions {
  const ContentDecorationRenderOptions({
    this.contentText,
    this.contentIconPath,
    this.border,
    this.borderColor,
    this.borderRadius,
    this.fontStyle,
    this.fontWeight,
    this.fontSize,
    this.fontFamily,
    this.textDecoration,
    this.color,
    this.backgroundColor,
    this.opacity,
    this.verticalAlign,
    this.margin,
    this.padding,
    this.width,
    this.height,
    this.affectsLetterSpacing,
  });

  static ContentDecorationRenderOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    return ContentDecorationRenderOptions(
      contentText: _string(json['contentText']),
      contentIconPath: uriFromJson(json['contentIconPath']),
      border: _string(json['border']),
      borderColor: CssColorValue.fromJson(json['borderColor']),
      borderRadius: _string(json['borderRadius']),
      fontStyle: _string(json['fontStyle']),
      fontWeight: _string(json['fontWeight']),
      fontSize: _string(json['fontSize']),
      fontFamily: _string(json['fontFamily']),
      textDecoration: _string(json['textDecoration']),
      color: CssColorValue.fromJson(json['color']),
      backgroundColor: CssColorValue.fromJson(json['backgroundColor']),
      opacity: _string(json['opacity']),
      verticalAlign: _string(json['verticalAlign']),
      margin: _string(json['margin']),
      padding: _string(json['padding']),
      width: _string(json['width']),
      height: _string(json['height']),
      affectsLetterSpacing: _bool(json['affectsLetterSpacing']),
    );
  }

  final String? contentText;
  final URI? contentIconPath;
  final String? border;
  final CssColorValue? borderColor;
  final String? borderRadius;
  final String? fontStyle;
  final String? fontWeight;
  final String? fontSize;
  final String? fontFamily;
  final String? textDecoration;
  final CssColorValue? color;
  final CssColorValue? backgroundColor;
  final String? opacity;
  final String? verticalAlign;
  final String? margin;
  final String? padding;
  final String? width;
  final String? height;

  /// `beforeInjectedText`/`afterInjectedText` only.
  final bool? affectsLetterSpacing;

  /// These options with [other]'s set properties over them (a more
  /// specific CSS rule for the same element).
  ContentDecorationRenderOptions overriddenBy(
    ContentDecorationRenderOptions? other,
  ) {
    if (other == null) return this;
    return ContentDecorationRenderOptions(
      contentText: other.contentText ?? contentText,
      contentIconPath: other.contentIconPath ?? contentIconPath,
      border: other.border ?? border,
      borderColor: other.borderColor ?? borderColor,
      borderRadius: other.borderRadius ?? borderRadius,
      fontStyle: other.fontStyle ?? fontStyle,
      fontWeight: other.fontWeight ?? fontWeight,
      fontSize: other.fontSize ?? fontSize,
      fontFamily: other.fontFamily ?? fontFamily,
      textDecoration: other.textDecoration ?? textDecoration,
      color: other.color ?? color,
      backgroundColor: other.backgroundColor ?? backgroundColor,
      opacity: other.opacity ?? opacity,
      verticalAlign: other.verticalAlign ?? verticalAlign,
      margin: other.margin ?? margin,
      padding: other.padding ?? padding,
      width: other.width ?? width,
      height: other.height ?? height,
      affectsLetterSpacing: other.affectsLetterSpacing ?? affectsLetterSpacing,
    );
  }

  Map<String, Object?> toJson() => {
    'contentText': ?contentText,
    if (contentIconPath case final uri?) 'contentIconPath': _uriToJson(uri),
    'border': ?border,
    'borderColor': ?borderColor?.toJson(),
    'borderRadius': ?borderRadius,
    'fontStyle': ?fontStyle,
    'fontWeight': ?fontWeight,
    'fontSize': ?fontSize,
    'fontFamily': ?fontFamily,
    'textDecoration': ?textDecoration,
    'color': ?color?.toJson(),
    'backgroundColor': ?backgroundColor?.toJson(),
    'opacity': ?opacity,
    'verticalAlign': ?verticalAlign,
    'margin': ?margin,
    'padding': ?padding,
    'width': ?width,
    'height': ?height,
    'affectsLetterSpacing': ?affectsLetterSpacing,
  };
}

/// `IThemeDecorationRenderOptions`: the options a theme kind can override.
class ThemeDecorationRenderOptions {
  const ThemeDecorationRenderOptions({
    this.backgroundColor,
    this.outline,
    this.outlineColor,
    this.outlineStyle,
    this.outlineWidth,
    this.border,
    this.borderColor,
    this.borderRadius,
    this.borderSpacing,
    this.borderStyle,
    this.borderWidth,
    this.fontStyle,
    this.fontWeight,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
    this.textDecoration,
    this.cursor,
    this.color,
    this.opacity,
    this.letterSpacing,
    this.gutterIconPath,
    this.gutterIconSize,
    this.overviewRulerColor,
    this.before,
    this.after,
    this.beforeInjectedText,
    this.afterInjectedText,
  });

  static ThemeDecorationRenderOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    return ThemeDecorationRenderOptions(
      backgroundColor: CssColorValue.fromJson(json['backgroundColor']),
      outline: _string(json['outline']),
      outlineColor: CssColorValue.fromJson(json['outlineColor']),
      outlineStyle: _string(json['outlineStyle']),
      outlineWidth: _string(json['outlineWidth']),
      border: _string(json['border']),
      borderColor: CssColorValue.fromJson(json['borderColor']),
      borderRadius: _string(json['borderRadius']),
      borderSpacing: _string(json['borderSpacing']),
      borderStyle: _string(json['borderStyle']),
      borderWidth: _string(json['borderWidth']),
      fontStyle: _string(json['fontStyle']),
      fontWeight: _string(json['fontWeight']),
      fontFamily: _string(json['fontFamily']),
      fontSize: _string(json['fontSize']),
      lineHeight: json['lineHeight'] is num
          ? (json['lineHeight'] as num).toDouble()
          : null,
      textDecoration: _string(json['textDecoration']),
      cursor: _string(json['cursor']),
      color: CssColorValue.fromJson(json['color']),
      opacity: _string(json['opacity']),
      letterSpacing: _string(json['letterSpacing']),
      gutterIconPath: uriFromJson(json['gutterIconPath']),
      gutterIconSize: _string(json['gutterIconSize']),
      overviewRulerColor: CssColorValue.fromJson(json['overviewRulerColor']),
      before: ContentDecorationRenderOptions.fromJson(json['before']),
      after: ContentDecorationRenderOptions.fromJson(json['after']),
      beforeInjectedText: ContentDecorationRenderOptions.fromJson(
        json['beforeInjectedText'],
      ),
      afterInjectedText: ContentDecorationRenderOptions.fromJson(
        json['afterInjectedText'],
      ),
    );
  }

  final CssColorValue? backgroundColor;
  final String? outline;
  final CssColorValue? outlineColor;
  final String? outlineStyle;
  final String? outlineWidth;
  final String? border;
  final CssColorValue? borderColor;
  final String? borderRadius;
  final String? borderSpacing;
  final String? borderStyle;
  final String? borderWidth;
  final String? fontStyle;
  final String? fontWeight;
  final String? fontFamily;
  final String? fontSize;
  final double? lineHeight;
  final String? textDecoration;
  final String? cursor;
  final CssColorValue? color;
  final String? opacity;
  final String? letterSpacing;
  final URI? gutterIconPath;
  final String? gutterIconSize;
  final CssColorValue? overviewRulerColor;
  final ContentDecorationRenderOptions? before;
  final ContentDecorationRenderOptions? after;
  final ContentDecorationRenderOptions? beforeInjectedText;
  final ContentDecorationRenderOptions? afterInjectedText;

  Map<String, Object?> toJson() => {
    'backgroundColor': ?backgroundColor?.toJson(),
    'outline': ?outline,
    'outlineColor': ?outlineColor?.toJson(),
    'outlineStyle': ?outlineStyle,
    'outlineWidth': ?outlineWidth,
    'border': ?border,
    'borderColor': ?borderColor?.toJson(),
    'borderRadius': ?borderRadius,
    'borderSpacing': ?borderSpacing,
    'borderStyle': ?borderStyle,
    'borderWidth': ?borderWidth,
    'fontStyle': ?fontStyle,
    'fontWeight': ?fontWeight,
    'fontFamily': ?fontFamily,
    'fontSize': ?fontSize,
    'lineHeight': ?lineHeight,
    'textDecoration': ?textDecoration,
    'cursor': ?cursor,
    'color': ?color?.toJson(),
    'opacity': ?opacity,
    'letterSpacing': ?letterSpacing,
    if (gutterIconPath case final uri?) 'gutterIconPath': _uriToJson(uri),
    'gutterIconSize': ?gutterIconSize,
    'overviewRulerColor': ?overviewRulerColor?.toJson(),
    'before': ?before?.toJson(),
    'after': ?after?.toJson(),
    'beforeInjectedText': ?beforeInjectedText?.toJson(),
    'afterInjectedText': ?afterInjectedText?.toJson(),
  };
}

/// `IDecorationRenderOptions`: what `registerTextEditorDecorationType`
/// registers.
class DecorationRenderOptions extends ThemeDecorationRenderOptions {
  const DecorationRenderOptions({
    super.backgroundColor,
    super.outline,
    super.outlineColor,
    super.outlineStyle,
    super.outlineWidth,
    super.border,
    super.borderColor,
    super.borderRadius,
    super.borderSpacing,
    super.borderStyle,
    super.borderWidth,
    super.fontStyle,
    super.fontWeight,
    super.fontFamily,
    super.fontSize,
    super.lineHeight,
    super.textDecoration,
    super.cursor,
    super.color,
    super.opacity,
    super.letterSpacing,
    super.gutterIconPath,
    super.gutterIconSize,
    super.overviewRulerColor,
    super.before,
    super.after,
    super.beforeInjectedText,
    super.afterInjectedText,
    this.isWholeLine,
    this.rangeBehavior,
    this.overviewRulerLane,
    this.light,
    this.dark,
  });

  static DecorationRenderOptions fromJson(Object? json) {
    final map = json is Map ? json : const <String, Object?>{};
    final theme = ThemeDecorationRenderOptions.fromJson(map)!;
    return DecorationRenderOptions(
      backgroundColor: theme.backgroundColor,
      outline: theme.outline,
      outlineColor: theme.outlineColor,
      outlineStyle: theme.outlineStyle,
      outlineWidth: theme.outlineWidth,
      border: theme.border,
      borderColor: theme.borderColor,
      borderRadius: theme.borderRadius,
      borderSpacing: theme.borderSpacing,
      borderStyle: theme.borderStyle,
      borderWidth: theme.borderWidth,
      fontStyle: theme.fontStyle,
      fontWeight: theme.fontWeight,
      fontFamily: theme.fontFamily,
      fontSize: theme.fontSize,
      lineHeight: theme.lineHeight,
      textDecoration: theme.textDecoration,
      cursor: theme.cursor,
      color: theme.color,
      opacity: theme.opacity,
      letterSpacing: theme.letterSpacing,
      gutterIconPath: theme.gutterIconPath,
      gutterIconSize: theme.gutterIconSize,
      overviewRulerColor: theme.overviewRulerColor,
      before: theme.before,
      after: theme.after,
      beforeInjectedText: theme.beforeInjectedText,
      afterInjectedText: theme.afterInjectedText,
      isWholeLine: _bool(map['isWholeLine']),
      rangeBehavior: _int(map['rangeBehavior']),
      overviewRulerLane: _int(map['overviewRulerLane']),
      light: ThemeDecorationRenderOptions.fromJson(map['light']),
      dark: ThemeDecorationRenderOptions.fromJson(map['dark']),
    );
  }

  final bool? isWholeLine;

  /// `TrackedRangeStickiness` (0 AlwaysGrows … 3 GrowsOnlyWhenTypingAfter).
  final int? rangeBehavior;

  /// `OverviewRulerLane` (1 left, 2 center, 4 right, 7 full).
  final int? overviewRulerLane;
  final ThemeDecorationRenderOptions? light;
  final ThemeDecorationRenderOptions? dark;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'isWholeLine': ?isWholeLine,
    'rangeBehavior': ?rangeBehavior,
    'overviewRulerLane': ?overviewRulerLane,
    'light': ?light?.toJson(),
    'dark': ?dark?.toJson(),
  };
}

/// `IThemeDecorationInstanceRenderOptions`.
class ThemeDecorationInstanceRenderOptions {
  const ThemeDecorationInstanceRenderOptions({this.before, this.after});

  static ThemeDecorationInstanceRenderOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    return ThemeDecorationInstanceRenderOptions(
      before: ContentDecorationRenderOptions.fromJson(json['before']),
      after: ContentDecorationRenderOptions.fromJson(json['after']),
    );
  }

  final ContentDecorationRenderOptions? before;
  final ContentDecorationRenderOptions? after;

  Map<String, Object?> toJson() => {
    'before': ?before?.toJson(),
    'after': ?after?.toJson(),
  };
}

/// `IDecorationInstanceRenderOptions`: one decoration's own `before`/`after`.
class DecorationInstanceRenderOptions
    extends ThemeDecorationInstanceRenderOptions {
  const DecorationInstanceRenderOptions({
    super.before,
    super.after,
    this.light,
    this.dark,
  });

  static DecorationInstanceRenderOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    return DecorationInstanceRenderOptions(
      before: ContentDecorationRenderOptions.fromJson(json['before']),
      after: ContentDecorationRenderOptions.fromJson(json['after']),
      light: ThemeDecorationInstanceRenderOptions.fromJson(json['light']),
      dark: ThemeDecorationInstanceRenderOptions.fromJson(json['dark']),
    );
  }

  final ThemeDecorationInstanceRenderOptions? light;
  final ThemeDecorationInstanceRenderOptions? dark;

  @override
  Map<String, Object?> toJson() => {
    ...super.toJson(),
    'light': ?light?.toJson(),
    'dark': ?dark?.toJson(),
  };
}

/// `IDecorationOptions`: one decoration of a type, as `$trySetDecorations`
/// sends it. [hoverMessage] stays JSON (`IMarkdownString` or a list).
class DecorationOptions {
  const DecorationOptions({
    required this.range,
    this.hoverMessage,
    this.renderOptions,
  });

  static DecorationOptions? fromJson(Object? json) {
    if (json is! Map) return null;
    final range = json['range'];
    if (range is! Map) return null;
    final startLine = _int(range['startLineNumber']);
    final startColumn = _int(range['startColumn']);
    final endLine = _int(range['endLineNumber']);
    final endColumn = _int(range['endColumn']);
    if (startLine == null ||
        startColumn == null ||
        endLine == null ||
        endColumn == null) {
      return null;
    }
    return DecorationOptions(
      range: Range(startLine, startColumn, endLine, endColumn),
      hoverMessage: json['hoverMessage'],
      renderOptions: DecorationInstanceRenderOptions.fromJson(
        json['renderOptions'],
      ),
    );
  }

  /// The ranges `$trySetDecorationsFast` sends: four numbers each
  /// (start line, start column, end line, end column).
  static List<DecorationOptions> fromFastJson(List<num> ranges) => [
    for (var i = 0; i + 3 < ranges.length; i += 4)
      DecorationOptions(
        range: Range(
          ranges[i].toInt(),
          ranges[i + 1].toInt(),
          ranges[i + 2].toInt(),
          ranges[i + 3].toInt(),
        ),
      ),
  ];

  final Range range;
  final Object? hoverMessage;
  final DecorationInstanceRenderOptions? renderOptions;
}
