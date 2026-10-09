// The extension runtime's download and install (goal: 三.5; acceptance 7:
// an interrupted download completes when tried again).

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_runtime.dart';

void main() {
  late FakeRuntimeServer server;
  late Directory temp;
  late String dir;
  final archive = fakeTarGz();
  const platform = 'darwin-arm64';

  setUp(() async {
    server = await FakeRuntimeServer.start();
    server.files['runtime-$platform.tar.gz'] = archive;
    temp = await Directory.systemTemp.createTemp('exthost-runtime-test-');
    dir = p.join(temp.path, 'exthost');
  });

  tearDown(() async {
    await server.close();
    await temp.delete(recursive: true);
  });

  ExtHostRuntimeInstaller installer({
    ExtHostRuntimeManifest? manifest,
    Map<String, String> environment = const {},
    int attempts = 1,
    Duration staleAfter = const Duration(hours: 1),
  }) => ExtHostRuntimeInstaller(
    manifest:
        manifest ?? fakeManifest({platform: archive}, baseUrl: server.baseUrl),
    directory: dir,
    environment: environment,
    attempts: attempts,
    backoff: (_) => Duration.zero,
    staleAfter: staleAfter,
  );

  /// What is in the runtimes' folder.
  List<String> left() => Directory(dir).existsSync()
      ? [for (final e in Directory(dir).listSync()) p.basename(e.path)]
      : const [];

  bool executable(String path) =>
      Platform.isWindows || File(path).statSync().mode & 0x40 != 0;

  test('downloads, checks, unpacks and keeps the runtime', () async {
    final progress = <RuntimeProgress>[];
    final runtime = await installer().ensure(
      platform: platform,
      onProgress: progress.add,
    );
    expect(runtime.root, p.join(dir, '$fakeVersion-abcdef12'));
    expect(runtime.id, '$fakeVersion-abcdef12');
    expect(runtime.productCommit, fakeCommit);
    expect(runtime.productVersion, fakeVersion);
    expect(runtime.quality, 'stable');
    expect(runtime.nodeExecutable, p.join(runtime.root, 'node'));
    expect(File(runtime.serverMain).existsSync(), isTrue);
    expect(File(runtime.productJson).existsSync(), isTrue);
    expect(executable(runtime.nodeExecutable), isTrue);
    expect(executable(p.join(runtime.root, 'bin', 'baocode-server')), isTrue);
    expect(
      executable(
        p.join(runtime.root, 'node_modules/native/build/Release/native.node'),
      ),
      isTrue,
    );
    expect(
      File(p.join(runtime.root, ExtHostRuntimeInstaller.markerFile))
          .existsSync(),
      isTrue,
    );
    // Only the version folder: no temporary file or folder left.
    expect(left(), ['$fakeVersion-abcdef12']);
    expect(progress.first.phase, RuntimePhase.downloading);
    expect(
      progress.map((p) => p.phase),
      containsAllInOrder([
        RuntimePhase.downloading,
        RuntimePhase.verifying,
        RuntimePhase.extracting,
      ]),
    );
    expect(
      progress.where((p) => p.phase == RuntimePhase.downloading).last.received,
      archive.length,
    );

    // Kept: the next run downloads nothing, and finds it without asking.
    final again = installer();
    expect((await again.installed(platform: platform))?.root, runtime.root);
    expect((await again.ensure(platform: platform)).root, runtime.root);
    expect(server.requests, hasLength(1));
  });

  test('refuses a download whose SHA-256 differs, keeping nothing', () async {
    final manifest = fakeManifest(
      {platform: archive},
      baseUrl: server.baseUrl,
      sha256Override: '0' * 64,
    );
    await expectLater(
      installer(manifest: manifest, attempts: 3).ensure(platform: platform),
      throwsA(
        isA<ExtHostRuntimeException>().having(
          (e) => e.kind,
          'kind',
          ExtHostRuntimeErrorKind.verification,
        ),
      ),
    );
    // Not tried again: the same file would come.
    expect(server.requests, hasLength(1));
    expect(left(), isEmpty);
    expect(
      await installer(manifest: manifest).installed(platform: platform),
      isNull,
    );
  });

  test('refuses a download of another size', () async {
    final manifest = fakeManifest(
      {platform: archive},
      baseUrl: server.baseUrl,
      sizeOverride: archive.length + 1,
    );
    await expectLater(
      installer(manifest: manifest).ensure(platform: platform),
      throwsA(
        isA<ExtHostRuntimeException>().having(
          (e) => e.kind,
          'kind',
          ExtHostRuntimeErrorKind.verification,
        ),
      ),
    );
    expect(left(), isEmpty);
  });

  test('an interrupted download leaves nothing behind; trying again '
      'installs (acceptance 7)', () async {
    server.plan
      ..clear()
      ..addAll([Serve.half, Serve.whole]);
    await expectLater(
      installer().ensure(platform: platform),
      throwsA(
        isA<ExtHostRuntimeException>()
            .having((e) => e.kind, 'kind', ExtHostRuntimeErrorKind.network)
            .having((e) => e.transient, 'transient', isTrue),
      ),
    );
    expect(left(), isEmpty);
    final runtime = await installer().ensure(platform: platform);
    expect(File(runtime.serverMain).existsSync(), isTrue);
    expect(left(), ['$fakeVersion-abcdef12']);
    expect(server.requests, hasLength(2));
  });

  test('retries a dropped download and a 503 by itself', () async {
    server.plan
      ..clear()
      ..addAll([Serve.half, Serve.unavailable, Serve.whole]);
    final runtime = await installer(attempts: 3).ensure(platform: platform);
    expect(File(runtime.nodeExecutable).existsSync(), isTrue);
    expect(server.requests, hasLength(3));
    expect(left(), ['$fakeVersion-abcdef12']);
  });

  test('does not retry a 404', () async {
    server.plan
      ..clear()
      ..add(Serve.missing);
    await expectLater(
      installer(attempts: 4).ensure(platform: platform),
      throwsA(
        isA<ExtHostRuntimeException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.transient, 'transient', isFalse),
      ),
    );
    expect(server.requests, hasLength(1));
    expect(left(), isEmpty);
  });

  test('callers at the same time share one install', () async {
    server.gate = Completer<void>();
    final shared = installer();
    final first = <RuntimeProgress>[];
    final second = <RuntimeProgress>[];
    final a = shared.ensure(platform: platform, onProgress: first.add);
    final b = shared.ensure(platform: platform, onProgress: second.add);
    // Both see the download under way before it completes.
    while (first.isEmpty || second.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    server.gate!.complete();
    final [one, two] = await Future.wait([a, b]);
    expect(one.root, two.root);
    expect(server.requests, hasLength(1));
    expect(first.last.phase, RuntimePhase.extracting);
    expect(second.last.phase, RuntimePhase.extracting);
  });

  test('a cancelled install stops and keeps nothing', () async {
    server.gate = Completer<void>();
    final source = CancellationTokenSource();
    final progress = <RuntimeProgress>[];
    final install = installer().ensure(
      platform: platform,
      onProgress: progress.add,
      cancellationToken: source.token,
    );
    // The download started, its first half in, the rest held back.
    while (progress.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    source.cancel();
    await expectLater(install, throwsA(isA<CancellationException>()));
    server.gate!.complete();
    // The download's clean-up runs as the install unwinds.
    for (var i = 0; i < 100 && left().isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(left(), isEmpty);
  });

  test('$platform with no build is refused', () async {
    await expectLater(
      installer().ensure(platform: 'linux-x64'),
      throwsA(
        isA<ExtHostRuntimeException>().having(
          (e) => e.kind,
          'kind',
          ExtHostRuntimeErrorKind.unsupportedPlatform,
        ),
      ),
    );
    expect(server.requests, isEmpty);
  });

  test('BAOCODE_EXTHOST_BASE_URL replaces the manifest\'s baseUrl', () async {
    // Nothing listens on the manifest's own address.
    final manifest = fakeManifest({
      platform: archive,
    }, baseUrl: 'http://127.0.0.1:9/nowhere/');
    final runtime = await installer(
      manifest: manifest,
      environment: {
        ExtHostRuntimeInstaller.baseUrlVariable: server.baseUrl.substring(
          0,
          server.baseUrl.length - 1, // without its slash
        ),
      },
    ).ensure(platform: platform);
    expect(File(runtime.serverMain).existsSync(), isTrue);
    expect(server.requests, ['runtime-$platform.tar.gz']);
  });

  test('BAOCODE_EXTHOST_DIR is used as it is, nothing downloaded', () async {
    final own = Directory(p.join(temp.path, 'dev-runtime'));
    for (final MapEntry(key: path, value: (content, _))
        in fakeRuntimeFiles().entries) {
      File(p.join(own.path, path))
        ..createSync(recursive: true)
        ..writeAsBytesSync(content);
    }
    final environment = {ExtHostRuntimeInstaller.directoryVariable: own.path};
    final runtime = await installer(environment: environment)
        .ensure(platform: platform);
    expect(runtime.root, own.path);
    expect(runtime.id, isNull);
    expect(runtime.productCommit, fakeCommit);
    expect(
      (await installer(environment: environment).installed(platform: platform))
          ?.root,
      own.path,
    );
    expect(server.requests, isEmpty);
    expect(left(), isEmpty);

    // Not a runtime: said so.
    await expectLater(
      installer(
        environment: {
          ExtHostRuntimeInstaller.directoryVariable: p.join(temp.path, 'none'),
        },
      ).ensure(platform: platform),
      throwsA(
        isA<ExtHostRuntimeException>().having(
          (e) => e.kind,
          'kind',
          ExtHostRuntimeErrorKind.layout,
        ),
      ),
    );
  });

  test('removes what killed installs left, and replaces a version folder '
      'that is not whole', () async {
    final id = '$fakeVersion-abcdef12';
    Directory(p.join(dir, 'old.tmp-1234-abc', 'node_modules'))
        .createSync(recursive: true);
    File(p.join(dir, '$id.download-1234-abc')).writeAsStringSync('partial');
    // No marker: never a whole install.
    File(p.join(dir, id, 'product.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    final runtime = await installer(staleAfter: Duration.zero)
        .ensure(platform: platform);
    expect(left(), [id]);
    expect(runtime.productCommit, fakeCommit);
  });

  test('keeps another process\'s recent temporary files', () async {
    final recent = p.join(dir, 'x.tmp-99999-abc');
    Directory(recent).createSync(recursive: true);
    await installer().ensure(platform: platform);
    expect(Directory(recent).existsSync(), isTrue);
  });

  test('installs a Windows runtime from its ZIP', () async {
    final zip = p.join(temp.path, 'runtime.zip');
    fakeZip(zip);
    final bytes = File(zip).readAsBytesSync();
    server.files['runtime-win32-x64.zip'] = bytes;
    final runtime = await installer(
      manifest: fakeManifest({'win32-x64': bytes}, baseUrl: server.baseUrl),
    ).ensure(platform: 'win32-x64');
    expect(runtime.windows, isTrue);
    expect(runtime.nodeExecutable, p.join(runtime.root, 'node.exe'));
    expect(File(runtime.nodeExecutable).existsSync(), isTrue);
    expect(runtime.productVersion, fakeVersion);
  });
}
