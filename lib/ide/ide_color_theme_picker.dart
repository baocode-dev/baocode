/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// VS Code's Preferences: Color Theme picker (`workbench.action.selectTheme`,
// ⌘K ⌘T / Ctrl+K Ctrl+T).
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/themes/browser/themes.contribution.ts (the
// action, `InstalledThemesPicker.openQuickPick` with its `selectTheme`
// delay, `toEntry`, `toEntries`, `defaultThemeDescriptions`) and
// `ThemeSettingDefaults` from
// src/vs/workbench/services/themes/common/workbenchThemeService.ts.
//
// Deviations:
// - No marketplace: neither "Browse Additional Color Themes..." nor
//   "Install Additional Color Themes..." is listed, themes have no "Manage
//   Extension" button, and Enter with no active item (a filter matching
//   nothing) only closes the picker, where upstream opens the Extensions
//   view's `category:themes` search.
// - No `window.autoDetectColorScheme`: the preferred color scheme is always
//   upstream's undefined, so the placeholder is its "detect system color
//   mode disabled" title, the order is light, dark, then high contrast
//   themes, and there is no color mode button beside the input.
// - When a theme fails to apply, upstream applies the current one again
//   without writing settings (`setColorTheme(current, undefined)`); here that
//   is a preview of it, the controller's only way not to persist.
// - `localeCompare` is `ideLocaleCompare`, which approximates ICU's root
//   collation.

import 'dart:async';

import 'package:flutter/services.dart';

import 'editor/monaco/vs/platform/theme/common/theme.dart';
import 'ide_commands.dart';
import 'ide_quick_input.dart';

/// A color theme the picker lists (upstream IWorkbenchColorTheme).
class IdeColorThemeEntry {
  const IdeColorThemeEntry({
    required this.id,
    required this.label,
    required this.type,
    this.description,
  });

  final String id; // settingsId, e.g. 'Dark 2026'
  final String label;
  final ColorScheme type; // from vs/platform/theme/common/theme.dart
  final String? description;
}

/// What the picker needs from the theme service (upstream IWorkbenchThemeService).
abstract interface class IdeColorThemeController {
  List<IdeColorThemeEntry> get colorThemes;
  String get colorThemeId;

  /// `setColorTheme(id, 'preview')` when [preview], else applied and persisted.
  Future<void> setColorTheme(String id, {bool preview = false});
}

/// The Preferences: Color Theme command.
const ideSelectColorThemeCommandId = 'workbench.action.selectTheme';

/// Its keybinding, `KeyChord(CtrlCmd+K, CtrlCmd+T)`.
const ideSelectColorThemeKeybinding = IdeKeybinding(
  LogicalKeyboardKey.keyK,
  primary: true,
  second: IdeKeybinding(LogicalKeyboardKey.keyT, primary: true),
);

/// `ThemeSettingDefaults.COLOR_THEME_DARK` and `COLOR_THEME_LIGHT`.
const _defaultDark = 'Dark 2026';
const _defaultLight = 'Light 2026';

/// `defaultThemeDescriptions`.
const _defaultThemeDescriptions = {
  _defaultLight: 'Default Light',
  _defaultDark: 'Default Dark',
};

/// The quick pick of [themes]' color themes (`SelectColorThemeAction.run`
/// with `InstalledThemesPicker.openQuickPick`): moving the active item
/// previews its theme 200ms later, accepting applies and persists it, and
/// hiding otherwise applies the theme that was current again. [onError]
/// reports a theme that failed to apply (upstream `onUnexpectedError`).
IdeQuickPick ideColorThemePick(
  IdeColorThemeController themes, {
  ValueChanged<Object>? onError,
}) {
  final currentId = themes.colorThemeId;
  final all = themes.colorThemes;
  final entries = Map<IdeQuickPickItem, IdeColorThemeEntry>.identity();

  // `toEntry`.
  IdeQuickPickItem toEntry(IdeColorThemeEntry theme) {
    final settingId = theme.id;
    final item = IdeQuickPickItem(
      label: theme.label,
      description:
          _defaultThemeDescriptions[settingId] ??
          theme.description ??
          (theme.label == settingId ? null : settingId),
    );
    entries[item] = theme;
    return item;
  }

  // `toEntries`: the default themes first, then by label.
  List<IdeQuickPickEntry> toEntries(
    Iterable<IdeColorThemeEntry> list,
    String label,
  ) {
    bool pinned(IdeColorThemeEntry theme) =>
        theme.id == _defaultDark || theme.id == _defaultLight;
    final sorted = list.toList();
    ideStableSort(sorted, (t1, t2) {
      final pin1 = pinned(t1);
      final pin2 = pinned(t2);
      if (pin1 != pin2) return pin1 ? -1 : 1;
      return ideLocaleCompare(t1.label, t2.label);
    });
    return [
      if (sorted.isNotEmpty) IdeQuickPickSeparator(label),
      for (final theme in sorted) toEntry(theme),
    ];
  }

  // The order for an undefined preferred color scheme.
  final picks = [
    ...toEntries(
      all.where((theme) => theme.type == ColorScheme.light),
      'light themes',
    ),
    ...toEntries(
      all.where((theme) => theme.type == ColorScheme.dark),
      'dark themes',
    ),
    ...toEntries(
      all.where((theme) => isHighContrast(theme.type)),
      'high contrast themes',
    ),
  ];

  Timer? selectThemeTimeout;

  // Previews [theme] after 200ms, or applies it next (the current theme
  // when null); a newer call replaces a pending one.
  void selectTheme(IdeColorThemeEntry? theme, bool applyTheme) {
    selectThemeTimeout?.cancel();
    selectThemeTimeout = Timer(
      applyTheme ? Duration.zero : const Duration(milliseconds: 200),
      () {
        selectThemeTimeout = null;
        final id = theme?.id ?? currentId;
        unawaited(
          themes
              .setColorTheme(id, preview: !applyTheme)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  onError?.call(error);
                  unawaited(
                    themes
                        .setColorTheme(currentId, preview: true)
                        .then<void>(
                          (_) {},
                          onError: (Object error) => onError?.call(error),
                        ),
                  );
                },
              ),
        );
      },
    );
  }

  var isCompleted = false;
  IdeColorThemeEntry? themeOf(IdeQuickPickItem? item) =>
      item == null ? null : entries[item];
  final active = entries.keys.where((item) => entries[item]!.id == currentId);
  return IdeQuickPick(
    items: picks,
    placeholder: 'Select Color Theme (detect system color mode disabled)',
    activeItems: active.take(1).toList(),
    matchOnDescription: true,
    onDidChangeActive: (item) => selectTheme(themeOf(item), false),
    onDidAccept: (item) {
      isCompleted = true;
      // No item: upstream searches the marketplace (not ported).
      if (themeOf(item) case final theme?) selectTheme(theme, true);
    },
    onDidHide: () {
      if (!isCompleted) selectTheme(null, true);
    },
  );
}
