import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Ends the process [pid] and every process it started, as a command's
/// shell leaves its children running when only it is killed. [windows]
/// for Windows' way of it (where this runs, when not given).
Future<void> killTree(int pid, {bool force = false, bool? windows}) async {
  if (windows ?? Platform.isWindows) {
    try {
      await Process.run('taskkill', ['/T', '/F', '/PID', '$pid']);
    } on ProcessException {
      Process.killPid(pid);
    }
    return;
  }
  final tree = <int>[pid, ...await _descendants(pid)];
  final signal = force ? ProcessSignal.sigkill : ProcessSignal.sigterm;
  // The children first, so none is left orphaned to go on.
  for (final id in tree.reversed) {
    Process.killPid(id, signal);
  }
  if (force) return;
  // What does not end on being asked is made to.
  unawaited(
    Future<void>.delayed(const Duration(seconds: 2), () {
      for (final id in tree) {
        Process.killPid(id, ProcessSignal.sigkill);
      }
    }),
  );
}

/// A process's output, read to [stdout] and [stderr] as it comes.
class ProcessOutput {
  ProcessOutput(
    Process process,
    void Function(List<int> bytes) stdout,
    void Function(List<int> bytes) stderr,
  ) {
    _reading = [process.stdout.listen(stdout), process.stderr.listen(stderr)];
    _ended = Future.wait([for (final r in _reading) r.asFuture<void>()]);
  }

  late final List<StreamSubscription<List<int>>> _reading;
  late final Future<void> _ended;

  /// Waits, once the process has ended, for its output to end as well, for
  /// [grace] at most: what it left running (started apart, out of
  /// [killTree]'s reach) may hold its pipes open long after. Those still
  /// open then are no longer read.
  Future<void> ended({Duration grace = const Duration(seconds: 2)}) async {
    try {
      await _ended.timeout(grace);
    } on TimeoutException {
      await Future.wait([for (final r in _reading) r.cancel()]);
    } on Object {
      // A pipe that broke: what came of it is all there is.
    }
  }
}

Future<List<int>> _descendants(int pid) async {
  try {
    final result = await Process.run('ps', ['-A', '-o', 'pid=,ppid=']);
    final children = <int, List<int>>{};
    for (final line in '${result.stdout}'.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 2) continue;
      final child = int.tryParse(parts[0]);
      final parent = int.tryParse(parts[1]);
      if (child == null || parent == null) continue;
      (children[parent] ??= []).add(child);
    }
    final out = <int>[];
    final pending = [pid];
    while (pending.isNotEmpty) {
      final next = pending.removeLast();
      for (final child in children[next] ?? const <int>[]) {
        if (out.contains(child)) continue;
        out.add(child);
        pending.add(child);
      }
    }
    return out;
  } on ProcessException {
    return const [];
  }
}

/// The shell commands are run in: the user's, when it is bash or zsh;
/// else bash; on Windows, Git's bash where it is installed.
class Shell {
  const Shell(this.executable, {this.posix = true});

  final String executable;

  /// Whether it takes POSIX shell commands (not cmd.exe).
  final bool posix;

  /// The shell for [environment]'s user, on Windows when [windows] (where
  /// this runs, when not given); [exists] says whether a file is there.
  static Shell find(
    Map<String, String> environment, {
    bool? windows,
    bool Function(String path)? exists,
  }) {
    exists ??= (path) => File(path).existsSync();
    if (windows ?? Platform.isWindows) {
      final path = p.windows;
      final candidates = [
        environment['CLAUDE_CODE_GIT_BASH_PATH'],
        // Git's own, by the git on the PATH (`Git\cmd\git.exe`).
        for (final dir
            in (environment['PATH'] ?? environment['Path'] ?? '').split(';'))
          if (dir.isNotEmpty && exists(path.join(dir, 'git.exe')))
            path.normalize(path.join(dir, '..', 'bin', 'bash.exe')),
        r'C:\Program Files\Git\bin\bash.exe',
        r'C:\Program Files (x86)\Git\bin\bash.exe',
        if (environment['LOCALAPPDATA'] case final local?)
          path.join(local, 'Programs', 'Git', 'bin', 'bash.exe'),
      ];
      for (final candidate in candidates.whereType<String>()) {
        if (exists(candidate)) return Shell(candidate);
      }
      return Shell(environment['COMSPEC'] ?? 'cmd.exe', posix: false);
    }
    final user = environment['SHELL'];
    if (user != null &&
        (user.endsWith('/bash') || user.endsWith('/zsh')) &&
        exists(user)) {
      return Shell(user);
    }
    for (final candidate in const ['/bin/bash', '/usr/bin/bash', '/bin/zsh']) {
      if (exists(candidate)) return Shell(candidate);
    }
    return const Shell('/bin/sh');
  }

  /// The arguments that run [command], then write the folder it ended in
  /// to [cwdFile] (so that a `cd` holds for the next command).
  List<String> arguments(String command, String cwdFile) {
    if (!posix) return ['/d', '/s', '/c', command];
    const script =
        r'eval "$1" < /dev/null; __bao_status=$?; '
        r'pwd -P >| "$2" 2>/dev/null; exit $__bao_status';
    return ['-c', script, p.basename(executable), command, cwdFile];
  }
}
