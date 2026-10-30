import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/pty.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';

import 'fake_pty.dart';
import 'fake_terminal.dart';

void main() {
  late List<FakePty> started;
  late TerminalService terminals;
  late int changes;

  setUp(() {
    started = [];
    changes = 0;
    terminals = TerminalService(
      root: '/project',
      backend: fakeTerminalBackend(started),
    )..addListener(() => changes++);
  });

  tearDown(() => terminals.dispose());

  test('the first terminal is made when asked for, once', () async {
    expect(terminals.active, isNull);
    final first = terminals.ensureTerminal();
    expect(terminals.ensureTerminal(), first);
    expect(terminals.instances, [first]);
    expect(terminals.active, first);
    expect(changes, 1);
    await pumpEventQueue();
    expect(started.single.launch!.workingDirectory, '/project');

    // New ones start where the project now is.
    terminals.root = '/other';
    terminals.create();
    await pumpEventQueue();
    expect(started.last.launch!.workingDirectory, '/other');
  });

  test('a new terminal is active, as big as the others, and next and '
      'previous go round', () async {
    final a = terminals.create()..resize(120, 40);
    final b = terminals.create();
    final c = terminals.create();
    expect(terminals.instances, [a, b, c]);
    expect([a.id, b.id, c.id], [1, 2, 3]);
    expect(terminals.active, c);
    expect((b.columns, b.rows), (120, 40));

    terminals.focusNext();
    expect(terminals.active, a);
    terminals.focusPrevious();
    expect(terminals.active, c);
    terminals.focusPrevious();
    expect(terminals.active, b);
    terminals.setActive(a);
    expect(terminals.active, a);
  });

  test('a tab moves to where it is dragged, past hidden ones, the active '
      'one staying', () async {
    final a = terminals.create();
    final hidden = terminals.create(
      config: const TerminalLaunchConfig(hideFromUser: true),
    );
    final b = terminals.create();
    final c = terminals.create();
    terminals.move(c, 0);
    expect(terminals.instances, [c, a, b]);
    terminals.move(c, 2);
    expect(terminals.instances, [a, b, c]);
    terminals.move(a, 1);
    expect(terminals.instances, [b, a, c]);
    expect(terminals.allInstances, contains(hidden));
    expect(terminals.active, c);
  });

  test('killing one hangs it up; the one after it (else before) becomes '
      'active', () async {
    final a = terminals.create();
    final b = terminals.create();
    final c = terminals.create();
    await pumpEventQueue();
    terminals.setActive(b);

    terminals.kill();
    expect(terminals.instances, [a, c]);
    expect(terminals.active, c);
    expect(started[1].kills, [PtySignal.hangup]);

    terminals.kill(c);
    expect(terminals.active, a);
    terminals.kill(a);
    expect(terminals.instances, isEmpty);
    expect(terminals.active, isNull);
    terminals.kill();
  });

  test('a terminal whose process exits cleanly goes; one that fails stays '
      'with its reason', () async {
    final a = terminals.create();
    final b = terminals.create();
    await pumpEventQueue();

    started[0].exit(0);
    await pumpEventQueue();
    expect(terminals.instances, [b]);
    expect(a.exitMessage, isNull);

    final before = changes;
    started[1].exit(127);
    await pumpEventQueue();
    expect(terminals.instances, [b]);
    expect(b.exitMessage, contains('exit code: 127'));
    expect(changes, greaterThan(before));
  });

  test('a rename is edited in place, then taken or cancelled', () async {
    final a = terminals.create();
    await pumpEventQueue();
    terminals.startRename();
    expect(terminals.editing, a);
    terminals.endRename(a);
    expect(terminals.editing, isNull);
    expect(a.title, 'zsh');

    terminals.startRename(a);
    terminals.endRename(a, 'server');
    expect(a.title, 'server');

    // Killed while edited, the edit ends.
    terminals.startRename(a);
    terminals.kill(a);
    expect(terminals.editing, isNull);
  });

  test('disposed, it hangs up every terminal', () async {
    terminals
      ..create()
      ..create();
    await pumpEventQueue();
    terminals.dispose();
    expect(
      [for (final pty in started) pty.kills],
      [
        [PtySignal.hangup],
        [PtySignal.hangup],
      ],
    );
    terminals = TerminalService(root: '/project');
  });
}
