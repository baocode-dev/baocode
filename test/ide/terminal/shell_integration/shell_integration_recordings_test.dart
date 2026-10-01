/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/xterm/
// shellIntegrationAddon.integrationTest.ts, on the ported core's internal
// terminal (upstream opens a DOM terminal; nothing here needs one).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/shell_integration_addon.dart';
import 'package:bao_xterm/common/lifecycle.dart';
import 'package:bao_xterm/headless/terminal.dart';

import 'recordings.dart';
import 'shell_integration_test_helpers.dart';

// These are test cases recorded with the `Developer: Record Terminal Session`
// command. Once that is run, a terminal is created and the test case is
// manually executed. After nothing happens for a few seconds the test case
// will be put into the clipboard.
//
// They aim to guarantee the complex interactions within command detection
// result in a particular outcome.

typedef _RecordedTestCase = ({
  /// The test case name.
  String name,

  /// A set of events that will play or be awaited for in order.
  List<RecordedSessionEvent> events,

  /// Any assertions to perform after the events have been played and
  /// validated.
  void Function(ICommandDetectionCapability? commandDetection) finalAssertions,
});

final _recordedTestCases = <_RecordedTestCase>[
  (
    name: 'rich_windows11_pwsh7_echo_3_times',
    events: richWindows11Pwsh7Echo3Times,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, [
        'echo a',
        'echo b',
        'echo c',
      ], '|');
    },
  ),
  (
    name: 'rich_windows11_pwsh7_ls_one_time',
    events: richWindows11Pwsh7LsOneTime,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, ['ls'], '|');
    },
  ),
  (
    name: 'rich_windows11_pwsh7_type_foo',
    events: richWindows11Pwsh7TypeFoo,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, [], 'foo|');
    },
  ),
  (
    name: 'rich_windows11_pwsh7_type_foo_left_twice',
    events: richWindows11Pwsh7TypeFooLeftTwice,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, [], 'f|oo');
    },
  ),
  (
    name: 'rich_macos_zsh_omz_echo_3_times',
    events: richMacosZshOmzEcho3Times,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, [
        'echo a',
        'echo b',
        'echo c',
      ], '|');
    },
  ),
  (
    name: 'rich_macos_zsh_omz_ls_one_time',
    events: richMacosZshOmzLsOneTime,
    finalAssertions: (commandDetection) {
      _assertCommandDetectionState(commandDetection, ['ls'], '|');
    },
  ),
  (
    name: 'basic_macos_zsh_p10k_ls_one_time',
    events: basicMacosZshP10kLsOneTime,
    finalAssertions: (commandDetection) {
      // Prompt input model doesn't work for p10k yet
      // Assert a single command has completed
      expect([for (final e in commandDetection!.commands) e.command], ['']);
    },
  ),
];

void _assertCommandDetectionState(
  ICommandDetectionCapability? commandDetection,
  List<String> commands,
  String promptInput,
) {
  if (commandDetection == null) {
    fail('Command detection must be set');
  }
  expect([for (final e in commandDetection.commands) e.command], commands);
  expect(commandDetection.promptInputModel.getCombinedString(), promptInput);
}

void main() {
  late Terminal xterm;
  late ITerminalCapabilityStore capabilities;

  setUp(() {
    xterm = createTestTerminal();
    final shellIntegrationAddon = ShellIntegrationAddon(
      '',
      null,
      xterm.logService,
    );
    addTearDown(shellIntegrationAddon.dispose);
    capabilities = shellIntegrationAddon.capabilities;
    shellIntegrationAddon.activate(xterm);
  });

  for (final testCase in _recordedTestCases) {
    test(testCase.name, () async {
      final events = testCase.events;
      for (var i = 0; i < events.length; i++) {
        final event = events[i];
        switch (event['type']) {
          case 'resize':
            xterm.resize(event['cols']! as int, event['rows']! as int);
          case 'output':
            final data = event['data']! as String;
            final futures = <Future<void>>[];
            if (data.contains('\x1b]633;B')) {
              // If the output contains the command start sequence, allow
              // time for the prompt to get adjusted.
              final commandDetection = capabilities.get(
                TerminalCapability.commandDetection,
              );
              if (commandDetection != null) {
                final started = Completer<void>();
                late final IDisposable listener;
                listener = commandDetection.onCommandStarted((_) {
                  listener.dispose();
                  started.complete();
                });
                futures.add(started.future);
              }
            }
            futures.add(writeP(xterm, data));
            await Future.wait(futures);
          case 'input':
            xterm.input(event['data']! as String, true);
          case 'promptInputChange':
            // Ignore this event if it's followed by another
            // promptInputChange as that means this one isn't important and
            // could cause a race condition in the test
            if (i + 1 < events.length &&
                events[i + 1]['type'] == 'promptInputChange') {
              continue;
            }
            final data = event['data']! as String;
            final promptInputModel = capabilities
                .get(TerminalCapability.commandDetection)
                ?.promptInputModel;
            if (promptInputModel != null &&
                promptInputModel.getCombinedString() != data) {
              final changed = Completer<void>();
              final listener = promptInputModel.onDidChangeInput((_) {
                if (promptInputModel.getCombinedString() == data &&
                    !changed.isCompleted) {
                  changed.complete();
                }
              });
              try {
                await changed.future.timeout(
                  const Duration(seconds: 1),
                  onTimeout: () => throw StateError(
                    'Prompt input change timed out '
                    'current="${promptInputModel.getCombinedString()}", '
                    'expected="$data"',
                  ),
                );
              } finally {
                listener.dispose();
              }
            }
        }
      }
      testCase.finalAssertions(
        capabilities.get(TerminalCapability.commandDetection),
      );
    });
  }
}
