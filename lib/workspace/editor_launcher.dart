import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../platform/app_platform.dart';

import 'editor_launcher_stub.dart'
    if (dart.library.io) 'editor_launcher_io.dart'
    as platform;

/// An app a project can be opened in, named as each platform has it.
enum Editor {
  /// BaoCode's own editor: the IDE layout, not an app to launch.
  fastIde(
    'Fast Ide',
    null,
    icon: Icons.space_dashboard_outlined,
    builtIn: true,
  ),
  vscode(
    'VS Code',
    'code',
    macApp: 'Visual Studio Code',
    icon: Icons.code_rounded,
  ),
  cursor('Cursor', 'cursor', macApp: 'Cursor', icon: Icons.near_me_outlined),
  zed('Zed', 'zed', macApp: 'Zed', icon: Icons.bolt_rounded),
  xcode(
    'Xcode',
    null,
    macApp: 'Xcode',
    icon: Icons.build_outlined,
    macOSOnly: true,
  ),
  folder(
    'Finder',
    null,
    windowsLabel: 'File Explorer',
    icon: Icons.folder_open_outlined,
  ),
  terminal(
    'Terminal',
    'wt',
    macApp: 'Terminal',
    windowsLabel: 'Windows Terminal',
    icon: Icons.terminal_rounded,
  );

  const Editor(
    this.label,
    this.command, {
    required this.icon,
    this.macApp,
    this.windowsLabel,
    this.macOSOnly = false,
    this.builtIn = false,
  });

  /// What macOS calls it.
  final String label;

  /// The command to run on Windows, found on the PATH by the shell (see
  /// window_controls.dart); null where the platform opens the project
  /// itself (the file manager), or has no such app.
  final String? command;

  /// The macOS app to open with; null for the default (Finder, for a
  /// folder).
  final String? macApp;

  /// What Windows calls it, where that differs.
  final String? windowsLabel;

  /// Whether only macOS has it.
  final bool macOSOnly;

  /// Whether it is BaoCode's own ([fastIde]), shown instead of launched.
  final bool builtIn;

  final IconData icon;

  /// What the platform calls it.
  String get platformLabel =>
      AppPlatform.isWindows ? (windowsLabel ?? label) : label;

  /// [platformLabel] in [l10n]'s language: the system's own apps are named
  /// as the system names them there.
  String localizedPlatformLabel(AppLocalizations l10n) => switch (this) {
    folder when AppPlatform.isWindows => l10n.workspaceFileExplorer,
    folder => l10n.workspaceFinder,
    terminal when AppPlatform.isWindows => l10n.workspaceWindowsTerminal,
    terminal => l10n.workspaceTerminalApp,
    _ => platformLabel,
  };

  /// Whether the platform has it at all.
  bool get available => !macOSOnly || !AppPlatform.isWindows;

  /// The apps this platform can open a project in, in the order of the
  /// menu.
  static List<Editor> get availableEditors => [
    for (final editor in values)
      if (editor.available) editor,
  ];
}

/// Opens [path] in [editor]. False where that is not possible (the web, a
/// platform that has no such app) or it failed, e.g. the app is not
/// installed.
Future<bool> openInEditor(Editor editor, String path) async =>
    !editor.builtIn && await platform.openPath(path, editor: editor);

/// Opens a link or file in its default app (the browser, for a URL).
Future<bool> openExternal(String target) => platform.openPath(target);
