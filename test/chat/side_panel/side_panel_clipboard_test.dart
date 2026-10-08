import 'package:baocode/chat/chat_session.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/ide/ide_explorer.dart';
import 'package:baocode/kernel/agent_kernel.dart' show KernelContext;
import 'package:baocode/theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../ide/workbench/fake_files.dart';

/// The side panel's files page with the system's clipboard, as the IDE's
/// explorer: files copied in Finder or Explorer paste in, its own copies go
/// there, and its keys work without the IDE's workbench.
void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  /// The system's clipboard: what it holds, as files.
  List<String> clipboard(WidgetTester tester) {
    final held = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('baocode/window');
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'writePasteboardFiles':
          held
            ..clear()
            ..addAll((call.arguments as List).cast<String>());
          return true;
        case 'readPasteboardFiles':
          return [
            for (final path in held)
              {'path': path, 'directory': !p.basename(path).contains('.')},
          ];
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    return held;
  }

  /// The side panel of a conversation in the test project, on its files
  /// page.
  Future<TreeFiles> pumpPanel(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = ChatSession(
      historyCount: 8,
      kernelContext: KernelContext(cwd: testRoot),
      openReview: (root, {session}) async => null,
    );
    addTearDown(session.dispose);
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final files = TreeFiles({
      inRoot('lib/a.dart'): 'a',
      inRoot('README.md'): 'r',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Material(
          child: AgentSidePanelArea(
            panel: panel,
            builder: (context) => AgentSidePanelView(
              panel: panel,
              session: session,
              files: files,
              watchDirectory: (_) => const Stream.empty(),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    panel.showSection(session, SidePanelSection.files);
    await tester.pumpAndSettle();
    return files;
  }

  Finder row(String name) =>
      find.descendant(of: find.byType(IdeExplorer), matching: find.text(name));

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tapAt(
      tester.getCenter(finder),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  Future<void> ctrl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('files copied in Finder or Explorer paste into the tree, from '
      'the keyboard and the menu', (tester) async {
    final held = clipboard(tester);
    final files = await pumpPanel(tester);
    expect(find.byType(IdeExplorer), findsOneWidget);
    held.add(inRoot('lib/a.dart'));

    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyV);
    expect(files.contents[inRoot('a.dart')], 'a');

    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(files.contents[inRoot('lib/a copy.dart')], 'a');
  }, variant: windows);

  testWidgets('a copy is on the system\'s clipboard; cut and paste moves', (
    tester,
  ) async {
    final held = clipboard(tester);
    final files = await pumpPanel(tester);
    await tester.tap(row('README.md'));
    await tester.pumpAndSettle();
    await ctrl(tester, LogicalKeyboardKey.keyC);
    expect(held, [inRoot('README.md')]);

    await ctrl(tester, LogicalKeyboardKey.keyX);
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(files.contents.containsKey(inRoot('README.md')), isFalse);
    expect(files.contents[inRoot('lib/README.md')], 'r');
  }, variant: windows);

  testWidgets('a paste that fails says why', (tester) async {
    final held = clipboard(tester);
    await pumpPanel(tester);
    held.add(inRoot('lib'));
    await rightClick(tester, row('lib'));
    await tester.tap(find.text('Paste'));
    await tester.pumpAndSettle();
    expect(
      find.text('File to paste is an ancestor of the destination folder'),
      findsOneWidget,
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(
      find.text('File to paste is an ancestor of the destination folder'),
      findsNothing,
    );
  }, variant: windows);
}
