import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/workspace/workspace.dart';

import 'update_fakes.dart';

void main() {
  final l10n = englishLocalizations;

  Future<void> show(
    WidgetTester tester,
    UpdateService service,
    VoidCallback onUpdate,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: Sidebar(
              workspace: Workspace.mock(),
              onCollapse: () {},
              onOpenSettings: () {},
              updates: service,
              onUpdate: onUpdate,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder update() => find.text(l10n.updateButton);

  testWidgets('Update shows beside the gear while an update waits', (
    tester,
  ) async {
    final service = serviceOf(FakeBackend(manifestOf('1.2.0')));
    var updates = 0;
    await show(tester, service, () => updates++);
    expect(update(), findsNothing);

    await tester.runAsync(() async {
      await service.check(manual: true);
      await service.download();
    });
    await tester.pump();
    expect(update(), findsOneWidget);

    await tester.tap(update());
    expect(updates, 1);

    // Skipped: it goes.
    service.skip(service.release!);
    await tester.pump();
    expect(update(), findsNothing);
    service.dispose();
  });
}
