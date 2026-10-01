import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/quit_confirmation.dart';
import 'package:baocode/workspace/workspace.dart';

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
  await tester.pump();
}

void main() {
  testWidgets('a quit asks first; Cancel keeps the app', (tester) async {
    await _pumpApp(tester);
    final response = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(find.text('Quit BaoCode?'), findsOneWidget);
    expect(
      find.text('Running agents and terminals will be stopped.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(await response, AppExitResponse.cancel);
    expect(find.text('Quit BaoCode?'), findsNothing);
  });

  testWidgets('Quit quits', (tester) async {
    await _pumpApp(tester);
    final response = tester.binding.handleRequestAppExit();
    await tester.pump();
    await tester.tap(find.text('Quit'));
    await tester.pump();
    expect(await response, AppExitResponse.exit);
  });

  testWidgets('a second request while asking does not quit', (tester) async {
    await _pumpApp(tester);
    final first = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(find.text('Quit BaoCode?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(await first, AppExitResponse.cancel);
  });

  testWidgets('a quit already chosen (Quit Now) is not asked about', (
    tester,
  ) async {
    await _pumpApp(tester);
    QuitConfirmation.skipNext();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(find.text('Quit BaoCode?'), findsNothing);
  });
}
