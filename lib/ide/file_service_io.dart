import 'dart:async';
import 'dart:io';

import 'package:bao_remote/local.dart';
import 'package:path/path.dart' as p;

import '../platform/data_dir.dart';
import 'file_service.dart';
import 'host_paths.dart';

export 'package:bao_remote/local.dart'
    show readFileBytes, walkProjectFiles, watchDirectory;

class LocalIdeFileService extends LocalFiles implements IdeFileService {
  LocalIdeFileService(super.root);
}

/// How many bytes the file at [path] takes.
Future<int> fileByteSize(String path) => File(path).length();

Future<void> uploadTo(
  IdeFileService files,
  List<({String from, String to})> items, {
  TransferProgress? onProgress,
}) async {
  final folders = <String>[];
  final copies = <({String from, String to})>[];
  Future<void> walk(String from, String to) async {
    switch (await FileSystemEntity.type(from)) {
      case FileSystemEntityType.directory:
        folders.add(to);
        await for (final entry in Directory(from).list(followLinks: false)) {
          // A link to a folder is left out: it may lead back up.
          if (entry is Link && await FileSystemEntity.isDirectory(entry.path)) {
            continue;
          }
          await walk(
            entry.path,
            hostPathsFor(to).join(to, p.basename(entry.path)),
          );
        }
      case FileSystemEntityType.file:
        copies.add((from: from, to: to));
      default:
        throw IdeFileNotFoundException(from);
    }
  }

  for (final (:from, :to) in items) {
    await walk(from, to);
  }
  for (final folder in folders) {
    await files.create(folder, directory: true);
  }
  onProgress?.call(0, copies.length);
  for (final (i, (:from, :to)) in copies.indexed) {
    await files.writeBytes(to, await File(from).readAsBytes());
    onProgress?.call(i + 1, copies.length);
  }
}

Future<void> downloadFrom(
  IdeHostFiles files,
  List<({String from, String to, bool directory})> items, {
  TransferProgress? onProgress,
  FileProgress? onFile,
  Future<void>? cancel,
}) async {
  var cancelled = false;
  unawaited(cancel?.then((_) => cancelled = true));
  void check() {
    if (cancelled) throw const TransferCancelledException();
  }

  final folders = <String>[];
  final copies = <({String from, String to})>[];
  Future<void> walk(String from, String to, {required bool directory}) async {
    if (!directory) {
      copies.add((from: from, to: to));
      return;
    }
    folders.add(to);
    for (final entry in await files.list(from)) {
      await walk(
        entry.path,
        p.join(to, entry.name),
        directory: entry.isDirectory,
      );
    }
  }

  for (final (:from, :to, :directory) in items) {
    check();
    await walk(from, to, directory: directory);
  }
  for (final folder in folders) {
    await Directory(folder).create(recursive: true);
  }
  onProgress?.call(0, copies.length);
  for (final (i, (:from, :to)) in copies.indexed) {
    check();
    await _download(files, from, to, onFile: onFile, cancel: cancel);
    onProgress?.call(i + 1, copies.length);
  }
}

/// How much of a file one request reads: small enough that the agent's
/// messages on the same connection are not held up long behind it.
const _rangeLength = 512 * 1024;

/// Writes [from], a file of [files]' host, to [to] here: a stretch at a
/// time where it can be, nothing left of it when given up or failed.
Future<void> _download(
  IdeHostFiles files,
  String from,
  String to, {
  FileProgress? onFile,
  Future<void>? cancel,
}) async {
  final file = File(to);
  await file.parent.create(recursive: true);
  if (files is! IdeRangeFiles) {
    await file.writeAsBytes(await files.readBytes(from));
    return;
  }
  final ranges = files as IdeRangeFiles;
  var cancelled = false;
  unawaited(cancel?.then((_) => cancelled = true));
  final sink = file.openWrite();
  var done = false;
  try {
    var offset = 0;
    while (true) {
      if (cancelled) throw const TransferCancelledException();
      final (:bytes, :size) = await ranges.readRange(
        from,
        offset,
        _rangeLength,
        cancel: cancel,
      );
      if (cancelled) throw const TransferCancelledException();
      sink.add(bytes);
      offset += bytes.length;
      onFile?.call(offset, size);
      if (bytes.isEmpty || offset >= size) break;
    }
    done = true;
  } on Object {
    if (cancelled) throw const TransferCancelledException();
    rethrow;
  } finally {
    await sink.close();
    if (!done) await file.delete().catchError((Object _) => file);
  }
}

/// How long downloads for other apps are kept: pasted or dropped, they
/// were copied from there.
const _downloadsKept = Duration(days: 1);

Future<String> newDownloadFolder() async {
  final downloads = Directory(
    p.join(DataDirectory.current.cacheDir, 'remote-files'),
  );
  final now = DateTime.now();
  if (await downloads.exists()) {
    await for (final old in downloads.list()) {
      try {
        if (now.difference((await old.stat()).modified) > _downloadsKept) {
          await old.delete(recursive: true);
        }
      } on FileSystemException {
        // In use, or gone: left for another time.
      }
    }
  }
  final folder = Directory(
    p.join(downloads.path, '${now.microsecondsSinceEpoch}'),
  );
  await folder.create(recursive: true);
  return folder.path;
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
    await _download(files, from, to);
  } else if (!p.equals(from, to)) {
    await File(from).copy(to);
  }
}
