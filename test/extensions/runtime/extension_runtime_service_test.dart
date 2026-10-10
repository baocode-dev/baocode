// The extension runtime as the app gets it (goal: 三.5): the service's
// states while it is downloaded and installed, the status bar entry, and
// the shipped manifest against runtime_version.dart.
//
// BAOCODE_EXTHOST_SCREENS=<dir> writes the status bar while downloading
// to <dir>/runtime_downloading.png (build/exthost-screens/ by convention).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bao_exthost/bao_exthost.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/extensions/runtime/runtime_status_item.dart';
import 'package:baocode/extensions/runtime/runtime_version.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/remote_exthost.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/theme/workbench_theme.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _platform = 'linux-x64';

/// A runtime's files, gzipped as a tar.
List<int> _runtimeArchive() {
  final bytes = BytesBuilder(copy: false);
  final tar = TarWriter(_Sink(bytes), mtime: 1700000000);
  final files = {
    'node': '#!/bin/sh\n',
    'out/server-main.js': 'console.log(1)\n',
    'product.json': jsonEncode({'version': '9.9.9', 'commit': 'c' * 40}),
    // Big enough for progress along the way.
    'node_modules/blob.bin': String.fromCharCodes(
      List.generate(400000, (i) => 32 + (i * 7919) % 90),
    ),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    tar.addFile(key, utf8.encode(value), mode: key == 'node' ? 0x1ED : 0x1A4);
  }
  tar.close();
  return gzip.encode(bytes.takeBytes());
}

final class _Sink implements Sink<List<int>> {
  _Sink(this._bytes);

  final BytesBuilder _bytes;

  @override
  void add(List<int> data) => _bytes.add(data);

  @override
  void close() {}
}

void main() {
  late Directory temp;
  late List<int> archive;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exthost-service-test-');
    archive = _runtimeArchive();
  });

  tearDown(() => temp.delete(recursive: true));

  /// A manifest whose archive is a file in the mirror folder (a `file:`
  /// base URL: no network, and no HTTP the test binding would stub).
  String manifest() => jsonEncode({
    'version': '9.9.9',
    'id': '9.9.9-abcdef12',
    'productCommit': 'c' * 40,
    'upstreamVersion': '1.0.0',
    'upstreamCommit': 'd' * 40,
    'nodeVersion': '24.0.0',
    'baseUrl': Uri.directory(p.join(temp.path, 'mirror')).toString(),
    'platforms': {
      _platform: {
        'file': 'runtime.tar.gz',
        'size': archive.length,
        'sha256': sha256.convert(archive).toString(),
      },
    },
  });

  ExtensionRuntimeService service() => ExtensionRuntimeService(
    loadManifest: () async => manifest(),
    directory: p.join(temp.path, 'exthost'),
    platform: _platform,
    installer: (manifest, directory) => ExtHostRuntimeInstaller(
      manifest: manifest,
      directory: directory,
      environment: const {},
      attempts: 1,
    ),
  );

  void putArchive() => File(p.join(temp.path, 'mirror', 'runtime.tar.gz'))
    ..createSync(recursive: true)
    ..writeAsBytesSync(archive);

  test(
    'absent, downloading, installing, ready; found ready next time',
    () async {
      putArchive();
      final runtimes = service();
      expect(await runtimes.refresh(), isNull);
      expect(runtimes.state, isA<ExtensionRuntimeAbsent>());

      final states = <ExtensionRuntimeState>[];
      runtimes.addListener(() => states.add(runtimes.state));
      final first = runtimes.ensureReady();
      // Callers at the same time share it.
      expect(identical(runtimes.ensureReady(), first), isTrue);
      expect(runtimes.busy, isTrue);
      final runtime = await first;
      expect(runtimes.busy, isFalse);
      expect(runtime.productVersion, '9.9.9');
      expect(runtime.root, p.join(temp.path, 'exthost', '9.9.9-abcdef12'));
      expect(runtimes.runtime, same(runtime));

      expect(states.first, isA<ExtensionRuntimeDownloading>());
      final downloads = states
          .whereType<ExtensionRuntimeDownloading>()
          .toList();
      expect(downloads.length, greaterThan(1));
      expect(downloads.last.received, archive.length);
      expect(downloads.last.fraction, 1.0);
      final installing = states.indexWhere(
        (s) => s is ExtensionRuntimeInstalling,
      );
      expect(installing, greaterThan(states.lastIndexOf(downloads.last)));
      expect(states.last, isA<ExtensionRuntimeReady>());
      // Not one repaint per chunk.
      expect(states.length, lessThan(1100));

      // Ready at once from then on, and for the next run.
      expect(await runtimes.ensureReady(), same(runtime));
      final next = service();
      expect((await next.refresh())?.root, runtime.root);
      expect(next.state, isA<ExtensionRuntimeReady>());
    },
  );

  test('failed, then tried again', () async {
    final runtimes = service();
    // No archive at the mirror yet.
    await expectLater(
      runtimes.ensureReady(),
      throwsA(isA<ExtHostRuntimeException>()),
    );
    expect(runtimes.state, isA<ExtensionRuntimeFailed>());
    expect(runtimes.busy, isFalse);
    expect(Directory(p.join(temp.path, 'exthost')).listSync(), isEmpty);

    putArchive();
    final runtime = await runtimes.ensureReady();
    expect(runtimes.state, isA<ExtensionRuntimeReady>());
    expect(File(runtime.serverMain).existsSync(), isTrue);
  });

  test('a broken manifest fails, said so', () async {
    final runtimes = ExtensionRuntimeService(
      loadManifest: () async => '{',
      directory: p.join(temp.path, 'exthost'),
      platform: _platform,
    );
    await expectLater(runtimes.ensureReady(), throwsFormatException);
    expect(runtimes.state, isA<ExtensionRuntimeFailed>());
  });

  test('the shipped manifest is the runtime runtime_version.dart pins', () {
    final manifest = ExtHostRuntimeManifest.parse(
      File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
    );
    expect(manifest.version, extHostRuntimeVersion);
    expect(manifest.productCommit, extHostProductCommit);
    expect(manifest.upstreamVersion, extHostUpstreamVersion);
    expect(manifest.upstreamCommit, extHostUpstreamCommit);
    expect(manifest.nodeVersion, extHostNodeVersion);
    expect(manifest.platforms.keys, unorderedEquals(extHostRuntimePlatforms));
    expect(
      '${manifest.baseUrl}',
      'https://dl.baocode.dev/releases/exthost/${manifest.id}/',
    );
    // In the app's bundle.
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('    - assets/exthost/\n'),
    );
  });

  group('status bar entry', () {
    test('only while it is under way, or failed', () {
      expect(
        extensionRuntimeStatusItem(const ExtensionRuntimeAbsent()),
        isNull,
      );
      final downloading = extensionRuntimeStatusItem(
        const ExtensionRuntimeDownloading(
          received: 42 * 1048576,
          total: 100 * 1048576,
        ),
      )!;
      expect(downloading.text, 'Downloading extension runtime 42%');
      expect(downloading.icon, Codicons.cloudDownload);
      expect(downloading.tooltip, contains('42.0 MB of 100.0 MB'));
      expect(
        extensionRuntimeStatusItem(
          const ExtensionRuntimeDownloading(received: 10, total: 0),
        )!.text,
        'Downloading extension runtime…',
      );
      expect(
        extensionRuntimeStatusItem(const ExtensionRuntimeInstalling())!.text,
        'Installing extension runtime…',
      );
      var retried = false;
      final failed = extensionRuntimeStatusItem(
        const ExtensionRuntimeFailed(
          ExtHostRuntimeException(
            ExtHostRuntimeErrorKind.network,
            'Could not download',
          ),
        ),
        onRetry: () => retried = true,
      )!;
      expect(failed.text, 'Extension runtime unavailable');
      expect(failed.tooltip, contains('Could not download'));
      expect(failed.tooltip, contains('Click to try again'));
      failed.onTap!();
      expect(retried, isTrue);
    });

    test('in Chinese', () {
      final zh = lookupAppLocalizations(const Locale('zh'));
      expect(
        extensionRuntimeStatusItem(
          const ExtensionRuntimeDownloading(received: 1, total: 4),
          l10n: zh,
        )!.text,
        '正在下载扩展运行时 25%',
      );
    });

    test('a remote host\'s install: downloaded there, or sent from here', () {
      expect(remoteRuntimeStatusItem(null, 'box'), isNull);
      final there = remoteRuntimeStatusItem(
        const RemoteRuntimeProgress('downloading', received: 1, total: 2),
        'box',
      )!;
      expect(there.text, 'Installing extension runtime on box 50%');
      expect(there.icon, Codicons.cloudDownload);
      final sent = remoteRuntimeStatusItem(
        const RemoteRuntimeProgress(
          'downloading',
          received: 3 * 1048576,
          total: 4 * 1048576,
          uploading: true,
        ),
        'box',
      )!;
      expect(sent.text, 'Sending extension runtime to box 75%');
      expect(sent.icon, Codicons.cloudUpload);
      expect(sent.tooltip, contains('3.0 MB of 4.0 MB'));
      expect(
        remoteRuntimeStatusItem(
          const RemoteRuntimeProgress('extracting'),
          'box',
        )!.text,
        'Installing extension runtime on box…',
      );
      expect(
        remoteRuntimeStatusItem(
          const RemoteRuntimeProgress('downloading', received: 1, total: 4),
          'box',
          l10n: lookupAppLocalizations(const Locale('zh')),
        )!.text,
        '正在 box 上安装扩展运行时 25%',
      );
    });

    testWidgets('renders in the status bar while downloading', (tester) async {
      final screens = Platform.environment['BAOCODE_EXTHOST_SCREENS'];
      if (screens != null) {
        await tester.runAsync(() async {
          for (final (family, path) in [
            ('Snapshot', '/System/Library/Fonts/Supplemental/Arial.ttf'),
            (Codicons.fontFamily, 'assets/codicons/codicon.ttf'),
          ]) {
            if (!File(path).existsSync()) continue;
            await (FontLoader(
                  family,
                )..addFont(File(path).readAsBytes().then(ByteData.sublistView)))
                .load();
          }
        });
      }
      final key = GlobalKey();
      final item = extensionRuntimeStatusItem(
        const ExtensionRuntimeDownloading(
          received: 35 * 1048576,
          total: 84 * 1048576,
        ),
      )!;
      tester.view.physicalSize = const Size(1280, 44);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: screens == null ? null : 'Snapshot'),
          home: RepaintBoundary(
            key: key,
            child: Material(
              color: themeColors['sideBar.background'],
              child: IdeStatusBar(
                left: [
                  const IdeStatusBarItem('main', icon: Codicons.gitBranch),
                  item,
                ],
                right: const [IdeStatusBarItem('Ln 1, Col 1')],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Downloading extension runtime 41%'), findsOneWidget);
      if (screens == null) return;
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(p.join(screens, 'runtime_downloading.png'))
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
        image.dispose();
      });
    });
  });
}
