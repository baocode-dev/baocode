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

/// The files under one open project. The web cannot access local projects.
abstract interface class IdeFileService {
  factory IdeFileService(String root) = platform.LocalIdeFileService;

  Future<List<IdeFile>> list(String directory);
  Future<String> read(String path);

  /// Save a previously read file, rejecting changes to its on-disk baseline.
  /// [expectedText] also protects against another editor using this service.
  Future<void> write(String path, String text, {String? expectedText});
}
