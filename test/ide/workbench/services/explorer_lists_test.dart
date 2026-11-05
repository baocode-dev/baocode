import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_list.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/explorer.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/services/lists.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/explorer.dart';
import 'package:baocode/ide/workbench/contributions/lists.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/views.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The explorer and the lists alone: a file revealed, the panes, the tree
/// following the workspace; `list.*` in the list with the keyboard.
void main() {
  late FakeWorkbenchHost host;
  late WorkbenchServices services;
  late ExplorerService explorer;
  late IdeWorkspace workspace;

  void setUpServices() {
    host = FakeWorkbenchHost();
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('src/a.dart'): 'a', inRoot('b.dart'): 'b'}),
    );
    explorer = ExplorerService(host: host, settings: () => null);
    services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(ContextKeyService())
      ..add<WorkbenchHost>(host)
      ..add(ListService())
      ..add(LayoutService(host: host, layout: () => workspace.layout))
      ..add(explorer)
      ..add(workspace);
    final contributions = [
      ListsContribution(services),
      ExplorerContribution(services),
    ];
    explorer.attach(workspace);
    addTearDown(() {
      disposeContributions(contributions);
      services.remove<IdeWorkspace>(owned: false);
      services.dispose();
      workspace.dispose();
    });
  }

  testWidgets('a file revealed: the explorer shown, its folder open', (
    tester,
  ) async {
    setUpServices();
    var changes = 0;
    explorer.addListener(() => changes++);
    explorer.togglePane('folder');
    expect(explorer.panes, isEmpty);
    expect(changes, 1);

    host.shown = IdeSideView.search;
    explorer.reveal(inRoot('src/a.dart'));
    expect(host.shown, IdeSideView.explorer);
    expect(explorer.panes, {'folder'});
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(explorer.controller.selected, inRoot('src/a.dart'));

    // Show Outline: its pane opened too.
    services.get<ActionRegistry>().byId('outline.focus')!.run(services, null);
    expect(explorer.panes, {'folder', 'outline'});

    // The tree's own commands wait for it to show.
    final keys = services.get<ContextKeyService>();
    expect(keys.getValue('filesExplorerFocus'), isFalse);
    expect(
      services.get<ActionRegistry>().byId('renameFile')!.precondition!(
        services,
      ),
      isFalse,
    );
  });

  testWidgets('another workspace: the tree and the index follow it', (
    tester,
  ) async {
    setUpServices();
    final first = explorer.controller;
    explorer.detach();
    final other = IdeWorkspace(
      inRoot('src'),
      files: TreeFiles({inRoot('src/a.dart'): 'a'}),
    );
    addTearDown(other.dispose);
    explorer.attach(other);
    expect(explorer.controller, isNot(same(first)));
    expect(explorer.controller.root, inRoot('src'));
  });

  testWidgets('list.* moves in the list with the keyboard', (tester) async {
    setUpServices();
    final keys = services.get<ContextKeyService>();
    final actions = services.get<ActionRegistry>();
    bool enabled(String id) => actions.byId(id)!.precondition!(services);
    expect(keys.getValue('listFocus'), isFalse);
    expect(enabled('list.focusDown'), isFalse);

    final list = GlobalKey<_ListState>();
    await tester.pumpWidget(_List(key: list));
    list.currentState!.focus.requestFocus();
    await tester.pump();
    expect(keys.getValue('listFocus'), isTrue);
    expect(keys.getValue('listSupportsMultiselect'), isFalse);
    expect(enabled('list.selectAll'), isFalse);

    actions.byId('list.focusDown')!.run(services, null);
    expect(list.currentState!.focused, 0);
    actions.byId('list.focusDown')!.run(services, 2);
    expect(list.currentState!.focused, 2);
    actions.byId('list.focusLast')!.run(services, null);
    expect(list.currentState!.focused, 4);
  });
}

class _List extends StatefulWidget {
  const _List({super.key});

  @override
  State<_List> createState() => _ListState();
}

class _ListState extends State<_List> with IdeKeyboardList<_List> {
  final focus = FocusNode();
  int focused = -1;

  @override
  bool get listHasFocus => focus.hasFocus;

  @override
  int get listLength => 5;

  @override
  int get listFocusedIndex => focused;

  @override
  void listFocusAt(int index) => setState(() => focused = index);

  @override
  void listSelect() {}

  @override
  void dispose() {
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: focus, child: const SizedBox());
}
