import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_notifications.dart';
import 'package:baocode/theme/codicons.dart';

import 'fake_files.dart';

void main() {
  group('notifications', () {
    // Disposed by each test, as the binding checks for timers before
    // tear-downs run.
    late IdeNotifications notifications;

    setUp(() => notifications = IdeNotifications());

    void shown() {}

    testWidgets('a toast goes after its timeout, and stays in the center', (
      tester,
    ) async {
      notifications.addListener(shown);
      final info = notifications.notify(IdeSeverity.info, 'Indexed');
      final error = notifications.notify(IdeSeverity.error, 'Failed');
      expect(notifications.toasts, [info, error]);
      expect(notifications.unread, 2);

      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toasts, [error]);
      await tester.pump(const Duration(seconds: 5));
      expect(notifications.toasts, isEmpty);
      expect(notifications.notifications, [error, info]);
      notifications.dispose();
    });

    testWidgets('a silent one is only in the center, unread', (tester) async {
      final quiet = notifications.notify(
        IdeSeverity.info,
        'Install the server?',
        sticky: true,
        silent: true,
      );
      expect(notifications.toasts, isEmpty);
      expect(notifications.notifications, [quiet]);
      expect(notifications.unread, 1);
      notifications.dispose();
    });

    testWidgets('toasts time out only while a workbench shows them', (
      tester,
    ) async {
      final early = notifications.notify(IdeSeverity.info, 'Before');
      await tester.pump(const Duration(seconds: 30));
      expect(notifications.toasts, [early]);

      notifications.addListener(shown);
      await tester.pump(const Duration(seconds: 5));
      notifications.removeListener(shown);
      await tester.pump(const Duration(seconds: 30));
      expect(notifications.toasts, [early]);

      notifications.addListener(shown);
      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toasts, isEmpty);
      expect(notifications.notifications, [early]);
      notifications.dispose();
    });

    testWidgets('sticky toasts, and ones under the mouse, stay', (
      tester,
    ) async {
      notifications.addListener(shown);
      final asked = notifications.notify(
        IdeSeverity.info,
        'Asked',
        sticky: true,
      );
      final error = notifications.notify(
        IdeSeverity.error,
        'With actions',
        primary: [IdeNotificationAction('Retry', () {})],
      );
      final warning = notifications.notify(
        IdeSeverity.warning,
        'Without actions',
        primary: [IdeNotificationAction('Open', () {})],
      );
      final hovered = notifications.notify(IdeSeverity.info, 'Hovered');
      notifications.hover(hovered, true);
      expect(asked.sticky, isTrue);
      expect(error.sticky, isTrue);
      expect(warning.sticky, isFalse);

      await tester.pump(const Duration(seconds: 30));
      expect(notifications.notifications, hasLength(4));
      expect(notifications.toasts, containsAll([asked, error, hovered]));
      expect(notifications.toasts, isNot(contains(warning)));

      notifications.hover(hovered, false);
      await tester.pump(const Duration(seconds: 10));
      expect(notifications.toasts, isNot(contains(hovered)));
      notifications.dispose();
    });

    testWidgets('three toasts at most, the newest last; the same message '
        'replaces', (tester) async {
      var closed = 0;
      for (final message in ['a', 'b', 'c']) {
        notifications.notify(
          IdeSeverity.info,
          message,
          onClose: () => closed++,
        );
      }
      notifications.notify(IdeSeverity.info, 'd');
      expect(
        [for (final n in notifications.toasts) n.message],
        ['b', 'c', 'd'],
      );

      notifications.notify(IdeSeverity.info, 'a');
      expect(closed, 1);
      expect(
        [for (final n in notifications.notifications) n.message],
        ['a', 'd', 'c', 'b'],
      );
      expect(notifications.toasts.last.message, 'a');
      notifications.dispose();
    });

    testWidgets('the center takes the toasts and marks them read', (
      tester,
    ) async {
      final bell = ideNotificationsStatusItem(notifications);
      expect(bell.icon, Codicons.bell);
      expect(bell.tooltip, 'No Notifications');

      notifications.notify(IdeSeverity.warning, 'Slow');
      expect(ideNotificationsStatusItem(notifications).icon, Codicons.bellDot);
      expect(
        ideNotificationsStatusItem(notifications).tooltip,
        '1 New Notification',
      );

      notifications.toggleCenter();
      expect(notifications.toasts, isEmpty);
      expect(notifications.unread, 0);
      expect(
        ideNotificationsStatusItem(notifications).tooltip,
        'Hide Notifications',
      );
      // Ones that come while it is open are read there.
      notifications.notify(IdeSeverity.info, 'Done');
      expect(notifications.unread, 0);
      expect(notifications.toasts, isEmpty);

      notifications.hideCenter();
      expect(
        ideNotificationsStatusItem(notifications).tooltip,
        'No New Notifications',
      );
      notifications.clearAll();
      expect(notifications.notifications, isEmpty);
      notifications.dispose();
    });

    testWidgets('an action closes its notification and runs', (tester) async {
      final ran = <String>[];
      notifications.notify(
        IdeSeverity.info,
        'Install the recommended server?',
        primary: [
          IdeNotificationAction(
            'Install',
            () => ran.add('install'),
            menu: [IdeNotificationAction('Install Pre-Release', () {})],
          ),
          IdeNotificationAction('Show Recommendations', () => ran.add('show')),
        ],
        secondary: [IdeNotificationAction('Never', () => ran.add('never'))],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: IdeNotificationToasts(notifications: notifications),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Actions expand it: its buttons show, and the toolbar.
      expect(find.text('Show Recommendations'), findsOneWidget);
      expect(find.byTooltip('Expand Notification'), findsNothing);
      await tester.tap(find.byIcon(Codicons.chevronDown).first);
      await tester.pumpAndSettle();
      expect(find.text('Install Pre-Release'), findsOneWidget);
      await tester.tap(find.text('Install Pre-Release'));
      await tester.pumpAndSettle();
      expect(notifications.notifications, isEmpty);
      expect(find.text('Show Recommendations'), findsNothing);
      expect(ran, isEmpty);

      notifications.notify(
        IdeSeverity.info,
        'Again?',
        primary: [IdeNotificationAction('Install', () => ran.add('install'))],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Install'));
      await tester.pumpAndSettle();
      expect(ran, ['install']);
      expect(notifications.notifications, isEmpty);
      await tester.pumpWidget(const SizedBox());
      notifications.dispose();
    });
  });

  testWidgets('a failed save is an error toast, not a banner', (tester) async {
    final workspace = await pumpWorkbench(
      tester,
      {'a.txt': 'a'},
      open: ['a.txt'],
    );
    workspace.edit(inRoot('a.txt'), 'mine');
    (workspace.files as TreeFiles).contents[inRoot('a.txt')] = 'theirs';
    await chord(tester, LogicalKeyboardKey.keyS, control: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('The file changed on disk'), findsOneWidget);
    expect(find.byIcon(Codicons.error), findsOneWidget);
    expect(find.byIcon(Codicons.bellDot), findsOneWidget);

    // It goes after 15 seconds, and is in the center.
    await tester.pump(const Duration(seconds: 15));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('The file changed on disk'), findsNothing);
    await tester.tap(find.byIcon(Codicons.bellDot));
    await tester.pump();
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.textContaining('The file changed on disk'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('NOTIFICATIONS'), findsNothing);
    expect(find.byIcon(Codicons.bell), findsOneWidget);
  });
}
