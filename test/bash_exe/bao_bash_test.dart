// BaoCode Bash, offered on Windows: the build latest.json names, the shell
// agents run commands in, whom the composer recommends it to, installing it,
// and Settings → General → Command Line.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/bash_exe/bao_bash.dart';
import 'package:baocode/bash_exe/bao_bash_io.dart';
import 'package:baocode/bash_exe/bao_bash_view.dart';
import 'package:baocode/tips/feature_tip.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Storage implements TipStorage {
  final Map<String, Object?> values = {};

  @override
  Object? get(String key) => values[key];

  @override
  Future<void> set(String key, Object? value) async =>
      values[key] = jsonDecode(jsonEncode(value));
}

class _Host implements BaoBashHost {
  _Host({this.latest});

  Object? latest;
  BaoBashInstall? kept;
  Completer<void>? downloading;

  @override
  String? get arch => 'x64';

  @override
  BaoBashInstall? installed() => kept;

  @override
  Future<Object?> fetchLatest() async {
    if (latest == null) throw const SocketException('offline');
    return latest;
  }

  @override
  Future<BaoBashInstall> install(
    BaoBashRelease release,
    void Function(double done) progress,
  ) async {
    progress(0.5);
    await downloading?.future;
    return kept = (
      version: release.version,
      executable:
          r'C:\data\tools\bash-exe\'
          '${release.version}\\bash.exe',
    );
  }

  @override
  Future<void> uninstall() async => kept = null;

  String? git;

  @override
  String? gitBash() => git;

  @override
  String cmd() => r'C:\Windows\system32\cmd.exe';

  @override
  String powershell() =>
      r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';
}

class _Settings extends ChangeNotifier implements ShellSettings {
  final Map<String, Object?> values = {};

  @override
  Object? operator [](String key) => values[key];

  @override
  Future<void> update(String key, Object? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
    notifyListeners();
  }
}

const _git = r'C:\Program Files\Git\bin\bash.exe';

Map<String, Object?> _latest(String version) => {
  'version': version,
  'commit': 'abc',
  'files': {
    'x64': {
      'url': 'https://dl.baocode.dev/tools/bash-exe/$version/x64.exe.gz',
      'size': 13 * 1024 * 1024,
      'sha256': 'AB' * 32,
      'unpacked': 31 * 1024 * 1024,
    },
  },
};

void main() {
  test('the build latest.json names for the architecture', () {
    final release = BaoBashRelease.parse(_latest('0.2.0'), 'x64')!;
    expect(release.version, '0.2.0');
    expect(release.sha256, 'ab' * 32);
    expect(release.unpacked, 31 * 1024 * 1024);
    expect(BaoBashRelease.parse(_latest('0.2.0'), 'arm64'), isNull);
    expect(BaoBashRelease.parse(_latest('../x'), 'x64'), isNull);
    expect(BaoBashRelease.parse('nonsense', 'x64'), isNull);
  });

  group('the shell in use', () {
    test(
      'none picked: BaoCode Bash where installed, else Git Bash, else cmd',
      () async {
        final host = _Host(latest: _latest('0.1.0'));
        final bash = BaoBash(host: host, settings: _Settings());
        expect(bash.inUse, (
          shell: WindowsShell.cmd,
          executable: r'C:\Windows\system32\cmd.exe',
        ));
        final withGit = BaoBash(host: host..git = _git, settings: _Settings());
        expect(withGit.inUse, (shell: WindowsShell.gitBash, executable: _git));
        await withGit.install();
        expect(withGit.inUse.shell, WindowsShell.baoBash);
        expect(withGit.shown, WindowsShell.baoBash);
      },
    );

    test('the one picked, where it can run', () async {
      final settings = _Settings();
      final host = _Host(latest: _latest('0.1.0'))..git = _git;
      final bash = BaoBash(host: host, settings: settings);
      await bash.choose(WindowsShell.powershell);
      expect(bash.inUse.executable, endsWith('powershell.exe'));
      expect(bash.shown, WindowsShell.powershell);
      // No file named yet: as if none were picked.
      await bash.choose(WindowsShell.custom);
      expect(
        (bash.shown, bash.inUse.shell),
        (WindowsShell.custom, WindowsShell.gitBash),
      );
      await bash.setCustomPath(r' D:\msys64\usr\bin\bash.exe ');
      expect(bash.inUse, (
        shell: WindowsShell.custom,
        executable: r'D:\msys64\usr\bin\bash.exe',
      ));
    });

    test('BaoCode Bash downloaded the first time it is picked', () async {
      final host = _Host(latest: _latest('0.1.0'))
        ..git = _git
        ..downloading = Completer<void>();
      final bash = BaoBash(host: host, settings: _Settings());
      final picking = bash.choose(WindowsShell.baoBash);
      await Future<void>.delayed(Duration.zero);
      // Git Bash meanwhile.
      expect(
        (bash.shown, bash.inUse.shell, bash.busy),
        (WindowsShell.baoBash, WindowsShell.gitBash, true),
      );
      host.downloading!.complete();
      await picking;
      expect(bash.inUse.shell, WindowsShell.baoBash);
    });
  });

  group('recommended over the composer', () {
    test('to whoever runs commands in neither it nor Git Bash', () async {
      final storage = _Storage();
      final host = _Host(latest: _latest('0.1.0'));
      final bash = BaoBash(host: host, storage: storage, settings: _Settings());
      expect(bash.showsHint, isTrue);
      expect(
        BaoBash(host: _Host()..git = _git, settings: _Settings()).showsHint,
        isFalse,
      );
      // A Git Bash user who picked PowerShell.
      final settings = _Settings();
      final picked = BaoBash(host: _Host()..git = _git, settings: settings);
      await picked.choose(WindowsShell.powershell);
      expect(picked.showsHint, isTrue);

      await bash.install();
      expect(bash.showsHint, isFalse);
    });

    test('until put off for good', () {
      final storage = _Storage();
      final bash = BaoBash(host: _Host(), storage: storage);
      bash.dismissHint();
      expect(bash.showsHint, isFalse);
      expect(BaoBash(host: _Host(), storage: storage).showsHint, isFalse);
    });
  });

  test('installed, updated and taken out', () async {
    final host = _Host(latest: _latest('0.1.0'));
    final bash = BaoBash(host: host);
    expect(bash.installed, isNull);

    final progress = <double?>[];
    bash.addListener(() => progress.add(bash.progress));
    await bash.install();
    expect(bash.installed?.version, '0.1.0');
    expect(progress, containsAllInOrder([0, 0.5, null]));
    expect(bash.updateAvailable, isFalse);

    host.latest = _latest('0.2.0');
    await bash.check();
    // Not again within the hour.
    expect(bash.updateAvailable, isFalse);
    await bash.check(force: true);
    expect(bash.updateAvailable, isTrue);
    await bash.install();
    expect(bash.installed?.version, '0.2.0');

    await bash.uninstall();
    expect(bash.installed, isNull);
  });

  test('offline: said so, nothing installed', () async {
    final bash = BaoBash(host: _Host());
    await bash.install();
    expect(bash.installed, isNull);
    expect(bash.error, contains('dl.baocode.dev'));
    expect(bash.busy, isFalse);
  });

  group('for the cores', () {
    tearDown(() => BaoBash.current = null);

    test("Claude Code's CLI: the shell in use where it is a bash", () async {
      final settings = _Settings();
      final host = _Host(latest: _latest('0.2.1'))..git = _git;
      final bash = BaoBash.current = BaoBash(host: host, settings: settings);
      // None picked: Git Bash, unless the user named one.
      expect(BaoBash.cliEnvironment({'PATH': r'C:\x'}), {
        'CLAUDE_CODE_GIT_BASH_PATH': _git,
      });
      // Windows' names are any case; an empty one names none.
      expect(
        BaoBash.cliEnvironment({'claude_code_git_bash_path': r'D:\b.exe'}),
        isEmpty,
      );
      expect(BaoBash.cliEnvironment({'CLAUDE_CODE_GIT_BASH_PATH': ''}), {
        'CLAUDE_CODE_GIT_BASH_PATH': _git,
      });
      await bash.choose(WindowsShell.baoBash);
      final installed = bash.installed!.executable;
      // Picked: before the one named.
      final cli = BaoBash.cliEnvironment({
        'CLAUDE_CODE_GIT_BASH_PATH': r'D:\b.exe',
      });
      expect(cli, {'CLAUDE_CODE_GIT_BASH_PATH': installed});
      expect(BaoBash.givesBaoBash(cli), isTrue);
      await bash.choose(WindowsShell.gitBash);
      expect(BaoBash.givesBaoBash(BaoBash.cliEnvironment(const {})), isFalse);
      // cmd, PowerShell: it finds Git Bash itself.
      await bash.choose(WindowsShell.cmd);
      expect(BaoBash.cliEnvironment(const {}), isEmpty);
      await bash.choose(WindowsShell.custom);
      await bash.setCustomPath(r'D:\msys64\usr\bin\bash.exe');
      expect(BaoBash.cliEnvironment(const {}), {
        'CLAUDE_CODE_GIT_BASH_PATH': r'D:\msys64\usr\bin\bash.exe',
      });
      await bash.setCustomPath(r'D:\nu\nu.exe');
      expect(BaoBash.cliEnvironment(const {}), isEmpty);
    });

    test('the built-in core: the shell in use, BaoCode Bash told', () async {
      final host = _Host(latest: _latest('0.2.1'));
      final bash = BaoBash.current = BaoBash(host: host, settings: _Settings());
      expect(BaoBash.coreEnvironment(), {
        'BAOCODE_SHELL': r'C:\Windows\system32\cmd.exe',
      });
      await bash.install();
      final installed = bash.installed!.executable;
      expect(BaoBash.coreEnvironment(), {
        'BAOCODE_BASH': installed,
        'BAOCODE_SHELL': installed,
      });
      await bash.choose(WindowsShell.powershell);
      expect(
        BaoBash.coreEnvironment()['BAOCODE_SHELL'],
        endsWith('powershell.exe'),
      );
    });

    test('nothing where it is not offered', () {
      expect(BaoBash.cliEnvironment(const {}), isEmpty);
      expect(BaoBash.coreEnvironment(), isEmpty);
    });
  });

  group('on disk', () {
    late Directory root;
    late HttpServer server;
    late List<int> exe;
    late List<int> served;

    setUp(() async {
      // flutter_test's clients answer 400 to all: a real one, to the
      // server here.
      HttpOverrides.global = null;
      root = await Directory.systemTemp.createTemp('baocode-bash-exe');
      exe = utf8.encode('MZ a bash.exe' * 1000);
      served = gzip.encode(exe);
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        request.response
          ..contentLength = served.length
          ..add(served);
        unawaited(request.response.close());
      });
    });

    tearDown(() async {
      await server.close(force: true);
      await root.delete(recursive: true);
    });

    BaoBashRelease release(String version, {String? sha256}) => BaoBashRelease(
      version: version,
      url: Uri.parse('http://127.0.0.1:${server.port}/bash.exe.gz'),
      size: served.length,
      sha256: sha256 ?? '${crypto.sha256.convert(served)}',
      unpacked: exe.length,
    );

    test('each version in its folder, the one before removed', () async {
      final host = IoBaoBashHost(root.path, client: HttpClient.new);
      expect(host.installed(), isNull);

      final first = await host.install(release('0.1.0'), (_) {});
      expect(first.executable, p.join(root.path, '0.1.0', 'bash.exe'));
      expect(await File(first.executable).readAsBytes(), exe);
      expect(host.installed(), first);

      final next = await host.install(release('0.2.0'), (_) {});
      expect(host.installed(), next);
      expect(Directory(p.join(root.path, '0.1.0')).existsSync(), isFalse);

      await host.uninstall();
      expect(host.installed(), isNull);
      expect(File(next.executable).existsSync(), isFalse);
    });

    test('not one other than named', () async {
      final host = IoBaoBashHost(root.path, client: HttpClient.new);
      await expectLater(
        host.install(release('0.1.0', sha256: '00' * 32), (_) {}),
        throwsStateError,
      );
      expect(host.installed(), isNull);
    });

    test('the build for the machine', () {
      String? arch(Map<String, String> environment) =>
          IoBaoBashHost(root.path, environment: environment).arch;
      expect(arch({'PROCESSOR_ARCHITECTURE': 'AMD64'}), 'x64');
      expect(arch({'PROCESSOR_ARCHITECTURE': 'ARM64'}), 'arm64');
      // An x64 app on an Arm machine.
      expect(
        arch({
          'PROCESSOR_ARCHITECTURE': 'AMD64',
          'PROCESSOR_ARCHITEW6432': 'ARM64',
        }),
        'arm64',
      );
      expect(arch({'PROCESSOR_ARCHITECTURE': 'x86'}), isNull);
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: Column(children: [child])),
        ),
      );
      await tester.pump();
    }

    const title = 'On Windows, BaoCode Bash is recommended';

    testWidgets('the hint installs it and picks it, or is put off', (
      tester,
    ) async {
      final host = _Host(latest: _latest('0.1.0'))
        ..downloading = Completer<void>();
      final settings = _Settings();
      final bash = BaoBash(host: host, storage: _Storage(), settings: settings);
      await pump(tester, BaoBashHint(bash: bash));
      expect(find.text(title), findsOne);

      await tester.tap(find.text('Install and Use'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Downloading… 50%'), findsOne);
      expect(settings[WindowsShell.settingKey], 'baoBash');
      host.downloading!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text(title), findsNothing);

      final later = BaoBash(host: _Host(), storage: _Storage());
      await pump(tester, BaoBashHint(bash: later));
      await tester.tap(find.text('Not Now'));
      await tester.pump();
      expect(find.text(title), findsNothing);
      expect(later.hintDismissed, isTrue);
    });

    testWidgets('Command Line: the shells to pick, BaoCode Bash under it', (
      tester,
    ) async {
      final host = _Host(latest: _latest('0.1.0'));
      final opened = <Uri>[];
      final bash = BaoBash(host: host, settings: _Settings());
      await pump(
        tester,
        SizedBox(
          width: 900,
          child: CommandLineSettings(bash: bash, open: opened.add),
        ),
      );
      await tester.pump();
      // cmd in use: no Git Bash here.
      expect(find.text(r'In use: C:\Windows\system32\cmd.exe'), findsOne);
      await tester.tap(find.text('cmd'));
      await tester.pumpAndSettle();
      expect(find.text('Git Bash'), findsNothing);
      expect(find.text('PowerShell'), findsOne);
      await tester.tap(find.text('BaoCode Bash (recommended)'));
      await tester.pumpAndSettle();
      expect(find.text('Version 0.1.0 installed.'), findsOne);
      expect(find.text('Uninstall'), findsOne);
      expect(find.text('Update'), findsNothing);

      host.latest = _latest('0.2.0');
      await bash.check(force: true);
      await tester.pump();
      expect(
        find.text('Version 0.1.0 installed. Version 0.2.0 is out.'),
        findsOne,
      );
      expect(find.text('Update'), findsOne);

      await tester.tap(find.textContaining('github.com/baocode-dev/bash-exe'));
      expect(
        opened.single.toString(),
        'https://github.com/baocode-dev/bash-exe',
      );
    });
  });
}
