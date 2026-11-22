import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/agent_kernel.dart' show SessionRecord;
import 'package:baocode/kernel/antigravity/agy_runtime.dart';
import 'package:baocode/kernel/antigravity/agy_runtime_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a project path as agy lists it, decoded', () {
    expect(
      agyPath('/Users/me/Library/Application%20Support/x'),
      '/Users/me/Library/Application Support/x',
    );
    expect(agyPath('/p/100%'), '/p/100%');
    expect(agyPath('/p/q'), '/p/q');
  });

  group('its MCP servers', () {
    test('as its config has them, a command or a URL', () {
      final servers = parseAgyMcpConfig(
        jsonEncode({
          'mcpServers': {
            'github': {
              'command': 'npx',
              'args': ['-y', 'server-github'],
            },
            'docs': {'serverUrl': 'https://docs.example/mcp', 'disabled': true},
          },
        }),
      );
      expect(
        [for (final s in servers) (s.name, s.enabled, s.target)],
        [
          ('github', true, 'npx -y server-github'),
          ('docs', false, 'https://docs.example/mcp'),
        ],
      );
    });

    test('none in a config without them', () {
      expect(parseAgyMcpConfig('{}'), isEmpty);
    });
  });

  test('what is left of one deleted goes, in whichever folder', () async {
    final home = Directory.systemTemp.createTempSync('agy');
    addTearDown(() => home.deleteSync(recursive: true));
    final runtime = LocalAgyRuntime(
      installDir: '${home.path}/none',
      dataDir: '${home.path}/antigravity-cli',
      stateDir: '${home.path}/state',
      environment: () async => {'HOME': home.path, 'PATH': ''},
    );
    final files = [
      // agy's own, and the Antigravity app's beside it.
      for (final root in ['antigravity-cli', 'antigravity']) ...[
        File('${home.path}/$root/conversations/a.db'),
        File('${home.path}/$root/conversations/a.db-wal'),
        File('${home.path}/$root/annotations/a.pbtxt'),
        File('${home.path}/$root/brain/a/plan.md'),
      ],
      File('${home.path}/antigravity-cli/conversations/b.db'),
    ];
    for (final file in files) {
      file.createSync(recursive: true);
    }
    await runtime.delete('a');
    expect(
      [for (final file in files) file.existsSync()],
      [for (var i = 0; i < 8; i++) false, true],
    );
    expect(Directory('${home.path}/antigravity/brain/a').existsSync(), isFalse);
  });

  test('the conversations last listed, kept', () {
    final dir = Directory.systemTemp.createTempSync('agy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runtime = LocalAgyRuntime(
      dataDir: '${dir.path}/agy',
      stateDir: '${dir.path}/state',
    );
    expect(runtime.lastSessions, isNull);
    runtime.lastSessions = [
      SessionRecordFixture.one('a', '/x', 't', DateTime(2026, 1, 2)),
    ];
    final kept = LocalAgyRuntime(
      dataDir: '${dir.path}/agy',
      stateDir: '${dir.path}/state',
    ).lastSessions!.single;
    expect((kept.id, kept.cwd, kept.title), ('a', '/x', 't'));
    expect(kept.updatedAt, DateTime(2026, 1, 2));
  });

  test('a conversation\'s tool key, kept', () {
    final dir = Directory.systemTemp.createTempSync('agy');
    addTearDown(() => dir.deleteSync(recursive: true));
    final runtime = LocalAgyRuntime(
      dataDir: '${dir.path}/agy',
      stateDir: '${dir.path}/state',
    );
    expect(runtime.toolKey('c1'), isNull);
    runtime.keepToolKey('c1', 'k1');
    runtime.keepToolKey('c2', 'k2');
    expect(runtime.toolKey('c1'), 'k1');
    expect(
      LocalAgyRuntime(
        dataDir: '${dir.path}/agy',
        stateDir: '${dir.path}/state',
      ).toolKey('c2'),
      'k2',
    );
  });

  group('agy as a service', () {
    late Directory dir;
    late LocalAgyRuntime runtime;
    int launches() => File('${dir.path}/launches').existsSync()
        ? File('${dir.path}/launches').readAsLinesSync().length
        : 0;
    List<String> asked() => File('${dir.path}/asked').existsSync()
        ? File('${dir.path}/asked').readAsLinesSync()
        : const [];

    // Real requests, not the test binding's stand-in client.
    setUpAll(() => HttpOverrides.global = null);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('agy');
      // A stand-in agy: answers initialize and session/list over stdio,
      // opens its "language server" (Connect over HTTP) and writes its
      // port to the log as agy does; logs launches and requests.
      final agy = File('${dir.path}/antigravity')
        ..writeAsStringSync(r'''#!/usr/bin/env python3
import json, os, struct, sys, threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
here = os.path.dirname(sys.argv[0])
open(os.path.join(here, 'launches'), 'a').write('x\n')
log = sys.argv[sys.argv.index('--log-file') + 1]
class H(BaseHTTPRequestHandler):
    def log_message(s, *a): pass
    def do_POST(s):
        n = int(s.headers.get('Content-Length', 0)); raw = s.rfile.read(n)
        method = s.path.rsplit('/', 1)[-1]
        open(os.path.join(here, 'asked'), 'a').write(method + '\n')
        if s.headers.get('Content-Type', '').startswith('application/connect+json'):
            body = json.loads(raw[5:]) if len(raw) > 5 else {}
            s.send_response(200); s.send_header('Content-Type', 'application/connect+json'); s.end_headers()
            def frame(flag, obj):
                data = json.dumps(obj).encode()
                s.wfile.write(bytes([flag]) + struct.pack('>I', len(data)) + data); s.wfile.flush()
            if method == 'Fail':
                frame(2, {'error': {'code': 'unknown', 'message': 'nope'}}); return
            frame(0, {'n': 1, 'echo': body}); frame(0, {'n': 2}); frame(2, {})
            return
        body = json.loads(raw or b'{}')
        if method == 'GetAuthStatus': out, code = {'authResult': {'hasValidAuth': True}}, 200
        elif method == 'Echo': out, code = body, 200
        else: out, code = {'code': 'not_found', 'message': 'unknown method ' + method}, 404
        data = json.dumps(out).encode()
        s.send_response(code); s.send_header('Content-Type', 'application/json')
        s.send_header('Content-Length', str(len(data))); s.end_headers(); s.wfile.write(data)
srv = ThreadingHTTPServer(('127.0.0.1', 0), H)
threading.Thread(target=srv.serve_forever, daemon=True).start()
for line in sys.stdin:
    m = json.loads(line)
    if 'id' not in m: continue
    open(os.path.join(here, 'asked'), 'a').write(m['method'] + '\n')
    r = {}
    if m['method'] == 'session/list':
        with open(log, 'a') as f:
            f.write('I1123 01:48:21.196309 54 server.go:1305] Language server listening on random port at 1 for HTTPS (gRPC)\n')
            f.write('I1123 01:48:21.196875 54 server.go:1313] Language server listening on random port at %d for HTTP\n' % srv.server_address[1])
        r = {'sessions': []}
    print(json.dumps({'jsonrpc': '2.0', 'id': m['id'], 'result': r}), flush=True)
''');
      Process.runSync('chmod', ['+x', agy.path]);
      runtime = LocalAgyRuntime(
        installDir: dir.path,
        dataDir: dir.path,
        stateDir: '${dir.path}/state',
        environment: () async => {
          'HOME': dir.path,
          'PATH': Platform.environment['PATH'] ?? '',
        },
      );
    });

    tearDown(() async {
      await LocalAgyRuntime.stopProcesses();
      dir.deleteSync(recursive: true);
    });

    test('one agy for all, its language server found by its log', () async {
      final server = await runtime.server();
      expect(identical(await runtime.server(), server), isTrue);
      expect(launches(), 1);
      expect(asked(), containsAllInOrder(['initialize', 'session/list']));
      expect(await server.call('Echo', {'a': 1}), {'a': 1});
      expect(
        await server.stream('Watch', {'x': 1}).toList(),
        [
          {
            'n': 1,
            'echo': {'x': 1},
          },
          {'n': 2},
        ],
      );
    }, skip: Platform.isWindows);

    test('what it refuses, and a stream it ends with an error', () async {
      final server = await runtime.server();
      await expectLater(
        server.call('Nope'),
        throwsA(
          isA<AgyError>()
              .having((e) => e.code, 'code', 'not_found')
              .having((e) => e.status, 'status', 404)
              .having((e) => e.message, 'message', 'unknown method Nope'),
        ),
      );
      await expectLater(
        server.stream('Fail').toList(),
        throwsA(isA<AgyError>().having((e) => e.message, 'message', 'nope')),
      );
    }, skip: Platform.isWindows);

    test('started again once gone', () async {
      await runtime.server();
      await LocalAgyRuntime.stopProcesses();
      await runtime.server();
      expect(launches(), 2);
    }, skip: Platform.isWindows);

    test('the app\'s tools served at one address, kept', () async {
      final a = await runtime.serveTools((message) async => {}, key: 'k1');
      final b = await runtime.serveTools((message) async => {}, key: 'k2');
      expect(a.url.port, b.url.port);
      expect(a.url.path, endsWith('/k1'));
      expect(b.url.path, endsWith('/k2'));
      final (url, headers) = (a.url, a.headers);
      await LocalAgyRuntime.stopProcesses();
      final again = await LocalAgyRuntime(
        installDir: dir.path,
        dataDir: dir.path,
        stateDir: '${dir.path}/state',
      ).serveTools((message) async => {}, key: 'k1');
      expect(again.url, url);
      expect(again.headers, headers);
    });
  });
}

/// A [SessionRecord] to keep, made here to keep the import light.
abstract final class SessionRecordFixture {
  static SessionRecord one(String id, String cwd, String title, DateTime at) =>
      SessionRecord(id: id, title: title, updatedAt: at, cwd: cwd);
}
