import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The parent and command line of a running process.
typedef RunningProcess = ({int parent, String command});

/// Child processes of one kind the app has running (Claude Code, language
/// servers), kept in a file so that a later start can end those a previous
/// one left behind: after a crash, a force quit, or a hot restart (which
/// keeps the app's process, and with it the children's pipes, so they would
/// never see their input end).
///
/// Each entry records the child's pid, the app's pid, and the child's
/// command line as `ps` showed it once started. A leftover is ended only
/// when it still runs that very command (a pid can be reused) and is an
/// orphan or a child of this process (another copy of the app may be
/// running its own). An entry without a command (from before commands were
/// recorded, or whose lookup failed) is ended only when [recognizes] its
/// command.
class ChildProcessRegistry {
  ChildProcessRegistry({
    required this.file,
    int? ownPid,
    this.lookup = psLookup,
    this.signal = _signal,
    this.recognizes = _never,
  }) : ownPid = ownPid ?? pid;

  final File file;
  final int ownPid;

  /// The parent and command line of a running process; null when none runs.
  final Future<RunningProcess?> Function(int pid) lookup;
  final bool Function(int pid) signal;

  /// Whether a command line is of this kind, for entries without one.
  final bool Function(String command) recognizes;

  /// This run's children and their command lines (null when unknown).
  final Map<int, String?> _children = {};

  /// Entries of other apps still running, kept as they were.
  final List<Map<String, Object?>> _others = [];
  Future<void> _writes = Future.value();

  /// Completes once what a previous run left is ended; started on first use.
  late final Future<void> reaped = _reap();

  Future<void> _reap() async {
    if (Platform.isWindows) return; // No `ps` to tell a reused pid apart.
    try {
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return;
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final (child, parent) = (entry['pid'], entry['parent']);
        if (child is! int || parent is! int) continue;
        final command = entry['command'];
        final running = await lookup(child);
        if (running == null) continue;
        final same = command is String
            ? running.command == command
            : recognizes(running.command);
        if (!same) continue;
        if (running.parent == 1 || running.parent == ownPid) {
          signal(child);
        } else if (running.parent == parent) {
          _others.add({
            'pid': child,
            'parent': parent,
            if (command is String) 'command': command,
          });
        }
      }
    } on Object {
      // A missing or unreadable file: nothing to reap.
    }
    await _save();
  }

  /// Records [child]; its command line is looked up unless given.
  Future<void> add(int child, {String? command}) async {
    await reaped;
    if (command == null && !Platform.isWindows) {
      try {
        command = (await lookup(child))?.command;
      } on Object {
        // Recorded without one: only [recognizes] can end it later.
      }
    }
    _children[child] = command;
    await _save();
  }

  Future<void> remove(int child) async {
    await reaped;
    if (_children.containsKey(child)) {
      _children.remove(child);
      await _save();
    }
  }

  Future<void> _save() => _writes = _writes.then((_) async {
    try {
      await file.parent.create(recursive: true);
      // Written aside, then renamed over: a reader (the next run, reaping)
      // never sees half a file.
      final written = await File('${file.path}.$ownPid.tmp').writeAsString(
        jsonEncode([
          ..._others,
          for (final MapEntry(key: child, value: command) in _children.entries)
            {'pid': child, 'parent': ownPid, 'command': ?command},
        ]),
      );
      await written.rename(file.path);
    } on FileSystemException {
      // Best effort: at worst a leftover is not found next time.
    }
  });

  /// [lookup] by `ps`.
  static Future<RunningProcess?> psLookup(int child) async {
    final result = await Process.run('ps', [
      '-o',
      'ppid=,command=',
      '-p',
      '$child',
    ]);
    if (result.exitCode != 0) return null;
    final line = '${result.stdout}'.trim();
    final space = line.indexOf(' ');
    if (space < 0) return null;
    final parent = int.tryParse(line.substring(0, space));
    if (parent == null) return null;
    return (parent: parent, command: line.substring(space + 1).trim());
  }

  static bool _signal(int child) => Process.killPid(child);

  static bool _never(String command) => false;
}
