// 九.6: the extension runtime on a remote host, through the BaoCode
// server's protocol in memory (this machine plays the host): installed by
// the host from the downloads (a local mirror of the real archive), or,
// where the host cannot reach them, downloaded here and sent; its VS Code
// server started there and reached through the connection.
@Tags(['exthost'])
@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:bao_remote/client.dart';
import 'package:bao_remote/server.dart';
import 'package:baocode/extensions/host/extension_server_io.dart';
import 'package:baocode/extensions/runtime/extension_runtime_service.dart';
import 'package:baocode/remote/remote_exthost.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The real archives, as the acceptance tests keep them.
const _dist = '/tmp/exthost-dl/dist';

/// The host cannot reach the downloads.
final class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'PROXY 127.0.0.1:9';
}

/// A server whose downloads go through [overrides] (none: as they are),
/// and a client joined to it in memory.
Future<RemoteClient> _connect(
  String dataDir, {
  HttpOverrides? overrides,
}) async {
  final toServer = StreamController<String>();
  final toClient = StreamController<String>();
  RemoteServer make() => RemoteServer(
    RpcPeer(toServer.stream, toClient.add),
    dataDir: dataDir,
    version: 'test',
  );
  final server = overrides == null
      ? make()
      : HttpOverrides.runWithHttpOverrides(make, overrides);
  final client = RemoteClient(RpcPeer(toClient.stream, toServer.add));
  await client.initialize();
  addTearDown(server.shutdown);
  return client;
}

/// A mirror of [_dist] on this machine.
Future<String> _mirror() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final file = File(p.join(_dist, p.basename(request.uri.path)));
    if (!file.existsSync()) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.contentLength = file.lengthSync();
      await request.response.addStream(file.openRead());
    }
    await request.response.close();
  });
  addTearDown(() => server.close(force: true));
  return 'http://127.0.0.1:${server.port}/';
}

void main() {
  final platform = currentExtHostPlatform();
  final manifest = ExtHostRuntimeManifest.parse(
    File(ExtensionRuntimeService.manifestAsset).readAsStringSync(),
  );
  final archive = platform == null ? null : manifest[platform]?.file;
  final skip = archive == null || !File(p.join(_dist, archive)).existsSync()
      ? 'No runtime archive in $_dist'
      : false;

  late Directory temp;
  setUp(() {
    // The test binding answers every request with a 400: these are real.
    HttpOverrides.global = null;
    temp = Directory.systemTemp.createTempSync('remote-exthost');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  Future<void> expectServes(ExtensionServer server) async {
    final environment = await server.environment();
    expect(environment['os'], isNotNull);
    final scanned = await server.scanExtensions();
    expect([
      for (final e in scanned) (e['identifier'] as Map)['value'],
    ], contains('vscode.typescript-language-features'));
  }

  test(
    'the host downloads the runtime and runs its server, reached through '
    'the connection',
    () async {
      final mirrored = manifest.withBaseUrl(await _mirror());
      final client = await _connect(p.join(temp.path, 'host'));
      final phases = <String>{};
      final server = await startRemoteExtensionServer(
        client,
        manifest: mirrored,
        downloads: p.join(temp.path, 'downloads'),
        onProgress: (progress) {
          expect(progress.uploading, isFalse);
          phases.add(progress.phase);
        },
      );
      addTearDown(server.dispose);
      expect(phases, containsAll(['downloading', 'verifying', 'extracting']));
      expect(server.product?['commit'], manifest.productCommit);
      expect(server.connector, isNotNull);
      await expectServes(server);
      // Nothing of it here: the downloads folder was not used.
      expect(Directory(p.join(temp.path, 'downloads')).existsSync(), isFalse);
      expect(
        Directory(p.join(temp.path, 'host', 'exthost', 'runtimes', manifest.id))
            .existsSync(),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );

  test(
    'a host that cannot reach the downloads is sent the archive downloaded '
    'here',
    () async {
      final mirrored = manifest.withBaseUrl(await _mirror());
      final client = await _connect(
        p.join(temp.path, 'host'),
        overrides: _Offline(),
      );
      var uploaded = 0;
      final server = await startRemoteExtensionServer(
        client,
        manifest: mirrored,
        downloads: p.join(temp.path, 'downloads'),
        onProgress: (progress) {
          if (progress.uploading) uploaded = progress.received;
        },
      );
      addTearDown(server.dispose);
      expect(uploaded, mirrored[platform!]!.size);
      expect(
        File(p.join(temp.path, 'downloads', archive)).existsSync(),
        isTrue,
        reason: 'kept here for the next host',
      );
      // The upload is gone once installed.
      expect(
        Directory(p.join(temp.path, 'host', 'exthost', 'uploads')).listSync(),
        isEmpty,
      );
      await expectServes(server);
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: skip,
  );
}
