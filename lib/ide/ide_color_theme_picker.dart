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
// - Auto 独立置顶，跟随系统亮度；真实主题仍按浅色、深色、高对比度排序，
//   不增加输入框旁的颜色模式按钮。
// - 取消或当前请求失败时恢复已提交偏好，不持久化打开时的具体主题。
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
  /// 跟随系统的选择 ID；不是主题资产，不加入 [colorThemes]。
  static const autoId = '__auto__';

  List<IdeColorThemeEntry> get colorThemes;
  String get colorThemeId;

  /// [preview] 为 true 时仅预览 [id]，否则应用并保存选择。
  Future<void> setColorTheme(String id, {bool preview = false});

  /// 恢复已提交偏好；Auto 使用恢复时最新的系统亮度，不写入设置。
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

/// [themes] 的主题快捷选择器：移动选项后等待 200ms 预览，确认时应用并保存。
/// 取消时恢复已提交偏好（包括 Auto），不写入设置；[onError] 接收应用失败。
/// 文案使用 [l10n]，未传入时使用英文。
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

  // Auto 独立置顶；保留真实主题的分组与排序。
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

  // 保留 200ms 预览；新请求替换待执行的预览，并使旧失败失效。
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
                  // 关闭或选择已更新后，旧失败不能恢复并覆盖新选择。
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
      // 无匹配项时只关闭并恢复偏好，不提交主题。
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
