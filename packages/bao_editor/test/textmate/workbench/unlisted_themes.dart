// VS Code's themes the fixtures recorded that the manifest no longer lists.

import 'package:bao_editor/textmate/textmate_manifest.dart';

/// Not listed but still bundled: the Bao themes include them, Dark 2026
/// including Dark (Visual Studio) in turn. As their manifest entries were.
const unlistedThemes = [
  TextMateThemeContribution(
    extension: 'theme-defaults',
    id: 'Light 2026',
    label: 'Light 2026',
    path: 'themes/2026-light.json',
    assetPath: 'themes/theme-defaults/themes/2026-light.json',
    uiTheme: 'vs',
  ),
  TextMateThemeContribution(
    extension: 'theme-defaults',
    id: 'Dark 2026',
    label: 'Dark 2026',
    path: 'themes/2026-dark.json',
    assetPath: 'themes/theme-defaults/themes/2026-dark.json',
    uiTheme: 'vs-dark',
  ),
  TextMateThemeContribution(
    extension: 'theme-defaults',
    id: 'Visual Studio Dark',
    label: 'Dark (Visual Studio)',
    path: 'themes/dark_vs.json',
    assetPath: 'themes/theme-defaults/themes/dark_vs.json',
    uiTheme: 'vs-dark',
  ),
];

/// No longer bundled at all: nothing to check against the fixtures.
const removedThemes = {'Monokai', 'Abyss', 'Quiet Light'};

/// The theme [id], listed or not; null when it is gone.
TextMateThemeContribution? recordedTheme(TextMateManifest manifest, String id) {
  for (final theme in unlistedThemes) {
    if (theme.id == id) return theme;
  }
  return manifest.themeById(id);
}
