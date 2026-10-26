import 'dart:io';

import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:bao_editor/monaco/flutter/editor_surface_controller.dart';
import 'package:baocode/ide/editor_word_wrap.dart';
import 'package:baocode/ide/ide_code_editor.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/settings/user_settings.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Word wrap, one choice for every editor (#203): settings.json's
/// `editor.wordWrap`, an editor's context menu, Alt+Z.
void main() {
  tearDown(() => EditorWordWrap.on.value = false);

  test('kept in settings.json, and read again as it changes there', () async {
    // (What is written is read back once the writes queued are done.)
    final temp = await Directory.systemTemp.createTemp('word_wrap');
    addTearDown(() => temp.delete(recursive: true));
    final file = File(p.join(temp.path, 'settings.json'))
      ..writeAsStringSync('{"editor.wordWrap": "on"}');
    final settings = UserSettings(file.path);
    addTearDown(settings.dispose);
    await settings.load();
    EditorWordWrap.follow(settings);
    expect(EditorWordWrap.on.value, isTrue);

    EditorWordWrap.toggle();
    expect(EditorWordWrap.on.value, isFalse);
    await settings.transform((_) => null);
    expect(settings['editor.wordWrap'], isNull, reason: 'off: not written');

    EditorWordWrap.set(true);
    await settings.transform((_) => null);
    expect(settings['editor.wordWrap'], 'on');

    file.writeAsStringSync('{"editor.wordWrap": "off"}');
    await settings.load();
    expect(EditorWordWrap.on.value, isFalse);
    file.writeAsStringSync('{"editor.wordWrap": "bounded"}');
    await settings.load();
    expect(EditorWordWrap.on.value, isTrue);
  });

  Future<void> show(WidgetTester tester) async {
    final controller = EditorSurfaceController(
      document: EditorDocumentModel(List.filled(80, 'word').join(' ')),
    );
    addTearDown(controller.dispose);
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeNotificationsScope(
            notifications: IdeNotifications(),
            child: IdeCodeEditor(
              controller: controller,
              path: '/w/a.txt',
              focusNode: focus,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    focus.requestFocus();
    await tester.pump();
  }

  bool wraps(WidgetTester tester) =>
      tester.widget<EditorSurface>(find.byType(EditorSurface)).wrap;

  testWidgets('Word Wrap in the context menu, checked while it wraps', (
    tester,
  ) async {
    await show(tester);
    expect(wraps(tester), isFalse);
    Future<void> rightClick() async {
      await tester.tapAt(
        tester.getTopLeft(find.byType(EditorSurface)) + const Offset(80, 8),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
    }

    await rightClick();
    await tester.tap(find.text('Word Wrap'));
    await tester.pumpAndSettle();
    expect(EditorWordWrap.on.value, isTrue);
    expect(wraps(tester), isTrue);
  });

  testWidgets('Alt+Z toggles it', (tester) async {
    await show(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(EditorWordWrap.on.value, isTrue);
    expect(wraps(tester), isTrue);
  });
}
