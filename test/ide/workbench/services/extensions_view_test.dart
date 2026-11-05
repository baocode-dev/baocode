import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/extensions/ui/extensions_model.dart';
import 'package:baocode/ide/ide_color_theme_picker.dart';
import 'package:baocode/ide/ide_commands.dart';
import 'package:baocode/ide/ide_quick_input.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/services/extensions_view.dart';
import 'package:baocode/ide/services/quick_input.dart';
import 'package:baocode/ide/workbench/actions.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/contributions/extensions.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/environment.dart';
import 'package:baocode/ide/workbench/quick_access.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/l10n/app_localizations.dart';
import 'package:baocode/settings/user_settings.dart';

import '../fake_files.dart';
import 'fake_host.dart';

/// The extensions alone, without theme extensions: the view's tab, no
/// page, nothing dropped taken; Close Editor and the File Icon Theme
/// pick.
void main() {
  testWidgets('without theme extensions: the language servers alone', (
    tester,
  ) async {
    final workspace = IdeWorkspace(
      testRoot,
      files: TreeFiles({inRoot('a.txt'): 'a'}),
    );
    final host = FakeWorkbenchHost();
    final quick = QuickInputService(
      host: host,
      registry: QuickAccessRegistry(),
      focusWorkbench: () {},
    );
    final told = <String>[];
    final extensions = ExtensionsViewService(
      host: host,
      environment: _Environment(),
      quickInput: quick,
      themes: () => null,
      languageServers: () => null,
      notify: told.add,
    );
    final panes = EditorPaneRegistry();
    final editors = EditorService(
      host: host,
      panes: panes,
      workspace: () => workspace,
      layout: () => workspace.layout,
      history: () => null,
      focusWorkbench: () {},
    );
    final services = WorkbenchServices()
      ..add(ActionRegistry())
      ..add<WorkbenchHost>(host)
      ..add<WorkbenchEnvironment>(_Environment())
      ..add(workspace)
      ..add(panes)
      ..add(editors)
      ..add(quick)
      ..add(extensions);
    final contribution = ExtensionsContribution(services);
    addTearDown(() {
      contribution.dispose();
      services.remove<IdeWorkspace>(owned: false);
      services.dispose();
      workspace.dispose();
    });
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
    IdeCommand command(String id) =>
        services.get<ActionRegistry>().byId(id)!.toCommand(services);

    expect(extensions.tab, ExtensionsTab.languageServers);
    extensions.tab = ExtensionsTab.themes;
    expect(extensions.tab, ExtensionsTab.languageServers);
    // A page opened needs theme extensions to show.
    extensions.openPage(const ExtensionEntry());
    expect(extensions.page, isNull);
    expect(extensions.pageShown, isFalse);
    expect(extensions.drop(['/tmp/x.vsix']), isFalse);
    expect(command('workbench.extensions.action.installVSIX').enabled, isFalse);
    extensions.reportMessage('broken');
    expect(told, ['broken']);

    // Close Editor: the active file's.
    expect(command('workbench.action.closeActiveEditor').enabled, isFalse);
    await editors.open(inRoot('a.txt'));
    command('workbench.action.closeActiveEditor').run();
    await tester.pumpAndSettle();
    expect(workspace.documents, isEmpty);

    // File Icon Theme: a pick, the bundled theme among it.
    expect(command('workbench.action.selectIconTheme').enabled, isTrue);
    command('workbench.action.selectIconTheme').run();
    final pick = quick.model! as IdeQuickPick;
    expect((pick.items.first as IdeQuickPickItem).label, 'Material Icon Theme');
    quick.close();
  });
}

class _Environment implements WorkbenchEnvironment {
  @override
  UserSettings? get settings => UserSettings('/nonexistent/settings.json');

  @override
  IdeColorThemeController? get colorThemes => null;

  @override
  List<IdeCommand> get hostCommands => const [];
}
