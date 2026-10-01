import 'package:flutter/material.dart';

import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../app_locale.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Region & Language: the display language, VS Code's
/// Configure Display Language. Each language is named in its own language;
/// a choice applies at once.
class LanguageSettingsPage extends StatelessWidget {
  const LanguageSettingsPage({super.key, required this.locale});

  final AppLocale locale;

  /// Each language in its own language.
  static const nativeNames = {
    AppLocale.english: 'English',
    AppLocale.simplifiedChinese: '简体中文',
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: locale,
      builder: (context, _) {
        final setting = locale.setting;
        final system = AppLocale.systemLocale(
          View.maybeOf(context)?.platformDispatcher.locales,
        );
        final systemSetting = AppLocale.normalize(system.toLanguageTag());
        final followSystem = l10n.languageSettingsFollowSystemCurrent(
          nativeNames[systemSetting] ?? nativeNames.values.first,
        );
        final current = nativeNames[setting] ?? followSystem;
        return SettingsPage(
          title: l10n.languageSettingsTitle,
          children: [
            SettingsCard(
              children: [
                SettingsRow(
                  label: l10n.languageSettingsDisplayLanguage,
                  description: l10n.languageSettingsDescription,
                  trailing: SettingsDropdown(
                    current: current,
                    semanticLabel: l10n.languageSettingsDisplayLanguageLabel(
                      current,
                    ),
                    entries: () => [
                      IdeMenuAction(
                        followSystem,
                        checked: setting == null,
                        onSelected: () => locale.select(null),
                      ),
                      const IdeMenuSeparator(),
                      for (final option in AppLocale.settings)
                        IdeMenuAction(
                          nativeNames[option]!,
                          checked: setting == option,
                          onSelected: () => locale.select(option),
                        ),
                    ],
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
