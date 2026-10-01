import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../theme/app_theme.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../app_locale.dart';

/// Settings → Region & Language: the display language, VS Code's
/// Configure Display Language. Each language is named in its own language,
/// and in the one shown under it; a choice applies at once.
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
        String? nameHere(String setting) => switch (setting) {
          AppLocale.english => l10n.languageSettingsEnglishName,
          AppLocale.simplifiedChinese =>
            l10n.languageSettingsSimplifiedChineseName,
          _ => null,
        };
        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          children: [
            Text(
              l10n.languageSettingsTitle,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              l10n.languageSettingsDisplayLanguage,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.languageSettingsDescription,
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LanguageOption(
                    label: l10n.languageSettingsFollowSystem,
                    detail: l10n.languageSettingsFollowSystemDetail(
                      nativeNames[systemSetting] ?? nativeNames.values.first,
                    ),
                    selected: setting == null,
                    onSelected: () => locale.select(null),
                  ),
                  for (final option in AppLocale.settings)
                    _LanguageOption(
                      label: nativeNames[option]!,
                      detail: nameHere(option) == nativeNames[option]
                          ? null
                          : nameHere(option),
                      selected: setting == option,
                      onSelected: () => locale.select(option),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One choice: its label, a muted detail after it, and a check when chosen.
class _LanguageOption extends StatefulWidget {
  const _LanguageOption({
    required this.label,
    required this.detail,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onSelected;

  @override
  State<_LanguageOption> createState() => _LanguageOptionState();
}

class _LanguageOptionState extends State<_LanguageOption> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focusBorder = themeColors['focusBorder'];
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: widget.selected,
      button: true,
      label: widget.label,
      excludeSemantics: true,
      onTap: widget.onSelected,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onSelected(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onSelected,
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _hovered || widget.selected
                  ? AppColors.hover
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: _focused ? focusBorder : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: AppColors.text, fontSize: 13),
                  ),
                ),
                if (widget.detail case final detail?) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.selected)
                  Icon(Codicons.check, size: 16, color: AppColors.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
