@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/files.dart' show IdeFileExistsException;
import 'package:bao_remote/local.dart' show ClaudeEnvironment, CliLocator;
import 'package:bao_agent/testing.dart';
import 'package:bao_remote/server.dart' show ServerClaude;
import 'package:baocode/chat/panels/health_banner.dart';
import 'package:baocode/ide/git/git_model.dart' show IdeGitGroup;
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/kernel/claude_code/claude_install_progress.dart';
import 'package:baocode/kernel/mock/mock_kernels.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/models/launch_environment.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/remote/open_remote.dart';
import 'package:baocode/remote/project_host.dart';
import 'package:baocode/remote/remote_files.dart';
import 'package:baocode/remote/remote_claude.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/remote_services.dart';
import 'package:baocode/remote/remote_status.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fixtures/lsp/fake_lsp.dart'
    show FakeCatalog, dartExecutable, fakeServer;
import 'remote_harness.dart';

/// A remote project as the app has it: its location, its host's
/// connection (lost and made again), and the IDE's and Claude Code's
/// services there, over servers in memory.
void main() {
  late Directory dataDir;
  late Directory project;
  late String root;
  late MemoryConnector connector;
  late SshHosts hosts;
  final previous = SshHosts.instance;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('baocode-remote-data-');
    project = Directory.systemTemp.createTempSync('baocode-remote-project-');
    root = project.resolveSymbolicLinksSync();
    connector = MemoryConnector(dataDir.path);
    hosts = SshHosts.instance = SshHosts(connect: connector.call);
  });
  tearDown(() async {
    await hosts.closeAll();
    SshHosts.instance = previous;
    ClaudeEnvironment.use(null);
    CliLocator.use(null);
    for (final dir in [dataDir, project]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  group('locations', () {
    test('a remote project is its host and its path there', () {
      const location = 'ssh://me@10.0.0.2:2222/home/me/app/';
      expect(RemoteLocation.isRemote(location), isTrue);
      expect(RemoteLocation.hostOf(location), 'me@10.0.0.2:2222');
      expect(RemoteLocation.pathOf(location), '/home/me/app');
      expect(RemoteLocation.nameOf(location), 'app');
      expect(RemoteLocation.of('dev', '/srv//x/'), 'ssh://dev/srv/x');
      expect(RemoteLocation.of(null, '/Users/me/x'), '/Users/me/x');
      expect(RemoteLocation.hostOf('/Users/me/x'), isNull);
      expect(RemoteLocation.pathOf('/Users/me/x'), '/Users/me/x');
      expect(RemoteLocation.pathOf('ssh://dev'), '/');
    });

    test('projects are told apart by host and path', () {
      final remote = Project.at('ssh://dev/home/me/app');
      expect(remote.name, 'app');
      expect(remote.host, 'dev');
      expect(remote.root, '/home/me/app');
      expect(remote, Project.at('ssh://dev/home/me/app'));
      expect(remote == Project.at('ssh://prod/home/me/app'), isFalse);
      expect(remote == Project.at('/home/me/app'), isFalse);
      final local = Project.at('/home/me/app');
      expect(local.host, isNull);
      expect(local.root, '/home/me/app');
    });

    test('a project is on this machine, or on its SSH host', () {
      expect(ProjectHost.of('/x'), isA<LocalHost>());
      final host = ProjectHost.of('ssh://dev/x');
      expect(host, same(hosts['dev']));
      expect(host.paths, p.posix);
      expect(host.pathOf('ssh://dev/x/y'), '/x/y');
    });
  });

  group('the connection', () {
    test('made once for all of a host, and again once lost', () async {
      final host = hosts['dev'];
      final states = <SshHostState>[];
      host.addListener(() => states.add(host.state));
      final first = await host.ready;
      expect(host.state, SshHostState.connected);
      expect(await host.ready, same(first));
      expect(connector.attempts, 1);
      expect(hosts.connected, [host]);

      final reconnected = host.reconnected.first;
      await connector.links.single.drop();
      final second = await reconnected;
      expect(second, isNot(same(first)));
      expect(host.state, SshHostState.connected);
      expect(connector.attempts, 2);
      expect(
        states,
        containsAllInOrder([
          SshHostState.connecting,
          SshHostState.connected,
          SshHostState.reconnecting,
          SshHostState.connected,
        ]),
      );
    });

    test('a refused key is not tried again alone; Reconnect does', () async {
      connector.failure = const SshConnectException(
        SshFailure.authentication,
        'The host refused the key',
      );
      final host = hosts['dev'];
      await expectLater(host.ready, throwsA(isA<SshConnectException>()));
      expect(host.state, SshHostState.failed);
      expect(host.error, isA<SshConnectException>());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(connector.attempts, 1);

      // Nor by each part of a project asking for it (its sessions, files,
      // git…, all restored at start): the user is not asked to sign in
      // again and again.
      for (var i = 0; i < 3; i++) {
        await expectLater(host.ready, throwsA(isA<SshConnectException>()));
      }
      expect(connector.attempts, 1);
      expect(host.state, SshHostState.failed);

      connector.failure = null;
      await host.reconnect();
      expect(host.state, SshHostState.connected);
      expect(host.error, isNull);
    });

    test('lost and not back at once: tried again, later each time', () async {
      final host = SshHost(
        'dev',
        connect: connector.call,
        maxBackoff: const Duration(milliseconds: 1),
      );
      addTearDown(host.close);
      await host.ready;
      var scheduled = 0;
      host.addListener(() {
        if (host.retryAt != null) scheduled++;
      });
      connector.failure = const SshConnectException(
        SshFailure.unreachable,
        'The host could not be reached.',
      );
      await connector.links.single.drop();
      await until(() => connector.attempts >= 3);
      expect(host.state, SshHostState.reconnecting);
      expect(scheduled, greaterThan(0));
      connector.failure = null;
      await until(() => host.state == SshHostState.connected);
    });

    test('a project\'s sessions are listed once its host is reached', () async {
      final mock = MockKernels.claudeCode;
      final workspace = Workspace(
        projects: const [],
        kernels: [
          KernelDescriptor(
            id: mock.id,
            label: mock.label,
            icon: mock.icon,
            description: mock.description,
            create: mock.create,
            catalog: _HostCatalog(),
          ),
        ],
      );
      addTearDown(workspace.dispose);
      connector.failure = const SshConnectException(
        SshFailure.unreachable,
        'The host could not be reached.',
      );
      workspace.openFolder(RemoteLocation.of('dev', root));
      await until(() => hosts['dev'].state == SshHostState.failed);
      expect(
        workspace.threads.where((thread) => thread.record != null),
        isEmpty,
      );

      connector.failure = null;
      await hosts['dev'].reconnect();
      await until(
        () => workspace.threads.any((thread) => thread.title == 'Kept there'),
      );
    });

    testWidgets('one that fails is said over the chat, and retried there', (
      tester,
    ) async {
      final location = RemoteLocation.of('dev', root);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Column(
              children: [
                SshHostBanner(location: location),
                SshHostBanner(location: root),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(HealthBanner), findsNothing);

      connector.failure = const SshConnectException(
        SshFailure.server,
        'The BaoCode server for Linux x64 could not be downloaded',
        detail: 'https://dl.baocode.dev/x.gz: HTTP 404',
      );
      await tester.runAsync(
        () => hosts['dev'].ready.then((_) {}, onError: (_) {}),
      );
      await tester.pump();
      expect(
        find.text(
          'Could not connect to dev: '
          'The BaoCode server for Linux x64 could not be downloaded',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(
        find.text('https://dl.baocode.dev/x.gz: HTTP 404'),
        findsOneWidget,
      );

      connector.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.runAsync(
        () => until(() => hosts['dev'].state == SshHostState.connected),
      );
      await tester.pump();
      expect(find.byType(HealthBanner), findsNothing);
    });
  });

  group('the IDE', () {
    String at(String name) => p.join(root, name);

    test(
      'files read, written, listed, and watched across a reconnect',
      () async {
        final host = hosts['dev'];
        final files = host.files(root) as RemoteIdeFileService;
        File(at('a.txt')).writeAsStringSync('one');
        Directory(at('src')).createSync();
        expect(await files.read(at('a.txt')), 'one');
        await files.write(at('a.txt'), 'two', expectedText: 'one');
        expect(File(at('a.txt')).readAsStringSync(), 'two');
        expect(
          [for (final f in await files.list(root)) f.name],
          ['src', 'a.txt'],
        );
        expect(
          await files.readBytes(at('a.txt')),
          Uint8List.fromList(utf8.encode('two')),
        );
        // A pasted picture, uploaded beside the document; never over a file.
        await files.writeBytes(at('shot.png'), Uint8List.fromList([1, 2, 3]));
        expect(File(at('shot.png')).readAsBytesSync(), [1, 2, 3]);
        await expectLater(
          files.writeBytes(at('a.txt'), Uint8List.fromList([9])),
          throwsA(isA<IdeFileExistsException>()),
        );
        expect(File(at('a.txt')).readAsStringSync(), 'two');
        File(at('shot.png')).deleteSync();
        final listing = await files.listProject(root);
        expect(listing.paths, [at('a.txt')]);

        var changes = 0;
        final watching = files.watchDirectory(root).listen((_) => changes++);
        addTearDown(watching.cancel);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        File(at('b.txt')).writeAsStringSync('new');
        await until(() => changes > 0);
        // Lost: once back, told (it may have changed meanwhile), and watched
        // again.
        final before = changes;
        final reconnected = host.reconnected.first;
        await connector.links.single.drop();
        await reconnected;
        await until(() => changes > before);
        await Future<void>.delayed(const Duration(milliseconds: 200));
        final after = changes;
        File(at('c.txt')).writeAsStringSync('newer');
        await until(() => changes > after);
      },
    );

    test('a folder watched while the host could not be reached: told '
        'once it is, to be read again', () async {
      connector.failure = const SshConnectException(
        SshFailure.server,
        'The BaoCode server could not be downloaded',
      );
      final host = hosts['dev'];
      final files = host.files(root) as RemoteIdeFileService;
      await expectLater(files.list(root), throwsA(isA<SshConnectException>()));
      var changes = 0;
      final watching = files.watchDirectory(root).listen((_) => changes++);
      addTearDown(watching.cancel);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(changes, 0);

      connector.failure = null;
      await host.reconnect();
      await until(() => changes > 0);
      expect(await files.list(root), isEmpty);
    });

    test('Git runs there', () async {
      Process.runSync('git', ['init', '-q'], workingDirectory: root);
      File(at('a.txt')).writeAsStringSync('x');
      final git = remoteGitService(hosts['dev'], root);
      expect(await git.repositoryRoot(), root);
      final state = (await git.status())!;
      expect(state.root, root);
      expect([for (final r in state.resources) r.path], [at('a.txt')]);
      await git.stage(null);
      final staged = (await git.status())!;
      expect(staged.resources.single.group, IdeGitGroup.staged);
    });

    test('a terminal there: its shell, its size, its nonce', () async {
      final backend = remoteTerminalBackend(hosts['dev']);
      expect(backend.supported, isTrue);
      final launch = await backend.launch(
        root,
        columns: 100,
        rows: 30,
        shell: (executable: '/bin/sh', arguments: const []),
      );
      final nonce = launch.environment!['VSCODE_NONCE']!;
      expect(nonce, isNotEmpty);
      final pty = await backend.start(launch);
      expect(RemotePtyAdapter.open, greaterThan(0));
      final output = StringBuffer();
      pty.output.listen((data) => output.write(utf8.decode(data)));
      pty.write(
        Uint8List.fromList(
          utf8.encode('echo "[\$((6*7))] \$(pwd)"; stty size; exit 3\n'),
        ),
      );
      expect(await pty.exitCode.timeout(const Duration(seconds: 10)), 3);
      expect(output.toString(), contains('[42] $root'));
      expect(output.toString(), contains('30 100'));
      final profiles = await backend.detectProfiles();
      expect(profiles.systemShell.executable, startsWith('/'));
    });

    test('a language server runs there: its root found there, the server '
        'its process, and started again after a reconnect', () async {
      final host = hosts['dev'];
      Directory(at('pkg/lib')).createSync(recursive: true);
      File(at('pkg/marker.yaml')).writeAsStringSync('');
      final path = at('pkg/lib/a.fake');
      File(path).writeAsStringSync('hello');
      final manager = LspManager(
        root,
        FakeCatalog([fakeServer('fake')], rootMarkers: ['marker.yaml']),
        _DartProvider(),
        startProcess: remoteLspStarter(host),
        watchDirectory: remoteLspWatcher(host),
        pathExists: (path) async => await (await host.ready).stat(path) != null,
        listDirectory: (dir) async => (await host.ready).entries(dir),
        paths: p.posix,
        processId: () => host.hello?.pid,
        shutdownTimeout: const Duration(seconds: 2),
      );
      addTearDown(manager.shutdown);
      final reconnected = host.reconnected.listen(
        (_) => manager.restartServers(),
      );
      addTearDown(reconnected.cancel);

      manager.openDocument(path, 'hello');
      Future<void> running() => until(
        () =>
            manager.statusFor(path).firstOrNull?.state ==
            LanguageServerState.running,
        timeout: const Duration(seconds: 30),
      );
      await running();
      Future<Map<String, Object?>> state() async =>
          (await manager
                  .clientFor('fake', path: path)!
                  .request('fake/state', {}))!
              as Map<String, Object?>;
      final initialize = (await state())['initializeParams']! as Map;
      expect(initialize['rootUri'], Uri.directory(at('pkg')).toString());
      expect(initialize['processId'], host.hello!.pid);

      // Edited, unsaved, then the connection goes: started again with it.
      manager.changeDocument(path, 'hello again', version: 2);
      final back = host.reconnected.first;
      await connector.links.single.drop();
      await back;
      await until(
        () =>
            manager.statusFor(path).firstOrNull?.state !=
            LanguageServerState.running,
      );
      await running();
      final docs = (await state())['docs']! as Map;
      expect(docs[Uri.file(path).toString()], 'hello again');
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('Claude Code', () {
    late Directory home;
    late File fake;
    late Directory config;

    setUp(() {
      // The CLI there, asked for.
      ClaudeCore.current = () => ClaudeCore.cli;
      addTearDown(() => ClaudeCore.current = () => ClaudeCore.fallback);
      home = Directory.systemTemp.createTempSync('baocode-remote-home-');
      config = Directory(p.join(home.path, '.claude'))..createSync();
      fake = File(p.join(home.path, 'fake-claude'))
        ..writeAsStringSync(r'''#!/bin/sh
settings=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--settings" ]; then settings="$arg"; fi
  prev="$arg"
done
dir=$(dirname "$0")
printf '%s\n' "$@" > "$dir/args"
pwd > "$dir/pwd"
printf '%s' "${CLAUDE_CODE_EMIT_SESSION_STATE_EVENTS-unset}" > "$dir/events"
printf '%s' "$settings" > "$dir/settings-path"
if [ -n "$settings" ] && [ -f "$settings" ]; then cp "$settings" "$dir/settings"; fi
echo '{"type":"system"}'
read line
printf '%s\n' "$line"
''');
      Process.runSync('chmod', ['+x', fake.path]);
      final environment = {
        'PATH': '/usr/bin:/bin',
        'HOME': home.path,
        'BAOCODE_CLAUDE_PATH': fake.path,
        'BAOCODE_CLAUDE_DATA_PATH': config.path,
        'CLAUDE_CONFIG_DIR': config.path,
      };
      CliLocator.use(environment);
      ClaudeEnvironment.use(environment);
    });
    tearDown(() => home.deleteSync(recursive: true));

    test('runs there; a key in its flag settings is in a file there, gone '
        'with it, never on its command line', () async {
      final location = RemoteLocation.of('dev', root);
      final transport = await startClaude(
        ClaudeLaunch(
          cwd: location,
          model: 'opus',
          env: const {
            'ANTHROPIC_API_KEY': 'sk-secret',
            'ANTHROPIC_BASE_URL': 'https://api.example.com',
          },
        ),
      );
      expect(transport, isA<RemoteClaudeTransport>());
      final messages = <Map<String, Object?>>[];
      final done = Completer<void>();
      transport.messages.listen(messages.add, onDone: done.complete);
      await until(() => messages.isNotEmpty);
      transport.write({'type': 'user', 'text': 'hi'});
      await done.future.timeout(const Duration(seconds: 10));

      String read(String name) =>
          File(p.join(home.path, name)).readAsStringSync().trim();
      final args = read('args').split('\n');
      expect(args, containsAllInOrder(['--model', 'opus']));
      expect(args.join(' '), isNot(contains('sk-secret')));
      expect(read('pwd'), root);
      expect(read('events'), '1');
      expect(jsonDecode(read('settings')), {
        'env': {
          ...ClaudeLaunch.unsetEnvironment,
          'ANTHROPIC_API_KEY': 'sk-secret',
          'ANTHROPIC_BASE_URL': 'https://api.example.com',
        },
      });
      expect(messages[1], {'type': 'user', 'text': 'hi'});
      expect(messages.last['type'], ClaudeExit.type);
      expect(messages.last['code'], 0);
      final settingsFile = read('settings-path');
      expect(settingsFile, isNot(startsWith(home.path)));
      await until(() => !File(settingsFile).existsSync());
    });

    test('a model proxy here is reached from there through a forwarded '
        'port', () async {
      final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => proxy.close(force: true));
      proxy.listen((request) async {
        request.response.write('proxied ${request.uri.path}');
        await request.response.close();
      });
      final client = await hosts['dev'].ready;
      final env = await remoteModelEnvironment(client, {
        'ANTHROPIC_BASE_URL': 'http://127.0.0.1:${proxy.port}/p/openai',
        'ANTHROPIC_AUTH_TOKEN': 'token',
      });
      final rewritten = Uri.parse(env!['ANTHROPIC_BASE_URL']!);
      expect(rewritten.port, isNot(proxy.port));
      expect(rewritten.path, '/p/openai');
      expect(env['ANTHROPIC_AUTH_TOKEN'], 'token');
      // The same port each time for the connection.
      final again = await remoteModelEnvironment(client, {
        'ANTHROPIC_BASE_URL': 'http://localhost:${proxy.port}',
      });
      expect(Uri.parse(again!['ANTHROPIC_BASE_URL']!).port, rewritten.port);
      final http = HttpClient();
      addTearDown(http.close);
      final request = await http.getUrl(rewritten.replace(path: '/v1/x'));
      final response = await request.close();
      expect(await utf8.decodeStream(response), 'proxied /v1/x');
      // A provider elsewhere is left as it is.
      expect(
        await remoteModelEnvironment(client, {
          'ANTHROPIC_BASE_URL': 'https://api.example.com',
        }),
        {'ANTHROPIC_BASE_URL': 'https://api.example.com'},
      );
    }, skip: _httpOverridden());

    test(
      'its sessions there are the project\'s, read and deleted there',
      () async {
        final sessions = Directory(
          p.join(config.path, 'projects', root.replaceAll('/', '-')),
        )..createSync(recursive: true);
        final file = File(p.join(sessions.path, 'abc.jsonl'))
          ..writeAsStringSync(
            '${jsonEncode({
              'type': 'user',
              'uuid': 'u1',
              'sessionId': 'abc',
              'cwd': root,
              'timestamp': '2026-10-01T10:00:00Z',
              'message': {'role': 'user', 'content': 'Fix the remote bug'},
            })}\n',
          );
        const catalog = ClaudeCatalog();
        final location = RemoteLocation.of('dev', root);
        final listed = await catalog.sessionsIn(location);
        expect([for (final s in listed) s.id], ['abc']);
        expect(listed.single.cwd, location);
        final history = await readClaudeHistory(listed.single);
        expect(history, isNotEmpty);
        await catalog.delete('abc');
        expect(file.existsSync(), isFalse);
        expect(await claudeUsageOffByAt(location), isNull);
      },
    );

    test('a build named by BAOCODE_CLAUDE_PATH that is not there: says '
        'so, nothing installed instead', () async {
      final environment = {
        'PATH': '/usr/bin:/bin',
        'HOME': home.path,
        'BAOCODE_CLAUDE_PATH': p.join(home.path, 'missing'),
      };
      CliLocator.use(environment);
      ClaudeEnvironment.use(environment);
      await expectLater(
        startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
        throwsA(
          isA<ClaudeUnavailable>()
              .having((e) => e.message, 'message', contains('dev'))
              .having(
                (e) => e.detail,
                'detail',
                contains(ServerClaude.pathVariable),
              ),
        ),
      );
      expect(hosts['dev'].installingClaude, isNull);
      expect(Directory(p.join(dataDir.path, 'claude')).existsSync(), isFalse);
    });
  });

  group('Claude Code on the built-in core', () {
    late Directory home;
    late FakeApi api;
    final self = ServerClaude.selfCommand;

    setUp(() async {
      home = Directory.systemTemp.createTempSync('baocode-remote-core-');
      api = await FakeApi.start(errands: (_) => Reply.text('A title'));
      ClaudeCore.current = () => ClaudeCore.builtin;
      // On the host, as its server saved in the app says.
      hosts.savedServers = () => {
        'dev': const SshServer(hostName: 'dev', core: SshCore.builtin),
      };
      // The server, from its source, run as the core.
      ServerClaude.selfCommand = () => [
        p.join(p.dirname(Platform.resolvedExecutable), 'dart'),
        p.absolute('packages/bao_remote/bin/baocode_server.dart'),
      ];
      if (!File(ServerClaude.selfCommand().first).existsSync()) {
        ServerClaude.selfCommand = () => [
          'dart',
          p.absolute('packages/bao_remote/bin/baocode_server.dart'),
        ];
      }
    });
    tearDown(() async {
      ClaudeCore.current = () => ClaudeCore.fallback;
      ServerClaude.selfCommand = self;
      await api.close();
      home.deleteSync(recursive: true);
    });

    Map<String, String> hostEnvironment({bool key = true}) => {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'HOME': home.path,
      'BAOCODE_CLAUDE_DATA_PATH': p.join(home.path, '.claude'),
      if (key) ...{
        'ANTHROPIC_API_KEY': 'sk-host',
        'ANTHROPIC_BASE_URL': api.baseUrl,
      },
    };

    test('runs there: the server run as the core, its session kept there '
        'as the CLI keeps one', () async {
      ClaudeEnvironment.use(hostEnvironment());
      api.model.script.addAll([
        Reply.tool('Write', {
          'file_path': p.join(root, 'there.txt'),
          'content': 'from the core\n',
        }),
        Reply.text('written there'),
      ]);
      final location = RemoteLocation.of('dev', root);
      // On an upstream of this machine's Settings → Models, over the
      // host's own key.
      final transport = await startClaude(
        ClaudeLaunch(
          cwd: location,
          permissionMode: 'acceptEdits',
          model: 'claude-sonnet-4-5',
          env: launchEnvironment(
            provider: ModelProvider(
              id: 'up',
              name: 'Upstream',
              baseUrl: api.baseUrl,
              auth: ProviderAuth.apiKey,
            ),
            model: 'claude-sonnet-4-5',
            key: 'sk-upstream',
          ),
        ),
      );
      expect(transport, isA<RemoteClaudeTransport>());
      final messages = <Map<String, Object?>>[];
      transport.messages.listen(messages.add);
      transport
        ..write({
          'type': 'control_request',
          'request_id': 'init',
          'request': {'subtype': 'initialize'},
        })
        ..write({
          'type': 'user',
          'message': {'role': 'user', 'content': 'write there.txt'},
        });
      await until(
        () => messages.any((m) => m['type'] == 'result'),
        timeout: const Duration(seconds: 90),
      );
      final result = messages.firstWhere((m) => m['type'] == 'result');
      expect(result['result'], 'written there');
      expect(
        File(p.join(root, 'there.txt')).readAsStringSync(),
        'from the core\n',
      );
      expect(api.headers.map((h) => h['x-api-key']).toSet(), {'sk-upstream'});
      expect(api.model.requests.map((r) => r.body['model']).toSet(), {
        'claude-sonnet-4-5',
      });
      final init = messages.firstWhere(
        (m) => m['type'] == 'system' && m['subtype'] == 'init',
      );
      expect(init['cwd'], root);
      transport.close();
      await transport.exited.timeout(const Duration(seconds: 20));
      final sessions = await const ClaudeCatalog().sessionsIn(location);
      expect([for (final s in sessions) s.id], [init['session_id']]);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('no upstream: not started there on the host\'s own setup, nor '
        'its CLI', () async {
      final fake = File(p.join(home.path, 'fake-claude'))
        ..writeAsStringSync('#!/bin/sh\ntouch "${home.path}/cli-ran"\n');
      Process.runSync('chmod', ['+x', fake.path]);
      final environment = {
        ...hostEnvironment(),
        'BAOCODE_CLAUDE_PATH': fake.path,
      };
      CliLocator.use(environment);
      ClaudeEnvironment.use(environment);
      await expectLater(
        startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
        throwsA(
          isA<ClaudeUnavailable>().having(
            (error) => error.message,
            'message',
            ClaudeCore.noModel,
          ),
        ),
      );
      expect(File(p.join(home.path, 'cli-ran')).existsSync(), isFalse);
      expect(api.headers, isEmpty);
    });
  });

  group('Open Remote Project', () {
    test('a host, then a folder there, then opened', () async {
      Directory(p.join(root, 'app')).createSync();
      final shown = <IdeQuickPick>[];
      String? opened;
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (location) => opened = location,
        hosts: hosts,
        configHosts: () async => ['dev', 'prod'],
      );
      await flow.start();
      final hostsPick = shown.single;
      final items = hostsPick.itemsFor!('');
      expect(
        [for (final i in items.whereType<IdeQuickPickItem>()) i.label],
        ['dev', 'prod'],
      );
      final typed = hostsPick.itemsFor!('me@box:2222');
      expect(
        (typed.first as IdeQuickPickItem).label,
        englishLocalizations.remoteConnectTo('me@box:2222'),
      );
      expect(
        (hostsPick.itemsFor!('-oProxyCommand=x').first as IdeQuickPickItem)
            .onAccept,
        isNull,
      );

      hostsPick.onDidAccept!(items.whereType<IdeQuickPickItem>().first);
      // Connecting, then the home folder there.
      await until(() => shown.length >= 3);
      final browse = shown.last;
      final typedPath = browse.itemsFor!(root);
      expect(
        (typedPath.first as IdeQuickPickItem).label,
        englishLocalizations.remoteGoTo(root),
      );
      (typedPath.first as IdeQuickPickItem).onAccept!();
      await until(() => shown.length >= 4);
      final inRoot = shown.last.itemsFor!('').whereType<IdeQuickPickItem>();
      expect(inRoot.map((i) => i.label), contains('app'));
      inRoot.firstWhere((i) => i.label == 'app').onAccept!();
      await until(() => shown.length >= 5);
      final inApp = shown.last.itemsFor!('').whereType<IdeQuickPickItem>();
      inApp
          .firstWhere(
            (i) => i.label == englishLocalizations.remoteOpenThisFolder,
          )
          .onAccept!();
      expect(opened, RemoteLocation.of('dev', p.join(root, 'app')));
    });

    test('the hosts added come first, by their names and icons; then '
        "~/.ssh/config's", () async {
      final shown = <IdeQuickPick>[];
      String? connected;
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        onConnected: (host) => connected = host,
        added: ['me@box:2222', 'dev'],
        labelOf: (host) => host == 'me@box:2222' ? 'Ubuntu' : host,
        iconOf: (host) => host == 'me@box:2222' ? const Text('🐧') : null,
        hosts: hosts,
        configHosts: () async => ['dev', 'prod'],
      );
      await flow.start();
      final pick = shown.single;
      final items = pick.itemsFor!('');
      expect(
        [
          for (final item in items)
            switch (item) {
              IdeQuickPickSeparator(:final label) => '-- $label',
              IdeQuickPickItem(:final label) => label,
            },
        ],
        ['-- Added', 'Ubuntu', 'dev', '-- ~/.ssh/config', 'prod'],
      );
      final ubuntu = items.whereType<IdeQuickPickItem>().first;
      expect(ubuntu.description, 'me@box:2222');
      expect(ubuntu.icon, isA<Text>());
      // Its address is no other host to connect to.
      expect(
        pick.itemsFor!('me@box:2222').whereType<IdeQuickPickItem>().map(
          (i) => i.label,
        ),
        isNot(contains(englishLocalizations.remoteConnectTo('me@box:2222'))),
      );

      pick.onDidAccept!(items.whereType<IdeQuickPickItem>().elementAt(1));
      await until(() => connected != null);
      expect(connected, 'dev');
    });

    test("this machine's WSL distributions last, by their names; not "
        'edited', () async {
      final before = defaultWslHosts;
      defaultWslHosts = () async => ['wsl+Ubuntu-24.04', 'wsl+Debian'];
      addTearDown(() => defaultWslHosts = before);
      final shown = <IdeQuickPick>[];
      String? connected;
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        onConnected: (host) => connected = host,
        onEdit: (_) {},
        added: ['wsl+Debian'],
        hosts: hosts,
        configHosts: () async => ['dev'],
      );
      await flow.start();
      final pick = shown.single;
      final items = pick.itemsFor!('');
      expect(
        [
          for (final item in items)
            switch (item) {
              IdeQuickPickSeparator(:final label) => '-- $label',
              IdeQuickPickItem(:final label) => label,
            },
        ],
        [
          '-- Added',
          'Debian',
          '-- ~/.ssh/config',
          'dev',
          '-- WSL',
          'Ubuntu-24.04',
        ],
      );
      final ubuntu = items.whereType<IdeQuickPickItem>().last;
      expect(ubuntu.description, isNull);
      expect(ubuntu.buttons, isEmpty);
      expect((ubuntu.icon! as Icon).icon, Codicons.terminalLinux);
      pick.onDidAccept!(ubuntu);
      await until(() => connected != null);
      expect(connected, 'wsl+Ubuntu-24.04');
    });

    test('a server added, what was typed given; those added edited, '
        "not ~/.ssh/config's", () async {
      final shown = <IdeQuickPick>[];
      final adding = <String?>[];
      final editing = <String>[];
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        added: ['me@box:2222', 'dev'],
        addressOf: (host) => host == 'me@box:2222' ? 'me@10.0.0.9' : host,
        labelOf: (host) => host == 'me@box:2222' ? 'Ubuntu' : host,
        onAdd: adding.add,
        onEdit: editing.add,
        hosts: hosts,
        configHosts: () async => ['dev', 'prod'],
      );
      await flow.start();
      final pick = shown.single;
      final items = pick.itemsFor!('').whereType<IdeQuickPickItem>().toList();
      expect(items.first.label, 'Add SSH Server...');
      // Where it is now, as saved.
      final ubuntu = items.firstWhere((item) => item.label == 'Ubuntu');
      expect(ubuntu.description, 'me@10.0.0.9');
      expect(ubuntu.buttons.single.tooltip, 'Edit');
      ubuntu.buttons.single.onPressed();
      expect(editing, ['me@box:2222']);
      for (final label in ['dev', 'prod']) {
        expect(
          items.firstWhere((item) => item.label == label).buttons,
          isEmpty,
        );
      }
      pick.itemsFor!('').whereType<IdeQuickPickItem>().first.onAccept!();
      final typed = pick.itemsFor!('me@new').whereType<IdeQuickPickItem>();
      typed.firstWhere((item) => item.label == 'Add SSH Server...').onAccept!();
      expect(adding, [null, 'me@new']);
    });

    test('a changed host key: forgotten when asked, then connected again; '
        "a server refusing to sign in, edited", () async {
      connector.failure = const SshConnectException(
        SshFailure.hostKeyChanged,
        'The host key changed.',
      );
      final shown = <IdeQuickPick>[];
      final forgotten = <String>[];
      final editing = <String>[];
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        onEdit: editing.add,
        onForgetHostKey: (host) async {
          forgotten.add(host);
          connector.failure = const SshConnectException(
            SshFailure.authentication,
            'The host refused to sign in.',
          );
          return true;
        },
        hosts: hosts,
        configHosts: () async => const [],
      );
      flow.startAt('me@moved');
      await until(() => shown.length > 1);
      final failed = shown.last.items.whereType<IdeQuickPickItem>().toList();
      expect(failed.first.label, startsWith("The server's key changed"));
      expect(failed.map((item) => item.label), isNot(contains('Retry')));
      expect(failed.map((item) => item.label), isNot(contains('Edit')));
      failed
          .firstWhere((item) => item.label == 'Remove the Old Key and Connect')
          .onAccept!();
      await until(() => shown.length > 3);
      expect(forgotten, ['me@moved']);
      final refused = shown.last.items.whereType<IdeQuickPickItem>().toList();
      expect(refused.first.label, startsWith('The server refused to sign in'));
      refused.firstWhere((item) => item.label == 'Edit').onAccept!();
      expect(editing, ['me@moved']);
    });

    test('a host that cannot be reached: why, and Retry', () async {
      connector.failure = const SshConnectException(
        SshFailure.unreachable,
        'The host could not be reached.',
        detail: 'ssh: Could not resolve hostname nowhere',
      );
      final shown = <IdeQuickPick>[];
      final flow = OpenRemoteFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        hosts: hosts,
        configHosts: () async => const [],
      );
      await flow.start();
      final items = shown.single.itemsFor!('nowhere');
      (items.first as IdeQuickPickItem).onAccept!();
      await until(() => shown.length >= 3);
      final failed = shown.last.items.whereType<IdeQuickPickItem>().toList();
      expect(
        failed.first.label,
        'The server could not be reached: check the address, port and network.',
      );
      expect(failed.first.detail, contains('nowhere'));
      expect(failed.last.label, englishLocalizations.remoteRetry);
    });
  });

  group('Open Remote File', () {
    test('a host, then a file there, then opened', () async {
      Directory(p.join(root, 'lib')).createSync();
      File(p.join(root, 'lib', 'a.dart')).writeAsStringSync('a');
      File(p.join(root, 'lib', 'sub.dart')).writeAsStringSync('b');
      final shown = <IdeQuickPick>[];
      String? opened;
      final flow = OpenRemoteFileFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (location) => opened = location,
        hosts: hosts,
        configHosts: () async => ['dev', 'prod'],
      );
      await flow.start();
      final hostsPick = shown.single;
      final items = hostsPick.itemsFor!('').whereType<IdeQuickPickItem>();
      expect(items.map((i) => i.label), ['dev', 'prod']);

      items.first.onAccept!();
      // Connecting, then the home folder there; a path typed goes to root.
      Directory(p.join(root, 'app')).createSync();
      await until(() => shown.length >= 3);
      (shown.last.itemsFor!(root).first as IdeQuickPickItem).onAccept!();
      await until(() => shown.length >= 4);
      final inRoot = shown.last.itemsFor!('').whereType<IdeQuickPickItem>();
      // Folders before files; a folder is walked into, a file opens.
      expect(inRoot.first.label, '..');
      expect(inRoot.map((i) => i.label), containsAll(['lib', 'app']));
      inRoot.firstWhere((i) => i.label == 'lib').onAccept!();
      await until(() => shown.length >= 5);
      final inLib = shown.last.itemsFor!('').whereType<IdeQuickPickItem>();
      expect(inLib.map((i) => i.label), containsAll(['a.dart', 'sub.dart']));
      inLib.firstWhere((i) => i.label == 'a.dart').onAccept!();
      expect(opened, RemoteLocation.of('dev', p.join(root, 'lib', 'a.dart')));
    });

    test('a path typed: a file opened, a folder walked into', () async {
      Directory(p.join(root, 'lib')).createSync();
      File(p.join(root, 'lib', 'a.dart')).writeAsStringSync('a');
      final shown = <IdeQuickPick>[];
      String? opened;
      final flow = OpenRemoteFileFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (location) => opened = location,
        hosts: hosts,
        configHosts: () async => const [],
      );
      await flow.open('dev');
      await until(() => shown.length >= 2);
      final file = p.join(root, 'lib', 'a.dart');
      final typed = shown.last.itemsFor!(file);
      (typed.first as IdeQuickPickItem).onAccept!();
      await until(() => opened != null);
      expect(opened, RemoteLocation.of('dev', file));

      // A folder typed is browsed, not opened.
      await flow.open('dev');
      await until(() => shown.length >= 4);
      final folder = shown.last.itemsFor!(p.join(root, 'lib'));
      (folder.first as IdeQuickPickItem).onAccept!();
      await until(
        () => shown.last.itemsFor!('').whereType<IdeQuickPickItem>().any(
          (i) => i.label == 'a.dart',
        ),
      );
      expect(opened, RemoteLocation.of('dev', file));
    });

    test('a host that cannot be reached: why, and Retry', () async {
      connector.failure = const SshConnectException(
        SshFailure.unreachable,
        'The host could not be reached.',
        detail: 'ssh: Could not resolve hostname nowhere',
      );
      final shown = <IdeQuickPick>[];
      final flow = OpenRemoteFileFlow(
        show: shown.add,
        l10n: englishLocalizations,
        onOpen: (_) {},
        hosts: hosts,
        configHosts: () async => const [],
      );
      await flow.start();
      final items = shown.single.itemsFor!('nowhere');
      (items.first as IdeQuickPickItem).onAccept!();
      await until(
        () => shown.last.items.whereType<IdeQuickPickItem>().any(
          (i) => i.label == 'The server could not be reached: check the address, port and network.',
        ),
      );
      final failed = shown.last.items.whereType<IdeQuickPickItem>().toList();
      expect(
        failed.first.label,
        'The server could not be reached: check the address, port and network.',
      );
      expect(failed.first.detail, contains('nowhere'));
      expect(failed.last.label, englishLocalizations.remoteRetry);
    });
  });

  group('the status bar\'s remote entry', () {
    testWidgets('shows the state, and opens the remote menu when clicked', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      final context = tester.element(find.byType(SizedBox));
      // Idle (never asked for): the state alone, not clickable.
      final plain = SshStatusIndicator(hosts['dev']).item(context);
      expect(plain.text, 'SSH: dev (disconnected)');
      expect(plain.onTapRect, isNull);
      expect(plain.tooltip, isNot(contains('Click for')));
      // A WSL distribution: by its name.
      expect(
        SshStatusIndicator(hosts['wsl+Ubuntu']).item(context).text,
        'WSL: Ubuntu (disconnected)',
      );
      expect(
        claudeInstallText(
          englishLocalizations,
          'wsl+Ubuntu',
          const ClaudeInstallProgress(0, null),
        ),
        englishLocalizations.remoteInstallingClaude('Ubuntu'),
      );

      // Installing Claude Code there: how far once its size is known.
      await tester.runAsync(() => hosts['dev'].reconnect());
      hosts['dev'].installingClaude = const ClaudeInstallProgress(10, null);
      expect(
        SshStatusIndicator(hosts['dev']).item(context).text,
        'SSH: dev (installing Claude Code...)',
      );
      hosts['dev'].installingClaude = const ClaudeInstallProgress(50, 100);
      expect(
        SshStatusIndicator(hosts['dev']).item(context).text,
        'SSH: dev (installing Claude Code 50%)',
      );
      hosts['dev'].installingClaude = null;
      await tester.runAsync(() => hosts['dev'].close());

      // With the menu: the same state, clickable, its tooltip saying so.
      Rect? chosen;
      final host = hosts['dev'];
      final item = SshStatusIndicator(
        host,
        onChoose: (rect) => chosen = rect,
      ).item(context);
      expect(item.text, plain.text);
      expect(item.tooltip, contains('Click for the hosts'));
      expect(item.onTapRect, isNotNull);
      final rect = Rect.fromLTWH(1, 2, 3, 4);
      item.onTapRect!(rect);
      expect(chosen, rect);
    });

    testWidgets('the entry clicked hands its rect to onTapRect', (
      tester,
    ) async {
      Rect? tapped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomLeft,
              child: IdeStatusBar(
                left: [
                  IdeStatusBarItem(
                    'SSH: dev',
                    onTapRect: (rect) => tapped = rect,
                  ),
                ],
                right: const [],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('SSH: dev'));
      await tester.pump();
      expect(tapped, isNotNull);
      expect(tapped!.isEmpty, isFalse);
    });
  });
}

/// Finds `dart` for every server: the fake one.
class _DartProvider implements LspServerProvider {
  @override
  Future<LspServerLocation> locate(LspServerDefinition server) async =>
      LspServerFound(dartExecutable);

  @override
  Future<void> install(
    String package, {
    void Function(String message)? onProgress,
  }) async {}
}

/// Under flutter_test every HttpClient request gets a 400, unless the test
/// clears the override (see remote_lsp_test.dart): skipped then.
Object _httpOverridden() {
  HttpOverrides.global = null;
  return false;
}

/// The sessions on the host its folder is on: one, once it is reached.
class _HostCatalog implements SessionCatalog {
  @override
  Future<List<ProjectRecord>> projects() async => const [];

  @override
  Future<List<SessionRecord>> sessionsIn(String cwd) async {
    await SshHosts.instance[RemoteLocation.hostOf(cwd)!].ready;
    return [
      SessionRecord(
        id: 'kept',
        title: 'Kept there',
        updatedAt: DateTime(2026, 10, 7),
        cwd: cwd,
      ),
    ];
  }

  @override
  Future<void> delete(String id) async {}
}
