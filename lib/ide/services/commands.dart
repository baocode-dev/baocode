// The window's commands as the Command Palette and the keybindings find
// them (upstream `ICommandService` with the palette's
// `CommandsQuickAccessProvider`): the registered actions first, then
// those of the sources not yet actions (the workbench's own, the editor's,
// the host's, the extensions'); of two with an id, the first is kept.

import 'package:flutter/foundation.dart';

import '../ide_commands.dart';
import '../workbench/actions.dart';
import '../workbench/services.dart';

class CommandService {
  CommandService({required this._services, required this._actions});

  final WorkbenchServices _services;
  final ActionRegistry _actions;

  final List<({List<IdeCommand> Function() commands, bool palette})> _sources =
      [];

  /// The commands run from the palette, the latest first.
  final IdeRecentList recent = IdeRecentList();

  /// [commands] among the window's until the returned callback runs: in
  /// the palette where [palette], for keybindings alone where not.
  VoidCallback addSource(
    List<IdeCommand> Function() commands, {
    bool palette = true,
  }) {
    final source = (commands: commands, palette: palette);
    _sources.add(source);
    return () => _sources.remove(source);
  }

  /// The commands the palette lists, as they are now.
  List<IdeCommand> palette() => [
    ..._actions.commands(_services, palette: true),
    for (final source in _sources)
      if (source.palette) ...source.commands(),
  ];

  /// Every command, the palette's and the keybindings' alone, by id.
  Map<String, IdeCommand> byId() {
    final byId = <String, IdeCommand>{};
    for (final command in [
      ..._actions.commands(_services),
      for (final source in _sources) ...source.commands(),
    ]) {
      byId.putIfAbsent(command.id, () => command);
    }
    return byId;
  }

  /// Runs [command], as the palette does: it is the latest run.
  void run(IdeCommand command) {
    recent.add(command.id);
    command.run();
  }

  /// Runs the command [id], as a menu does; false when there is none, or
  /// it cannot run now.
  bool runById(String id) {
    final command = byId()[id];
    if (command == null || !command.enabled) return false;
    run(command);
    return true;
  }
}
