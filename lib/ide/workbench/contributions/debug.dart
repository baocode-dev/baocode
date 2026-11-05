// The debugger's commands (debugCommands.ts, debug.contribution.ts), its
// context keys, and the status bar's mark of a session debugged
// (statusbarColorProvider.ts), over the window's DebugViewService.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../../debug/common/debug_model.dart' show Thread;
import '../../../debug/common/debug_types.dart';
import '../../../debug/ui/debug_strings.dart';
import '../../../debug/ui/debug_toolbar.dart' show debugActionThread;
import '../../../keybindings/keybinding_service.dart';
import '../../../theme/codicons.dart';
import '../../../theme/workbench_theme.dart' show themeColors;
import '../../ide_status_bar.dart';
import '../../services/debug_view.dart';
import '../actions.dart';
import '../context_keys.dart';
import '../contributions.dart';
import '../services.dart';
import '../statusbar.dart';
import '../views.dart';

/// The status bar's debugging mark: right of the remote's entry.
const debuggingPriority = 90.0;

class DebugContribution extends WorkbenchRegistrations {
  DebugContribution(WorkbenchServices services) {
    final debug = services.get<DebugViewService>();
    final host = services.get<WorkbenchHost>();
    bool hasDebugger(WorkbenchServices _) => debug.service != null;
    bool stopped(WorkbenchServices _) =>
        debug.service != null && debugActionThread(debug.service!) != null;

    /// One on the thread stepped (the focused one, else the first stopped).
    WorkbenchAction step(
      String id,
      String title,
      Future<void> Function(Thread thread) run,
    ) => WorkbenchAction(
      id: 'workbench.action.debug.$id',
      category: 'Debug',
      title: title,
      precondition: stopped,
      run: (_, _) {
        final thread = switch (debug.service) {
          final service? => debugActionThread(service),
          null => null,
        };
        if (thread != null) unawaited(run(thread));
      },
    );

    if (debugEntryShown) {
      add(
        services.get<ActionRegistry>().registerAll([
          WorkbenchAction(
            id: 'workbench.view.debug',
            category: 'View',
            title: DebugStrings.en.runAndDebug,
            precondition: hasDebugger,
            run: (_, _) => host.showView(IdeSideView.debug),
          ),
          WorkbenchAction(
            id: 'debug.start',
            category: 'Debug',
            title: 'Start Debugging',
            precondition: hasDebugger,
            run: (_, _) => debug.runAndDebug((view) => view.start()),
          ),
          WorkbenchAction(
            id: 'debug.startFromConfig',
            category: 'Debug',
            title: 'Start Debugging from Configuration',
            precondition: hasDebugger,
            takesArgs: true,
            run: (_, args) {
              final config = args is Map ? args.cast<String, Object?>() : null;
              debug.runAndDebug((view) => view.start(config: config));
            },
          ),
          WorkbenchAction(
            id: 'debug.addConfiguration',
            category: 'Debug',
            title: 'Add Configuration...',
            precondition: hasDebugger,
            run: (_, _) => debug.runAndDebug((view) => view.addConfiguration()),
          ),
          WorkbenchAction(
            id: 'debug.openConfigFile',
            category: 'Debug',
            title: 'Open launch.json',
            precondition: hasDebugger,
            run: (_, _) => debug.runAndDebug((view) => view.openConfigFile()),
          ),
          WorkbenchAction(
            id: 'workbench.action.debug.run',
            category: 'Debug',
            title: 'Run Without Debugging',
            precondition: hasDebugger,
            run: (_, _) =>
                debug.runAndDebug((view) => view.runWithoutDebugging()),
          ),
          WorkbenchAction(
            id: 'workbench.action.toggleRepl',
            category: 'Debug',
            title: 'Toggle Debug Console',
            precondition: hasDebugger,
            run: (_, _) => debug.toggleRepl(),
          ),
          WorkbenchAction(
            id: 'workbench.action.debug.stop',
            category: 'Debug',
            title: 'Stop Debugging',
            precondition: hasDebugger,
            run: (_, _) => unawaited(debug.service?.stopSession(null)),
          ),
          WorkbenchAction(
            id: 'workbench.action.debug.restart',
            category: 'Debug',
            title: 'Restart Debugging',
            precondition: (_) =>
                debug.service?.viewModel.focusedSession != null,
            run: (_, _) {
              final service = debug.service;
              final session = service?.viewModel.focusedSession;
              if (session != null) unawaited(service!.restartSession(session));
            },
          ),
          step('continue', 'Continue', (thread) => thread.continue_()),
          step('pause', 'Pause', (thread) => thread.pause()),
          step('stepOver', 'Step Over', (thread) => thread.next()),
          step('stepInto', 'Step Into', (thread) => thread.stepIn()),
          step('stepOut', 'Step Out', (thread) => thread.stepOut()),
        ]),
      );
    }
    add(
      services.get<ContextKeyService>().addProvider(
        (key) => key == 'inDebugMode' ? debug.inDebugMode : null,
      ),
    );
    add(
      services
          .get<StatusbarService>()
          .addEntry(
            'status.debugging',
            StatusbarAlignment.left,
            priority: debuggingPriority,
            changes: Listenable.merge([debug, KeybindingService.instance]),
            (context) => _debuggingItem(context, debug, host),
          )
          .dispose,
    );
  }
}

/// While a session is debugged, a mark of the debugging colors: the bar
/// on the window's color, not the bar of them upstream's
/// (statusbarColorProvider.ts).
IdeStatusBarItem? _debuggingItem(
  BuildContext context,
  DebugViewService debug,
  WorkbenchHost host,
) {
  final service = debug.service;
  if (service == null || service.state == DebugState.inactive) return null;
  final s = DebugStrings.of(context);
  final background = themeColors['statusBar.debuggingBackground'];
  final foreground = themeColors['statusBar.debuggingForeground'];
  return IdeStatusBarItem(
    service.viewModel.focusedSession?.getLabel() ?? s.runAndDebug,
    icon: Codicons.debugAltSmall,
    color: foreground,
    background: background,
    hoverBackground: Color.alphaBlend(
      foreground.withValues(alpha: 0.12),
      background,
    ),
    tooltip: KeybindingService.instance.titleWithKeybinding(
      s.runAndDebug,
      'workbench.view.debug',
    ),
    onTap: () => host.showView(IdeSideView.debug),
  );
}
