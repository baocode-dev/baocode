import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/update/installer_io.dart';
import 'package:baocode/update/update_manifest.dart';
import 'package:baocode/update/update_service.dart';

import 'update_fakes.dart';

/// Runs nothing: answers as [answer] says, and keeps what was asked.
class _FakeProcesses implements UpdateProcesses {
  _FakeProcesses(this.answer);

  final ProcessResult Function(String executable, List<String> arguments)
  answer;
  final List<List<String>> runs = [];
  final List<List<String>> started = [];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    runs.add([executable, ...arguments]);
    return answer(executable, arguments);
  }

  @override
  Future<void> startDetached(String executable, List<String> arguments) async {
    started.add([executable, ...arguments]);
  }
}

ProcessResult _result(int exitCode, [String stdout = '', String stderr = '']) =>
    ProcessResult(0, exitCode, stdout, stderr);

UpdateRelease _release() {
  final manifest = UpdateManifest.parse(manifestOf('1.2.0+12'));
  return UpdateRelease(
    manifest: manifest,
    platform: 'macos-arm64',
    asset: manifest.assetFor('macos-arm64')!,
  );
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode-installer');
  });

  tearDown(() async {
    // Made read-only by a test.
    await Process.run('chmod', ['-R', 'u+w', temp.path]);
    await temp.delete(recursive: true);
  });

  group('Windows', () {
    const environment = {
      'ProgramFiles': r'C:\Program Files',
      'ProgramFiles(x86)': r'C:\Program Files (x86)',
      'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
    };

    test('installs as the install there is: per machine or per user', () {
      expect(
        windowsPerMachineInstall(
          r'C:\Program Files\BaoCode\baocode.exe',
          environment,
        ),
        isTrue,
      );
      expect(
        windowsPerMachineInstall(
          r'c:\program files (x86)\BaoCode\baocode.exe',
          environment,
        ),
        isTrue,
      );
      expect(
        windowsPerMachineInstall(
          r'C:\Users\me\AppData\Local\Programs\BaoCode\baocode.exe',
          environment,
        ),
        isFalse,
      );
      expect(
        windowsPerMachineInstall(r'C:\Program Files Extra\b.exe', environment),
        isFalse,
      );
    });

    test("Setup's command line: this install, once the app is gone", () {
      expect(
        windowsInstallerArguments(
          perMachine: true,
          directory: r'C:\Program Files\BaoCode',
          pid: 4242,
          log: r'C:\Users\me\AppData\Roaming\baocode\updates\install.log',
        ),
        [
          '/SILENT',
          '/SUPPRESSMSGBOXES',
          '/NORESTART',
          '/CLOSEAPPLICATIONS',
          '/RELAUNCH',
          '/ALLUSERS',
          r'/DIR=C:\Program Files\BaoCode',
          '/WAITPID=4242',
          r'/LOG=C:\Users\me\AppData\Roaming\baocode\updates\install.log',
        ],
      );
      expect(
        windowsInstallerArguments(
          perMachine: false,
          directory: 'x',
          pid: 1,
          log: 'y',
        ),
        contains('/CURRENTUSER'),
      );
    });

    WindowsUpdateInstaller installerIn(
      Directory app,
      _FakeProcesses processes,
    ) => WindowsUpdateInstaller(
      executable: p.join(app.path, 'baocode.exe'),
      pid: 4242,
      environment: environment,
      updatesDirectory: p.join(temp.path, 'updates'),
      processes: processes,
    );

    test('updates only an app its installer installed', () async {
      final app = Directory(p.join(temp.path, 'BaoCode'))..createSync();
      final processes = _FakeProcesses((_, _) => _result(1));
      final installer = installerIn(app, processes);
      await expectLater(
        installer.prepare('setup.exe', _release()),
        throwsA(isA<ManualUpdateRequired>()),
      );

      File(p.join(app.path, 'unins000.exe')).createSync();
      final update = await installer.prepare('setup.exe', _release());
      expect(processes.started, isEmpty, reason: 'not before the app quits');
      await update.launch();
      final started = processes.started.single;
      // Setup itself, no shell in between.
      expect(started.first, 'setup.exe');
      expect(started, contains('/DIR=${app.path}'));
      expect(started, contains('/WAITPID=4242'));
      expect(
        started,
        contains('/LOG=${p.join(temp.path, 'updates', 'install.log')}'),
      );
      // Registered nowhere, and not under Program Files: per user.
      expect(started, contains('/CURRENTUSER'));
    });

    test('takes the install mode from where Setup registered it', () async {
      // Per machine, in a folder of its own outside Program Files.
      final app = Directory(p.join(temp.path, 'BaoCode'))..createSync();
      File(p.join(app.path, 'unins000.exe')).createSync();
      bool Function(String hive) registered = (hive) => hive == 'HKLM';
      final processes = _FakeProcesses((executable, arguments) {
        expect(executable, 'reg.exe');
        expect(arguments.last, '/reg:64');
        final key = arguments[1];
        expect(key, endsWith(windowsUninstallKey));
        return _result(registered(key.split(r'\').first) ? 0 : 1);
      });
      final installer = installerIn(app, processes);
      expect(await installer.installedPerMachine(), isTrue);
      registered = (hive) => hive == 'HKCU';
      expect(await installer.installedPerMachine(), isFalse);
      // Both: where it is decides.
      registered = (_) => true;
      expect(await installer.installedPerMachine(), isFalse);
    });
  });

  test('a Mac updates to the build for its processor', () {
    expect(macUpdatePlatform(arm64: true, translated: false), 'macos-arm64');
    expect(macUpdatePlatform(arm64: false, translated: false), 'macos-x64');
    // The Intel build, run by Rosetta on Apple silicon, moves to the
    // Apple silicon one.
    expect(macUpdatePlatform(arm64: false, translated: true), 'macos-arm64');
  });

  group('macOS', () {
    late Directory applications;
    late String app;
    late String zip;

    setUp(() {
      applications = Directory(p.join(temp.path, 'Applications'))..createSync();
      app = p.join(applications.path, 'BaoCode.app');
      Directory(p.join(app, 'Contents', 'MacOS')).createSync(recursive: true);
      final version = Directory(p.join(temp.path, 'updates', '1.2.0+12'))
        ..createSync(recursive: true);
      zip = p.join(version.path, 'BaoCode-1.2.0-mac.zip');
      File(zip).createSync();
    });

    /// What macOS's tools answer: ditto unpacks [unpacked] apps; bundle ids
    /// by path; codesign as [signed] and [teams] say.
    _FakeProcesses tools({
      List<String> unpacked = const ['BaoCode.app'],
      Map<String, String> ids = const {},
      Set<String> signed = const {},
      Map<String, String> teams = const {},
      int dittoExit = 0,
    }) => _FakeProcesses((executable, arguments) {
      switch (executable) {
        case '/usr/bin/ditto':
          for (final name in unpacked) {
            Directory(p.join(arguments.last, name)).createSync();
          }
          return _result(dittoExit, '', dittoExit == 0 ? '' : 'bad zip');
        case '/usr/libexec/PlistBuddy':
          final bundle = p.dirname(p.dirname(arguments.last));
          final id =
              ids[p.basename(p.dirname(bundle))] ??
              ids[p.basename(bundle)] ??
              'dev.baocode.desktop';
          return _result(0, '$id\n');
        case '/usr/bin/codesign' when arguments.first == '--verify':
          return _result(signed.contains(_where(arguments.last)) ? 0 : 1);
        case '/usr/bin/codesign':
          final team = teams[_where(arguments.last)];
          return _result(
            0,
            '',
            'Executable=x\nTeamIdentifier=${team ?? 'not set'}\n',
          );
      }
      return _result(127);
    });

    MacUpdateInstaller installerOf(_FakeProcesses processes, {String? at}) =>
        MacUpdateInstaller(
          executable: p.join(at ?? app, 'Contents', 'MacOS', 'BaoCode'),
          pid: 4242,
          updatesDirectory: p.join(temp.path, 'updates'),
          processes: processes,
        );

    test('unpacks, checks, and swaps the app once it has quit', () async {
      final processes = tools();
      final update = await installerOf(processes).prepare(zip, _release());
      final staging = p.join(p.dirname(zip), 'staging');
      expect(processes.runs.first, [
        '/usr/bin/ditto',
        '-x',
        '-k',
        zip,
        staging,
      ]);
      expect(processes.started, isEmpty);
      await update.launch();
      final script = p.join(p.dirname(zip), 'install.sh');
      expect(processes.started.single, ['/bin/bash', script]);
      final text = File(script).readAsStringSync();
      expect(text, contains('pid=4242\n'));
      expect(text, contains("target='$app'\n"));
      expect(text, contains("source='${p.join(staging, 'BaoCode.app')}'\n"));
      expect(text, contains("staging='$staging'\n"));
      expect(
        text,
        contains("exec >>'${p.join(temp.path, 'updates', 'install.log')}'"),
      );
    });

    test('refuses another app, or none, in the zip', () async {
      await expectLater(
        installerOf(tools(ids: {'staging': 'com.example.other'}))
            .prepare(zip, _release()),
        throwsA(isA<UpdateVerificationException>()),
      );
      await expectLater(
        installerOf(tools(unpacked: [])).prepare(zip, _release()),
        throwsA(isA<UpdateVerificationException>()),
      );
      await expectLater(
        installerOf(tools(unpacked: ['BaoCode.app', 'Other.app']))
            .prepare(zip, _release()),
        throwsA(isA<UpdateVerificationException>()),
      );
      await expectLater(
        installerOf(tools(dittoExit: 1)).prepare(zip, _release()),
        throwsA(
          isA<UpdateVerificationException>().having(
            (e) => e.message,
            'message',
            contains('bad zip'),
          ),
        ),
      );
    });

    test('a signed app takes only an update signed by its team', () async {
      // Unsigned (a developer's build): unsigned is fine.
      await installerOf(tools()).prepare(zip, _release());
      // Signed: the update has to be too.
      await expectLater(
        installerOf(tools(signed: {'app'})).prepare(zip, _release()),
        throwsA(isA<UpdateVerificationException>()),
      );
      await installerOf(tools(signed: {'app', 'update'}))
          .prepare(zip, _release());
      // By the same team.
      await expectLater(
        installerOf(
          tools(
            signed: {'app', 'update'},
            teams: {'app': 'TEAM1', 'update': 'TEAM2'},
          ),
        ).prepare(zip, _release()),
        throwsA(isA<UpdateVerificationException>()),
      );
      await installerOf(
        tools(
          signed: {'app', 'update'},
          teams: {'app': 'TEAM1', 'update': 'TEAM1'},
        ),
      ).prepare(zip, _release());
    });

    test('sends the user to the download page where it cannot', () async {
      final translocated = p.join(
        temp.path,
        'private',
        'var',
        'folders',
        'AppTranslocation',
        'ABC',
        'd',
        'BaoCode.app',
      );
      await expectLater(
        installerOf(tools(), at: translocated).prepare(zip, _release()),
        throwsA(isA<ManualUpdateRequired>()),
      );
      await expectLater(
        installerOf(
          tools(),
          at: p.join(temp.path, 'build', 'baocode'),
        ).prepare(zip, _release()),
        throwsA(isA<ManualUpdateRequired>()),
      );
      await Process.run('chmod', ['a-w', applications.path]);
      await expectLater(
        installerOf(tools()).prepare(zip, _release()),
        throwsA(isA<ManualUpdateRequired>()),
      );
    }, skip: Platform.isWindows);

    test('the script waits, swaps, restores on failure, and reopens', () {
      final text = macUpdateScript(
        pid: 7,
        source: "/tmp/it's/BaoCode.app",
        target: '/Applications/BaoCode.app',
        staging: '/tmp/staging',
        log: '/tmp/install.log',
      );
      expect(text, startsWith('#!/bin/bash\n'));
      expect(text, contains(r"source='/tmp/it'\''s/BaoCode.app'"));
      final order = [
        'kill -0 "\$pid"',
        'exit 1',
        r'/usr/bin/ditto "$source" "$new" && mv "$target" "$old"',
        r'mv "$new" "$target"',
        r'mv "$old" "$target"',
        r'/usr/bin/xattr -dr com.apple.quarantine "$target"',
        r'/usr/bin/open "$target"',
      ];
      var at = 0;
      for (final step in order) {
        final found = text.indexOf(step, at);
        expect(found, greaterThan(-1), reason: step);
        at = found;
      }
      // It runs: bash finds no syntax error.
      final file = File(p.join(temp.path, 'install.sh'))
        ..writeAsStringSync(text);
      expect(Process.runSync('bash', ['-n', file.path]).exitCode, 0);
    }, skip: Platform.isWindows);
  });
}

/// Which bundle a codesign call is about: the app, or the update (in
/// staging/).
String _where(String bundle) =>
    p.split(bundle).contains('staging') ? 'update' : 'app';
