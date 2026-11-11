// The panel (upstream panelPart.ts): Problems, References, the
// terminals and the debug console, on a card under the editor; built again
// as its tab, the language servers, the references, the terminals and
// the debugger change.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../debug/ui/debug_view.dart';
import '../../../keybindings/keybinding_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/workbench_theme.dart';
import '../../../workspace/editor_launcher.dart';
import '../../../workspace/islands.dart';
import '../../ide_modern_ui.dart';
import '../../lsp_ui/problems_panel.dart';
import '../../services/debug_view.dart';
import '../../services/editors.dart';
import '../../services/explorer.dart';
import '../../services/keybindings.dart';
import '../../services/language.dart';
import '../../services/layout.dart';
import '../../services/problems.dart';
import '../../services/quick_input.dart';
import '../../services/references.dart';
import '../../services/terminal_view.dart';
import '../../terminal/links/terminal_links.dart';
import '../../terminal/terminal_panel.dart';
import '../contributions.dart';
import '../options.dart';
import '../services.dart';
import '../style.dart';

class PanelPart extends StatelessWidget {
  const PanelPart({super.key, required this.options});

  final WorkbenchOptions options;

  @override
  Widget build(BuildContext context) {
    final services = WorkbenchScope.of(context);
    final layout = services.get<LayoutService>();
    final language = services.get<LanguageService>();
    final references = services.get<ReferencesService>();
    final terminalView = services.get<TerminalViewService>();
    final debugView = services.get<DebugViewService>();
    return ListenableBuilder(
      listenable: Listenable.merge([
        layout,
        language,
        references,
        terminalView,
        debugView,
        // New Terminal asks which of a workspace's folders.
        options.workspace,
        // Labels (the tooltips', the menus') follow the keybindings.
        KeybindingService.instance,
      ]),
      builder: (context, _) {
        final host = services.get<WorkbenchHost>();
        final keys = services.get<KeybindingDispatchService>();
        return Focus(
          focusNode: layout.panelFocus,
          // On a card of its own a gap under the editor's, of the
          // cards' color (not `panel.background`: a card as the
          // others). Not islands, panelPart.ts' `panel.background`,
          // `panel.border` above.
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              WorkbenchStyle.gap / 2,
              WorkbenchStyle.gap,
              WorkbenchStyle.gap / 2,
              0,
            ),
            child: IdePart(
              border: WorkbenchStyle.islands
                  ? null
                  : Border(top: IdePart.side('panel.border')),
              child: Island(
                color: WorkbenchStyle.islands
                    ? AppColors.code
                    : themeColors['panel.background'],
                child: IdeBottomPanel(
                  tab: layout.panel ?? layout.lastPanel,
                  root: options.workspace.root,
                  languages: language.languages,
                  references: references.references,
                  // TERMINAL, clicked, gives its terminal the keyboard.
                  onTab: (tab) => tab == IdePanelTab.terminal
                      ? terminalView.show()
                      : (layout.panel = tab),
                  onClose: () => layout.panel = null,
                  onOpen: (location, {select = false}) => unawaited(
                    services.get<EditorService>().openLocation(
                      location,
                      select: select,
                    ),
                  ),
                  onOpenFocused: (location) =>
                      unawaited(openWithKeyboard(host, location)),
                  problemsList: services.get<ProblemsService>().list,
                  referencesList: references.list,
                  textOf: _textOf,
                  terminal: switch (terminalView.terminals) {
                    final terminals? => TerminalPanel(
                      terminals: terminals,
                      tasks: options.terminalTasks,
                      files: options.workspace.files,
                      shownTask: terminalView.task,
                      onShowTask: terminalView.showTask,
                      onNew: terminalView.create,
                      onOpenLink: (link) => _openLink(services, link),
                      shouldSkipShell: keys.terminalSkipsShell,
                      resolveKey: keys.terminalFindKey,
                      hosts: options.terminalHosts,
                      place: host,
                      shown: options.visible,
                    ),
                    null => null,
                  },
                  debugConsole: switch (debugView.service) {
                    final debug? => DebugConsolePanel(service: debug),
                    null => null,
                  },
                  terminalActions: switch (terminalView.terminals) {
                    final terminals? => TerminalTitleActions(
                      terminals: terminals,
                      onNew: terminalView.create,
                      onNewWithProfile: (profile, {cwd}) =>
                          terminalView.create(profile: profile, cwd: cwd),
                      folders: options.workspace.roots,
                      onSelectDefaultProfile: () =>
                          unawaited(terminalView.selectDefaultProfile()),
                    ),
                    null => null,
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Opens a link from a terminal, as VS Code's link openers: a URL in the
  /// browser, a file in the editor at its line and column, a folder of the
  /// workspace in the explorer (another in the system's file manager, where
  /// VS Code opens a window), a word in quick open.
  void _openLink(WorkbenchServices services, TerminalLink link) {
    switch (link.type) {
      case TerminalLinkType.url:
        unawaited(openExternal(link.text));
      case TerminalLinkType.localFile:
        unawaited(
          services.get<EditorService>().open(
            link.path!,
            line: link.line,
            column: link.column,
            focusEditor: true,
          ),
        );
      case TerminalLinkType.localFolder:
        if (link.inWorkspace) {
          services.get<ExplorerService>().reveal(link.path!);
        } else {
          unawaited(openExternal(link.path!));
        }
      case TerminalLinkType.search:
        services.get<QuickInputService>().show(link.searchText ?? link.text);
    }
  }

  Future<String?> _textOf(String path) async {
    for (final doc in options.workspace.documents) {
      if (doc.path == path) return doc.text;
    }
    return options.workspace.files.read(path);
  }
}
