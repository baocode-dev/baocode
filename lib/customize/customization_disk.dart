import 'package:path/path.dart' as p;

import 'customization_disk_stub.dart'
    if (dart.library.io) 'customization_disk_io.dart'
    as platform;

/// The files Claude Code's customizations are kept in: this machine's, or
/// those of a remote host, where its agents run.
abstract interface class CustomizationDisk {
  /// This machine's; null where there are no files (the web).
  static CustomizationDisk? get local => platform.localCustomizationDisk();

  /// Whether these are this machine's files (shown in its file manager,
  /// opened in its IDE).
  bool get isLocal;

  /// How paths are spelled there.
  p.Context get paths;

  /// Claude Code's config folder there (`~/.claude` unless moved).
  Future<String> configDir();

  /// The user's home there; null where none is known.
  Future<String?> homeDir();

  /// [path]'s text; null for none, or one that cannot be read.
  Future<String?> read(String path);

  /// The files and folders in [directory], links followed (one leading
  /// nowhere as a folder); none for no such folder.
  Future<List<({String path, bool directory})>> children(String directory);

  /// Whether [path] is a folder (true) or a file (false); null where
  /// nothing is.
  Future<bool?> isDirectory(String path);

  /// Writes [text] to [path], making its folders.
  Future<void> write(String path, String text);

  /// Deletes [path], a folder with its contents.
  Future<void> delete(String path);
}
