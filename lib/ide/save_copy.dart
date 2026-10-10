import 'package:path/path.dart' as p;

import '../workspace/window_controls.dart';
import 'file_service.dart';

/// Whether a file shown can be saved elsewhere ([saveFileCopyAs]): where
/// there is a save panel.
bool get canSaveFileCopy => WindowControls.canPickFiles;

/// Save As… of the file [path] in a context menu: asks where on this
/// machine (the native save panel), then copies it there through [files],
/// downloading it from a remote project's host; [text] is written instead
/// when given. The path saved to, or null when cancelled.
Future<String?> saveFileCopyAs(
  IdeFileService files,
  String path, {
  String? text,
}) async {
  final local = files is! IdeHostFiles;
  final to = await WindowControls.pickSaveFile(
    // Not a folder of the host's: the panel is this machine's.
    directory: local ? p.dirname(path) : null,
    name: local ? p.basename(path) : p.posix.basename(path),
  );
  if (to == null) return null;
  await saveCopyTo(files, path, to, text: text);
  return to;
}
