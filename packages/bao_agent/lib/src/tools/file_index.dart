import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../util/cancel.dart';

/// The files under a folder, as a search goes through them: those git (or
/// ripgrep) would not ignore, hidden ones too, `.git` itself left out.
class FileIndex {
  FileIndex(this.environment);

  /// The environment programs are looked up in (`PATH`).
  final Map<String, String> environment;

  /// The most a folder that is no repository is walked for.
  static const maxWalked = 100000;

  /// Names a program that is ripgrep when run with `ARGV0=rg` (Claude
  /// Code's own build, which carries one): the app's, where the machine
  /// has no `rg` of its own.
  static const multicallVariable = 'BAOCODE_RIPGREP';

  /// ripgrep, where there is one: installed, else Claude Code's
  /// ([multicallVariable]); null when neither.
  late final String? ripgrep = which('rg', scripts: false) ?? _multicall?.$1;

  /// What ripgrep is run with: `ARGV0` where it is Claude Code's.
  late final Map<String, String> _ripgrepEnvironment = switch (_multicall) {
    (_, final environment) => environment,
    null => environment,
  };

  late final (String, Map<String, String>)? _multicall =
      switch (environment[multicallVariable]) {
        final path? when path.isNotEmpty && File(path).existsSync() => (
          path,
          {...environment, 'ARGV0': 'rg'},
        ),
        _ => null,
      };

  /// [program]'s path on `PATH`; null when it is not there. On Windows,
  /// a `.cmd` (or one with no extension) only with [scripts]: those are
  /// not started as a program is.
  String? which(String program, {bool scripts = true}) {
    final path =
        environment['PATH'] ??
        environment['Path'] ??
        Platform.environment['PATH'] ??
        '';
    final separator = Platform.isWindows ? ';' : ':';
    final names = Platform.isWindows
        ? [
            '$program.exe',
            if (scripts) ...['$program.cmd', program],
          ]
        : [program];
    for (final dir in path.split(separator)) {
      if (dir.isEmpty) continue;
      for (final name in names) {
        final candidate = p.join(dir, name);
        final file = File(candidate);
        if (!file.existsSync()) continue;
        if (Platform.isWindows) return candidate;
        // Executable by someone: the mode's x bits.
        if (file.statSync().mode & 0x49 != 0) return candidate;
      }
    }
    return null;
  }

  /// The files under [root] (absolute paths). Ignored files are left out
  /// unless [ignored].
  Future<List<String>> list(
    String root, {
    bool ignored = false,
    CancelToken? cancel,
  }) async {
    if (!ignored) {
      if (ripgrep case final rg?) {
        final files = await _run(
          rg,
          ['--files', '--hidden', '--glob', '!.git', '--null', '.'],
          root,
          cancel,
        );
        if (files != null) return files;
      }
      final git = await _run(
        'git',
        ['ls-files', '-z', '--cached', '--others', '--exclude-standard'],
        root,
        cancel,
      );
      if (git != null) {
        // Deleted but still in the index: not there to search.
        return [
          for (final file in git)
            if (File(file).existsSync()) file,
        ];
      }
    }
    return _walk(root, cancel);
  }

  Future<List<String>?> _run(
    String executable,
    List<String> arguments,
    String root,
    CancelToken? cancel,
  ) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: root,
        environment: executable == ripgrep ? _ripgrepEnvironment : environment,
      );
      unawaited(cancel?.whenCancelled.then((_) => process.kill()));
      final stdout = process.stdout.transform(utf8.decoder).join();
      unawaited(process.stderr.drain<void>());
      final code = await process.exitCode;
      final out = await stdout;
      // ripgrep says 1 when it found nothing.
      if (code != 0 && !(code == 1 && executable == ripgrep)) return null;
      return [
        for (final name in out.split('\x00'))
          if (name.trim().isNotEmpty)
            p.normalize(
              p.join(root, name.startsWith('./') ? name.substring(2) : name),
            ),
      ];
    } on ProcessException {
      return null;
    }
  }

  List<String> _walk(String root, CancelToken? cancel) {
    final out = <String>[];
    final pending = [Directory(root)];
    while (pending.isNotEmpty && out.length < maxWalked) {
      cancel?.check();
      final dir = pending.removeLast();
      List<FileSystemEntity> entries;
      try {
        entries = dir.listSync(followLinks: false);
      } on FileSystemException {
        continue;
      }
      for (final entry in entries) {
        final name = p.basename(entry.path);
        if (entry is Directory) {
          if (name == '.git' || name == '.hg' || name == '.svn') continue;
          pending.add(entry);
        } else if (entry is File) {
          out.add(entry.path);
        } else if (entry is Link) {
          if (FileSystemEntity.isFileSync(entry.path)) out.add(entry.path);
        }
      }
    }
    return out;
  }
}

/// Sorts [paths] newest first; those that cannot be read last.
List<String> byModified(List<String> paths) {
  final times = <String, int>{
    for (final path in paths)
      path: () {
        try {
          return File(path).lastModifiedSync().millisecondsSinceEpoch;
        } on FileSystemException {
          return 0;
        }
      }(),
  };
  return [...paths]..sort((a, b) {
    final byTime = times[b]!.compareTo(times[a]!);
    return byTime != 0 ? byTime : a.compareTo(b);
  });
}

/// [path] as the model is shown it: from [cwd] when inside it.
String shownPath(String path, String cwd) =>
    p.isWithin(cwd, path) ? p.relative(path, from: cwd) : path;
