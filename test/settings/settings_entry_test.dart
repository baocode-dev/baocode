import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:bao_editor/monaco/flutter/keybinding_entry.dart';
import 'package:bao_editor/monaco/vs/platform/theme/common/theme.dart' as vs;
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
import 'package:baocode/settings/pages/appearance_page.dart';
import 'package:baocode/settings/settings_dialog.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:baocode/workspace/workspace.dart';

final _mac = TargetPlatformVariant.only(TargetPlatform.macOS);

Future<Workspace> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // The app's keybindings, fresh for each test.
  KeybindingService.instance = KeybindingService();
  addTearDown(() => KeybindingService.instance = KeybindingService());
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  return workspace;
}

Future<void> _press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool meta = false,
}) async {
  if (meta) await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
  await tester.sendKeyEvent(key);
  if (meta) await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
  await tester.pumpAndSettle();
}

SettingsSection? _section(WidgetTester tester) {
  final dialog = find.byType(SettingsDialog);
  if (dialog.evaluate().isEmpty) return null;
  return tester.state<SettingsDialogState>(dialog).section;
}

double _chatLeft(WidgetTester tester) =>
    tester.getTopLeft(find.byType(ChatScreen)).dx;

void main() {
  testWidgets('⌘, opens the settings over the chat; Escape closes them', (
    tester,
  ) async {
    await _pumpApp(tester);
    expect(_section(tester), isNull);
    await _press(tester, LogicalKeyboardKey.comma, meta: true);
    expect(_section(tester), SettingsSection.general);
    expect(find.text('General'), findsWidgets);
    // Over the whole window, as Cursor's settings.
    expect(tester.getSize(find.byType(SettingsDialog)), const Size(1400, 900));

    await _press(tester, LogicalKeyboardKey.escape);
    expect(_section(tester), isNull);
  }, variant: _mac);

  testWidgets('⌘K ⌘S opens them on the keyboard shortcuts', (tester) async {
    await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.keyK, meta: true);
    expect(_section(tester), isNull);
    await _press(tester, LogicalKeyboardKey.keyS, meta: true);
    expect(_section(tester), SettingsSection.keyboard);
  }, variant: _mac);

  testWidgets('the sidebar gear and the menu bar\'s Preferences… open them', (
    tester,
  ) async {
    await _pumpApp(tester);
    final gear = find.descendant(
      of: find.byType(Sidebar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is SidebarIconButton && widget.icon == Codicons.settingsGear,
      ),
    );
    // Its label the title; its hover with the keys.
    expect(tester.widget<SidebarIconButton>(gear).tooltip, 'Settings');
    expect(
      find.descendant(
        of: gear,
        matching: find.byWidgetPredicate(
          (widget) => widget is IdeHover && widget.message == 'Settings (⌘,)',
        ),
      ),
      findsOneWidget,
    );
    await tester.tap(gear);
    await tester.pumpAndSettle();
    expect(_section(tester), SettingsSection.general);
    await _press(tester, LogicalKeyboardKey.escape);

    // What the app menu's Preferences… sends (MainFlutterWindow.swift).
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'baocode/window',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('menuCommand', openSettingsCommandId),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();
    expect(_section(tester), SettingsSection.general);
  }, variant: _mac);

  testWidgets('the chat runs its keybindings as the user set them', (
    tester,
  ) async {
    await _pumpApp(tester);
    final left = _chatLeft(tester);
    KeybindingService.instance.userEntries = const [
      KeybindingEntry(
        command: 'workbench.action.toggleSidebarVisibility',
        key: 'cmd+1',
      ),
      KeybindingEntry(command: '-workbench.action.toggleSidebarVisibility'),
    ];
    await _press(tester, LogicalKeyboardKey.keyB, meta: true);
    expect(_chatLeft(tester), left, reason: '⌘B is removed');
    await _press(tester, LogicalKeyboardKey.digit1, meta: true);
    expect(_chatLeft(tester), lessThan(left));
    await _press(tester, LogicalKeyboardKey.digit1, meta: true);
    expect(_chatLeft(tester), left);
  }, variant: _mac);

  testWidgets('a dialog over the chat keeps its keys', (tester) async {
    await _pumpApp(tester);
    final left = _chatLeft(tester);
    await _press(tester, LogicalKeyboardKey.comma, meta: true);
    await _press(tester, LogicalKeyboardKey.keyB, meta: true);
    await _press(tester, LogicalKeyboardKey.escape);
    expect(_chatLeft(tester), left);
  }, variant: _mac);

  testWidgets('the IDE has the settings\' commands', (tester) async {
    final workspace = await _pumpApp(tester);
    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    final commands = tester
        .widget<IdeWorkbench>(find.byType(IdeWorkbench))
        .commands;
    final keyboard = commands.firstWhere(
      (command) => command.id == openKeybindingsCommandId,
    );
    expect(keyboard.label, 'Open Keyboard Shortcuts');
    expect(keyboard.shortcutLabel(mac: true), '⌘K ⌘S');
    keyboard.run();
    await tester.pumpAndSettle();
    expect(_section(tester), SettingsSection.keyboard);
    await _press(tester, LogicalKeyboardKey.escape);
    commands.firstWhere((command) => command.id == openSettingsCommandId).run();
    await tester.pumpAndSettle();
    expect(_section(tester), SettingsSection.general);
  }, variant: _mac);

  testWidgets('the settings fill the window, find and switch pages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsDialog(
              context,
              pageBuilder: (context, section) => Text('page ${section.name}'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SettingsDialog)), const Size(700, 500));
    expect(find.text('page general'), findsOneWidget);
    // The pages listed in their groups' order.
    expect(
      tester.getTopLeft(find.text('Data Directory')).dy,
      greaterThan(tester.getTopLeft(find.text('Keyboard Shortcuts')).dy),
    );
    // The search keeps the pages it names.
    await tester.enterText(find.byType(TextField), 'data');
    await tester.pump();
    expect(find.text('Keyboard Shortcuts'), findsNothing);
    await tester.tap(find.text('Data Directory'));
    await tester.pumpAndSettle();
    expect(find.text('page dataDirectory'), findsOneWidget);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  test('every settings page is listed under one heading', () {
    expect([
      for (final category in SettingsCategory.values) ...category.sections,
    ], unorderedEquals(SettingsSection.values));
  });

  testWidgets('over the settings, ⌘K ⌘T shows the color theme\'s page and '
      '⌘K ⌘S the keyboard shortcuts\'', (tester) async {
    await _pumpApp(tester);
    await _press(tester, LogicalKeyboardKey.comma, meta: true);
    expect(_section(tester), SettingsSection.general);
    await _press(tester, LogicalKeyboardKey.keyK, meta: true);
    expect(_section(tester), SettingsSection.general);
    await _press(tester, LogicalKeyboardKey.keyT, meta: true);
    expect(_section(tester), SettingsSection.appearance);
    expect(find.text('Color Theme'), findsOneWidget);
    await _press(tester, LogicalKeyboardKey.keyK, meta: true);
    await _press(tester, LogicalKeyboardKey.keyS, meta: true);
    expect(_section(tester), SettingsSection.keyboard);
    // A second key that completes nothing does nothing.
    await _press(tester, LogicalKeyboardKey.keyK, meta: true);
    await _press(tester, LogicalKeyboardKey.keyQ, meta: true);
    expect(_section(tester), SettingsSection.keyboard);
  }, variant: _mac);

  testWidgets('so in the IDE\'s settings', (tester) async {
    final workspace = await _pumpApp(tester);
    workspace.layout = WorkspaceLayout.ide;
    await tester.pump();
    await tester.pump();
    await _press(tester, LogicalKeyboardKey.comma, meta: true);
    expect(_section(tester), SettingsSection.general);
    await _press(tester, LogicalKeyboardKey.keyK, meta: true);
    await _press(tester, LogicalKeyboardKey.keyT, meta: true);
    expect(_section(tester), SettingsSection.appearance);
    // The IDE's own theme picker stays shut under the dialog.
    expect(
      find.text('Select Color Theme (detect system color mode disabled)'),
      findsNothing,
    );
  }, variant: _mac);

  testWidgets('the settings\' search finds Appearance by "theme"', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSettingsDialog(
              context,
              pageBuilder: (context, section) => Text('page ${section.name}'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'theme');
    await tester.pump();
    expect(find.text('General'), findsNothing);
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('page appearance'), findsOneWidget);
  });

  testWidgets('Appearance lists the color themes by type, the current one '
      'ticked; one picked is applied and kept', (tester) async {
    // The whole page in the window: one cut off at the bottom, the menu
    // closing sends a semantics update the desktop engines reject.
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final themes = _FakeThemes();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppearanceSettingsPage(themes: themes, changes: themes),
        ),
      ),
    );
    expect(find.text('Dark 2026'), findsOneWidget);
    await tester.tap(find.text('Dark 2026'));
    await tester.pumpAndSettle();
    // Light first, the default first among them; then dark; then high
    // contrast.
    final order = [
      'Light 2026',
      'Solarized Light',
      'Monokai',
      'High Contrast',
    ].map((label) => tester.getTopLeft(find.text(label).last).dy).toList();
    expect(order, orderedEquals([...order]..sort()));
    await tester.tap(find.text('Monokai'));
    await tester.pumpAndSettle();
    expect(themes.applied, [('Monokai', false)]);
    expect(find.text('Monokai'), findsOneWidget);
  });
}

class _FakeThemes extends ChangeNotifier implements IdeColorThemeController {
  final List<(String, bool)> applied = [];

  @override
  String colorThemeId = 'Dark 2026';

  @override
  List<IdeColorThemeEntry> get colorThemes => const [
    IdeColorThemeEntry(
      id: 'Monokai',
      label: 'Monokai',
      type: vs.ColorScheme.dark,
    ),
    IdeColorThemeEntry(
      id: 'Solarized Light',
      label: 'Solarized Light',
      type: vs.ColorScheme.light,
    ),
    IdeColorThemeEntry(
      id: 'Dark 2026',
      label: 'Dark 2026',
      type: vs.ColorScheme.dark,
    ),
    IdeColorThemeEntry(
      id: 'High Contrast',
      label: 'High Contrast',
      type: vs.ColorScheme.highContrastDark,
    ),
    IdeColorThemeEntry(
      id: 'Light 2026',
      label: 'Light 2026',
      type: vs.ColorScheme.light,
    ),
  ];

  @override
  Future<void> setColorTheme(String id, {bool preview = false}) async {
    applied.add((id, preview));
    colorThemeId = id;
    notifyListeners();
  }
}
