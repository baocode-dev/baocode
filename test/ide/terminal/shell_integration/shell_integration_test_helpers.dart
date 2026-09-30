/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the shell integration tests share: a terminal, and writing to it.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/terminalTestHelpers.ts
// (`writeP`) and src/vs/platform/terminal/test/common/terminalTestHelpers.ts
// (`TestXtermLogger`).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/headless/terminal.dart';
import 'package:monad/ide/terminal/xterm/typings/xterm_headless.dart'
    hide Terminal;

/// Writes [data] and waits for it to be parsed.
Future<void> writeP(Terminal terminal, String data) {
  final completer = Completer<void>();
  final failTimeout = Timer(const Duration(seconds: 2), () {
    if (!completer.isCompleted) {
      completer.completeError(
        'Writing to xterm is taking longer than 2 seconds',
      );
    }
  });
  terminal.write(data, () {
    failTimeout.cancel();
    if (!completer.isCompleted) completer.complete();
  });
  return completer.future;
}

/// A logger for xterm.js that suppresses noisy warnings during tests.
class TestXtermLogger implements ILogger {
  @override
  void trace(String message, [List<Object?> args = const []]) {}
  @override
  void debug(String message, [List<Object?> args = const []]) {}
  @override
  void info(String message, [List<Object?> args = const []]) {}
  @override
  void warn(String message, [List<Object?> args = const []]) {
    if (message.contains('task queue')) {
      return;
    }
    printOnFailure('warn: $message $args');
  }

  @override
  void error(Object message, [List<Object?> args = const []]) {
    printOnFailure('error: $message $args');
  }
}

/// Upstream's `new Terminal({ allowProposedApi: true, cols, rows, logger:
/// TestXtermLogger })`, the ported core's internal terminal; disposed after
/// the test.
Terminal createTestTerminal({int cols = 80, int rows = 24}) {
  final terminal = Terminal(
    ITerminalOptions(
      allowProposedApi: true,
      cols: cols,
      rows: rows,
      logger: TestXtermLogger(),
    ),
  );
  addTearDown(terminal.dispose);
  return terminal;
}
