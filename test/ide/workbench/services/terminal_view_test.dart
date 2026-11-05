import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart' show IdePanelTab;
import 'package:baocode/ide/services/terminal_view.dart';
import 'package:baocode/ide/terminal/terminal_instance.dart';
import 'package:baocode/ide/terminal/terminal_service.dart';

import '../../terminal/fake_pty.dart';
import '../../terminal/fake_terminal.dart';
import 'fake_host.dart';

/// The panel's terminals as the workbench shows them, over a layout alone.
void main() {
  late IdeLayout layout;
  late FakeWorkbenchHost host;
  late TerminalViewService view;

  TerminalViewService make({bool runs = true}) {
    layout = IdeLayout();
    host = FakeWorkbenchHost();
    final service = TerminalViewService(
      terminals: runs
          ? TerminalService(
              root: '/project',
              backend: TerminalBackend(
                launch: fakeTerminalLaunch,
                start: FakePty.starter([]),
                detectProfiles: fakeTerminalProfiles,
              ),
            )
          : null,
      owned: true,
      host: host,
      layout: () => layout,
    );
    addTearDown(() {
      service.dispose();
      layout.dispose();
    });
    return service;
  }

  testWidgets('toggles the panel on TERMINAL, and makes terminals', (
    tester,
  ) async {
    view = make();
    view.toggle();
    expect(layout.panel, IdePanelTab.terminal);
    view.toggle();
    expect(layout.panel, isNull);

    view.create();
    await tester.pump();
    expect(view.terminals!.instances, hasLength(1));
    expect(layout.panel, IdePanelTab.terminal);
    expect(view.contextKey('terminalCount'), 1);
    expect(view.contextKey('terminalIsOpen'), isTrue);
    expect(view.contextKey('terminalProcessSupported'), isTrue);
    expect(view.contextKey('editorTextFocus'), isNull);
  });

  testWidgets('a background command shows in the terminal\'s place', (
    tester,
  ) async {
    view = make();
    var changes = 0;
    view.addListener(() => changes++);
    view.showTask('build');
    expect(view.task, 'build');
    expect(layout.panel, IdePanelTab.terminal);
    // The terminal shown again: the task goes.
    view.show();
    expect(view.task, isNull);
    expect(changes, 2);
  });

  testWidgets('the panel hides once the last terminal is gone', (tester) async {
    view = make();
    view.create();
    await tester.pump();
    expect(layout.panel, IdePanelTab.terminal);
    view.killAll();
    await tester.pump();
    expect(view.terminals!.instances, isEmpty);
    expect(layout.panel, isNull);
    expect(host.calls, contains('focusSoon'));
  });

  test('without terminals (the web), nothing to show', () {
    view = make(runs: false);
    view.show();
    expect(layout.panel, isNull);
    expect(view.contextKey('terminalProcessSupported'), isFalse);
    expect(view.running(childProcesses: false), isFalse);
  });
}
