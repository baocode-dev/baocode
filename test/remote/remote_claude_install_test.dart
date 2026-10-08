@TestOn('mac-os || linux')
library;

import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:bao_remote/local.dart'
    show ClaudeEnvironment, CliLocator, ManagedClaude;
import 'package:baocode/kernel/claude_code/claude_code_transport.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/remote/remote_binaries.dart';
import 'package:baocode/remote/remote_claude.dart';
import 'package:baocode/remote/remote_claude_install.dart';
import 'package:baocode/remote/remote_location.dart';
import 'package:baocode/remote/remote_status.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'remote_harness.dart';

/// Claude Code put on a remote host that has none, as VS Code's extension
/// comes with its own: downloaded there from a release server (a fake
/// one here), or downloaded here and sent; checked against the manifest;
/// run from the server's folder, the user's own untouched.
void main() {
  late Directory dataDir;
  late Directory home;
  late Directory marks;
  late String root;
  late MemoryConnector connector;
  late SshHosts hosts;
  late _FakeReleases releases;
  final previous = SshHosts.instance;

  setUp(() async {
    // flutter_test answers every HttpClient request with a 400.
    HttpOverrides.global = null;
    dataDir = Directory.systemTemp.createTempSync('baocode-install-data-');
    home = Directory.systemTemp.createTempSync('baocode-install-home-');
    marks = Directory(p.join(home.path, 'marks'))..createSync();
    final project = Directory(p.join(home.path, 'project'))..createSync();
    root = project.resolveSymbolicLinksSync();
    connector = MemoryConnector(dataDir.path);
    hosts = SshHosts.instance = SshHosts(connect: connector.call);
    final environment = {
      'PATH': '/usr/bin:/bin',
      'HOME': home.path,
      'MARKS': marks.path,
    };
    // Nowhere to find one: not the machine's own either.
    CliLocator.candidatesOverride = (_) => [p.join(home.path, 'no-claude')];
    CliLocator.use(environment);
    ClaudeEnvironment.use(environment);
    final client = await hosts['dev'].ready;
    releases = await _FakeReleases.start(
      ClaudeRelease.platformOf(client.hello!.platform),
    );
    ClaudeRelease.baseOverride = releases.base;
  });
  tearDown(() async {
    await hosts.closeAll();
    SshHosts.instance = previous;
    ClaudeRelease.baseOverride = null;
    CliLocator.candidatesOverride = null;
    CliLocator.use(null);
    await releases.close();
    for (final dir in [dataDir, home]) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  Future<List<Map<String, Object?>>> converse(ClaudeCodeTransport transport) {
    final messages = <Map<String, Object?>>[];
    final done = transport.messages.forEach(messages.add);
    return () async {
      await until(() => messages.isNotEmpty);
      transport.write({'type': 'user', 'text': 'hi'});
      await done.timeout(const Duration(seconds: 10));
      return messages;
    }();
  }

  String mark(String name) =>
      File(p.join(marks.path, name)).readAsStringSync().trim();

  test('none there: the host downloads it, checked, and it runs from the '
      'server\'s folder, its updater off', () async {
    final host = hosts['dev'];
    final seen = <ClaudeInstallProgress>[];
    host.addListener(() {
      if (host.installingClaude case final progress?) seen.add(progress);
    });
    final transport = await startClaude(
      ClaudeLaunch(cwd: RemoteLocation.of('dev', root)),
    );
    final messages = await converse(transport);
    expect(messages[1], {'type': 'user', 'text': 'hi'});
    expect(mark('pwd'), root);
    expect(mark('autoupdater'), '1');
    final installed = p.join(dataDir.path, 'claude', 'claude-9.9.9');
    expect(mark('self'), installed);
    expect(
      File(p.join(dataDir.path, 'claude', 'CURRENT')).readAsStringSync(),
      '9.9.9\n',
    );
    expect(releases.served, contains('/9.9.9/${releases.platform}/claude'));
    expect(seen, isNotEmpty);
    expect(seen.last.received, releases.binary.length);
    expect(seen.any((progress) => progress.uploading), isFalse);
    expect(host.installingClaude, isNull);

    // Started again: run, not installed again.
    releases.served.clear();
    await converse(
      await startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
    );
    expect(releases.served, isNot(contains(startsWith('/9.9.9/'))));
  });

  test('a host that cannot reach the downloads is sent the build this '
      'machine downloaded', () async {
    // The host asks first: refused it, not this machine after.
    releases.refuseFirst = 1;
    final host = hosts['dev'];
    final seen = <ClaudeInstallProgress>[];
    host.addListener(() {
      if (host.installingClaude case final progress?) seen.add(progress);
    });
    final downloads = Directory(p.join(home.path, 'downloads'));
    await installRemoteClaude(host, downloads: downloads);
    expect(seen.where((progress) => progress.uploading), isNotEmpty);
    expect(seen.last.received, releases.binary.length);
    final installed = File(p.join(dataDir.path, 'claude', 'claude-9.9.9'));
    expect(installed.readAsBytesSync(), releases.binary);
    expect(
      File(p.join(downloads.path, 'claude-9.9.9-${releases.platform}'))
          .existsSync(),
      isTrue,
    );
    final transport = await startClaude(
      ClaudeLaunch(cwd: RemoteLocation.of('dev', root)),
    );
    await converse(transport);
    expect(mark('self'), installed.path);
  });

  test('asked twice at once: installed once', () async {
    final host = hosts['dev'];
    await Future.wait([installRemoteClaude(host), installRemoteClaude(host)]);
    expect(
      releases.served.where((path) => path.endsWith('/claude')),
      hasLength(1),
    );
  });

  test('a build not the manifest\'s is not installed; the user is told how '
      'to install it themselves', () async {
    releases.corrupt = true;
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
    expect(Directory(p.join(dataDir.path, 'claude')).existsSync(), isTrue);
    expect(
      File(p.join(dataDir.path, 'claude', 'CURRENT')).existsSync(),
      isFalse,
    );
    expect(hosts['dev'].installingClaude, isNull);
  });

  /// What [command] prints in a terminal on the host, in [shell].
  Future<String> inTerminal(
    String command, {
    String shell = '/bin/sh',
    bool shellIntegration = false,
  }) async {
    final client = await hosts['dev'].ready;
    final pty = await client.startPty(
      cwd: root,
      shell: [shell],
      shellIntegration: shellIntegration,
    );
    final output = StringBuffer();
    pty.output.listen((data) => output.write(utf8.decode(data)));
    pty.write(utf8.encode('$command; exit\n'));
    await pty.exitCode.timeout(const Duration(seconds: 10));
    return '$output';
  }

  test('once it is there, the terminals there run it as `claude`, its '
      'updater off', () async {
    await converse(
      await startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
    );
    final command = p.join(dataDir.path, 'claude', 'bin', 'claude');
    final installed = p.join(dataDir.path, 'claude', 'claude-9.9.9');
    for (final (shell, integration) in [
      ('/bin/sh', false),
      ('/bin/bash', true),
    ]) {
      File(p.join(marks.path, 'self')).deleteSync();
      final output = await inTerminal(
        'command -v claude; echo hi | claude',
        shell: shell,
        shellIntegration: integration,
      );
      expect(output, contains(command), reason: shell);
      expect(mark('self'), installed, reason: shell);
      expect(mark('autoupdater'), '1', reason: shell);
    }
  });

  test('the user\'s own: the terminals there are left as they are', () async {
    await converse(
      await startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
    );
    final own = File(p.join(home.path, 'own-claude'))
      ..writeAsStringSync(_fakeClaude);
    Process.runSync('chmod', ['+x', own.path]);
    CliLocator.candidatesOverride = (_) => [own.path];
    CliLocator.use({
      'PATH': '/usr/bin:/bin',
      'HOME': home.path,
      'MARKS': marks.path,
    });
    final output = await inTerminal('echo "path=\$PATH"');
    expect(output, contains('path=/usr/bin:/bin'));
    expect(output, isNot(contains(p.join('claude', 'bin'))));
  });

  test('a build installed before there was a `claude` is given one', () {
    final directory = p.join(dataDir.path, 'claude');
    final managed = ManagedClaude(directory);
    expect(managed.command(), isNull);
    File(p.join(directory, 'claude-1.0.0'))
      ..createSync(recursive: true)
      ..writeAsStringSync('#!/bin/sh\necho "one \$1"\n');
    Process.runSync('chmod', ['+x', p.join(directory, 'claude-1.0.0')]);
    File(p.join(directory, 'CURRENT')).writeAsStringSync('1.0.0\n');
    expect(managed.command(), managed.binDirectory);
    final run = Process.runSync(p.join(managed.binDirectory, 'claude'), [
      'arg',
    ]);
    expect(run.stdout, 'one arg\n');
  });

  test('the user\'s own is run where there is one', () async {
    final own = File(p.join(home.path, 'own-claude'))
      ..writeAsStringSync(_fakeClaude);
    Process.runSync('chmod', ['+x', own.path]);
    CliLocator.candidatesOverride = (_) => [own.path];
    CliLocator.use({
      'PATH': '/usr/bin:/bin',
      'HOME': home.path,
      'MARKS': marks.path,
    });
    await converse(
      await startClaude(ClaudeLaunch(cwd: RemoteLocation.of('dev', root))),
    );
    expect(mark('self'), own.path);
    expect(mark('autoupdater'), 'unset');
    expect(releases.served, isEmpty);
  });

  testWidgets('its progress over the chat and in the status bar', (
    tester,
  ) async {
    final host = hosts['dev'];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ClaudeInstallBanner(location: RemoteLocation.of('dev', root)),
              ClaudeInstallBanner(location: root),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(LinearProgressIndicator), findsNothing);
    host.installingClaude = const ClaudeInstallProgress(50, 200);
    await tester.pump();
    expect(find.text('Installing Claude Code on dev… 25%'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    host.installingClaude = const ClaudeInstallProgress(
      150,
      200,
      uploading: true,
    );
    await tester.pump();
    expect(find.text('Sending Claude Code to dev… 75%'), findsOneWidget);

    final context = tester.element(find.byType(Column).first);
    final item = SshStatusIndicator(host).item(context);
    expect(item.text, 'SSH: dev (installing Claude Code 75%)');

    host.installingClaude = null;
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  group('the server of a development run', () {
    late Directory checkout;
    late File dart;

    setUp(() {
      checkout = Directory(p.join(home.path, 'checkout'));
      File(p.join(checkout.path, 'packages/bao_remote/bin/baocode_server.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void main() {}');
      File(p.join(checkout.path, 'packages/bao_remote/pubspec.yaml'))
          .writeAsStringSync('name: bao_remote');
      // Stands for `dart compile exe`: writes its -o, and what it was given.
      dart = File(p.join(home.path, 'sdk', 'bin', 'dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(r'''#!/bin/sh
out=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-o" ]; then out="$arg"; fi
  prev="$arg"
done
printf '%s ' "$@" > "$out"
echo built >> "$MARKS/builds"
''');
      Process.runSync('chmod', ['+x', dart.path]);
    });

    Future<SourceServerBinaries?> find() => SourceServerBinaries.find(
      current: p.join(checkout.path, 'packages'),
      executable: '/Applications/Nowhere.app/Contents/MacOS/BaoCode',
      environment: {
        'FLUTTER_ROOT': p.join(home.path, 'sdk'),
        'MARKS': marks.path,
      },
    );

    test('built from the checkout\'s sources once per platform, named '
        'by them', () async {
      final binaries = (await find())!;
      expect(binaries.root, checkout.path);
      expect(binaries.version, startsWith('dev-'));
      final built = utf8.decode((await binaries.read('linux-arm64'))!);
      expect(built, contains('--target-os linux --target-arch arm64'));
      expect(built, contains('-Dbaocode.version=${binaries.version}'));
      await binaries.read('linux-arm64');
      expect((await find())!.version, binaries.version);
      final again = await (await find())!.read('linux-arm64');
      expect(utf8.decode(again!), built);
      expect(mark('builds').split('\n'), hasLength(1));

      File(p.join(checkout.path, 'packages/bao_remote/bin/baocode_server.dart'))
          .writeAsStringSync('void main() { print(1); }');
      expect((await find())!.version, isNot(binaries.version));
    });

    test('for macOS, only on a Mac of that architecture', () async {
      final binaries = (await find())!;
      final host = switch (Abi.current()) {
        Abi.macosArm64 => 'arm64',
        Abi.macosX64 => 'x64',
        _ => null,
      };
      for (final arch in ['x64', 'arm64']) {
        final read = binaries.read('darwin-$arch');
        if (arch == host) {
          expect(
            utf8.decode((await read)!),
            contains('--target-os macos --target-arch $arch'),
          );
        } else {
          await expectLater(
            read,
            throwsA(
              isA<SshConnectException>().having(
                (e) => e.message,
                'message',
                contains('macOS $arch'),
              ),
            ),
          );
        }
      }
    });

    test('none outside a checkout', () async {
      expect(
        await SourceServerBinaries.find(
          current: home.path,
          executable: '/Applications/Nowhere.app/Contents/MacOS/BaoCode',
          environment: {'FLUTTER_ROOT': p.join(home.path, 'sdk')},
        ),
        isNull,
      );
    });
  });
}

/// Claude Code as the release server gives it: says where it ran from and
/// whether its updater is off, then echoes a line.
const _fakeClaude = r'''#!/bin/sh
printf '%s' "$0" > "$MARKS/self"
pwd > "$MARKS/pwd"
printf '%s' "${DISABLE_AUTOUPDATER-unset}" > "$MARKS/autoupdater"
echo '{"type":"system"}'
read line
printf '%s\n' "$line"
''';

/// downloads.claude.ai as the installer reads it: `/stable`, a version's
/// `manifest.json`, and its build for [platform].
class _FakeReleases {
  _FakeReleases._(this._server, this.platform);

  static Future<_FakeReleases> start(String platform) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final releases = _FakeReleases._(server, platform);
    server.listen(releases._serve);
    return releases;
  }

  final HttpServer _server;
  final String platform;
  final List<String> served = [];
  final List<int> binary = utf8.encode(_fakeClaude);

  /// Requests to refuse first (a 503), as for a host without the internet.
  int refuseFirst = 0;

  /// The manifest's checksum is not the build's.
  bool corrupt = false;

  String get base => 'http://127.0.0.1:${_server.port}';

  Future<void> _serve(HttpRequest request) async {
    final path = request.uri.path;
    final response = request.response;
    if (refuseFirst > 0) {
      refuseFirst--;
      response.statusCode = HttpStatus.serviceUnavailable;
      await response.close();
      return;
    }
    served.add(path);
    if (path == '/stable') {
      response.write('9.9.9\n');
    } else if (path == '/9.9.9/manifest.json') {
      final checksum = corrupt ? '0' * 64 : sha256.convert(binary).toString();
      response.write(
        jsonEncode({
          'version': '9.9.9',
          'platforms': {
            platform: {'checksum': checksum, 'size': binary.length},
          },
        }),
      );
    } else if (path == '/9.9.9/$platform/claude') {
      response.add(binary);
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  Future<void> close() => _server.close(force: true);
}
