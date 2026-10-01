import 'workspace.dart';

/// The window the app opens to: the `workbench.mainWindow` setting. Chat
/// is the app's own; the IDE is beside it. (The `code` command opens in
/// the IDE whichever it is.)
enum MainWindow {
  chat,
  ide,

  /// Whichever was shown when the app last quit.
  last;

  static const settingKey = 'workbench.mainWindow';

  /// When the setting is unset, or not one of these.
  static const fallback = chat;

  static MainWindow parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  /// The layout to show at launch, given the one kept from the last run.
  WorkspaceLayout layoutAtLaunch(WorkspaceLayout kept) => switch (this) {
    chat => WorkspaceLayout.chat,
    ide => WorkspaceLayout.ide,
    last => kept,
  };
}
