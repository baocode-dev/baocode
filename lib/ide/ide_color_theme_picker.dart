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
// - Auto, first and apart, follows the system's appearance; the themes stay
//   ordered light, dark, then high contrast, with no color mode button
//   beside the input.
// - Cancelled, or the current request failing, it goes back to the choice
//   kept, not to the theme shown as it opened.
// - `localeCompare` is `ideLocaleCompare`, which approximates ICU's root
//   collation.

import 'dart:async';

import 'package:flutter/services.dart';

import '../l10n/l10n.dart';

import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';

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
  /// The choice that follows the system: not a theme, not in [colorThemes].
  static const autoId = '__auto__';

  List<IdeColorThemeEntry> get colorThemes;
  String get colorThemeId;

  /// Shows [id]; unless [preview], keeps it as the choice too.
  Future<void> setColorTheme(String id, {bool preview = false});

  /// Back to the choice kept (Auto at the system's appearance now), nothing
  /// written.
  Future<void> restoreColorThemePreview();
}

/// The Preferences: Color Theme command.
const ideSelectColorThemeCommandId = 'workbench.action.selectTheme';

/// Its keybinding, `KeyChord(CtrlCmd+K, CtrlCmd+T)`.
const ideSelectColorThemeKeybinding = IdeKeybinding(
  LogicalKeyboardKey.keyK,
  primary: true,
  second: IdeKeybinding(LogicalKeyboardKey.keyT, primary: true),
);

/// `ThemeSettingDefaults.COLOR_THEME_DARK` and `COLOR_THEME_LIGHT` (ours:
/// workbench_theme.dart).
const _defaultDark = 'Bao Dark';
const _defaultLight = 'Bao Light';

/// `defaultThemeDescriptions`.
Map<String, String> _defaultThemeDescriptions(AppLocalizations l10n) => {
  _defaultLight: l10n.themeDefaultLight,
  _defaultDark: l10n.themeDefaultDark,
};

/// The quick pick of [themes]' color themes: moving the active item
/// previews it 200ms later, accepting applies and keeps it.
/// Hidden otherwise, the choice kept (Auto too) shows again, nothing
/// written; [onError] reports a theme that failed to apply.
/// Its own words are in [l10n]'s language (English when null).
IdeQuickPick ideColorThemePick(
  IdeColorThemeController themes, {
  ValueChanged<Object>? onError,
  AppLocalizations? l10n,
}) {
  final strings = l10n ?? englishLocalizations;
  final descriptions = _defaultThemeDescriptions(strings);
  final currentId = themes.colorThemeId;
  final all = themes.colorThemes;
  final entries = Map<IdeQuickPickItem, String>.identity();
  final auto = IdeQuickPickItem(
    label: strings.themeAuto,
    description: strings.themeFollowSystem,
  );
  entries[auto] = IdeColorThemeController.autoId;

  // `toEntry`.
  IdeQuickPickItem toEntry(IdeColorThemeEntry theme) {
    final settingId = theme.id;
    final item = IdeQuickPickItem(
      label: theme.label,
      description:
          descriptions[settingId] ??
          theme.description ??
          (theme.label == settingId ? null : settingId),
    );
    entries[item] = settingId;
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

  // Auto first, apart; the themes in their groups and order.
  final picks = [
    auto,
    ...toEntries(
      all.where((theme) => theme.type == ColorScheme.light),
      strings.themeLightThemes,
    ),
    ...toEntries(
      all.where((theme) => theme.type == ColorScheme.dark),
      strings.themeDarkThemes,
    ),
    ...toEntries(
      all.where((theme) => isHighContrast(theme.type)),
      strings.themeHighContrastThemes,
    ),
  ];

  Timer? selectThemeTimeout;
  var request = 0;
  var isClosed = false;
  var isAccepted = false;

  void restorePreview() => unawaited(
    themes.restoreColorThemePreview().then<void>(
      (_) {},
      onError: (Object error) => onError?.call(error),
    ),
  );

  // Previews [id] after 200ms, or applies it next (the choice kept when
  // null); a newer call replaces a pending one, and an older one's failure
  // no longer counts.
  void selectTheme(String? id, bool applyTheme) {
    selectThemeTimeout?.cancel();
    final currentRequest = ++request;
    selectThemeTimeout = Timer(
      applyTheme ? Duration.zero : const Duration(milliseconds: 200),
      () {
        selectThemeTimeout = null;
        if (isClosed && !applyTheme) return;
        if (id == null) {
          restorePreview();
          return;
        }
        unawaited(
          themes
              .setColorTheme(id, preview: !applyTheme)
              .then<void>(
                (_) {},
                onError: (Object error) {
                  onError?.call(error);
                  // Closed, or another picked since: not put back over it.
                  if (!isClosed && currentRequest == request) restorePreview();
                },
              ),
        );
      },
    );
  }

  String? themeOf(IdeQuickPickItem? item) =>
      item == null ? null : entries[item];
  final active = entries.keys.where((item) => entries[item] == currentId);
  return IdeQuickPick(
    items: picks,
    placeholder: strings.themeSelectPlaceholder,
    activeItems: active.take(1).toList(),
    matchOnDescription: true,
    onDidChangeActive: (item) {
      if (!isClosed && !isAccepted) selectTheme(themeOf(item), false);
    },
    onDidAccept: (item) {
      if (isClosed || isAccepted) return;
      // No item: closed, the choice kept shown again, nothing kept.
      if (themeOf(item) case final id?) {
        isAccepted = true;
        selectTheme(id, true);
      }
    },
    onDidHide: () {
      if (isClosed) return;
      isClosed = true;
      if (!isAccepted) {
        selectThemeTimeout?.cancel();
        selectThemeTimeout = null;
        request++;
        restorePreview();
      }
    },
  );
}
