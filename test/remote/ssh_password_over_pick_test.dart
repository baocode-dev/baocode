import 'package:bao_remote/client.dart';
import 'package:baocode/ide/ide_input.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/main.dart';
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/remote/ssh_host.dart';
import 'package:baocode/remote/ssh_passwords.dart';
import 'package:baocode/window/app_windows.dart';
import 'package:baocode/workbench.dart';
import 'package:baocode/workspace/workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Frames enough for a dialog to open or close (the quick input's spinner
/// may never settle).
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Signing in to a host asks for the password over the Connecting pick
/// (the open remote flow's): the dialog has to get it, Enter included,
/// not the pick under it.
void main() {
  late SshHosts saved;
  setUp(() => saved = SshHosts.instance);
  tearDown(() => SshHosts.instance = saved);

  WindowDelegate workbench(WidgetTester tester) =>
      tester.state<State>(find.byType(Workbench)) as WindowDelegate;

  Future<Future<String?>> ask(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SshHosts.instance = SshHosts(
      passwords: SshPasswords(secrets: MemorySecretStore()),
    );
    await tester.pumpWidget(BaoCodeApp(workspace: Workspace.mock()));
    await tester.pump();
    // The Connecting pick, as the open remote flow shows it.
    workbench(tester).showQuickPick(
      const IdeQuickPick(
        placeholder: 'Connecting to dev...',
        items: [IdeQuickPickItem(label: 'Connecting to dev...')],
      ),
    );
    await settle(tester);
    expect(find.byType(IdeQuickInput), findsOneWidget);
    // ssh asks, while it shows.
    final answer = SshHosts.instance.passwords.answer(
      SshPrompt(SshTarget.parse('dev'), "root@dev's password: "),
    );
    await settle(tester);
    expect(find.byType(IdeInputBox), findsOneWidget);
    return answer;
  }

  testWidgets('Enter answers the dialog over the pick', (tester) async {
    final answer = await ask(tester);
    await tester.enterText(find.byType(IdeInputBox), 'hunter2');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(await answer, 'hunter2');
  });

  testWidgets('the pick replaced under the dialog leaves it be', (
    tester,
  ) async {
    await ask(tester);
    // The flow moves on (a failure, say) while the dialog shows: the pick
    // under it goes, the dialog stays.
    workbench(tester).showQuickPick(
      const IdeQuickPick(
        placeholder: 'next',
        items: [IdeQuickPickItem(label: 'next')],
      ),
    );
    await settle(tester);
    expect(find.byType(IdeInputBox), findsOneWidget);
    expect(find.text('Connecting to dev...'), findsNothing);
  });
}
