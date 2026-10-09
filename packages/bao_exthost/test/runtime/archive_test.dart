// The runtime's archives, its manifest and the platform names.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fake_runtime.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('exthost-archive-test-');
  });

  tearDown(() => temp.delete(recursive: true));

  Map<String, (List<int>, bool)> files() => {
    'a.txt': (utf8.encode('a'), false),
    'run': (utf8.encode('#!/bin/sh\n'), true),
    // ustar's prefix split.
    '${'deep/' * 30}leaf.txt': (utf8.encode('deep'), false),
    // No split fits: a pax record.
    'dir/${'x' * 120}.txt': (utf8.encode('long'), false),
    'empty': (const <int>[], false),
    'big.bin': (
      Uint8List.fromList(List.generate(70000, (i) => i * 7 % 256)),
      false,
    ),
  };

  void expectFiles(String root, Map<String, (List<int>, bool)> expected) {
    for (final MapEntry(key: path, value: (content, _)) in expected.entries) {
      expect(File(p.join(root, path)).readAsBytesSync(), content, reason: path);
    }
  }

  test('a tar written in chunks of any size reads back', () async {
    final archive = gzip.decode(fakeTarGz(files()));
    for (final size in [1, 511, 512, 513, 4096, archive.length]) {
      final out = p.join(temp.path, 'tar-$size');
      final chunks = [
        for (var i = 0; i < archive.length; i += size)
          archive.sublist(i, (i + size).clamp(0, archive.length)),
      ];
      final executables = await extractTarStream(
        Stream.fromIterable(chunks),
        out,
      );
      expectFiles(out, files());
      expect(executables.map((e) => p.relative(e, from: out)), ['run']);
    }
  });

  test('a ZIP reads back', () async {
    final zip = p.join(temp.path, 'a.zip');
    fakeZip(zip, files());
    final out = p.join(temp.path, 'zip');
    final executables = await extractZipFile(zip, out);
    expectFiles(out, files());
    expect(executables.map((e) => p.relative(e, from: out)), ['run']);
    if (!Platform.isWindows) {
      final result = Process.runSync('unzip', ['-tq', zip]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    }
  });

  test('the same entries make the same bytes', () {
    expect(fakeTarGz(files()), fakeTarGz(files()));
  });

  test('a truncated or broken tar is refused', () async {
    final archive = gzip.decode(fakeTarGz(files()));
    await expectLater(
      extractTarStream(
        Stream.value(archive.sublist(0, 700)),
        p.join(temp.path, 'truncated'),
      ),
      throwsA(isA<ArchiveException>()),
    );
    final broken = Uint8List.fromList(archive)..[10] ^= 0xFF;
    await expectLater(
      extractTarStream(Stream.value(broken), p.join(temp.path, 'broken')),
      throwsA(isA<ArchiveException>()),
    );
  });

  test('an entry outside the folder is refused', () async {
    final archive = gzip.decode(
      fakeTarGz({'../evil.txt': (utf8.encode('x'), false)}),
    );
    await expectLater(
      extractTarStream(Stream.value(archive), p.join(temp.path, 'out')),
      throwsA(isA<ArchiveException>()),
    );
    expect(File(p.join(temp.path, 'evil.txt')).existsSync(), isFalse);
  });

  group('manifest', () {
    final json = {
      'version': '1.135.06055',
      'id': '1.135.06055-0123abcd',
      'productCommit': 'c' * 40,
      'upstreamVersion': '1.135.0',
      'upstreamCommit': 'd' * 40,
      'nodeVersion': '24.18.1',
      'baseUrl':
          'https://dl.baocode.dev/releases/exthost/1.135.06055-0123abcd/',
      'platforms': {
        'darwin-arm64': {
          'file': 'a.tar.gz',
          'url': 'https://dl.baocode.dev/releases/exthost/1.135.06055-0123abcd/a.tar.gz',
          'size': 10,
          'sha256': 'A' * 64,
        },
        'win32-x64': {'file': 'w.zip', 'size': 20, 'sha256': 'b' * 64},
      },
    };

    test('parses, and a mirror replaces the base URL', () {
      final manifest = ExtHostRuntimeManifest.parse(jsonEncode(json));
      expect(manifest.id, '1.135.06055-0123abcd');
      expect(manifest['darwin-arm64']!.sha256, 'a' * 64);
      expect(manifest['darwin-arm64']!.isZip, isFalse);
      expect(
        '${manifest['win32-x64']!.url}',
        'https://dl.baocode.dev/releases/exthost/1.135.06055-0123abcd/w.zip',
      );
      expect(manifest['win32-x64']!.isZip, isTrue);
      final mirror = manifest.withBaseUrl('http://mirror.local/rt');
      expect(
        '${mirror['darwin-arm64']!.url}',
        'http://mirror.local/rt/a.tar.gz',
      );
      expect(
        ExtHostRuntimeManifest.fromJson(manifest.toJson()).toJson(),
        manifest.toJson(),
      );
    });

    test('refuses what is not one', () {
      for (final broken in [
        {...json, 'platforms': null},
        {...json, 'version': 3},
        {
          ...json,
          'platforms': {
            'x': {'file': '../a', 'size': 1, 'sha256': 'a' * 64},
          },
        },
        {
          ...json,
          'platforms': {
            'x': {'file': 'a', 'size': 1, 'sha256': 'nothex'},
          },
        },
        {...json, 'id': '../up'},
      ]) {
        expect(
          () => ExtHostRuntimeManifest.fromJson(broken),
          throwsFormatException,
          reason: '$broken',
        );
      }
      expect(() => ExtHostRuntimeManifest.parse('{'), throwsFormatException);
    });

    test('the app\'s manifest parses and names all five platforms', () {
      // packages/bao_exthost/test/runtime → the repository's assets.
      final file = File(
        p.join('..', '..', 'assets', 'exthost', 'exthost_runtimes.json'),
      );
      final manifest = ExtHostRuntimeManifest.parse(file.readAsStringSync());
      expect(manifest.platforms.keys, unorderedEquals(extHostRuntimePlatforms));
      expect(manifest.id, startsWith('${manifest.version}-'));
      for (final asset in manifest.platforms.values) {
        expect('${asset.url}', startsWith('${manifest.baseUrl}'));
        expect(asset.isZip, asset.platform.startsWith('win32'));
      }
    });
  });

  test('platform names', () {
    String? of(String os, String target) =>
        extHostPlatformOf(os: os, version: '3.13.4 (stable) on "$target"');
    expect(of('macos', 'macos_arm64'), 'darwin-arm64');
    expect(of('macos', 'macos_x64'), 'darwin-x64');
    expect(of('windows', 'windows_x64'), 'win32-x64');
    expect(of('windows', 'windows_arm64'), 'win32-x64');
    expect(of('linux', 'linux_x64'), 'linux-x64');
    expect(of('linux', 'linux_arm64'), 'linux-arm64');
    expect(of('linux', 'linux_riscv64'), isNull);
    expect(of('android', 'android_arm64'), isNull);
    expect(currentExtHostPlatform(), isNotNull);
  });
}
