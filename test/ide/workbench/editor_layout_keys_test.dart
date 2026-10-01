import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import 'fake_files.dart';

/// The editors' and the layout's commands beyond the first ones (VS Code's
/// editorActions.ts, layoutActions.ts): the recently used editors, Go to
/// Last Edit Location, the panel maximized, the parts focused.
void main() {
  const files = {'a.dart': 'a\n', 'b.dart': 'b\n', 'c.dart': 'c\n'};

  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  Future<void> run(WidgetTester tester, String id) async {
    workbench(tester).commands
        .firstWhere((command) => command.id == id)
        .invoke();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('Open Next / Previous Recently Used Editor walk one stack', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart', 'c.dart'],
    );
    // By recent use: c, b, a.
    await run(tester, 'workbench.action.openPreviousRecentlyUsedEditor');
    expect(workspace.active!.path, inRoot('b.dart'));
    await run(tester, 'workbench.action.openPreviousRecentlyUsedEditor');
    expect(workspace.active!.path, inRoot('a.dart'));
    // The stack stays while they run: its end stays the end.
    await run(tester, 'workbench.action.openPreviousRecentlyUsedEditor');
    expect(workspace.active!.path, inRoot('a.dart'));
    await run(tester, 'workbench.action.openNextRecentlyUsedEditor');
    expect(workspace.active!.path, inRoot('b.dart'));
    await run(tester, 'workbench.action.openNextRecentlyUsedEditorInGroup');
    expect(workspace.active!.path, inRoot('c.dart'));
    // Another editor to the front starts it again: b, c, a.
    await chord(tester, LogicalKeyboardKey.digit2, alt: true);
    expect(workspace.active!.path, inRoot('b.dart'));
    await run(tester, 'workbench.action.openPreviousRecentlyUsedEditor');
    expect(workspace.active!.path, inRoot('c.dart'));
  });

  testWidgets('Ctrl+K Ctrl+Q goes to the last edit; Go Previous', (
    tester,
  ) async {
    final workspace = await pumpWorkbench(
      tester,
      files,
      open: ['a.dart', 'b.dart'],
    );
    final state = workbench(tester);
    bool enabled(String id) =>
        state.commands.firstWhere((command) => command.id == id).enabled;
    expect(enabled('workbench.action.navigateToLastEditLocation'), isFalse);
    workspace.documents.first.model.replaceText('a\nedited\n');
    await tester.pump();
    expect(enabled('workbench.action.navigateToLastEditLocation'), isTrue);
    expect(workspace.active!.path, inRoot('b.dart'));
    await chord(tester, LogicalKeyboardKey.keyK, control: true);
    await chord(tester, LogicalKeyboardKey.keyQ, control: true);
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
    // Go Previous goes back to where that came from, and again returns.
    await run(tester, 'workbench.action.navigateLast');
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('b.dart'));
    await run(tester, 'workbench.action.navigateLast');
    await tester.pumpAndSettle();
    expect(workspace.active!.path, inRoot('a.dart'));
  });

  testWidgets('the panel maximized, focused and hidden; the side bar '
      'focused and hidden', (tester) async {
    await pumpWorkbench(tester, files, open: ['a.dart']);
    final state = workbench(tester);
    expect(state.keyContext('panelVisible'), isFalse);
    await run(tester, 'workbench.action.toggleMaximizedPanel');
    expect(state.keyContext('panelVisible'), isTrue);
    expect(state.keyContext('panelMaximized'), isTrue);
    final panel = find.byKey(const ValueKey('ide-panel'));
    final maximized = tester.getSize(panel).height;
    await run(tester, 'workbench.action.toggleMaximizedPanel');
    expect(state.keyContext('panelMaximized'), isFalse);
    expect(tester.getSize(panel).height, lessThan(maximized));
    await run(tester, 'workbench.action.toggleMaximizedPanel');
    await run(tester, 'workbench.action.closePanel');
    expect(state.keyContext('panelVisible'), isFalse);
    // Shown again, it is not maximized.
    await run(tester, 'workbench.action.togglePanel');
    expect(state.keyContext('panelMaximized'), isFalse);
    await run(tester, 'workbench.action.closePanel');

    // Ctrl+0: the side bar's view; Ctrl+1: the editor.
    await chord(tester, LogicalKeyboardKey.digit0, control: true);
    await tester.pump();
    expect(state.keyContext('sideBarFocus'), isTrue);
    expect(state.keyContext('explorerViewletFocus'), isTrue);
    expect(state.keyContext('focusedView'), 'workbench.explorer.fileView');
    expect(state.keyContext('activeViewlet'), 'workbench.view.explorer');
    await chord(tester, LogicalKeyboardKey.digit1, control: true);
    await tester.pump();
    expect(state.keyContext('sideBarFocus'), isFalse);
    expect(state.keyContext('editorTextFocus'), isTrue);
    await run(tester, 'workbench.action.closeSidebar');
    expect(find.byType(IdeExplorer), findsNothing);
    expect(state.keyContext('sideBarVisible'), isFalse);
    expect(state.keyContext('activeViewlet'), isNull);
    await run(tester, 'workbench.action.closeAuxiliaryBar');
    expect(state.keyContext('auxiliaryBarVisible'), isFalse);
  });

  testWidgets('Ctrl+Alt+I (⌃⌘I) goes back to the chat window, as it came', (
    tester,
  ) async {
    var backs = 0;
    await pumpWorkbench(tester, files, open: ['a.dart'], onBack: () => backs++);
    expect(workbench(tester).keyContext('ideMode'), isTrue);
    await chord(tester, LogicalKeyboardKey.keyI, control: true, alt: true);
    await tester.pumpAndSettle();
    expect(backs, 1);

    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(backs, 2);
    debugDefaultTargetPlatformOverride = null;
  });
}
