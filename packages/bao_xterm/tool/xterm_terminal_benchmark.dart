// Whole-terminal throughput benchmark for the ported xterm.js headless
// Terminal (parser, input handler, buffer, scrollback, write buffer).
//
// Not part of the test suite. Run from the repository root with:
//   dart run tool/xterm_terminal_benchmark.dart
// or AOT:
//   dart compile exe tool/xterm_terminal_benchmark.dart -o /tmp/xterm_terminal_bench
//   /tmp/xterm_terminal_bench
//
// Like upstream's test/benchmark/Terminal.benchmark.ts (write/string and
// write/utf8), but with generated output instead of `ls -lR /usr/lib`, and
// written in pty-sized chunks: a terminal of 120x40 with 1000 lines of
// scrollback receives a few MB of `ls -la --color` listings, a `cat` of this
// port's Dart sources, SGR-heavy highlighted lines and cursor movement
// (progress bars, multi-line status redraws, a full-screen TUI in the
// alternate buffer, scroll regions). MB = 1e6 bytes of UTF-8 input, what a
// pty delivers.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bao_xterm/headless/public/terminal.dart';
import 'package:bao_xterm/typings/xterm_headless.dart' hide Terminal;

const int _cols = 120;
const int _rows = 40;
const int _scrollback = 1000;
const int _partBytes = 1200 * 1000; // per workload
const int _chunkSize = 16384; // a typical pty read
const int _warmupRounds = 2;
const int _rounds = 7;

/// Deterministic LCG so every run writes the same data.
class _Random {
  int _seed = 0x2545F491;

  int next(int n) {
    _seed = (_seed * 1103515245 + 12345) & 0x7fffffff;
    return _seed % n;
  }

  T pick<T>(List<T> list) => list[next(list.length)];
}

final _Random _rnd = _Random();

int _utf8Length(String s) => utf8.encode(s).length;

/// Lines (or blocks) from [line] until they hold [bytes] UTF-8 bytes.
List<String> _fill(int bytes, String Function() line) {
  final units = <String>[];
  var n = 0;
  while (n < bytes) {
    final s = line();
    n += _utf8Length(s);
    units.add(s);
  }
  return units;
}

const List<String> _nameParts = [
  'src', 'lib', 'test', 'build', 'terminal', 'buffer', 'parser', 'input', //
  'handler', 'service', 'options', 'core', 'render', 'widget', 'main', 'util',
  'config', 'README', 'CHANGELOG', 'package', 'index', 'node_modules', 'dist',
  'ünïcödé', '日本語', 'data',
];
const List<String> _extensions = [
  '.dart',
  '.ts',
  '.js',
  '.json',
  '.md',
  '.yaml',
  '.lock',
  '.png',
  '.sh',
  '',
];

String _name(int maxParts) {
  final parts = 1 + _rnd.next(maxParts);
  return [for (var i = 0; i < parts; i++) _rnd.pick(_nameParts)]
      .join(_rnd.next(2) == 0 ? '_' : '-');
}

/// `ls -la --color=auto`, some names long enough to wrap.
String _lsLine() {
  final kind = _rnd.next(10);
  final dir = kind < 3;
  final link = kind == 3;
  final exe = kind == 4;
  final perms = dir
      ? 'drwxr-xr-x'
      : link
      ? 'lrwxr-xr-x'
      : exe
      ? '-rwxr-xr-x'
      : '-rw-r--r--';
  final links = (1 + _rnd.next(40)).toString().padLeft(3);
  final size = _rnd.next(2000000).toString().padLeft(9);
  final day = (1 + _rnd.next(30)).toString().padLeft(2);
  final time =
      '${_rnd.next(24).toString().padLeft(2, '0')}:'
      '${_rnd.next(60).toString().padLeft(2, '0')}';
  final name = _name(_rnd.next(20) == 0 ? 14 : 4);
  final String colored;
  if (dir) {
    colored = '\x1b[1;34m$name\x1b[0m';
  } else if (link) {
    colored = '\x1b[1;36m$name\x1b[0m -> ../${_name(3)}';
  } else if (exe) {
    colored = '\x1b[1;32m$name.sh\x1b[0m';
  } else {
    colored = '$name${_rnd.pick(_extensions)}';
  }
  return '$perms $links leokun  staff $size Sep $day $time $colored\r\n';
}

/// `cat` of Dart sources: plain text, tabs and CRLF (onlcr); one unit per
/// line.
List<String> _catText() {
  final dir = Directory('lib');
  if (!dir.existsSync()) {
    stderr.writeln('Run from the repository root (needs $dir).');
    exit(2);
  }
  final files =
      dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  final lines = [
    for (final f in files)
      for (final l in f.readAsStringSync().split('\n'))
        '${l.endsWith('\r') ? l.substring(0, l.length - 1) : l}\r\n',
  ];
  var i = 0;
  return _fill(_partBytes, () => lines[i++ % lines.length]);
}

const List<String> _words = [
  'final', 'class', 'return', 'await', 'Future<void>', 'const', 'import', //
  'buffer', 'lines', 'cursorX', '0x1b', "'\\r\\n'", '=>', '{', '}', '(', ')',
  'error:', 'warning:', 'src/main.dart:42:7', 'naïve', '€', '日本語', '✓',
];
const List<String> _sgr = [
  '\x1b[0m', '\x1b[1m', '\x1b[3m', '\x1b[4m', '\x1b[31m', '\x1b[1;32m', //
  '\x1b[33;44m', '\x1b[38;5;208m', '\x1b[48;5;236m', '\x1b[38;2;255;128;0m',
  '\x1b[48;2;30;30;46m', '\x1b[4:3m', '\x1b[58;5;196m', '\x1b[2;9m', '\x1b[m',
  '\x1b[7m', '\x1b[27m', '\x1b[39;49m',
];

/// Syntax-highlighted or diagnostic output: an SGR before most tokens.
String _sgrLine() {
  final sb = StringBuffer();
  final lineNo = _rnd.next(9999).toString().padLeft(5);
  sb.write('\x1b[38;5;242m$lineNo \x1b[0m│ ');
  var width = 8;
  final target = 40 + _rnd.next(75);
  while (width < target) {
    sb.write(_rnd.pick(_sgr));
    if (_rnd.next(3) == 0) {
      sb.write(_rnd.pick(_sgr));
    }
    final w = _rnd.pick(_words);
    sb.write(w);
    sb.write(' ');
    width += w.length + 1;
  }
  sb.write('\x1b[0m\r\n');
  return sb.toString();
}

/// Progress bars, multi-line status redraws, a full-screen TUI frame in the
/// alternate buffer, and scrolling in a scroll region.
String _cursorBlock() {
  final sb = StringBuffer();
  switch (_rnd.next(4)) {
    case 0:
      // Single-line progress bar redrawn with CR and EL.
      for (var p = 0; p <= 100; p += 2) {
        final done = p * 50 ~/ 100;
        sb.write(
          '\r\x1b[K\x1b[32m${'█' * done}\x1b[90m${'░' * (50 - done)}\x1b[0m '
          '${p.toString().padLeft(3)}% ${_name(2)}',
        );
      }
      sb.write('\r\n');
    case 1:
      // cargo/npm style: three status lines rewritten in place.
      sb.write('\r\n\r\n\r\n');
      for (var i = 0; i < 30; i++) {
        sb.write('\x1b[3A');
        for (var l = 0; l < 3; l++) {
          sb.write(
            '\r\x1b[2K\x1b[1;36m${'Compiling'.padLeft(12)}\x1b[0m '
            '${_name(3)} v0.$i.$l\r\n',
          );
        }
      }
    case 2:
      // A top/htop-like frame in the alternate buffer.
      sb.write('\x1b[?1049h\x1b[?25l\x1b[H\x1b[2J');
      for (var frame = 0; frame < 3; frame++) {
        sb.write('\x1b[H\x1b[7m PID USER      %CPU %MEM COMMAND');
        sb.write('${' ' * 85}\x1b[0m');
        for (var r = 2; r <= _rows; r++) {
          sb.write('\x1b[$r;1H');
          sb.write(
            '${_rnd.next(99999).toString().padLeft(5)} leokun   '
            '\x1b[${_rnd.next(2) == 0 ? 32 : 31}m'
            '${(_rnd.next(1000) / 10).toStringAsFixed(1).padLeft(5)}\x1b[0m '
            '${(_rnd.next(1000) / 10).toStringAsFixed(1).padLeft(4)} '
            '${_name(3)}\x1b[K',
          );
        }
      }
      sb.write('\x1b[?25h\x1b[?1049l');
    case 3:
      // less/vim-like scrolling inside a scroll region, with IL/DL.
      sb.write('\x1b[2;${_rows - 1}r\x1b[${_rows - 1};1H');
      for (var i = 0; i < 20; i++) {
        sb.write('\n\r\x1b[K${_rnd.pick(_words)} ${_name(4)} $i');
      }
      sb.write('\x1b[5;1H\x1b[3L\x1b[10;1H\x1b[2M');
      sb.write('\x1b[r\x1b[$_rows;1H\r\n');
  }
  return sb.toString();
}

Future<void> _writeAll(Terminal term, List<Object> chunks) {
  final c = Completer<void>();
  for (var i = 0; i < chunks.length - 1; i++) {
    term.write(chunks[i]);
  }
  term.write(chunks.last, c.complete);
  return c.future;
}

List<String> _stringChunks(String s) => [
  for (var i = 0; i < s.length; i += _chunkSize)
    s.substring(i, i + _chunkSize < s.length ? i + _chunkSize : s.length),
];

List<Uint8List> _byteChunks(Uint8List b) => [
  for (var i = 0; i < b.length; i += _chunkSize)
    Uint8List.sublistView(
      b,
      i,
      i + _chunkSize < b.length ? i + _chunkSize : b.length,
    ),
];

Future<({double median, double best})> _measure(
  List<Object> chunks,
  int bytes,
) async {
  final term = Terminal(
    ITerminalOptions(cols: _cols, rows: _rows, scrollback: _scrollback),
  );
  final times = <double>[];
  for (var i = 0; i < _warmupRounds + _rounds; i++) {
    final sw = Stopwatch()..start();
    await _writeAll(term, chunks);
    sw.stop();
    if (i >= _warmupRounds) {
      times.add(sw.elapsedMicroseconds / 1e6);
    }
  }
  if (term.buffer.active.length != _rows + _scrollback) {
    throw StateError('unexpected buffer length ${term.buffer.active.length}');
  }
  term.dispose();
  times.sort();
  final mb = bytes / 1e6;
  return (median: mb / times[times.length ~/ 2], best: mb / times.first);
}

Future<void> main() async {
  final units = <String, List<String>>{
    'ls -la --color': _fill(_partBytes, _lsLine),
    'cat *.dart': _catText(),
    'SGR-heavy': _fill(_partBytes, _sgrLine),
    'cursor movement': _fill(_partBytes, _cursorBlock),
  };
  final parts = {for (final e in units.entries) e.key: e.value.join()};
  // The mix interleaves about a chunk of whole lines (or blocks) of each part
  // at a time, as a session would; cutting anywhere else would break escape
  // sequences.
  final mixed = StringBuffer();
  final next = List<int>.filled(units.length, 0);
  final lists = units.values.toList();
  while (Iterable<int>.generate(lists.length)
      .any((p) => next[p] < lists[p].length)) {
    for (var p = 0; p < lists.length; p++) {
      for (var n = 0; n < _chunkSize && next[p] < lists[p].length;) {
        final unit = lists[p][next[p]++];
        mixed.write(unit);
        n += unit.length;
      }
    }
  }
  parts['mixed (all of the above)'] = mixed.toString();

  stdout.writeln(
    'headless Terminal ${_cols}x$_rows, scrollback $_scrollback; '
    'writes of $_chunkSize-unit chunks; '
    '$_rounds rounds after $_warmupRounds warmup; MB/s median (best)',
  );
  for (final entry in parts.entries) {
    final bytes = utf8.encode(entry.value);
    final s = await _measure(_stringChunks(entry.value), bytes.length);
    final u = await _measure(_byteChunks(bytes), bytes.length);
    stdout.writeln(
      '${entry.key.padRight(26)} ${(bytes.length / 1e6).toStringAsFixed(2)} MB'
      '  string ${s.median.toStringAsFixed(1).padLeft(6)} '
      '(${s.best.toStringAsFixed(1)})'
      '  utf8 ${u.median.toStringAsFixed(1).padLeft(6)} '
      '(${u.best.toStringAsFixed(1)})',
    );
  }
}
