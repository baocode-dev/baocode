// The real runtime, as tool/build_exthost_runtime.dart built it into
// build/exthost-runtime/: installed from there (a file: mirror) as the app
// would from dl.baocode.dev, and its server started. Opt in with
// `dart test --run-skipped -t exthost test/runtime/real_runtime_test.dart`.
@Tags(['exthost'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'the built runtime installs from its manifest and its server starts',
    () async {
      final repository = p.normalize(p.absolute('../..'));
      final built = p.join(repository, 'build', 'exthost-runtime');
      final manifest = ExtHostRuntimeManifest.parse(
        File(p.join(repository, 'assets', 'exthost', 'exthost_runtimes.json'))
            .readAsStringSync(),
      );
      final platform = currentExtHostPlatform()!;
      final temp = await Directory.systemTemp.createTemp('exthost-real-');
      addTearDown(() => temp.delete(recursive: true));
      final runtime = await ExtHostRuntimeInstaller(
        manifest: manifest,
        directory: p.join(temp.path, 'exthost'),
        environment: {
          ExtHostRuntimeInstaller.baseUrlVariable: Uri.directory(built)
              .toString(),
        },
      ).ensure(platform: platform);
      expect(runtime.productCommit, manifest.productCommit);
      expect(runtime.productVersion, manifest.version);
      final product =
          jsonDecode(File(runtime.productJson).readAsStringSync()) as Map;
      expect(product['nameShort'], 'BaoCode');
      expect(product['urlProtocol'], 'baocode');

      final token = File(p.join(temp.path, 'token'))..writeAsStringSync('t');
      final server = await Process.start(runtime.nodeExecutable, [
        runtime.serverMain,
        '--host',
        '127.0.0.1',
        '--port',
        '0',
        '--connection-token-file',
        token.path,
        '--server-data-dir',
        p.join(temp.path, 'data'),
        '--extensions-dir',
        p.join(temp.path, 'extensions'),
        '--accept-server-license-terms',
      ]);
      addTearDown(server.kill);
      final listening = await server.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .firstWhere((line) => line.contains('Extension host agent listening'))
          .timeout(const Duration(seconds: 30));
      expect(listening, matches(RegExp(r'listening on \d+')));
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
