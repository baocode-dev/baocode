import 'dart:async';

import 'package:baocode/chat/widgets/inline_rename_field.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/theme/codicons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<List<String?>> pump(
    WidgetTester tester, {
    List<String> suggestions = const [],
    Future<String?> Function()? onSummarize,
  }) async {
    final done = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              child: InlineRenameField(
                initial: 'Current',
                suggestions: suggestions,
                onSummarize: onSummarize,
                onDone: done.add,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return done;
  }

  String text(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('↓ lists what was asked under it, the current title aside; '
      'not by itself, nor by ↑', (tester) async {
    await pump(tester, suggestions: ['Current', 'Fix login', 'Add tests']);
    expect(find.text('Fix login'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('Fix login'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Fix login'), findsOneWidget);
    expect(find.text('Add tests'), findsOneWidget);
    // Only the field's.
    expect(find.text('Current'), findsOneWidget);
  });

  testWidgets('↑ and ↓ go through the list, Enter puts the one picked in '
      'the field and another saves it', (tester) async {
    final done = await pump(tester, suggestions: ['Fix login', 'Add tests']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(text(tester), 'Add tests');
    expect(done, isEmpty);
    expect(find.text('Fix login'), findsNothing);
    // Not the list's: the field's, which submits it.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(done, ['Add tests']);
  });

  testWidgets('typing filters the list, and opens none', (tester) async {
    await pump(tester, suggestions: ['Fix login', 'Add tests']);
    await tester.enterText(find.byType(TextField), 'tes');
    await tester.pump();
    expect(find.text('Add tests'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Add tests'), findsOneWidget);
    expect(find.text('Fix login'), findsNothing);
  });

  testWidgets('a click on one puts it in the field', (tester) async {
    final done = await pump(tester, suggestions: ['Fix login']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.tap(find.text('Fix login'));
    await tester.pump();
    expect(text(tester), 'Fix login');
    expect(done, isEmpty);
  });

  testWidgets('the button at its end puts a title summed up in the field, '
      'with the field kept', (tester) async {
    final summary = Completer<String?>();
    final done = await pump(tester, onSummarize: () => summary.future);
    expect(find.byIcon(Codicons.sparkle), findsOneWidget);
    await tester.tap(find.byIcon(Codicons.sparkle));
    await tester.pump();
    expect(find.byIcon(Codicons.loading), findsOneWidget);
    summary.complete('Login fix');
    await tester.pump();
    expect(text(tester), 'Login fix');
    expect(done, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(done, ['Login fix']);
  });

  testWidgets('it says when no title could be had', (tester) async {
    await pump(tester, onSummarize: () async => null);
    await tester.tap(find.byIcon(Codicons.sparkle));
    await tester.pump();
    expect(find.byIcon(Codicons.warning), findsOneWidget);
    expect(text(tester), 'Current');
  });

  testWidgets('without suggestions, no list shows', (tester) async {
    await pump(tester, onSummarize: () async => null);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byIcon(Codicons.history), findsNothing);
  });

  testWidgets('Esc cancels, the list open or not', (tester) async {
    final done = await pump(tester, suggestions: ['Fix login']);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(done, [null]);
  });
}
