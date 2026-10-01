/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/capabilities/
// commandDetectionCapability.test.ts, on the ported core's internal
// terminal. Upstream clears the capability's commands after each
// assertion (through a subclass); here the assertions skip those already
// asserted.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection/terminal_command.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection_capability.dart';
import 'package:bao_xterm/headless/terminal.dart';

import '../shell_integration_test_helpers.dart';

typedef _Match = ({String command, String? cwd, int? exitCode, int line});

void main() {
  late Terminal xterm;
  late CommandDetectionCapability capability;
  late List<ITerminalCommand> addEvents;
  var asserted = 0;

  void assertCommands(List<_Match> expectedCommands) {
    final commands = capability.commands.skip(asserted).toList();
    expect(
      commands.map((e) => e.command),
      expectedCommands.map((e) => e.command),
    );
    expect(commands.map((e) => e.cwd), expectedCommands.map((e) => e.cwd));
    expect(
      commands.map((e) => e.exitCode),
      expectedCommands.map((e) => e.exitCode),
    );
    expect(
      commands.map((e) => e.marker?.line),
      expectedCommands.map((e) => e.line),
    );
    // Ensure timestamps are set and were captured recently
    for (final command in commands) {
      expect(
        (DateTime.now().millisecondsSinceEpoch - command.timestamp).abs(),
        lessThan(2000),
      );
      expect(
        command.id,
        isNotNull,
        reason: 'Expected command to have an assigned id',
      );
    }
    expect(addEvents, commands);
    // Clear the commands to avoid re-asserting past commands
    addEvents.clear();
    asserted = capability.commands.length;
  }

  Future<void> printStandardCommand(
    String prompt,
    String command,
    String output,
    String? cwd,
    int exitCode,
  ) async {
    if (cwd != null) {
      capability.setCwd(cwd);
    }
    capability.handlePromptStart();
    await writeP(xterm, '\r$prompt');
    capability.handleCommandStart();
    await writeP(xterm, command);
    capability.handleCommandExecuted();
    await writeP(xterm, '\r\n$output\r\n');
    capability.handleCommandFinished(exitCode);
  }

  Future<void> printCommandStart(String prompt) async {
    capability.handlePromptStart();
    await writeP(xterm, '\r$prompt');
    capability.handleCommandStart();
  }

  setUp(() {
    xterm = createTestTerminal(cols: 80);
    capability = CommandDetectionCapability(xterm, xterm.logService);
    addTearDown(capability.dispose);
    addEvents = [];
    asserted = 0;
    capability.onCommandFinished(addEvents.add);
    assertCommands([]);
  });

  test(
    'should not add commands when no capability methods are triggered',
    () async {
      await writeP(xterm, 'foo\r\nbar\r\n');
      assertCommands([]);
      await writeP(xterm, 'baz\r\n');
      assertCommands([]);
    },
  );

  test('should add commands for expected capability method calls', () async {
    await printStandardCommand(r'$ ', 'echo foo', 'foo', null, 0);
    await printCommandStart(r'$ ');
    assertCommands([(command: 'echo foo', exitCode: 0, cwd: null, line: 0)]);
  });

  test('should trim the command when command executed appears on the following line', () async {
    await printStandardCommand(r'$ ', 'echo foo\r\n', 'foo', null, 0);
    await printCommandStart(r'$ ');
    assertCommands([(command: 'echo foo', exitCode: 0, cwd: null, line: 0)]);
  });

  group('cwd', () {
    test('should add cwd to commands when it\'s set', () async {
      await printStandardCommand(r'$ ', 'echo foo', 'foo', '/home', 0);
      await printStandardCommand(r'$ ', 'echo bar', 'bar', '/home/second', 0);
      await printCommandStart(r'$ ');
      assertCommands([
        (command: 'echo foo', exitCode: 0, cwd: '/home', line: 0),
        (command: 'echo bar', exitCode: 0, cwd: '/home/second', line: 2),
      ]);
    });
    test(
      'should add old cwd to commands if no cwd sequence is output',
      () async {
        await printStandardCommand(r'$ ', 'echo foo', 'foo', '/home', 0);
        await printStandardCommand(r'$ ', 'echo bar', 'bar', null, 0);
        await printCommandStart(r'$ ');
        assertCommands([
          (command: 'echo foo', exitCode: 0, cwd: '/home', line: 0),
          (command: 'echo bar', exitCode: 0, cwd: '/home', line: 2),
        ]);
      },
    );
    test('should use an undefined cwd if it\'s not set initially', () async {
      await printStandardCommand(r'$ ', 'echo foo', 'foo', null, 0);
      await printStandardCommand(r'$ ', 'echo bar', 'bar', '/home', 0);
      await printCommandStart(r'$ ');
      assertCommands([
        (command: 'echo foo', exitCode: 0, cwd: null, line: 0),
        (command: 'echo bar', exitCode: 0, cwd: '/home', line: 2),
      ]);
    });
  });

  test('should not inherit the previous exit code when a duplicate command is interrupted', () async {
    await printStandardCommand(r'$ ', 'echo test', 'test', null, 0);

    capability.handlePromptStart();
    await writeP(xterm, '\r\$ ');
    capability.handleCommandStart();
    await writeP(xterm, 'echo test');
    xterm.input('\x03');
    await writeP(xterm, '^C');
    capability.setCommandLine('echo test', true);
    capability.handleCommandExecuted();
    await writeP(xterm, '\r\n');
    capability.handleCommandFinished(null);

    await printCommandStart(r'$ ');

    assertCommands([
      (command: 'echo test', exitCode: 0, cwd: null, line: 0),
      (command: 'echo test', exitCode: null, cwd: null, line: 2),
    ]);
  });

  test('should inherit the previous exit code for duplicate commands without interruption', () async {
    await printStandardCommand(r'$ ', 'echo ^C', 'test', null, 0);

    capability.handlePromptStart();
    await writeP(xterm, '\r\$ ');
    capability.handleCommandStart();
    await writeP(xterm, 'echo ^C');
    capability.setCommandLine('echo ^C', true);
    capability.handleCommandExecuted();
    await writeP(xterm, '\r\ntest\r\n');
    capability.handleCommandFinished(null);

    await printCommandStart(r'$ ');

    assertCommands([
      (command: 'echo ^C', exitCode: 0, cwd: null, line: 0),
      (command: 'echo ^C', exitCode: 0, cwd: null, line: 2),
    ]);
  });

  test('should preserve explicit newlines at 80-column wrap boundaries in command output', () async {
    final boundaryWidthLine = 'A' * 80;
    await printStandardCommand(
      r'$ ',
      'cat content.txt',
      '$boundaryWidthLine\r\nafter',
      null,
      0,
    );
    await printCommandStart(r'$ ');

    expect(capability.commands.length, 1);
    final output = capability.commands[0].getOutput();
    expect(output, isNotNull);
    expect(output, contains('$boundaryWidthLine\nafter\n'));
    expect(output, isNot(contains('${boundaryWidthLine}after')));
  });

  // New: not upstream.
  group('New', () {
    test('commands know their markers, output and rows', () async {
      await printStandardCommand(r'$ ', 'ls', 'a\r\nb', '/tmp', 2);
      await printCommandStart(r'$ ');
      final command = capability.commands.single;
      expect(command.promptStartMarker!.line, 0);
      expect(command.marker!.line, 0);
      // Executed before the command's line feed, as the shell sends it.
      expect(command.executedMarker!.line, 0);
      expect(command.executedX, 4);
      expect(command.endMarker!.line, 3);
      expect(command.startX, 2);
      expect(command.getOutput(), '\$ ls\na\nb\n');
      expect(command.hasOutput(), isTrue);
      expect(command.getPromptRowCount(), 1);
      expect(command.getCommandRowCount(), 1);
      expect(command.extractCommandLine(), 'ls');
      // Pulled from the buffer: medium confidence.
      expect(command.commandLineConfidence, 'medium');
      final match = command.getOutputMatch(
        ITerminalOutputMatcher(
          lineMatcher: RegExp('b'),
          anchor: 'bottom',
          length: 2,
        ),
      );
      expect(match?.regexMatch[0], 'b');
      // From the end marker's line (the next prompt's) up.
      expect(match?.outputLines, ['b', r'$ ']);
      expect(capability.getCommandForLine(1), same(command));
      expect(capability.getCwdForLine(1), '/tmp');
      expect(capability.getCommandForLine(3), same(capability.currentCommand));
    });

    test(
      'a command line set with a nonce is trusted, high confidence',
      () async {
        capability.handlePromptStart();
        await writeP(xterm, '\r\$ ');
        capability.handleCommandStart();
        await writeP(xterm, 'echo hi');
        capability.setCommandLine('echo hi', true);
        capability.handleCommandExecuted();
        await writeP(xterm, '\r\nhi\r\n');
        capability.handleCommandFinished(0);
        final command = capability.commands.single;
        expect(command.command, 'echo hi');
        expect(command.isTrusted, isTrue);
        expect(command.commandLineConfidence, 'high');
      },
    );

    test('started and executed events', () async {
      final started = <ITerminalCommand>[];
      final executed = <PartialTerminalCommand>[];
      capability.onCommandStarted(started.add);
      capability.onCommandExecuted(executed.add);
      await printStandardCommand(r'$ ', 'pwd', '/', null, 0);
      expect(started.single.marker!.line, 0);
      expect(started.single.exitCode, isNull);
      expect(executed.single.command, 'pwd');
      expect(capability.executingCommand, isNull);
    });

    test('ED 2 invalidates the commands in the viewport', () async {
      final invalidated = <List<ITerminalCommand>>[];
      capability.onCommandInvalidated(invalidated.add);
      await printStandardCommand(r'$ ', 'ls', 'a', null, 0);
      await printCommandStart(r'$ ');
      await writeP(xterm, '\x1b[2J');
      expect(invalidated.single.single.command, 'ls');
      expect(capability.commands, isEmpty);
      expect(capability.currentCommand.wasCleared, isTrue);
    });

    test('serializes and deserializes the commands', () async {
      await printStandardCommand(r'$ ', 'echo foo', 'foo', '/home', 0);
      await printCommandStart(r'$ ');
      final serialized = capability.serialize();
      expect(serialized.commands.map((e) => e.command), ['echo foo', '']);

      final other = CommandDetectionCapability(xterm, xterm.logService);
      addTearDown(other.dispose);
      final finished = <ITerminalCommand>[];
      final started = <ITerminalCommand>[];
      other.onCommandFinished(finished.add);
      other.onCommandStarted(started.add);
      other.deserialize(serialized);
      expect(other.commands.single.command, 'echo foo');
      expect(other.commands.single.wasReplayed, isTrue);
      expect(other.commands.single.marker!.line, 0);
      expect(finished, other.commands);
      expect(started.single.marker!.line, 2);
      expect(other.cwd, '/home');
    });

    test(
      'a cursor above the command start invalidates it after 500ms',
      () async {
        final invalidated = <ICommandInvalidationRequest>[];
        capability.onCurrentCommandInvalidated(invalidated.add);
        await writeP(xterm, '\r\n\r\n');
        capability.handlePromptStart();
        capability.handleCommandStart();
        await writeP(xterm, '\x1b[H');
        await Future<void>.delayed(const Duration(milliseconds: 250));
        expect(invalidated, isEmpty);
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(invalidated.single.reason, CommandInvalidationReason.windows);
        expect(capability.currentCommand.isInvalid, isTrue);
      },
    );
  });
}
