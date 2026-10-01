/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Ported from VS Code src/vs/workbench/services/themes/common/
// themeCompatibility.ts at 6a598d4a13031703d483d103c1d934a36ad27971:
// `convertSettings`, which reads a TextMate theme's `settings` (a .tmTheme, or
// a JSON theme with a `settings` array).
// Deviations: [colors] keeps the theme's hex strings, where upstream stores
// `Color.fromHex` of them (ColorThemeData converts when it reads one); the
// color ids are inlined from colorRegistry.ts and editorColorRegistry.ts.
// A rule that is not a JSON object is kept but otherwise ignored.

final Map<String, List<String>> _settingToColorIdMapping = () {
  final mapping = <String, List<String>>{};
  void addSettingMapping(String settingId, String colorId) {
    (mapping[settingId] ??= []).add(colorId);
  }

  addSettingMapping('background', 'editor.background');
  addSettingMapping('foreground', 'editor.foreground');
  addSettingMapping('selection', 'editor.selectionBackground');
  addSettingMapping('inactiveSelection', 'editor.inactiveSelectionBackground');
  addSettingMapping(
    'selectionHighlightColor',
    'editor.selectionHighlightBackground',
  );
  addSettingMapping(
    'findMatchHighlight',
    'editor.findMatchHighlightBackground',
  );
  addSettingMapping('currentFindMatchHighlight', 'editor.findMatchBackground');
  addSettingMapping('hoverHighlight', 'editor.hoverHighlightBackground');
  // inlined to avoid editor/contrib dependencies
  addSettingMapping('wordHighlight', 'editor.wordHighlightBackground');
  addSettingMapping(
    'wordHighlightStrong',
    'editor.wordHighlightStrongBackground',
  );
  addSettingMapping(
    'findRangeHighlight',
    'editor.findRangeHighlightBackground',
  );
  addSettingMapping(
    'findMatchHighlight',
    'peekViewResult.matchHighlightBackground',
  );
  addSettingMapping(
    'referenceHighlight',
    'peekViewEditor.matchHighlightBackground',
  );
  addSettingMapping('lineHighlight', 'editor.lineHighlightBackground');
  addSettingMapping('rangeHighlight', 'editor.rangeHighlightBackground');
  addSettingMapping('caret', 'editorCursor.foreground');
  addSettingMapping('invisibles', 'editorWhitespace.foreground');
  addSettingMapping('guide', 'editorIndentGuide.background1');
  addSettingMapping('activeGuide', 'editorIndentGuide.activeBackground1');

  const ansiColorMap = [
    'ansiBlack', 'ansiRed', 'ansiGreen', 'ansiYellow', 'ansiBlue', //
    'ansiMagenta', 'ansiCyan', 'ansiWhite', 'ansiBrightBlack',
    'ansiBrightRed', 'ansiBrightGreen', 'ansiBrightYellow',
    'ansiBrightBlue', 'ansiBrightMagenta', 'ansiBrightCyan',
    'ansiBrightWhite',
  ];
  for (final color in ansiColorMap) {
    addSettingMapping(color, 'terminal.$color');
  }
  return mapping;
}();

/// Appends [oldSettings] to [textMateRules]; a rule without a scope holds the
/// theme's global settings, which set [colors] and lose every key but
/// `foreground`, `background` and `fontStyle`.
void convertSettings(
  List<Object?> oldSettings, {
  required List<Object?> textMateRules,
  required Map<String, String> colors,
}) {
  for (final rule in oldSettings) {
    textMateRules.add(rule);
    if (rule is! Map<String, Object?> || _isTruthy(rule['scope'])) {
      continue;
    }
    final settings = rule['settings'];
    if (!_isTruthy(settings)) {
      rule['settings'] = <String, Object?>{};
    } else if (settings is Map<String, Object?>) {
      for (final key in settings.keys.toList()) {
        final mappings = _settingToColorIdMapping[key];
        if (mappings != null) {
          final colorHex = settings[key];
          if (colorHex is String) {
            for (final colorId in mappings) {
              colors[colorId] = colorHex;
            }
          }
        }
        if (key != 'foreground' && key != 'background' && key != 'fontStyle') {
          settings.remove(key);
        }
      }
    }
  }
}

/// JavaScript truthiness of a JSON value.
bool _isTruthy(Object? value) => switch (value) {
  null || false || '' => false,
  num n => n != 0 && !n.isNaN,
  _ => true,
};
