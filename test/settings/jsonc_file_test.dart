import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:path/path.dart' as p;

/// Settings files read leniently, kept up to date as they change on disk,
/// and changed in place. Every file is in a temporary folder.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('baocode-jsonc-file'));
  tearDown(() => dir.deleteSync(recursive: true));

  String path(String name) => p.join(dir.path, name);

  /// Waits (a while) for [condition], which the file watcher makes true.
  Future<void> eventually(bool Function() condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a missing file is null; a broken one keeps the last good value '
      'and says why', () async {
    final file = JsoncFile(path('settings.json'));
    addTearDown(file.dispose);
    var notified = 0;
    file.addListener(() => notified++);

    await file.load();
    expect((file.value, file.error, file.loaded), (null, null, true));

    File(file.path).writeAsStringSync('{\n  // mine\n  "a": 1,\n}');
    await file.load();
    expect(file.value, {'a': 1});
    expect(file.error, isNull);
    expect(notified, 1);

    File(file.path).writeAsStringSync('{\n  "a": 2\n  "b": 3\n}');
    await file.load();
    expect(file.value, {'a': 1});
    expect(file.error, 'Comma expected at line 3, column 3');
    expect(notified, 2);

    // Unchanged on disk: nothing to hear.
    await file.load();
    expect(notified, 2);

    File(file.path).writeAsStringSync('{"a": 2, "b": 3}');
    await file.load();
    expect(file.value, {'a': 2, 'b': 3});
    expect(file.error, isNull);
    expect(notified, 3);

    File(file.path).deleteSync();
    await file.load();
    expect((file.value, file.error), (null, null));
  });

  test('edits keep comments, are heard once, and make a missing file and '
      'its folder', () async {
    final file = JsoncFile(path('User/keybindings.json'));
    addTearDown(file.dispose);
    var notified = 0;
    file.addListener(() => notified++);

    await file.edit([-1], {'key': 'cmd+k', 'command': 'a'}, insert: true);
    expect(
      File(file.path).readAsStringSync(),
      '[\n    {\n        "key": "cmd+k",\n        "command": "a"\n    }\n]',
    );
    expect(notified, 1);

    File(file.path).writeAsStringSync(
      '// Mine\n[\n  // first\n  {"key": "cmd+k", "command": "a"}\n]\n',
    );
    await file.load();
    await file.edit([-1], {'key': 'cmd+j', 'command': 'b'}, insert: true);
    await file.edit([0], null, remove: true);
    expect(
      File(file.path).readAsStringSync(),
      '// Mine\n[\n  // first\n  {\n    "key": "cmd+j",\n    "command": "b"\n  }\n]\n',
    );
    expect(file.value, [
      {'key': 'cmd+j', 'command': 'b'},
    ]);
    expect(await file.readText(), File(file.path).readAsStringSync());
    expect(
      dir.listSync(recursive: true).where((e) => e.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('a file that does not parse is not edited', () async {
    final file = JsoncFile(path('settings.json'));
    addTearDown(file.dispose);
    File(file.path).writeAsStringSync('{"a": }');
    await expectLater(
      file.edit(['b'], 1),
      throwsA(
        isA<JsoncFileException>().having(
          (e) => e.message,
          'message',
          contains('Value expected'),
        ),
      ),
    );
    expect(File(file.path).readAsStringSync(), '{"a": }');
    expect(file.error, isNotNull);
    await expectLater(
      JsoncFile(path('list.json'))
          .writeText('[]')
          .then((_) => JsoncFile(path('list.json')).edit(['a'], 1)),
      throwsA(isA<JsoncFileException>()),
    );
  });

  test(
    'transform reads and writes in one step, between other changes',
    () async {
      final file = JsoncFile(path('keybindings.json'));
      addTearDown(file.dispose);
      File(file.path).writeAsStringSync('// mine\n[]');
      // Started together: neither loses the other's change.
      await Future.wait([
        file.edit([-1], 'a', insert: true),
        file.transform((text) => text!.replaceFirst(']', '  , "b"\n]')),
        file.edit([-1], 'c', insert: true),
      ]);
      expect(file.value, ['a', 'b', 'c']);
      expect(File(file.path).readAsStringSync(), startsWith('// mine\n'));
      // Nothing returned, or the same text: nothing written.
      final before = File(file.path).lastModifiedSync();
      await file.transform((_) => null);
      await file.transform((text) => text);
      expect(File(file.path).lastModifiedSync(), before);
      // A missing file is null to it.
      final missing = JsoncFile(path('missing.json'));
      addTearDown(missing.dispose);
      String? seen = '';
      await missing.transform((text) => seen = text);
      expect(seen, isNull);
      expect(File(missing.path).existsSync(), isFalse);
    },
  );

  test('watching hears changes made on disk, not its own', () async {
    final file = JsoncFile(
      path('settings.json'),
      debounce: const Duration(milliseconds: 20),
    );
    addTearDown(file.dispose);
    await file.load();
    file.watch();
    var notified = 0;
    file.addListener(() => notified++);

    // Changes made by another program.
    File(file.path).writeAsStringSync('{"a": 1}');
    await eventually(() => file.value != null);
    expect(file.value, {'a': 1});

    File(file.path).writeAsStringSync('{"a": 1,, }');
    await eventually(() => file.error != null);
    expect(file.value, {'a': 1});

    File(file.path).writeAsStringSync('{"a": 2}');
    await eventually(() => file.error == null);
    expect(file.value, {'a': 2});

    // Its own write, seen by the watcher too, is heard once.
    final before = notified;
    await file.edit(['a'], 3);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(notified, before + 1);
    expect(file.value, {'a': 3});
  });

  test('a file linked elsewhere is written there, the link kept', () async {
    final target = File(path('dotfiles/settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    final link = Link(path('User/settings.json'))
      ..createSync(target.path, recursive: true);
    final file = JsoncFile(link.path);
    addTearDown(file.dispose);
    await file.edit(['a'], true);
    expect(FileSystemEntity.isLinkSync(link.path), isTrue);
    expect(target.readAsStringSync(), '{\n    "a": true\n}');
  });

  group('settings', () {
    test('UserSettings: set, change and remove a setting', () async {
      final settings = UserSettings(path('User/settings.json'));
      addTearDown(settings.dispose);
      await settings.load();
      expect(settings['workbench.colorTheme'], isNull);
      await settings.update('workbench.colorTheme', 'Monokai');
      await settings.update('editor.fontSize', 14);
      await settings.update('workbench.colorTheme', 'Abyss');
      expect(settings.values, {
        'workbench.colorTheme': 'Abyss',
        'editor.fontSize': 14,
      });
      await settings.update('editor.fontSize', null);

      final again = UserSettings(settings.path);
      addTearDown(again.dispose);
      await again.load();
      expect(again.values, {'workbench.colorTheme': 'Abyss'});
    });

    test('ArgvSettings: the locale, read before the first frame', () async {
      final argv = ArgvSettings(path('argv.json'));
      addTearDown(argv.dispose);
      argv.loadSync();
      expect(argv.locale, isNull);
      await argv.setLocale('zh-cn');
      expect(argv.read(), 'zh-cn');

      File(argv.path).writeAsStringSync(
        '// BaoCode reads this first.\n{\n  "locale": "en", // English\n}\n',
      );
      final next = ArgvSettings(argv.path)..loadSync();
      addTearDown(next.dispose);
      expect(next.locale, 'en');
      await next.write(null);
      expect(
        File(argv.path).readAsStringSync(),
        '// BaoCode reads this first.\n{\n}\n',
      );
      expect(next.locale, isNull);
    });

    test('GlobalStorage keeps small values', () async {
      final storage = GlobalStorage(path('state/storage.json'));
      addTearDown(storage.dispose);
      await storage.load();
      expect(storage.get<bool>('keybindingsImportOffered'), isNull);
      await storage.set('keybindingsImportOffered', true);
      expect(storage.get<bool>('keybindingsImportOffered'), isTrue);
      expect(storage.get<String>('keybindingsImportOffered'), isNull);
      await storage.set('keybindingsImportOffered', null);
      expect(storage.get<bool>('keybindingsImportOffered'), isNull);
    });

    test('SettingsFiles: where each file is, and which are broken', () async {
      final files = SettingsFiles(DataDirectory(dir.path));
      addTearDown(files.dispose);
      expect(files.settings.path, p.join(dir.path, 'User', 'settings.json'));
      expect(
        files.keybindings.path,
        p.join(dir.path, 'User', 'keybindings.json'),
      );
      expect(files.argv.path, p.join(dir.path, 'argv.json'));
      expect(files.storage.path, p.join(dir.path, 'state', 'storage.json'));
      File(files.keybindings.path)
        ..createSync(recursive: true)
        ..writeAsStringSync('[');
      var changes = 0;
      files.changes.addListener(() => changes++);
      await files.load();
      expect(files.broken, [files.keybindings]);
      expect(changes, greaterThan(0));
    });
  });

  test('the color theme setting is kept in settings.json, its colors in '
      'state; a setting changed in the file applies', () async {
    final files = SettingsFiles(DataDirectory(dir.path));
    addTearDown(files.dispose);
    final store = MemoryPreferenceStore();
    final workspace = Workspace(preferences: store);
    addTearDown(workspace.dispose);
    await workspace.load();
    final storage = ColorThemeSettings(
      settings: files.settings,
      state: workspace,
    );
    addTearDown(storage.dispose);
    final themes = WorkbenchThemeService.instance
      ..restore(
        setting: storage.colorThemeSetting,
        data: storage.colorThemeData,
      )
      ..storage = storage;
    storage.follow(themes);

    // The default theme, kept as the app starts, is not written.
    await themes.initialize();
    expect(File(files.settings.path).existsSync(), isFalse);

    await themes.setColorTheme('Red');
    await eventually(() => files.settings['workbench.colorTheme'] == 'Red');
    expect(store.preferences['colorThemeData'], isA<String>());

    await files.settings.writeText('{\n  "workbench.colorTheme": "Abyss"\n}');
    await eventually(() => themes.colorThemeId == 'Abyss');
    expect(
      File(files.settings.path).readAsStringSync(),
      '{\n  "workbench.colorTheme": "Abyss"\n}',
    );

    // Removed: the default theme.
    await files.settings.writeText('{}');
    await eventually(
      () => themes.colorThemeId == ThemeSettingDefaults.colorThemeDark,
    );
  });
}
