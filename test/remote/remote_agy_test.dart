@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bao_remote/acp.dart' show ManagedAgy;
import 'package:bao_remote/client.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment;
import 'package:bao_remote/server.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/mock_claude_code_transport.dart';
import 'package:baocode/kernel/kernel_event.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/network/network_proxy_io.dart';
import 'package:baocode/network/proxy_settings.dart';
import 'package:baocode/remote/remote_agy.dart';
import 'package:baocode/remote/remote_claude.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

void main() {
  late Directory dataDir;
  late Directory home;
  late Directory marks;
  late String root;
  late MemoryConnector connector;
  late SshHosts hosts;
  late _FakeAgyFeed feed;
  late String target;
  late NetworkProxy previousProxy;
  final previousHosts = SshHosts.instance;

  setUp(() async {
    HttpOverrides.global = null;
    previousProxy = NetworkProxy.instance;
    NetworkProxy.instance = NetworkProxy(
      system: () async => const ProxyRoute.direct(),
      environment: () async => const {},
    );
    dataDir = Directory.systemTemp.createTempSync('baocode-remote-agy-data-');
    home = Directory.systemTemp.createTempSync('baocode-remote-agy-home-');
    marks = Directory(p.join(home.path, 'marks'))..createSync();
    final project = Directory(p.join(home.path, 'project'))..createSync();
    root = project.resolveSymbolicLinksSync();

    connector = MemoryConnector(dataDir.path);
    hosts = SshHosts.instance = SshHosts(connect: connector.call);
    ManagedAgy.systemCandidatesOverride = (_) => const [];
    RemoteAgySetups.instance = RemoteAgySetups(hosts: hosts);
    ClaudeEnvironment.use({
      'PATH': '/usr/bin:/bin',
      'HOME': home.path,
      'MARKS': marks.path,
    });

    final client = await hosts['dev'].ready;
    target = AgyRelease.targetOf(client.hello!.platform);
    feed = await _FakeAgyFeed.start(
      workDir: home,
      target: target,
      version: '2.4.0',
      scriptBody: _mockAgyScript,
    );
    AgyRelease.feedOverride = feed.feedUrl;
    AgyRelease.downloadsPrefixOverride = feed.downloadsPrefix;
  });

  tearDown(() async {
    ServerAgy.selfCommand = null;
    ManagedAgy.systemCandidatesOverride = null;
    AgyRelease.feedOverride = null;
    AgyRelease.downloadsPrefixOverride = null;
    ClaudeEnvironment.use(null);
    NetworkProxy.instance = previousProxy;
    RemoteAgySetups.instance.reset();
    RemoteAgySetups.instance = RemoteAgySetups();
    await hosts.closeAll();
    SshHosts.instance = previousHosts;
    await feed.close();
    for (final dir in [dataDir, home]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  String mark(String name) =>
      File(p.join(marks.path, name)).readAsStringSync().trim();

  group('installRemoteAgy', () {
    test(
      'downloads directly on remote host, updates installingAgy & onProgress, '
      'and clears state after completion',
      () async {
        final host = hosts['dev'];
        final bannerProgress = <ClaudeInstallProgress>[];
        host.addListener(() {
          if (host.installingAgy case final progress?) {
            bannerProgress.add(progress);
          }
        });
        final fractions = <double>[];

        await installRemoteAgy(host, onProgress: fractions.add);

        final client = await host.ready;
        expect(await client.agyVersion(), '2.4.0');
        expect(host.installingAgy, isNull);
        expect(bannerProgress, isNotEmpty);
        expect(bannerProgress.any((p) => p.uploading), isFalse);
        expect(bannerProgress.last.received, feed.archiveBytes.length);
        expect(fractions, isNotEmpty);
        expect(fractions.last, 1.0);
        expect(feed.manifestRequests, 1);
        expect(feed.archiveRequests, 1);
      },
    );

    test(
      'falls back to local download + SHA-512 cache + chunked upload when '
      'remote download fails',
      () async {
        // First manifest request (from remote host) fails with 503.
        feed.failNextRequests = 1;
        final host = hosts['dev'];
        final downloads = Directory(p.join(home.path, 'downloads'));
        final seen = <ClaudeInstallProgress>[];
        host.addListener(() {
          if (host.installingAgy case final progress?) seen.add(progress);
        });
        final fractions = <double>[];

        await installRemoteAgy(
          host,
          downloads: downloads,
          onProgress: fractions.add,
        );

        final client = await host.ready;
        expect(await client.agyVersion(), '2.4.0');
        expect(host.installingAgy, isNull);
        expect(seen.where((p) => p.uploading), isNotEmpty);
        expect(seen.last.uploading, isTrue);
        expect(seen.last.received, feed.archiveBytes.length);
        expect(fractions, isNotEmpty);
        expect(fractions.last, 1.0);

        final cachedFile = File(
          p.join(downloads.path, 'agy-2.4.0-$target.tar.gz'),
        );
        expect(cachedFile.existsSync(), isTrue);
        expect(
          await AgyRelease.verifySha512(cachedFile, feed.sha512Hex),
          isTrue,
        );
        expect(feed.archiveRequests, 1);

        // Second fallback reuses SHA-512-verified cache file without
        // re-downloading the archive from the release server.
        feed.failNextRequests = 1;
        final secondSeen = <ClaudeInstallProgress>[];
        void listener() {
          if (host.installingAgy case final progress?) secondSeen.add(progress);
        }

        host.addListener(listener);
        try {
          await installRemoteAgy(host, downloads: downloads);
        } finally {
          host.removeListener(listener);
        }
        expect(feed.archiveRequests, 1);
        expect(secondSeen.where((p) => p.uploading), isNotEmpty);
        expect(host.installingAgy, isNull);
      },
    );

    test('deduplicates concurrent installations for the same host', () async {
      final host = hosts['dev'];
      final a = <double>[];
      final b = <double>[];

      await Future.wait([
        installRemoteAgy(host, onProgress: a.add),
        installRemoteAgy(host, onProgress: b.add),
      ]);

      expect(feed.archiveRequests, 1);
      expect(a, isNotEmpty);
      expect(b, isNotEmpty);
      expect(a.last, 1.0);
      expect(b.last, 1.0);
      expect(host.installingAgy, isNull);
    });
  });

  group('RemoteAgyRuntime', () {
    test(
      'delegates version, latestVersion, models, signOut, deleteSession, '
      'warm, stopAll, and throws UnsupportedError on start',
      () async {
        final host = hosts['dev'];
        final runtime = RemoteAgyRuntime(host);

        expect(await runtime.version(), isNull);
        await runtime.install();
        expect(await runtime.version(), '2.4.0');
        expect(await runtime.latestVersion(), '2.4.0');

        // Configure a loopback manual proxy to verify proxy env forwarding.
        final dummyProxy = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(dummyProxy.close);
        NetworkProxy.instance = NetworkProxy(
          system: () async => ProxyRoute.manual(
            ProxyServer.parse('http://127.0.0.1:${dummyProxy.port}')!,
          ),
          environment: () async => const {},
        );

        final models = await runtime.models();
        expect(models, [
          const AgyModel(
            'gemini-3-pro',
            'Gemini 3 Pro',
            efforts: ['low', 'high'],
          ),
        ]);
        expect(mark('models_https_proxy'), startsWith('http://127.0.0.1:'));
        expect(mark('models_no_proxy'), contains('127.0.0.1'));

        await runtime.signOut();
        expect(mark('signed_out'), 'yes');

        final managed = ManagedAgy(p.join(dataDir.path, 'antigravity'));
        final sessionFile = File(
          p.join(managed.home, 'antigravity-cli', 'sessions', 'sess-12345678'),
        )..createSync(recursive: true);
        expect(sessionFile.existsSync(), isTrue);
        await runtime.deleteSession('sess-12345678');
        expect(sessionFile.existsSync(), isFalse);

        runtime.warm();
        await runtime.stopAll();
        expect(() => runtime.start(root), throwsUnsupportedError);
      },
    );

    test(
      'signIn bridges loopback callback port via RemoteOAuthCallbackBridge '
      'and completes when browser hits redirect_uri',
      () async {
        // Real local backend pretending to be the remote agy OAuth callback
        // HTTP server on a separate port.
        final callbackReceived = Completer<String>();
        final backend = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => backend.close(force: true));
        backend.listen((request) async {
          if (!callbackReceived.isCompleted) {
            callbackReceived.complete(request.uri.toString());
          }
          request.response
            ..statusCode = HttpStatus.ok
            ..write('Signed in!');
          await request.response.close();
        });

        // Pick a free local port that the bridge can bind.
        final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final callbackPort = probe.port;
        await probe.close();

        // Build an in-memory RPC server that emits OAuth URL on agy/signIn and
        // remaps tcp/connect(callbackPort) -> backend.port so the bridge and
        // backend don't collide on loopback in this single-machine test.
        final signInEvents = StreamController<Object?>();
        final harness = await _CustomAgyRpcHost.start(
          onSignIn: (_) => signInEvents.stream,
          tcpConnectPortRemap: {callbackPort: backend.port},
        );
        addTearDown(harness.close);

        Uri? openedUri;
        var promptCalled = false;
        final runtime = RemoteAgyRuntime(
          harness.host,
          openUrl: (uri) async {
            openedUri = uri;
            // Simulate the local browser completing OAuth and hitting the
            // local callback URL bridged to the remote server.
            final http = HttpClient();
            try {
              final req = await http.getUrl(
                Uri.parse(
                  'http://127.0.0.1:$callbackPort/callback?code=oauth-ok',
                ),
              );
              final res = await req.close();
              final body = await utf8.decodeStream(res);
              expect(res.statusCode, HttpStatus.ok);
              expect(body, 'Signed in!');
            } finally {
              http.close(force: true);
            }
            signInEvents.add({'type': 'done'});
            await signInEvents.close();
          },
          requestCode: (_, {required bridgeActive}) async {
            promptCalled = true;
            return null;
          },
        );

        final signInFuture = runtime.signIn();
        signInEvents.add({
          'type': 'url',
          'url':
              'https://accounts.google.com/o/oauth2/auth?client_id=test&redirect_uri=http%3A%2F%2F127.0.0.1%3A$callbackPort%2Fcallback',
          'callbackPort': callbackPort,
          'needsCode': false,
        });

        await signInFuture.timeout(const Duration(seconds: 10));
        expect(openedUri?.host, 'accounts.google.com');
        expect(promptCalled, isFalse);
        expect(await callbackReceived.future, '/callback?code=oauth-ok');
      },
    );

    test(
      'signIn falls back to requestCode when local callback port is occupied '
      'and submits auth code',
      () async {
        // Occupy a local loopback port so RemoteOAuthCallbackBridge.start
        // returns null.
        final blocker = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(blocker.close);

        final signInEvents = StreamController<Object?>();
        String? submittedCode;
        final harness = await _CustomAgyRpcHost.start(
          onSignIn: (_) => signInEvents.stream,
          onAuthCode: (code) async {
            submittedCode = code;
            signInEvents.add({'type': 'done'});
            await signInEvents.close();
          },
        );
        addTearDown(harness.close);

        bool? observedBridgeActive;
        final runtime = RemoteAgyRuntime(
          harness.host,
          openUrl: (_) async {},
          requestCode: (url, {required bridgeActive}) async {
            observedBridgeActive = bridgeActive;
            return '  manual-code-123  ';
          },
        );

        final signInFuture = runtime.signIn();
        signInEvents.add({
          'type': 'url',
          'url':
              'https://accounts.google.com/o/oauth2/auth?client_id=test&redirect_uri=http%3A%2F%2F127.0.0.1%3A${blocker.port}%2Fcallback',
          'callbackPort': blocker.port,
          'needsCode': false,
        });

        await signInFuture.timeout(const Duration(seconds: 10));
        expect(observedBridgeActive, isFalse);
        expect(submittedCode, 'manual-code-123');
      },
    );

    test(
      'signIn prompts requestCode when needsCode is true (OOB) and handles '
      'cancellation via null code or cancel future',
      () async {
        // 1. OOB needsCode == true -> submits code -> done.
        final events1 = StreamController<Object?>();
        String? submitted;
        final harness1 = await _CustomAgyRpcHost.start(
          onSignIn: (_) => events1.stream,
          onAuthCode: (code) async {
            submitted = code;
            events1.add({'type': 'done'});
            await events1.close();
          },
        );
        addTearDown(harness1.close);

        var openCount = 0;
        final runtime1 = RemoteAgyRuntime(
          harness1.host,
          openUrl: (_) async => openCount++,
          requestCode: (uri, {required bridgeActive}) async {
            expect(bridgeActive, isFalse);
            return 'oob-token';
          },
        );
        final f1 = runtime1.signIn();
        // Send line + url for same OAuth URL: openUrl should only fire once.
        const oobUrl =
            'https://accounts.google.com/o/oauth2/auth?client_id=test&redirect_uri=urn%3Aietf%3Awg%3Aoauth%3A2.0%3Aoob';
        events1.add({'type': 'line', 'text': 'Visit $oobUrl'});
        events1.add({
          'type': 'url',
          'url': oobUrl,
          'callbackPort': null,
          'needsCode': true,
        });
        await f1.timeout(const Duration(seconds: 10));
        expect(openCount, 1);
        expect(submitted, 'oob-token');

        // 2. requestCode returns null -> cancels remote stream & throws.
        final cancelled2 = Completer<void>();
        late final StreamController<Object?> events2;
        events2 = StreamController<Object?>(
          onCancel: () {
            if (!cancelled2.isCompleted) cancelled2.complete();
          },
        );
        final harness2 = await _CustomAgyRpcHost.start(
          onSignIn: (_) => events2.stream,
        );
        addTearDown(harness2.close);

        final runtime2 = RemoteAgyRuntime(
          harness2.host,
          openUrl: (_) async {},
          requestCode: (_, {required bridgeActive}) async => null,
        );
        final f2 = runtime2.signIn();
        events2.add({
          'type': 'url',
          'url': oobUrl,
          'callbackPort': null,
          'needsCode': true,
        });
        await expectLater(f2, throwsA(isA<AgyUnavailable>()));
        await cancelled2.future.timeout(const Duration(seconds: 5));

        // 3. Explicit cancel future -> cancels remote stream & throws.
        final cancelled3 = Completer<void>();
        late final StreamController<Object?> events3;
        events3 = StreamController<Object?>(
          onCancel: () {
            if (!cancelled3.isCompleted) cancelled3.complete();
          },
        );
        final harness3 = await _CustomAgyRpcHost.start(
          onSignIn: (_) => events3.stream,
        );
        addTearDown(harness3.close);

        final cancelCompleter = Completer<void>();
        final runtime3 = RemoteAgyRuntime(
          harness3.host,
          openUrl: (_) async {},
        );
        final f3 = runtime3.signIn(cancel: cancelCompleter.future);
        events3.add({'type': 'line', 'text': 'Starting login...'});
        await Future<void>.delayed(const Duration(milliseconds: 50));
        cancelCompleter.complete();
        await expectLater(f3, throwsA(isA<AgyUnavailable>()));
        await cancelled3.future.timeout(const Duration(seconds: 5));
      },
    );
  });

  group('RemoteClaudeTransport.start with launch.agy', () {
    test(
      'surfaces needsInstall card instead of silently downloading, then starts '
      'with core=agy and forwarded proxy env after confirmed install',
      () async {
        // Fake `baocode-server` binary invoked for `agy --agy-root ...`.
        final fakeServerBin = File(p.join(home.path, 'fake-baocode-server'))
          ..writeAsStringSync(r'''#!/bin/sh
printf '%s\n' "$@" > "$MARKS/server_args"
printf '%s' "${HTTP_PROXY-unset}" > "$MARKS/agy_http_proxy"
printf '%s' "${HTTPS_PROXY-unset}" > "$MARKS/agy_https_proxy"
printf '%s' "${NO_PROXY-unset}" > "$MARKS/agy_no_proxy"
echo '{"type":"system","subtype":"init","session_id":"remote-agy-1"}'
read line
printf '%s\n' "$line"
''');
        Process.runSync('chmod', ['755', fakeServerBin.path]);
        ServerAgy.selfCommand = () => [fakeServerBin.path];

        // Configure a local loopback proxy to verify proxy env forwarding.
        final dummyProxy = await ServerSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        addTearDown(dummyProxy.close);
        NetworkProxy.instance = NetworkProxy(
          system: () async => ProxyRoute.manual(
            ProxyServer.parse('http://127.0.0.1:${dummyProxy.port}')!,
          ),
          environment: () async => const {},
        );

        final host = hosts['dev'];
        expect(await (await host.ready).agyVersion(), isNull);

        // Before user confirms installation: does NOT silently download 103MB,
        // and surfaces the inline install confirmation card for the host.
        await expectLater(
          startClaude(
            ClaudeLaunch(
              cwd: RemoteLocation.of('dev', root),
              agy: true,
              model: 'gemini-3-pro',
            ),
          ),
          throwsA(
            isA<ClaudeUnavailable>().having(
              (e) => e.message,
              'message',
              contains('not installed on dev'),
            ),
          ),
        );
        expect(
          RemoteAgySetups.instance.of('dev').stage,
          RemoteAgySetupStage.needsInstall,
        );
        expect(await (await host.ready).agyVersion(), isNull);

        // Once user confirms install via the card, launching succeeds with
        // core=agy and local proxy forwarding.
        await installRemoteAgy(host);
        final transport = await startClaude(
          ClaudeLaunch(
            cwd: RemoteLocation.of('dev', root),
            agy: true,
            model: 'gemini-3-pro',
          ),
        );

        final messages = <Map<String, Object?>>[];
        final done = transport.messages.forEach(messages.add);
        await until(() => messages.isNotEmpty);
        transport.write({'type': 'user', 'text': 'hello remote agy'});
        await done.timeout(const Duration(seconds: 10));

        expect(await (await host.ready).agyVersion(), '2.4.0');
        expect(messages.first['session_id'], 'remote-agy-1');
        expect(messages[1], {'type': 'user', 'text': 'hello remote agy'});
        final args = mark('server_args').split('\n');
        expect(args.first, 'agy');
        expect(args, contains('--agy-root'));
        expect(args, contains('--model'));
        expect(args, contains('gemini-3-pro'));
        expect(mark('agy_http_proxy'), startsWith('http://127.0.0.1:'));
        expect(mark('agy_https_proxy'), startsWith('http://127.0.0.1:'));
        expect(mark('agy_no_proxy'), contains('127.0.0.1'));
        expect(mark('agy_no_proxy'), contains('localhost'));
      },
    );

    test(
      'converts AgyUnavailable(signIn: true) into ClaudeUnavailable and marks '
      'inline sign-in card',
      () async {
        final harness = await _CustomAgyRpcHost.start(
          onStartClaude: (_) => throw const AgyUnavailable(
            'Sign in to Antigravity',
            signIn: true,
          ),
        );
        addTearDown(harness.close);

        await expectLater(
          RemoteClaudeTransport.start(
            harness.host,
            ClaudeLaunch(
              cwd: RemoteLocation.of('dev', root),
              agy: true,
              model: 'gemini-3-pro',
            ),
          ),
          throwsA(
            isA<ClaudeUnavailable>()
                .having((e) => e.message, 'message', contains('dev'))
                .having(
                  (e) => e.detail,
                  'detail',
                  contains('card above the input box'),
                ),
          ),
        );
        expect(
          RemoteAgySetups.instance.of('dev').stage,
          RemoteAgySetupStage.needsSignIn,
        );
      },
    );
  });

  group('ClaudeCodeKernel remote swarm replay', () {
    test(
      'restores SwarmSnapshot over SSH when replaying a remote agy session',
      () async {
        final managed = ManagedAgy(p.join(dataDir.path, 'antigravity'));
        const swarmId = 'swarm-remote-001';
        final swarmDir = Directory(
          p.join(managed.brainDir, swarmId, '.system_generated', 'swarm'),
        )..createSync(recursive: true);
        File(p.join(swarmDir.path, 'members.json')).writeAsStringSync(
          jsonEncode({
            'title': 'Remote Swarm',
            'members': {
              'worker-1': {
                'conversation_id': 'conv-worker-1',
                'role': 'worker',
                'status': 'working',
              },
            },
          }),
        );

        final session = SessionRecord(
          id: 'sess-remote-swarm',
          title: 'Remote Swarm',
          cwd: RemoteLocation.of('dev', root),
          updatedAt: DateTime.now(),
        );
        final kernel = ClaudeCodeKernel(
          MockKernels.claudeCode,
          KernelContext(
            cwd: RemoteLocation.of('dev', root),
            resume: session,
          ),
          start: (_) async => MockClaudeCodeTransport(),
          providers: ModelProviders.memory(),
          readHistory: (_) async => [
            {'type': 'antigravity-session', 'agySessionId': swarmId},
          ],
        );
        addTearDown(kernel.dispose);

        SwarmReported? reported;
        final sub = kernel.events.listen((event) {
          if (event is SwarmReported) reported = event;
        });
        addTearDown(sub.cancel);

        await until(() => reported != null);
        expect(reported!.swarm?.swarmId, swarmId);
        expect(reported!.swarm?.title, 'Remote Swarm');
        expect(
          reported!.swarm?.members.any((m) => m.name == 'worker-1'),
          isTrue,
        );
      },
    );
  });
}

/// Minimal mock `antigravity` executable script supporting `models` and
/// `acp` (`initialize` + `logout`).
const _mockAgyScript = r'''#!/bin/sh
if [ "$1" = "models" ]; then
  printf '%s' "${HTTPS_PROXY-unset}" > "$MARKS/models_https_proxy"
  printf '%s' "${NO_PROXY-unset}" > "$MARKS/models_no_proxy"
  printf 'gemini-3-pro-low\tGemini 3 Pro (Low)\n'
  printf 'gemini-3-pro-high\tGemini 3 Pro (High)\n'
  exit 0
fi
if [ "$1" = "acp" ]; then
  while IFS= read -r line; do
    case "$line" in
      *'"method":"initialize"'*)
        id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
        printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":1}}\n' "$id"
        ;;
      *'"method":"logout"'*)
        id=$(printf '%s' "$line" | sed -n 's/.*"id":\([0-9]*\).*/\1/p')
        printf 'yes' > "$MARKS/signed_out"
        printf '{"jsonrpc":"2.0","id":%s,"result":{}}\n' "$id"
        exit 0
        ;;
    esac
  done
  exit 0
fi
exit 0
''';

/// Local fake Antigravity release feed serving `<target>.json` and a real
/// `.tar.gz` archive with valid SHA-512 checksum.
class _FakeAgyFeed {
  _FakeAgyFeed._(
    this._server,
    this.target,
    this.version,
    this.archiveBytes,
    this.sha512Hex,
  );

  static Future<_FakeAgyFeed> start({
    required Directory workDir,
    required String target,
    required String version,
    required String scriptBody,
  }) async {
    final src = Directory(p.join(workDir.path, 'agy-src-$version'))
      ..createSync(recursive: true);
    final bin = File(p.join(src.path, 'antigravity'))
      ..writeAsStringSync(scriptBody);
    Process.runSync('chmod', ['755', bin.path]);
    final archive = File(p.join(workDir.path, 'agy-$version.tar.gz'));
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
    final bytes = archive.readAsBytesSync();
    final digest = sha512.convert(bytes).toString();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final feed = _FakeAgyFeed._(server, target, version, bytes, digest);
    server.listen(feed._serve);
    return feed;
  }

  final HttpServer _server;
  final String target;
  final String version;
  final List<int> archiveBytes;
  final String sha512Hex;

  int failNextRequests = 0;
  int manifestRequests = 0;
  int archiveRequests = 0;

  String get _base => 'http://127.0.0.1:${_server.port}';
  String get feedUrl => '$_base/manifests';
  String get downloadsPrefix => '$_base/downloads/';

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    if (failNextRequests > 0) {
      failNextRequests--;
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    if (path == '/manifests/$target.json') {
      manifestRequests++;
      response.headers.contentType = ContentType.json;
      response.write(
        jsonEncode({
          'version': version,
          'url': '${downloadsPrefix}antigravity_$target.tar.gz',
          'sha512': sha512Hex,
        }),
      );
    } else if (path == '/downloads/antigravity_$target.tar.gz') {
      archiveRequests++;
      response.contentLength = archiveBytes.length;
      response.add(archiveBytes);
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}

/// Lightweight in-memory [SshHost] backed by a customizable [RemoteServer] for
/// unit-testing headless OAuth sign-in, bridge forwarding, and error mapping.
class _CustomAgyRpcHost {
  _CustomAgyRpcHost._(this.server, this.host, this._dataDir);

  static Future<_CustomAgyRpcHost> start({
    Stream<Object?> Function(Map<String, Object?> params)? onSignIn,
    Future<void> Function(String code)? onAuthCode,
    Future<Object?> Function(Map<String, Object?> params)? onStartClaude,
    Map<int, int> tcpConnectPortRemap = const {},
  }) async {
    final dataDir = Directory.systemTemp.createTempSync('baocode-custom-agy-');
    final toServer = StreamController<String>();
    final toClient = StreamController<String>();
    final serverPeer = RpcPeer(toServer.stream, toClient.add);
    final server = RemoteServer(
      serverPeer,
      dataDir: dataDir.path,
      version: 'test',
    );
    final subs = <int, StreamSubscription<Object?>>{};
    var nextStreamId = 1000;
    final previousCancel = serverPeer.notificationHandlers[RemoteProtocol.streamCancel];
    serverPeer.notificationHandlers[RemoteProtocol.streamCancel] = (params) {
      final id = paramsOf(params)['stream'] as int?;
      if (id != null && subs.containsKey(id)) {
        unawaited(subs.remove(id)?.cancel());
        return;
      }
      previousCancel?.call(params);
    };

    int openTestStream(Stream<Object?> stream) {
      final id = ++nextStreamId;
      subs[id] = stream.listen(
        (item) => serverPeer.notify(RemoteProtocol.streamData, {
          'stream': id,
          'data': item,
        }),
        onError: (Object error) {
          subs.remove(id);
          serverPeer.notify(RemoteProtocol.streamError, {
            'stream': id,
            'error': RpcError.from(error).toJson(),
          });
        },
        onDone: () {
          subs.remove(id);
          serverPeer.notify(RemoteProtocol.streamDone, {'stream': id});
        },
        cancelOnError: true,
      );
      return id;
    }

    if (onSignIn != null) {
      serverPeer.handlers[RemoteProtocol.agySignIn] = (params, _) =>
          openTestStream(onSignIn(paramsOf(params)));
    }
    if (onAuthCode != null) {
      serverPeer.handlers[RemoteProtocol.agyAuthCode] = (params, _) async {
        await onAuthCode(paramsOf(params)['code'] as String? ?? '');
        return null;
      };
    }
    if (onStartClaude != null) {
      serverPeer.handlers[RemoteProtocol.claudeStart] = (params, _) =>
          onStartClaude(paramsOf(params));
    }
    if (tcpConnectPortRemap.isNotEmpty) {
      final originalConnect = serverPeer.handlers[RemoteProtocol.tcpConnect]!;
      serverPeer.handlers[RemoteProtocol.tcpConnect] = (params, cancel) {
        final args = Map<String, Object?>.of(paramsOf(params));
        final port = args['port'] as int?;
        if (port != null && tcpConnectPortRemap.containsKey(port)) {
          args['port'] = tcpConnectPortRemap[port];
        }
        return originalConnect(args, cancel);
      };
    }

    final client = RemoteClient(RpcPeer(toClient.stream, toServer.add));
    await client.initialize();
    final host = SshHost(
      'dev',
      connect: (target, {onProgress}) async =>
          SshConnection.over(target, client, ended: () => server.shutdown()),
    );
    await host.ready;
    return _CustomAgyRpcHost._(server, host, dataDir);
  }

  final RemoteServer server;
  final SshHost host;
  final Directory _dataDir;

  Future<void> close() async {
    await host.close();
    await server.shutdown();
    if (_dataDir.existsSync()) _dataDir.deleteSync(recursive: true);
  }
}
