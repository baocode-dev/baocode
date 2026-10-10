import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/quit_confirmation.dart';
import 'package:baocode/workspace/workspace.dart';

/// The app with an agent at work (with nothing at work, a quit is not
/// asked about: see `AppWindows.confirmQuit`).
Future<Workspace> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final workspace = Workspace.mock();
  await tester.pumpWidget(BaoCodeApp(workspace: workspace));
  await tester.pump();
  workspace.selected.session.send(const ComposerMessage(text: 'Go on'));
  await tester.pump();
  return workspace;
}

/// The agent stopped, and its timers run out.
Future<void> _stop(WidgetTester tester, Workspace workspace) async {
  workspace.selected.session.stop();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('a quit asks first; Cancel keeps the app', (tester) async {
    final workspace = await _pumpApp(tester);
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
    await _stop(tester, workspace);
  });

  testWidgets('Quit quits', (tester) async {
    final workspace = await _pumpApp(tester);
    final response = tester.binding.handleRequestAppExit();
    await tester.pump();
    await tester.tap(find.text('Quit'));
    await tester.pump();
    expect(await response, AppExitResponse.exit);
    await _stop(tester, workspace);
  });

  testWidgets('a second request while asking does not quit', (tester) async {
    final workspace = await _pumpApp(tester);
    final first = tester.binding.handleRequestAppExit();
    await tester.pump();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.cancel);
    expect(find.text('Quit BaoCode?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(await first, AppExitResponse.cancel);
    await _stop(tester, workspace);
  });

  testWidgets('a quit already chosen (Quit Now) is not asked about', (
    tester,
  ) async {
    final workspace = await _pumpApp(tester);
    QuitConfirmation.skipNext();
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);
    expect(find.text('Quit BaoCode?'), findsNothing);
    await _stop(tester, workspace);
  });
}
