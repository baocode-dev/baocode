import 'dart:io';

import 'package:bao_agent/bao_agent.dart' show defaultCoreSystemPrompt;
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/kernel/claude_code/claude_core_setting.dart';
import 'package:baocode/settings/pages/builtin_core_page.dart';
import 'package:baocode/settings/pages/settings_dropdown.dart';
import 'package:baocode/settings/settings_dialog.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory data;
  late UserSettings settings;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-builtin-core');
    settings = UserSettings(p.join(data.path, 'settings.json'));
    await settings.load();
  });

  tearDown(() async {
    ClaudeCore.current = () => ClaudeCore.fallback;
    SettingsDialogState.resetLayout();
    settings.dispose();
    await data.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100; i++) {
      if (done()) {
        await tester.pump();
        return;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    fail('timed out');
  }

  Future<void> showPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: BuiltinCoreSettingsPage(settings: settings)),
      ),
    );
    await tester.pump();
  }

  Future<void> chooseMode(WidgetTester tester, String label) async {
    await tester.tap(find.byType(SettingsDropdown));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'switches modes, edits and saves prompt, loads default, and resets',
    (tester) async {
      await showPage(tester);

      // Default mode hides the editor; Default System Prompt starts collapsed.
      expect(
        tester.widget<SettingsDropdown>(find.byType(SettingsDropdown)).current,
        'Default',
      );
      expect(find.byType(IdeInputBox), findsNothing);
      expect(
        find.textContaining('You are the coding agent built into BaoCode.'),
        findsNothing,
      );

      // Expand the read-only Default System Prompt reference.
      await tester.tap(find.text('Default System Prompt'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('You are the coding agent built into BaoCode.'),
        findsOneWidget,
      );
      expect(find.text('Copy'), findsOneWidget);

      // Switch to Append mode: editor appears without Load Default button.
      await chooseMode(tester, 'Append to Default');
      await settle(
        tester,
        () => settings[CoreSystemPrompt.modeKey] == 'append',
      );
      expect(find.byType(IdeInputBox), findsOneWidget);
      expect(find.text('Load Default'), findsNothing);
      expect(find.text('Reset to Default'), findsOneWidget);

      // Type prompt and unfocus to commit to settings.json.
      await tester.enterText(
        find.byType(IdeInputBox),
        'Always reply concisely.',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      await settle(
        tester,
        () => settings[CoreSystemPrompt.textKey] == 'Always reply concisely.',
      );

      // Switch to Replace mode: Load Default fills and persists the default prompt.
      await chooseMode(tester, 'Replace Default');
      await settle(
        tester,
        () => settings[CoreSystemPrompt.modeKey] == 'replace',
      );
      expect(find.text('Load Default'), findsOneWidget);
      await tester.tap(find.text('Load Default'));
      await tester.pump();
      await settle(
        tester,
        () => settings[CoreSystemPrompt.textKey] == defaultCoreSystemPrompt(),
      );

      // Reset to Default clears both keys and hides the editor.
      await tester.tap(find.text('Reset to Default'));
      await tester.pump();
      await settle(
        tester,
        () =>
            settings[CoreSystemPrompt.modeKey] == null &&
            settings[CoreSystemPrompt.textKey] == null,
      );
      expect(
        tester.widget<SettingsDropdown>(find.byType(SettingsDropdown)).current,
        'Default',
      );
      expect(find.byType(IdeInputBox), findsNothing);
    },
  );

  testWidgets('uncommitted edits are persisted when the page disposes', (
    tester,
  ) async {
    await tester.runAsync(
      () => settings.update(CoreSystemPrompt.modeKey, 'append'),
    );
    await showPage(tester);

    await tester.enterText(find.byType(IdeInputBox), 'Saved on close');
    await tester.pump();
    // Dispose without unfocusing first.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await settle(
      tester,
      () => settings[CoreSystemPrompt.textKey] == 'Saved on close',
    );
  });

  testWidgets(
    'Built-in Core menu item is always shown and searchable regardless of active core',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      ClaudeCore.current = () => ClaudeCore.cli;

      await tester.pumpWidget(
        MaterialApp(
          home: SettingsDialog(
            pageBuilder: (context, section) => Text('page ${section.name}'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Built-in Core'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'prompt');
      await tester.pump();
      expect(find.text('Built-in Core'), findsOneWidget);

      await tester.tap(find.text('Built-in Core'));
      await tester.pumpAndSettle();
      expect(find.text('page builtinCore'), findsOneWidget);
    },
  );
}
