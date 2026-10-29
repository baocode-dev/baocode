import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../update/version.dart';

/// What the app went through, one line each, in `logs/events.log`
/// (`DataDirectory.logsDir`), beside [ErrorLog]'s errors.log: its windows
/// and views, coming to the front and going, the color theme, the stash's
/// panel. A release build fails silently at times — a window that draws
/// nothing, with no error — and what led to it is then read here, in the
/// diagnostics a user uploads (Settings → Updates).
///
/// Only what happened, never what the user wrote: no text, no titles.
///
/// A run's first line names the app's version and the system; its last,
/// how it ended ([appExit]: quit, a signal, the session's end, a crash the
/// native side caught). A run that ended without one was killed (as
/// `kill -9` does, or the system for memory) or crashed past the native
/// side, or the machine went down: the next run says so as it starts,
/// with the crash report the system kept of it, if any ([crashSince]).
///
/// Past [maxBytes], the file becomes `events.1.log` and a new one starts,
/// so the latest events are always kept.
class EventLog {
  EventLog(
    this.directory, {
    this.maxBytes = 1024 * 1024,
    this.crashSince,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The app's, once `main` has made it; none under test.
  static EventLog? current;

  /// The folder of the log files.
  final String directory;

  final int maxBytes;

  /// The crash report the system kept of the app since a time (the run
  /// before's last event), in a line; null when none.
  final String? Function(DateTime since)? crashSince;

  final DateTime Function() _clock;

  /// The category of a run's last line: how it ended. The native side
  /// writes it too (windows/runner/log_folder.h, packages/bao_sampler's
  /// crash handler), in the same form.
  static const exitCategory = 'exit';

  /// How much of the file's end is read for how the run before ended.
  static const _tailBytes = 64 * 1024;

  String get path => p.join(directory, 'events.log');

  /// The file before it, moved aside.
  String get previousPath => p.join(directory, 'events.1.log');

  bool _started = false;
  int _size = 0;

  /// Writes [message] under [category] (`window`, `theme`…), timed.
  void record(String category, String message) {
    try {
      _write('${_clock().toIso8601String()} [$category] $message\n');
    } catch (_) {
      // The log is no reason to fail: a disk full, a folder gone.
    }
  }

  void _write(String line) {
    if (!_started) {
      _started = true;
      Directory(directory).createSync(recursive: true);
      final file = File(path);
      _size = file.existsSync() ? file.lengthSync() : 0;
      final before = _runBefore(file);
      _rollIfFull(0);
      _append(
        '--- BaoCode $appVersionString · ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion} · pid $pid ---\n',
      );
      if (before != null) _append(_unannounced(before));
    }
    _rollIfFull(line.length);
    _append(line);
  }

  /// The run before's, from the end of [file], if it ended without a word:
  /// its pid (when its first line is in what is read) and its last event's
  /// time.
  ({String? pid, DateTime? last})? _runBefore(File file) {
    if (_size == 0) return null;
    final String tail;
    final handle = file.openSync();
    try {
      final from = max(0, _size - _tailBytes);
      handle.setPositionSync(from);
      tail = utf8.decode(handle.readSync(_size - from), allowMalformed: true);
    } finally {
      handle.closeSync();
    }
    final lines = const LineSplitter().convert(tail);
    final first = lines.lastIndexWhere((line) => line.startsWith('--- '));
    final run = lines.skip(max(0, first));
    if (run.any((line) => line.contains(' [$exitCategory] '))) return null;
    final pid = first < 0
        ? null
        : RegExp(r'· pid (\d+) ---').firstMatch(lines[first])?.group(1);
    DateTime? last;
    for (final line in run.toList().reversed) {
      final space = line.indexOf(' ');
      last = DateTime.tryParse(space < 0 ? line : line.substring(0, space));
      if (last != null) break;
    }
    return (pid: pid, last: last);
  }

  String _unannounced(({String? pid, DateTime? last}) run) {
    final crash = switch (run.last) {
      final last? => _crashReport(last),
      null => null,
    };
    return '${_clock().toIso8601String()} [app] the run before'
        '${run.pid == null ? '' : ' (pid ${run.pid})'} ended without saying '
        'how${run.last == null ? '' : ', after ${run.last!.toIso8601String()}'}: '
        '${crash == null ? 'killed (kill -9, out of memory), a crash, or the '
                  'system going down' : 'crash report $crash'}\n';
  }

  String? _crashReport(DateTime since) {
    try {
      return crashSince?.call(since);
    } catch (_) {
      return null;
    }
  }

  void _rollIfFull(int adding) {
    if (_size == 0 || _size + adding <= maxBytes) return;
    final previous = File(previousPath);
    if (previous.existsSync()) previous.deleteSync();
    File(path).renameSync(previousPath);
    _size = 0;
  }

  void _append(String text) {
    File(path).writeAsStringSync(text, mode: FileMode.append, flush: true);
    _size += text.length;
  }
}

/// Writes [message] to [EventLog.current], if there is one.
void appEvent(String category, String message) =>
    EventLog.current?.record(category, message);

/// Writes how the app is ending ([EventLog.exitCategory]): `quit`,
/// `SIGTERM`.
void appExit(String how) => appEvent(EventLog.exitCategory, how);
