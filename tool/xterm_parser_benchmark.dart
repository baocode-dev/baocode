// Throughput micro-benchmark for the ported xterm.js EscapeSequenceParser.
//
// Not part of the test suite. Run with:
//   dart run tool/xterm_parser_benchmark.dart
// or AOT:
//   dart compile exe tool/xterm_parser_benchmark.dart -o /tmp/xterm_parser_bench
//   /tmp/xterm_parser_bench
//
// Feeds a few MB of mixed printable text + SGR/CSI + CR/LF through the parser
// with no-op handlers and reports MB/s (MB = 1e6 bytes of UTF-8 input, i.e.
// what a pty would deliver).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/ide/terminal/xterm/common/input/text_decoder.dart';
import 'package:baocode/ide/terminal/xterm/common/parser/escape_sequence_parser.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm.dart'
    show IFunctionIdentifier;

const int _targetBytes = 4 * 1000 * 1000;
const int _chunkSize = 131072; // xterm.js WriteBuffer chunk size
const int _warmupRounds = 3;
const int _rounds = 10;

// Counters so the handlers are not optimized away.
int _printed = 0;
int _csi = 0;
int _exe = 0;

String _generateInput() {
  const words = <String>[
    'lorem', 'ipsum', 'dolor', 'sit', 'amet', 'consectetur', 'adipiscing', //
    'elit', 'sed', 'do', 'eiusmod', 'tempor', 'incididunt', 'ut', 'labore',
    'build', 'error:', 'warning:', 'src/main.dart:42:7', '0x7fff5fbff8a0',
    'öäü', '€', 'naïve', '日本語',
  ];
  const sgr = <String>[
    '\x1b[0m', '\x1b[1m', '\x1b[31m', '\x1b[1;32m', '\x1b[38;5;208m', //
    '\x1b[38;2;255;128;0m', '\x1b[48;5;236m', '\x1b[4:3m', '\x1b[m',
  ];
  const csi = <String>[
    '\x1b[K', '\x1b[2K', '\x1b[10;20H', '\x1b[?25l', '\x1b[?25h', //
    '\x1b[3A', '\x1b[J',
  ];
  // Deterministic LCG so every run parses the same data.
  var seed = 0x2545F491;
  int next(int n) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % n;
  }

  final sb = StringBuffer();
  var bytes = 0;
  while (bytes < _targetBytes) {
    final line = StringBuffer();
    final wordsInLine = 6 + next(10);
    for (var w = 0; w < wordsInLine; ++w) {
      final r = next(10);
      if (r < 3) {
        line.write(sgr[next(sgr.length)]);
      } else if (r == 3) {
        line.write(csi[next(csi.length)]);
      }
      line.write(words[next(words.length)]);
      line.write(' ');
    }
    line.write('\x1b[0m\r\n');
    final s = line.toString();
    bytes += utf8.encode(s).length;
    sb.write(s);
  }
  return sb.toString();
}

void main() {
  final text = _generateInput();
  final utf8Bytes = utf8.encode(text).length;

  // Decode once up front (not measured), then split into chunks.
  final all = Uint32List(text.length);
  final length = StringToUtf32().decode(text, all);
  final chunks = <Uint32List>[];
  for (var i = 0; i < length; i += _chunkSize) {
    final end = i + _chunkSize < length ? i + _chunkSize : length;
    chunks.add(Uint32List.sublistView(all, i, end));
  }

  final parser = EscapeSequenceParser();
  parser.setPrintHandler((data, start, end) {
    _printed += end - start;
  });
  for (final f in const ['m', 'H', 'K', 'J', 'A', 'h', 'l']) {
    parser.registerCsiHandler(IFunctionIdentifier(final_: f), (params) {
      _csi++;
      return true;
    });
    parser.registerCsiHandler(IFunctionIdentifier(prefix: '?', final_: f), (
      params,
    ) {
      _csi++;
      return true;
    });
  }
  parser.setCsiHandlerFallback((ident, params) {
    _csi++;
  });
  parser.setExecuteHandler('\r', () {
    _exe++;
    return true;
  });
  parser.setExecuteHandler('\n', () {
    _exe++;
    return true;
  });

  double runOnce() {
    final sw = Stopwatch()..start();
    for (final chunk in chunks) {
      parser.parse(chunk, chunk.length);
    }
    sw.stop();
    return sw.elapsedMicroseconds / 1e6;
  }

  for (var i = 0; i < _warmupRounds; ++i) {
    runOnce();
  }
  _printed = 0;
  _csi = 0;
  _exe = 0;

  final times = <double>[];
  for (var i = 0; i < _rounds; ++i) {
    times.add(runOnce());
  }
  times.sort();
  final best = times.first;
  final median = times[times.length ~/ 2];
  final mb = utf8Bytes / 1e6;

  stdout.writeln(
    'input: ${mb.toStringAsFixed(2)} MB UTF-8, $length codepoints, '
    '${chunks.length} chunks of <= $_chunkSize',
  );
  stdout.writeln(
    'per round: ${_printed ~/ _rounds} printed, ${_csi ~/ _rounds} CSI, '
    '${_exe ~/ _rounds} EXE',
  );
  stdout.writeln(
    'rounds: $_rounds (after $_warmupRounds warmup); '
    'median ${(median * 1000).toStringAsFixed(1)} ms, '
    'best ${(best * 1000).toStringAsFixed(1)} ms',
  );
  stdout.writeln(
    'throughput: median ${(mb / median).toStringAsFixed(1)} MB/s, '
    'best ${(mb / best).toStringAsFixed(1)} MB/s',
  );
}
