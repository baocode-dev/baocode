import 'dart:convert';
import 'dart:io';

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

  group('its sign-in', () {
    final json = jsonEncode({
      'token': {
        'access_token': 'ya29.a',
        'refresh_token': '1//r',
        'expiry': '2026-11-22T12:00:00Z',
      },
      'auth_method': 'oauth-personal',
      'id_token_email': 'me@example.com',
    });

    void expectRead(String secret) {
      final credentials = parseAgyCredentials(secret)!;
      expect(credentials.accessToken, 'ya29.a');
      expect(credentials.refreshToken, '1//r');
      expect(credentials.expiry, DateTime.utc(2026, 11, 22, 12));
      expect(credentials.email, 'me@example.com');
    }

    test('as JSON', () => expectRead(json));

    test('as go-keyring keeps it, base64', () {
      expectRead('go-keyring-base64:${base64.encode(utf8.encode(json))}');
    });

    test('as go-keyring keeps it, hex', () {
      final hex = [
        for (final byte in utf8.encode(json))
          byte.toRadixString(16).padLeft(2, '0'),
      ].join();
      expectRead('go-keyring-encoded:$hex');
    });

    test('none without a token', () {
      expect(parseAgyCredentials('{"token":{}}'), isNull);
      expect(parseAgyCredentials('not json'), isNull);
    });

    test('from its file, without a keychain to keep it in', () async {
      final dir = Directory.systemTemp.createTempSync('agy');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/antigravity-oauth-token').writeAsStringSync(json);
      final credentials = await LocalAgyRuntime(dataDir: dir.path)
          .credentials();
      expect(credentials?.accessToken, 'ya29.a');
    });
  });

  test(
    'turns timed in the app\'s own state, gone with the conversation',
    () async {
      final dir = Directory.systemTemp.createTempSync('agy');
      addTearDown(() => dir.deleteSync(recursive: true));
      final runtime = LocalAgyRuntime(
        dataDir: '${dir.path}/agy',
        stateDir: '${dir.path}/state',
      );
      expect(runtime.turnsTimed('s1'), isEmpty);
      runtime
        ..timeTurn('s1', {'text': 'a', 'workedMs': 1})
        ..timeTurn('s1', {'text': 'b', 'workedMs': 2});
      expect([for (final t in runtime.turnsTimed('s1')) t['text']], ['a', 'b']);
      expect(
        File('${dir.path}/state/antigravity/s1.json').existsSync(),
        isTrue,
      );
      await runtime.delete('s1');
      expect(runtime.turnsTimed('s1'), isEmpty);
    },
  );

  test('one deleted goes, in whichever folder agy keeps it', () async {
    final home = Directory.systemTemp.createTempSync('agy');
    addTearDown(() => home.deleteSync(recursive: true));
    final runtime = LocalAgyRuntime(
      dataDir: '${home.path}/antigravity-cli',
      stateDir: '${home.path}/state',
    );
    final files = [
      // agy's own, and the Antigravity app's beside it, which agy lists.
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

  group('a spare', () {
    late Directory dir;
    late LocalAgyRuntime runtime;
    int launches() => File('${dir.path}/launches').existsSync()
        ? File('${dir.path}/launches').readAsLinesSync().length
        : 0;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('agy');
      // A stand-in agy: answers initialize and session/list, logs launches.
      final agy = File('${dir.path}/antigravity')
        ..writeAsStringSync("""#!/usr/bin/env python3
import json, os, sys
open(os.path.join(os.path.dirname(sys.argv[0]), 'launches'), 'a').write('x\\n')
for line in sys.stdin:
    m = json.loads(line)
    if 'id' not in m: continue
    r = {'sessions': [{'sessionId': 'a', 'cwd': '/x', 'title': 't'}]} if m['method'] == 'session/list' else {}
    print(json.dumps({'jsonrpc': '2.0', 'id': m['id'], 'result': r}), flush=True)
""");
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

    test(
      'a listing leaves agy booted: listed again and started on, no new one',
      () async {
        expect((await runtime.sessions()).single.id, 'a');
        expect((await runtime.sessions()).single.id, 'a');
        expect(launches(), 1);
        await runtime.start(dir.path);
        // Taken, another is booted for the next.
        for (var i = 0; i < 100 && launches() < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(launches(), 2);
      },
      skip: Platform.isWindows,
    );
  });
}
