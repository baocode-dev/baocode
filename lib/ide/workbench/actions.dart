// The workbench's actions: a command's id, title and keybindings with what
// it runs, registered by the feature it is of (upstream `registerAction2`,
// src/vs/platform/actions/common/actions.ts), and run with the window's
// services rather than a widget's state.

import 'package:flutter/foundation.dart';

import '../../keybindings/default_keybindings.dart' show commandCatalog;
import '../ide_commands.dart';
import 'services.dart';

/// One command of the workbench's.
@immutable
class WorkbenchAction {
  const WorkbenchAction({
    required this.id,
    required this.title,
    required this.run,
    this.category,
    this.keybindings = const [],
    this.keybindingLabel,
    this.palette = true,
    this.precondition,
    this.takesArgs = false,
    this.titleFor,
  });

  /// One of the keybindings' catalog, its title and category the
  /// catalog's.
  factory WorkbenchAction.catalog(
    String id, {
    required void Function(WorkbenchServices services, Object? args) run,
    bool Function(WorkbenchServices services)? precondition,
    bool palette = true,
    bool takesArgs = false,
  }) {
    final info = commandCatalog[id];
    return WorkbenchAction(
      id: id,
      title: info?.title ?? id,
      category: info?.category,
      run: run,
      precondition: precondition,
      palette: palette,
      takesArgs: takesArgs,
    );
  }

  /// The command's id, as keybindings and settings name it.
  final String id;

  /// As the Command Palette lists it, after [category].
  final String title;

  /// Its title as things are now, for a toggle's (Turn On / Turn Off):
  /// [title] without.
  final String Function(WorkbenchServices services)? titleFor;
  final String? category;

  /// Keybindings of a command the defaults do not have (see
  /// [IdeCommand.keybindings]).
  final List<IdeKeybinding> keybindings;
  final String? keybindingLabel;

  /// Whether the Command Palette lists it (upstream `f1`); a list's or a
  /// view's key alone not.
  final bool palette;

  /// Whether it runs now (upstream `precondition`); always without one.
  final bool Function(WorkbenchServices services)? precondition;

  /// Runs it, with a keybinding's `args` where it has some.
  final void Function(WorkbenchServices services, Object? args) run;

  /// Whether [run] reads `args` (a keybinding's), so that a keybinding's
  /// `args` reach it rather than it running without.
  final bool takesArgs;

  /// As the palette and the keybindings run it.
  IdeCommand toCommand(WorkbenchServices services) => IdeCommand(
    id: id,
    label: titleFor?.call(services) ?? title,
    category: category,
    keybindings: keybindings,
    keybindingLabel: keybindingLabel,
    enabled: precondition?.call(services) ?? true,
    run: () => run(services, null),
    runWithArgs: takesArgs ? (args) => run(services, args) : null,
  );
}

/// The actions registered, in the order they were: of two with an id, the
/// first runs (as the workbench's commands did, the first of an id kept).
class ActionRegistry extends ChangeNotifier {
  final List<WorkbenchAction> _actions = [];

  List<WorkbenchAction> get actions => List.unmodifiable(_actions);

  /// Adds [action] until the returned callback runs.
  VoidCallback register(WorkbenchAction action) => registerAll([action]);

  VoidCallback registerAll(Iterable<WorkbenchAction> actions) {
    final added = [...actions];
    _actions.addAll(added);
    notifyListeners();
    return () {
      for (final action in added) {
        _actions.remove(action);
      }
      notifyListeners();
    };
  }

  WorkbenchAction? byId(String id) {
    for (final action in _actions) {
      if (action.id == id) return action;
    }
    return null;
  }

  /// The actions as commands, with what [services] has now: those the
  /// palette lists where [palette].
  List<IdeCommand> commands(
    WorkbenchServices services, {
    bool palette = false,
  }) => [
    for (final action in _actions)
      if (!palette || action.palette) action.toCommand(services),
  ];
}
