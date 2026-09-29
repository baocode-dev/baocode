import 'package:path/path.dart' as p;

import 'file_service_stub.dart'
    if (dart.library.io) 'file_service_io.dart'
    as platform;

class IdeFile {
  const IdeFile(this.path, this.name, {required this.isDirectory});

  final String path;
  final String name;
  final bool isDirectory;
}

/// A save refused because the file changed since it was read or last saved.
class IdeFileConflictException implements Exception {
  const IdeFileConflictException(this.path);

  final String path;

  @override
  String toString() =>
      'The file changed on disk. Reopen it before saving: $path';
}

/// A read of a file that does not exist.
class IdeFileNotFoundException implements Exception {
  const IdeFileNotFoundException(this.path);

  final String path;

  @override
  String toString() => 'File not found: $path';
}

/// A read refused because the file looks binary, or is not UTF-8.
class IdeBinaryFileException implements Exception {
  const IdeBinaryFileException(this.path);

  final String path;

  @override
  String toString() => 'Binary files cannot be edited: $path';
}

/// A read refused because the file is over the editor's size limit.
class IdeFileTooLargeException implements Exception {
  const IdeFileTooLargeException(this.path, this.size);

  final String path;

  /// In bytes.
  final int size;

  @override
  String toString() => 'Files over 5 MB cannot be edited: $path';
}

/// The files under one open project. The web cannot access local projects.
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
}

/// Directory names never indexed for Quick Open: VCS metadata, dependency
/// caches and build outputs.
const ideIndexExcludedDirectories = <String>{
  '.git',
  '.hg',
  '.svn',
  '.dart_tool',
  '.idea',
  '.gradle',
  '.next',
  '.nuxt',
  '.cache',
  '.venv',
  '.pub-cache',
  '__pycache__',
  'build',
  'node_modules',
  'bower_components',
  'Pods',
  'DerivedData',
  'venv',
};

/// Files under a project root, as found by [listProjectFiles].
class IdeFileListing {
  IdeFileListing(List<String> paths, {this.truncated = false})
    : paths = List.unmodifiable(paths);

  /// Absolute paths joined onto the root as given (symlinks not resolved).
  final List<String> paths;

  /// Whether the listing stopped at its limit.
  final bool truncated;
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
