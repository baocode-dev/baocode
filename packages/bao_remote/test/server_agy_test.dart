import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/acp.dart';
import 'package:bao_remote/client.dart';
import 'package:bao_remote/files.dart' show IdeFileNotFoundException;
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:bao_remote/server.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

class _TestHarness {
  _TestHarness._(this.server, this.client, this.dataDir);

  static Future<_TestHarness> start() async {
    final dataDir = Directory.systemTemp.createTempSync('baocode-agy-test-');
    final toServer = StreamController<String>();
    final toClient = StreamController<String>();
    final server = RemoteServer(
      RpcPeer(toServer.stream, toClient.add),
      dataDir: dataDir.path,
      version: 'test',
    );
    final client = RemoteClient(RpcPeer(toClient.stream, toServer.add));
    await client.initialize();
    return _TestHarness._(server, client, dataDir);
  }

  final RemoteServer server;
  final RemoteClient client;
  final Directory dataDir;

  ManagedAgy get managed => ManagedAgy(p.join(dataDir.path, 'antigravity'));

  Future<void> close() async {
    await server.shutdown();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  }
}

/// Builds a `.tar.gz` archive containing an `antigravity` executable script
/// and returns `(archiveFile, build)`.
(File, AgyBuild) _makeTarGzBuild(
  Directory dir, {
  required String version,
  required String target,
  required String scriptBody,
}) {
  final src = Directory(p.join(dir.path, 'src-$version'))
    ..createSync(recursive: true);
  final bin = File(p.join(src.path, 'antigravity'))
    ..writeAsStringSync(scriptBody);
  if (!Platform.isWindows) {
    Process.runSync('chmod', ['755', bin.path]);
  }
  final archive = File(p.join(dir.path, 'antigravity-$version.tar.gz'));
  final tar = Process.runSync('tar', [
    '-czf',
    archive.path,
    '-C',
    src.path,
    'antigravity',
  ]);
  if (tar.exitCode != 0) {
    fail('tar failed: ${tar.stderr}');
  }
  final digest = sha512.convert(archive.readAsBytesSync()).toString();
  final build = AgyBuild(
    version: version,
    target: target,
    url:
        'https://storage.googleapis.com/antigravity-public/antigravity-cli/$version/antigravity_$target.tar.gz',
    sha512: digest,
  );
  return (archive, build);
}

void main() {
  group('Protocol & RpcError', () {
    test('RemoteProtocol.version is 13 and AgyUnavailable round-trips', () {
      expect(RemoteProtocol.version, 13);
      const original = AgyUnavailable(
        'Sign in required',
        notInstalled: true,
        signIn: true,
        detail: 'No cached token',
      );
      final encoded = RpcError.from(original).toJson();
      final decoded = RpcError.fromJson(encoded).toException();
      expect(decoded, isA<AgyUnavailable>());
      final error = decoded as AgyUnavailable;
      expect(error.message, 'Sign in required');
      expect(error.notInstalled, isTrue);
      expect(error.signIn, isTrue);
      expect(error.detail, 'No cached token');
    });
  });

  group('ServerAgyRuntime environment & proxy helpers', () {
    test('injects headless Linux file token storage and disables auto-update', () {
      final headless = ServerAgyRuntime.buildProcessEnvironment(
        {'PATH': '/usr/bin'},
        {'HTTPS_PROXY': 'http://127.0.0.1:7890'},
        isLinux: true,
      );
      expect(headless['AGY_CLI_DISABLE_AUTO_UPDATE'], '1');
      expect(headless['AGY_CLI_FORCE_FILE_TOKEN_STORAGE'], '1');
      expect(headless['HTTPS_PROXY'], 'http://127.0.0.1:7890');

      final desktopLinux = ServerAgyRuntime.buildProcessEnvironment(
        {'DISPLAY': ':0'},
        const {},
        isLinux: true,
      );
      expect(desktopLinux.containsKey('AGY_CLI_FORCE_FILE_TOKEN_STORAGE'), isFalse);

      final explicitLinux = ServerAgyRuntime.buildProcessEnvironment(
        const {},
        {'AGY_CLI_FORCE_FILE_TOKEN_STORAGE': '0'},
        isLinux: true,
      );
      expect(explicitLinux['AGY_CLI_FORCE_FILE_TOKEN_STORAGE'], '0');

      final macos = ServerAgyRuntime.buildProcessEnvironment(
        const {},
        const {},
        isLinux: false,
      );
      expect(macos['AGY_CLI_DISABLE_AUTO_UPDATE'], '1');
      expect(macos.containsKey('AGY_CLI_FORCE_FILE_TOKEN_STORAGE'), isFalse);
    });

    test('findProxyForEnvironment honors HTTP_PROXY, HTTPS_PROXY, ALL_PROXY, NO_PROXY', () {
      expect(ServerAgyRuntime.findProxyForEnvironment(const {}), isNull);

      final fromHttps = ServerAgyRuntime.findProxyForEnvironment({
        'HTTPS_PROXY': 'http://proxy.internal:8080',
        'NO_PROXY': 'bypass.local,.corp.test',
      })!;
      expect(
        fromHttps(Uri.parse('https://storage.googleapis.com/a')),
        contains('PROXY proxy.internal:8080'),
      );
      expect(fromHttps(Uri.parse('https://bypass.local/a')), 'DIRECT');
      expect(fromHttps(Uri.parse('https://api.corp.test/a')), 'DIRECT');

      final fromAll = ServerAgyRuntime.findProxyForEnvironment({
        'ALL_PROXY': 'http://127.0.0.1:7890',
      })!;
      expect(
        fromAll(Uri.parse('https://example.com')),
        contains('PROXY 127.0.0.1:7890'),
      );
      expect(
        fromAll(Uri.parse('http://example.com')),
        contains('PROXY 127.0.0.1:7890'),
      );
    });
  });

  group('AgyCommandLine.parse', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('agy-cli-parse-');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('parses all ClaudeLaunch flags, settings, mcp-config, and prompt splitting', () {
      final settingsFile = File(p.join(tempDir.path, 'settings.json'))
        ..writeAsStringSync(
          jsonEncode({
            'effortLevel': 'high',
            'env': {'FOO': 'bar'},
          }),
        );
      final promptFile = File(p.join(tempDir.path, 'prompt.txt'))
        ..writeAsStringSync(
          '${AgyLaunchOptions.defaultAppendedSystemPrompt}\n\nExtra workspace instructions.',
        );

      final parsed = AgyCommandLine.parse(
        [
          '-p',
          '--print',
          '--verbose',
          '--include-partial-messages',
          '--replay-user-messages',
          '--allow-dangerously-skip-permissions',
          '--permission-prompt-tool',
          'stdio',
          '--thinking-display',
          'summarized',
          '--input-format',
          'stream-json',
          '--output-format',
          'stream-json',
          '--permission-mode',
          'acceptEdits',
          '--model',
          'gemini-3.8-flash',
          '--effort',
          'high',
          '--autocompact',
          '250000',
          '-r',
          'sess-42',
          '--add-dir',
          '/extra/one',
          '--add-dir',
          '/extra/two',
          '--settings',
          settingsFile.path,
          '--settings',
          jsonEncode({'extraKey': true}),
          '--no-session-persistence',
          '--mcp-config',
          jsonEncode({
            'mcpServers': {
              'baocode': {'type': 'sdk', 'name': 'baocode'},
              'ext': {'command': 'node', 'args': ['server.js']},
            },
          }),
          '--strict-mcp-config',
          '--allowedTools',
          'mcp__baocode,Read',
          '--tools',
          'Read,Edit',
          '--append-system-prompt-file',
          promptFile.path,
          '--agy-root',
          '/srv/agy',
        ],
        cwd: '/repo',
        environment: {'HOME': '/home/dev'},
      );

      expect(parsed.agyRoot, '/srv/agy');
      expect(parsed.inputFormat, 'stream-json');
      expect(parsed.outputFormat, 'stream-json');
      final o = parsed.options;
      expect(o.cwd, '/repo');
      expect(o.resume, 'sess-42');
      expect(o.model, 'gemini-3.8-flash');
      expect(o.permissionMode, 'acceptEdits');
      expect(o.effort, 'high');
      expect(o.autocompact, 250000);
      expect(o.persist, isFalse);
      expect(o.directories, ['/extra/one', '/extra/two']);
      expect(o.sdkServers, ['baocode']);
      expect(o.flagSettings['effortLevel'], 'high');
      expect(o.flagSettings['extraKey'], isTrue);
      expect(
        (o.flagSettings['mcpServers'] as Map).containsKey('ext'),
        isTrue,
      );
      expect(
        (o.flagSettings['mcpServers'] as Map).containsKey('baocode'),
        isFalse,
      );
      expect(
        (o.flagSettings['permissions'] as Map)['allow'],
        containsAll(['mcp__baocode', 'Read']),
      );
      expect(
        o.appendedSystemPrompt,
        AgyLaunchOptions.defaultAppendedSystemPrompt,
      );
      expect(o.instructions, 'Extra workspace instructions.');
    });

    test('preserves custom --append-system-prompt without default prefix as instructions', () {
      final parsed = AgyCommandLine.parse(
        [
          '--dangerously-skip-permissions',
          '--append-system-prompt',
          'Custom prompt without default header',
        ],
        cwd: '/repo',
        environment: const {},
      );
      expect(parsed.options.permissionMode, 'bypassPermissions');
      expect(
        parsed.options.appendedSystemPrompt,
        AgyLaunchOptions.defaultAppendedSystemPrompt,
      );
      expect(
        parsed.options.instructions,
        'Custom prompt without default header',
      );
    });

    test('supports --system-prompt and --system-prompt-file', () {
      final sysFile = File(p.join(tempDir.path, 'sys.txt'))
        ..writeAsStringSync('Bot system instructions');
      final parsed = AgyCommandLine.parse(
        ['--system-prompt-file', sysFile.path],
        cwd: '/repo',
        environment: const {},
      );
      expect(parsed.options.instructions, 'Bot system instructions');
    });
  });

  group('RemoteServer <-> RemoteClient Antigravity RPCs', () {
    late _TestHarness harness;
    late Directory workDir;
    late String target;

    setUp(() async {
      ManagedAgy.systemCandidatesOverride = (_) => const [];
      harness = await _TestHarness.start();
      workDir = Directory.systemTemp.createTempSync('baocode-agy-work-');
      target = AgyRelease.targetOf(harness.client.hello!.platform);
    });

    tearDown(() async {
      ManagedAgy.systemCandidatesOverride = null;
      AgyRelease.feedOverride = null;
      AgyRelease.downloadsPrefixOverride = null;
      ServerAgy.selfCommand = null;
      await harness.close();
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
    });

    test('prefers existing system-installed antigravity binary over managed copy', () async {
      final sysBin = File(p.join(workDir.path, 'antigravity'))
        ..writeAsStringSync('''#!/bin/sh
if [ "\$1" = "--version" ]; then
  echo "antigravity 3.1.4"
  exit 0
fi
if [ "\$1" = "models" ]; then
  printf 'system-model\\tSystem Model\\n'
  exit 0
fi
''');
      if (!Platform.isWindows) {
        Process.runSync('chmod', ['755', sysBin.path]);
      }
      ManagedAgy.systemCandidatesOverride = (_) => [sysBin.path];

      expect(await harness.client.agyVersion(), '3.1.4');
      final models = await harness.client.agyModels();
      expect(models.map((m) => m.id).toList(), ['system-model']);
    });

    test('agyInstall honors fast probeTimeoutMs when direct feed stalls', () async {
      final stalled = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => stalled.close(force: true));
      stalled.listen((req) {
        // Deliberately never reply so probeTimeout triggers quickly.
      });
      AgyRelease.feedOverride = 'http://127.0.0.1:${stalled.port}/manifests';

      final sw = Stopwatch()..start();
      await expectLater(
        harness.client.agyInstall(
          probeTimeout: const Duration(milliseconds: 250),
        ),
        throwsA(isA<AgyUnavailable>()),
      );
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(2500));
    });

    test('agyVersion is null before install and startClaude(core: agy) throws typed errors', () async {
      expect(await harness.client.agyVersion(), isNull);

      await expectLater(
        harness.client.startClaude(
          cwd: p.join(workDir.path, 'missing'),
          arguments: const [],
          core: 'agy',
        ),
        throwsA(isA<IdeFileNotFoundException>()),
      );

      await expectLater(
        harness.client.startClaude(
          cwd: workDir.path,
          arguments: const [],
          core: 'agy',
        ),
        throwsA(
          isA<AgyUnavailable>().having(
            (e) => e.notInstalled,
            'notInstalled',
            isTrue,
          ),
        ),
      );
    });

    test(
      'agyUpload verifies SHA-512, unpacks .tar.gz in chunks, and installs',
      () async {
        final (archive, build) = _makeTarGzBuild(
          workDir,
          version: '1.8.0',
          target: target,
          scriptBody: '#!/bin/sh\necho "mock-agy 1.8.0"\n',
        );

        // Wrong target rejected.
        final wrongTargetBuild = AgyBuild(
          version: build.version,
          target: target == 'linux_amd64' ? 'darwin_arm64' : 'linux_amd64',
          url: build.url,
          sha512: build.sha512,
        );
        await expectLater(
          harness.client.agyUpload(wrongTargetBuild, archive),
          throwsA(isA<AgyUnavailable>()),
        );

        // Wrong SHA-512 rejected.
        final badShaBuild = AgyBuild(
          version: build.version,
          target: build.target,
          url: build.url,
          sha512: '0' * 128,
        );
        await expectLater(
          harness.client.agyUpload(badShaBuild, archive, chunkSize: 128),
          throwsA(
            isA<AgyUnavailable>().having(
              (e) => e.detail,
              'detail',
              contains('checksum'),
            ),
          ),
        );

        // Valid chunked upload succeeds.
        final progress = <(int, int)>[];
        final installedVersion = await harness.client.agyUpload(
          build,
          archive,
          chunkSize: 128,
          onProgress: (sent, size) => progress.add((sent, size)),
        );
        expect(installedVersion, '1.8.0');
        expect(await harness.client.agyVersion(), '1.8.0');
        expect(progress, isNotEmpty);
        expect(progress.last.$1, archive.lengthSync());
        expect(progress.last.$2, archive.lengthSync());

        final exe = await harness.managed.executable();
        final run = Process.runSync(exe, const []);
        expect(run.exitCode, 0);
        expect('${run.stdout}'.trim(), 'mock-agy 1.8.0');
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );

    test(
      'agyLatestVersion and agyInstall fetch from release feed with progress',
      () async {
        final (archive, tarBuild) = _makeTarGzBuild(
          workDir,
          version: '1.9.2',
          target: target,
          scriptBody: '#!/bin/sh\necho "installed-via-feed"\n',
        );
        final archiveBytes = archive.readAsBytesSync();

        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final baseUrl = 'http://127.0.0.1:${server.port}';
        server.listen((request) async {
          final res = request.response;
          if (request.uri.path == '/manifests/$target.json') {
            res.write(
              jsonEncode({
                'version': '1.9.2',
                'url': '$baseUrl/downloads/1.9.2/antigravity_$target.tar.gz',
                'sha512': tarBuild.sha512,
              }),
            );
          } else if (request.uri.path ==
              '/downloads/1.9.2/antigravity_$target.tar.gz') {
            res.contentLength = archiveBytes.length;
            res.add(archiveBytes);
          } else {
            res.statusCode = HttpStatus.notFound;
          }
          await res.close();
        });

        AgyRelease.feedOverride = '$baseUrl/manifests';
        AgyRelease.downloadsPrefixOverride = '$baseUrl/downloads/';

        expect(await harness.client.agyLatestVersion(), '1.9.2');

        final progress = <(int, int)>[];
        await harness.client.agyInstall(
          onProgress: (received, total) => progress.add((received, total)),
        );
        expect(await harness.client.agyVersion(), '1.9.2');
        expect(progress, isNotEmpty);
        expect(progress.last.$1, archiveBytes.length);
        expect(progress.last.$2, archiveBytes.length);
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );

    test(
      'agyModels parses models and maps unauthenticated output to signIn error',
      () async {
        final (archive1, build1) = _makeTarGzBuild(
          workDir,
          version: '1.8.1',
          target: target,
          scriptBody: '''#!/bin/sh
if [ "\$1" = "models" ]; then
  printf 'gemini-3.8-flash-low\tGemini 3.8 Flash (Low)\\n'
  printf 'gemini-3.8-flash-high\tGemini 3.8 Flash (High)\\n'
  printf 'claude-sonnet-4\tClaude Sonnet 4\\n'
  exit 0
fi
exit 1
''',
        );
        await harness.client.agyUpload(build1, archive1);

        final models = await harness.client.agyModels();
        expect(models, [
          const AgyModel(
            'gemini-3.8-flash',
            'Gemini 3.8 Flash',
            efforts: ['low', 'high'],
          ),
          const AgyModel('claude-sonnet-4', 'Claude Sonnet 4'),
        ]);

        // Replace with unauthenticated mock.
        final (archive2, build2) = _makeTarGzBuild(
          workDir,
          version: '1.8.2',
          target: target,
          scriptBody: '''#!/bin/sh
if [ "\$1" = "models" ]; then
  echo "Error: Please sign in first" >&2
  exit 1
fi
exit 1
''',
        );
        await harness.client.agyUpload(build2, archive2);

        await expectLater(
          harness.client.agyModels(),
          throwsA(
            isA<AgyUnavailable>().having((e) => e.signIn, 'signIn', isTrue),
          ),
        );
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );

    test(
      'agySignIn streams line + URL events, accepts authCode, and kills process on cancel',
      () async {
        final markerFile = File(p.join(workDir.path, 'login-pid.txt'));
        final codeFile = File(p.join(workDir.path, 'received-code.txt'));
        final (archive, build) = _makeTarGzBuild(
          workDir,
          version: '1.8.3',
          target: target,
          scriptBody: '''#!/bin/sh
if [ "\$1" = "acp" ] && [ "\$2" = "--login" ]; then
  echo \$\$ > "${markerFile.path}"
  if [ "\$MOCK_MODE" = "cancel" ]; then
    echo "Open https://accounts.google.com/o/oauth2/v2/auth?client_id=abc&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob"
    sleep 30
    exit 0
  fi
  echo "Please open https://accounts.google.com/o/oauth2/v2/auth?client_id=abc&redirect_uri=http%3A%2F%2F127.0.0.1%3A45678%2Foauth2callback."
  IFS= read -r code
  echo "\$code" > "${codeFile.path}"
  if [ "\$code" = "expected-code-99" ]; then
    echo "Signed in!"
    exit 0
  fi
  echo "Invalid code" >&2
  exit 1
fi
exit 1
''',
        );
        await harness.client.agyUpload(build, archive);

        // 1. Happy path: loopback URL + code submission + done.
        final events = <Map<String, Object?>>[];
        final urlReceived = Completer<void>();
        final done = Completer<void>();
        final sub = harness.client.agySignIn().listen(
          (event) {
            events.add(event);
            if (event['type'] == 'url' && !urlReceived.isCompleted) {
              urlReceived.complete();
            }
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          onError: (Object error) {
            if (!done.isCompleted) done.completeError(error);
          },
        );
        await urlReceived.future.timeout(const Duration(seconds: 5));
        final urlEvent = events.firstWhere((e) => e['type'] == 'url');
        expect(
          urlEvent['url'],
          'https://accounts.google.com/o/oauth2/v2/auth?client_id=abc&redirect_uri=http%3A%2F%2F127.0.0.1%3A45678%2Foauth2callback',
        );
        expect(urlEvent['callbackPort'], 45678);
        expect(urlEvent['needsCode'], isFalse);

        await harness.client.agySubmitAuthCode('expected-code-99');
        await done.future.timeout(const Duration(seconds: 5));
        await sub.cancel();

        expect(codeFile.readAsStringSync().trim(), 'expected-code-99');
        expect(events.any((e) => e['type'] == 'line'), isTrue);
        expect(events.last, {'type': 'done'});

        // 2. Cancel path: OOB URL (needsCode: true) + cancelling stream kills process.
        if (markerFile.existsSync()) markerFile.deleteSync();
        final cancelUrl = Completer<Map<String, Object?>>();
        final cancelSub = harness.client
            .agySignIn(environment: const {'MOCK_MODE': 'cancel'})
            .listen((event) {
              if (event['type'] == 'url' && !cancelUrl.isCompleted) {
                cancelUrl.complete(event);
              }
            });
        final oobEvent = await cancelUrl.future.timeout(
          const Duration(seconds: 5),
        );
        expect(oobEvent['callbackPort'], isNull);
        expect(oobEvent['needsCode'], isTrue);
        final loginPid = int.parse(markerFile.readAsStringSync().trim());
        await cancelSub.cancel();

        // Wait briefly and verify the process exited.
        var alive = true;
        for (var i = 0; i < 30; i++) {
          final check = Process.runSync('kill', ['-0', '$loginPid']);
          if (check.exitCode != 0) {
            alive = false;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(alive, isFalse);
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );

    test(
      'agySignOut sends ACP logout',
      () async {
        final logoutLog = File(p.join(workDir.path, 'logout.log'));
        final (archive, build) = _makeTarGzBuild(
          workDir,
          version: '1.8.4',
          target: target,
          scriptBody: '''#!/bin/sh
while IFS= read -r line; do
  case "\$line" in
    *'"method":"initialize"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":1}}\\n' "\$id"
      ;;
    *'"method":"logout"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      echo "logged-out" > "${logoutLog.path}"
      printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "\$id"
      ;;
  esac
done
''',
        );
        await harness.client.agyUpload(build, archive);
        await harness.client.agySignOut();
        expect(logoutLog.existsSync(), isTrue);
        expect(logoutLog.readAsStringSync().trim(), 'logged-out');
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );

    test('agySwarmSnapshot, agySwarmTranscript, and agyDeleteSession', () async {
      const swarmId = '11111111-2222-3333-4444-555555555555';
      const workerConvId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
      final swarmDir = Directory(
        p.join(harness.managed.brainDir, swarmId, '.system_generated', 'swarm'),
      )..createSync(recursive: true);
      File(p.join(swarmDir.path, 'members.json')).writeAsStringSync(
        jsonEncode({
          'title': 'Remote Swarm Test',
          'members': {
            'coordinator': {
              'conversation_id': swarmId,
              'role': 'coordinator',
              'status': 'working',
            },
            'worker-a': {
              'conversation_id': workerConvId,
              'role': 'worker',
              'status': 'waiting',
              'model': 'gemini-3.8-flash',
            },
          },
        }),
      );
      File(p.join(swarmDir.path, 'board.jsonl')).writeAsStringSync(
        '${jsonEncode({'seq': 1, 'agent': 'coordinator', 'text': '@worker-a run checks', 'time': '2026-11-28 21:00:00'})}\n',
      );
      final transcriptFile = File(
        p.join(
          harness.managed.brainDir,
          workerConvId,
          '.system_generated',
          'logs',
          'transcript.jsonl',
        ),
      )..parent.createSync(recursive: true);
      transcriptFile.writeAsStringSync(
        '${jsonEncode({'step_index': 1, 'type': 'PLANNER_RESPONSE', 'thinking': 'Checking files', 'content': 'All good', 'created_at': '2026-11-28T21:00:01Z'})}\n',
      );

      expect(await harness.client.agySwarmSnapshot('missing-swarm'), isNull);

      final snapshot = await harness.client.agySwarmSnapshot(swarmId);
      expect(snapshot, isNotNull);
      expect(snapshot!.swarmId, swarmId);
      expect(snapshot.title, 'Remote Swarm Test');
      expect(snapshot.members.length, 2);
      expect(snapshot.messages.length, 1);
      expect(snapshot.messages.first.text, '@worker-a run checks');

      final steps = await harness.client.agySwarmTranscript(workerConvId);
      expect(steps, isNotEmpty);

      // Delete session removes its brain directory.
      await harness.client.agyDeleteSession(swarmId);
      expect(
        Directory(p.join(harness.managed.brainDir, swarmId)).existsSync(),
        isFalse,
      );
    });

    test('claudeDelete cleans up linked antigravity-session data', () async {
      const claudeId = 'claude-session-for-agy-cleanup';
      const agyId = '22222222-3333-4444-5555-666666666666';
      final agyBrain = Directory(p.join(harness.managed.brainDir, agyId))
        ..createSync(recursive: true);

      // Write a session file under the resolved Claude config directory.
      final configDir = await ClaudeEnvironment.configDir();
      final projectDir = Directory(
        p.join(configDir, 'projects', 'server-agy-test-tmp'),
      )..createSync(recursive: true);
      final sessionFile = File(p.join(projectDir.path, '$claudeId.jsonl'))
        ..writeAsStringSync(
          '${jsonEncode({'type': AgyTransportCore.syncType, 'agySessionId': agyId})}\n',
        );
      addTearDown(() {
        if (sessionFile.existsSync()) sessionFile.deleteSync();
        if (projectDir.existsSync() && projectDir.listSync().isEmpty) {
          projectDir.deleteSync();
        }
      });

      await harness.client.claudeDelete(claudeId);
      expect(sessionFile.existsSync(), isFalse);
      expect(agyBrain.existsSync(), isFalse);
    });

    test(
      'end-to-end baocode_server.dart agy with mock antigravity ACP script',
      () async {
        final (archive, build) = _makeTarGzBuild(
          workDir,
          version: '1.9.0',
          target: target,
          scriptBody: '''#!/bin/sh
while IFS= read -r line; do
  case "\$line" in
    *'"method":"initialize"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":1}}\\n' "\$id"
      ;;
    *'"method":"session/list"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","id":%s,"result":{"sessions":[]}}\\n' "\$id"
      ;;
    *'"method":"session/new"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","id":%s,"result":{"sessionId":"12345678-1111-2222-3333-444444444444"}}\\n' "\$id"
      ;;
    *'"method":"session/set_config_option"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","id":%s,"result":{}}\\n' "\$id"
      ;;
    *'"method":"session/prompt"'*)
      id=\$(echo "\$line" | sed -n 's/.*"id":\\([0-9]*\\).*/\\1/p')
      printf '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"12345678-1111-2222-3333-444444444444","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Hello from remote agy!"}}}}\\n'
      printf '{"jsonrpc":"2.0","id":%s,"result":{"stopReason":"end_turn"}}\\n' "\$id"
      ;;
  esac
done
''',
        );
        await harness.client.agyUpload(build, archive);

        // Point ServerAgy.selfCommand to `dart bin/baocode_server.dart`.
        final serverScript = p.normalize(
          p.join(Directory.current.path, 'bin', 'baocode_server.dart'),
        );
        final resolvedScript = File(serverScript).existsSync()
            ? serverScript
            : p.normalize(
                p.join(
                  Directory.current.path,
                  'packages',
                  'bao_remote',
                  'bin',
                  'baocode_server.dart',
                ),
              );
        expect(File(resolvedScript).existsSync(), isTrue);
        ServerAgy.selfCommand = () => [
          Platform.resolvedExecutable,
          resolvedScript,
        ];

        final claudeConfigDir = Directory(p.join(workDir.path, 'claude-cfg'))
          ..createSync(recursive: true);

        final proc = await harness.client.startClaude(
          cwd: workDir.path,
          core: 'agy',
          arguments: const [
            '-p',
            '--input-format',
            'stream-json',
            '--output-format',
            'stream-json',
            '--verbose',
            '--model',
            'gemini-3.8-flash',
            '--no-session-persistence',
          ],
          environment: {
            'CLAUDE_CONFIG_DIR': claudeConfigDir.path,
            'BAOCODE_AGY_IGNORE_SYSTEM': '1',
          },
        );

        final received = <Map<String, Object?>>[];
        final initDone = Completer<void>();
        final resultDone = Completer<Map<String, Object?>>();
        final stderrBuf = StringBuffer();

        proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(
          stderrBuf.write,
        );
        proc.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((line) {
              if (line.trim().isEmpty) return;
              final msg = (jsonDecode(line) as Map).cast<String, Object?>();
              received.add(msg);
              if (msg['type'] == 'control_response' && !initDone.isCompleted) {
                initDone.complete();
              }
              if (msg['type'] == 'result' && !resultDone.isCompleted) {
                resultDone.complete(msg);
              }
            });

        void send(Map<String, Object?> msg) =>
            proc.write(utf8.encode('${jsonEncode(msg)}\n'));

        send({
          'type': 'control_request',
          'request_id': 'req-1',
          'request': {'subtype': 'initialize'},
        });
        await initDone.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => fail('Init timed out; stderr: $stderrBuf'),
        );

        send({
          'type': 'user',
          'uuid': 'user-1',
          'message': {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': 'Say hi'},
            ],
          },
        });
        final result = await resultDone.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => fail('Turn timed out; stderr: $stderrBuf'),
        );
        expect(result['is_error'], isNot(true));

        final assistantTexts = [
          for (final msg in received)
            if (msg['type'] == 'assistant')
              for (final block
                  in ((msg['message'] as Map?)?['content'] as List? ??
                      const []))
                if (block is Map && block['type'] == 'text') block['text'],
        ];
        expect(assistantTexts.join(), contains('Hello from remote agy!'));
        // Never emit transport_exit over stdout (parent synthesizes it).
        expect(received.any((m) => m['type'] == 'transport_exit'), isFalse);

        await proc.closeStdin();
        final exitCode = await proc.exitCode.timeout(
          const Duration(seconds: 10),
        );
        expect(exitCode, 0);
      },
      skip: Platform.isWindows ? 'POSIX shell/tar test' : false,
    );
  });
}
