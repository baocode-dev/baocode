import 'package:baocode/chat/chat_models.dart';
import 'package:baocode/chat/widgets/notice_row.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child, {double width = 600}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('zh'),
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: child),
    ),
  ),
);

void main() {
  testWidgets('compaction notice spans full width and centers short label', (
    tester,
  ) async {
    const notice = NoticeItem(
      NoticeKind.compaction,
      'Conversation compacted',
      compaction: CompactionNote(auto: false),
    );
    await tester.pumpWidget(_wrap(const NoticeRow(item: notice), width: 600));

    final rowBox = tester.getRect(find.byType(NoticeRow));
    final dividers = find.byType(Divider);
    expect(dividers, findsNWidgets(2));
    final leftDivider = tester.getRect(dividers.first);
    final rightDivider = tester.getRect(dividers.last);

    expect(rowBox.width, closeTo(600, 0.5));
    expect(leftDivider.left, closeTo(rowBox.left, 0.5));
    expect(rightDivider.right, closeTo(rowBox.right, 0.5));
    expect(leftDivider.width, closeTo(rightDivider.width, 1.0));
    expect(leftDivider.width, greaterThan(200));
  });

  testWidgets('compaction notice wraps long label cleanly in narrow width', (
    tester,
  ) async {
    const notice = NoticeItem(
      NoticeKind.compaction,
      'Conversation compacted early',
      compaction: CompactionNote(
        auto: true,
        tooLong: true,
        before: 220900,
        after: 18400,
        window: 400000,
      ),
    );
    await tester.pumpWidget(_wrap(const NoticeRow(item: notice), width: 300));

    expect(tester.takeException(), isNull);
    final rowBox = tester.getRect(find.byType(NoticeRow));
    final dividers = find.byType(Divider);
    final leftDivider = tester.getRect(dividers.first);
    final rightDivider = tester.getRect(dividers.last);
    expect(leftDivider.left, closeTo(rowBox.left, 0.5));
    expect(rightDivider.right, closeTo(rowBox.right, 0.5));
    expect(leftDivider.width, closeTo(rightDivider.width, 1.0));
  });
}
