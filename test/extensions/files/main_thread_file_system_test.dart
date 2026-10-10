import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/files/file_types.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/main_thread_harness.dart';

void main() {
  late Directory temp;
  late MainThreadHarness harness;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('bao-mt-files');
    harness = MainThreadHarness(folder: temp);
  });

  tearDown(() async {
    await harness.dispose();
    await temp.delete(recursive: true);
  });

  test(r'$stat, $readFile, $writeFile, $readdir answer the extension host',
      () async {
    await File('${temp.path}/a.txt').writeAsString('hello');

    final stat =
        (await harness.call(
              MainContext.mainThreadFileSystem,
              r'$stat',
              [VsUri.file('${temp.path}/a.txt').toJson()],
            ))!
            as Map;
    expect(stat['type'], FileType.file);
    expect(stat['size'], 5);
    expect(stat['mtime'], isA<num>());

    final buffer =
        (await harness.call(
              MainContext.mainThreadFileSystem,
              r'$readFile',
              [VsUri.file('${temp.path}/a.txt').toJson()],
            ))!
            as RpcBuffer;
    expect(utf8.decode(buffer.bytes), 'hello');

    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$writeFile',
      [
        VsUri.file('${temp.path}/b.txt').toJson(),
        RpcBuffer(Uint8List.fromList(utf8.encode('written'))),
      ],
    );
    expect(await File('${temp.path}/b.txt').readAsString(), 'written');

    final readdir =
        (await harness.call(
              MainContext.mainThreadFileSystem,
              r'$readdir',
              [VsUri.file(temp.path).toJson()],
            ))!
            as List;
    expect(
      {for (final e in readdir) (e as List)[0]: e[1]},
      {'a.txt': FileType.file, 'b.txt': FileType.file},
    );
  });

  test('a missing file fails with the file system error code', () async {
    await expectLater(
      harness.call(
        MainContext.mainThreadFileSystem,
        r'$stat',
        [VsUri.file('${temp.path}/nope').toJson()],
      ),
      throwsA(
        isA<RpcRemoteError>().having(
          (e) => e.name,
          'name',
          FileSystemProviderErrorCode.fileNotFound.value,
        ),
      ),
    );
    // Reading a folder is a folder, not a file.
    await Directory('${temp.path}/dir').create();
    await expectLater(
      harness.call(
        MainContext.mainThreadFileSystem,
        r'$readdir',
        [VsUri.file('${temp.path}/a.txt').toJson()],
      ),
      throwsA(isA<RpcRemoteError>()),
    );
  });

  test(r'$mkdir, $rename, $copy and $delete work on the disk', () async {
    await Directory('${temp.path}/dir').create();
    await File('${temp.path}/dir/a.txt').writeAsString('a');

    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$rename',
      [
        VsUri.file('${temp.path}/dir/a.txt').toJson(),
        VsUri.file('${temp.path}/dir/b.txt').toJson(),
        {'overwrite': false},
      ],
    );
    expect(File('${temp.path}/dir/b.txt').existsSync(), isTrue);

    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$copy',
      [
        VsUri.file('${temp.path}/dir').toJson(),
        VsUri.file('${temp.path}/copy').toJson(),
        {'overwrite': false},
      ],
    );
    expect(File('${temp.path}/copy/b.txt').readAsStringSync(), 'a');

    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$delete',
      [
        VsUri.file('${temp.path}/copy').toJson(),
        {'recursive': true, 'useTrash': false},
      ],
    );
    expect(Directory('${temp.path}/copy').existsSync(), isFalse);

    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$mkdir',
      [VsUri.file('${temp.path}/made/deep').toJson()],
    );
    expect(Directory('${temp.path}/made/deep').existsSync(), isTrue);
  });

  test('an extension\'s provider serves its scheme through the file service',
      () async {
    final provider = _ExtensionMemfs();
    harness.answer(
      ExtHostContext.extHostFileSystem,
      r'$stat',
      (args) async => provider.stat(VsUri.revive((args[1] as Map).cast())),
    );
    harness.answer(ExtHostContext.extHostFileSystem, r'$readdir', (args) async {
      final path = VsUri.revive((args[1] as Map).cast()).path;
      return [
        for (final name in provider.children(path)) [name, FileType.file],
      ];
    });
    harness.answer(ExtHostContext.extHostFileSystem, r'$readFile', (args) async {
      return RpcBuffer(
        Uint8List.fromList(utf8.encode(provider.read(VsUri.revive((args[1] as Map).cast()).path))),
      );
    });
    final writes = <String>[];
    harness.answer(ExtHostContext.extHostFileSystem, r'$writeFile', (args) async {
      writes.add(
        '${VsUri.revive((args[1] as Map).cast()).path}='
        '${utf8.decode((args[2] as RpcBuffer).bytes)}',
      );
      return null;
    });

    // `$registerFileSystemProvider` awaits the activation of
    // `onFileSystem:memfs`; the test's registration answers it.
    final registered = harness.registerProvider(
      5,
      'memfs',
      FileSystemProviderCapabilities.fileReadWrite,
    );
    harness.registered('memfs');
    await registered;

    expect(harness.files.hasProvider(VsUri('memfs', path: '/')), isTrue);
    expect(
      (await harness.files.stat(VsUri('memfs', path: '/a.txt'))).isFile,
      isTrue,
    );
    final resolved = await harness.files.resolve(VsUri('memfs', path: '/'));
    expect(resolved.children!.map((c) => c.name), ['a.txt']);
    expect(
      utf8.decode(await harness.files.readFile(VsUri('memfs', path: '/a.txt'))),
      'memfs!',
    );
    await harness.files.writeFile(
      VsUri('memfs', path: '/b.txt'),
      Uint8List.fromList(utf8.encode('x')),
    );
    expect(writes, ['/b.txt=x']);

    // Unregistering takes it away again.
    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$unregisterProvider',
      [5],
    );
    expect(harness.files.hasProvider(VsUri('memfs', path: '/')), isFalse);
  });

  test('an extension provider\'s changes reach the file service', () async {
    harness.answer(ExtHostContext.extHostFileSystem, r'$stat', (_) async {
      return {'type': FileType.file, 'size': 0};
    });
    final registered = harness.registerProvider(6, 'memfs', 0);
    harness.registered('memfs');
    await registered;

    final changes = <FileChange>[];
    final sub = harness.files.onDidFilesChange.listen(changes.addAll);
    addTearDown(sub.cancel);
    harness.files.watch(VsUri('memfs', path: '/a.txt'), const WatchOptions());
    await pumpEventQueue();
    await harness.call(
      MainContext.mainThreadFileSystem,
      r'$onFileSystemChange',
      [
        6,
        [
          {
            'resource': VsUri('memfs', path: '/a.txt').toJson(),
            'type': FileChangeType.updated.index,
          },
        ],
      ],
    );
    await harness.files.flushChanges();
    expect(changes.single.type, FileChangeType.updated);
  });

  test(r'$registerFileSystemProvider tells the extension host the provider info',
      () async {
    // The file service's own providers are announced when the actor is
    // made (`$acceptProviderInfos`).
    await pumpEventQueue();
    final infos = harness.callsTo(ExtHostContext.extHostFileSystemInfo.nid);
    expect(infos, isNotEmpty);
    final first = infos.first;
    expect(first.$1, r'$acceptProviderInfos');
    final uri = VsUri.revive((first.$2[0] as Map).cast());
    expect(uri.path, '/dummy');
    expect(first.$2[1], isA<num>());
  });
}

/// A tiny in-memory provider as an extension would register one.
final class _ExtensionMemfs {
  final files = <String, String>{'/a.txt': 'memfs!'};

  Iterable<String> children(String path) => [
    for (final key in files.keys)
      if (key.startsWith(path == '/' ? '/' : '$path/'))
        key.substring(path == '/' ? 1 : path.length + 1),
  ];

  String read(String path) => files[path]!;

  Map<String, Object?> stat(VsUri uri) {
    if (uri.path == '/') return {'type': FileType.directory};
    if (!files.containsKey(uri.path)) {
      throw StateError('ENOENT: ${uri.path}');
    }
    return {'type': FileType.file, 'size': files[uri.path]!.length};
  }
}
