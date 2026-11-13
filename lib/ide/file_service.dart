import 'dart:convert';
import 'dart:typed_data';

import 'package:bao_remote/files.dart';
import 'package:bao_remote/search.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import 'file_service_stub.dart'
    if (dart.library.io) 'file_service_io.dart'
    as platform;

export 'package:bao_remote/files.dart';

/// The files an open project's IDE reads and writes: the project's, and
/// any other opened, as VS Code opens a file outside its workspace. The
/// web cannot access local files.
abstract interface class IdeFileService {
  factory IdeFileService(String root) = platform.LocalIdeFileService;

  Future<List<IdeFile>> list(String directory);

  /// The file's text. Throws [IdeBinaryFileException] or
  /// [IdeFileTooLargeException] for what the editor does not show unless
  /// [force]d (VS Code's Open Anyway): then malformed UTF-8 is replaced
  /// and the size limit is raised.
  Future<String> read(String path, {bool force = false});

  /// Save a previously read file, rejecting changes to its on-disk baseline.
  /// [expectedText] also protects against another editor using this service.
  Future<void> write(String path, String text, {String? expectedText});

  /// Creates an empty file, or a folder with [directory]; throws
  /// [IdeFileExistsException] when [path] exists.
  Future<void> create(String path, {bool directory = false});

  /// Moves [from] to [to] (a rename); throws [IdeFileExistsException] when
  /// [to] exists.
  Future<void> rename(String from, String to);

  /// Copies [from] (a folder with its contents) to [to]; throws
  /// [IdeFileExistsException] when [to] exists.
  Future<void> copy(String from, String to);

  /// Deletes [path] (a folder with its contents) for good.
  Future<void> delete(String path);

  /// Makes the file [path] of [bytes] (a picture pasted beside a
  /// document); throws [IdeFileExistsException] when [path] exists.
  Future<void> writeBytes(String path, Uint8List bytes);
}

/// A file service of files on another machine (a remote project's host):
/// what the IDE does on the disk besides reading and writing text, it does
/// through it too.
abstract interface class IdeHostFiles implements IdeFileService {
  /// [path]'s bytes (an image's), as [readFileBytes] reads them here.
  Future<Uint8List> readBytes(String path);

  /// Changes to the entries of [directory], as [watchDirectory] here.
  Stream<void> watchDirectory(String directory);

  /// The project's files, as [listProjectFiles] lists them here.
  Future<IdeFileListing> listProject(String root, {int limit = 50000});

  /// The text search of the IDE's Search view, run there.
  Stream<Object> searchText(String root, IdeTextQuery query);
}

/// A host's files read a stretch at a time: a big one downloads without
/// holding up the rest of the connection (the agent's output, its pings),
/// and can be given up partway.
abstract interface class IdeRangeFiles {
  /// At most [length] of [path]'s bytes from [offset] (fewer at its end),
  /// and its size; given up once [cancel] completes.
  Future<({Uint8List bytes, int size})> readRange(
    String path,
    int offset,
    int length, {
    Future<void>? cancel,
  });

  /// How many bytes the files and folders at [paths] take; counted only
  /// until over [limit].
  Future<int> sizeOf(List<String> paths, {int? limit});

  /// Adds [bytes] to the end of [path], which [IdeFileService.writeBytes]
  /// made and is [offset] bytes long so far: a big file uploaded a stretch
  /// at a time.
  Future<void> appendBytes(String path, int offset, Uint8List bytes);
}

/// A download or an upload given up (see [downloadFrom]'s `cancel`).
class TransferCancelledException implements Exception {
  const TransferCancelledException();

  @override
  String toString() => 'The transfer was cancelled';
}

/// [error] as a message in [l10n]'s language: the file service's own
/// exceptions translated, others as they describe themselves.
String localizedFileError(
  AppLocalizations l10n,
  Object error,
) => switch (error) {
  IdeFileConflictException(:final path) => l10n.fileErrorConflict(path),
  IdeFileNotFoundException(:final path) => l10n.fileErrorNotFound(path),
  IdeBinaryFileException(:final path) => l10n.fileErrorBinary(path),
  IdeFileTooLargeException(:final path) => l10n.fileErrorTooLarge(path),
  IdeFileExistsException(:final path) => l10n.fileErrorExists(p.basename(path)),
  IdeFileAccessDeniedException(:final path) => l10n.fileErrorAccessDenied(path),
  _ => '$error',
};

/// [path]'s bytes, for a preview (an image's): read whole, without the
/// editor's binary and size checks. Throws [IdeFileNotFoundException] when
/// there is no such file.
Future<Uint8List> readFileBytes(String path) => platform.readFileBytes(path);

/// How many bytes [path] takes, a file of this machine's.
Future<int> fileByteSize(String path) => platform.fileByteSize(path);

/// How many bytes [path] takes through [files], as [readBytesThrough]
/// reads it; null where that cannot be told.
Future<int>? byteSizeThrough(IdeFileService files, String path) =>
    switch (files) {
      platform.LocalIdeFileService() => fileByteSize(path),
      final IdeRangeFiles files => files.sizeOf([path]),
      _ => null,
    };

/// Copies [from], a file or folder of this machine's (pasted from the
/// system's clipboard), to [to] through [files]: onto a remote project's
/// host, which is Linux or macOS. Links to folders are left out.
Future<void> copyLocalTo(IdeFileService files, String from, String to) =>
    platform.uploadTo(files, [(from: from, to: to)]);

/// How far a copy between this machine and a remote host is: [done] of
/// [total] files.
typedef TransferProgress = void Function(int done, int total);

/// How far the file being downloaded is: [read] of its [size] bytes.
typedef FileProgress = void Function(int read, int size);

/// Copies each of [items] (this machine's files and folders) to its place
/// on a remote project's host through [files], the folders first, then
/// the files one by one, [onProgress] told after each: a file a stretch at
/// a time where [files] writes so ([IdeRangeFiles]), how far told to
/// [onFile]. Once [cancel] completes it stops, with a
/// [TransferCancelledException], the file it was on left out. Links to
/// folders are left out.
Future<void> uploadTo(
  IdeFileService files,
  List<({String from, String to})> items, {
  TransferProgress? onProgress,
  FileProgress? onFile,
  Future<void>? cancel,
}) => platform.uploadTo(
  files,
  items,
  onProgress: onProgress,
  onFile: onFile,
  cancel: cancel,
);

/// Copies each of [items] (files and folders of a remote host, [files]')
/// to its place on this machine, as [uploadTo] the other way: a file a
/// stretch at a time where [files] reads so ([IdeRangeFiles]), how far
/// told to [onFile]. Once [cancel] completes it stops, with a
/// [TransferCancelledException], the file it was on left out.
Future<void> downloadFrom(
  IdeHostFiles files,
  List<({String from, String to, bool directory})> items, {
  TransferProgress? onProgress,
  FileProgress? onFile,
  Future<void>? cancel,
}) => platform.downloadFrom(
  files,
  items,
  onProgress: onProgress,
  onFile: onFile,
  cancel: cancel,
);

/// A new folder of this machine's to download a remote host's files into,
/// for other apps to take (pasted in Finder, dragged out); those of days
/// before are deleted.
Future<String> newDownloadFolder() => platform.newDownloadFolder();

/// Save As… of a file shown: writes it to [to] on this machine, written
/// over (the save panel asked). [text] when given (an editor's, unsaved
/// changes and all), else [from]'s bytes as read through [files]: from a
/// remote project's host, a download, how far told to [onFile] and given
/// up once [cancel] completes (see [downloadFrom]).
Future<void> saveCopyTo(
  IdeFileService files,
  String from,
  String to, {
  String? text,
  FileProgress? onFile,
  Future<void>? cancel,
}) => platform.saveCopyTo(
  files,
  from,
  to,
  text: text,
  onFile: onFile,
  cancel: cancel,
);

/// Changes to the entries of [directory] (not of its subfolders): files
/// written, made, moved or deleted there, by anything. Empty where it
/// cannot be watched.
Stream<void> watchDirectory(String directory) =>
    platform.watchDirectory(directory);

/// The extensions VS Code's image preview opens instead of the text editor
/// (extensions/media-preview's `imagePreview.previewEditor`), less those
/// Flutter cannot decode (`.tif`, `.tga`, `.psd`).
const ideImageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.jpe',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
  '.svg',
};

/// Whether [path] opens in the image preview.
bool ideIsImagePath(String path) =>
    ideImageExtensions.contains(p.extension(path).toLowerCase());

/// [path]'s bytes through [files]: read here for a local project, on the
/// host for a remote one; other services give their text.
Future<Uint8List> readBytesThrough(IdeFileService files, String path) async {
  if (files is platform.LocalIdeFileService) return readFileBytes(path);
  if (files is IdeHostFiles) return files.readBytes(path);
  return utf8.encode(await files.read(path, force: true));
}

/// Every regular file under [root], skipping [ideIndexExcludedDirectories],
/// at most [limit]. Local projects are walked on a background isolate;
/// other services are walked through [IdeFileService.list].
Future<IdeFileListing> listProjectFiles(
  IdeFileService files,
  String root, {
  int limit = 50000,
}) async {
  if (files is platform.LocalIdeFileService) {
    return platform.walkProjectFiles(root, ideIndexExcludedDirectories, limit);
  }
  if (files is IdeHostFiles) return files.listProject(root, limit: limit);
  final paths = <String>[];
  final pending = <String>[root];
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    List<IdeFile> entries;
    try {
      entries = await files.list(directory);
    } catch (_) {
      continue;
    }
    for (final entry in entries) {
      final path = p.join(directory, entry.name);
      if (entry.isDirectory) {
        if (!ideIndexExcludedDirectories.contains(entry.name)) {
          pending.add(path);
        }
      } else {
        paths.add(path);
        if (paths.length >= limit) {
          return IdeFileListing(paths..sort(), truncated: true);
        }
      }
    }
  }
  return IdeFileListing(paths..sort());
}
