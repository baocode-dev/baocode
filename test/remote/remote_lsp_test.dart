@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:bao_remote/lsp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/lsp/fake_lsp.dart' show dartExecutable, fakeServerScript;
import 'remote_harness.dart';

/// Language servers on the host: their bytes carried both ways as the
/// app's client would send them, and installs done there.
void main() {
  late RemoteHarness harness;

  setUp(() async => harness = await RemoteHarness.start());
  tearDown(() async {
    ClaudeEnvironment.use(null);
    await harness.close();
  });

  List<int> frame(Map<String, Object?> message) {
    final body = utf8.encode(jsonEncode(message));
    return [...ascii.encode('Content-Length: ${body.length}\r\n\r\n'), ...body];
  }

  /// The JSON messages in [bytes] so far.
  List<Map<String, Object?>> messages(List<int> bytes) {
    final found = <Map<String, Object?>>[];
    var at = 0;
    while (true) {
      final text = latin1.decode(bytes.sublist(at));
      final header = text.indexOf('\r\n\r\n');
      if (header < 0) break;
      final length = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(text)![1]!,
      );
      final start = at + header + 4;
      if (bytes.length < start + length) break;
      found.add(
        jsonDecode(utf8.decode(bytes.sublist(start, start + length)))
            as Map<String, Object?>,
      );
      at = start + length;
    }
    return found;
  }

  test('a server runs there: its pid, and its messages both ways', () async {
    final root = Directory(p.join(harness.dataDir.path, 'project'))
      ..createSync();
    final server = await harness.client.start(
      dartExecutable,
      [fakeServerScript],
      cwd: root.path,
      login: false,
    );
    expect(server.pid, greaterThan(0));
    final out = <int>[];
    server.stdout.listen(out.addAll);
    server.write(
      frame({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {
          'processId': harness.client.hello!.pid,
          'rootUri': Uri.directory(root.path).toString(),
          'capabilities': <String, Object?>{},
          'initializationOptions': {'name': 'remote-fake'},
        },
      }),
    );
    await until(() => messages(out).any((m) => m['id'] == 1));
    final answer = messages(out).firstWhere((m) => m['id'] == 1);
    expect(answer['result'], isA<Map>());
    expect(
      ((answer['result'] as Map)['serverInfo'] as Map?)?['name'],
      anyOf(isNull, 'remote-fake'),
    );

    server.write(frame({'jsonrpc': '2.0', 'id': 2, 'method': 'shutdown'}));
    await until(() => messages(out).any((m) => m['id'] == 2));
    server.write(frame({'jsonrpc': '2.0', 'method': 'exit'}));
    expect(await server.exitCode.timeout(const Duration(seconds: 15)), 0);
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('the server ends what it runs when it shuts down', () async {
    final server = await harness.client.start(dartExecutable, [
      fakeServerScript,
    ], login: false);
    await harness.server.shutdown();
    expect(
      await server.exitCode.timeout(const Duration(seconds: 15)),
      isNot(0),
    );
  });

  group('installing', () {
    late HttpServer http;
    late MasonPackage package;
    final requests = <String>[];

    setUp(() async {
      // flutter_test answers every HttpClient request with a 400.
      final overrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = overrides);
      requests.clear();
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((request) async {
        requests.add(request.uri.path);
        if (request.uri.path == '/fake-ls.tar.gz') {
          request.response.add(
            File(p.join('test', 'fixtures', 'lsp', 'mason', 'fake-ls.tar.gz'))
                .readAsBytesSync(),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
      package = MasonPackage.fromJson({
        'name': 'fake-remote',
        'categories': ['LSP'],
        'source': {
          'id': 'pkg:generic/example/fake-ls@1.0',
          'download': {
            'files': {
              'fake-ls.tar.gz': 'http://127.0.0.1:${http.port}/fake-ls.tar.gz',
            },
          },
        },
        'bin': {'fake-remote-ls': 'fake-ls-1.0/bin/fake-ls'},
      });
      ClaudeEnvironment.use({'PATH': '/usr/bin:/bin'});
    });
    tearDown(() => http.close(force: true));

    test('downloaded and unpacked there, found, run, and removed', () async {
      expect(
        await harness.client.locateLanguageServer(
          'fake-remote-ls',
          masonPackage: 'fake-remote',
          packages: [package],
        ),
        isA<LspServerMissing>().having(
          (m) => m.package,
          'package',
          'fake-remote',
        ),
      );
      final progress = <String>[];
      await harness.client.installLanguageServer(
        package,
        onProgress: progress.add,
      );
      expect(requests, ['/fake-ls.tar.gz']);
      expect(progress, isNotEmpty);
      expect(await harness.client.installedLanguageServers(), ['fake-remote']);

      final found = await harness.client.locateLanguageServer(
        'fake-remote-ls',
        masonPackage: 'fake-remote',
        packages: [package],
      );
      expect(found, isA<LspServerFound>());
      final executable = (found as LspServerFound).executable;
      expect(
        p.isWithin(p.join(harness.dataDir.path, 'lsp'), executable),
        isTrue,
      );
      final ran = await harness.client.run(executable, const [], login: false);
      expect(ran.stdout.trim(), 'fake-ls');

      await harness.client.uninstallLanguageServer('fake-remote');
      expect(await harness.client.installedLanguageServers(), isEmpty);
    }, timeout: const Timeout(Duration(minutes: 1)));

    test('a failed download fails the install there', () async {
      final broken = MasonPackage.fromJson({
        ...package.toJson(),
        'source': {
          'id': 'pkg:generic/example/fake-ls@1.0',
          'download': {
            'files': {
              'fake-ls.tar.gz': 'http://127.0.0.1:${http.port}/missing.tar.gz',
            },
          },
        },
      });
      await expectLater(
        harness.client.installLanguageServer(broken),
        throwsA(isA<LspInstallException>()),
      );
      expect(await harness.client.installedLanguageServers(), isEmpty);
    });
  });
}
