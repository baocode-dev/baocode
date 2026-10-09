// The Run and Debug side bar: the configuration row, then the Variables,
// Watch, Call Stack and Breakpoints sections; and the Debug Console as a
// panel of its own.

import 'package:flutter/material.dart';

import '../../ide/ide_list.dart';
import '../../ide/ide_panes.dart';
import '../common/debug_model.dart';
import '../common/debug_types.dart';
import '../service/debug_service.dart';
import 'breakpoints_view.dart';
import 'call_stack_view.dart';
import 'debug_console_view.dart';
import 'debug_strings.dart';
import 'loaded_scripts_view.dart';
import 'run_and_debug_view.dart';
import 'variables_view.dart';
import 'watch_view.dart';

/// Which sections the Run and Debug view shows (`debug.showInStatusBar`
/// aside; VS Code's views can be hidden by the user).
final class DebugViewSections {
  const DebugViewSections({
    this.variables = true,
    this.watch = true,
    this.callStack = true,
    this.breakpoints = true,
    this.loadedScripts = true,
  });

  final bool variables;
  final bool watch;
  final bool callStack;
  final bool breakpoints;
  final bool loadedScripts;
}

/// The Run and Debug side bar view.
class DebugView extends StatefulWidget {
  const DebugView({
    super.key,
    required this.service,
    this.runAndDebugKey,
    this.sections = const DebugViewSections(),
    this.onEditBreakpoint,
    this.expanded,
    this.onToggleExpanded,
  });

  final DebugService service;
  final GlobalKey<RunAndDebugViewState>? runAndDebugKey;
  final DebugViewSections sections;

  /// "Edit Breakpoint" of the breakpoints view (the editor's widget).
  final void Function(Breakpoint breakpoint)? onEditBreakpoint;

  /// Expanded sections; the view keeps its own when null.
  final Set<String>? expanded;
  final ValueChanged<String>? onToggleExpanded;

  @override
  State<DebugView> createState() => _DebugViewState();
}

class _DebugViewState extends State<DebugView> {
  late Set<String> _expanded =
      widget.expanded ?? {'variables', 'watch', 'callStack', 'breakpoints'};
  late final BreakpointsViewController _breakpoints =
      BreakpointsViewController();
  final ChangeNotifier _collapseWatch = _CollapseSignal();
  final ChangeNotifier _collapseStack = _CollapseSignal();

  @override
  void dispose() {
    _breakpoints.dispose();
    _collapseWatch.dispose();
    _collapseStack.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      _expanded = {..._expanded};
      if (!_expanded.remove(id)) _expanded.add(id);
    });
    widget.onToggleExpanded?.call(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = DebugStrings.of(context);
    final service = widget.service;
    final sections = widget.sections;
    final session = service.viewModel.focusedSession;
    final variablesCount = service.viewModel.focusedStackFrame != null
        ? 1
        : null;
    final panes = <IdePane>[
      if (sections.variables)
        IdePane(
          id: 'variables',
          title: s.variables,
          badge: variablesCount != null ? IdeCountBadge(variablesCount) : null,
          body: VariablesView(service: service),
        ),
      if (sections.watch)
        IdePane(
          id: 'watch',
          title: s.watch,
          badge: service.model.getWatchExpressions().isEmpty
              ? null
              : IdeCountBadge(service.model.getWatchExpressions().length),
          actions: watchViewActions(
            context,
            service,
            onCollapseAll: () => (_collapseWatch as _CollapseSignal).fire(),
          ),
          body: WatchView(service: service, collapseAll: _collapseWatch),
        ),
      if (sections.callStack)
        IdePane(
          id: 'callStack',
          title: s.callStack,
          badge: service.model.getSessions().isEmpty
              ? null
              : IdeCountBadge(service.model.getSessions().length),
          actions: callStackViewActions(
            context,
            onCollapseAll: () => (_collapseStack as _CollapseSignal).fire(),
          ),
          body: CallStackView(service: service, collapseAll: _collapseStack),
        ),
      if (sections.breakpoints)
        IdePane(
          id: 'breakpoints',
          title: s.breakpoints,
          actions: breakpointsViewActions(
            context,
            service,
            onAddFunctionBreakpoint: () =>
                _breakpoints.addFunctionBreakpoint(service),
          ),
          body: BreakpointsView(
            service: service,
            controller: _breakpoints,
            onEditBreakpoint: widget.onEditBreakpoint,
          ),
        ),
      if (sections.loadedScripts &&
          (session?.capabilities.flag('supportsLoadedSourcesRequest') ?? false))
        IdePane(
          id: 'loadedScripts',
          title: s.loadedScripts,
          body: LoadedScriptsView(service: service),
        ),
    ];

    return Column(
      children: [
        RunAndDebugView(key: widget.runAndDebugKey, service: service),
        const SizedBox(height: 4),
        Expanded(
          child: IdePaneContainer(
            panes: panes,
            expanded: _expanded,
            onToggle: _toggle,
          ),
        ),
      ],
    );
  }
}

/// Tells a view to collapse (the title action).
class _CollapseSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// The Debug Console as a panel: its own view with the console in it.
class DebugConsolePanel extends StatefulWidget {
  const DebugConsolePanel({super.key, required this.service});

  final DebugService service;

  @override
  State<DebugConsolePanel> createState() => _DebugConsolePanelState();
}

class _DebugConsolePanelState extends State<DebugConsolePanel> {
  final GlobalKey<DebugConsoleViewState> _consoleKey = GlobalKey();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PanelTitle(
        title: DebugStrings.of(context).debugConsole,
        actions: _consoleKey.currentState?.actions(context) ?? const [],
      ),
      Expanded(
        child: DebugConsoleView(key: _consoleKey, service: widget.service),
      ),
    ],
  );
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.actions});

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Container(
    height: 26,
    color: IdeListColors.inactiveSelection,
    child: Row(
      children: [
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 11, color: IdeListColors.foreground),
          ),
        ),
        ...actions,
        const SizedBox(width: 4),
      ],
    ),
  );
}

/// The sections a session's state makes useful (the breakpoints view is
/// always there, as in VS Code).
List<String> debugVisibleSections(DebugState state) => const [
  'variables',
  'watch',
  'callStack',
  'breakpoints',
  'loadedScripts',
];
