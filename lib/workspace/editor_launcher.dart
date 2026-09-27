import 'package:flutter/material.dart';

import 'editor_launcher_stub.dart'
    if (dart.library.io) 'editor_launcher_io.dart'
    as platform;

/// Apps a project can be opened in.
enum Editor {
  vscode('VS Code', 'Visual Studio Code', Icons.code_rounded),
  cursor('Cursor', 'Cursor', Icons.near_me_outlined),
  zed('Zed', 'Zed', Icons.bolt_rounded),
  xcode('Xcode', 'Xcode', Icons.build_outlined),
  finder('Finder', null, Icons.folder_open_outlined),
  terminal('Terminal', 'Terminal', Icons.terminal_rounded);

  const Editor(this.label, this.appName, this.icon);

  final String label;

  /// The macOS app to open with; null for the default (Finder, for a
  /// folder).
  final String? appName;
  final IconData icon;
}

/// Opens [path] in [editor]. False where that is not possible (the web, a
/// platform other than macOS) or it failed, e.g. the app is not installed.
Future<bool> openInEditor(Editor editor, String path) =>
    platform.openPath(path, appName: editor.appName);
