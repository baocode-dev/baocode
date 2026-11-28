import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/acp.dart';
import 'package:bao_remote/protocol.dart' show RemotePlatform;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('AgyBuild', () {
    test('toJson / fromJson round-trip and equality', () {
      const build = AgyBuild(
        version: '1.5.16',
        target: 'linux_amd64',
        url:
            'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.16/antigravity_linux_amd64.tar.gz',
        sha512:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      );
      final decoded = AgyBuild.fromJson(build.toJson());
      expect(decoded, equals(build));
      expect(decoded.hashCode, equals(build.hashCode));
      expect(decoded.isArchive, isTrue);

      const rawBinary = AgyBuild(
        version: '1.5.16',
        target: 'windows_amd64',
        url:
            'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.16/antigravity.exe',
        sha512:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      );
      expect(rawBinary.isArchive, isFalse);
    });
  });

  group('AgyRelease.targetOf', () {
    test('maps all RemotePlatform values to manifest target names', () {
      expect(
        AgyRelease.targetOf(const RemotePlatform('linux', 'x64', libc: 'gnu')),
        'linux_amd64',
      );
      expect(
        AgyRelease.targetOf(const RemotePlatform('linux', 'arm64')),
        'linux_arm64',
      );
      expect(
        AgyRelease.targetOf(const RemotePlatform('darwin', 'arm64')),
        'darwin_arm64',
      );
      expect(
        AgyRelease.targetOf(const RemotePlatform('darwin', 'x64')),
        'darwin_amd64',
      );
      expect(
        AgyRelease.targetOf(const RemotePlatform('win', 'x64')),
        'windows_amd64',
      );
      expect(
        AgyRelease.targetOf(const RemotePlatform('win', 'arm64')),
        'windows_arm64',
      );
    });
  });

  group('AgyRelease feed, download & SHA-512 verification', () {
    late HttpServer server;
    late Directory tempDir;
    late String baseUrl;
    late List<int> payload;
    late String payloadSha512;
    late Map<String, Object?> manifest;
    var manifestStatus = HttpStatus.ok;
    var downloadStatus = HttpStatus.ok;
    var corruptDownload = false;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('agy-release-test-');
      payload = utf8.encode('#!/bin/sh\necho "agy 1.6.0"\n');
      payloadSha512 = sha512.convert(payload).toString();
      manifestStatus = HttpStatus.ok;
      downloadStatus = HttpStatus.ok;
      corruptDownload = false;

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      baseUrl = 'http://127.0.0.1:${server.port}';
      manifest = {
        'version': '1.6.0',
        'url': '$baseUrl/downloads/1.6.0/antigravity',
        'sha512': payloadSha512,
      };
      server.listen((request) async {
        final response = request.response;
        if (request.uri.path == '/manifests/linux_amd64.json') {
          response.statusCode = manifestStatus;
          if (manifestStatus == HttpStatus.ok) {
            response.write(jsonEncode(manifest));
          }
        } else if (request.uri.path == '/downloads/1.6.0/antigravity') {
          response.statusCode = downloadStatus;
          if (downloadStatus == HttpStatus.ok) {
            final bytes = corruptDownload ? utf8.encode('corrupted') : payload;
            response.contentLength = bytes.length;
            response.add(bytes);
          }
        } else {
          response.statusCode = HttpStatus.notFound;
        }
        await response.close();
      });
    });

    tearDown(() async {
      AgyRelease.feedOverride = null;
      AgyRelease.downloadsPrefixOverride = null;
      await server.close(force: true);
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('fetches manifest, downloads with progress, and verifies SHA-512', () async {
      final release = AgyRelease(
        feed: '$baseUrl/manifests',
        downloadsPrefix: '$baseUrl/downloads/',
      );
      final build = await release.latest('linux_amd64');
      expect(build.version, '1.6.0');
      expect(build.target, 'linux_amd64');
      expect(build.url, '$baseUrl/downloads/1.6.0/antigravity');
      expect(build.sha512, payloadSha512);

      final dest = File(p.join(tempDir.path, 'agy.part'));
      final progress = <(int, int)>[];
      await release.download(
        build,
        dest,
        onProgress: (received, total) => progress.add((received, total)),
      );
      expect(dest.existsSync(), isTrue);
      expect(dest.readAsBytesSync(), payload);
      expect(progress, isNotEmpty);
      expect(progress.last.$1, payload.length);
      expect(progress.last.$2, payload.length);
      expect(await AgyRelease.verifySha512(dest, payloadSha512), isTrue);
      expect(
        await AgyRelease.verifySha512(dest, payloadSha512.toUpperCase()),
        isTrue,
      );
      expect(await AgyRelease.verifySha512(dest, '0' * 128), isFalse);
      expect(
        await AgyRelease.verifySha512(
          File(p.join(tempDir.path, 'missing')),
          payloadSha512,
        ),
        isFalse,
      );
    });

    test('rejects manifest whose URL does not match allowed prefix', () async {
      manifest = {
        'version': '1.6.0',
        'url': 'https://evil.example.com/antigravity',
        'sha512': payloadSha512,
      };
      final release = AgyRelease(
        feed: '$baseUrl/manifests',
        downloadsPrefix: AgyRelease.defaultDownloadsPrefix,
      );
      await expectLater(
        release.latest('linux_amd64'),
        throwsA(isA<AgyUnavailable>()),
      );
    });

    test('rejects HTTP error from manifest feed', () async {
      manifestStatus = HttpStatus.serviceUnavailable;
      final release = AgyRelease(
        feed: '$baseUrl/manifests',
        downloadsPrefix: '$baseUrl/downloads/',
      );
      await expectLater(
        release.latest('linux_amd64'),
        throwsA(
          isA<AgyUnavailable>().having(
            (e) => e.message,
            'message',
            contains('503'),
          ),
        ),
      );
    });

    test('deletes file and throws on SHA-512 mismatch during download', () async {
      corruptDownload = true;
      final release = AgyRelease(
        feed: '$baseUrl/manifests',
        downloadsPrefix: '$baseUrl/downloads/',
      );
      final build = await release.latest('linux_amd64');
      final dest = File(p.join(tempDir.path, 'corrupt.part'));
      await expectLater(
        release.download(build, dest),
        throwsA(
          isA<AgyUnavailable>().having(
            (e) => e.message,
            'message',
            contains('checksum'),
          ),
        ),
      );
      expect(dest.existsSync(), isFalse);
    });
  });

  group('ManagedAgy', () {
    late Directory tempDir;
    late ManagedAgy managed;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('managed-agy-test-');
      managed = ManagedAgy(p.join(tempDir.path, 'antigravity'));
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('reports notInstalled before any build is installed', () async {
      expect(await managed.version(), isNull);
      expect(managed.brainDir, p.join(managed.home, 'antigravity-cli', 'brain'));
      await expectLater(
        managed.executable(),
        throwsA(
          isA<AgyUnavailable>().having(
            (e) => e.notInstalled,
            'notInstalled',
            isTrue,
          ),
        ),
      );
    });

    test('installs direct binary, sets executable bit, and prunes old build', () async {
      const build1 = AgyBuild(
        version: '1.5.0',
        target: 'linux_amd64',
        url:
            'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.0/antigravity',
        sha512: 'a',
      );
      final part1 = managed.partOf(build1)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\necho "v1.5.0"\n');

      final exe1 = await managed.installArchive(build1, part1);
      expect(await managed.version(), '1.5.0');
      expect(await managed.executable(), exe1);
      expect(File(exe1).existsSync(), isTrue);
      if (!Platform.isWindows) {
        final run = Process.runSync(exe1, const []);
        expect(run.exitCode, 0);
        expect('${run.stdout}'.trim(), 'v1.5.0');
      }

      const build2 = AgyBuild(
        version: '1.6.0',
        target: 'linux_amd64',
        url:
            'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.6.0/antigravity',
        sha512: 'b',
      );
      final part2 = managed.partOf(build2)
        ..writeAsStringSync('#!/bin/sh\necho "v1.6.0"\n');
      final exe2 = await managed.installArchive(build2, part2);
      expect(await managed.version(), '1.6.0');
      expect(await managed.executable(), exe2);
      // Previous version pruned by default.
      expect(Directory(p.join(managed.binDir, '1.5.0')).existsSync(), isFalse);
    });

    test(
      'installArchive extracts .tar.gz archive and makes binary executable',
      () async {
        final staging = Directory(p.join(tempDir.path, 'tar-src'))
          ..createSync(recursive: true);
        File(p.join(staging.path, 'antigravity'))
            .writeAsStringSync('#!/bin/sh\necho "from-tar"\n');
        const build = AgyBuild(
          version: '1.7.0',
          target: 'darwin_arm64',
          url:
              'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.7.0/antigravity_darwin_arm64.tar.gz',
          sha512: 'c',
        );
        final archive = managed.partOf(build);
        archive.parent.createSync(recursive: true);
        final tar = Process.runSync('tar', [
          '-czf',
          archive.path,
          '-C',
          staging.path,
          'antigravity',
        ]);
        expect(tar.exitCode, 0, reason: '${tar.stderr}');

        final exe = await managed.installArchive(build, archive);
        expect(await managed.version(), '1.7.0');
        expect(await managed.executable(), exe);
        expect(archive.existsSync(), isFalse);
        final run = Process.runSync(exe, const []);
        expect(run.exitCode, 0);
        expect('${run.stdout}'.trim(), 'from-tar');
      },
      skip: Platform.isWindows ? 'POSIX tar test' : false,
    );

    test('deleteSession removes matching conversation artifacts under home', () async {
      const sid = '12345678-aaaa-bbbb-cccc-1234567890ab';
      final brainEntry = Directory(p.join(managed.brainDir, sid))
        ..createSync(recursive: true);
      final convFile = File(
        p.join(managed.home, 'antigravity-cli', 'conversations', '$sid.db'),
      )
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('db');
      final otherFile = File(
        p.join(
          managed.home,
          'antigravity-cli',
          'conversations',
          '99999999-other.db',
        ),
      )..writeAsStringSync('keep');

      await managed.deleteSession(sid);
      expect(brainEntry.existsSync(), isFalse);
      expect(convFile.existsSync(), isFalse);
      expect(otherFile.existsSync(), isTrue);
    });
  });

  group('Pure-Dart JSON models', () {
    test('AgyLaunchOptions and AgyModel JSON round-trip', () {
      const options = AgyLaunchOptions(
        cwd: '/repo',
        resume: 'sess-1',
        model: 'gemini-3.8-flash',
        permissionMode: 'acceptEdits',
        effort: 'high',
        autocompact: 200000,
        persist: false,
        directories: ['/extra'],
        folderInstructions: false,
        instructions: 'Be concise.',
        sdkServers: ['baocode'],
        flagSettings: {'effortLevel': 'high'},
        baseEnvironment: {'FOO': 'bar'},
        brainDir: '/brain',
      );
      final roundTrip = AgyLaunchOptions.fromJson(options.toJson());
      expect(roundTrip.cwd, '/repo');
      expect(roundTrip.resume, 'sess-1');
      expect(roundTrip.model, 'gemini-3.8-flash');
      expect(roundTrip.permissionMode, 'acceptEdits');
      expect(roundTrip.effort, 'high');
      expect(roundTrip.autocompact, 200000);
      expect(roundTrip.persist, isFalse);
      expect(roundTrip.directories, ['/extra']);
      expect(roundTrip.folderInstructions, isFalse);
      expect(roundTrip.instructions, 'Be concise.');
      expect(roundTrip.sdkServers, ['baocode']);
      expect(roundTrip.flagSettings, {'effortLevel': 'high'});
      expect(roundTrip.baseEnvironment, {'FOO': 'bar'});
      expect(roundTrip.brainDir, '/brain');

      const model = AgyModel(
        'gemini-3.8-flash',
        'Gemini 3.8 Flash',
        efforts: ['low', 'high'],
      );
      expect(AgyModel.fromJson(model.toJson()), equals(model));
    });
  });
}
