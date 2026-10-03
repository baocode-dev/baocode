import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/composer/composer.dart';
import 'package:baocode/theme/app_theme.dart';

QuillController _controller(WidgetTester tester, int index) =>
    tester.widget<QuillEditor>(find.byType(QuillEditor).at(index)).controller;

void main() {
  testWidgets('the same agent\'s composer in two places (two windows): what '
      'is typed in one shows in the other', (tester) async {
    final session = ChatSession(historyCount: 0);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        localizationsDelegates: const [FlutterQuillLocalizations.delegate],
        home: Scaffold(
          body: Column(
            children: [
              for (var i = 0; i < 2; i++)
                Expanded(
                  child: ChatComposer(session: session, draft: session.draft),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    final first = _controller(tester, 0), second = _controller(tester, 1);
    first.replaceText(0, 0, 'hello', const TextSelection.collapsed(offset: 5));
    await tester.pump();
    expect(second.document.toPlainText(), 'hello\n');
    // Not the other's edit to undo there.
    expect(second.hasUndo, isFalse);

    second.replaceText(
      5,
      0,
      ' world',
      const TextSelection.collapsed(offset: 11),
    );
    await tester.pump();
    expect(first.document.toPlainText(), 'hello world\n');
    expect(
      Document.fromDelta(session.draft.content!).toPlainText(),
      'hello world\n',
    );

    second.clear();
    await tester.pump();
    expect(first.document.toPlainText(), '\n');
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  });
}
