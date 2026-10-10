import 'dart:async';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart' hide ColorScheme;

import '../../chat/chat_keys.dart';
import '../../chat/chat_width.dart';
import '../../chat/user_message_style.dart';
import '../../ide/ide_code_editor.dart';
import '../../ide/ide_color_theme_picker.dart';
import '../../ide/ide_quick_input.dart' show ideLocaleCompare;
import '../../ide/terminal/terminal_colors.dart' show terminalColorTheme;
import '../../ide/terminal/terminal_render_theme.dart'
    show terminalBaseFontSize, vscodeTerminalFontSize;
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/code_font.dart';
import '../../theme/workbench_theme.dart' show ThemeSettingDefaults;
import '../user_settings.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Appearance: the color theme (`workbench.colorTheme`, as
/// Preferences: Color Theme picks it), the chat's, the IDE's and the
/// terminal's alike, and how wide the conversation grows
/// (`chat.maxWidth`, see [ChatWidth]); then the code's font, size and
/// ligatures, the window's text size and the terminal's (see [CodeFont]). A
/// choice is applied and kept at once.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({
    super.key,
    required this.themes,
    this.changes,
    this.settings,
  });

  final IdeColorThemeController themes;

  /// Tells when [themes]' theme changes (the theme service itself).
  final Listenable? changes;

  /// settings.json; none under test, where the width is not kept.
  final UserSettings? settings;

  static String widthName(BuildContext context, double width) {
    final l10n = context.l10n;
    if (width.isInfinite) return l10n.appearanceSettingsChatWidthFull;
    if (width == ChatWidth.fallback) {
      return l10n.appearanceSettingsChatWidthDefault;
    }
    return '${width.round()}';
  }

  void _selectWidth(double width) {
    ChatWidth.current.value = width;
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings
          .update(ChatWidth.settingKey, ChatWidth.setting(width))
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint('${ChatWidth.settingKey} not kept: $error');
          }),
    );
  }

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

  /// The families the dropdown offers: each is put first, then the defaults.
  static const _codeFontPresets = <String>[
    'JetBrains Mono',
    'Fira Code',
    'Cascadia Code',
    'Consolas',
    'Menlo',
    'Monaco',
    'Courier New',
  ];

  /// The step of [steps] nearest [value]: the slider's position.
  static int _nearest<T extends num>(List<T> steps, num value) {
    var nearest = 0;
    for (var i = 1; i < steps.length; i++) {
      if ((steps[i] - value).abs() < (steps[nearest] - value).abs()) {
        nearest = i;
      }
    }
    return nearest;
  }

  static List<String> _presetOf(String name) => [
    name,
    ...CodeFont.defaultFamilies.where((family) => family != name),
  ];

  /// The dropdown's text for [families]: Default; a preset's name when the
  /// list is that preset; else the list itself.
  static String _familyName(BuildContext context, List<String> families) {
    if (listEquals(families, CodeFont.defaultFamilies)) {
      return context.l10n.appearanceSettingsCodeFontDefault;
    }
    final first = families.first;
    if (listEquals(families, _presetOf(first))) return first;
    return families.join(', ');
  }

  /// Writes [value] for [key] in settings.json (null removes it).
  void _keep(String key, Object? value) {
    final settings = this.settings;
    if (settings == null) return;
    unawaited(
      settings.update(key, value).catchError((Object error) {
        // A settings file that does not parse is left as it is; its error
        // is shown.
        debugPrint('$key not kept: $error');
      }),
    );
  }

  static String _styleName(BuildContext context, UserMessageStyle style) =>
      switch (style) {
        UserMessageStyle.sticky =>
          context.l10n.appearanceSettingsUserMessageStyleSticky,
        UserMessageStyle.bubble =>
          context.l10n.appearanceSettingsUserMessageStyleBubble,
      };

  void _selectStyle(UserMessageStyle style) {
    UserMessageStyle.current.value = style;
    _keep(UserMessageStyle.settingKey, style.setting);
  }

  void _selectFamilies(List<String> families) {
    CodeFont.families.value = families;
    _keep(CodeFont.familySettingKey, CodeFont.familiesSetting(families));
  }

  void _selectSize(double size) {
    CodeFont.size.value = size;
    _keep(CodeFont.sizeSettingKey, CodeFont.sizeSetting(size));
  }

  void _selectLigatures(bool on) {
    CodeFont.ligatures.value = on;
    _keep(CodeFont.ligaturesSettingKey, CodeFont.ligaturesSetting(on));
  }

  void _selectTerminalSize(double? size) {
    CodeFont.terminalSize.value = size;
    _keep(CodeFont.terminalSizeSettingKey, CodeFont.terminalSizeSetting(size));
  }

  /// The step nearest the size the terminal follows the window's text at,
  /// where a custom size starts.
  static double _followedTerminalSize() {
    final size =
        CodeFont.uiSized(terminalBaseFontSize) * CodeFont.uiScale.value / 100;
    return CodeFont.sizeSteps[_nearest(CodeFont.sizeSteps, size)];
  }

  void _selectUiScale(int percent) {
    CodeFont.uiScale.value = percent;
    _keep(CodeFont.uiScaleSettingKey, CodeFont.uiScaleSetting(percent));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: Listenable.merge([
        changes,
        ChatWidth.current,
        UserMessageStyle.current,
        CodeFont.families,
        CodeFont.size,
        CodeFont.ligatures,
        CodeFont.uiScale,
        CodeFont.terminalSize,
      ]),
      builder: (context, _) {
        final widthStep = ChatWidth.stepOf(ChatWidth.current.value);
        final widthShown = widthName(context, ChatWidth.steps[widthStep]);
        final styleShown = _styleName(context, UserMessageStyle.current.value);
        final families = CodeFont.families.value;
        final sizeStep = _nearest(CodeFont.sizeSteps, CodeFont.size.value);
        final sizeShown = '${CodeFont.size.value.round()}';
        final uiScaleStep = CodeFont.uiScale.value - CodeFont.minUiScale;
        final uiScaleShown = '${CodeFont.uiScale.value}';
        final terminalSize = CodeFont.terminalSize.value;
        final terminalSizeShown = terminalSize == null
            ? l10n.appearanceSettingsTerminalSizeFollow
            : l10n.appearanceSettingsTerminalSizeCustom;
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
                SettingsRow(
                  label: l10n.appearanceSettingsChatWidth,
                  description: l10n.appearanceSettingsChatWidthDescription,
                  trailing: SettingsSlider(
                    step: widthStep,
                    count: ChatWidth.steps.length,
                    label: widthShown,
                    semanticLabel: l10n.appearanceSettingsChatWidthLabel(
                      widthShown,
                    ),
                    onChanged: (step) => _selectWidth(ChatWidth.steps[step]),
                    tapOnly: true,
                  ),
                ),
                SettingsRow(
                  label: l10n.appearanceSettingsUserMessageStyle,
                  description:
                      l10n.appearanceSettingsUserMessageStyleDescription,
                  trailing: SettingsDropdown(
                    current: styleShown,
                    width: 220,
                    semanticLabel: l10n.appearanceSettingsUserMessageStyleLabel(
                      styleShown,
                    ),
                    entries: () => ideMenuGroups([
                      [
                        for (final style in UserMessageStyle.values)
                          IdeMenuAction(
                            _styleName(context, style),
                            checked: style == UserMessageStyle.current.value,
                            onSelected: () => _selectStyle(style),
                          ),
                      ],
                    ]),
                  ),
                ),
              ],
            ),
            SettingsCard(
              children: [
                SettingsRow(
                  label: l10n.appearanceSettingsCodeFont,
                  description: l10n.appearanceSettingsCodeFontDescription,
                  below: [
                    SettingsTextField(
                      value: listEquals(families, CodeFont.defaultFamilies)
                          ? ''
                          : families.join(', '),
                      hint: CodeFont.defaultFamilies.join(', '),
                      semanticLabel: l10n.appearanceSettingsCodeFontField,
                      width: 360,
                      onSubmitted: (text) =>
                          _selectFamilies(CodeFont.parseFamilies(text)),
                    ),
                  ],
                  trailing: SettingsDropdown(
                    current: _familyName(context, families),
                    width: 220,
                    semanticLabel: l10n.appearanceSettingsCodeFontLabel(
                      _familyName(context, families),
                    ),
                    entries: () => ideMenuGroups([
                      [
                        IdeMenuAction(
                          l10n.appearanceSettingsCodeFontDefault,
                          checked: listEquals(
                            families,
                            CodeFont.defaultFamilies,
                          ),
                          onSelected: () =>
                              _selectFamilies(CodeFont.defaultFamilies),
                        ),
                        for (final name in _codeFontPresets)
                          IdeMenuAction(
                            name,
                            checked: listEquals(families, _presetOf(name)),
                            onSelected: () => _selectFamilies(_presetOf(name)),
                          ),
                      ],
                    ]),
                  ),
                ),
                // Not const: it must redraw as the font, size or ligatures
                // change.
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _CodeFontPreview(),
                ),
                SettingsRow(
                  label: l10n.appearanceSettingsCodeSize,
                  description: l10n.appearanceSettingsCodeSizeDescription,
                  trailing: SettingsSlider(
                    step: sizeStep,
                    count: CodeFont.sizeSteps.length,
                    label: sizeShown,
                    semanticLabel: l10n.appearanceSettingsCodeSizeLabel(
                      sizeShown,
                    ),
                    onChanged: (step) => _selectSize(CodeFont.sizeSteps[step]),
                  ),
                ),
                SettingsSwitchRow(
                  label: l10n.appearanceSettingsLigatures,
                  description: l10n.appearanceSettingsLigaturesDescription,
                  value: CodeFont.ligatures.value,
                  onChanged: _selectLigatures,
                ),
                SettingsRow(
                  label: l10n.appearanceSettingsUiScale,
                  description: l10n.appearanceSettingsUiScaleDescription,
                  trailing: SettingsSlider(
                    step: uiScaleStep,
                    count: CodeFont.maxUiScale - CodeFont.minUiScale + 1,
                    label: '$uiScaleShown%',
                    semanticLabel: l10n.appearanceSettingsUiScaleLabel(
                      uiScaleShown,
                    ),
                    onChanged: (step) =>
                        _selectUiScale(CodeFont.minUiScale + step),
                  ),
                ),
                SettingsRow(
                  label: l10n.appearanceSettingsTerminalSize,
                  description: l10n.appearanceSettingsTerminalSizeDescription,
                  trailing: SettingsDropdown(
                    current: terminalSizeShown,
                    width: 220,
                    semanticLabel: l10n.appearanceSettingsTerminalSizeLabel(
                      terminalSizeShown,
                    ),
                    entries: () => ideMenuGroups([
                      [
                        IdeMenuAction(
                          l10n.appearanceSettingsTerminalSizeFollow,
                          checked: terminalSize == null,
                          onSelected: () => _selectTerminalSize(null),
                        ),
                        IdeMenuAction(
                          l10n.appearanceSettingsTerminalSizeCustom,
                          checked: terminalSize != null,
                          onSelected: () {
                            if (terminalSize != null) return;
                            _selectTerminalSize(_followedTerminalSize());
                          },
                        ),
                      ],
                    ]),
                  ),
                ),
                if (terminalSize != null)
                  SettingsRow(
                    label: l10n.appearanceSettingsTerminalSizeValue,
                    trailing: SettingsSlider(
                      step: _nearest(CodeFont.sizeSteps, terminalSize),
                      count: CodeFont.sizeSteps.length,
                      label: '${terminalSize.round()}',
                      semanticLabel: l10n.appearanceSettingsTerminalSizeLabel(
                        '${terminalSize.round()}',
                      ),
                      onChanged: (step) =>
                          _selectTerminalSize(CodeFont.sizeSteps[step]),
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: _TerminalFontPreview(),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// A shell session in the terminal's colors, drawn as the terminal draws
/// text (its font, without ligatures, at its size), so the size can be seen
/// before a terminal is opened.
class _TerminalFontPreview extends StatelessWidget {
  const _TerminalFontPreview();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        terminalColorTheme,
        CodeFont.families,
        CodeFont.terminalSize,
      ]),
      builder: (context, _) {
        final colors = terminalColorTheme.value;
        final ansi = colors.ansi;
        // Scaled here as the terminal scales it, so not again by the text.
        final size = vscodeTerminalFontSize(
          MediaQuery.textScalerOf(context),
          SystemTextScale.maybeOf(context),
        );
        TextSpan span(String text, [Color? color]) => TextSpan(
          text: text,
          style: TextStyle(color: color),
        );
        List<TextSpan> prompt(String command) => [
          span('~/app ', ansi[4]),
          span('main ', ansi[5]),
          span('❯ ', ansi[2]),
          span('$command\n'),
        ];
        return DecoratedBox(
          decoration: BoxDecoration(
            color: colors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.partBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text.rich(
              TextSpan(
                children: [
                  ...prompt('ls'),
                  span('README.md  '),
                  span('lib', ansi[12]),
                  span('  pubspec.yaml  '),
                  span('test', ansi[12]),
                  span('\n'),
                  ...prompt('git status -s'),
                  span(' M', ansi[1]),
                  span(' lib/main.dart\n'),
                  span('??', ansi[1]),
                  span(' lib/terminal.dart'),
                ],
              ),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                color: colors.foreground,
                fontFamily: AppFonts.mono,
                fontFamilyFallback: AppFonts.monoFallbacks,
                fontSize: size,
                height: 1.2,
                // The terminal draws a cell at a time: no ligatures.
                fontFeatures: const [
                  FontFeature.disable('liga'),
                  FontFeature.disable('calt'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A sample of TypeScript in the IDE's editor, highlighted, read-only: it is
/// drawn in the code font as it is set (family, size, ligatures), so the
/// choice can be seen before it is used.
class _CodeFontPreview extends StatefulWidget {
  const _CodeFontPreview();

  @override
  State<_CodeFontPreview> createState() => _CodeFontPreviewState();
}

class _CodeFontPreviewState extends State<_CodeFontPreview> {
  static const _sample = '''
type Point = { x: number; y: number };
const add = (a: Point, b: Point): Point =>
  ({ x: a.x + b.x, y: a.y + b.y });
if (add(p, q).x >= 0 && p !== q) {
  return items ?? [];
}''';

  // The document is handed in, so it is disposed here, not by the controller.
  final _document = EditorDocumentModel(_sample);
  late final _text = EditorSurfaceController(document: _document);

  @override
  void dispose() {
    _text.dispose();
    _document.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // As tall as the sample at the code's size, so there is nothing to scroll.
    final lines = '\n'.allMatches(_sample).length + 1;
    return SizedBox(
      height: lines * CodeFont.sized(13) * 1.45 + 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.partBorder),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: IdeCodeEditor(
            controller: _text,
            path: 'preview.ts',
            readOnly: true,
            bare: true,
          ),
        ),
      ),
    );
  }
}
