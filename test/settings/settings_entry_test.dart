import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/ide/ide_hover.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/keybindings/default_keybindings.dart';
import 'package:baocode/keybindings/keybinding_entry.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/main.dart';
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
    expect(_section(tester), SettingsSection.language);
    expect(find.text('Region & Language'), findsWidgets);
    final size = tester.getSize(
      find
          .descendant(
            of: find.byType(SettingsDialog),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(size, const Size(SettingsDialog.maxWidth, SettingsDialog.maxHeight));

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
    expect(_section(tester), SettingsSection.language);
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
    expect(_section(tester), SettingsSection.language);
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
    expect(_section(tester), SettingsSection.language);
  }, variant: _mac);

  testWidgets('the dialog shrinks with the window, and switches pages', (
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
    final box = find
        .descendant(
          of: find.byType(SettingsDialog),
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(box), const Size(700 - 48, 500 - 48));
    expect(find.text('page language'), findsOneWidget);
    await tester.tap(find.text('Data Directory'));
    await tester.pumpAndSettle();
    expect(find.text('page dataDirectory'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });
}
