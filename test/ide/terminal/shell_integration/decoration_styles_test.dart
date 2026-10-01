/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `getDurationString` is adapted from VS Code
// 6a598d4a13031703d483d103c1d934a36ad27971: src/vs/base/test/common/
// date.test.ts (its short words; the full words are not ported). The rest
// is not upstream.

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection/terminal_command.dart';
import 'package:baocode/ide/terminal/shell_integration/decoration_styles.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:bao_xterm/headless/terminal.dart';
import 'package:baocode/theme/codicons.dart';

import 'shell_integration_test_helpers.dart';

void main() {
  group('getDurationString', () {
    test('basic', () {
      expect(getDurationString(1), '1ms');
      expect(getDurationString(999), '999ms');
      expect(getDurationString(1000), '1s');
      expect(getDurationString(1000 * 60 - 1), '59.999s');
      expect(getDurationString(1000 * 60), '1 mins');
      expect(getDurationString(1000 * 60 * 60 - 1), '60 mins');
      expect(getDurationString(1000 * 60 * 60), '1 hrs');
      expect(getDurationString(1000 * 60 * 60 * 24 - 1), '24 hrs');
      expect(getDurationString(1000 * 60 * 60 * 24), '1 days');
    });
  });

  group('getTerminalCommandDecorationState', () {
    late Terminal xterm;
    final now = DateTime.now().millisecondsSinceEpoch;

    ITerminalCommand command({
      int? exitCode,
      int? timestamp,
      int duration = 0,
      IMarkProperties? markProperties,
    }) => TerminalCommand(
      xterm,
      TerminalCommandProperties(
        command: 'make',
        commandLineConfidence: 'high',
        isTrusted: true,
        timestamp: timestamp ?? now - 5000,
        duration: duration,
        id: null,
        marker: null,
        cwd: null,
        exitCode: exitCode,
        commandStartLineContent: null,
        markProperties: markProperties,
        executedX: null,
        startX: null,
      ),
    );

    setUp(() => xterm = createTestTerminal());

    test('of a running command', () {
      final state = getTerminalCommandDecorationState(command(), null, now);
      expect(state.status, TerminalCommandDecorationStatus.running);
      expect(state.icon, Codicons.circle);
      expect(state.classNames, [
        DecorationSelector.defaultColor,
        DecorationSelector.defaultClass,
      ]);
      expect(state.color, TerminalColors.commandDecorationDefaultBackground);
      expect(state.exitCodeText, 'Running');
      expect(state.duration, 5000);
      expect(state.durationText, '5s');
    });

    test('of a successful command', () {
      final state = getTerminalCommandDecorationState(
        command(exitCode: 0, duration: 250),
        null,
        now,
      );
      expect(state.status, TerminalCommandDecorationStatus.success);
      expect(state.icon, Codicons.circleFilled);
      expect(state.classNames, [DecorationSelector.success]);
      expect(state.color, TerminalColors.commandDecorationSuccessBackground);
      expect(state.exitCodeText, '0');
      expect(state.durationText, '250ms');
      expect(state.hoverMessage, 'Command executed now and took 250ms');
    });

    test('of a failed command', () {
      final state = getTerminalCommandDecorationState(
        command(exitCode: 127, duration: 90000),
        null,
        now,
      );
      expect(state.status, TerminalCommandDecorationStatus.error);
      expect(state.icon, Codicons.errorSmall);
      expect(state.classNames, [DecorationSelector.errorColor]);
      expect(state.color, TerminalColors.commandDecorationErrorBackground);
      expect(state.exitCode, 127);
      expect(
        state.hoverMessage,
        'Command executed now, took 2 mins and failed (Exit Code 127)',
      );
    });

    test('from a stored state', () {
      final timestamp = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      final state = getTerminalCommandDecorationState(
        null,
        TerminalCommandDecorationPersistedState(
          exitCode: -1,
          timestamp: timestamp,
          duration: 1000,
        ),
      );
      expect(state.status, TerminalCommandDecorationStatus.error);
      expect(
        state.hoverMessage,
        'Command executed 2 hrs ago, took 1s and failed',
      );

      final unknown = getTerminalCommandDecorationState(null);
      expect(unknown.status, TerminalCommandDecorationStatus.unknown);
      expect(unknown.icon, Codicons.circle);
      expect(unknown.hoverMessage, '');
    });

    test('hover content of marks', () {
      expect(getTerminalDecorationHoverContent(null), '');
      expect(getTerminalDecorationHoverContent(null, 'Build'), 'Build');
      expect(
        getTerminalDecorationHoverContent(
          command(markProperties: IMarkProperties(hoverMessage: 'Task')),
          null,
          true,
        ),
        'Task',
      );
      expect(
        getTerminalDecorationHoverContent(
          command(markProperties: IMarkProperties()),
        ),
        '',
      );
    });
  });

  test('decorationColorOf', () {
    expect(
      decorationColorOf([DecorationSelector.errorColor]),
      TerminalColors.commandDecorationErrorBackground,
    );
    expect(
      decorationColorOf([DecorationSelector.defaultClass]),
      TerminalColors.commandDecorationDefaultBackground,
    );
    expect(
      decorationColorOf([DecorationSelector.defaultColor]),
      TerminalColors.commandDecorationSuccessBackground,
    );
  });

  test('decorationLayout', () {
    expect(decorationLayout(fontSize: 12, defaultFontSize: 12, lineHeight: 1), (
      width: 16.0,
      height: 16.0,
      fontSize: 16.0,
      marginLeft: -17.0,
    ));
    // Scaled down with the font, never up.
    expect(decorationLayout(fontSize: 6, defaultFontSize: 12, lineHeight: 1), (
      width: 8.0,
      height: 8.0,
      fontSize: 8.0,
      marginLeft: -8.5,
    ));
    expect(
      decorationLayout(fontSize: 20, defaultFontSize: 12, lineHeight: 1.5),
      (width: 16.0, height: 24.0, fontSize: 16.0, marginLeft: -17.0),
    );
  });
}
