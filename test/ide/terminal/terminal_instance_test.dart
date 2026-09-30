import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/pty.dart';
import 'package:monad/ide/terminal/terminal_instance.dart';

import 'fake_pty.dart';
import 'fake_terminal.dart';

/// A terminal on a fake, and what it was told of its exit.
({TerminalInstance terminal, List<FakePty> started, List<int?> exits}) _start({
  TerminalBackend? backend,
  List<FakePty>? started,
}) {
  final ptys = started ?? <FakePty>[];
  final exits = <int?>[];
  final terminal = TerminalInstance(
    id: 1,
    root: '/project',
    backend: backend ?? fakeTerminalBackend(ptys),
    columns: 100,
    rows: 30,
    onExit: (terminal) => exits.add(terminal.exitCode),
  );
  addTearDown(terminal.dispose);
  return (terminal: terminal, started: ptys, exits: exits);
}

void main() {
  test('starts the shell in its folder, as big as it is, and is named '
      'after the process', () async {
    final (:terminal, :started, exits: _) = _start();
    expect(terminal.title, 'Terminal');
    expect(terminal.processName, '');
    await pumpEventQueue();

    final launch = started.single.launch!;
    expect(launch.executable, '/bin/zsh');
    expect(launch.workingDirectory, '/project');
    expect((launch.columns, launch.rows), (100, 30));
    expect(terminal.pty, started.single);
    expect(terminal.processName, 'zsh');
    expect(terminal.title, 'zsh');
    expect(terminal.exited, isFalse);
  });

  test('a Windows shell is named without its .exe', () async {
    final (:terminal, started: _, exits: _) = _start(
      backend: TerminalBackend(
        launch: (root, {columns = 80, rows = 24}) async =>
            PtyLaunch(executable: 'pwsh.EXE', workingDirectory: root),
        start: FakePty.starter([]),
        supported: true,
      ),
    );
    await pumpEventQueue();
    expect(terminal.title, 'pwsh');
  });

  test('what is typed before the process is there goes to it once it is; '
      'its output and its size go through', () async {
    final (:terminal, :started, exits: _) = _start();
    terminal
      ..writeText('ls\r')
      ..resize(120, 40);
    await pumpEventQueue();
    final pty = started.single;
    expect(pty.written, 'ls\r');
    // Resized before it started: the pty is told once it is there.
    expect(pty.resizes, [(columns: 120, rows: 40)]);

    final printed = <String>[];
    terminal.output.listen((data) => printed.add(utf8.decode(data)));
    pty.emitText('total 0\r\n');
    await pumpEventQueue();
    expect(printed, ['total 0\r\n']);

    terminal
      ..writeText('pwd\r')
      ..resize(120, 40)
      ..resize(80, 24);
    expect(pty.written, 'ls\rpwd\r');
    expect(pty.resizes.last, (columns: 80, rows: 24));
    expect(pty.resizes, hasLength(2));
    expect((terminal.columns, terminal.rows), (80, 24));
  });

  test(
    'a rename overrides the process name; an empty one gives it back',
    () async {
      final (:terminal, started: _, exits: _) = _start();
      await pumpEventQueue();
      var changes = 0;
      terminal.addListener(() => changes++);

      terminal.rename('build');
      expect(terminal.title, 'build');
      expect(terminal.userTitle, 'build');
      terminal.rename('build');
      expect(changes, 1);
      terminal.rename('  ');
      expect(terminal.title, 'zsh');
      expect(terminal.userTitle, isNull);
      expect(changes, 2);
    },
  );

  test('exit code 0 ends it without a message', () async {
    final (:terminal, :started, :exits) = _start();
    await pumpEventQueue();
    started.single.exit(0);
    await pumpEventQueue();
    expect(exits, [0]);
    expect(terminal.exited, isTrue);
    expect(terminal.exitMessage, isNull);
  });

  test(
    'a signal ends it without a message, as node-pty reports it (0)',
    () async {
      final (:terminal, :started, :exits) = _start();
      await pumpEventQueue();
      started.single.exit(-PtySignal.kill.number);
      await pumpEventQueue();
      expect(exits, [-9]);
      expect(terminal.exitMessage, isNull);
    },
  );

  test(
    'another exit code is explained as VS Code does, and input stops',
    () async {
      final (:terminal, :started, :exits) = _start();
      await pumpEventQueue();
      final pty = started.single;
      pty.exit(2);
      await pumpEventQueue();
      expect(exits, [2]);
      expect(terminal.exitCode, 2);
      expect(
        terminal.exitMessage,
        'The terminal process "/bin/zsh \'-l\'" terminated with exit code: 2.',
      );
      terminal.writeText('late');
      expect(pty.written, '');
      // Its process is gone: disposing it hangs nothing up.
      terminal.dispose();
      expect(pty.kills, isEmpty);
    },
  );

  test('a launch that fails leaves the reason', () async {
    final (:terminal, started: _, :exits) = _start(
      backend: TerminalBackend(
        launch: fakeTerminalLaunch,
        start: (launch) async =>
            throw const PtyException('The folder is gone', detail: '/project'),
        supported: true,
      ),
    );
    await pumpEventQueue();
    expect(exits, [null]);
    expect(terminal.exited, isTrue);
    expect(
      terminal.exitMessage,
      'The terminal process failed to launch: The folder is gone: /project.',
    );
  });

  test('disposed, it hangs up its process and hears no more of it', () async {
    final (:terminal, :started, :exits) = _start();
    await pumpEventQueue();
    final pty = started.single;
    terminal.dispose();
    expect(pty.kills, [PtySignal.hangup]);
    pty.exit(1);
    await pumpEventQueue();
    expect(exits, isEmpty);
    expect(terminal.exited, isFalse);
  });

  test('disposed before its process started, none starts; disposed while '
      'it starts, it is hung up as it comes', () async {
    final (terminal: early, started: none, exits: _) = _start();
    early.dispose();
    await pumpEventQueue();
    expect(none, isEmpty);

    final starting = Completer<Pty>();
    final (:terminal, started: _, exits: _) = _start(
      backend: TerminalBackend(
        launch: fakeTerminalLaunch,
        start: (launch) => starting.future,
        supported: true,
      ),
    );
    await pumpEventQueue();
    terminal.dispose();
    final pty = FakePty();
    starting.complete(pty);
    await pumpEventQueue();
    expect(pty.kills, [PtySignal.hangup]);
    expect(terminal.pty, isNull);
  });

  test('what the process prints goes into the emulator; its shell '
      'integration trusts the command lines its launch\'s nonce comes '
      'with', () async {
    final ptys = <FakePty>[];
    final (:terminal, started: _, exits: _) = _start(
      backend: TerminalBackend(
        launch: (root, {columns = 80, rows = 24}) async => PtyLaunch(
          executable: '/bin/zsh',
          arguments: const ['-l'],
          workingDirectory: root,
          environment: const {'VSCODE_NONCE': 'n0nce'},
        ),
        start: FakePty.starter(ptys),
        linkStat: (_) async => null,
        supported: true,
      ),
    );
    await pumpEventQueue();
    expect(terminal.shellIntegration, isNotNull);

    // A command line reported with the nonce is trusted; one with another
    // is ignored (VS Code's OSC 633;E), the line then being what was typed
    // at the prompt: nothing here.
    String command(String line, String nonce) =>
        '\x1b]633;A\x07\$ \x1b]633;B\x07\x1b]633;E;$line;$nonce\x07'
        '\x1b]633;C\x07\r\n\x1b]633;D;0\x07';
    ptys.single.emitText('${command('ls', 'n0nce')}${command('rm', 'other')}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final commands = terminal.shellIntegration!.commands;
    expect(
      [for (final c in commands) (c.command, c.isTrusted)],
      [('ls', true), ('', false)],
    );
    expect(
      terminal.terminal.buffer.lines.get(0)!.translateToString(true),
      r'$ ',
    );
  });
}
