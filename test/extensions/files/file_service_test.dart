import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/file_service.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mem_file_system.dart';

VsUri _uri(String path) => VsUri('memfs', path: path);

void main() {
  late MemFileSystemProvider memfs;
  late FileService service;
  late void Function() unregister;

  setUp(() {
    memfs = MemFileSystemProvider();
    service = FileService(batchDelay: Duration.zero);
    unregister = service.registerProvider('memfs', memfs);
  });

  tearDown(() {
    service.dispose();
    memfs.dispose();
  });

  test('stat maps the provider\'s stat', () async {
    memfs
      ..addDirectory('/dir')
      ..addFile('/dir/a.txt', 'hello');
    expect((await service.stat(_uri('/dir/a.txt'))).isFile, isTrue);
    expect((await service.stat(_uri('/dir/a.txt'))).size, 5);
    expect((await service.stat(_uri('/dir'))).isDirectory, isTrue);
    await expectLater(
      service.stat(_uri('/nope')),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileNotFound,
        ),
      ),
    );
  });

  test('resolve lists a folder\'s children, files and folders', () async {
    memfs
      ..addDirectory('/p')
      ..addDirectory('/p/sub')
      ..addFile('/p/a.txt', 'a')
      ..addFile('/p/sub/b.txt', 'b');
    final stat = await service.resolve(_uri('/p'));
    expect(stat.isDirectory, isTrue);
    expect(
      {for (final c in stat.children!) c.name: c.isDirectory},
      {'sub': true, 'a.txt': false},
    );
  });

  test('readFile and writeFile go through the provider', () async {
    memfs.addFile('/a.txt', 'hello');
    expect(utf8.decode(await service.readFile(_uri('/a.txt'))), 'hello');
    await service.writeFile(_uri('/a.txt'), Uint8List.fromList(utf8.encode('bye')));
    expect(utf8.decode(memfs.entries['/a.txt']!), 'bye');
  });

  test('writing makes the folders above a new file (mkdirp)', () async {
    await service.writeFile(
      _uri('/deep/er/a.txt'),
      Uint8List.fromList(utf8.encode('x')),
    );
    expect(memfs.entries.containsKey('/deep'), isTrue);
    expect(memfs.entries.containsKey('/deep/er'), isTrue);
    expect(utf8.decode(memfs.entries['/deep/er/a.txt']!), 'x');
  });

  test('writing a folder, or over a read-only provider, fails', () async {
    memfs.addDirectory('/dir');
    await expectLater(
      service.writeFile(_uri('/dir'), Uint8List(0)),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileIsDirectory,
        ),
      ),
    );
    final ro = MemFileSystemProvider(readonly: true)..addFile('/a.txt', 'a');
    final roService = FileService()..registerProvider('ro', ro);
    addTearDown(() {
      roService.dispose();
      ro.dispose();
    });
    await expectLater(
      roService.writeFile(VsUri('ro', path: '/a.txt'), Uint8List(0)),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.filePermissionDenied,
        ),
      ),
    );
  });

  test('move renames through one provider, and makes the target folders',
      () async {
    memfs.addFile('/a.txt', 'a');
    await service.move(_uri('/a.txt'), _uri('/sub/a.txt'));
    expect(memfs.entries.containsKey('/a.txt'), isFalse);
    expect(memfs.entries.containsKey('/sub'), isTrue);
    expect(utf8.decode(memfs.entries['/sub/a.txt']!), 'a');
  });

  test('move onto an existing file needs overwrite', () async {
    memfs
      ..addFile('/a.txt', 'a')
      ..addFile('/b.txt', 'b');
    await expectLater(
      service.move(_uri('/a.txt'), _uri('/b.txt')),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileMoveConflict,
        ),
      ),
    );
    await service.move(_uri('/a.txt'), _uri('/b.txt'), overwrite: true);
    expect(memfs.entries.containsKey('/a.txt'), isFalse);
    expect(utf8.decode(memfs.entries['/b.txt']!), 'a');
  });

  test('copy uses the provider\'s copy, or walks the tree without it', () async {
    memfs
      ..addDirectory('/dir/sub')
      ..addFile('/dir/a.txt', 'a')
      ..addFile('/dir/sub/b.txt', 'b');
    await service.copy(_uri('/dir'), _uri('/copy'));
    expect(utf8.decode(memfs.entries['/copy/a.txt']!), 'a');
    expect(utf8.decode(memfs.entries['/copy/sub/b.txt']!), 'b');

    // A provider without FileFolderCopy: every file is read and written.
    final slow = MemFileSystemProvider(canCopy: false)
      ..addFile('/a.txt', 'hello');
    final slowService = FileService()..registerProvider('slow', slow);
    addTearDown(() {
      slowService.dispose();
      slow.dispose();
    });
    await slowService.copy(VsUri('slow', path: '/a.txt'), VsUri('slow', path: '/b.txt'));
    expect(utf8.decode(slow.entries['/b.txt']!), 'hello');
  });

  test('copying a folder into itself is refused', () async {
    memfs.addDirectory('/dir');
    await expectLater(
      service.copy(_uri('/dir'), _uri('/dir/inner')),
      throwsA(isA<StateError>()),
    );
  });

  test('delete removes a tree, and needs recursion for a folder', () async {
    memfs
      ..addDirectory('/dir')
      ..addFile('/dir/a.txt', 'a');
    await expectLater(
      service.delete(_uri('/dir')),
      throwsA(isA<StateError>()),
    );
    await service.delete(_uri('/dir'), recursive: true);
    expect(memfs.entries.containsKey('/dir'), isFalse);
    await expectLater(
      service.delete(_uri('/dir')),
      throwsA(
        isA<FileOperationException>().having(
          (e) => e.result,
          'result',
          FileOperationResult.fileNotFound,
        ),
      ),
    );
  });

  test('delete to the trash asks the provider', () async {
    memfs.addFile('/a.txt', 'a');
    await service.delete(_uri('/a.txt'), useTrash: true);
    expect(memfs.trashed, ['/a.txt']);
  });

  test('a missing provider fails as ENOPRO, and activation joins', () async {
    var activated = <String>[];
    final stop = service.addActivator((scheme) async {
      activated.add(scheme);
      if (scheme == 'lazy') service.registerProvider(scheme, MemFileSystemProvider());
    });
    addTearDown(stop);
    expect(await service.canHandleResource(VsUri('lazy', path: '/x')), isTrue);
    expect(activated, ['lazy']);

    expect(service.hasProvider(_uri('/x')), isTrue);
    await expectLater(
      service.stat(VsUri('nothing', path: '/x')),
      throwsA(isA<NoFileSystemProviderException>()),
    );
  });

  test('cache: unregistering the provider makes it unknown', () async {
    unregister();
    await expectLater(
      service.stat(_uri('/a.txt')),
      throwsA(isA<NoFileSystemProviderException>()),
    );
  });

  test('watches report coalesced changes', () async {
    memfs.addDirectory('/dir');
    final seen = <List<FileChange>>[];
    final sub = service.onDidFilesChange.listen(seen.add);
    addTearDown(sub.cancel);
    final stop = service.watch(
      _uri('/dir'),
      const WatchOptions(recursive: true, excludes: [
        '**/node_modules',
      ]),
    );
    // Watches are registered once the provider is resolved.
    await pumpEventQueue();
    expect(memfs.watchOptions.single.recursive, isTrue);
    expect(memfs.watchOptions.single.excludes, ['**/node_modules']);

    // A create then a delete of the same path cancels out.
    memfs.fire([
      FileChange(_uri('/dir/tmp.txt'), FileChangeType.added),
      FileChange(_uri('/dir/tmp.txt'), FileChangeType.deleted),
    ]);
    await service.flushChanges();
    expect(seen, isEmpty);

    // A delete then a create is a change.
    memfs.fire([
      FileChange(_uri('/dir/a.txt'), FileChangeType.deleted),
      FileChange(_uri('/dir/a.txt'), FileChangeType.added),
    ]);
    await service.flushChanges();
    // Both are batched into one delivery (see FileService.batchDelay).
    await pumpEventQueue();
    expect(seen.length, 1);
    expect(seen.single.map((c) => c.type), [FileChangeType.updated]);

    stop();
  });

  test('a correlated watcher sees its own changes only', () async {
    memfs.addDirectory('/dir');
    final correlated = <List<FileChange>>[];
    final uncorrelated = <List<FileChange>>[];
    final sub = service.onDidFilesChange.listen(uncorrelated.add);
    addTearDown(sub.cancel);
    final stop = service.createWatcher(
      _uri('/dir'),
      const WatchOptions(),
      correlated.add,
    );
    await pumpEventQueue();
    memfs.fireCorrelated([
      FileChange(_uri('/dir/a.txt'), FileChangeType.added),
    ]);
    await service.flushChanges();
    expect(correlated.single.single.type, FileChangeType.added);
    expect(uncorrelated, isEmpty);
    stop();
  });

  test('coalesceFileChanges drops deletes under a deleted folder', () {
    final changes = coalesceFileChanges([
      FileChange(_uri('/dir/a.txt'), FileChangeType.deleted),
      FileChange(_uri('/dir'), FileChangeType.deleted),
      FileChange(_uri('/other.txt'), FileChangeType.added),
    ]);
    expect(
      [for (final c in changes) '${c.type.name} ${c.resource.path}'],
      ['deleted /dir', 'added /other.txt'],
    );
  });

  test('normalizeWatcherPattern makes relative patterns absolute', () {
    expect(normalizeWatcherPattern('/w', '**/x'), '**/x');
    expect(normalizeWatcherPattern('/w', 'node_modules'), (
      base: '/w',
      pattern: 'node_modules',
    ));
    final matches = parseGlob(
      normalizeWatcherPattern('/w', 'node_modules/**'),
    );
    expect(matches('/w/node_modules/x.js'), isTrue);
  });
}
