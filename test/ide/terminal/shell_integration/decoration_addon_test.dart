/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminal/test/browser/xterm/decorationAddon.test.ts,
// on the ported core's internal terminal and decoration service. The
// decorations have no element, hover or listeners here: disposing one
// removes it from the addon's decorations.

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/buffer_mark_capability.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection/terminal_command.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/command_detection_capability.dart';
import 'package:baocode/ide/terminal/shell_integration/capabilities/terminal_capability_store.dart';
import 'package:baocode/ide/terminal/shell_integration/decoration_addon.dart';
import 'package:baocode/ide/terminal/shell_integration/decoration_styles.dart';
import 'package:baocode/ide/terminal/shell_integration/shell_integration_addon.dart';
import 'package:baocode/ide/terminal/terminal_colors.dart';
import 'package:baocode/ide/terminal/xterm/common/buffer/types.dart';
import 'package:baocode/ide/terminal/xterm/common/services/decoration_service.dart';
import 'package:baocode/ide/terminal/xterm/headless/terminal.dart';
import 'package:baocode/theme/codicons.dart';

import '../terminal_color_themes.dart';
import 'shell_integration_test_helpers.dart';

void main() {
  late DecorationAddon decorationAddon;
  late DecorationService decorationService;
  late TerminalCapabilityStore capabilities;
  late Terminal xterm;

  /// Upstream's `{ command, marker, timestamp: Date.now(), ... } as
  /// ITerminalCommand`.
  ITerminalCommand command(
    String command, {
    IMarker? marker,
    int? exitCode,
    int duration = 0,
    IMarkProperties? markProperties,
  }) => TerminalCommand(
    xterm,
    TerminalCommandProperties(
      command: command,
      commandLineConfidence: 'high',
      isTrusted: true,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      duration: duration,
      id: null,
      marker: marker,
      cwd: null,
      exitCode: exitCode,
      commandStartLineContent: null,
      markProperties: markProperties,
      executedX: null,
      startX: null,
    ),
  );

  setUp(() {
    xterm = createTestTerminal(cols: 80, rows: 30);
    decorationService = DecorationService(
      xterm.logService,
      xterm.bufferService,
    );
    capabilities = TerminalCapabilityStore();
    final commandDetection = CommandDetectionCapability(
      xterm,
      xterm.logService,
    );
    capabilities.add(TerminalCapability.commandDetection, commandDetection);
    decorationAddon = DecorationAddon(capabilities, decorationService);
    decorationAddon.activate(xterm);
    addTearDown(() {
      decorationAddon.dispose();
      commandDetection.dispose();
      capabilities.dispose();
      decorationService.dispose();
    });
  });

  group('registerDecoration', () {
    test('should throw when command has no marker', () {
      expect(
        () => decorationAddon.registerCommandDecoration(command('cd src')),
        throwsStateError,
      );
    });
    test('should return undefined when marker has been disposed of', () {
      final marker = xterm.registerMarker(1);
      marker.dispose();
      expect(
        decorationAddon.registerCommandDecoration(
          command('cd src', marker: marker),
        ),
        isNull,
      );
    });
    test('should return decoration when marker has not been disposed of', () {
      final marker = xterm.registerMarker(2);
      expect(
        decorationAddon.registerCommandDecoration(
          command('cd src', marker: marker),
        ),
        isNotNull,
      );
    });
    test('should return decoration with mark properties', () {
      final marker = xterm.registerMarker(2);
      expect(
        decorationAddon.registerCommandDecoration(
          null,
          false,
          IMarkProperties(marker: marker),
        ),
        isNotNull,
      );
    });
    test(
      'should dispose decoration resources when the decoration is disposed',
      () {
        final marker = xterm.registerMarker(2);
        final decoration = decorationAddon.registerCommandDecoration(
          command('cd src', marker: marker, exitCode: 0),
        )!;
        expect(decorationAddon.decorations, hasLength(1));
        var changes = 0;
        decorationAddon.onDidChangeDecorations((_) => changes++);

        decoration.dispose();

        expect(changes, 1);
        expect([
          for (final d in decorationAddon.decorations) d.marker.id,
        ], isNot(contains(marker.id)));
        expect(decorationService.decorations, isEmpty);
      },
    );
  });

  // Not upstream: what the view paints.
  group('decorations', () {
    test('of a successful command', () {
      final marker = xterm.registerMarker(0);
      decorationAddon.registerCommandDecoration(
        command('ls', marker: marker, exitCode: 0, duration: 1500),
      );
      final decoration = decorationAddon.decorations.single;
      expect(decoration.marker, same(marker));
      expect(decoration.isPlaceholder, isFalse);
      expect(decoration.classNames, [
        DecorationSelector.commandDecoration,
        DecorationSelector.codicon,
        DecorationSelector.xtermDecoration,
        DecorationSelector.success,
      ]);
      expect(decoration.icon, Codicons.circleFilled);
      expect(
        decoration.color,
        TerminalColors.commandDecorationSuccessBackground,
      );
      expect(decoration.isVisible, isTrue);
      expect(decoration.isInteractive, isTrue);
      expect(
        decoration.hoverMessage,
        'Show Command Actions\n\n---\n\nCommand executed now and took 1.5s',
      );
      final overviewRuler = decoration.decoration.options.overviewRulerOptions!;
      expect(overviewRuler.color, '#1b81a8');
      expect(overviewRuler.position, 'left');
    });

    test('of a failed command', () {
      final marker = xterm.registerMarker(0);
      decorationAddon.registerCommandDecoration(
        command('false', marker: marker, exitCode: 1, duration: 20),
      );
      final decoration = decorationAddon.decorations.single;
      expect(decoration.classNames.last, DecorationSelector.errorColor);
      expect(decoration.icon, Codicons.errorSmall);
      expect(decoration.color, TerminalColors.commandDecorationErrorBackground);
      expect(
        decoration.hoverMessage,
        'Show Command Actions\n\n---\n\n'
        'Command executed now, took 20ms and failed (Exit Code 1)',
      );
      final overviewRuler = decoration.decoration.options.overviewRulerOptions!;
      expect(overviewRuler.color, '#f14c4c');
      expect(overviewRuler.position, 'right');
    });

    test('of a command being run: the placeholder', () {
      final marker = xterm.registerMarker(0);
      decorationAddon.registerCommandDecoration(
        command('sleep 1', marker: marker),
        true,
      );
      final decoration = decorationAddon.decorations.single;
      expect(decoration.isPlaceholder, isTrue);
      expect(
        decoration.classNames,
        containsAll([
          DecorationSelector.defaultColor,
          DecorationSelector.defaultClass,
        ]),
      );
      expect(decoration.icon, Codicons.circle);
      expect(
        decoration.color,
        TerminalColors.commandDecorationDefaultBackground,
      );
      expect(decoration.isInteractive, isFalse);
      expect(decoration.hoverMessage, isNull);
      final overviewRuler = decoration.decoration.options.overviewRulerOptions!;
      expect(overviewRuler.color, 'rgba(255, 255, 255, 0.25)');
      expect(overviewRuler.position, 'left');

      // The next decoration replaces it.
      decorationAddon.registerCommandDecoration(
        command('sleep 1', marker: xterm.registerMarker(1), exitCode: 0),
      );
      expect(decorationAddon.decorations, hasLength(1));
      expect(decorationAddon.decorations.single.isPlaceholder, isFalse);
    });

    test('of marks', () async {
      final bufferMarks = BufferMarkCapability(xterm);
      addTearDown(bufferMarks.dispose);
      capabilities.add(TerminalCapability.bufferMarkDetection, bufferMarks);

      bufferMarks.addMark(IMarkProperties(hidden: true));
      expect(decorationAddon.decorations, isEmpty);

      bufferMarks.addMark();
      await writeP(xterm, '\r\n');
      bufferMarks.addMark(IMarkProperties(hoverMessage: 'Build started'));
      final [mark, markWithHover] = decorationAddon.decorations.toList();
      expect(mark.command, isNull);
      expect(mark.icon, Codicons.circleSmallFilled);
      expect(mark.color, TerminalColors.commandDecorationDefaultBackground);
      expect(mark.isInteractive, isFalse);
      expect(mark.hoverMessage, isNull);
      expect(markWithHover.marker.line, 1);
      expect(markWithHover.isInteractive, isTrue);
      expect(
        markWithHover.classNames,
        isNot(contains(DecorationSelector.defaultClass)),
      );
    });

    test('follow decorationsEnabled', () {
      decorationAddon.registerCommandDecoration(
        command('ls', marker: xterm.registerMarker(0), exitCode: 0),
      );

      decorationAddon.setDecorationsEnabled(gutter: false, overviewRuler: true);
      // Upstream disposes them, and draws the ones to come.
      expect(decorationAddon.decorations, isEmpty);
      decorationAddon.registerCommandDecoration(
        command('ls', marker: xterm.registerMarker(0), exitCode: 0),
      );
      final decoration = decorationAddon.decorations.single;
      expect(decoration.isVisible, isFalse);
      expect(decoration.decoration.options.overviewRulerOptions, isNotNull);

      decorationAddon.setDecorationsEnabled(gutter: true, overviewRuler: false);
      decorationAddon.registerCommandDecoration(
        command('ls', marker: xterm.registerMarker(0), exitCode: 0),
      );
      expect(decorationAddon.decorations.single.isVisible, isTrue);
      expect(
        decorationAddon
            .decorations
            .single
            .decoration
            .options
            .overviewRulerOptions,
        isNull,
      );

      decorationAddon.setDecorationsEnabled(
        gutter: false,
        overviewRuler: false,
      );
      expect(
        decorationAddon.registerCommandDecoration(
          command('ls', marker: xterm.registerMarker(0), exitCode: 0),
        ),
        isNull,
      );
      expect(decorationAddon.decorations, isEmpty);
    });

    test('go with their marker', () {
      final marker = xterm.registerMarker(0);
      decorationAddon.registerCommandDecoration(
        command('ls', marker: marker, exitCode: 0),
      );
      marker.dispose();
      expect(decorationAddon.decorations, isEmpty);
      expect(decorationService.decorations, isEmpty);
    });

    test('are cleared when the addon is disposed', () {
      decorationAddon.registerCommandDecoration(
        command('ls', marker: xterm.registerMarker(0), exitCode: 0),
      );
      decorationAddon.dispose();
      expect(decorationAddon.decorations, isEmpty);
      expect(decorationService.decorations, isEmpty);
    });
  });

  // Not upstream: the decorations of commands as the shell reports them.
  group('with shell integration', () {
    late ShellIntegrationAddon shellIntegrationAddon;

    setUp(() {
      // On a terminal of its own.
      decorationAddon.dispose();
      decorationService.dispose();
      xterm = createTestTerminal();
      decorationService = DecorationService(
        xterm.logService,
        xterm.bufferService,
      );
      shellIntegrationAddon = ShellIntegrationAddon('', null, xterm.logService);
      addTearDown(shellIntegrationAddon.dispose);
      shellIntegrationAddon.activate(xterm);
      decorationAddon = DecorationAddon(
        shellIntegrationAddon.capabilities,
        decorationService,
      );
      decorationAddon.activate(xterm);
    });

    test('a placeholder while a command runs, then its status', () async {
      await writeP(xterm, '\x1b]633;A\x07\$ \x1b]633;B\x07');
      final placeholder = decorationAddon.decorations.single;
      expect(placeholder.isPlaceholder, isTrue);
      expect(placeholder.marker.line, 0);

      await writeP(xterm, 'false\r\n\x1b]633;E;false;\x07\x1b]633;C\x07');
      expect(decorationAddon.decorations.single.isPlaceholder, isTrue);

      await writeP(xterm, '\x1b]633;D;1\x07\x1b]633;A\x07\$ \x1b]633;B\x07');
      final [failed, next] = decorationAddon.decorations.toList();
      expect(failed.command!.command, 'false');
      expect(failed.icon, Codicons.errorSmall);
      expect(failed.marker.line, 0);
      expect(next.isPlaceholder, isTrue);
      expect(next.marker.line, 1);

      await writeP(xterm, 'true\r\n\x1b]633;E;true;\x07\x1b]633;C\x07');
      await writeP(xterm, '\x1b]633;D;0\x07');
      expect(
        [for (final d in decorationAddon.decorations) d.color],
        [
          TerminalColors.commandDecorationErrorBackground,
          TerminalColors.commandDecorationSuccessBackground,
        ],
      );
    });
  });

  // Upstream's `onDidColorThemeChange` listener (`_refreshStyles(true)`).
  test('a theme change recolors the decorations and their marks', () {
    final theme = ValueNotifier(TerminalColorTheme.dark2026);
    addTearDown(theme.dispose);
    decorationAddon.dispose();
    decorationAddon = DecorationAddon(
      capabilities,
      decorationService,
      colorTheme: theme,
    );
    decorationAddon.activate(xterm);
    decorationAddon.registerCommandDecoration(
      command('false', marker: xterm.registerMarker(0), exitCode: 1),
    );
    decorationAddon.registerCommandDecoration(
      command('sleep 1', marker: xterm.registerMarker(1)),
      true,
    );
    final [failed, placeholder] = decorationAddon.decorations.toList();
    expect(failed.color, TerminalColors.commandDecorationErrorBackground);
    expect(
      placeholder.decoration.options.overviewRulerOptions!.color,
      'rgba(255, 255, 255, 0.25)',
    );
    var changes = 0;
    decorationAddon.onDidChangeDecorations((_) => changes++);

    theme.value = light2026;
    expect(changes, 1);
    expect(failed.color, const Color(0xFFE51400));
    expect(placeholder.color, const Color(0x40000000));
    expect(failed.decoration.options.overviewRulerOptions!.color, '#e51400');
    expect(failed.decoration.options.overviewRulerOptions!.position, 'right');
    expect(
      placeholder.decoration.options.overviewRulerOptions!.color,
      'rgba(0, 0, 0, 0.25)',
    );
    // New ones take the theme's colors.
    decorationAddon.registerCommandDecoration(
      command('true', marker: xterm.registerMarker(2), exitCode: 0),
    );
    final succeeded = decorationAddon.decorations.last;
    expect(succeeded.color, const Color(0xFF2090D3));
    expect(succeeded.decoration.options.overviewRulerOptions!.color, '#2090d3');

    decorationAddon.dispose();
    // ignore: invalid_use_of_protected_member
    expect(theme.hasListeners, isFalse);
  });

  test('as upstream, a theme change gives a decoration registered without '
      'an overview ruler mark one', () {
    final theme = ValueNotifier(TerminalColorTheme.dark2026);
    addTearDown(theme.dispose);
    decorationAddon.dispose();
    decorationAddon = DecorationAddon(
      capabilities,
      decorationService,
      showOverviewRulerDecorations: false,
      colorTheme: theme,
    );
    decorationAddon.activate(xterm);
    decorationAddon.registerCommandDecoration(
      command('true', marker: xterm.registerMarker(0), exitCode: 0),
    );
    final decoration = decorationAddon.decorations.single.decoration;
    expect(decoration.options.overviewRulerOptions, isNull);
    theme.value = light2026;
    expect(decoration.options.overviewRulerOptions!.color, '#2090d3');
    expect(decoration.options.overviewRulerOptions!.position, isNull);
  });

  test('cssColor', () {
    expect(cssColor(const Color(0xFF1B81A8)), '#1b81a8');
    expect(cssColor(const Color(0x40FFFFFF)), 'rgba(255, 255, 255, 0.25)');
    expect(cssColor(const Color(0x00000000)), 'rgba(0, 0, 0, 0)');
    expect(cssColor(const Color(0x80102030)), 'rgba(16, 32, 48, 0.5)');
  });
}
