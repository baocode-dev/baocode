/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/workbench/services/themes/common/
// workbenchThemeService.ts at 6a598d4a13031703d483d103c1d934a36ad27971: the
// types a color theme's TextMate rules and its contribution use
// (`ITextMateThemingRule`, `ITokenColorizationSetting`,
// `IThemeExtensionPoint`). The theme service itself is not ported.
// Deviation: the rule fields keep JSON's looseness (`Object?`), because
// `ColorThemeData.tokenColors` passes theme values through unchecked.

class ITextMateThemingRule {
  const ITextMateThemingRule({this.name, this.scope, required this.settings});

  final String? name;

  /// A string (comma-separated selectors), a list of them, or null; other
  /// JSON values pass through as upstream lets them.
  final Object? scope;
  final ITokenColorizationSetting settings;
}

class ITokenColorizationSetting {
  const ITokenColorizationSetting({
    this.foreground,
    this.background,
    this.fontStyle,
    this.fontFamily,
    this.fontSize,
    this.lineHeight,
  });

  final String? foreground;
  final String? background;

  /// `[italic|bold|underline|strikethrough]`, as the theme wrote it.
  final Object? fontStyle;
  final Object? fontFamily;
  final Object? fontSize;
  final Object? lineHeight;
}

/// A `contributes.themes` entry of an extension's package.json.
class IThemeExtensionPoint {
  const IThemeExtensionPoint({
    required this.id,
    this.label,
    this.description,
    required this.path,
    this.uiTheme,
  });

  final String id;
  final String? label;
  final String? description;
  final String path;

  /// A `ThemeTypeSelector` value: `vs`, `vs-dark`, `hc-black` or `hc-light`.
  final String? uiTheme;
}
