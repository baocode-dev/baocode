// Adapted from vscode-textmate 9.3.2 (25b68dad91920b1ed79d357534b8c4582f62d80d):
// src/theme.ts, `IRawTheme` and `IRawThemeSetting` (MIT, see LICENSE.md).

/// A theme's token rules as vscode-textmate takes them.
///
/// The fields keep JSON's looseness, since `parseTheme` checks them as
/// upstream does: a scope is a string (comma-separated selectors), a list of
/// strings, or absent; a style value counts only when it is a string.
class IRawTheme {
  const IRawTheme({this.name, required this.settings});

  final String? name;
  final List<IRawThemeSetting> settings;
}

class IRawThemeSetting {
  const IRawThemeSetting({this.name, this.scope, required this.settings});

  final String? name;

  /// A `ScopePattern` (String), a `List` of them, or null.
  final Object? scope;
  final IRawThemeSettingStyle settings;
}

class IRawThemeSettingStyle {
  const IRawThemeSettingStyle({
    this.fontStyle,
    this.foreground,
    this.background,
  });

  final Object? fontStyle;
  final Object? foreground;
  final Object? background;
}
