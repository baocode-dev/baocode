// JSONC files read and written through the workspace's file service: a
// remote project's `.vscode/settings.json` and `tasks.json`, on its host.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../../settings/jsonc_file.dart';
import 'file_service.dart';
import 'file_types.dart';

final class FileServiceJsoncStorage implements JsoncFileStorage {
  FileServiceJsoncStorage(this.files);

  final FileService files;

  @override
  Future<String?> read(String path) async {
    final uri = VsUri.file(path);
    if (!await files.exists(uri)) return null;
    return utf8.decode(await files.readFile(uri), allowMalformed: true);
  }

  @override
  Future<void> write(String path, String text) async {
    final folder = VsUri.file(p.dirname(path));
    if (!await files.exists(folder)) await files.createFolder(folder);
    await files.writeFile(
      VsUri.file(path),
      Uint8List.fromList(utf8.encode(text)),
    );
  }

  /// Its folder watched (not recursively), the changes to it (or to the
  /// folder: a remote host says which folder changed, not what).
  @override
  Stream<void> changes(String path) {
    late final StreamController<void> controller;
    void Function()? stop;
    final folder = p.dirname(path);
    controller = StreamController<void>(
      onListen: () {
        stop = files.createWatcher(
          VsUri.file(folder),
          const WatchOptions(recursive: false),
          (changes) {
            if (changes.any(
              (c) => c.resource.path == path || c.resource.path == folder,
            )) {
              controller.add(null);
            }
          },
        );
      },
      onCancel: () => stop?.call(),
    );
    return controller.stream;
  }
}
