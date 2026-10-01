import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/lsp_ui/problems_panel.dart';
import 'package:monad/ide/ide_layout.dart';
import 'package:monad/ide/ide_menu.dart';
import 'package:monad/ide/ide_quick_input.dart';
import 'package:monad/ide/ide_workbench.dart';
import 'package:monad/keybindings/keybinding_service.dart';
import 'package:monad/settings/user_settings.dart';
import 'package:monad/theme/codicons.dart';
import 'package:path/path.dart' as p;

import '../terminal/fake_pty.dart';
import 'fake_files.dart';

final _panel = find.byKey(const ValueKey('ide-panel'));

Finder _inPanel(Finder finder) => find.descendant(of: _panel, matching: finder);

/// The open menu's items.
final _menuItems = find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_MenuItem',
);

Finder _inMenu(String label) =>
    find.descendant(of: _menuItems, matching: find.text(label));

/// A quick pick's row: its label and description, or a separator's label.
Finder _inPick(String text) =>
    find.descendant(of: find.byType(IdeQuickInput), matching: find.text(text));

/// The panel's terminals start the shell VS Code's terminal profiles name:
/// the default one (`terminal.integrated.defaultProfile.<os>`), or one
/// picked from the New Terminal dropdown or Create New Terminal (With
/// Profile); Select Default Profile sets it in settings.json.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  // The profiles' settings are the system's (`.osx`); the fakes are macOS'.
  final macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  Future<void> run(WidgetTester tester, String id, [Object? args]) async {
    workbench(tester).commandsById[id]!.invoke(args);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// Lets a menu or quick pick close and run what was chosen.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens the New Terminal dropdown, after +.
  Future<void> openDropdown(WidgetTester tester) async {
    await tester.tap(_inPanel(find.byIcon(Codicons.chevronDown)));
    await settle(tester);
    expect(_menuItems, findsWidgets);
  }

  /// The open menu's actions, as `label` or `label (disabled)`.
  List<String> menuLabels(WidgetTester tester) => [
    for (final item in tester.widgetList(_menuItems))
      switch ((item as dynamic).action as IdeMenuAction) {
        final action when action.enabled => action.label,
        final action => '${action.label} (disabled)',
      },
  ];

  IdePanelTab? panel(WidgetTester tester) => tester
      .widget<IdeWorkbench>(find.byType(IdeWorkbench))
      .workspace
      .layout
      .panel;

  String launched(FakePty pty) =>
      [pty.launch!.executable, ...pty.launch!.arguments].join(' ');

  test("the layout's panel opens on TERMINAL first, PROBLEMS where there "
      'are no terminals, then on the tab it last showed', () {
    final layout = IdeLayout()..togglePanel();
    expect(layout.panel, IdePanelTab.terminal);
    layout.togglePanel();
    expect(layout.panel, isNull);

    final web = IdeLayout()..terminals = false;
    expect(web.lastPanel, IdePanelTab.problems);
    web.togglePanel();
    expect(web.panel, IdePanelTab.problems);

    layout
      ..panel = IdePanelTab.references
      ..togglePanel()
      ..togglePanel();
    expect(layout.panel, IdePanelTab.references);
  });

  testWidgets('Toggle Panel opens it on TERMINAL, as VS Code, whose '
      'terminal view is the default; without terminals, on PROBLEMS', (
    tester,
  ) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    await run(tester, 'workbench.action.togglePanel');
    expect(panel(tester), IdePanelTab.terminal);
    expect(_inPanel(find.text('TERMINAL')), findsOneWidget);
    expect(ptys, hasLength(1));
    // None set: the user's shell.
    expect(launched(ptys.single), '/bin/zsh -l');

    await tester.pumpWidget(const SizedBox());
    await pumpWorkbench(tester, {'a.txt': 'a'}, terminals: false);
    await run(tester, 'workbench.action.togglePanel');
    expect(panel(tester), IdePanelTab.problems);
  });

  testWidgets("+'s dropdown lists the settings' profiles, the default "
      'first, then Select Default Profile; one picked starts', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));
    await run(tester, 'workbench.action.terminal.toggleTerminal');
    expect(ptys, hasLength(1));

    // Beside +, a narrow chevron titled as upstream's.
    final chevron = _inPanel(find.byIcon(Codicons.chevronDown));
    final add = _inPanel(find.byIcon(Codicons.add));
    expect(tester.getRect(chevron).left, greaterThan(tester.getRect(add).left));
    expect(find.byTooltip('Launch Profile...'), findsOneWidget);

    await openDropdown(tester);
    // sh is /etc/shells' only: detected, not listed.
    // No settings.json here: no default to set.
    expect(menuLabels(tester), [
      'zsh (Default)',
      'bash',
      'fish',
      'Select Default Profile (disabled)',
    ]);

    await tester.tap(_inMenu('fish'));
    await settle(tester);
    expect(_menuItems, findsNothing);
    expect(ptys, hasLength(2));
    expect(launched(ptys.last), '/opt/homebrew/bin/fish -l');
    expect(ptys.last.launch!.workingDirectory, testRoot);
    expect(panel(tester), IdePanelTab.terminal);
  }, variant: macOS);

  testWidgets('Create New Terminal (With Profile) picks among them all, the '
      'default active; a keybinding names one', (tester) async {
    final ptys = <FakePty>[];
    await pumpWorkbench(tester, {
      'a.txt': 'a',
    }, startPty: FakePty.starter(ptys));

    await run(tester, 'workbench.action.terminal.newWithProfile');
    expect(find.byType(IdeQuickInput), findsOneWidget);
    expect(find.text('Select the terminal profile to create'), findsOneWidget);
    for (final row in [
      'profiles',
      'bash  /bin/bash -l',
      'zsh  /bin/zsh -l',
      'fish  /opt/homebrew/bin/fish -l',
      'detected',
      'sh  /bin/sh',
    ]) {
      expect(_inPick(row), findsOneWidget, reason: row);
    }
    await tester.tap(_inPick('bash  /bin/bash -l'));
    await settle(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(launched(ptys.single), '/bin/bash -l');
    expect(panel(tester), IdePanelTab.terminal);

    await run(tester, 'workbench.action.terminal.newWithProfile', {
      'profileName': 'sh',
    });
    await settle(tester);
    expect(find.byType(IdeQuickInput), findsNothing);
    expect(launched(ptys.last), '/bin/sh');

    // One not there: nothing.
    await run(tester, 'workbench.action.terminal.newWithProfile', {
      'profileName': 'nu',
    });
    await settle(tester);
    expect(ptys, hasLength(2));
  }, variant: macOS);

  testWidgets('Select Default Profile writes it to settings.json, where '
      'new terminals and the dropdown find it', (tester) async {
    final temp = Directory.systemTemp.createTempSync('monad-terminal-default');
    addTearDown(() => temp.deleteSync(recursive: true));
    final settings = UserSettings(
      p.join(temp.path, 'User', 'settings.json'),
      debounce: Duration.zero,
    );
    addTearDown(settings.dispose);
    File(settings.path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{\n  // mine\n}\n');
    settings.loadSync();
    final ptys = <FakePty>[];
    await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      startPty: FakePty.starter(ptys),
      settings: settings,
    );

    await run(tester, 'workbench.action.terminal.selectDefaultShell');
    expect(find.text('Select your default terminal profile'), findsOneWidget);
    await tester.tap(_inPick('bash  /bin/bash -l'));
    for (var i = 0; i < 100; i++) {
      if (settings['terminal.integrated.defaultProfile.osx'] != null) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(settings['terminal.integrated.defaultProfile.osx'], 'bash');
    expect(File(settings.path).readAsStringSync(), contains('// mine'));
    // Nothing started meanwhile.
    expect(ptys, isEmpty);

    await run(tester, 'workbench.action.terminal.new');
    await settle(tester);
    expect(launched(ptys.single), '/bin/bash -l');

    await openDropdown(tester);
    expect(menuLabels(tester), [
      'bash (Default)',
      'fish',
      'zsh',
      'Select Default Profile',
    ]);
    await tester.tap(_inMenu('Select Default Profile'));
    await settle(tester);
    expect(find.text('Select your default terminal profile'), findsOneWidget);
    expect(
      tester
          .widget<IdeQuickInput>(find.byType(IdeQuickInput))
          .pick!
          .activeItems!
          .single
          .label,
      'bash',
    );
  }, variant: macOS);
}
