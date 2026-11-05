// The terminal's commands and context keys (terminal.contribution.ts,
// terminalActions.ts, terminal.find.contribution.ts, terminalContextKey.ts),
// over the window's TerminalViewService.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../lsp_ui/problems_panel.dart' show IdePanelTab;
import '../../services/layout.dart';
import '../../services/terminal_view.dart';
import '../../terminal/terminal_instance.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';

class TerminalContribution extends WorkbenchRegistrations {
  TerminalContribution(WorkbenchServices services) {
    final view = services.get<TerminalViewService>();
    final terminals = view.terminals;
    bool hasTerminals(WorkbenchServices _) => terminals != null;
    bool hasActive(WorkbenchServices _) => view.active != null;
    bool selected() => view.active?.selection.hasSelection ?? false;

    /// One on the active terminal (upstream
    /// `registerActiveInstanceAction`).
    WorkbenchAction active(
      String id,
      void Function(TerminalInstance terminal) run, {
      bool Function()? enabled,
    }) => WorkbenchAction.catalog(
      'workbench.action.terminal.$id',
      precondition: (_) => view.active != null && (enabled?.call() ?? true),
      run: (_, _) {
        if (view.active case final terminal?) run(terminal);
      },
    );

    add(
      services.get<ActionRegistry>().registerAll([
        WorkbenchAction(
          id: 'workbench.action.terminal.toggleTerminal',
          category: 'Terminal',
          title: 'Toggle Terminal',
          precondition: hasTerminals,
          run: (_, _) => view.toggle(),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.new',
          category: 'Terminal',
          title: 'Create New Terminal',
          precondition: hasTerminals,
          run: (_, _) => view.create(),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.newWithProfile',
          category: 'Terminal',
          title: 'Create New Terminal (With Profile)',
          precondition: hasTerminals,
          takesArgs: true,
          run: (_, args) => unawaited(view.createWithProfile(args)),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.selectDefaultShell',
          category: 'Terminal',
          title: 'Select Default Profile',
          precondition: (_) => terminals?.profiles.canSetDefault ?? false,
          run: (_, _) => unawaited(view.selectDefaultProfile()),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.kill',
          category: 'Terminal',
          title: 'Kill the Active Terminal Instance',
          precondition: hasActive,
          run: (_, _) => terminals?.kill(),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.rename',
          category: 'Terminal',
          title: 'Rename...',
          precondition: hasActive,
          run: (_, _) => view.rename(),
        ),
        // Their keys are the terminal's own, while it has focus (see
        // TerminalPanel): elsewhere they switch editors.
        WorkbenchAction(
          id: 'workbench.action.terminal.focusNext',
          category: 'Terminal',
          title: 'Focus Next Terminal Group',
          precondition: hasActive,
          run: (_, _) => view.cycle(next: true),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.focusPrevious',
          category: 'Terminal',
          title: 'Focus Previous Terminal Group',
          precondition: hasActive,
          run: (_, _) => view.cycle(next: false),
        ),
        WorkbenchAction(
          id: 'workbench.action.terminal.focus',
          category: 'Terminal',
          title: 'Focus Terminal',
          precondition: hasTerminals,
          run: (_, _) => view.show(),
        ),
        if (terminals != null) ...[
          active(
            'copySelection',
            (t) => unawaited(t.clipboard.copySelection()),
            enabled: selected,
          ),
          active(
            'copyAndClearSelection',
            (t) => unawaited(
              t.clipboard.copySelection().then(
                (_) => t.selection.clearSelection(),
              ),
            ),
            enabled: selected,
          ),
          active('paste', (t) => unawaited(t.clipboard.paste())),
          active(
            'pasteSelection',
            (t) => unawaited(t.clipboard.pasteSelection()),
          ),
          active('selectAll', (t) => t.selection.selectAll()),
          active('clear', (t) => t.terminal.clear()),
          active(
            'clearSelection',
            (t) => t.selection.clearSelection(),
            enabled: selected,
          ),
          active('scrollDown', (t) => t.terminal.scrollLines(1)),
          active('scrollDownPage', (t) => t.terminal.scrollPages(1)),
          active('scrollToBottom', (t) => t.terminal.scrollToBottom()),
          active('scrollUp', (t) => t.terminal.scrollLines(-1)),
          active('scrollUpPage', (t) => t.terminal.scrollPages(-1)),
          active('scrollToTop', (t) => t.terminal.scrollToTop()),
          WorkbenchAction.catalog(
            'workbench.action.terminal.killAll',
            precondition: (_) => terminals.instances.isNotEmpty,
            run: (_, _) => view.killAll(),
          ),
          // Find (terminal.find.contribution.ts), on the active
          // terminal's widget.
          active('focusFind', view.focusFind),
          active('hideFind', (t) {
            t.find.hide();
            t.focus();
          }),
          active('findNext', (t) => t.find.findNext()),
          active('findPrevious', (t) => t.find.findPrevious()),
          active('toggleFindRegex', (t) => t.find.toggleRegex()),
          active('toggleFindWholeWord', (t) => t.find.toggleWholeWord()),
          active(
            'toggleFindCaseSensitive',
            (t) => t.find.toggleCaseSensitive(),
          ),
          active(
            'searchWorkspace',
            (t) => services.get<WorkbenchHost>().executeCommand(
              'workbench.action.findInFiles',
              {'query': t.selection.selectionText},
            ),
            enabled: selected,
          ),
          // For keybindings only: Send Sequence, which needs its `text`.
          WorkbenchAction.catalog(
            'workbench.action.terminal.sendSequence',
            palette: false,
            precondition: hasActive,
            takesArgs: true,
            run: (_, args) => view.sendSequence(args),
          ),
        ],
      ]),
    );
    add(services.get<ContextKeyService>().addProvider(view.contextKey));
    if (terminals == null) return;
    final layout = services.get<LayoutService>();
    // Focus into Panel on TERMINAL: its terminal (one made) focused.
    add(layout.focusPanelWith(IdePanelTab.terminal, view.show));
    // VS Code makes a terminal when its view shows with none: as the
    // window opens on it, and as it is shown.
    var shown = layout.panel;
    void panelChanged() {
      if (layout.panel == shown) return;
      shown = layout.panel;
      if (shown == IdePanelTab.terminal) terminals.ensureTerminal();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (layout.panel == IdePanelTab.terminal &&
          services.get<WorkbenchHost>().context != null) {
        terminals.ensureTerminal();
      }
    });
    layout.addListener(panelChanged);
    add(() => layout.removeListener(panelChanged));
  }
}
