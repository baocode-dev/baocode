@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/kernel/claude_code/claude_environment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  final local = Platform.environment['LOCALAPPDATA'];
  final windowsApps = local == null
      ? null
      : p.join(local, 'Microsoft', 'WindowsApps');
  final store = windowsApps == null
      ? null
      : p.join(windowsApps, 'Microsoft.PowerShell_8wekyb3d8bbwe', 'pwsh.exe');
  final aliases =
      [?store, if (windowsApps != null) p.join(windowsApps, 'pwsh.exe')]
          .where(
            (path) =>
                FileSystemEntity.typeSync(path, followLinks: false) ==
                FileSystemEntityType.link,
          )
          .toList();

  test(
    'Store aliases work in automatic and explicit terminal profiles',
    () async {
      ClaudeEnvironment.use({'LOCALAPPDATA': local!});
      addTearDown(() => ClaudeEnvironment.use(null));
      final profiles = await terminalProfiles(
        configured: {
          for (final (index, path) in aliases.indexed)
            'Store $index': {'path': path},
        },
      );
      if (aliases.contains(store)) {
        expect(profiles.systemShell.executable, store);
      }
      final dir = await Directory.systemTemp.createTemp('baocode-pwsh');
      addTearDown(() => dir.delete());
      for (final (index, path) in aliases.indexed) {
        final profile = profiles.profiles.singleWhere(
          (profile) => profile.name == 'Store $index',
        );
        expect(profile.path, path);
        final pty = await spawnPty(
          PtyLaunch(
            executable: profile.path,
            arguments: ['-NoProfile', '-Command', r'$PSVersionTable.PSEdition'],
            workingDirectory: dir.path,
          ),
        );
        addTearDown(() => pty.kill());
        final output = utf8.decoder.bind(pty.output).join();
        expect(await pty.exitCode.timeout(const Duration(seconds: 15)), 0);
        expect(await output, contains('Core'));
      }
    },
    skip: aliases.isEmpty
        ? 'PowerShell Store aliases are not installed'
        : false,
  );
}
