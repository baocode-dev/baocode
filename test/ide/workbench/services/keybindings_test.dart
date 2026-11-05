import 'package:bao_editor/monaco/flutter/keybinding_entry.dart'
    show KeybindingPlatform;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/services/commands.dart';
import 'package:baocode/ide/services/keybindings.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/keybindings/keybinding_service.dart';
import 'package:baocode/l10n/app_localizations.dart';

import 'fake_host.dart';

/// The keys alone, over the window's commands and no window: a key's
/// command run, a two-chord keybinding's first chord waiting in the status
/// bar, the second one run or told it is none.
void main() {
  testWidgets('a key, and two chords', (tester) async {
    final host = FakeWorkbenchHost();
    final services = WorkbenchServices();
    final actions = services.add(ActionRegistry());
    final keys = services.add(ContextKeyService());
    final statusbar = services.add(StatusbarService());
    final ran = <String>[];
    actions.registerAll([
      for (final id in const [
        'workbench.action.quickOpen',
        'workbench.action.selectTheme',
      ])
        WorkbenchAction(id: id, title: id, run: (_, _) => ran.add(id)),
    ]);
    final focus = FocusNode(debugLabel: 'workbench');
    final dispatch = services.add(
      KeybindingDispatchService(
        host: host,
        commands: CommandService(services: services, actions: actions),
        contextKeys: keys,
        statusbar: statusbar,
        focusNode: focus,
        active: () => true,
      ),
    );
    addTearDown(() {
      services.dispose();
      focus.dispose();
    });
    expect(dispatch, isNotNull);
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            host.context = context;
            return Focus(
              focusNode: focus,
              autofocus: true,
              onKeyEvent: dispatch.onKey,
              child: const SizedBox(),
            );
          },
        ),
      ),
    );
    await tester.pump();
    final mod = KeybindingService.instance.platform == KeybindingPlatform.mac
        ? LogicalKeyboardKey.meta
        : LogicalKeyboardKey.control;

    // ⌘P: Go to File.
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(mod);
    expect(ran, ['workbench.action.quickOpen']);

    // ⌘K waits for the next chord; ⌘T completes Color Theme.
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    expect(statusbar.message, contains('was pressed'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(mod);
    expect(ran.last, 'workbench.action.selectTheme');
    expect(statusbar.message, isNull);

    // ⌘K then a key of no keybinding: told so.
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(mod);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    expect(statusbar.message, contains('is not a command'));
    expect(ran, hasLength(2));
    await tester.pump(const Duration(seconds: 11));
    expect(statusbar.message, isNull);
  });
}
