import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/chat/composer/composer_files.dart';

import 'fake_files.dart';

void main() {
  testWidgets(
    'Ctrl+L (⌘L) in the editor puts the lines selected in the '
    'chat, shown; with none, only shows it',
    (tester) async {
      final mac = defaultTargetPlatform == TargetPlatform.macOS;
      Future<void> addSelection() async {
        if (!mac) {
          return chord(tester, LogicalKeyboardKey.keyL, control: true);
        }
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      final added = <List<CodeReference>>[];
      await pumpWorkbench(
        tester,
        {'a.dart': 'one\ntwo\nthree\n'},
        open: ['a.dart'],
        nativeEditor: true,
        onAddCodeToChat: added.add,
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(Duration.zero));
        await tester.pump();
      }
      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      final controller = tester
          .widget<EditorSurface>(find.byType(EditorSurface))
          .controller;
      controller.select(4, 13);
      await tester.pump();

      await addSelection();
      expect(added, [
        [
          CodeReference(
            path: inRoot('a.dart'),
            start: 2,
            end: 3,
            code: 'two\nthree',
          ),
        ],
      ]);
      expect(find.byKey(chatKey), findsOneWidget);

      await tester.tap(find.byType(EditorSurface));
      await tester.pump();
      controller.select(1, 1);
      await tester.pump();
      await addSelection();
      expect(added, hasLength(2));
      expect(added.last, isEmpty);
      // The editor's coloring, done.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    },
    variant: TargetPlatformVariant({
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
}
