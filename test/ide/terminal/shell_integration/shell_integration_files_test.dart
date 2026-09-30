import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration_files.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration_injection.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration_scripts.dart';
import 'package:monad/ide/terminal/terminal_shell.dart';
import 'package:path/path.dart' as p;

/// VS Code's scripts written where a shell loads them, in a temp folder of
/// the test's own; no shell is started.
void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('monad-si-test'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('the scripts are VS Code 6a598d4a\'s, headers and all', () {
    expect(shellIntegrationScripts.keys, [
      'shellIntegration-bash.sh',
      'shellIntegration-env.zsh',
      'shellIntegration-login.zsh',
      'shellIntegration-profile.zsh',
      'shellIntegration-rc.zsh',
      'shellIntegration.fish',
      'shellIntegration.ps1',
    ]);
    // Their sizes in bytes at 6a598d4a (the generator checks the bytes).
    expect(
      {
        for (final MapEntry(:key, :value) in shellIntegrationScripts.entries)
          key: utf8.encode(value).length,
      },
      {
        'shellIntegration-bash.sh': 14603,
        'shellIntegration-env.zsh': 592,
        'shellIntegration-login.zsh': 593,
        'shellIntegration-profile.zsh': 848,
        'shellIntegration-rc.zsh': 10424,
        'shellIntegration.fish': 7886,
        'shellIntegration.ps1': 11122,
      },
    );
    for (final script in shellIntegrationScripts.values) {
      expect(
        script,
        startsWith(
          '# ------------------------------------------------------------------'
          '---------------------------\n'
          '#   Copyright (c) Microsoft Corporation. All rights reserved.\n'
          '#   Licensed under the MIT License.',
        ),
      );
      expect(script, isNot(contains('\r')));
    }
    expect(
      shellIntegrationScripts['shellIntegration-bash.sh'],
      contains(r'\e]633;E;%s;%s\a'),
    );
  });

  group('ShellIntegrationFolder', () {
    test('is a new private folder with every script in it', () {
      final folder = ShellIntegrationFolder(temp);
      final root = folder.path;
      expect(p.dirname(root), temp.path);
      expect(p.basename(root), startsWith('monad-shell-integration-'));
      if (!Platform.isWindows) {
        // Like mkdtemp: the user's alone.
        expect(Directory(root).statSync().mode & 0x1ff, 0x1c0);
      }
      for (final MapEntry(:key, :value) in shellIntegrationScripts.entries) {
        expect(File(p.join(root, key)).readAsStringSync(), value);
      }
      // The same folder for the next terminal.
      expect(folder.path, root);
      expect(temp.listSync(), hasLength(1));
    });

    test('puts back a script that changed, and the folder once gone', () {
      final folder = ShellIntegrationFolder(temp);
      final root = folder.path;
      final bash = File(p.join(root, 'shellIntegration-bash.sh'))
        ..writeAsStringSync('echo tampered');
      expect(folder.path, root);
      expect(
        bash.readAsStringSync(),
        shellIntegrationScripts['shellIntegration-bash.sh'],
      );
      Directory(root).deleteSync(recursive: true);
      final again = folder.path;
      expect(again, isNot(root));
      expect(File(p.join(again, 'shellIntegration.fish')).existsSync(), isTrue);
      // No temporary file is left behind.
      expect(
        Directory(again).listSync().map((e) => p.basename(e.path)),
        unorderedEquals(shellIntegrationScripts.keys),
      );
    });

    test('throws when the folder cannot be made', () {
      final folder = ShellIntegrationFolder(Directory(p.join(temp.path, 'no')));
      expect(() => folder.path, throwsA(isA<FileSystemException>()));
    });
  });

  test('copyShellIntegrationFiles copies, and swallows failures', () {
    final source = File(p.join(temp.path, 'source'))..writeAsStringSync('rc');
    final dest = p.join(temp.path, 'zsh', '.zshrc');
    copyShellIntegrationFiles([
      (source: p.join(temp.path, 'missing'), dest: p.join(temp.path, 'x')),
      (source: source.path, dest: dest),
    ]);
    expect(File(dest).readAsStringSync(), 'rc');
    expect(File(p.join(temp.path, 'x')).existsSync(), isFalse);
  });

  group('injectShellIntegration', () {
    const environment = {'PATH': '/usr/bin:/bin', 'HOME': '/Users/me'};

    PtyLaunch launch(String shell, List<String> arguments) => PtyLaunch(
      executable: shell,
      arguments: arguments,
      workingDirectory: '/project',
      environment: environment,
    );

    test('makes zsh load the scripts from its own ZDOTDIR', () {
      final folder = ShellIntegrationFolder(temp);
      final injected = injectShellIntegration(
        launch('/bin/zsh', ['-l']),
        os: TerminalOs.macOS,
        nonce: 'the-nonce',
        folder: folder,
      );
      final root = folder.path;
      final zdotdir = p.join(root, 'zsh');
      expect(injected.arguments, ['-il']);
      expect(injected.environment, {
        ...environment,
        'VSCODE_INJECTION': '1',
        'VSCODE_NONCE': 'the-nonce',
        'ZDOTDIR': zdotdir,
        'USER_ZDOTDIR': isNotEmpty,
      });
      for (final (name, script) in [
        ('.zshrc', 'shellIntegration-rc.zsh'),
        ('.zprofile', 'shellIntegration-profile.zsh'),
        ('.zshenv', 'shellIntegration-env.zsh'),
        ('.zlogin', 'shellIntegration-login.zsh'),
      ]) {
        expect(
          File(p.join(zdotdir, name)).readAsStringSync(),
          shellIntegrationScripts[script],
        );
      }
    });

    test('points bash at the script in the folder', () {
      final folder = ShellIntegrationFolder(temp);
      final injected = injectShellIntegration(
        launch('/bin/bash', ['-l']),
        os: TerminalOs.macOS,
        folder: folder,
      );
      final script = p.join(folder.path, 'shellIntegration-bash.sh');
      expect(injected.arguments, ['--init-file', script]);
      expect(File(script).existsSync(), isTrue);
      expect(injected.environment!['VSCODE_SHELL_LOGIN'], '1');
      expect(injected.environment!['VSCODE_STABLE'], '1');
      // A new nonce for each terminal.
      expect(shellIntegrationNonce(injected), hasLength(36));
      expect(
        shellIntegrationNonce(
          injectShellIntegration(
            launch('/bin/bash', ['-l']),
            os: TerminalOs.macOS,
            folder: folder,
          ),
        ),
        isNot(shellIntegrationNonce(injected)),
      );
    });

    test('leaves an unsupported shell as it was, with the nonce', () {
      final injected = injectShellIntegration(
        launch('/bin/sh', const []),
        os: TerminalOs.linux,
        nonce: 'n',
        folder: ShellIntegrationFolder(temp),
      );
      expect(injected.executable, '/bin/sh');
      expect(injected.arguments, isEmpty);
      expect(injected.environment, {...environment, 'VSCODE_NONCE': 'n'});
    });

    test('starts the shell as it was when the folder cannot be made', () {
      final injected = injectShellIntegration(
        launch('/bin/zsh', ['-l']),
        os: TerminalOs.macOS,
        nonce: 'n',
        folder: ShellIntegrationFolder(Directory(p.join(temp.path, 'no'))),
      );
      expect(injected.arguments, ['-l']);
      expect(injected.environment, {...environment, 'VSCODE_NONCE': 'n'});
    });
  });

  test('windowsBuildNumber reads Dart\'s description of Windows', () {
    expect(windowsBuildNumber('"Windows 10 Pro" 10.0 (Build 19045)'), 19045);
    expect(windowsBuildNumber('"Windows 11 Home" 10.0 (Build 22631)'), 22631);
    expect(windowsBuildNumber('10.0.18309'), 18309);
    expect(windowsBuildNumber('Darwin Kernel Version 25.5.0'), 0);
  });
}
