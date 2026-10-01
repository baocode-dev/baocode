import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/workspace/preference_store.dart';

void main() {
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
