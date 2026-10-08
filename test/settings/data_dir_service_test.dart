@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/data_dir.dart';
import 'package:baocode/settings/data_dir_service.dart';
import 'package:path/path.dart' as p;

/// Moving the data folder copies only the app's own entries, points the
/// next run at the copy last, and later removes only the app's entries
/// from the old folder. Every folder is a temporary one.
void main() {
  late Directory root;
  late String home;
  late String current;

  setUp(() {
    root = Directory.systemTemp.createTempSync('baocode-move');
    home = p.join(root.path, 'home');
    current = p.join(root.path, 'current');
    Directory(home).createSync();
    // The app's data, beside the web view's (Chromium's) files.
    for (final (path, text) in [
      ('User/settings.json', '{"workbench.colorTheme": "Abyss"}'),
      ('User/keybindings.json', '[]'),
      ('argv.json', '{"locale": "zh-cn"}'),
      ('keymaps/vim.json', '{}'),
      ('state/state.json', '{"kernel": "claude"}'),
      ('state/storage.json', '{}'),
      ('state/claude-processes.json', '[{"pid": 1, "parent": 2}]'),
      ('state/lsp-processes.json.12.3.tmp', '[]'),
      ('servers/tool/bin/tool', '#!/bin/sh'),
      ('language-packs/toy/manifest.json', '{}'),
      ('checkpoints/app-1f/HEAD', 'ref: refs/heads/main'),
      ('cache/claude-sessions.json', '{}'),
      ('icons/index.json', '[]'),
      ('workspaces/w1/web.code-workspace', '{"folders": []}'),
      ('Cookies', 'chromium'),
      ('GPUCache/data_0', 'chromium'),
      ('Local Storage/leveldb/LOG', 'chromium'),
      ('preferences.json', '{"old": true}'),
    ]) {
      File(p.join(current, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(text);
    }
    // A server's link into its own folder, as installers make.
    Link(p.join(current, 'servers', 'tool-link'))
        .createSync(p.join(current, 'servers', 'tool', 'bin', 'tool'));
  });
  tearDown(() {
    Process.runSync('chmod', ['-R', 'u+rwX', root.path]);
    root.deleteSync(recursive: true);
  });

  DataDirectoryService service([String? path]) => DataDirectoryService(
    current: DataDirectory(path ?? current),
    environment: {'HOME': home},
    home: home,
  );

  String folder(String name, {List<String> files = const []}) {
    final path = p.join(root.path, name);
    Directory(path).createSync(recursive: true);
    for (final file in files) {
      File(p.join(path, file))
        ..createSync(recursive: true)
        ..writeAsStringSync('');
    }
    return path;
  }

  List<String> tree(String path) => [
    for (final entity in Directory(
      path,
    ).listSync(recursive: true, followLinks: false))
      p.relative(entity.path, from: path),
  ]..sort();

  File pointer() => File(p.join(home, '.baocode', 'config-dir.json'));

  group('check', () {
    test(
      'an empty folder, one with BaoCode data, one with other files',
      () async {
        expect(
          (await service().check(folder('empty', files: ['.DS_Store'])))
              .contents,
          DataDirectoryContents.empty,
        );
        expect(
          (await service().check(
            folder('baocode', files: ['User/settings.json']),
          )).contents,
          DataDirectoryContents.baocodeData,
        );
        expect(
          (await service().check(folder('argv', files: ['argv.json'])))
              .contents,
          DataDirectoryContents.baocodeData,
        );
        expect(
          (await service().check(folder('other', files: ['notes.txt'])))
              .contents,
          DataDirectoryContents.other,
        );
      },
    );

    test('not the folder in use, inside it, or around it', () async {
      for (final path in [
        current,
        p.join(current, 'User'),
        root.path,
        '$current/',
      ]) {
        final target = await service().check(path);
        expect(target.ok, isFalse, reason: path);
        expect(target.contents, isNull);
      }
      // A link to it is it.
      final link = p.join(root.path, 'link');
      Link(link).createSync(current);
      expect((await service().check(link)).ok, isFalse);
    });

    test('a folder that is missing, relative or read-only', () async {
      expect((await service().check(p.join(root.path, 'gone'))).ok, isFalse);
      expect((await service().check('relative/path')).ok, isFalse);
      final readOnly = folder('read-only');
      Process.runSync('chmod', ['555', readOnly]);
      final target = await service().check(readOnly);
      expect(target.error, contains('cannot be written'));
      // Made when asked (the default place may not be there yet).
      final made = p.join(root.path, 'made', 'baocode');
      expect((await service().check(made, create: true)).ok, isTrue);
      expect(Directory(made).existsSync(), isTrue);
    });
  });

  test('migrate copies only the app\'s entries, and points the next run '
      'there last', () async {
    final target = folder('target', files: ['notes.txt']);
    final progress = <(int, int)>[];
    final moving = service();
    await moving.migrate(target, onProgress: (d, t) => progress.add((d, t)));

    expect(tree(target), [
      'User',
      'User/keybindings.json',
      'User/settings.json',
      'argv.json',
      'cache',
      'cache/claude-sessions.json',
      'checkpoints',
      'checkpoints/app-1f',
      'checkpoints/app-1f/HEAD',
      'icons',
      'icons/index.json',
      'keymaps',
      'keymaps/vim.json',
      'language-packs',
      'language-packs/toy',
      'language-packs/toy/manifest.json',
      'notes.txt',
      'servers',
      'servers/tool',
      'servers/tool-link',
      'servers/tool/bin',
      'servers/tool/bin/tool',
      'state',
      'state/state.json',
      'state/storage.json',
      'workspaces',
      'workspaces/w1',
      'workspaces/w1/web.code-workspace',
    ]);
    expect(
      File(p.join(target, 'User', 'settings.json')).readAsStringSync(),
      '{"workbench.colorTheme": "Abyss"}',
    );
    // The link points into the copy.
    expect(
      Link(p.join(target, 'servers', 'tool-link')).targetSync(),
      p.join(target, 'servers', 'tool', 'bin', 'tool'),
    );
    expect(progress.first, (0, 12));
    expect(progress.last, (12, 12));
    // The old folder is as it was: the web view's files included.
    expect(File(p.join(current, 'Cookies')).existsSync(), isTrue);
    expect(File(p.join(current, 'state', 'state.json')).existsSync(), isTrue);

    expect(jsonDecode(pointer().readAsStringSync()), {
      'dataDir': target,
      'previousDataDir': current,
    });
    expect(moving.pendingPath, target);
    final next = resolveDataDirectory(environment: {'HOME': home}, home: home);
    expect((next.ok, next.path), (true, target));
  });

  test(
    'a copy that fails is taken back, and the pointer not written',
    () async {
      final target = folder('target');
      final unreadable = File(
        p.join(current, 'servers', 'tool', 'bin', 'tool'),
      );
      Process.runSync('chmod', ['000', unreadable.path]);
      await expectLater(service().migrate(target), throwsA(anything));
      expect(tree(target), isEmpty);
      expect(pointer().existsSync(), isFalse);
    },
  );

  test('a folder with BaoCode data is used as it is', () async {
    final target = folder('target', files: ['User/settings.json']);
    await service().useAsIs(target);
    expect(tree(target), ['User', 'User/settings.json']);
    expect(jsonDecode(pointer().readAsStringSync()), {
      'dataDir': target,
      'previousDataDir': current,
    });
  });

  test('back to the default: the pointer keeps only the folder moved '
      'from', () async {
    final moving = service();
    final target = await moving.check(moving.defaultPath, create: true);
    expect(target.contents, DataDirectoryContents.empty);
    await moving.migrate(target.path);
    expect(jsonDecode(pointer().readAsStringSync()), {
      'previousDataDir': current,
    });
    expect(
      resolveDataDirectory(environment: {'HOME': home}, home: home).source,
      DataDirectorySource.defaultLocation,
    );
  });

  test('the old folder loses only the app\'s entries', () async {
    final target = folder('target');
    await service().migrate(target);

    // The next run, in the new folder.
    final next = service(target);
    expect(next.previousDirectory, current);
    expect(DataDirectoryService.leftoverItems(current), DataDirectory.items);
    await next.removeOldData(current);
    expect(tree(current), [
      'Cookies',
      'GPUCache',
      'GPUCache/data_0',
      'Local Storage',
      'Local Storage/leveldb',
      'Local Storage/leveldb/LOG',
      'preferences.json',
    ]);
    expect(next.previousDirectory, isNull);
    expect(jsonDecode(pointer().readAsStringSync()), {'dataDir': target});
    // The folder in use is never removed.
    expect(() => next.removeOldData(target), throwsArgumentError);
  });

  test('keeping the old data forgets it; an invalid pointer is left '
      'alone', () async {
    final target = folder('target');
    await service().migrate(target);
    await service(target).forgetPrevious();
    expect(service(target).previousDirectory, isNull);
    expect(tree(current), contains('User/settings.json'));

    pointer().writeAsStringSync('oops');
    await service(target).forgetPrevious();
    expect(pointer().readAsStringSync(), 'oops');
  });
}
