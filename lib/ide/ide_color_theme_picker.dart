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
// - 自动模式由主题服务处理；此步仍只列具体主题，按浅色、深色、高对比
//   分组，输入框旁不另设颜色模式按钮。
// - 取消或加载失败时结束预览，恢复服务最新保存的选择；过期失败不回滚。
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

/// 用户保存的主题偏好；自动模式保留固定主题 id，实际配色由系统决定。
typedef IdeColorThemeSelection = ({String id, bool automatic});

/// What the picker needs from the theme service (upstream IWorkbenchThemeService).
abstract interface class IdeColorThemeController {
  List<IdeColorThemeEntry> get colorThemes;
  String get colorThemeId;
  IdeColorThemeSelection get colorThemeSelection;

  /// 结束预览，恢复执行时已保存的选择；返回恢复完成的 Future。
  Future<void> restoreColorTheme();

  /// 应用 [id] 或 [automatic] 指定的系统配色；[preview] 时不保存。
  /// 返回应用完成的 Future。
  Future<void> setColorTheme(
    String id, {
    bool preview = false,
    bool automatic = false,
  });
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

/// The quick pick of [themes]' color themes (`SelectColorThemeAction.run`
/// with `InstalledThemesPicker.openQuickPick`): moving the active item
/// previews its theme 200ms later, accepting applies and persists it, and
/// 取消时恢复服务最新保存的选择，不覆盖预览期间的外部配置变更。
/// [onError] 报告当前请求的加载错误（上游 `onUnexpectedError`）。
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
  final entries = Map<IdeQuickPickItem, IdeColorThemeEntry>.identity();

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

  // 具体主题按浅色、深色、高对比分组。
  final picks = [
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

  // 预览延迟 200ms；取消或无匹配项时结束预览，恢复最新保存的选择。
  void selectTheme(IdeColorThemeSelection? theme, bool applyTheme) {
    selectThemeTimeout?.cancel();
    final mine = ++request;
    selectThemeTimeout = Timer(
      applyTheme ? Duration.zero : const Duration(milliseconds: 200),
      () {
        selectThemeTimeout = null;
        final change = theme == null
            ? themes.restoreColorTheme()
            : themes.setColorTheme(
                theme.id,
                preview: !applyTheme,
                automatic: theme.automatic,
              );
        unawaited(
          change.then<void>(
            (_) {},
            onError: (Object error) {
              // 旧预览的失败不能覆盖后来接受的主题。
              if (mine != request) return;
              onError?.call(error);
              unawaited(
                themes.restoreColorTheme().then<void>(
                  (_) {},
                  onError: (Object error) {
                    if (mine == request) onError?.call(error);
                  },
                ),
              );
            },
          ),
        );
      },
    );
  }

  var isCompleted = false;
  IdeColorThemeSelection? themeOf(IdeQuickPickItem? item) {
    final theme = entries[item];
    return theme == null ? null : (id: theme.id, automatic: false);
  }

  final active = entries.keys.where((item) => entries[item]!.id == currentId);
  return IdeQuickPick(
    items: picks,
    placeholder: strings.themeSelectPlaceholder,
    activeItems: active.take(1).toList(),
    matchOnDescription: true,
    onDidChangeActive: (item) => selectTheme(themeOf(item), false),
    onDidAccept: (item) {
      isCompleted = true;
      // 无匹配项也须结束预览，不能把临时 Auto 留在服务中。
      selectTheme(themeOf(item), true);
    },
    onDidHide: () {
      if (!isCompleted) selectTheme(null, true);
    },
  );
}
