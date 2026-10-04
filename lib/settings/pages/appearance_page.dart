import 'dart:async';

import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:flutter/material.dart' hide ColorScheme;

import '../../chat/chat_keys.dart';
import '../../ide/ide_color_theme_picker.dart';
import '../../ide/ide_quick_input.dart' show ideLocaleCompare;
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/workbench_theme.dart' show ThemeSettingDefaults;
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Appearance: the color theme (`workbench.colorTheme`, as
/// Preferences: Color Theme picks it), the chat's, the IDE's and the
/// terminal's alike. A choice is applied and kept at once.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key, required this.themes, this.changes});

  final IdeColorThemeController themes;

  /// Tells when [themes]' theme changes (the theme service itself).
  final Listenable? changes;

  /// The themes in the menu: light, dark, then high contrast, as the
  /// picker lists them, each group the defaults first, then by label.
  List<List<IdeColorThemeEntry>> _groups() {
    final all = themes.colorThemes;
    bool pinned(IdeColorThemeEntry theme) =>
        theme.id == ThemeSettingDefaults.colorThemeDark ||
        theme.id == ThemeSettingDefaults.colorThemeLight;
    List<IdeColorThemeEntry> sorted(bool Function(ColorScheme) type) =>
        all.where((theme) => type(theme.type)).toList()..sort((a, b) {
          final pin = (pinned(a) ? 0 : 1) - (pinned(b) ? 0 : 1);
          return pin != 0 ? pin : ideLocaleCompare(a.label, b.label);
        });
    return [
      sorted((type) => type == ColorScheme.light),
      sorted((type) => type == ColorScheme.dark),
      sorted(isHighContrast),
    ];
  }

  void _select(IdeColorThemeEntry theme) => unawaited(
    themes.setColorTheme(theme.id).catchError((Object error) {
      debugPrint('${theme.id} not applied: $error');
    }),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: changes ?? Listenable.merge(const []),
      builder: (context, _) {
        final groups = _groups();
        final currentId = themes.colorThemeId;
        final current = groups
            .expand((group) => group)
            .where((theme) => theme.id == currentId)
            .firstOrNull;
        final shown = current?.label ?? currentId;
        final key = ChatKeys.keyLabel(ideSelectColorThemeCommandId);
        return SettingsPage(
          title: l10n.appearanceSettingsTitle,
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  label: l10n.appearanceSettingsColorTheme,
                  description: key == null
                      ? l10n.appearanceSettingsColorThemeDescription
                      : l10n.appearanceSettingsColorThemeDescriptionWithKey(
                          key,
                        ),
                  trailing: SettingsDropdown(
                    current: shown,
                    width: 220,
                    semanticLabel: l10n.appearanceSettingsColorThemeLabel(
                      shown,
                    ),
                    entries: () => ideMenuGroups([
                      for (final group in groups)
                        [
                          for (final theme in group)
                            IdeMenuAction(
                              theme.label,
                              checked: theme.id == currentId,
                              onSelected: () => _select(theme),
                            ),
                        ],
                    ]),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
