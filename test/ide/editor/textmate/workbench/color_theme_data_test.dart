// The Dart color theme loader against VS Code: every bundled theme's
// IRawTheme and token color map must equal what
// tool/generate_textmate_fixtures.mjs recorded from the upstream setup
// (test/fixtures/textmate/themes/<id>.json), plus the loader's corner cases.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/editor/monaco/vs/base/common/color.dart';
import 'package:baocode/ide/editor/monaco/vs/platform/theme/common/theme.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/text_mate/browser/text_mate_tokenization_feature_impl.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/themes/common/color_theme_data.dart';
import 'package:baocode/ide/editor/monaco/vs/workbench/services/themes/common/plist_parser.dart'
    as plist;
import 'package:baocode/ide/editor/monaco/vs/workbench/services/themes/common/workbench_theme_service.dart';
import 'package:baocode/ide/editor/textmate/textmate_manifest.dart';
import 'package:baocode/ide/editor/textmate/vscode_textmate/raw_theme.dart';

Future<String> readAsset(String path) =>
    File('$textMateAssetRoot/$path').readAsString();

/// The IRawTheme as plain JSON, as `JSON.stringify` writes it upstream.
Map<String, Object?> rawThemeToJson(IRawTheme theme) => {
  if (theme.name != null) 'name': theme.name,
  'settings': [
    for (final setting in theme.settings)
      {
        if (setting.name != null) 'name': setting.name,
        if (setting.scope != null) 'scope': setting.scope,
        'settings': {
          if (setting.settings.foreground != null)
            'foreground': setting.settings.foreground,
          if (setting.settings.background != null)
            'background': setting.settings.background,
          if (setting.settings.fontStyle != null)
            'fontStyle': setting.settings.fontStyle,
        },
      },
  ],
};

/// Loads a theme from in-memory files.
Future<ColorThemeData> loadTheme(
  Map<String, String> files,
  String path, {
  String? uiTheme,
}) async {
  final theme = ColorThemeData.fromExtensionTheme(
    IThemeExtensionPoint(
      id: 'Test',
      label: 'Test',
      path: path,
      uiTheme: uiTheme,
    ),
    path,
    extensionId: 'test.themes',
  );
  await theme.ensureLoaded((path) async {
    final content = files[path];
    if (content == null) throw FileSystemException('missing', path);
    return content;
  });
  return theme;
}

void main() {
  final manifest = TextMateManifest.parse(
    File('$textMateAssetRoot/manifest.json').readAsStringSync(),
  );

  group('bundled themes match VS Code', () {
    for (final contribution in manifest.themes) {
      test(contribution.id, () async {
        final fixture = jsonDecode(
          File('test/fixtures/textmate/themes/${contribution.id}.json')
              .readAsStringSync(),
        ) as Map<String, Object?>;
        expect(fixture['revision'], manifest.revision);

        final theme = ColorThemeData.fromExtensionTheme(
          contribution,
          contribution.assetPath,
          extensionId: contribution.extensionId,
        );
        await theme.ensureLoaded(readAsset);

        expect(theme.type.value, fixture['type']);
        expect(rawThemeToJson(toRawTheme(theme)), fixture['rawTheme']);
        expect(theme.tokenColorMap, fixture['tokenColorMap']);
      });
    }
  });

  group('bundled theme details', () {
    Future<ColorThemeData> bundled(String id) async {
      final contribution = manifest.themeById(id)!;
      final theme = ColorThemeData.fromExtensionTheme(
        contribution,
        contribution.assetPath,
        extensionId: contribution.extensionId,
      );
      await theme.ensureLoaded(readAsset);
      return theme;
    }

    test('Dark 2026 follows its include chain', () async {
      final theme = await bundled('Dark 2026');
      expect(theme.id, 'vs-dark vscode-theme-defaults-themes-2026-dark-json');
      expect(theme.label, 'Dark 2026');
      expect(theme.settingsId, 'Dark 2026');
      expect(theme.type, ColorScheme.dark);
      expect(theme.semanticHighlighting, isTrue);
      // 2026-dark.json includes dark_modern.json, which includes
      // dark_plus.json, which includes dark_vs.json; later files win.
      expect(theme.colors['editor.background'], '#121314');
      expect(theme.colors['chat.slashCommandForeground'], '#85B6FF');
      expect(theme.colors['ports.iconRunningProcessForeground'], '#369432');
      // Rules accumulate in include order: 50 + 15 + 0 + 53.
      expect(theme.themeTokenColors.length, 118);
      expect(theme.semanticTokenColors.length, 4 + 4);
    });

    test('Dark+ default rule and colors', () async {
      final theme = await bundled('Dark+');
      final first = theme.tokenColors.first;
      expect(first.scope, isNull);
      expect(first.settings.foreground, '#D4D4D4');
      expect(first.settings.background, '#1E1E1E');
      expect(theme.tokenColorMap.take(3), [null, '#D4D4D4', '#1E1E1E']);
      expect(theme.getTokenColorId('#d4d4d4'), 1);
      expect(theme.getTokenColorId('#nothing'), 0);
      expect(theme.defines('editor.background'), isTrue);
      expect(theme.defines('editor.selectionForeground'), isFalse);
    });

    test('high contrast themes', () async {
      expect(
        (await bundled('Default High Contrast')).type,
        ColorScheme.highContrastDark,
      );
      expect(
        (await bundled('Default High Contrast Light')).type,
        ColorScheme.highContrastLight,
      );
      expect((await bundled('Light Modern')).type, ColorScheme.light);
    });
  });

  group('loading', () {
    test('include chain, default colors and semantic colors', () async {
      final theme = await loadTheme(
        {
          'themes/base.json': '''{
          // base
          "colors": { "editor.foreground": "#aabbcc", "editor.background": "#112233", },
          "tokenColors": [ { "scope": "comment", "settings": { "foreground": "#00ff0080" } } ],
          "semanticHighlighting": true,
          "semanticTokenColors": {
            "variable": "#123",
            "function": { "foreground": "#abcdef", "bold": true },
            "type": { "italic": true },
            "ignored": { "unknown": 1 }
          }
        }''',
          'themes/child.json': '''{
          "include": "./base.json",
          "colors": { "editor.foreground": "default", "editor.selectionBackground": "#ff000033" },
          "tokenColors": [
            { "scope": ["keyword", "storage"], "settings": { "foreground": "#fff", "fontStyle": "bold" } },
            { "settings": { "foreground": "#000" } },
            { "scope": "", "settings": { "foreground": "#111" } },
            { "scope": "x", "settings": { "foreground": "red", "background": "#ABCDEFFF" } }
          ]
        }''',
        },
        'themes/child.json',
        uiTheme: 'vs',
      );

      expect(theme.type, ColorScheme.light);
      expect(theme.semanticHighlighting, isTrue);
      expect(theme.colors, {
        'editor.background': '#112233',
        'editor.selectionBackground': '#ff000033',
      });
      expect(rawThemeToJson(toRawTheme(theme)), {
        'name': 'Test',
        'settings': [
          {
            'settings': {'foreground': '#333333', 'background': '#112233'},
          },
          {
            'scope': 'comment',
            'settings': {'foreground': '#00FF0080'},
          },
          {
            'scope': ['keyword', 'storage'],
            'settings': {'foreground': '#FFFFFF', 'fontStyle': 'bold'},
          },
          {
            'scope': 'x',
            'settings': {'background': '#ABCDEF'},
          },
          for (final (scope, color) in [
            ('token.info-token', '#316BCD'),
            ('token.warn-token', '#CD9731'),
            ('token.error-token', '#CD3131'),
            ('token.debug-token', '#800080'),
          ])
            {
              'scope': scope,
              'settings': {'foreground': color},
            },
        ],
      });
      expect(theme.semanticTokenColors.map((r) => r.selector), [
        'variable',
        'function',
        'type',
      ]);
      // The semantic foregrounds are already in the map.
      expect(theme.tokenColorMap, [
        null,
        '#333333',
        '#112233',
        '#00FF0080',
        '#FFFFFF',
        '#ABCDEF',
        '#316BCD',
        '#CD9731',
        '#CD3131',
        '#800080',
      ]);
    });

    test(
      'semantic colors extend the color map after the token colors',
      () async {
        final theme = await loadTheme({
          't.json':
              '{ "semanticTokenColors": { "a": "#010203", '
              '"b": { "foreground": "#0a0b0c80" } } }',
        }, 't.json');
        final map = theme.tokenColorMap;
        expect(map.sublist(map.length - 2), ['#010203', '#0A0B0C80']);
      },
    );

    test('a settings array is read as a TextMate theme', () async {
      final theme = await loadTheme({
        'monokai.json': '''{
          "settings": [
            { "settings": { "background": "#272822", "foreground": "#F8F8F2",
                            "caret": "#F8F8F0", "lineHighlight": "#3E3D32" } },
            { "name": "Comment", "scope": "comment", "settings": { "foreground": "#75715E" } }
          ],
          "colors": { "editor.background": "#000000" },
          "semanticHighlighting": true
        }''',
      }, 'monokai.json');
      expect(theme.colors, {
        'editor.background': '#272822',
        'editor.foreground': '#F8F8F2',
        'editorCursor.foreground': '#F8F8F0',
        'editor.lineHighlightBackground': '#3E3D32',
      });
      expect(theme.semanticHighlighting, isFalse);
      final rules = toRawTheme(theme).settings;
      expect(rules[0].settings.foreground, '#F8F8F2');
      expect(rules[0].settings.background, '#272822');
      expect(rules[1].scope, 'comment');
      expect(rules[1].settings.foreground, '#75715E');
      expect(rules.length, 2 + 4); // with the dark default token colors
    });

    test('tokenColors can name a .tmTheme file', () async {
      final theme = await loadTheme({
        'themes/t.json':
            '{ "colors": { "editor.background": "#010101" }, '
            '"tokenColors": "../tm/t.tmTheme" }',
        'tm/t.tmTheme': '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>name</key><string>T</string>
  <key>settings</key>
  <array>
    <dict>
      <key>settings</key>
      <dict>
        <key>background</key><string>#202020</string>
        <key>foreground</key><string>#e0e0e0</string>
      </dict>
    </dict>
    <dict>
      <key>scope</key><string>string, constant.character &amp; x</string>
      <key>settings</key>
      <dict><key>foreground</key><string>#ce9178</string><key>fontStyle</key><string>italic</string></dict>
    </dict>
  </array>
</dict>
</plist>''',
      }, 'themes/t.json');
      // The .tmTheme is read after `colors`, so its global settings win.
      expect(theme.colors['editor.background'], '#202020');
      final rules = toRawTheme(theme).settings;
      expect(rules[0].settings.foreground, '#E0E0E0');
      expect(rules[1].scope, 'string, constant.character & x');
      expect(rules[1].settings.foreground, '#CE9178');
      expect(rules[1].settings.fontStyle, 'italic');
    });

    test(
      'a theme with token.info-token gets no default token colors',
      () async {
        final theme = await loadTheme({
          't.json':
              '{ "tokenColors": [ { "scope": "token.info-token", '
              '"settings": { "foreground": "#123456" } } ] }',
        }, 't.json');
        expect(theme.tokenColors.map((r) => r.scope), [
          null,
          'token.info-token',
        ]);
      },
    );

    test('registry defaults per theme type', () async {
      Future<List<String?>> first(
        String? uiTheme, [
        String colors = '{}',
      ]) async {
        final theme = await loadTheme(
          {'t.json': '{ "colors": $colors }'},
          't.json',
          uiTheme: uiTheme,
        );
        final rule = theme.tokenColors.first.settings;
        return [rule.foreground, rule.background];
      }

      expect(await first(null), ['#BBBBBB', '#1E1E1E']);
      expect(await first('vs-dark'), ['#BBBBBB', '#1E1E1E']);
      expect(await first('vs'), ['#333333', '#FFFFFF']);
      expect(await first('hc-black'), ['#FFFFFF', '#000000']);
      expect(await first('hc-light'), ['#292929', '#FFFFFF']);
      // hcLight's editor.foreground defaults to the theme's `foreground`.
      expect(await first('hc-light', '{ "foreground": "#123456" }'), [
        '#123456',
        '#FFFFFF',
      ]);
    });

    test('editor colors go through Color.fromHex', () async {
      Future<String?> foreground(String value) async {
        final theme = await loadTheme({
          't.json': '{ "colors": { "editor.foreground": "$value" } }',
        }, 't.json');
        return theme.tokenColors.first.settings.foreground;
      }

      expect(await foreground('red'), '#FF0000');
      expect(await foreground('#GGGGGG'), '#000000');
      expect(await foreground('#abcd'), '#AABBCCDD');
      expect(await foreground('#abc'), '#AABBCC');
      expect(await foreground('#12345680'), '#12345680');
      expect(await foreground('#123456ff'), '#123456');
    });

    test('malformed files are rejected', () async {
      Future<void> load(String content) =>
          loadTheme({'t.json': content}, 't.json');

      await expectLater(
        load('{ "colors": { } '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Problems parsing JSON theme file: Closing brace expected',
          ),
        ),
      );
      await expectLater(load('[]'), throwsFormatException);
      await expectLater(load('{ "colors": "x" }'), throwsFormatException);
      await expectLater(load('{ "tokenColors": 1 }'), throwsFormatException);
      await expectLater(
        load(
          '{ "semanticTokenColors": { "a": { "bold": true, "foreground": 1 } } }',
        ),
        throwsFormatException,
      );
      await expectLater(
        loadTheme({'t.json': '{ "include": "./missing.json" }'}, 't.json'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('fromExtensionTheme ids and labels', () {
      final theme = ColorThemeData.fromExtensionTheme(
        const IThemeExtensionPoint(id: '', path: './themes/9 x.json'),
        'x',
        extensionId: 'pub.ext',
      );
      expect(theme.id, 'vs-dark pub-ext-themes-9-x-json');
      expect(theme.label, '9 x.json');
      expect(theme.settingsId, '9 x.json');
      expect(theme.isLoaded, isFalse);
      expect(
        ColorThemeData.fromExtensionTheme(
          const IThemeExtensionPoint(
            id: 'a',
            path: '1.json',
            uiTheme: 'hc-light',
          ),
          'x',
          extensionId: '',
        ).id,
        'hc-light _-1-json',
      );
    });
  });

  group('normalizeColor', () {
    test('as upstream', () {
      expect(normalizeColor(null), isNull);
      expect(normalizeColor(''), isNull);
      expect(normalizeColor('#abc'), '#AABBCC');
      expect(normalizeColor('#abcf'), '#AABBCC');
      expect(normalizeColor('#abce'), '#AABBCCEE');
      expect(normalizeColor('#a1b2c3'), '#A1B2C3');
      expect(normalizeColor('#a1b2c3FF'), '#A1B2C3');
      expect(normalizeColor('#a1b2c380'), '#A1B2C380');
      expect(normalizeColor('#a1b2c'), isNull);
      expect(normalizeColor('#a1b2cg'), isNull);
      expect(normalizeColor('a1b2c3'), isNull);
      expect(normalizeColor(Color.fromHex('#FfEeDd')), '#FFEEDD');
      expect(normalizeColor(Color(RGBA(1, 2, 3, 0.5))), '#01020380');
    });
  });

  group('plist parser', () {
    test('values', () {
      expect(
        plist.parse('''
<?xml version="1.0"?>
<!-- comment -->
<plist version="1.0"><dict>
  <key>s</key><string>a &lt;b&gt; &#65;&#x42;</string>
  <key>i</key><integer>42</integer>
  <key>r</key><real>1.5</real>
  <key>t</key><true/>
  <key>f</key><false/>
  <key>e</key><string/>
  <key>a</key><array><integer>1</integer><dict/></array>
</dict></plist>'''),
        {
          's': 'a <b> AB',
          'i': 42,
          'r': 1.5,
          't': true,
          'f': false,
          'e': '',
          'a': [1, <String, Object?>{}],
        },
      );
    });

    test('errors', () {
      expect(
        () => plist.parse('<dict><string>x</string></dict>'),
        throwsFormatException,
      );
      expect(() => plist.parse('<array></dict>'), throwsFormatException);
      expect(() => plist.parse('x'), throwsFormatException);
      expect(() => plist.parse('<integer>x</integer>'), throwsFormatException);
    });
  });
}
