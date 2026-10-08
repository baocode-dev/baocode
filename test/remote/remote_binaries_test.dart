import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:baocode/remote/remote_binaries.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Makes real HTTP requests, which the test binding would otherwise answer
/// with 400.
class _RealHttp extends HttpOverrides {}

void main() {
  late Directory temp;
  late String remote;
  late String cache;
  late HttpServer server;
  late Map<String, List<int>> served;
  late List<String> requested;

  setUp(() async {
    HttpOverrides.global = _RealHttp();
    temp = await Directory.systemTemp.createTemp('remote_binaries_test');
    remote = p.join(temp.path, 'remote');
    cache = p.join(temp.path, 'cache');
    Directory(remote).createSync();
    served = {};
    requested = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requested.add(request.uri.path);
      final bytes = served[request.uri.path];
      if (bytes == null) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.add(bytes);
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await server.close(force: true);
    await temp.delete(recursive: true);
  });

  final build = utf8.encode('the x64 server');

  /// What tool/build_remote_server.dart leaves in an installer: VERSION
  /// and servers.json, the Linux x64 build served gzipped ([gz] in its
  /// place), named [key] there.
  void installer({
    String version = '1.0.0.1-abc',
    List<int>? gz,
    String key = 'linux-x64',
  }) {
    final bytes = gzip.encode(build);
    served['/remote/$version/baocode-server-linux-x64.gz'] = gz ?? bytes;
    File(p.join(remote, 'VERSION')).writeAsStringSync('$version\n');
    File(p.join(remote, 'servers.json')).writeAsStringSync(
      jsonEncode({
        'version': version,
        'files': {
          key: {
            'url':
                'http://127.0.0.1:${server.port}/remote/$version/'
                'baocode-server-linux-x64.gz',
            'size': bytes.length,
            'sha256': '${crypto.sha256.convert(bytes)}',
          },
        },
      }),
    );
  }

  RemoteServerBinaries? found() => bundledServerBinaries(
    environment: {'BAOCODE_REMOTE_SERVER_DIR': remote},
    executable: p.join(temp.path, 'app', 'baocode'),
    current: temp.path,
    cacheDir: cache,
  );

  test('the builds in the folder, when they are there', () async {
    installer();
    File(p.join(remote, 'baocode-server-linux-x64')).writeAsStringSync('raw');
    final binaries = found();
    expect(binaries, isA<DirectoryServerBinaries>());
    expect(utf8.decode((await binaries!.read('linux-x64'))!), 'raw');
    expect(requested, isEmpty);
  });

  test(
    'downloads a build, checks it, and keeps it for the next host',
    () async {
      installer();
      Directory(p.join(cache, '0.9.0.1-old')).createSync(recursive: true);
      final binaries = found();
      expect(binaries, isA<DownloadedServerBinaries>());
      expect(binaries!.version, '1.0.0.1-abc');

      expect(await binaries.read('linux-x64'), build);
      expect(requested, hasLength(1));
      expect(
        File(p.join(cache, '1.0.0.1-abc', 'baocode-server-linux-x64.gz'))
            .existsSync(),
        isTrue,
      );
      // Only this app's version is kept.
      expect(Directory(p.join(cache, '0.9.0.1-old')).existsSync(), isFalse);

      // The next host's, and the next run's: from what was kept.
      expect(await binaries.read('linux-x64'), build);
      expect(await found()!.read('linux-x64'), build);
      expect(requested, hasLength(1));
    },
  );

  test('the same builds at hand, not downloaded', () async {
    installer();
    // The checkout the installer's app was built in.
    final checkout = Directory(p.join(temp.path, 'build', 'remote'))
      ..createSync(recursive: true);
    File(p.join(checkout.path, 'baocode-server-linux-x64'))
        .writeAsStringSync('built');
    File(p.join(checkout.path, 'VERSION')).writeAsStringSync('1.0.0.1-abc\n');
    final binaries = found();
    expect(binaries, isA<DirectoryServerBinaries>());
    expect(utf8.decode((await binaries!.read('linux-x64'))!), 'built');
    expect(requested, isEmpty);

    // Another build's: downloaded.
    File(p.join(checkout.path, 'VERSION')).writeAsStringSync('1.0.0.1-new\n');
    expect(found(), isA<DownloadedServerBinaries>());
  });

  test('two hosts at once download it once', () async {
    installer();
    final binaries = found()!;
    final both = await Future.wait([
      binaries.read('linux-x64'),
      binaries.read('linux-x64'),
    ]);
    expect(both, [build, build]);
    expect(requested, hasLength(1));
  });

  test('refuses a download that is not the build named', () async {
    installer(gz: gzip.encode(utf8.encode('something else')));
    await expectLater(
      found()!.read('linux-x64'),
      throwsA(
        isA<SshConnectException>().having(
          (error) => error.failure,
          'failure',
          SshFailure.server,
        ),
      ),
    );
    expect(Directory(cache).existsSync(), isFalse);
  });

  test('a download that fails says so, and is tried again', () async {
    installer();
    final binaries = found()!;
    final saved = served.remove(
      '/remote/1.0.0.1-abc/baocode-server-linux-x64.gz',
    )!;
    await expectLater(
      binaries.read('linux-x64'),
      throwsA(isA<SshConnectException>()),
    );
    served['/remote/1.0.0.1-abc/baocode-server-linux-x64.gz'] = saved;
    expect(await binaries.read('linux-x64'), build);
  });

  test('none for a platform servers.json does not name', () async {
    installer();
    expect(await found()!.read('linux-arm64'), isNull);
    expect(await found()!.read('darwin-arm64'), isNull);
  });

  test(
    'a servers.json naming architectures alone names Linux builds',
    () async {
      installer(key: 'x64');
      final binaries = found()!;
      expect(await binaries.read('linux-x64'), build);
      expect(await binaries.read('darwin-x64'), isNull);
    },
  );

  test('the macOS builds in the folder', () async {
    installer();
    File(p.join(remote, 'baocode-server-darwin-arm64'))
        .writeAsStringSync('mac');
    final binaries = found()!;
    expect(binaries, isA<DirectoryServerBinaries>());
    expect(utf8.decode((await binaries.read('darwin-arm64'))!), 'mac');
    expect(await binaries.read('linux-x64'), isNull);
  });

  test('not a servers.json of another build', () {
    installer();
    File(p.join(remote, 'VERSION')).writeAsStringSync('1.0.0.1-other\n');
    expect(DownloadedServerBinaries.at(remote, cacheDir: cache), isNull);
  });
}
