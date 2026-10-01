/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/test/browser/
// linkTestUtils.ts (helpers, not a test). An expected link is a record,
// `(uri: ..., range: ...)` or `(text: ..., range: ...)`. As upstream, the
// links' types are not compared (both sides take [expectedType]).
//
// Also the tests' fakes: VS Code's `URI.file` on a POSIX host, and a stat
// function over a list of files (upstream's stubbed file service).

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/links/links.dart';
import 'package:baocode/ide/terminal/links/terminal_link_parsing.dart';
import 'package:baocode/ide/terminal/links/terminal_link_resolver.dart';
import 'package:baocode/ide/terminal/xterm/typings/xterm_headless.dart';

Future<void> assertLinkHelper(
  String text,
  List<Record> expected,
  ITerminalLinkDetector detector,
  TerminalBuiltinLinkType expectedType,
) async {
  detector.xterm.reset();

  // Write the text and wait for the parser to finish
  final written = Completer<void>();
  detector.xterm.write(text, written.complete);
  await written.future;
  final textSplit = text.split('\r\n');
  final lastLineIndex = textSplit
      .take(textSplit.length - 1)
      .fold(0, (p, c) => p + math.max((c.length / 80).ceil(), 1));

  // Ensure all links are provided
  final lines = <IBufferLine>[];
  for (var i = 0; i < detector.xterm.buffer.active.cursorY + 1; i++) {
    lines.add(detector.xterm.buffer.active.getLine(i)!);
  }

  // Detect links always on the last line with content
  final actualLinks = [
    for (final e in await detector.detect(
      lines,
      lastLineIndex,
      detector.xterm.buffer.active.cursorY,
    ))
      (
        link: e.uri?.toString() ?? e.text,
        type: expectedType,
        bufferRange: e.bufferRange,
      ),
  ];
  final expectedLinks = [
    for (final e in expected)
      switch (e) {
        (:final Uri uri, :final List<List<int>> range) => (
          type: expectedType,
          link: uri.toString(),
          bufferRange: _range(range),
        ),
        (:final String text, :final List<List<int>> range) => (
          type: expectedType,
          link: text,
          bufferRange: _range(range),
        ),
        _ => throw ArgumentError.value(e, 'expected'),
      },
  ];
  expect(actualLinks, expectedLinks);
}

IBufferRange _range(List<List<int>> range) => IBufferRange(
  start: IBufferCellPosition(x: range[0][0], y: range[0][1]),
  end: IBufferCellPosition(x: range[1][0], y: range[1][1]),
);

/// VS Code's `URI.file` on macOS or Linux: the path, made absolute.
Uri uriFile(String path) =>
    Uri(scheme: 'file', path: path.startsWith('/') ? path : '/$path');

/// A stat function where the files of [files] exist (all of them while it
/// returns null), none of them a folder; paths compare with [os]' syntax.
TerminalLinkStat fakeStat(List<Uri>? Function() files, OperatingSystem os) {
  final osPath = osPathContext(os);
  return (path) async {
    final list = files();
    if (list == null ||
        list.any((e) => osPath.equals(fileUriToPath(e, os) ?? '', path))) {
      return false;
    }
    return null;
  };
}

/// Upstream's `strings.format`: `{n}` is the n-th argument.
String format(String value, List<Object?> args) {
  return value.replaceAllMapped(RegExp(r'\{(\d+)\}'), (match) {
    final idx = int.parse(match[1]!);
    return idx < 0 || idx >= args.length ? match[0]! : '${args[idx]}';
  });
}
