import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/chat/chat_screen.dart';
import 'package:baocode/chat/side_panel/side_panel_view.dart';
import 'package:baocode/ide/terminal/terminal_panel.dart';
import 'package:baocode/main.dart';
import 'package:baocode/workspace/chat_terminal.dart';
import 'package:baocode/workspace/workspace.dart';

import '../ide/terminal/fake_pty.dart';
import '../workspace_test.dart' show claude;
import '../ide/terminal/fake_terminal.dart';

void main() {
  testWidgets('probe', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const window = MethodChannel('baocode/window');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window, (call) async => null);
    final workspace = Workspace(kernels: [claude]);
    final ptys = <FakePty>[];
    await tester.pumpWidget(BaoCodeApp(workspace: workspace, terminalBackend: fakeTerminalBackend(ptys)));
    await tester.runAsync(workspace.load);
    await tester.pump();
    final existing = workspace.threads.firstWhere((t) => t.record != null);
    workspace.select(existing);
    for (var i = 0; i < 5; i++) await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byType(ChatTerminalToggle));
    for (var i = 0; i < 5; i++) await tester.pump(const Duration(milliseconds: 100));
    debugPrint('chat ${tester.getRect(find.byType(ChatScreen).first)}');
    debugPrint('rail ${find.byType(SidePanelRail).evaluate().isEmpty ? 'none' : tester.getRect(find.byType(SidePanelRail))}');
    debugPrint('panelTitle ${tester.getRect(find.text('TERMINAL'))}');
    debugPrint('area ${tester.getRect(find.byType(ChatTerminalArea).first)}');
    final tv = find.byType(TerminalPanel);
    debugPrint('terminalPanel ${tv.evaluate().isEmpty ? 'none' : tester.getRect(tv.first)}');
    await tester.pumpWidget(const SizedBox());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
