// launch.json on the local file system.

import 'dart:io';

import '../../base/uri.dart' show VsUri;

import 'debug_configuration_manager.dart';

/// Reads and writes `file:` URIs.
final class IoLaunchFileStore implements LaunchFileStore {
  const IoLaunchFileStore({this.windows = false});

  final bool windows;

  @override
  Future<String?> read(VsUri uri) async {
    if (uri.scheme != 'file') return null;
    final file = File(uri.fsPath(windows: windows));
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(VsUri uri, String content) async {
    if (uri.scheme != 'file') throw UnsupportedError('Cannot write ${uri.scheme} URIs');
    final file = File(uri.fsPath(windows: windows));
    await file.parent.create(recursive: true);
    await file.writeAsString(content, flush: true);
  }
}
