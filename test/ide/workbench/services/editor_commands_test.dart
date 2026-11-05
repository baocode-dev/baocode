import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/auto_save.dart';
import 'package:baocode/ide/services/chat.dart';
import 'package:baocode/ide/services/commands.dart';
import 'package:baocode/ide/services/configuration.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/services/quick_input.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/editor_commands.dart';
import 'package:baocode/ide/workbench/contributions/window.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/environment.dart';
import 'package:baocode/ide/workbench/quick_access.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/statusbar.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/settings/user_settings.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The editors' and the window's commands alone, over a workspace and no
/// text editor: closing and cycling, the tabs' actions, the settings they
/// toggle, auto save, the chat's and the app's commands.
void main() {
  late IdeWorkspace workspace;
  late FakeWorkbenchHost host;
  late EditorService editors;
  late LayoutService layout;
  late ConfigurationService config;
  late WorkbenchServices services;
  late List<WorkbenchContribution> contributions;
  late _Environment environment;
  final sent = <String>[];
  var backs = 0;

  Future<void> setUpCommands(WidgetTester tester) async {
    workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({
        inRoot('a.txt'): 'a',
        inRoot('src/b.txt'): 'b',
        inRoot('c.txt'): 'c',
      }),
    );
    host = FakeWorkbenchHost();
    sent.clear();
    backs = 0;
    environment = _Environment();
    final panes = EditorPaneRegistry();
    editors = EditorService(
      host: host,
      panes: panes,
      workspace: () => workspace,
      layout: () => workspace.layout,
      history: () => null,
      focusWorkbench: () {},
      revealInExplorer: (path) => sent.add('reveal $path'),
    );
    layout = LayoutService(host: host, layout: () => workspace.layout);
    config = ConfigurationService(settings: () => null);
    services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add(StatusbarService())
      ..add<WorkbenchHost>(host)
      ..add<WorkbenchEnvironment>(environment)
      ..add(workspace)
      ..add(panes)
      ..add(editors)
      ..add(layout)
      ..add(config);
    services
      ..add(CommandService(services: services, actions: services.get()))
      ..add(
        QuickInputService(
          host: host,
          registry: QuickAccessRegistry(),
          focusWorkbench: () {},
        ),
      )
      ..add(
        ChatService(
          host: host,
          layout: layout,
          editors: editors,
          addCode: () =>
              (code) => sent.add('code ${code.length}'),
          ask: () => sent.add,
          back: () =>
              () => backs++,
        ),
      );
    contributions = [
      EditorCommandsContribution(services),
      WindowContribution(services),
    ];
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
    addTearDown(() {
      disposeContributions(contributions);
      services.remove<IdeWorkspace>(owned: false);
      services.dispose();
      workspace.dispose();
    });
  }

  IdeCommand command(String id) => services.get<CommandService>().byId()[id]!;
  List<String> names() => [for (final doc in workspace.documents) doc.name];

  testWidgets('closed and cycled as the commands say', (tester) async {
    await setUpCommands(tester);
    expect(command('workbench.action.closeAllEditors').enabled, isFalse);
    for (final name in ['a.txt', 'src/b.txt', 'c.txt']) {
      await editors.open(inRoot(name));
    }
    command('workbench.action.openEditorAtIndex1').run();
    await tester.pump();
    expect(workspace.active?.name, 'a.txt');
    expect(command('workbench.action.closeEditorsToTheLeft').enabled, isFalse);
    command('workbench.action.nextEditor').run();
    await tester.pump();
    expect(workspace.active?.name, 'b.txt');

    command('workbench.action.closeEditorsToTheRight').run();
    await tester.pumpAndSettle();
    expect(names(), ['a.txt', 'b.txt']);
    command('workbench.action.closeOtherEditors').run();
    await tester.pumpAndSettle();
    expect(names(), ['b.txt']);
    expect(command('workbench.action.closeOtherEditors').enabled, isFalse);
  });

  testWidgets('the tab\'s actions: copied paths, revealed', (tester) async {
    await setUpCommands(tester);
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await editors.open(inRoot('src/b.txt'));
    command('copyFilePath').run();
    command('copyRelativeFilePath').run();
    await tester.pump();
    expect(copied, [inRoot('src/b.txt'), p.join('src', 'b.txt')]);
    expect(editors.relativePath(inRoot('src/b.txt')), p.join('src', 'b.txt'));
  });

  testWidgets('toggles: their titles follow, settings.json is told', (
    tester,
  ) async {
    await setUpCommands(tester);
    var changes = 0;
    config.addListener(() => changes++);
    expect(config.formatOnSave, isFalse);
    expect(
      command('baocode.ide.toggleFormatOnSave').label,
      'Turn On Format on Save',
    );
    config.formatOnSave = true;
    expect(
      command('baocode.ide.toggleFormatOnSave').label,
      'Turn Off Format on Save',
    );
    // Without a repository, no blame to toggle.
    expect(command('git.blame.toggleEditorDecoration').enabled, isFalse);
    config.gitBlame = false;
    expect(config.gitBlame, isFalse);
    expect(changes, 2);
    config.reloaded();
    expect(config.formatOnSave, isFalse);
    expect(config.gitBlame, isTrue);
  });

  testWidgets('the chat\'s and the app\'s commands', (tester) async {
    await setUpCommands(tester);
    // No text editor: no selection to add.
    expect(command('workbench.action.chat.attachSelection').enabled, isFalse);
    workspace.layout.chat = false;
    services.get<ChatService>().ask('why?');
    expect(sent, ['why?']);
    expect(workspace.layout.chat, isTrue);
    command('baocode.ide.backToChat').run();
    await tester.pump();
    expect(backs, 1);

    expect(command('workbench.action.selectTheme').enabled, isFalse);
    expect(command('workbench.action.openGlobalSettings').enabled, isFalse);
    var settingsOpened = 0;
    environment.hostCommands = [
      IdeCommand(
        id: 'workbench.action.openSettings',
        label: 'Open Settings',
        run: () => settingsOpened++,
      ),
    ];
    command('workbench.action.openGlobalSettings').run();
    expect(settingsOpened, 1);
    // The app's own, among the window's.
    expect(
      services.get<CommandService>().palette().map((command) => command.id),
      contains('workbench.action.openSettings'),
    );
  });

  testWidgets('auto save: after a delay, as settings.json says', (
    tester,
  ) async {
    await setUpCommands(tester);
    final temp = await tester.runAsync(
      () => Directory.systemTemp.createTemp('auto_save'),
    );
    addTearDown(() => temp!.deleteSync(recursive: true));
    final file = File(p.join(temp!.path, 'settings.json'))
      ..writeAsStringSync(
        '{"files.autoSave": "afterDelay", "files.autoSaveDelay": 50}',
      );
    final settings = UserSettings(file.path);
    addTearDown(settings.dispose);
    await tester.runAsync(settings.load);
    final autoSave = AutoSaveService(
      host: host,
      config: ConfigurationService(settings: () => settings),
      editors: editors,
      workspace: () => workspace,
    );
    addTearDown(autoSave.dispose);
    expect(autoSave.mode, 'afterDelay');
    expect(autoSave.delay, const Duration(milliseconds: 50));

    await editors.open(inRoot('a.txt'));
    final doc = workspace.active!;
    doc.text = 'edited';
    expect(doc.dirty, isTrue);
    autoSave.schedule();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpAndSettle();
    expect(doc.dirty, isFalse);
    expect(await workspace.files.read(inRoot('a.txt')), 'edited');
  });
}

class _Environment implements WorkbenchEnvironment {
  @override
  UserSettings? get settings => null;

  @override
  IdeColorThemeController? get colorThemes => null;

  @override
  List<IdeCommand> hostCommands = const [];
}
