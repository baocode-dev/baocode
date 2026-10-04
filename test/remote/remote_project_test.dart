@TestOn('mac-os || linux')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/local.dart' show ClaudeEnvironment, CliLocator;
import 'package:baocode/ide/git/git_model.dart' show IdeGitGroup;
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/lsp/lsp_manager.dart';
import 'package:baocode/ide/lsp/language_features.dart';
import 'package:baocode/ide/lsp/lsp_server_definition.dart';
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/open_remote.dart';
import 'package:baocode/remote/project_host.dart';
import 'package:baocode/remote/remote_claude.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/remote_services.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/workspace/workspace.dart' show Project;
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

    test('not installed there: says so, and how to install it', () async {
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
                contains(remoteClaudeInstallCommand),
              ),
        ),
      );
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
      expect(failed.first.label, 'The host could not be reached.');
      expect(failed.first.detail, contains('nowhere'));
      expect(failed.last.label, englishLocalizations.remoteRetry);
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
