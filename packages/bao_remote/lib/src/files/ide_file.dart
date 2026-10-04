import 'package:path/path.dart' as p;

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

/// A file operation's target is taken.
class IdeFileExistsException implements Exception {
  const IdeFileExistsException(this.path);

  final String path;

  @override
  String toString() =>
      'A file or folder ${p.basename(path)} already exists at this location.';
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
