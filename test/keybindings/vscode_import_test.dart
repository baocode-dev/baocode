import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keymap.dart';
import 'package:baocode/keybindings/vscode_import.dart';
import 'package:baocode/settings/jsonc.dart';
import 'package:path/path.dart' as p;

import 'fake_home.dart';

void main() {
  late Directory home;
  late VsCodeInstalls installs;
  late String support;

  setUp(() async {
    home = await createFakeHome();
    installs = VsCodeInstalls(
      home: home.path,
      environment: {'HOME': home.path},
      platform: KeybindingPlatform.mac,
    );
    support = p.join(home.path, 'Library', 'Application Support');
  });

  tearDown(() => home.delete(recursive: true));

  bool isSupported(String command) => supportedCommands.contains(command);

  group('detection', () {
    test("finds each editor's keybindings and its profiles' own", () async {
      final sources = await installs.keybindingsSources();
      expect(
        [
          for (final source in sources)
            (source.product, source.profile, source.entryCount),
        ],
        [
          (VsCodeProduct.code, null, 5),
          (VsCodeProduct.code, 'Work', 2),
          (VsCodeProduct.cursor, null, 3),
        ],
      );
      expect(
        sources[0].path,
        p.join(support, 'Code', 'User', 'keybindings.json'),
      );
      expect(
        sources[1].path,
        p.join(
          support,
          'Code',
          'User',
          'profiles',
          '-5f3e2a1',
          'keybindings.json',
        ),
      );
      expect(sources[1].label, 'Visual Studio Code (Work)');
      expect(sources[2].label, 'Cursor');
    });

    test('a profile stored with a URI location', () async {
      final user = p.join(support, 'Code', 'User');
      final dir = p.join(home.path, 'elsewhere', 'profile');
      await Directory(dir).create(recursive: true);
      await File(p.join(dir, 'keybindings.json')).writeAsString('[]');
      await File(p.join(user, 'globalStorage', 'storage.json')).writeAsString(
        '{"userDataProfiles": ['
        '{"location": {"\$mid": 1, "path": "$dir", "scheme": "file"}, '
        '"name": "Moved"},'
        '{"location": "${Uri.file(dir)}", "name": "As string"}]}',
      );
      final profiles = [
        for (final source in await installs.keybindingsSources())
          if (source.product == VsCodeProduct.code)
            (source.profile, source.path),
      ];
      expect(profiles, [
        (null, p.join(user, 'keybindings.json')),
        ('Moved', p.join(dir, 'keybindings.json')),
        ('As string', p.join(dir, 'keybindings.json')),
      ]);
    });

    test('where each platform keeps user data and extensions', () {
      VsCodeInstalls on(KeybindingPlatform platform, Map<String, String> env) =>
          VsCodeInstalls(
            home: platform == KeybindingPlatform.windows
                ? r'C:\Users\leo'
                : '/home/leo',
            environment: env,
            platform: platform,
          );

      final windows = on(KeybindingPlatform.windows, {
        'APPDATA': r'C:\Users\leo\AppData\Roaming',
      });
      expect(
        windows.userDir(VsCodeProduct.cursor),
        r'C:\Users\leo\AppData\Roaming\Cursor\User',
      );
      expect(
        windows.extensionsDir(VsCodeProduct.code),
        r'C:\Users\leo\.vscode\extensions',
      );
      expect(
        on(KeybindingPlatform.windows, {
          'USERPROFILE': r'D:\leo',
        }).userDataDir(VsCodeProduct.insiders),
        r'D:\leo\AppData\Roaming\Code - Insiders',
      );

      expect(
        on(KeybindingPlatform.linux, {}).userDir(VsCodeProduct.vscodium),
        '/home/leo/.config/VSCodium/User',
      );
      expect(
        on(KeybindingPlatform.linux, {
          'XDG_CONFIG_HOME': '/xdg',
        }).userDir(VsCodeProduct.windsurf),
        '/xdg/Windsurf/User',
      );
      expect(
        on(KeybindingPlatform.linux, {}).extensionsDir(VsCodeProduct.vscodium),
        '/home/leo/.vscode-oss/extensions',
      );
      expect(
        on(KeybindingPlatform.mac, {
          'VSCODE_APPDATA': '/data',
        }).userDataDir(VsCodeProduct.code),
        '/data/Code',
      );
    });

    test('Linux: a home with ~/.config', () async {
      final config = p.join(home.path, '.config', 'Code', 'User');
      await Directory(config).create(recursive: true);
      await File(p.join(config, 'keybindings.json'))
          .writeAsString(codeKeybindings);
      final linux = VsCodeInstalls(
        home: home.path,
        platform: KeybindingPlatform.linux,
      );
      final sources = await linux.keybindingsSources();
      expect(sources.single.path, p.join(config, 'keybindings.json'));
      expect(sources.single.entryCount, 5);
    });

    test('nothing installed', () async {
      final empty = await Directory.systemTemp.createTemp('baocode_empty_');
      addTearDown(() => empty.delete(recursive: true));
      final detection = await VsCodeInstalls(
        home: empty.path,
        platform: KeybindingPlatform.mac,
      ).detect();
      expect(detection.sources, isEmpty);
      expect(detection.keymaps, isEmpty);
      expect(detection.importable, isFalse);
    });
  });

  group('keymap extensions', () {
    test('found in every editor, the newest not obsolete one', () async {
      final keymaps = await installs.keymapExtensions();
      expect(
        [
          for (final keymap in keymaps)
            (keymap.id, keymap.name, keymap.version),
        ],
        [
          ('ms-vscode.atom-keybindings', 'Atom Keymap', '3.3.0'),
          ('acme.emacs-keymap', 'Emacs Keymap', '1.2.0'),
        ],
      );
      final atom = keymaps.first;
      expect(atom.products, [VsCodeProduct.code, VsCodeProduct.cursor]);
      expect(atom.entryCount, 2);
      expect(
        p.basename(atom.path),
        startsWith('ms-vscode.atom-keybindings-3.3.0'),
      );
      expect(keymaps.last.products, [VsCodeProduct.cursor]);
      expect(keymaps.last.entryCount, 1);
    });

    test('a built-in one is not written, only reported', () async {
      final keymapsDir = p.join(home.path, 'baocode', 'keymaps');
      final catalog = KeymapCatalog(
        keymapsDir: keymapsDir,
        bundle: _DiskBundle(),
      );
      final atom = (await installs.keymapExtensions()).first;
      final result = await importKeymapExtension(atom, catalog);
      expect(result.builtIn, isTrue);
      expect(result.id, 'ms-vscode.atom-keybindings');
      expect(result.name, 'Atom');
      expect(result.path, isNull);
      expect(Directory(keymapsDir).existsSync(), isFalse);
    });

    test('another is written in the keymap format, and listed', () async {
      final keymapsDir = p.join(home.path, 'baocode', 'keymaps');
      final catalog = KeymapCatalog(
        keymapsDir: keymapsDir,
        bundle: _DiskBundle(),
      );
      final emacs = (await installs.keymapExtensions()).last;
      final result = await importKeymapExtension(emacs, catalog);
      expect(result.builtIn, isFalse);
      expect(result.path, p.join(keymapsDir, 'acme.emacs-keymap.json'));
      expect(parseJsonc(File(result.path!).readAsStringSync()), {
        'id': 'acme.emacs-keymap',
        'name': 'Emacs Keymap',
        'version': '1.2.0',
        'keybindings': [
          {
            'key': 'ctrl+x ctrl+s',
            'command': 'workbench.action.files.save',
            'emacs': 'save-buffer',
          },
        ],
      });

      final loaded = (await catalog.load('acme.emacs-keymap'))!;
      expect(loaded.builtIn, isFalse);
      expect(loaded.entries, [
        const KeybindingEntry(
          command: 'workbench.action.files.save',
          key: 'ctrl+x ctrl+s',
        ),
      ]);
      expect(
        [for (final keymap in await catalog.list()) keymap.id],
        [...KeymapCatalog.builtInIds, 'acme.emacs-keymap'],
      );
    });
  });

  group('importing keybindings', () {
    late String target;

    setUp(
      () => target = p.join(home.path, 'baocode', 'User', 'keybindings.json'),
    );

    String cursor() => p.join(support, 'Cursor', 'User', 'keybindings.json');
    String code() => p.join(support, 'Code', 'User', 'keybindings.json');

    test('replace: a verbatim copy, ours backed up', () async {
      const ours = '// mine\n[{"key": "cmd+k", "command": "a.b"}]\n';
      await File(target).create(recursive: true);
      await File(target).writeAsString(ours);

      final report = await importKeybindings(
        source: cursor(),
        target: target,
        mode: KeybindingsImportMode.replace,
        isSupported: isSupported,
      );
      expect(File(target).readAsStringSync(), cursorKeybindings);
      expect(report.backupPath, '$target.bak');
      expect(File('$target.bak').readAsStringSync(), ours);

      // The report: the command the app lacks is kept all the same.
      expect(report.total, 3);
      expect(report.supported, 2);
      expect(report.unsupported, [
        const KeybindingEntry(
          command: 'workbench.action.toggleAgentsFromKeyboard',
          key: 'cmd+3',
          when: '!isAuxiliaryWindowFocusedContext',
        ),
      ]);
      expect(
        File(target).readAsStringSync(),
        contains('workbench.action.toggleAgentsFromKeyboard'),
      );
    });

    test('replace: nothing to back up', () async {
      final report = await importKeybindings(
        source: code(),
        target: target,
        mode: KeybindingsImportMode.replace,
        isSupported: isSupported,
      );
      expect(report.backupPath, isNull);
      expect(File('$target.bak').existsSync(), isFalse);
      expect(File(target).readAsStringSync(), codeKeybindings);
      expect((report.total, report.supported), (5, 5));
    });

    test('merge: appends what ours lacks, keeping our comments', () async {
      await importKeybindings(
        source: code(),
        target: target,
        mode: KeybindingsImportMode.replace,
        isSupported: isSupported,
      );
      final report = await importKeybindings(
        source: cursor(),
        target: target,
        mode: KeybindingsImportMode.merge,
        isSupported: isSupported,
      );
      // navigateBack and toggleSidebarVisibility Code has already.
      expect(report.total, 3);
      expect(report.duplicates, 2);
      expect(report.backupPath, isNull);
      expect(
        [for (final entry in report.unsupported) entry.command],
        ['workbench.action.toggleAgentsFromKeyboard'],
      );

      final text = File(target).readAsStringSync();
      expect(
        [
          for (final entry in KeybindingEntry.listFromJson(parseJsonc(text)))
            (entry.key, entry.command),
        ],
        [
          ('cmd+e', 'workbench.action.navigateBack'),
          ('shift+cmd+e', 'workbench.action.navigateForward'),
          ('cmd+1', 'workbench.action.toggleSidebarVisibility'),
          ('cmd+2', 'workbench.action.terminal.toggleTerminal'),
          ('cmd+3', 'workbench.action.toggleAuxiliaryBar'),
          ('cmd+3', 'workbench.action.toggleAgentsFromKeyboard'),
        ],
      );
      // Code's text is untouched up to the entry appended, indented as it.
      expect(text, startsWith(codeKeybindings.substring(0, 300)));
      expect(
        text,
        contains(
          '\n  {\n    "key": "cmd+3",\n    "command": '
          '"workbench.action.toggleAgentsFromKeyboard"',
        ),
      );

      // Again: all there already.
      final again = await importKeybindings(
        source: cursor(),
        target: target,
        mode: KeybindingsImportMode.merge,
        isSupported: isSupported,
      );
      expect(again.duplicates, 3);
      expect(File(target).readAsStringSync(), text);
    });

    test('merge: into a file with comments only, or none', () async {
      await File(target).create(recursive: true);
      await File(target).writeAsString('// mine\n');
      await importKeybindings(
        source: cursor(),
        target: target,
        mode: KeybindingsImportMode.merge,
        isSupported: isSupported,
      );
      final text = File(target).readAsStringSync();
      expect(text, startsWith('// mine\n'));
      expect(KeybindingEntry.listFromJson(parseJsonc(text)), hasLength(3));

      await File(target).delete();
      final report = await importKeybindings(
        source: p.join(
          support,
          'Code',
          'User',
          'profiles',
          '-5f3e2a1',
          'keybindings.json',
        ),
        target: target,
        mode: KeybindingsImportMode.merge,
        isSupported: isSupported,
      );
      final created = File(target).readAsStringSync();
      expect(created, startsWith('// Place your key bindings in this file'));
      final entries = KeybindingEntry.listFromJson(parseJsonc(created));
      expect(entries, hasLength(2));
      // A removal is supported when its command is.
      expect(entries.last.command, '-editor.action.addCommentLine');
      expect(report.unsupported, isEmpty);
    });

    test('merge: not into a file with errors, or not an array', () async {
      await File(target).create(recursive: true);
      for (final ours in ['[{"key": "cmd+k"', '{"key": "cmd+k"}']) {
        await File(target).writeAsString(ours);
        await expectLater(
          importKeybindings(
            source: code(),
            target: target,
            mode: KeybindingsImportMode.merge,
            isSupported: isSupported,
          ),
          throwsA(isA<KeybindingsImportException>()),
        );
        expect(File(target).readAsStringSync(), ours);
      }
    });

    test('the report', () {
      final report = keybindingsImportReport(const [
        KeybindingEntry(command: 'a.supported', key: 'cmd+a'),
        KeybindingEntry(command: '-a.supported', key: 'cmd+b'),
        KeybindingEntry(command: '-b.missing', key: 'cmd+c'),
        KeybindingEntry(command: 'b.missing'),
      ], (command) => command == 'a.supported');
      expect((report.total, report.supported), (4, 2));
      expect(
        [for (final entry in report.unsupported) entry.command],
        ['-b.missing', 'b.missing'],
      );
    });
  });

  group('first-launch offer', () {
    test('when there is something to import, once', () async {
      final store = _MemoryStore();
      final detection = await installs.detect();
      expect(detection.importable, isTrue);
      expect(shouldOfferKeybindingsImport(detection, store), isTrue);

      await markKeybindingsImportOffered(store);
      expect(store.values, {keybindingsImportOfferedKey: true});
      expect(shouldOfferKeybindingsImport(detection, store), isFalse);
    });

    test('not when nothing was found', () {
      final store = _MemoryStore();
      expect(
        shouldOfferKeybindingsImport(const KeybindingsDetection(), store),
        isFalse,
      );
      // Only empty keybindings files: nothing to import either.
      final empty = KeybindingsDetection(
        sources: [
          KeybindingsSource(
            product: VsCodeProduct.code,
            path: p.join(support, 'Code', 'User', 'keybindings.json'),
            entryCount: 0,
          ),
        ],
      );
      expect(shouldOfferKeybindingsImport(empty, store), isFalse);
    });
  });
}

class _MemoryStore implements ImportOfferStore {
  final values = <String, Object?>{};

  @override
  Object? get(String key) => values[key];

  @override
  void set(String key, Object? value) => values[key] = value;
}

/// The assets as the repository has them.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(await File(key).readAsBytes());
}
