import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/preference_store.dart';
import 'package:baocode/workspace/workspace.dart';

void main() {
  test('a file not written fails its write, the next tried', () async {
    final folder = await Directory.systemTemp.createTemp(
      'baocode-prefs-failure',
    );
    addTearDown(() => folder.delete(recursive: true));
    final parent = File('${folder.path}/parent');
    await parent.writeAsString('阻止创建子目录');
    final store = PreferenceStore.file('${parent.path}/preferences.json');
    await expectLater(
      store.write({'first': 1}),
      throwsA(isA<FileSystemException>()),
    );
    final workspace = Workspace(preferences: store);
    addTearDown(workspace.dispose);
    await workspace.load();
    await expectLater(
      workspace.storeColorTheme(
        setting: 'Bao Light',
        autoDetectColorScheme: true,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(workspace.colorThemeSetting, isNull);
    expect(workspace.autoDetectColorScheme, isFalse);
    await parent.delete();
    await store.write({'second': 2});
    expect(await store.read(), {'second': 2});
  });

  test('preferences written to a file are read back; none, or a broken '
      'file, reads as none', () async {
    final folder = await Directory.systemTemp.createTemp('baocode-prefs');
    addTearDown(() => folder.delete(recursive: true));
    final path = '${folder.path}/nested/preferences.json';
    final store = PreferenceStore.file(path);
    expect(await store.read(), isEmpty);

    await store.write({'first': 1});
    await store.write({
      'settings': {'model': 'opus'},
    });
    expect(await PreferenceStore.file(path).read(), {
      'settings': {'model': 'opus'},
    });

    await File(path).writeAsString('{not json');
    expect(await store.read(), isEmpty);
  });
}
