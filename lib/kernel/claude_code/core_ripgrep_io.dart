import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show FileIndex;
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';
import 'local_claude_io.dart';

/// ripgrep for BaoCode's own core where the machine has none (#883): as
/// Claude Code's own build carries one (it is ripgrep when run with
/// `ARGV0=rg`), the one BaoCode runs gives it. Without, a search on
/// Windows was cmd.exe's `findstr` or a script written for it: slow, and
/// short of what `rg` finds.
abstract final class CoreRipgrep {
  /// The build last asked, and whether it is ripgrep with `ARGV0=rg`.
  static (String, bool)? _asked;

  /// [environment] with `rg` on its `PATH` and Claude Code's build named
  /// for the core's own searches ([FileIndex.multicallVariable]), where it
  /// has no `rg` and that build gives one; else as it is.
  static Future<void> addTo(Map<String, String> environment) async {
    if (FileIndex(environment).which('rg', scripts: false) != null) return;
    try {
      final cli = await LocalClaude.locate(install: false);
      final executable = cli.executable;
      if (!await _isRipgrep(executable)) return;
      final bin = await writeShims(
        p.join(DataDirectory.current.path, 'bin'),
        executable,
      );
      environment[FileIndex.multicallVariable] = executable;
      final key = Platform.isWindows
          ? environment.keys.firstWhere(
              (name) => name.toUpperCase() == 'PATH',
              orElse: () => 'PATH',
            )
          : 'PATH';
      final path = environment[key];
      environment[key] = path == null || path.isEmpty
          ? bin
          : '$bin${Platform.isWindows ? ';' : ':'}$path';
    } on Object catch (error) {
      // Searched without, as before.
      debugPrint('No ripgrep for the core: $error');
    }
  }

  static Future<bool> _isRipgrep(String executable) async {
    if (_asked case (final asked, final answer) when asked == executable) {
      return answer;
    }
    var answer = false;
    try {
      // A native build: not a script, nor npm's, that has no ripgrep in it
      // and would be run as Claude Code.
      if (!_native(executable)) throw const FormatException('not native');
      final result = await Process.run(
        executable,
        const ['--version'],
        environment: const {'ARGV0': 'rg'},
      ).timeout(const Duration(seconds: 10));
      answer = result.exitCode == 0 && '${result.stdout}'.startsWith('ripgrep');
    } on Object {
      answer = false;
    }
    _asked = (executable, answer);
    return answer;
  }

  /// Whether [path] starts as a program built for a machine does: ELF,
  /// Mach-O, or Windows' MZ.
  static bool _native(String path) {
    final file = File(path).openSync();
    try {
      final head = file.readSync(4);
      if (head.length < 4) return false;
      final magic =
          (head[0] << 24) | (head[1] << 16) | (head[2] << 8) | head[3];
      return magic == 0x7f454c46 ||
          const {
            0xcffaedfe,
            0xcefaedfe,
            0xfeedfacf,
            0xcafebabe,
          }.contains(magic) ||
          (head[0] == 0x4d && head[1] == 0x5a);
    } finally {
      file.closeSync();
    }
  }

  /// `rg` in [dir], running [executable] as ripgrep: a POSIX shell's, and
  /// on Windows cmd.exe's too. Written only where not already so. Returns
  /// [dir].
  @visibleForTesting
  static Future<String> writeShims(
    String dir,
    String executable, {
    bool? windows,
  }) async {
    windows ??= Platform.isWindows;
    await Directory(dir).create(recursive: true);
    final quoted = "'${executable.replaceAll("'", r"'\''")}'";
    final shims = {
      'rg': '#!/bin/sh\nARGV0=rg exec $quoted "\$@"\n',
      if (windows)
        'rg.cmd':
            '@echo off\r\nsetlocal\r\nset "ARGV0=rg"\r\n"$executable" %*\r\n',
    };
    for (final MapEntry(key: name, value: text) in shims.entries) {
      final file = File(p.join(dir, name));
      if (file.existsSync() && file.readAsStringSync() == text) continue;
      await file.writeAsString(text, flush: true);
      if (!windows) await Process.run('chmod', ['755', file.path]);
    }
    return dir;
  }
}
