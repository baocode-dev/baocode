import 'dart:io';

import 'package:bao_remote/local.dart';
import 'package:path/path.dart' as p;

import 'file_service.dart';

export 'package:bao_remote/local.dart'
    show readFileBytes, walkProjectFiles, watchDirectory;

class LocalIdeFileService extends LocalFiles implements IdeFileService {
  LocalIdeFileService(super.root);
}

Future<void> copyLocalTo(IdeFileService files, String from, String to) async {
  switch (await FileSystemEntity.type(from)) {
    case FileSystemEntityType.directory:
      await files.create(to, directory: true);
      await for (final entry in Directory(from).list(followLinks: false)) {
        // A link to a folder is left out: it may lead back up.
        if (entry is Link && await FileSystemEntity.isDirectory(entry.path)) {
          continue;
        }
        await copyLocalTo(
          files,
          entry.path,
          p.posix.join(to, p.basename(entry.path)),
        );
      }
    case FileSystemEntityType.file:
      await files.writeBytes(to, await File(from).readAsBytes());
    default:
      throw IdeFileNotFoundException(from);
  }
}

Future<void> saveCopyTo(
  IdeFileService files,
  String from,
  String to, {
  String? text,
}) async {
  final file = File(to);
  if (text != null) {
    await file.writeAsString(text);
  } else if (files is IdeHostFiles) {
    await file.writeAsBytes(await files.readBytes(from));
  } else if (!p.equals(from, to)) {
    await File(from).copy(to);
  }
}
