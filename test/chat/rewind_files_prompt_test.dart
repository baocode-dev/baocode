import 'package:baocode/chat/review/change_review.dart';
import 'package:baocode/chat/rewind_files_prompt.dart';
import 'package:baocode/chat/rewind_files_setting.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RewindFile _file(String name, RewindOutcome outcome) =>
    RewindFile('/p/$name', outcome, name: name, created: false);

void main() {
  tearDown(() => RewindFilesSetting.current = () => RewindFilesSetting.ask);

  test('tells what goes back, what is kept of others, what cannot', () {
    final detail = rewindFilesDetail(englishLocalizations, [
      _file('a.txt', RewindOutcome.restore),
      _file('b.txt', RewindOutcome.merge),
      _file('c.txt', RewindOutcome.conflict),
    ]);
    expect(
      detail,
      'The agent changed 2 files after this message:\n'
      '  a.txt\n'
      '  b.txt\n'
      '1 of them was also changed elsewhere since: those changes are kept.\n'
      '\n'
      "1 file can't be undone cleanly and will stay as it is:\n"
      '  c.txt\n'
      '\n'
      "What commands changed (Bash) isn't tracked and stays.",
    );
  });

  test('names the first files, counts the rest', () {
    final detail = rewindFilesDetail(englishLocalizations, [
      for (var i = 0; i < 10; i++) _file('f$i', RewindOutcome.restore),
    ]);
    expect(detail, contains('  f7\n  …and 2 more\n'));
    expect(detail, isNot(contains('f8')));
  });

  testWidgets('asks only when there are files and the setting asks', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    final context = tester.element(find.byType(SizedBox));
    final some = [_file('a.txt', RewindOutcome.restore)];

    expect(await askRewindFiles(context, () async => const []), isFalse);
    RewindFilesSetting.current = () => RewindFilesSetting.revert;
    expect(await askRewindFiles(context, () async => some), isTrue);
    RewindFilesSetting.current = () => RewindFilesSetting.keep;
    expect(await askRewindFiles(context, () async => some), isFalse);

    RewindFilesSetting.current = () => RewindFilesSetting.ask;
    RewindFilesSetting? written;
    RewindFilesSetting.write = (value) => written = value;
    addTearDown(() => RewindFilesSetting.write = null);
    final asked = askRewindFiles(context, () async => some);
    await tester.pumpAndSettle();
    expect(
      find.text('Undo the file changes made after this message?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Remember my choice'));
    await tester.tap(find.text('Undo and Send'));
    await tester.pumpAndSettle();
    expect(await asked, isTrue);
    expect(written, RewindFilesSetting.revert);
  });
}
