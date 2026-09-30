// Tests of a terminal's ShellIntegration: the commands, cwds and
// decorations it finds in what VS Code's scripts write.

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/shell_integration/capabilities/capabilities.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration.dart';
import 'package:monad/ide/terminal/shell_integration/shell_integration_addon.dart';
import 'package:monad/ide/terminal/terminal_colors.dart';
import 'package:monad/ide/terminal/xterm/common/services/decoration_service.dart';
import 'package:monad/ide/terminal/xterm/headless/terminal.dart';
import 'package:monad/theme/codicons.dart';

import 'shell_integration_test_helpers.dart';

void main() {
  late Terminal terminal;

  setUp(() => terminal = createTestTerminal());

  ShellIntegration create({String nonce = 'n0nce', bool isWindows = false}) {
    final shellIntegration = ShellIntegration(
      terminal,
      nonce: nonce,
      isWindows: isWindows,
    );
    addTearDown(shellIntegration.dispose);
    return shellIntegration;
  }

  /// What VS Code's scripts write around a command line typed at a `$ `
  /// prompt, with [nonce] on its command line.
  Future<void> runCommand(
    String commandLine, {
    String nonce = 'n0nce',
    int? exitCode = 0,
    String output = '',
  }) async {
    await writeP(terminal, '\x1b]633;A\x07\$ \x1b]633;B\x07$commandLine\r\n');
    if (commandLine.isNotEmpty) {
      final serialized = serializeVSCodeOscMessage(commandLine);
      await writeP(terminal, '\x1b]633;E;$serialized;$nonce\x07');
      await writeP(terminal, '\x1b]633;C\x07$output');
    }
    await writeP(
      terminal,
      '\x1b]633;D${exitCode == null ? '' : ';$exitCode'}\x07',
    );
  }

  test('knows nothing without shell integration', () async {
    final shellIntegration = create();
    await writeP(terminal, '\$ ls\r\na b\r\n\$ ');
    expect(shellIntegration.status, ShellIntegrationStatus.off);
    expect(shellIntegration.commandDetection, isNull);
    expect(shellIntegration.commands, isEmpty);
    expect(shellIntegration.recentCommands, isEmpty);
    expect(shellIntegration.cwd, isNull);
    expect(shellIntegration.cwds, isEmpty);
    expect(shellIntegration.decorations, isEmpty);
  });

  test('tracks commands', () async {
    final shellIntegration = create();
    final statuses = <ShellIntegrationStatus>[];
    shellIntegration.onDidChangeStatus(statuses.add);
    final started = <ITerminalCommand>[];
    shellIntegration.onCommandStarted(started.add);
    final finished = <ITerminalCommand>[];
    shellIntegration.onCommandFinished(finished.add);

    await runCommand('ls', output: 'a b\r\n');
    await runCommand('false', exitCode: 1);

    expect(statuses, [ShellIntegrationStatus.vsCode]);
    expect([for (final c in started) c.marker!.line], [0, 2]);
    expect(finished, shellIntegration.commands);
    final [ls, false_] = shellIntegration.commands;
    expect(ls.command, 'ls');
    expect(ls.isTrusted, isTrue);
    expect(ls.exitCode, 0);
    expect(ls.marker!.line, 0);
    expect(ls.getOutput(), 'a b\n');
    expect(false_.command, 'false');
    expect(false_.exitCode, 1);
    expect(false_.marker!.line, 2);
  });

  test('trusts command lines with its nonce only', () async {
    final shellIntegration = create();
    await runCommand('echo a');
    await runCommand('echo b', nonce: 'spoofed');
    expect(
      [for (final c in shellIntegration.commands) c.isTrusted],
      [true, false],
    );
  });

  test('trusts nothing without a nonce', () async {
    final shellIntegration = create(nonce: '');
    await runCommand('echo a', nonce: '');
    await writeP(terminal, '\x1b]633;P;Cwd=/a;\x07');
    expect(shellIntegration.commands.single.isTrusted, isFalse);
    expect(
      shellIntegration.capabilities
          .get(TerminalCapability.cwdDetection)!
          .isTrusted,
      isFalse,
    );
  });

  test('tracks the cwd', () async {
    final shellIntegration = create();
    final cwds = <String>[];
    shellIntegration.onDidChangeCwd(cwds.add);

    await writeP(terminal, '\x1b]633;A\x07\x1b]633;P;Cwd=/home/u;n0nce\x07');
    expect(shellIntegration.cwd, '/home/u');
    expect(
      shellIntegration.capabilities
          .get(TerminalCapability.cwdDetection)!
          .isTrusted,
      isTrue,
    );
    await writeP(terminal, '\$ \x1b]633;B\x07');
    await writeP(terminal, 'cd /tmp\r\n\x1b]633;E;cd\\x20/tmp;n0nce\x07');
    await writeP(terminal, '\x1b]633;C\x07\x1b]633;D;0\x07');
    // From the OSC 7 of another shell's script: never trusted.
    await writeP(terminal, '\x1b]7;file://host/tmp\x07');

    expect(shellIntegration.cwd, '/tmp');
    expect(shellIntegration.cwds, ['/home/u', '/tmp']);
    expect(cwds, ['/home/u', '/tmp']);
    expect(
      shellIntegration.capabilities
          .get(TerminalCapability.cwdDetection)!
          .isTrusted,
      isFalse,
    );
    expect(shellIntegration.commands.single.cwd, '/home/u');
  });

  test('uppercases drive letters on Windows', () async {
    final shellIntegration = create(isWindows: true);
    await writeP(terminal, '\x1b]633;P;Cwd=c:\\x5cUsers;n0nce\x07');
    expect(shellIntegration.cwd, r'C:\Users');
  });

  test('lists the recent commands', () async {
    final shellIntegration = create();
    await runCommand('ls');
    await runCommand('pwd');
    await runCommand(' ls ');
    await runCommand('', exitCode: null);
    expect(
      [for (final c in shellIntegration.recentCommands) c.command],
      [' ls ', 'pwd'],
    );

    // Not the one running.
    await writeP(terminal, '\x1b]633;A\x07\$ \x1b]633;B\x07pwd\r\n');
    await writeP(terminal, '\x1b]633;E;pwd;n0nce\x07\x1b]633;C\x07');
    expect(
      [for (final c in shellIntegration.recentCommands) c.command],
      [' ls '],
    );
  });

  test('decorates the commands', () async {
    final shellIntegration = create();
    var changes = 0;
    shellIntegration.onDidChangeDecorations((_) => changes++);

    await runCommand('ls');
    await runCommand('false', exitCode: 1);
    await writeP(terminal, '\x1b]633;A\x07\$ \x1b]633;B\x07');

    expect(changes, greaterThan(0));
    final [ls, false_, placeholder] = shellIntegration.decorations.toList();
    expect(
      (ls.marker.line, ls.icon, ls.color),
      (
        0,
        Codicons.circleFilled,
        TerminalColors.commandDecorationSuccessBackground,
      ),
    );
    expect(
      (false_.marker.line, false_.icon, false_.color),
      (1, Codicons.errorSmall, TerminalColors.commandDecorationErrorBackground),
    );
    expect(placeholder.isPlaceholder, isTrue);
    expect(placeholder.marker.line, 2);
  });

  test('marks the overview ruler of the given decoration service', () async {
    final decorationService = DecorationService(
      terminal.logService,
      terminal.bufferService,
    );
    addTearDown(decorationService.dispose);
    final shellIntegration = ShellIntegration(
      terminal,
      nonce: 'n0nce',
      decorationService: decorationService,
    );
    await runCommand('false', exitCode: 1);
    expect(
      [
        for (final d in decorationService.decorations)
          (d.options.overviewRulerOptions?.color, d.marker.line),
      ],
      [('#f14c4c', 0)],
    );

    // Its decorations go with it.
    shellIntegration.dispose();
    expect(decorationService.decorations, isEmpty);
  });

  test('stops reading the terminal when disposed', () async {
    final shellIntegration = create();
    await runCommand('ls');
    shellIntegration.dispose();
    await runCommand('pwd');
    expect(shellIntegration.decorations, isEmpty);
  });
}
