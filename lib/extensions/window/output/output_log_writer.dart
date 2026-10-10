/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/platform/log/common/fileLog.ts (`FileLogger`: the line format,
// buffering for 100 ms, a file past 5 MB moved to `<name>_<1..5>`),
// src/vs/platform/log/common/log.ts (`AbstractMessageLogger.checkLogLevel`,
// `log()`).
//
// Deviations: appends to the file instead of rewriting it whole (the
// output panel then reads only what is new); the backup is the file
// renamed.

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../host/init_data.dart' show ExtHostLogLevel;

/// A logger the extension host creates on the main thread
/// (`$createLogger` for a resource it cannot write itself): writes
/// upstream's log lines to [path].
final class OutputLogWriter {
  OutputLogWriter(
    this.path, {
    required this.level,
    this.always = false,
    this.donotUseFormatters = false,
    this.maxFileBytes = 5 * 1024 * 1024,
    this.flushDelay = const Duration(milliseconds: 100),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String path;

  /// Below it nothing is written (`Off`: nothing at all) unless [always].
  ExtHostLogLevel level;

  /// `logLevel: 'always'`: every message is written.
  final bool always;

  /// Messages written as they are (an output channel's), not as lines with
  /// a time and a level.
  final bool donotUseFormatters;
  final int maxFileBytes;
  final Duration flushDelay;
  final DateTime Function() _clock;

  final _buffer = StringBuffer();
  Timer? _timer;
  Future<void> _writing = Future.value();
  int _backupIndex = 1;
  bool _disposed = false;

  bool _canLog(ExtHostLogLevel at) =>
      always || (level != ExtHostLogLevel.off && level.index <= at.index);

  /// `log(logger, level, message)`: nothing for `Off`.
  void log(ExtHostLogLevel at, String message) {
    if (_disposed || at == ExtHostLogLevel.off || !_canLog(at)) return;
    if (donotUseFormatters) {
      _buffer.write(message);
    } else {
      _buffer.write('${_timestamp()} [${_levelName(at)}] $message\n');
    }
    _timer ??= Timer(flushDelay, () => unawaited(flush()));
  }

  /// Writes what is buffered.
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) return _writing;
    final text = _buffer.toString();
    _buffer.clear();
    return _writing = _writing.then((_) => _append(text));
  }

  Future<void> _append(String text) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        if (await file.length() > maxFileBytes) {
          _backupIndex = _backupIndex > 5 ? 1 : _backupIndex;
          final backup = p.join(
            p.dirname(path),
            '${p.basename(path)}_${_backupIndex++}',
          );
          await file.rename(backup);
        }
      } else {
        await file.parent.create(recursive: true);
      }
      await File(path).writeAsString(text, mode: FileMode.append, flush: true);
    } on FileSystemException {
      // A logs folder deleted under it: the messages are lost, as upstream
      // loses them.
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await flush();
    _disposed = true;
  }

  String _timestamp() {
    final t = _clock();
    String two(int v) => v.toString().padLeft(2, '0');
    String three(int v) => v.toString().padLeft(3, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}'
        '.${three(t.millisecond)}';
  }

  static String _levelName(ExtHostLogLevel level) => switch (level) {
    ExtHostLogLevel.trace => 'trace',
    ExtHostLogLevel.debug => 'debug',
    ExtHostLogLevel.info => 'info',
    ExtHostLogLevel.warning => 'warning',
    ExtHostLogLevel.error => 'error',
    ExtHostLogLevel.off => '',
  };
}
