import 'dart:io';

import 'workspace_trust.dart';

/// The trusted folders' file: `workspaceTrust.json` in the app's data
/// folder, written whole through a temporary file.
final class FileWorkspaceTrustStorage implements WorkspaceTrustStorage {
  FileWorkspaceTrustStorage(this.path);

  final String path;

  @override
  Future<String?> read() async {
    final file = File(path);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final temp = File('$path.tmp');
    await temp.writeAsString(contents, flush: true);
    await temp.rename(path);
  }
}
