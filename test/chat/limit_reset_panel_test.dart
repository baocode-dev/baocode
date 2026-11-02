import 'package:baocode/chat/panels/limit_reset_panel.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required DateTime resetsAt,
    Locale locale = const Locale('en'),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 640,
              child: LimitResetPanel(resetsAt: resetsAt),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A time later today, half an hour on (clamped before midnight).
  DateTime laterToday() {
    final now = DateTime.now();
    final at = now.add(const Duration(minutes: 30));
    return at.day == now.day
        ? at
        : DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  String clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  testWidgets('says when the agent goes on, nothing to answer', (tester) async {
    final at = laterToday();
    await pump(tester, resetsAt: at);
    expect(
      find.text(
        'Usage limit reached · continues automatically after it resets at '
        '${clock(at)}',
      ),
      findsOneWidget,
    );
    expect(find.byType(GestureDetector), findsNothing);
    // Gone as the limit resets: no timer left behind.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('in Chinese', (tester) async {
    final at = laterToday();
    await pump(tester, resetsAt: at, locale: const Locale('zh'));
    expect(find.text('已达到用量上限，将在 ${clock(at)} 重置后自动继续'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('goes as the limit resets', (tester) async {
    await pump(
      tester,
      // Far enough off for a slow runner to show it first.
      resetsAt: DateTime.now().add(const Duration(seconds: 2)),
    );
    expect(find.textContaining('Usage limit reached'), findsOneWidget);
    // The clock read is the real one: past it, then the timer.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2100)),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(find.textContaining('Usage limit reached'), findsNothing);
  });

  test('the reset time: today, tomorrow, or with its date', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final now = DateTime(2026, 10, 13, 14, 2);
    expect(resetTime(DateTime(2026, 10, 13, 16, 30), l10n, now: now), '16:30');
    expect(
      resetTime(DateTime(2026, 10, 14, 3, 50), l10n, now: now),
      'tomorrow 03:50',
    );
    expect(resetTime(DateTime(2026, 10, 16, 9), l10n, now: now), '10/16 09:00');
  });
}
