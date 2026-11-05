import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/services/commands.dart';
import 'package:baocode/ide/services/quick_input.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/quick_access.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/l10n/app_localizations.dart';

import 'fake_host.dart';

/// The quick input and the commands alone: a text's provider by its
/// prefix, opened and switched, a pick in its place, closed with the
/// keyboard back; the commands of the actions and of the sources.
void main() {
  late FakeWorkbenchHost host;
  late QuickAccessRegistry registry;
  late QuickInputService quick;
  var workbenchFocused = 0;

  Future<void> setUpQuick(WidgetTester tester) async {
    host = FakeWorkbenchHost();
    registry = QuickAccessRegistry();
    workbenchFocused = 0;
    quick = QuickInputService(
      host: host,
      registry: registry,
      focusWorkbench: () => workbenchFocused++,
    );
    addTearDown(quick.dispose);
    QuickAccessProvider provider(String prefix, {String? key}) =>
        QuickAccessProvider(
          prefix: prefix,
          contextKey: key,
          placeholder: (_) => 'in "$prefix"',
          picks: (_, filter) => [IdeQuickPickItem(label: '$prefix|$filter')],
        );
    registry
      ..register(provider('', key: 'inFilesPicker'))
      ..register(provider('>'))
      ..register(provider('edt ', key: 'inEditorsPicker'))
      ..register(provider('edt mru ', key: 'inEditorsPicker'));
    await tester.pumpWidget(
      Localizations(
        locale: const Locale('en'),
        delegates: AppLocalizations.localizationsDelegates,
        child: Builder(
          builder: (context) {
            host.context = context;
            return const SizedBox();
          },
        ),
      ),
    );
  }

  testWidgets('a text\'s provider: the longest prefix it starts with', (
    tester,
  ) async {
    await setUpQuick(tester);
    expect(quick.picks('foo').single.label, '|foo');
    expect(quick.picks('>run').single.label, '>|run');
    expect(quick.picks('edt a').single.label, 'edt |a');
    expect(quick.picks('edt mru a').single.label, 'edt mru |a');
    expect(quick.placeholder('>'), 'in ">"');
  });

  testWidgets('opened, a pick in its place, closed: the keyboard back', (
    tester,
  ) async {
    await setUpQuick(tester);
    var changes = 0;
    quick.addListener(() => changes++);
    expect(quick.contextKey('inQuickOpen'), isFalse);
    expect(quick.contextKey('inFilesPicker'), isFalse);
    expect(quick.contextKey('someoneElses'), isNull);

    quick.show('');
    expect(quick.isOpen, isTrue);
    expect(quick.text, '');
    expect(quick.activation, IdeQuickPickFocus.first);
    expect(quick.contextKey('inFilesPicker'), isTrue);
    expect(quick.contextKey('inEditorsPicker'), isFalse);
    expect(quick.contextKey('quickInputType'), 'quickPick');

    // With a quick navigation: the second row first, the input hidden
    // only if none showed.
    quick.show('edt mru ', quickNavigate: const []);
    expect(quick.activation, IdeQuickPickFocus.second);
    expect(quick.hideInput, isFalse);
    expect(quick.contextKey('inEditorsPicker'), isTrue);

    var hidden = 0;
    quick.showModel(
      IdeQuickInputBox(onDidAccept: (_) {}, onDidHide: () => hidden++),
    );
    expect(quick.text, isNull);
    expect(quick.contextKey('quickInputType'), 'inputBox');
    expect(quick.contextKey('inFilesPicker'), isFalse);

    quick.close();
    expect(quick.isOpen, isFalse);
    expect(hidden, 1);
    expect(workbenchFocused, 1);
    expect(changes, 4);
    // Closed already: nothing.
    quick.close();
    expect(workbenchFocused, 1);
  });

  test('commands: the actions\' first, then the sources\', by id', () {
    final services = WorkbenchServices();
    final actions = services.add(ActionRegistry());
    final commands = CommandService(services: services, actions: actions);
    final ran = <String>[];
    actions.registerAll([
      WorkbenchAction(id: 'a', title: 'A', run: (_, _) => ran.add('a')),
      WorkbenchAction(
        id: 'hidden',
        title: 'Hidden',
        palette: false,
        run: (_, _) => ran.add('hidden'),
      ),
    ]);
    commands
      ..addSource(
        () => [
          IdeCommand(id: 'a', label: 'Other A', run: () => ran.add('a2')),
          IdeCommand(id: 'b', label: 'B', run: () => ran.add('b')),
        ],
      )
      ..addSource(
        () => [
          IdeCommand(
            id: 'off',
            label: 'Off',
            enabled: false,
            run: () => ran.add('off'),
          ),
        ],
        palette: false,
      );
    expect(commands.palette().map((command) => command.id), ['a', 'a', 'b']);
    expect(commands.byId().keys, ['a', 'hidden', 'b', 'off']);
    expect(commands.runById('a'), isTrue);
    expect(commands.runById('hidden'), isTrue);
    expect(commands.runById('off'), isFalse);
    expect(commands.runById('none'), isFalse);
    expect(ran, ['a', 'hidden']);
    expect(commands.recent.items, ['hidden', 'a']);
    services.dispose();
  });
}
