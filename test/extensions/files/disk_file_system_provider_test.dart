import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/disk_file_system_provider_io.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late DiskFileSystemProvider disk;
  late FileService service;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bao-files');
    disk = DiskFileSystemProvider();
    service = FileService(batchDelay: Duration.zero)
      ..registerProvider('file', disk);
  });

  tearDown(() async {
    service.dispose();
    disk.dispose();
    await temp.delete(recursive: true);
  });

  VsUri uri(String path) => VsUri.file(path);

  String path(String name) => p.join(temp.path, name);

  test('stat, readdir, read and write round-trip', () async {
    await File(path('a.txt')).writeAsString('hello');
    await Directory(path('sub')).create();
    await File(path('sub/b.txt')).writeAsString('b');

    final stat = await service.stat(uri(path('a.txt')));
    expect(stat.isFile, isTrue);
    expect(stat.size, 5);
    expect(stat.mtime, greaterThan(0));
    expect((await service.stat(uri(path('sub')))).isDirectory, isTrue);

    final entries = await service.resolve(uri(temp.path));
    expect(
      {for (final c in entries.children!) c.name: c.isDirectory},
      {'a.txt': false, 'sub': true},
    );
    expect(
      utf8.decode(await service.readFile(uri(path('sub/b.txt')))),
      'b',
    );

    await service.writeFile(
      uri(path('sub/c.txt')),
      Uint8List.fromList(utf8.encode('c')),
    );
    expect(await File(path('sub/c.txt')).readAsString(), 'c');

    // Writing makes the folders above a new file.
    await service.writeFile(
      uri(path('made/up/d.txt')),
      Uint8List.fromList(utf8.encode('d')),
    );
    expect(await File(path('made/up/d.txt')).readAsString(), 'd');
  });

  test('missing files and folders fail with the file system codes', () async {
    await expectLater(
      service.stat(uri(path('nope'))),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileNotFound,
        ),
      ),
    );
    await expectLater(
      service.resolve(uri(path('nope'))),
      throwsA(isA<FileOperationException>()),
    );
    await expectLater(
      service.readFile(uri(path('nope'))),
      throwsA(isA<FileOperationException>()),
    );
    // A folder is not a file.
    await Directory(path('dir')).create();
    await expectLater(
      service.readFile(uri(path('dir'))),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileIsDirectory,
        ),
      ),
    );
  });

  test('move, copy and delete on the disk', () async {
    await File(path('a.txt')).writeAsString('a');
    await Directory(path('dir')).create();
    await File(path('dir/x.txt')).writeAsString('x');

    await service.move(uri(path('a.txt')), uri(path('b.txt')));
    expect(File(path('a.txt')).existsSync(), isFalse);
    expect(await File(path('b.txt')).readAsString(), 'a');

    await service.copy(uri(path('dir')), uri(path('copy')));
    expect(await File(path('copy/x.txt')).readAsString(), 'x');

    await service.delete(uri(path('copy')), recursive: true);
    expect(Directory(path('copy')).existsSync(), isFalse);

    // A non-empty folder needs `recursive`.
    await expectLater(
      service.delete(uri(path('dir'))),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      service.move(uri(path('b.txt')), uri(path('dir/x.txt'))),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileMoveConflict,
        ),
      ),
    );
  });

  test('delete can use the Trash given', () async {
    final trashed = <String>[];
    final withTrash = DiskFileSystemProvider(
      trash: (path) async => trashed.add(path),
    );
    final s = FileService()..registerProvider('file', withTrash);
    addTearDown(() {
      s.dispose();
      withTrash.dispose();
    });
    await File(path('a.txt')).writeAsString('a');
    addTearDown(() async {
      final f = File(path('a.txt'));
      if (await f.exists()) await f.delete();
    });
    await s.delete(uri(path('a.txt')), useTrash: true);
    expect(trashed, [path('a.txt')]);
  });

  test('watching reports a file written beside a watched one', () async {
    await Directory(path('w')).create();
    final changes = <FileChange>[];
    final sub = service.onDidFilesChange.listen(changes.addAll);
    addTearDown(sub.cancel);
    final stop = service.watch(
      uri(path('w')),
      const WatchOptions(recursive: true),
    );
    await pumpEventQueue();
    await File(path('w/a.txt')).writeAsString('a');
    // The watcher's own delay, then the service's batch.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await service.flushChanges();
    expect(
      changes.map((c) => p.basename(c.resource.fsPath())),
      contains('a.txt'),
    );
    stop();
  }, skip: !FileSystemEntity.isWatchSupported);
}
