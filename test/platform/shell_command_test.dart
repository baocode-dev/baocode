@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/shell_command.dart';
import 'package:baocode/platform/shell_command_io.dart';
import 'package:path/path.dart' as p;

/// The `code` command, installed into temporary folders only: what it
/// finds there, what it writes, what it refuses to replace, and what it
/// asks the system to run as root (run here as the user instead).
void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('baocode-shell'));
  tearDown(() {
    // Undo a read-only folder's mode, so it can go.
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is Directory) Process.runSync('chmod', ['755', entity.path]);
    }
    root.deleteSync(recursive: true);
  });

  File write(String path, String content) => File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);

  group('macOS', () {
    late String target;
    late String searchPath;
    late List<List<String>> ran;
    late ProcessResult Function(String command) osascript;

    setUp(() {
      target = p.join(root.path, 'usr local', 'bin', 'code');
      searchPath = '/usr/bin:${p.dirname(target)}:/bin';
      ran = [];
      osascript = (command) => ProcessResult(0, 0, '', '');
    });

    MacShellCommand command() => MacShellCommand(
      target: target,
      searchPath: () async => searchPath,
      temporaryDirectory: root.path,
      run: (executable, arguments, {environment}) async {
        ran.add([executable, ...arguments]);
        if (executable == 'osascript') {
          return osascript(_appleScriptCommand(arguments.last));
        }
        return Process.run(executable, arguments);
      },
    );

    test('installs a script of its own, there to be run', () async {
      final shell = command();
      expect(shell.location, target);
      expect(await shell.status(), ShellCommandStatus.notInstalled);
      await shell.install();
      expect(await shell.status(), ShellCommandStatus.installed);
      final script = File(target).readAsStringSync();
      expect(
        script,
        startsWith('#!/usr/bin/env bash\n# BaoCode shell command\n'),
      );
      expect(script, contains('open -b dev.baocode.desktop'));
      expect(File(target).statSync().modeString(), 'rwxr-xr-x');
      expect(ran.where((run) => run.first == 'osascript'), isEmpty);
    });

    test('another app\'s is not replaced unless asked', () async {
      write(target, '#!/bin/sh\necho vscode\n');
      final shell = command();
      expect(await shell.status(), ShellCommandStatus.occupied);
      await expectLater(shell.install(), throwsA(isA<ShellCommandException>()));
      expect(File(target).readAsStringSync(), contains('vscode'));

      await shell.uninstall();
      expect(File(target).existsSync(), isTrue, reason: 'not ours to remove');

      await shell.install(overwrite: true);
      expect(await shell.status(), ShellCommandStatus.installed);
    });

    test('a link in its place is replaced, not written through', () async {
      final vscode = write(p.join(root.path, 'VS Code', 'code'), 'vscode');
      Directory(p.dirname(target)).createSync(recursive: true);
      Link(target).createSync(vscode.path);
      final shell = command();
      expect(await shell.status(), ShellCommandStatus.occupied);
      await shell.install(overwrite: true);
      expect(vscode.readAsStringSync(), 'vscode');
      expect(FileSystemEntity.isLinkSync(target), isFalse);
      expect(await shell.status(), ShellCommandStatus.installed);

      // One that leads nowhere is someone's too.
      File(target).deleteSync();
      Link(target).createSync(p.join(root.path, 'gone'));
      expect(await shell.status(), ShellCommandStatus.occupied);
    });

    test('another ahead of it on the PATH occupies it', () async {
      final brew = p.join(root.path, 'homebrew', 'bin');
      write(p.join(brew, 'code'), 'vscode');
      searchPath = '$brew:${p.dirname(target)}';
      final shell = command();
      expect(await shell.status(), ShellCommandStatus.occupied);
      await expectLater(shell.install(), throwsA(isA<ShellCommandException>()));

      // Behind it, ours is the one run.
      searchPath = '${p.dirname(target)}:$brew';
      await shell.install();
      expect(await shell.status(), ShellCommandStatus.installed);
    });

    test('uninstalls only its own', () async {
      final shell = command();
      await shell.install();
      await shell.uninstall();
      expect(File(target).existsSync(), isFalse);
      expect(await shell.status(), ShellCommandStatus.notInstalled);
      await shell.uninstall();
    });

    test('a folder not the user\'s to write: as an administrator', () async {
      // Quotes and spaces, for the shell and AppleScript to keep.
      target = p.join(root.path, 'it\'s "admin"', 'bin', 'code');
      final locked = [p.dirname(p.dirname(target))];
      Directory(locked.first).createSync(recursive: true);
      Process.runSync('chmod', ['555', locked.first]);
      osascript = (command) {
        // As root would: the folders opened up for it, the command run.
        for (final dir in locked) {
          Process.runSync('chmod', ['755', dir]);
        }
        final result = Process.runSync('/bin/sh', ['-c', command]);
        for (final dir in locked) {
          Process.runSync('chmod', ['555', dir]);
        }
        return result;
      };
      final shell = command();
      await shell.install();
      expect(ran.where((run) => run.first == 'osascript'), hasLength(1));
      expect(await shell.status(), ShellCommandStatus.installed);
      expect(File(target).readAsStringSync(), shell.script);
      expect(File(target).statSync().modeString(), 'rwxr-xr-x');
      // The staged copy is gone.
      expect(
        root.listSync().where(
          (entity) =>
              p.basename(entity.path).startsWith('baocode-shell-command'),
        ),
        isEmpty,
      );

      locked.add(p.dirname(target));
      Process.runSync('chmod', ['555', p.dirname(target)]);
      await shell.uninstall();
      expect(File(target).existsSync(), isFalse);
      expect(ran.where((run) => run.first == 'osascript'), hasLength(2));
    });

    test('the password refused: cancelled, nothing installed', () async {
      Directory(p.dirname(target)).createSync(recursive: true);
      Process.runSync('chmod', ['555', p.dirname(target)]);
      osascript = (_) =>
          ProcessResult(0, 1, '', 'execution error: User canceled. (-128)');
      await expectLater(
        command().install(),
        throwsA(
          isA<ShellCommandException>().having(
            (error) => error.cancelled,
            'cancelled',
            isTrue,
          ),
        ),
      );
      osascript = (_) => ProcessResult(0, 1, '', 'something else');
      await expectLater(
        command().install(),
        throwsA(
          isA<ShellCommandException>()
              .having((error) => error.cancelled, 'cancelled', isFalse)
              .having((error) => error.message, 'message', contains('else')),
        ),
      );
      expect(File(target).existsSync(), isFalse);
    });

    test('the AppleScript keeps backslashes and quotes', () {
      expect(
        MacShellCommand.administratorScript(r'''echo "a\b" 'c' '''),
        r'''do shell script "echo \"a\\b\" 'c' " with administrator privileges''',
      );
    });

    group('the script', () {
      late String opened;

      /// Runs the installed script in [folder], with an `open` that writes
      /// down what it was given.
      Future<ProcessResult> run(List<String> arguments, String folder) async {
        final fakes = p.join(root.path, 'fakes');
        opened = p.join(root.path, 'opened.txt');
        write(
          p.join(fakes, 'open'),
          '#!/bin/sh\nfor a in "\$@"; do echo "\$a"; done > "$opened"\n',
        );
        Process.runSync('chmod', ['755', p.join(fakes, 'open')]);
        return Process.run(
          target,
          arguments,
          workingDirectory: folder,
          environment: {'PATH': '$fakes:/usr/bin:/bin'},
        );
      }

      List<String> openedWith() =>
          File(opened).existsSync() ? File(opened).readAsLinesSync() : [];

      test('hands what is there to the app', () async {
        await command().install();
        final project = Directory(p.join(root.path, 'my project'))
          ..createSync();
        write(p.join(project.path, 'a file.txt'), '');

        final result = await run([
          '-n',
          '.',
          'a file.txt',
          'gone',
        ], project.path);
        expect(result.exitCode, 0);
        expect(openedWith(), ['-b', 'dev.baocode.desktop', '.', 'a file.txt']);
        expect(result.stderr, 'code: gone: No such file or directory\n');
      });

      test('with nothing named, only brings it up', () async {
        await command().install();
        final result = await run(['--wait'], root.path);
        expect(result.exitCode, 0);
        expect(openedWith(), ['-b', 'dev.baocode.desktop']);
      });

      test('with nothing there, says so and fails', () async {
        await command().install();
        final result = await run(['nope'], root.path);
        expect(result.exitCode, 1);
        expect(openedWith(), isEmpty);
        expect(result.stderr, contains('nope: No such file or directory'));
      });
    });
  });

  group('Windows', () {
    late String bin;
    late String user;
    late String machine;
    late List<String> written;
    late Map<String, String> environment;

    setUp(() {
      bin = p.join(root.path, 'Local', 'BaoCode', 'bin');
      user = r'%ROOT%\tools;' + p.join(root.path, 'other');
      machine = p.join(root.path, 'System32');
      written = [];
      environment = {'PATHEXT': '.exe;.cmd', 'Root': root.path};
    });

    WindowsShellCommand command() => WindowsShellCommand(
      binDirectory: bin,
      executable: r'C:\Program Files\BaoCode %1\baocode.exe',
      environment: environment,
      run: (executable, arguments, {environment}) =>
          fail('no process to run: $executable'),
      readPaths: () async => (user: user, machine: machine),
      writeUserPath: (value) async {
        written.add(value);
        user = value;
      },
    );

    test('the script starts the app with what it is given', () {
      expect(
        command().script,
        '@echo off\r\n'
        'REM BaoCode shell command\r\n'
        'start "" "C:\\Program Files\\BaoCode %%1\\baocode.exe" %*\r\n',
      );
    });

    test('installs the script, its folder last on the user\'s PATH', () async {
      final shell = command();
      expect(shell.location, p.join(bin, 'code.cmd'));
      expect(await shell.status(), ShellCommandStatus.notInstalled);
      await shell.install();
      expect(File(shell.location).readAsStringSync(), shell.script);
      expect(written, ['%ROOT%\\tools;${p.join(root.path, 'other')};$bin']);
      expect(await shell.status(), ShellCommandStatus.installed);

      // Installed again: the PATH has it already.
      await shell.install();
      expect(written, hasLength(1));
    });

    test('its folder found under a variable is its own', () async {
      user = '%ROOT%/Local/BaoCode/bin;%ROOT%\\tools';
      final shell = command();
      await shell.install();
      expect(written, isEmpty);
      expect(await shell.status(), ShellCommandStatus.installed);

      await shell.uninstall();
      expect(written, [r'%ROOT%\tools']);
      expect(File(shell.location).existsSync(), isFalse);
      expect(await shell.status(), ShellCommandStatus.notInstalled);
    });

    test('a `code` ahead of it is not put behind unless asked', () async {
      final vscode = p.join(root.path, 'VS Code', 'bin');
      write(p.join(vscode, 'code.cmd'), '@echo vscode');
      user = vscode;
      final shell = command();
      expect(await shell.status(), ShellCommandStatus.occupied);
      await expectLater(shell.install(), throwsA(isA<ShellCommandException>()));
      expect(File(shell.location).existsSync(), isFalse);
      expect(written, isEmpty);

      await shell.install(overwrite: true);
      expect(written, ['$bin;$vscode']);
      expect(await shell.status(), ShellCommandStatus.installed);

      // Behind it again (the user moved it): occupied once more.
      user = '$vscode;$bin';
      expect(await shell.status(), ShellCommandStatus.occupied);
      await shell.install(overwrite: true);
      expect(user, '$bin;$vscode');
    });

    test('the machine\'s PATH comes first, and stays so', () async {
      write(p.join(machine, 'code.exe'), '');
      final shell = command();
      expect(await shell.status(), ShellCommandStatus.occupied);
      await shell.install(overwrite: true);
      expect(await shell.status(), ShellCommandStatus.occupied);
    });

    test('a file of another\'s in its place is left at uninstall', () async {
      final shell = command();
      write(shell.location, '@echo not ours');
      user = bin;
      expect(await shell.status(), ShellCommandStatus.occupied);
      await shell.uninstall();
      expect(File(shell.location).readAsStringSync(), '@echo not ours');
    });

    test('without %LOCALAPPDATA%: unsupported', () async {
      final shell = WindowsShellCommand(environment: const {});
      expect(shell.location, isEmpty);
      expect(await shell.status(), ShellCommandStatus.unsupported);
      await expectLater(shell.install(), throwsA(isA<ShellCommandException>()));
    });
  });

  group('ShellCommand', () {
    // The tests' own stand-in (flutter_test_config.dart) put aside.
    setUp(() => ShellCommand.debugInstaller = null);
    tearDown(() => ShellCommand.debugInstaller = null);

    test('nothing to install off the desktop', () async {
      expect(ShellCommand.supported, isFalse);
      expect(ShellCommand.location, isEmpty);
      expect(await ShellCommand.status(), ShellCommandStatus.unsupported);
      await expectLater(
        ShellCommand.install(),
        throwsA(isA<ShellCommandException>()),
      );
      await ShellCommand.uninstall();
    });

    test('goes to the platform\'s installer', () async {
      final target = p.join(root.path, 'bin', 'code');
      ShellCommand.debugInstaller = MacShellCommand(
        target: target,
        searchPath: () async => p.dirname(target),
      );
      expect(ShellCommand.supported, isTrue);
      expect(ShellCommand.location, target);
      await ShellCommand.install();
      expect(await ShellCommand.status(), ShellCommandStatus.installed);
      await ShellCommand.uninstall();
      expect(await ShellCommand.status(), ShellCommandStatus.notInstalled);
    });
  });
}

/// The shell command in `do shell script "…" with administrator
/// privileges`, its AppleScript escapes undone.
String _appleScriptCommand(String script) {
  final match = RegExp(
    r'^do shell script "(.*)" with administrator privileges$',
    dotAll: true,
  ).firstMatch(script)!;
  return match[1]!.replaceAllMapped(RegExp(r'\\(.)'), (escape) => escape[1]!);
}
