import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_columns.dart';
import 'package:baocode/ide/ide_layout.dart';
import 'package:baocode/ide/lsp_ui/problems_panel.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/layout.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/views.dart';

import 'fake_host.dart';

/// The layout alone, over an IdeLayout and no window: the side bar's view,
/// the panel toggled and maximized, its context keys, its commands, and
/// what it keeps of the view state.
void main() {
  late IdeLayout parts;
  late FakeWorkbenchHost host;
  late LayoutService layout;
  late WorkbenchServices services;
  late LayoutContribution contribution;

  setUp(() {
    parts = IdeLayout();
    host = FakeWorkbenchHost();
    layout = LayoutService(host: host, layout: () => parts)..attach(parts);
    services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(ContextKeyService())
      ..add<WorkbenchHost>(host)
      ..add(layout);
    contribution = LayoutContribution(services);
  });

  tearDown(() {
    contribution.dispose();
    services.dispose();
    parts.dispose();
  });

  /// [id] run, if its precondition holds: whether it ran.
  bool run(String id) {
    final action = services.get<ActionRegistry>().byId(id)!;
    if (!(action.precondition?.call(services) ?? true)) return false;
    action.run(services, null);
    return true;
  }

  Object? key(String key) => services.get<ContextKeyService>().getValue(key);

  test('a view shown: the side bar with it, the keys following', () {
    var changes = 0;
    layout.addListener(() => changes++);
    parts.sidebar = false;
    expect(key('sideBarVisible'), isFalse);
    expect(key('activeViewlet'), isNull);

    expect(run('workbench.view.search'), isTrue);
    expect(layout.view, IdeSideView.search);
    expect(parts.sidebar, isTrue);
    expect(key('activeViewlet'), 'workbench.view.search');
    expect(key('explorerViewletVisible'), isFalse);
    expect(changes, greaterThanOrEqualTo(2));

    run('workbench.action.toggleSidebarVisibility');
    expect(parts.sidebar, isFalse);
  });

  test('the panel toggled, maximized, and restored as it hides', () {
    expect(layout.panel, isNull);
    run('workbench.action.togglePanel');
    expect(layout.panel, parts.lastPanel);
    expect(key('panelVisible'), isTrue);

    run('workbench.action.toggleMaximizedPanel');
    expect(key('panelMaximized'), isTrue);
    run('workbench.action.closePanel');
    expect(layout.panel, isNull);
    expect(layout.panelMaximized, isFalse);
    // Closed, Close Panel is not for it.
    expect(run('workbench.action.closePanel'), isFalse);

    // Maximized from hidden: shown so.
    run('workbench.action.toggleMaximizedPanel');
    expect(layout.panel, isNotNull);
    expect(layout.panelMaximized, isTrue);

    layout.togglePanelTab(IdePanelTab.problems);
    expect(layout.panel, IdePanelTab.problems);
    expect(key('activePanel'), 'workbench.panel.markers');
    layout.togglePanelTab(IdePanelTab.problems);
    expect(layout.panel, isNull);
  });

  testWidgets('a view or a panel given the keyboard as it shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          host.context = context;
          return const SizedBox();
        },
      ),
    );
    final focused = <String>[];
    final unregister = layout.focusViewWith(
      IdeSideView.explorer,
      () => focused.add('explorer'),
    );
    layout.focusPanelWith(IdePanelTab.terminal, () => focused.add('terminal'));

    layout.showView(IdeSideView.explorer);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(focused, ['explorer']);

    unregister();
    layout.showView(IdeSideView.explorer);
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(focused, ['explorer']);

    parts.panel = IdePanelTab.terminal;
    run('workbench.action.focusPanel');
    expect(focused, ['explorer', 'terminal']);
  });

  test('kept and restored as the view state had it', () {
    layout
      ..sidebarWidth = 312
      ..chatWidth = 420
      ..panelHeight = 200
      ..view = IdeSideView.sourceControl;
    final kept = <String, Object?>{};
    layout.saveState(kept);
    expect(kept, containsPair('sidebarWidth', 312.0));
    expect(kept, containsPair('chatWidth', 420.0));
    expect(kept, containsPair('panelHeight', 200.0));
    expect(kept, containsPair('view', 'sourceControl'));
    expect(kept.keys, containsAll(parts.toJson().keys));

    final restored = LayoutService(host: host, layout: () => parts)
      ..restoreState({
        ...kept,
        // Not a size: left as it was.
        'chatWidth': -1,
      });
    expect(restored.sidebarWidth, 312);
    expect(restored.chatWidth, IdeColumns.defaultChat);
    expect(restored.panelHeight, 200);
    expect(restored.view, IdeSideView.sourceControl);
    restored.dispose();
  });
}
