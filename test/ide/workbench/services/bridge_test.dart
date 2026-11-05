import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_status_bar.dart';
import 'package:baocode/ide/ide_workbench.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/context_keys.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/keybindings/keybinding_service.dart';

import '../fake_files.dart';

/// The services stand beside the workbench's own commands, keys and status
/// bar while the features move to them.
void main() {
  setUp(() => KeybindingService.instance = KeybindingService());
  tearDown(() => KeybindingService.instance = KeybindingService());

  IdeWorkbenchState workbench(WidgetTester tester) =>
      tester.state<IdeWorkbenchState>(find.byType(IdeWorkbench));

  testWidgets('actions, context keys and status entries reach the '
      'workbench', (tester) async {
    await pumpWorkbench(tester, {'a.txt': 'a'}, open: ['a.txt']);
    final state = workbench(tester);
    final services = state.services;
    var ran = 0;
    services.get<ActionRegistry>().register(
      WorkbenchAction(
        id: 'test.action',
        title: 'Test Action',
        run: (_, _) => ran++,
      ),
    );
    expect(state.commands.any((c) => c.id == 'test.action'), isTrue);
    state.commandsById['test.action']!.run();
    expect(ran, 1);

    services.get<ContextKeyService>().createKey('testKey', 'value');
    expect(state.keyContext('testKey'), 'value');
    // The workbench's own keys still answer.
    expect(state.keyContext('ideMode'), isTrue);

    services.get<StatusbarService>().addEntry(
      'test.entry',
      StatusbarAlignment.left,
      (_) => const IdeStatusBarItem('From a service'),
    );
    await tester.pump();
    expect(find.text('From a service'), findsOneWidget);
  });
}
