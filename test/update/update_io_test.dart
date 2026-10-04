import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/update/update_io.dart';
import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/update_signature.dart';
import 'package:baocode/update/version.dart';

/// A local server, in place of baocode.dev: what it serves by path, what it
/// was asked.
class _Server {
  _Server._(this._server) {
    _server.listen(_handle);
  }

  static Future<_Server> start() async =>
      _Server._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  final HttpServer _server;
  final Map<String, Uint8List> files = {};
  final List<String?> ranges = [];

  /// Ignores Range requests, as some servers do.
  bool ranged = true;

  /// Sends only this much of a file, then drops the connection.
  int? cutAt;

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}/$path');

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    final file = files[request.uri.path.substring(1)];
    if (file == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final range = request.headers.value(HttpHeaders.rangeHeader);
    ranges.add(range);
    var from = 0;
    if (range != null && ranged) {
      from = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
      if (from >= file.length) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }
      response.statusCode = HttpStatus.partialContent;
    }
    final body = file.sublist(from);
    if (cutAt case final cut?) {
      response.contentLength = body.length;
      final socket = await response.detachSocket();
      socket.add(body.sublist(0, cut));
      await socket.flush();
      socket.destroy();
      return;
    }
    response.contentLength = body.length;
    response.add(body);
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

/// Makes real HTTP requests, which the test binding would otherwise answer
/// with 400.
class _RealHttp extends HttpOverrides {}

void main() {
  late _Server server;
  late Directory directory;
  late IoUpdateBackend backend;
  final seed = UpdateSignature.generateSeed();
  final publicKey = UpdateSignature.publicKeyOf(seed);
  final bytes = Uint8List.fromList(
    List.generate(200 * 1024, (i) => Random(i).nextInt(256)),
  );

  /// [bytes] as the release of [version] for windows-x64, signed with
  /// [signWith] (the test key).
  UpdateRelease release({
    String version = '1.2.0+12',
    Uint8List? data,
    int? size,
    String? sha256,
    String? signWith,
    String platform = 'windows-x64',
  }) {
    final content = data ?? bytes;
    final digest = sha256 ?? '${crypto.sha256.convert(content)}';
    final length = size ?? content.length;
    final asset = UpdateAsset(
      url: server.url('BaoCode-setup.exe'),
      size: length,
      sha256: digest,
      signature: UpdateSignature.sign(
        payload: UpdateSignature.payload(
          version: version,
          platform: platform,
          size: length,
          sha256: digest,
        ),
        seed: signWith ?? seed,
      ),
    );
    return UpdateRelease(
      manifest: UpdateManifest(
        version: AppVersion.parse(version),
        platforms: {platform: asset},
      ),
      platform: platform,
      asset: asset,
    );
  }

  setUp(() async {
    HttpOverrides.global = _RealHttp();
    server = await _Server.start();
    server.files['BaoCode-setup.exe'] = bytes;
    directory = await Directory.systemTemp.createTemp('baocode-updates');
    backend = IoUpdateBackend(
      directory: directory.path,
      publicKey: publicKey,
      timeout: const Duration(seconds: 5),
    );
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await server.close();
    await directory.delete(recursive: true);
  });

  List<String> files() => [
    for (final entity in directory.listSync(recursive: true))
      if (entity is File) p.relative(entity.path, from: directory.path),
  ]..sort();

  group('IoUpdateBackend', () {
    test('fetches the manifest', () async {
      server.files['latest.json'] = Uint8List.fromList('{"a": 1}'.codeUnits);
      expect(
        await backend.fetchManifest(server.url('latest.json')),
        '{"a": 1}',
      );
      await expectLater(
        backend.fetchManifest(server.url('missing.json')),
        throwsA(isA<HttpException>()),
      );
    });

    test('downloads, checks and keeps a release', () async {
      final progress = <int>[];
      final path = await backend.download(
        release(),
        onProgress: (received, total) {
          expect(total, bytes.length);
          progress.add(received);
        },
      );
      expect(path, p.join(directory.path, '1.2.0+12', 'BaoCode-setup.exe'));
      expect(await File(path).readAsBytes(), bytes);
      expect(progress.last, bytes.length);
      expect(files(), [p.join('1.2.0+12', 'BaoCode-setup.exe')]);
    });

    test('finds a download made before without fetching it again', () async {
      await backend.download(release());
      server.ranges.clear();
      await backend.download(release());
      expect(server.ranges, isEmpty);
    });

    test('refuses a download whose SHA-256 is not the manifest\'s', () async {
      await expectLater(
        backend.download(release(sha256: 'b' * 64)),
        throwsA(
          isA<UpdateVerificationException>().having(
            (e) => e.message,
            'message',
            contains('SHA-256'),
          ),
        ),
      );
      expect(files(), isEmpty, reason: 'the bad download is gone');
    });

    test('refuses a download signed with another key', () async {
      await expectLater(
        backend.download(release(signWith: UpdateSignature.generateSeed())),
        throwsA(
          isA<UpdateVerificationException>().having(
            (e) => e.message,
            'message',
            contains('not signed'),
          ),
        ),
      );
      expect(files(), isEmpty);
    });

    test('refuses a download of another size', () async {
      await expectLater(
        backend.download(release(size: bytes.length + 10)),
        throwsA(isA<UpdateVerificationException>()),
      );
      expect(files(), isEmpty);
      await expectLater(
        backend.download(release(size: bytes.length - 10)),
        throwsA(
          isA<UpdateVerificationException>().having(
            (e) => e.message,
            'message',
            contains('larger'),
          ),
        ),
      );
      expect(files(), isEmpty);
    });

    test('a signature for another version does not pass', () async {
      // Signed as 1.1.0, offered as 1.2.0: a downgrade.
      final real = release(version: '1.1.0');
      final passedOff = UpdateRelease(
        manifest: UpdateManifest(version: AppVersion.parse('1.2.0')),
        platform: 'windows-x64',
        asset: real.asset,
      );
      await expectLater(
        backend.download(passedOff),
        throwsA(isA<UpdateVerificationException>()),
      );
    });

    test('picks up where a download stopped', () async {
      server.cutAt = 50 * 1024;
      await expectLater(backend.download(release()), throwsA(anything));
      final part = File(
        p.join(directory.path, '1.2.0+12', 'BaoCode-setup.exe.part'),
      );
      expect(await part.length(), 50 * 1024);
      server.cutAt = null;
      server.ranges.clear();
      final path = await backend.download(release());
      expect(server.ranges, ['bytes=${50 * 1024}-']);
      expect(await File(path).readAsBytes(), bytes);
    });

    test('starts over where the server cannot resume', () async {
      final part = File(
        p.join(directory.path, '1.2.0+12', 'BaoCode-setup.exe.part'),
      );
      await part.parent.create(recursive: true);
      await part.writeAsBytes(bytes.sublist(0, 1000));
      server.ranged = false;
      final path = await backend.download(release());
      expect(await File(path).readAsBytes(), bytes);
    });

    test('keeps only the newest version', () async {
      server.files['BaoCode-setup.exe'] = bytes;
      await backend.download(release(version: '1.1.0'));
      await backend.download(release(version: '1.2.0+12'));
      expect(files(), [p.join('1.2.0+12', 'BaoCode-setup.exe')]);
    });

    test('cleans up what is installed by now', () async {
      for (final name in ['1.0.0+1', '1.1.0', '1.2.0+12', 'junk']) {
        await File(p.join(directory.path, name, 'x')).create(recursive: true);
      }
      await File(p.join(directory.path, 'install.log')).writeAsString('');
      await backend.cleanUp(AppVersion.parse('1.1.0'));
      expect(files(), [p.join('1.2.0+12', 'x'), 'install.log']);
      await IoUpdateBackend(directory: p.join(directory.path, 'none'))
          .cleanUp(AppVersion.parse('1.0.0'));
    });
  });
}
