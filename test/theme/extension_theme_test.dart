// Color themes of extensions (`contributes.themes`): listed with the
// bundled ones, applied from their files, and a kept one waits for the
// extensions before falling back (goal 九.2: a theme from Open VSX).

import 'dart:io';

import 'package:baocode/theme/workbench_theme.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory extension;

  setUp(() {
    extension = Directory.systemTemp.createTempSync('theme-ext');
    Directory(p.join(extension.path, 'themes')).createSync();
    File(p.join(extension.path, 'themes', 'base.json'))
        .writeAsStringSync('{"colors": {"editor.foreground": "#112233"}}');
    File(p.join(extension.path, 'themes', 'acme.json')).writeAsStringSync('''
{
  // Comments, as theme files have them.
  "include": "./base.json",
  "colors": {"editor.background": "#abcdef"},
  "tokenColors": [{"scope": "comment", "settings": {"foreground": "#00ff00"}}]
}''');
  });

  tearDown(() => extension.deleteSync(recursive: true));

  List<({String extensionId, String location, Map<String, Object?> theme})>
  themes() => [
    (
      extensionId: 'acme.theme',
      location: extension.path,
      theme: {
        'id': 'Acme Dark',
        'label': 'Acme Dark',
        'uiTheme': 'vs-dark',
        'path': './themes/acme.json',
      },
    ),
  ];

  test('an extension\'s theme is listed and applies from its file', () async {
    final service = WorkbenchThemeService()..restore(setting: 'Bao Dark');
    await service.initialize();
    await service.setExtensionThemes(themes());
    expect(
      service.colorThemes.map((theme) => theme.id),
      containsAll(['Bao Dark', 'Acme Dark']),
    );

    await service.setColorTheme('Acme Dark');
    expect(service.colorThemeId, 'Acme Dark');
    expect(service.colorTheme.isLoaded, isTrue);
    expect(service.colors['editor.background'], const Color(0xffabcdef));
    // Its include's colors too.
    expect(service.colors['editor.foreground'], const Color(0xff112233));
  });

  test(
    'a kept extension theme waits for the extensions, then applies',
    () async {
      final service = WorkbenchThemeService()
        ..waitsForExtensionThemes = true
        ..restore(setting: 'Acme Dark');
      await service.initialize();
      expect(service.colorThemeId, 'Acme Dark');
      expect(service.colorTheme.isLoaded, isFalse);

      await service.setExtensionThemes(themes());
      expect(service.colorTheme.settingsId, 'Acme Dark');
      expect(service.colorTheme.isLoaded, isTrue);
    },
  );

  test('a kept extension theme no longer installed falls back', () async {
    final service = WorkbenchThemeService()
      ..waitsForExtensionThemes = true
      ..restore(setting: 'Acme Dark');
    await service.initialize();
    await service.setExtensionThemes(const []);
    expect(service.colorTheme.settingsId, 'Bao Dark');
  });
}
