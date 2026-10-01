import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:baocode/keybindings/keymap.dart';
import 'package:path/path.dart' as p;

void main() {
  group('built-in keymap assets', () {
    final files = [
      for (final file in Directory('assets/keymaps').listSync())
        if (file is File && file.path.endsWith('.json')) file,
    ];

    test('are the catalog\'s, each with its license', () {
      expect({
        for (final file in files) p.basenameWithoutExtension(file.path),
      }, KeymapCatalog.builtInIds.toSet());
      for (final id in KeymapCatalog.builtInIds) {
        final license = File('assets/keymaps/LICENSES/$id.md');
        expect(license.readAsStringSync(), contains('MIT License'), reason: id);
      }
      expect(
        File('pubspec.yaml').readAsStringSync(),
        allOf(
          contains('- assets/keymaps/\n'),
          contains('- assets/keymaps/LICENSES/\n'),
        ),
      );
    });

    for (final id in KeymapCatalog.builtInIds) {
      test('$id parses, with an id, a name and keybindings', () {
        final json = jsonDecode(
          File(KeymapCatalog.assetPath(id)).readAsStringSync(),
        ) as Map<String, Object?>;
        expect(json['id'], id);
        expect(
          json['name'],
          isA<String>().having((n) => n, 'name', isNotEmpty),
        );
        expect(json['version'], matches(RegExp(r'^\d+\.\d+\.\d+$')));
        final keybindings = json['keybindings'] as List;
        final keymap = Keymap.fromJson(json, builtIn: true)!;
        expect(keymap.id, id);
        // Every one an entry; all but a few with a key (IntelliJ's
        // `intellij.openInOppositeGroup` has none, as upstream).
        expect(keymap.entries, hasLength(keybindings.length));
        expect(keymap.entries, isNotEmpty);
        final unbound = keymap.entries.where(
          (entry) =>
              entry.keyFor(KeybindingPlatform.mac) == null &&
              entry.keyFor(KeybindingPlatform.windows) == null,
        );
        expect(unbound.length, lessThan(2), reason: '$unbound');
      });
    }

    test('names', () {
      String name(String id) =>
          (jsonDecode(File(KeymapCatalog.assetPath(id)).readAsStringSync())
              as Map)['name'];
      expect(name('ms-vscode.atom-keybindings'), 'Atom');
      expect(name('k--kato.intellij-idea-keybindings'), 'IntelliJ IDEA');
      expect(name('ms-vscode.sublime-keybindings'), 'Sublime Text');
    });
  });

  group('KeymapCatalog', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('keymaps_'));
    tearDown(() => dir.delete(recursive: true));

    test('lists the bundled keymaps (as pubspec.yaml bundles them)', () async {
      final catalog = KeymapCatalog(keymapsDir: p.join(dir.path, 'none'));
      final keymaps = await catalog.list();
      expect([
        for (final keymap in keymaps) keymap.id,
      ], KeymapCatalog.builtInIds);
      expect(keymaps.every((keymap) => keymap.builtIn), isTrue);
      final atom = (await catalog.load('MS-VSCode.atom-keybindings'))!;
      expect(atom.name, 'Atom');
      expect(atom.version, '3.3.0');
      expect(atom.entries, hasLength(72));
    });

    test('and the imported ones, by name', () async {
      final catalog = KeymapCatalog(
        keymapsDir: dir.path,
        bundle: _Bundle({
          for (final id in KeymapCatalog.builtInIds)
            KeymapCatalog.assetPath(id): jsonEncode({
              'id': id,
              'name': id,
              'keybindings': [],
            }),
        }),
      );
      await catalog.write(
        id: 'b.zed',
        name: 'Zed',
        keybindings: [
          {'key': 'cmd+k', 'command': 'z', 'extra': 1},
        ],
      );
      await catalog.write(
        id: 'a.vim',
        name: 'Vim',
        version: '1.0.0',
        keybindings: [],
      );
      // Not listed: a built-in's id, not an id, not a keymap, not JSON.
      File(p.join(dir.path, 'ms-vscode.atom-keybindings.json'))
          .writeAsStringSync('{"name": "Mine", "keybindings": []}');
      File(p.join(dir.path, 'no id.json')).writeAsStringSync('{}');
      File(p.join(dir.path, 'x.list.json')).writeAsStringSync('[]');
      File(p.join(dir.path, 'x.text.json')).writeAsStringSync('nope {');
      File(p.join(dir.path, 'notes.txt')).writeAsStringSync('');

      final keymaps = await catalog.list();
      expect(
        [for (final keymap in keymaps) keymap.name],
        [...KeymapCatalog.builtInIds, 'Vim', 'Zed'],
      );
      final zed = (await catalog.load('b.zed'))!;
      expect(zed.builtIn, isFalse);
      expect(zed.version, isNull);
      expect(zed.entries, [const KeybindingEntry(command: 'z', key: 'cmd+k')]);
      // The file keeps what the extension had.
      expect(
        jsonDecode(File(catalog.importedPath('b.zed')).readAsStringSync()),
        {
          'id': 'b.zed',
          'name': 'Zed',
          'keybindings': [
            {'key': 'cmd+k', 'command': 'z', 'extra': 1},
          ],
        },
      );
      expect(
        (await catalog.load('ms-vscode.atom-keybindings'))!.builtIn,
        isTrue,
      );
      expect(await catalog.load('none.here'), isNull);
      expect(await catalog.load('../escape'), isNull);
      expect(
        () => catalog.write(id: '../x', name: 'x', keybindings: []),
        throwsArgumentError,
      );
    });
  });

  test('Keymap JSON', () {
    const keymap = Keymap(
      id: 'a.b',
      name: 'AB',
      version: '2.0.0',
      entries: [KeybindingEntry(command: 'c', key: 'cmd+c', when: 'w')],
    );
    expect(keymap.toJson(), {
      'id': 'a.b',
      'name': 'AB',
      'version': '2.0.0',
      'keybindings': [
        {'key': 'cmd+c', 'command': 'c', 'when': 'w'},
      ],
    });
    final read = Keymap.fromJson(keymap.toJson())!;
    expect((read.id, read.name, read.version), ('a.b', 'AB', '2.0.0'));
    expect(read.entries, keymap.entries);
    expect(Keymap.fromJson({'id': 'a.b', 'keybindings': []})!.name, 'a.b');
    expect(Keymap.fromJson({'id': 'a.b'}), isNull);
    expect(Keymap.fromJson({'name': 'x', 'keybindings': []}), isNull);
    expect(Keymap.fromJson([]), isNull);
    expect(isKeymapId('k--kato.intellij-idea-keybindings'), isTrue);
    expect(isKeymapId('a/b.c'), isFalse);
  });
}

class _Bundle extends CachingAssetBundle {
  _Bundle(this.assets);

  final Map<String, String> assets;

  @override
  Future<ByteData> load(String key) async {
    final text = assets[key];
    if (text == null) throw StateError('No asset $key');
    return ByteData.sublistView(utf8.encode(text));
  }
}
