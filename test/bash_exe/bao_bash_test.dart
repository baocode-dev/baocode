// BaoCode Bash, offered on Windows: the build latest.json names, whom the
// settings dialog recommends it to, installing it, and its Settings → General
// row and notice.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/bash_exe/bao_bash.dart';
import 'package:baocode/bash_exe/bao_bash_io.dart';
import 'package:baocode/bash_exe/bao_bash_view.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/tips/feature_tip.dart';
import 'package:baocode/tips/feature_tips_controller.dart';
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
}

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

  group('recommended to', () {
    var now = DateTime.utc(2026, 11, 13);
    BaoBash make(_Storage storage) =>
        BaoBash(host: _Host(), storage: storage, now: () => now);

    setUp(() => now = DateTime.utc(2026, 11, 13));

    test('one who ran the app before, once they have sent five messages', () {
      final storage = _Storage()
        ..values[FeatureTipsController.storageKey] = {'lastVersion': '1.0.0'};
      final bash = make(storage)..noteStart();
      expect(bash.newUser, isTrue);
      for (var i = 0; i < 4; i++) {
        bash.countSent();
      }
      expect(bash.newUser, isTrue);
      bash.countSent();
      expect(bash.newUser, isFalse);
      expect(bash.showsNotice, isTrue);
      // Kept: the next run knows.
      expect(make(storage).showsNotice, isTrue);

      bash.dismissNotice();
      expect(bash.showsNotice, isFalse);
      expect(make(storage).showsNotice, isFalse);
    });

    test('a new install, a week on', () {
      final storage = _Storage();
      final bash = make(storage)..noteStart();
      for (var i = 0; i < 10; i++) {
        bash.countSent();
      }
      expect(bash.newUser, isTrue);
      now = now.add(const Duration(days: 6));
      expect(bash.newUser, isTrue);
      now = now.add(const Duration(days: 2));
      expect(bash.newUser, isFalse);
      // The first run is kept as it was, the tips having run since.
      storage.values[FeatureTipsController.storageKey] = {'lastVersion': '2'};
      make(storage).noteStart();
      expect(make(storage).newUser, isFalse);
    });

    test('nobody, once it is installed', () async {
      final storage = _Storage()
        ..values[BaoBash.storageKey] = {
          'firstSeen': '2000-01-01T00:00:00.000Z',
          'sent': 5,
        };
      final host = _Host(latest: _latest('0.1.0'));
      final bash = BaoBash(host: host, storage: storage);
      expect(bash.showsNotice, isTrue);
      await bash.install();
      expect(bash.showsNotice, isFalse);
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

  group('in the settings', () {
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

    BaoBash oldUser(_Host host) => BaoBash(
      host: host,
      storage: _Storage()
        ..values[BaoBash.storageKey] = {
          'firstSeen': '2000-01-01T00:00:00.000Z',
          'sent': 5,
        },
    );

    testWidgets('the notice installs it, or is put off for good', (
      tester,
    ) async {
      final host = _Host(latest: _latest('0.1.0'))
        ..downloading = Completer<void>();
      final bash = oldUser(host);
      await pump(
        tester,
        BaoBashNotice(bash: bash, core: () => ClaudeCore.builtin),
      );
      expect(find.text('On Windows, BaoCode Bash is recommended'), findsOne);

      await tester.tap(find.text('Install'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Downloading… 50%'), findsOne);
      host.downloading!.complete();
      await tester.pump();
      await tester.pump();
      expect(
        find.text('On Windows, BaoCode Bash is recommended'),
        findsNothing,
      );

      final later = oldUser(_Host());
      await pump(
        tester,
        BaoBashNotice(bash: later, core: () => ClaudeCore.builtin),
      );
      await tester.tap(find.text('Not Now'));
      await tester.pump();
      expect(
        find.text('On Windows, BaoCode Bash is recommended'),
        findsNothing,
      );
      expect(later.noticeDismissed, isTrue);
    });

    testWidgets('no notice where the CLI runs the agents, nor to a new user', (
      tester,
    ) async {
      await pump(
        tester,
        BaoBashNotice(bash: oldUser(_Host()), core: () => ClaudeCore.cli),
      );
      expect(
        find.text('On Windows, BaoCode Bash is recommended'),
        findsNothing,
      );
      await pump(
        tester,
        BaoBashNotice(
          bash: BaoBash(host: _Host(), storage: _Storage()),
          core: () => ClaudeCore.builtin,
        ),
      );
      expect(
        find.text('On Windows, BaoCode Bash is recommended'),
        findsNothing,
      );
    });

    testWidgets('the row: its size to install, its version once installed', (
      tester,
    ) async {
      final host = _Host(latest: _latest('0.1.0'));
      final bash = BaoBash(host: host);
      await pump(tester, BaoBashSetting(bash: bash));
      await tester.pump();
      expect(find.text('BaoCode Bash (recommended)'), findsOne);
      expect(find.text('Install (13 MB)'), findsOne);

      await tester.tap(find.text('Install (13 MB)'));
      await tester.pump();
      await tester.pump();
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
    });
  });
}
