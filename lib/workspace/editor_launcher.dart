import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'editor_launcher_stub.dart'
    if (dart.library.io) 'editor_launcher_io.dart'
    as platform;

/// An app a project can be opened in, named as each platform has it.
enum Editor {
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

  final IconData icon;

  /// What the platform calls it.
  String get platformLabel => _windows ? (windowsLabel ?? label) : label;

  /// Whether the platform has it at all.
  bool get available => !macOSOnly || !_windows;

  /// The apps this platform can open a project in, in the order of the
  /// menu.
  static List<Editor> get availableEditors => [
    for (final editor in values)
      if (editor.available) editor,
  ];

  static bool get _windows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}

/// Opens [path] in [editor]. False where that is not possible (the web, a
/// platform that has no such app) or it failed, e.g. the app is not
/// installed.
Future<bool> openInEditor(Editor editor, String path) =>
    platform.openPath(path, editor: editor);

/// Opens a link or file in its default app (the browser, for a URL).
Future<bool> openExternal(String target) => platform.openPath(target);
