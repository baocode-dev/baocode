// The files the agent read found by the paths it names them by, those
// paths gone wrong too.

import 'package:baocode/chat/side_panel/file_link.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _root = '/Users/me/Desktop';
const _read = '/Users/me/Documents/app/lib/chat/step_folds.dart';

void main() {
  /// The scope of a conversation in [_root] whose agent read [_read].
  FileOpenScope scope(List<FileOpenRequest> opened) => FileOpenScope(
    root: _root,
    onOpen: opened.add,
    existence: FileExistence((path) async => path == _read),
    seen: const [_read],
    child: const SizedBox(),
  );

  test('a path relative to another folder opens the file read', () async {
    final opened = <FileOpenRequest>[];
    final files = scope(opened);
    expect(
      files.openLink(
        FileLink(
          'Documents/app/lib/chat/step_folds.dart',
          FileLineRange(12, 27),
        ),
      ),
      isTrue,
    );
    await pumpEventQueue();
    expect(opened.single.path, _read);
    expect(opened.single.range, FileLineRange(12, 27));
    // Known now: it resolves there at once.
    expect(files.resolve('app/lib/chat/step_folds.dart'), _read);
  });

  test('a file read outside the project opens by its absolute path', () {
    final files = scope([]);
    expect(files.resolve(_read), _read);
    expect(files.resolve('../Documents/app/lib/chat/step_folds.dart'), _read);
    expect(files.resolve('/Users/me/Documents/other.dart'), isNull);
    expect(files.resolve('../Documents/other.dart'), isNull);
  });

  test('only whole names match, and only files read', () async {
    final files = scope([]);
    await pumpEventQueue();
    expect(files.resolve('_folds.dart'), '$_root/_folds.dart');
    expect(files.resolve('lib/other/step_folds.dart'), isNot(_read));
  });
}
