import 'workspace.dart';

/// The window the app opens to: the `workbench.mainWindow` setting. Chat
/// is the app's own; the IDE is beside it. One or the other, never both
/// (see AppWindows.prepareLaunch). (The `code` command opens in the IDE
/// whichever it is.)
enum MainWindow {
  /// Where it was left: the chat or the IDE, whichever was in front when
  /// the app last quit (the default).
  last,

  /// The chat (the agents), always.
  chat,

  /// The IDE, always.
  ide;

  static const settingKey = 'workbench.mainWindow';

  /// When the setting is unset, or not one of these.
  static const fallback = last;

  static MainWindow parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  /// The layout to show at launch, given the one kept from the last run.
  WorkspaceLayout layoutAtLaunch(WorkspaceLayout kept) => switch (this) {
    chat => WorkspaceLayout.chat,
    ide => WorkspaceLayout.ide,
    last => kept,
  };
}
