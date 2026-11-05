import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/services/navigation_history.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/editor_status.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/l10n/app_localizations.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The editors alone, over a workspace and no text editor: opened,
/// selected, cycled and closed; a pane's control focused; the caret and
/// the status bar's entries for it.
void main() {
  late IdeWorkspace workspace;
  late FakeWorkbenchHost host;
  late EditorPaneRegistry panes;
  late EditorService editors;
  late NavigationHistoryService history;
  late WorkbenchServices services;
  var shown = 0;
  var workbenchFocused = 0;

  Future<void> setUpEditors(WidgetTester tester) async {
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({
        inRoot('a.txt'): 'a\nb',
        inRoot('b.txt'): 'b',
        inRoot('c.txt'): 'c',
      }),
    );
    host = FakeWorkbenchHost();
    panes = EditorPaneRegistry();
    shown = 0;
    workbenchFocused = 0;
    history = NavigationHistoryService(
      workspace: workspace,
      caret: () => editors.position,
      open: (location) => editors.openLocation(location, record: false),
      select: (doc) => editors.select(doc),
    );
    editors = EditorService(
      host: host,
      panes: panes,
      workspace: () => workspace,
      layout: () => workspace.layout,
      history: () => history,
      focusWorkbench: () => workbenchFocused++,
      onShowEditor: () => shown++,
    );
    services = WorkbenchServices()
      ..add(StatusbarService())
      ..add<WorkbenchHost>(host)
      ..add(workspace)
      ..add(editors);
    final status = EditorStatusContribution(services);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            host.context = context;
            return const SizedBox();
          },
        ),
      ),
    );
    addTearDown(() {
      status.dispose();
      services.remove<IdeWorkspace>(owned: false);
      services.dispose();
      history.dispose();
      panes.dispose();
      workspace.dispose();
    });
  }

  testWidgets('opened, cycled, selected by place', (tester) async {
    await setUpEditors(tester);
    await editors.open(inRoot('a.txt'));
    await editors.open(inRoot('b.txt'));
    await editors.open(inRoot('c.txt'));
    expect(workspace.active?.name, 'c.txt');
    expect(shown, 3);
    expect(editors.busy, isFalse);

    editors.cycle(1);
    await tester.pump();
    expect(workspace.active?.name, 'a.txt');
    editors.openAt(-1);
    await tester.pump();
    expect(workspace.active?.name, 'c.txt');
    editors.openAt(1);
    await tester.pump();
    expect(workspace.active?.name, 'b.txt');
  });

  testWidgets('closed: the history told, the keyboard to the workbench', (
    tester,
  ) async {
    await setUpEditors(tester);
    await editors.open(inRoot('a.txt'));
    await editors.open(inRoot('b.txt'));
    await editors.close(workspace.active!);
    expect(workspace.documents.map((doc) => doc.name), ['a.txt']);
    expect(history.canReopenClosed, isTrue);
    await editors.closeAll([...workspace.documents]);
    expect(workspace.documents, isEmpty);
    // The frame the window's rebuild draws.
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(workbenchFocused, isPositive);
  });

  testWidgets('a pane of its own: focused and scrolled through its control', (
    tester,
  ) async {
    await setUpEditors(tester);
    final control = _Control();
    panes.register(
      EditorPane(
        id: 'test',
        accepts: (doc) => doc.name == 'a.txt',
        build: (_, _) => const SizedBox(),
        control: (_) => control,
      ),
    );
    await editors.open(inRoot('a.txt'), line: 2, column: 3);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(control.calls, ['revealLine 2:3']);
    editors.focus();
    expect(control.calls.last, 'focus');
  });

  testWidgets('the caret: the status bar\'s line and column', (tester) async {
    await setUpEditors(tester);
    final statusbar = services.get<StatusbarService>();
    List<String> right() => [
      for (final item in statusbar.items(
        host.context!,
        StatusbarAlignment.right,
      ))
        item.text,
    ];
    // No document: no entries.
    expect(right(), isEmpty);
    await editors.open(inRoot('a.txt'));
    editors.positionChanged((
      position: const Position(2, 1),
      statusColumn: 1,
      selectionLength: 3,
      selectionLines: 2,
    ));
    expect(editors.position, const Position(2, 1));
    expect(right(), [
      'Ln 2, Col 1 (2 lines, 3 selected)',
      'Spaces: 4',
      'UTF-8',
      'LF',
      'Plain Text',
    ]);
    // Clicked: its command.
    statusbar.items(host.context!, StatusbarAlignment.right).first.onTap!();
    expect(host.calls.last, 'executeCommand workbench.action.gotoLine null');
  });
}

class _Control implements EditorPaneControl {
  final calls = <String>[];

  @override
  void focus() => calls.add('focus');

  @override
  void revealLine(int line, [int column = 1]) =>
      calls.add('revealLine $line:$column');
}
