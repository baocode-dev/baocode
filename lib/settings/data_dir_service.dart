import 'dart:io';

import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../platform/app_paths.dart';
import '../platform/data_dir.dart';

/// What a folder the data could move to holds.
enum DataDirectoryContents {
  /// Nothing (the system's own `.DS_Store` and such aside).
  empty,

  /// The app's data ([DataDirectory.markers]): used as it is.
  baocodeData,

  /// Other files: the app's are put beside them.
  other,
}

/// A folder checked for the data to move to ([DataDirectoryService.check]).
class DataDirectoryTarget {
  const DataDirectoryTarget(
    this.path, {
    this.contents,
    this.error,
    this.localize,
  });

  final String path;

  /// What it holds; null when it cannot be used.
  final DataDirectoryContents? contents;

  /// Why it cannot be used; null when it can.
  final String? error;

  /// Gives [error] in a language; English ([error]) when null.
  final String Function(AppLocalizations l10n)? localize;

  bool get ok => error == null;

  /// [error] in [l10n]'s language.
  String? localizedError(AppLocalizations l10n) =>
      error == null ? null : (localize?.call(l10n) ?? error);
}

/// Why [checkDataDirectory] turned down [path] ([error], its English), in
/// [l10n]'s language.
String localizedDataDirectoryProblem(
  AppLocalizations l10n,
  DataDirectoryProblem problem,
  String path, {
  String? error,
}) => switch (problem) {
  DataDirectoryProblem.notWritable => l10n.dataDirNotWritable(path),
  DataDirectoryProblem.missing
      when error?.endsWith(' is not a folder.') ?? false =>
    l10n.dataDirNotFolder(path),
  DataDirectoryProblem.missing => l10n.dataDirNotThere(path),
  DataDirectoryProblem.invalidPointer => error ?? '',
};

/// Whether [error] is a file in use for now, which may not be a moment
/// later. On Windows ([windows]; this platform when null): open in a
/// program that shares it with no one (a language server, git, a virus
/// scanner, the search indexer), a part of it locked, or removed but still
/// open (its folder then not empty yet). Elsewhere: busy.
bool isFileInUse(FileSystemException error, {bool? windows}) {
  final code = error.osError?.errorCode;
  if (code == null) return false;
  return (windows ?? Platform.isWindows)
      // ERROR_ACCESS_DENIED, _SHARING_VIOLATION, _LOCK_VIOLATION,
      // _DIR_NOT_EMPTY, _USER_MAPPED_FILE.
      ? const {5, 32, 33, 145, 1224}.contains(code)
      // EBUSY, ETXTBSY.
      : const {16, 26}.contains(code);
}

/// How long [retryWhileInUse] waits before each try again: some three
/// seconds in all.
const fileInUseDelays = [
  Duration(milliseconds: 50),
  Duration(milliseconds: 100),
  Duration(milliseconds: 200),
  Duration(milliseconds: 400),
  Duration(milliseconds: 800),
  Duration(milliseconds: 1600),
];

/// Runs [action], and again after each of [delays] while it fails on a
/// file [inUse].
Future<T> retryWhileInUse<T>(
  Future<T> Function() action, {
  List<Duration> delays = fileInUseDelays,
  bool Function(FileSystemException error) inUse = isFileInUse,
}) async {
  for (var attempt = 0; ; attempt++) {
    try {
      return await action();
    } on FileSystemException catch (error) {
      if (attempt >= delays.length || !inUse(error)) rethrow;
      await Future<void>.delayed(delays[attempt]);
    }
  }
}

/// Moving the data directory: checking a folder, copying the app's data
/// there (or using what is there), and pointing the next run at it through
/// `~/.baocode/config-dir.json`, written last. The run that made the change
/// keeps its folder until the app restarts; the next one offers to remove
/// what is left in the old one ([previousDirectory], [removeOldData]).
///
/// Only the app's own entries ([DataDirectory.items]) are ever copied or
/// removed: the folder holds other programs' files too (the web views'
/// `Cookies`, `GPUCache`, `Local Storage`…).
class DataDirectoryService {
  DataDirectoryService({
    DataDirectory? current,
    Map<String, String>? environment,
    String? home,
  }) : current = current ?? DataDirectory.current,
       environment = environment ?? Platform.environment,
       home = home ?? _defaultHome(environment);

  /// The user's home; under `flutter test` (and no [environment] given) a
  /// temporary folder instead, as [DataDirectory.current] is, so no test
  /// reads or writes the user's `~/.baocode`.
  static String _defaultHome(Map<String, String>? environment) {
    if (environment == null &&
        Platform.environment.containsKey('FLUTTER_TEST')) {
      return p.join(Directory.systemTemp.path, 'baocode-test-home-$pid');
    }
    return AppPaths.home(environment ?? Platform.environment);
  }

  /// The folder this run uses.
  final DataDirectory current;
  final Map<String, String> environment;
  final String home;

  /// `~/.baocode/config-dir.json`.
  String get pointerFile => DataDirectoryPointer.fileIn(home);

  /// The platform's place for the data.
  String get defaultPath => DataDirectory.defaultPath(environment);

  /// Whether `BAOCODE_DATA_DIR` decides the folder, whatever is chosen here.
  bool get setByEnvironment =>
      environment[DataDirectory.environmentVariable]?.trim().isNotEmpty ??
      false;

  /// Whether this run uses the platform's place.
  bool get usesDefault => _same(current.path, defaultPath);

  /// The pointer as it is now; null when there is none or it is invalid.
  DataDirectoryPointer? get pointer {
    try {
      return DataDirectoryPointer.read(File(pointerFile));
    } on FormatException {
      return null;
    }
  }

  /// The folder the next run is to use, when it is not this one's (the
  /// data was moved, and the app not restarted yet).
  String? get pendingPath {
    if (setByEnvironment) return null;
    final String next;
    try {
      next = switch (DataDirectoryPointer.read(File(pointerFile))?.dataDir) {
        final dataDir? => expandDataDirectory(dataDir, home),
        null => defaultPath,
      };
    } on FormatException {
      return null;
    }
    return _same(next, current.path) ? null : next;
  }

  // --- Choosing a folder ---------------------------------------------------

  /// Whether the data can move to [path], and what is there: it must be
  /// a folder files can be written in, neither the current one nor inside
  /// it, nor one the current one is inside. [create] makes it first (the
  /// platform's default place, which may not be there yet).
  Future<DataDirectoryTarget> check(String path, {bool create = false}) async {
    path = expandDataDirectory(path.trim(), home);
    if (!p.isAbsolute(path)) {
      return DataDirectoryTarget(
        path,
        error: 'Choose a full path.',
        localize: (l10n) => l10n.dataDirFullPath,
      );
    }
    path = p.normalize(path);
    if (_same(path, current.path)) {
      return DataDirectoryTarget(
        path,
        error: 'This is the folder in use.',
        localize: (l10n) => l10n.dataDirInUse,
      );
    }
    if (_within(current.path, path)) {
      return DataDirectoryTarget(
        path,
        error: 'The new folder cannot be inside the one in use.',
        localize: (l10n) => l10n.dataDirInsideCurrent,
      );
    }
    if (_within(path, current.path)) {
      return DataDirectoryTarget(
        path,
        error: 'The new folder cannot contain the one in use.',
        localize: (l10n) => l10n.dataDirContainsCurrent,
      );
    }
    if (create) {
      try {
        await Directory(path).create(recursive: true);
      } on FileSystemException catch (error) {
        return DataDirectoryTarget(
          path,
          error: 'The folder cannot be made: ${error.message}',
          localize: (l10n) => l10n.dataDirCannotMake(error.message),
        );
      }
    }
    final (problem, error) = checkDataDirectory(path);
    if (problem != null) {
      return DataDirectoryTarget(
        path,
        error: error,
        localize: (l10n) =>
            localizedDataDirectoryProblem(l10n, problem, path, error: error),
      );
    }
    return DataDirectoryTarget(path, contents: await contentsOf(path));
  }

  /// What the folder at [path] holds.
  static Future<DataDirectoryContents> contentsOf(String path) async {
    var empty = true;
    await for (final entity in Directory(path).list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (DataDirectory.markers.contains(name)) {
        return DataDirectoryContents.baocodeData;
      }
      if (!_systemFiles.contains(name.toLowerCase())) empty = false;
    }
    return empty ? DataDirectoryContents.empty : DataDirectoryContents.other;
  }

  /// What the system leaves in any folder it shows.
  static const _systemFiles = {'.ds_store', 'thumbs.db', 'desktop.ini'};

  // --- Moving --------------------------------------------------------------

  /// Copies the app's data to [target] (checked by [check]), makes sure it
  /// all arrived, and only then points the next run at it. The process
  /// lists (`state/*-processes.json`), files left aside (`*.tmp`) and the
  /// locks of git at work in the checkpoints stay: they are this run's.
  /// A file in use is waited for a little ([retryWhileInUse]); one removed
  /// since it was listed is not copied. What was copied is taken back when
  /// anything fails. [onProgress] hears how many files of how many are
  /// done.
  Future<void> migrate(
    String target, {
    void Function(int done, int total)? onProgress,
  }) async {
    final source = current.path;
    final entries = [
      for (final item in DataDirectory.items) ...await _entries(source, item),
    ];
    final total = entries.whereType<_FileEntry>().length;
    // What the copy adds, taken back if it fails.
    final created = [
      for (final item in DataDirectory.items)
        if (_exists(p.join(source, item)) && !_exists(p.join(target, item)))
          p.join(target, item),
    ];
    try {
      var done = 0;
      // The length of each file copied.
      final copied = <String, int>{};
      onProgress?.call(done, total);
      for (final entry in entries) {
        final to = p.join(target, entry.relative);
        switch (entry) {
          case _DirectoryEntry():
            await Directory(to).create(recursive: true);
          case _LinkEntry(target: final link):
            await Link(to).create(
              _relinked(link, from: source, to: target),
              recursive: true,
            );
          case _FileEntry(:final path):
            await Directory(p.dirname(to)).create(recursive: true);
            if (await _copy(path, to) case final length?) {
              copied[entry.relative] = length;
            }
            onProgress?.call(++done, total);
        }
      }
      await _verify(entries, target, copied);
      await DataDirectoryPointer(
        dataDir: _same(target, defaultPath) ? null : target,
        previousDataDir: source,
      ).write(File(pointerFile));
    } on Object {
      for (final path in created) {
        await _remove(path);
      }
      rethrow;
    }
  }

  /// Points the next run at [target], which already holds the app's data;
  /// nothing is copied.
  Future<void> useAsIs(String target) => DataDirectoryPointer(
    dataDir: _same(target, defaultPath) ? null : target,
    previousDataDir: current.path,
  ).write(File(pointerFile));

  // --- The old folder ------------------------------------------------------

  /// The folder the data was moved from, while the app's entries are still
  /// there; null when there is none (or it is this run's).
  String? get previousDirectory {
    final previous = pointer?.previousDataDir;
    if (previous == null) return null;
    final path = expandDataDirectory(previous, home);
    if (!p.isAbsolute(path) || _same(path, current.path)) return null;
    return leftoverItems(path).isEmpty ? null : path;
  }

  /// The app's entries in [directory].
  static List<String> leftoverItems(String directory) => [
    for (final item in DataDirectory.items)
      if (_exists(p.join(directory, item))) item,
  ];

  /// Removes the app's entries from [directory], the folder itself and
  /// everything else in it left as they are; then forgets it. Returns the
  /// entries that could not all go, a file in them still in use (on
  /// Windows, open in another program): what could of them is removed,
  /// and the folder is offered again on the next start.
  Future<List<String>> removeOldData(String directory) async {
    if (_same(directory, current.path) || _within(directory, current.path)) {
      throw ArgumentError.value(directory, 'directory', 'is in use');
    }
    final left = [
      for (final item in leftoverItems(directory))
        if (!await _remove(p.join(directory, item))) item,
    ];
    if (left.isEmpty) await forgetPrevious();
    return left;
  }

  /// Stops offering to remove the old folder's data.
  Future<void> forgetPrevious() async {
    final DataDirectoryPointer? kept;
    try {
      kept = DataDirectoryPointer.read(File(pointerFile));
    } on FormatException {
      return; // Never written over unasked.
    }
    if (kept?.previousDataDir == null) return;
    await DataDirectoryPointer(dataDir: kept!.dataDir).write(File(pointerFile));
  }

  // --- Files ---------------------------------------------------------------

  /// Everything under [item] in [root], parents first; a link as a link.
  /// What goes as it is listed is passed over.
  static Future<List<_Entry>> _entries(String root, String item) async {
    final path = p.join(root, item);
    final entries = <_Entry>[];
    Future<void> visit(String path) async {
      final relative = p.relative(path, from: root);
      if (_left(relative)) return;
      try {
        switch (FileSystemEntity.typeSync(path, followLinks: false)) {
          case FileSystemEntityType.link:
            entries.add(_LinkEntry(relative, await Link(path).target()));
          case FileSystemEntityType.directory:
            entries.add(_DirectoryEntry(relative));
            final children =
                await Directory(path)
                      .list(followLinks: false)
                      .map((entity) => entity.path)
                      .toList()
                  ..sort();
            for (final child in children) {
              await visit(child);
            }
          case FileSystemEntityType.file:
            entries.add(_FileEntry(relative, path));
          default:
            break;
        }
      } on FileSystemException {
        if (_exists(path)) rethrow;
      }
    }

    await visit(path);
    return entries;
  }

  /// Whether the entry at [relative] stays behind: this run's process
  /// lists, files left aside (`<name>.<pid>.<n>.tmp`, as
  /// [writeFileAtomically] writes them), and the locks of git at work in
  /// a checkpoint (a copy would keep it locked there for good).
  static bool _left(String relative) {
    final parts = p.split(relative);
    final name = parts.last;
    return switch (parts.first) {
      'state' => name.endsWith('-processes.json') || name.endsWith('.tmp'),
      'checkpoints' => name.endsWith('.lock') || _writtenAside.hasMatch(name),
      _ => _writtenAside.hasMatch(name),
    };
  }

  static final _writtenAside = RegExp(r'\.\d+\.\d+\.tmp$');

  /// How many times [_copy] copies a file that changes as it is copied.
  static const _copyTries = 3;

  /// Copies the file [from] to [to], waiting a little while it is in use,
  /// and again when it changed as it was copied; the length copied, or
  /// null when it is gone (removed since it was listed: a file written
  /// aside, a lock let go).
  static Future<int?> _copy(String from, String to) async {
    for (var tries = 1; ; tries++) {
      try {
        await retryWhileInUse(() => File(from).copy(to));
        final length = await File(to).length();
        if (length == await File(from).length()) return length;
      } on FileSystemException {
        if (_exists(from)) rethrow;
        await _remove(to);
        return null;
      }
      if (tries == _copyTries) {
        throw FileSystemException('Changed while copied', from);
      }
    }
  }

  /// A link's target [link], or where it points into the folder [from]
  /// the same place in the copy, [to].
  static String _relinked(
    String link, {
    required String from,
    required String to,
  }) {
    if (!p.isAbsolute(link) || !p.isWithin(from, link)) return link;
    return p.join(to, p.relative(link, from: from));
  }

  /// Whether every entry is in [target], each file [copied] at its length
  /// (one gone before it was copied passed over).
  static Future<void> _verify(
    List<_Entry> entries,
    String target,
    Map<String, int> copied,
  ) async {
    for (final entry in entries) {
      final path = p.join(target, entry.relative);
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      final ok = switch (entry) {
        _DirectoryEntry() => type == FileSystemEntityType.directory,
        _LinkEntry() => type == FileSystemEntityType.link,
        _FileEntry() => switch (copied[entry.relative]) {
          null => true,
          final length =>
            type == FileSystemEntityType.file &&
                await File(path).length() == length,
        },
      };
      if (!ok) {
        throw FileSystemException('Not copied whole', path);
      }
    }
  }

  static bool _exists(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  /// Removes [path], a folder with all in it, waiting a little while a
  /// file is in use; when one still is, all of it that can go. Whether it
  /// is gone.
  static Future<bool> _remove(String path) async {
    try {
      await retryWhileInUse(() => _delete(path, recursive: true));
    } on FileSystemException {
      await _removeWhatCan(path);
    }
    return !_exists(path);
  }

  /// Removes what can go of [path] at once: in a folder, all but what is
  /// in use.
  static Future<void> _removeWhatCan(String path) async {
    try {
      return await _delete(path, recursive: true);
    } on FileSystemException {
      if (FileSystemEntity.typeSync(path, followLinks: false) !=
          FileSystemEntityType.directory) {
        return;
      }
    }
    try {
      final children = await Directory(path)
          .list(followLinks: false)
          .map((entity) => entity.path)
          .toList();
      for (final child in children) {
        await _removeWhatCan(child);
      }
      await Directory(path).delete();
    } on FileSystemException {
      // Still in use: left.
    }
  }

  static Future<void> _delete(String path, {bool recursive = false}) async {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.link:
        await Link(path).delete();
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: recursive);
      case FileSystemEntityType.notFound:
        break;
      default:
        await File(path).delete();
    }
  }

  /// [path] as the file system names it: links resolved where it exists.
  static String _canonical(String path) {
    var resolved = p.normalize(p.absolute(path));
    try {
      if (FileSystemEntity.typeSync(resolved) !=
          FileSystemEntityType.notFound) {
        resolved = Directory(resolved).resolveSymbolicLinksSync();
      }
    } on FileSystemException {
      // As it is.
    }
    return p.canonicalize(resolved);
  }

  static bool _same(String a, String b) =>
      p.equals(_canonical(a), _canonical(b));

  /// Whether [child] is inside [parent].
  static bool _within(String parent, String child) =>
      p.isWithin(_canonical(parent), _canonical(child));
}

sealed class _Entry {
  const _Entry(this.relative);

  /// Its path in the data folder.
  final String relative;
}

class _DirectoryEntry extends _Entry {
  const _DirectoryEntry(super.relative);
}

class _LinkEntry extends _Entry {
  const _LinkEntry(super.relative, this.target);

  final String target;
}

class _FileEntry extends _Entry {
  const _FileEntry(super.relative, this.path);

  final String path;
}
