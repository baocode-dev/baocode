/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/platform/theme/common/theme.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971. The string enums become Dart
// enums whose `value` is upstream's string.

/// Color scheme used by the OS and by color themes.
enum ColorScheme {
  dark('dark'),
  light('light'),
  highContrastDark('hcDark'),
  highContrastLight('hcLight');

  const ColorScheme(this.value);

  final String value;
}

enum ThemeTypeSelector {
  vs('vs'),
  vsDark('vs-dark'),
  hcBlack('hc-black'),
  hcLight('hc-light');

  const ThemeTypeSelector(this.value);

  final String value;

  static ThemeTypeSelector? fromValue(String value) {
    for (final selector in values) {
      if (selector.value == value) return selector;
    }
    return null;
  }
}

bool isHighContrast(ColorScheme scheme) =>
    scheme == ColorScheme.highContrastDark ||
    scheme == ColorScheme.highContrastLight;

bool isDark(ColorScheme scheme) =>
    scheme == ColorScheme.dark || scheme == ColorScheme.highContrastDark;
