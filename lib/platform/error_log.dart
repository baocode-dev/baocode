import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../update/version.dart';

/// What went wrong in the app unseen, kept in the data folder's
/// `logs/errors.log` (`DataDirectory.logsDir`) for a user to send: a
/// release build shows nothing of an error — a widget that fails to build
/// is a grey box, a frame that fails to lay out or paint a window that
/// stops moving.
///
/// A run's first entry follows a line naming the app's version and the
/// system. An error that comes again and again (every frame) is written
/// [repeatsInFull] times, then counted at each power of ten. A file grown
/// past [maxBytes] becomes `errors.1.log` as the next run first writes,
/// and no run writes more than that.
class ErrorLog {
  ErrorLog(
    this.directory, {
    this.maxBytes = 1024 * 1024,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// The folder of the log files.
  final String directory;

  final int maxBytes;

  /// How many times the same error is written whole.
  static const repeatsInFull = 3;

  /// The most of a stack written: a build's recursion runs to hundreds.
  static const maxStackLines = 80;

  final DateTime Function() _clock;

  String get path => p.join(directory, 'errors.log');

  /// The file of a run before, moved aside.
  String get previousPath => p.join(directory, 'errors.1.log');

  /// How many times each error came this run, by what tells it apart.
  final Map<String, int> _counts = {};
  int _written = 0;
  bool _started = false;
  bool _full = false;

  /// Writes what [FlutterError.onError] and [PlatformDispatcher.onError]
  /// are told, then hands it on to the handlers they had.
  void install() {
    final flutter = FlutterError.onError;
    FlutterError.onError = (details) {
      recordFlutterError(details);
      flutter?.call(details);
    };
    final platform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack, source: 'uncaught');
      return platform?.call(error, stack) ?? false;
    };
  }

  /// An error the framework caught: in a build, a layout, a paint, a
  /// gesture's handler.
  void recordFlutterError(FlutterErrorDetails details) => record(
    details.exception,
    details.stack,
    source: details.library ?? 'Flutter',
    context: details.context?.toDescription(),
  );

  void record(
    Object error,
    StackTrace? stack, {
    required String source,
    String? context,
  }) {
    try {
      _record(error, stack, source: source, context: context);
    } catch (_) {
      // The log is no reason to fail: a disk full, a folder gone.
    }
  }

  void _record(
    Object error,
    StackTrace? stack, {
    required String source,
    String? context,
  }) {
    if (_full) return;
    final message = '$error';
    final key = '$source\n$context\n$message';
    final count = _counts[key] = (_counts[key] ?? 0) + 1;
    final String entry;
    if (count <= repeatsInFull) {
      final lines = [
        for (final line in '${stack ?? ''}'.trimRight().split('\n'))
          if (line.isNotEmpty) line,
      ];
      final parts = [
        '${_clock().toIso8601String()} [$source]'
            '${context == null || context.isEmpty ? '' : ' $context'}',
        message,
        ...lines.take(maxStackLines),
        if (lines.length > maxStackLines)
          '… ${lines.length - maxStackLines} more frames',
      ];
      entry = '${parts.join('\n')}\n\n';
    } else if (_isPowerOfTen(count)) {
      entry =
          '${_clock().toIso8601String()} [$source] the same again, '
          '$count times: ${message.split('\n').first}\n\n';
    } else {
      return;
    }
    _write(entry);
  }

  void _write(String entry) {
    if (!_started) {
      _started = true;
      Directory(directory).createSync(recursive: true);
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > maxBytes) {
        final previous = File(previousPath);
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previousPath);
      }
      _append(
        '--- BaoCode $appVersionString · ${Platform.operatingSystem} '
        '${Platform.operatingSystemVersion} · '
        '${_clock().toIso8601String()} ---\n',
      );
    }
    if (_written + entry.length > maxBytes) {
      _full = true;
      _append('(No more this run: the log reached $maxBytes bytes.)\n');
      return;
    }
    _append(entry);
  }

  void _append(String text) {
    File(path).writeAsStringSync(text, mode: FileMode.append, flush: true);
    _written += text.length;
  }

  static bool _isPowerOfTen(int n) {
    while (n % 10 == 0) {
      n ~/= 10;
    }
    return n == 1;
  }
}
