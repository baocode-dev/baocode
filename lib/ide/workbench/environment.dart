// What the app gives a window, as the services read it now (upstream
// `IWorkbenchEnvironmentService` with the host's own commands): the
// IdeWorkbench widget's options, which the app may change as it runs.

import '../../settings/user_settings.dart';
import '../ide_color_theme_picker.dart' show IdeColorThemeController;
import '../ide_commands.dart';

abstract interface class WorkbenchEnvironment {
  /// settings.json, where the app has one.
  UserSettings? get settings;

  /// The color themes to pick from, where the app has them.
  IdeColorThemeController? get colorThemes;

  /// The app's commands (Open Folder…, Settings), after the workbench's.
  List<IdeCommand> get hostCommands;
}

extension WorkbenchEnvironmentCommands on WorkbenchEnvironment {
  /// The app's command [id], to run it from another id.
  IdeCommand? hostCommand(String id) =>
      hostCommands.where((command) => command.id == id).firstOrNull;
}
