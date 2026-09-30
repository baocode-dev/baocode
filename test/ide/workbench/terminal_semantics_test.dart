// The terminal panel through what changes its semantics most: output with
// command marks, hovers, scrolling, a second terminal, find, the panel's
// tabs, processes ending, the panel closing. Every test's semantics
// updates are applied as the desktop engines apply them
// (flutter_test_config.dart, semantics_tree.dart).

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../terminal/fake_pty.dart';
import 'fake_files.dart';

void main() {
  testWidgets('the terminal panel\'s semantics updates apply to the '
      'desktop engines\' tree', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
      'lib/b.dart': 'b',
    }, startPty: FakePty.starter(ptys));
    void check(String step) =>
        expect(tester.takeException(), isNull, reason: step);
    check('shown');

    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await chord(tester, LogicalKeyboardKey.backquote, control: true);
    await settle();
    check('terminal opened');

    String command(String line, int code) =>
        '\x1b]633;A\x07\$ \x1b]633;B\x07$line\x1b]633;E;$line\x07'
        '\x1b]633;C\x07\r\noutput of $line\r\n\x1b]633;D;$code\x07';
    ptys.last.emitText(
      '${command('ls', 0)}${command('false', 1)}'
      '${List.generate(60, (i) => 'line $i\r\n').join()}'
      '${command('echo', 0)}\x1b]633;A\x07\$ ',
    );
    await settle();
    check('output with command marks');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    final panel = tester.getRect(find.byKey(const ValueKey('ide-panel')));
    for (var y = panel.top + 4; y < panel.bottom; y += 6) {
      for (final x in [panel.left + 6, panel.left + 12, panel.right - 40]) {
        await mouse.moveTo(Offset(x, y));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await settle();
    check('hovered');

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: panel.center,
        scrollDelta: const Offset(0, -400),
      ),
    );
    await settle();
    check('scrolled');

    await chord(
      tester,
      LogicalKeyboardKey.backquote,
      control: true,
      shift: true,
    );
    await settle();
    check('second terminal');

    await chord(tester, LogicalKeyboardKey.keyF, control: true);
    await settle();
    check('find');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle();

    await tester.tap(find.text('PROBLEMS'));
    await settle();
    await tester.tap(find.text('TERMINAL'));
    await settle();
    check('tabs switched');

    ptys.last.exit(1);
    await settle();
    ptys.first.exit(0);
    await settle();
    check('terminals ended');

    await chord(tester, LogicalKeyboardKey.backquote, control: true);
    await settle();
    check('panel closed');
  });
}
