import 'dart:io';

import '../platform/app_paths.dart';
import 'editor_launcher.dart';
import 'window_controls.dart';

/// Opens [path] in [editor], or in the app the system opens it with when
/// [editor] is null; false where that cannot be done or it failed.
Future<bool> openPath(String path, {Editor? editor}) async {
  path = AppPaths.expandHome(path);
  if (Platform.isMacOS) return _onMacOS(path, editor?.macApp);
  if (Platform.isWindows) return _onWindows(path, editor);
  return false;
}

/// `open [-a app] path`, on macOS.
Future<bool> _onMacOS(String path, String? appName) async {
  try {
    final result = await Process.run('open', [
      if (appName != null) ...['-a', appName],
      path,
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// The shell opens it, on Windows: `ShellExecute` finds the app on the
/// PATH (see windows/runner/window_channel.cpp), which is also how a
/// `.cmd` shim and a console app are started the way they expect.
Future<bool> _onWindows(String path, Editor? editor) {
  final command = editor?.command;
  if (command == null) return WindowControls.openExternal(path);
  return WindowControls.openExternal(
    path,
    app: command,
    // Windows Terminal opens in the folder with `-d`; the editors take it
    // as the file to open.
    arguments: editor == Editor.terminal ? ['-d', path] : const [],
  );
}
