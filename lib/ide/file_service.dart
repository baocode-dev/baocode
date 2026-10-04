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

/// [error] as a message in [l10n]'s language: the file service's own
/// exceptions translated, others as they describe themselves.
String localizedFileError(AppLocalizations l10n, Object error) =>
    switch (error) {
      IdeFileConflictException(:final path) => l10n.fileErrorConflict(path),
      IdeFileNotFoundException(:final path) => l10n.fileErrorNotFound(path),
      IdeBinaryFileException(:final path) => l10n.fileErrorBinary(path),
      IdeFileTooLargeException(:final path) => l10n.fileErrorTooLarge(path),
      IdeFileExistsException(:final path) => l10n.fileErrorExists(
        p.basename(path),
      ),
      _ => '$error',
    };

/// [path]'s bytes, for a preview (an image's): read whole, without the
/// editor's binary and size checks. Throws [IdeFileNotFoundException] when
/// there is no such file.
Future<Uint8List> readFileBytes(String path) => platform.readFileBytes(path);

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
