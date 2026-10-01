/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/capabilities/
// partialCommandDetectionCapability.test.ts, on the ported core's internal
// terminal.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/partial_command_detection_capability.dart';
import 'package:bao_xterm/common/buffer/types.dart';
import 'package:bao_xterm/common/event.dart';
import 'package:bao_xterm/headless/terminal.dart';

import '../shell_integration_test_helpers.dart';

void main() {
  late Terminal xterm;
  late PartialCommandDetectionCapability capability;
  late List<IMarker> addEvents;
  late Emitter<void> onDidExecuteTextEmitter;

  void assertCommands(List<int> expectedLines) {
    expect(capability.commands.map((e) => e.line), expectedLines);
    expect(addEvents.map((e) => e.line), expectedLines);
  }

  setUp(() {
    xterm = createTestTerminal(cols: 80);
    onDidExecuteTextEmitter = Emitter<void>();
    capability = PartialCommandDetectionCapability(
      xterm,
      onDidExecuteTextEmitter.event,
    );
    addTearDown(capability.dispose);
    addTearDown(onDidExecuteTextEmitter.dispose);
    addEvents = [];
    capability.onCommandFinished(addEvents.add);
  });

  test('should not add commands when the cursor position is too close to the left side', () async {
    assertCommands([]);
    xterm.input('\x0d');
    await writeP(xterm, '\r\n');
    assertCommands([]);
    await writeP(xterm, 'a');
    xterm.input('\x0d');
    await writeP(xterm, '\r\n');
    assertCommands([]);
  });

  test('should add commands when the cursor position is not too close to the left side', () async {
    assertCommands([]);
    await writeP(xterm, 'ab');
    xterm.input('\x0d');
    await writeP(xterm, '\r\n\r\n');
    assertCommands([0]);
    await writeP(xterm, 'cd');
    xterm.input('\x0d');
    await writeP(xterm, '\r\n');
    assertCommands([0, 2]);
  });

  test('onDidExecuteText should cause onDidCommandFinished to fire', () async {
    await writeP(xterm, 'cd');
    onDidExecuteTextEmitter.fire(null);
    await writeP(xterm, 'pwd');
    onDidExecuteTextEmitter.fire(null);
    expect(addEvents.length, 2);
  });

  // New: not upstream.
  test('clearing the screen drops the commands in the viewport', () async {
    await writeP(xterm, 'ab');
    xterm.input('\x0d');
    await writeP(xterm, '\r\ncd');
    xterm.input('\x0d');
    expect(capability.commands.map((e) => e.line), [0, 1]);
    await writeP(xterm, '\x1b[2J');
    expect(capability.commands, isEmpty);
  });
}
