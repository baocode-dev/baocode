@TestOn('mac-os || linux || windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/ide/file_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// This machine's files: bytes written to a new file (a pasted picture),
/// never over one.
void main() {
  late Directory project;
  late IdeFileService files;

  setUp(() {
    project = Directory.systemTemp.createTempSync('baocode-write-bytes-');
    files = IdeFileService(project.path);
  });
  tearDown(() => project.deleteSync(recursive: true));

  String at(String name) => p.join(project.path, name);

  test('a new file of the bytes', () async {
    final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));
    await files.writeBytes(at('shot.png'), bytes);
    expect(File(at('shot.png')).readAsBytesSync(), bytes);
  });

  test('never over a file, nor a folder', () async {
    File(at('taken.png')).writeAsBytesSync([7]);
    Directory(at('folder.png')).createSync();
    for (final name in ['taken.png', 'folder.png']) {
      await expectLater(
        files.writeBytes(at(name), Uint8List.fromList([1])),
        throwsA(isA<IdeFileExistsException>()),
      );
    }
    expect(File(at('taken.png')).readAsBytesSync(), [7]);
  });

  test('in a folder that is not there, it fails and leaves nothing', () async {
    await expectLater(
      files.writeBytes(at('none/a.png'), Uint8List.fromList([1])),
      throwsA(anything),
    );
    expect(Directory(at('none')).existsSync(), isFalse);
  });
}
