import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/ide_find_widget.dart';
import 'package:monad/ide/ide_hover.dart';
import 'package:monad/ide/ide_panes.dart';
import 'package:monad/ide/ide_tab_bar.dart';
import 'package:monad/ide/ide_workbench.dart';
import 'package:monad/ide/terminal/terminal_view.dart';
import 'package:monad/keybindings/keybinding_entry.dart';
import 'package:monad/keybindings/keybinding_service.dart';

import '../lsp_ui/fake_language_features.dart';
import '../terminal/fake_pty.dart';
import 'fake_files.dart';

/// The workbench's buttons that do what a command does have its keybinding
/// in their tooltips, as VS Code's action bars title their items
/// (`Toggle Primary Side Bar (⌘B)`), and follow the keybindings as they
/// change (a keymap, `keybindings.json`).
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  Future<void> run(WidgetTester tester, String id) async {
    workbench(tester).commandsById[id]!.invoke();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// A mouse over [target]'s center, to move on with.
  Future<TestGesture> hover(WidgetTester tester, Finder target) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(target));
    await tester.pump();
    return mouse;
  }

  /// The explorer's folder pane: its header hovered, its actions show.
  Finder folder() => find.descendant(
    of: find.byType(IdePaneContainer),
    matching: find.text('project'),
  );

  void expectTooltips(List<String> tooltips) {
    for (final tooltip in tooltips) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
  }

  testWidgets(
    'macOS: the title bar, the activity bar, the explorer and the status '
    'bar',
    (tester) async {
      await pumpWorkbench(
        tester,
        {'a.dart': 'a', 'b.dart': 'b'},
        open: ['a.dart', 'b.dart'],
        languages: FakeLanguageFeatures(),
      );
      final mouse = await hover(tester, folder());
      expectTooltips([
        // The title bar.
        'Toggle Primary Side Bar (⌘B)',
        'Toggle Panel (⌃`)',
        'Toggle Chat (⌘J)',
        'Search project (⌘P)',
        'Back to chat (⌃⌘I)',
        // The activity bar.
        'Explorer (⇧⌘E)',
        'Search files (⇧⌘F)',
        'Source Control (⌃⇧G)',
        'Extensions (⇧⌘X)',
        // The explorer's commands have no keys by default.
        'New File...',
        'New Folder...',
        'Refresh Explorer',
        'Collapse Folders in Explorer',
        // The status bar.
        'No Problems (⇧⌘M)',
        'Go to Line/Column (⌃G)',
      ]);

      // Close Editor's keys on the active tab's close button only.
      expect(find.byTooltip('Close b.dart (⌘W)'), findsOneWidget);
      await mouse.moveTo(
        tester.getCenter(
          find.descendant(
            of: find.byType(IdeTabBar),
            matching: find.text('a.dart'),
          ),
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Close a.dart'), findsOneWidget);
    },
    variant: macOS,
  );

  testWidgets('macOS: the hover shows the title and the keys', (tester) async {
    await pumpWorkbench(tester, {'a.dart': 'a'});
    await hover(tester, find.byTooltip('Toggle Primary Side Bar (⌘B)'));
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 150));
    expect(
      find.descendant(
        of: find.byType(IdeHoverBox),
        matching: find.text('Toggle Primary Side Bar (⌘B)'),
      ),
      findsOneWidget,
    );
  }, variant: macOS);

  testWidgets('macOS: the find widget\'s buttons and toggles', (tester) async {
    await pumpWorkbench(tester, {'a.dart': 'alpha alpha'}, open: ['a.dart']);
    await run(tester, 'editor.action.startFindReplaceAction');
    expect(find.byType(IdeFindWidget), findsOneWidget);
    expectTooltips([
      'Match case (⌥⌘C)',
      'Whole word (⌥⌘W)',
      'Regular expression (⌥⌘R)',
      'Previous match (⇧Enter)',
      'Next match (Enter)',
      'Close find (Escape)',
      'Replace match (Enter)',
      'Replace all (⌘Enter)',
      // Upstream's has no keybinding.
      'Toggle replace',
    ]);
  }, variant: macOS);

  testWidgets('macOS: the panel\'s tabs and actions', (tester) async {
    await pumpWorkbench(
      tester,
      {'a.dart': 'a'},
      open: ['a.dart'],
      startPty: FakePty.starter([]),
    );
    await run(tester, 'workbench.action.terminal.toggleTerminal');
    expect(find.byType(TerminalView), findsOneWidget);
    expectTooltips([
      'Problems (⇧⌘M)',
      'References',
      'Terminal (⌃`)',
      'New Terminal (⌃⇧`)',
      'Kill Terminal',
      'Close Panel',
    ]);
  }, variant: macOS);

  testWidgets('off macOS, the keys are Ctrl+…', (tester) async {
    await pumpWorkbench(
      tester,
      {'a.dart': 'a'},
      open: ['a.dart'],
      startPty: FakePty.starter([]),
    );
    await run(tester, 'actions.find');
    await run(tester, 'workbench.action.terminal.toggleTerminal');
    expectTooltips([
      'Toggle Primary Side Bar (Ctrl+B)',
      'Search project (Ctrl+P)',
      'Back to chat (Ctrl+Alt+I)',
      'Explorer (Ctrl+Shift+E)',
      'Search files (Ctrl+Shift+F)',
      'Source Control (Ctrl+Shift+G)',
      'Close a.dart (Ctrl+W)',
      'Go to Line/Column (Ctrl+G)',
      'Match case (Alt+C)',
      'Previous match (Shift+Enter)',
      'Problems (Ctrl+Shift+M)',
      'Terminal (Ctrl+`)',
      'New Terminal (Ctrl+Shift+`)',
    ]);
  });

  testWidgets('the tooltips follow the user\'s keybindings and the keymap', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.dart': 'a'}, open: ['a.dart']);
    await hover(tester, folder());
    expect(find.byTooltip('New File...'), findsOneWidget);

    // keybindings.json: a key for New File, another for Show Explorer, and
    // Close Editor's Ctrl+W removed: its Ctrl+F4 shows.
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(key: 'ctrl+alt+n', command: 'explorer.newFile'),
      KeybindingEntry(key: 'ctrl+alt+e', command: 'workbench.view.explorer'),
      KeybindingEntry(
        key: 'ctrl+w',
        command: '-workbench.action.closeActiveEditor',
      ),
    ];
    await tester.pump();
    expectTooltips([
      'New File... (Ctrl+Alt+N)',
      'Explorer (Ctrl+Alt+E)',
      'Close a.dart (Ctrl+F4)',
    ]);
    expect(find.byTooltip('Explorer (Ctrl+Shift+E)'), findsNothing);
    expect(find.byTooltip('Close a.dart (Ctrl+W)'), findsNothing);

    // A keymap's.
    KeybindingService.instance.setKeymap(
      'test',
      entries: const [
        KeybindingEntry(key: 'ctrl+e', command: 'workbench.action.quickOpen'),
        KeybindingEntry(
          key: 'ctrl+alt+b',
          command: 'workbench.action.toggleSidebarVisibility',
        ),
      ],
    );
    await tester.pump();
    expectTooltips([
      'Search project (Ctrl+E)',
      'Toggle Primary Side Bar (Ctrl+Alt+B)',
    ]);

    // Back to the defaults.
    KeybindingService.instance
      ..setKeymap(null)
      ..userEntries = const [];
    await tester.pump();
    expectTooltips([
      'New File...',
      'Explorer (Ctrl+Shift+E)',
      'Close a.dart (Ctrl+W)',
      'Search project (Ctrl+P)',
      'Toggle Primary Side Bar (Ctrl+B)',
    ]);
  });

  testWidgets('a tab bar\'s More Actions has no command, so no keys', (
    tester,
  ) async {
    await pumpWorkbench(tester, {'a.dart': 'a'}, open: ['a.dart']);
    expect(
      find.descendant(
        of: find.byType(IdeTabBar),
        matching: find.byTooltip('More Actions…'),
      ),
      findsOneWidget,
    );
  });
}
