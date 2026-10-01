// Test helpers adapted from vscode-textmate 9.3.2 (25b68dad…):
// src/tests/themes.test.ts and src/tests/themeTest.ts (MIT, see
// fixtures/LICENSE.md).

import 'dart:convert';
import 'dart:io';

import 'package:bao_editor/textmate/vscode_textmate/plist.dart';
import 'package:bao_editor/textmate/vscode_textmate/theme.dart';

/// Upstream's `test-cases/` folder, copied next to the tests.
const String fixturesRoot = 'test/textmate/vscode_textmate/fixtures';

String fixturePath(String relative) => '$fixturesRoot/$relative';

String readFixture(String relative) =>
    File(fixturePath(relative)).readAsStringSync();

/// Decodes a theme file as upstream's tests do: JSON for `.json`, else plist.
Object? loadThemeFile(String relative) {
  final contents = readFixture(relative);
  if (relative.endsWith('.json')) {
    return jsonDecode(contents);
  }
  return parsePLIST(contents);
}

/// Converts a decoded theme into [IRawTheme].
///
/// Entries without `settings` are dropped: upstream's `parseTheme` skips them
/// too, and the shifted indexes keep their relative order.
IRawTheme rawThemeFromJson(Object? json) {
  final map = json as Map;
  final settings = <IRawThemeSetting>[];
  for (final entry in (map['settings'] as List? ?? const [])) {
    if (entry is! Map) continue;
    final style = entry['settings'];
    if (style is! Map) continue;
    final hasFont =
        style.containsKey('fontFamily') ||
        style.containsKey('fontSize') ||
        style.containsKey('lineHeight');
    settings.add(
      IRawThemeSetting(
        name: entry['name'] is String ? entry['name'] as String : null,
        scope: entry['scope'],
        settings: hasFont
            ? IRawThemeSettingStyleWithFont(
                fontStyle: style['fontStyle'],
                foreground: style['foreground'],
                background: style['background'],
                fontFamily: style['fontFamily'],
                fontSize: style['fontSize'],
                lineHeight: style['lineHeight'],
              )
            : IRawThemeSettingStyle(
                fontStyle: style['fontStyle'],
                foreground: style['foreground'],
                background: style['background'],
              ),
      ),
    );
  }
  return IRawTheme(
    name: map['name'] is String ? map['name'] as String : null,
    settings: settings,
  );
}

/// `str.split(/\r\n|\r|\n/)`.
List<String> splitLines(String str) => str.split(RegExp(r'\r\n|\r|\n'));
