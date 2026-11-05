import 'package:bao_editor/monaco/vs/editor/common/core/position.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/debug/service/debug_service.dart';
import 'package:baocode/ide/ide_workspace.dart';
import 'package:baocode/ide/search/text_search.dart';
import 'package:baocode/ide/services/auto_save.dart';
import 'package:baocode/ide/services/configuration.dart';
import 'package:baocode/ide/services/debug_view.dart';
import 'package:baocode/ide/services/editors.dart';
import 'package:baocode/ide/services/explorer.dart';
import 'package:baocode/ide/services/extensions_view.dart';
import 'package:baocode/ide/services/language.dart';
import 'package:baocode/ide/services/layout.dart';
import 'package:baocode/ide/services/navigation_history.dart';
import 'package:baocode/ide/services/problems.dart';
import 'package:baocode/ide/services/quick_input.dart';
import 'package:baocode/ide/services/references.dart';
import 'package:baocode/ide/services/scm_service.dart';
import 'package:baocode/ide/services/search_view.dart';
import 'package:baocode/ide/services/terminal_view.dart';
import 'package:baocode/ide/workbench/contributions.dart';
import 'package:baocode/ide/workbench/editor_panes.dart';
import 'package:baocode/ide/workbench/environment.dart';
import 'package:baocode/ide/workbench/quick_access.dart';
import 'package:baocode/ide/workbench/services.dart';
import 'package:baocode/ide/workbench/storage.dart';
import 'package:baocode/ide/workbench/views.dart';
import 'package:baocode/ide/workbench/workspace_binding.dart';
import 'package:baocode/l10n/app_localizations.dart';

import '../../../debug/support/fake_debug_adapter.dart';
import '../fake_files.dart';
import 'fake_host.dart';

/// The services on a workspace without the workbench: attached, the
/// editor in front followed, another workspace swapped in.
void main() {
  testWidgets('the services follow the workspace, and the next one', (
    tester,
  ) async {
    IdeWorkspace workspaceOf(String name) =>
        IdeWorkspace(testRoot, files: TreeFiles({inRoot(name): name}));
    var workspace = workspaceOf('a.txt');
    final first = workspace;
    addTearDown(first.dispose);
    // The debugger given, as the workbench's tests give theirs.
    late final DebugService debug;
    await tester.runAsync(() async {
      debug = (await createFakeDebugService()).service;
    });
    addTearDown(debug.dispose);
    final host = FakeWorkbenchHost();
    final services = WorkbenchServices()
      ..add<WorkbenchHost>(host)
      ..add(WorkbenchStorage());
    final layout = services.add(
      LayoutService(host: host, layout: () => workspace.layout),
    );
    final panes = services.add(EditorPaneRegistry());
    final editors = services.add(
      EditorService(
        host: host,
        panes: panes,
        workspace: () => workspace,
        layout: () => workspace.layout,
        history: () => services.find<NavigationHistoryService>(),
        focusWorkbench: () {},
      ),
    );
    final language = services.add(
      LanguageService(
        host: host,
        caret: () => const Position(1, 1),
        applyEdit: (_) async => true,
        ignored: () => const {},
      ),
    );
    services
      ..add(ExplorerService(host: host, settings: () => null))
      ..add(ScmService(host: host, storage: services.get()))
      ..add(
        TerminalViewService(
          terminals: null,
          owned: true,
          host: host,
          layout: () => workspace.layout,
        ),
      )
      ..add(
        DebugViewService(
          host: host,
          given: () => debug,
          layout: () => workspace.layout,
          selection: () => null,
        ),
      )
      ..add(
        AutoSaveService(
          host: host,
          config: ConfigurationService(settings: () => null),
          editors: editors,
          workspace: () => workspace,
        ),
      )
      ..add(
        SearchViewService(
          host: host,
          layout: layout,
          editors: editors,
          workspace: () => workspace,
          textSearch: () => ideSearchText,
          storage: services.get(),
        ),
      )
      ..add(
        ExtensionsViewService(
          host: host,
          environment: _Environment(),
          quickInput: QuickInputService(
            host: host,
            registry: QuickAccessRegistry(),
            focusWorkbench: () {},
          ),
          themes: () => null,
          languageServers: () => null,
          notify: (_) {},
        ),
      )
      ..add(
        ProblemsService(
          host: host,
          language: language,
          layout: () => workspace.layout,
          caret: () => const Position(1, 1),
          activePath: () => workspace.active?.path,
          showHover: () {},
        ),
      )
      ..add(
        ReferencesService(
          host: host,
          layout: () => workspace.layout,
          caret: () => const Position(1, 1),
          activePath: () => workspace.active?.path,
        ),
      );
    final binding = WorkspaceBinding(services);
    addTearDown(() {
      host.context = null;
      binding.detach();
      services.dispose();
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

    binding.attach(workspace);
    expect(services.get<IdeWorkspace>(), same(workspace));
    expect(binding.workspace, same(workspace));
    // No terminals here: the panel has no TERMINAL tab.
    expect(workspace.layout.terminals, isFalse);

    // An editor opened from the Git log's place: the explorer's view back
    // beside it, the chat's maximizing ended.
    layout.view = IdeSideView.sourceControl;
    workspace.layout.chat = true;
    await editors.open(inRoot('a.txt'));
    tester.binding.scheduleFrame();
    await tester.pump();
    expect(layout.view, IdeSideView.explorer);
    expect(workspace.layout.editorVisible, isTrue);
    final history = services.get<NavigationHistoryService>();

    // Another workspace: the services on it, the history its own.
    final second = workspaceOf('b.txt');
    addTearDown(second.dispose);
    binding.detach();
    expect(services.find<IdeWorkspace>(), isNull);
    expect(services.find<NavigationHistoryService>(), isNull);
    workspace = second;
    binding.attach(second);
    expect(services.get<IdeWorkspace>(), same(second));
    expect(services.get<NavigationHistoryService>(), isNot(same(history)));
    await editors.open(inRoot('b.txt'));
    await tester.pump();
    expect(second.active?.name, 'b.txt');
    // The first one's layout no longer followed.
    var changes = 0;
    layout.addListener(() => changes++);
    first.layout.sidebar = !first.layout.sidebar;
    expect(changes, 0);
    second.layout.sidebar = !second.layout.sidebar;
    expect(changes, 1);
  });
}

class _Environment implements WorkbenchEnvironment {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
