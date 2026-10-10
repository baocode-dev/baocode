// `vscode.window.showOpenDialog` / `showSaveDialog` on the app's native
// panels (lib/workspace/window_controls.dart).

import '../../workspace/window_controls.dart';
import '../window/window_ports.dart';

/// [ExtensionFilePickers] on the window's open and save panels. The panels
/// take a folder and a name; titles, button labels and file filters are
/// not theirs to show (docs/extensions/EXTHOST_PARITY.md).
final class WindowFilePickers implements ExtensionFilePickers {
  const WindowFilePickers();

  @override
  Future<List<String>?> pickOpen({
    required bool files,
    required bool folders,
    required bool many,
    String? directory,
    String? title,
    String? openLabel,
    Map<String, List<String>> filters = const {},
  }) async {
    // A folder panel when folders alone are asked for; files otherwise.
    if (folders && !files) {
      final folder = await WindowControls.pickDirectory();
      return folder == null ? null : [folder];
    }
    final paths = await WindowControls.pickOpenFiles(
      directory: directory,
      multiple: many,
    );
    return paths.isEmpty ? null : paths;
  }

  @override
  Future<String?> pickSave({
    String? directory,
    String? name,
    String? title,
    String? saveLabel,
    Map<String, List<String>> filters = const {},
  }) => WindowControls.pickSaveFile(directory: directory, name: name);
}
