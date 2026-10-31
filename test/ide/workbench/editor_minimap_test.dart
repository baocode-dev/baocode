import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/editor_minimap_setting.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_tab_bar.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_files.dart';

/// The code editors' minimap, one choice for every editor: settings.json's
/// `editor.minimap.enabled`, an editor tab's context menu, Alt+M.
void main() {
  tearDown(() => EditorMinimap.on.value = true);

  test('kept in settings.json, and read again as it changes there', () async {
    // (What is written is read back once the writes queued are done.)
    final temp = await Directory.systemTemp.createTemp('minimap');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'settings.json'))
      ..writeAsStringSync('{}');
    final settings = UserSettings(file.path);
    addTearDown(settings.dispose);
    await settings.load();
    EditorMinimap.follow(settings);
    expect(EditorMinimap.on.value, isTrue, reason: 'on by default');

    EditorMinimap.toggle();
    expect(EditorMinimap.on.value, isFalse);
    await settings.transform((_) => null);
    expect(settings['editor.minimap.enabled'], isFalse);

    EditorMinimap.set(true);
    await settings.transform((_) => null);
    expect(
      settings['editor.minimap.enabled'],
      isNull,
      reason: 'on: not written',
    );

    file.writeAsStringSync('{"editor.minimap.enabled": false}');
    await settings.load();
    expect(EditorMinimap.on.value, isFalse);
    file.writeAsStringSync('{"editor.minimap.enabled": true}');
    await settings.load();
    expect(EditorMinimap.on.value, isTrue);
  });

  Future<void> settleAssets(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
  }

  bool shown(WidgetTester tester) =>
      tester.widget<EditorSurface>(find.byType(EditorSurface)).showMinimap;

  testWidgets('Minimap in a tab\'s context menu, checked while it shows; '
      'Alt+M in the editor toggles it', (tester) async {
    await pumpWorkbench(
      tester,
      {'a.dart': 'void main() {}\n'},
      open: ['a.dart'],
      nativeEditor: true,
      // As the app's workbench has it.
      commands: [
        IdeCommand(
          id: EditorMinimap.commandId,
          label: 'Toggle Minimap',
          run: EditorMinimap.toggle,
        ),
      ],
    );
    await settleAssets(tester);
    expect(shown(tester), isTrue);

    await tester.tap(
      find.descendant(
        of: find.byType(IdeTabBar),
        matching: find.text('a.dart'),
      ),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Minimap'));
    await tester.pumpAndSettle();
    expect(EditorMinimap.on.value, isFalse);
    expect(shown(tester), isFalse);

    await tester.tap(find.byType(EditorSurface));
    await tester.pump();
    await chord(tester, LogicalKeyboardKey.keyM, alt: true);
    await tester.pump();
    expect(EditorMinimap.on.value, isTrue);
    expect(shown(tester), isTrue);
    await tester.pump(const Duration(milliseconds: 50));
  });
}
