import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

/// Where [DataDirectory.current] was found.
enum DataDirectorySource {
  /// The `BAOCODE_DATA_DIR` environment variable.
  environment,

  /// `~/.baocode/config-dir.json` ([DataDirectoryPointer]).
  pointer,

  /// The platform's place for app data ([DataDirectory.defaultPath]).
  defaultLocation,

  /// The platform's place for this run only: the one configured could not
  /// be used, and the user chose to go on without it.
  temporaryDefault,
}

/// The folder the app keeps the user's settings and its own state in, laid
/// out as VS Code's user data folder is:
///
/// ```text
/// <path>/User/{settings.json,keybindings.json,lsp.json}
/// <path>/argv.json                  the display language
/// <path>/keymaps/
/// <path>/state/{state.json,storage.json,*-processes.json}
/// <path>/servers/  <path>/language-packs/
/// <path>/checkpoints/             snapshots of the projects agents change
/// <path>/cache/                   what can be made again, to start faster
/// ```
///
/// Other programs keep files there too (the web views' `Cookies`,
/// `GPUCache`, `Local Storage`…): only [items] are the app's.
class DataDirectory {
  const DataDirectory(
    this.path, {
    this.source = DataDirectorySource.defaultLocation,
  });

  /// The one this run uses, resolved once as the app starts (main.dart,
  /// [resolveDataDirectory]). Until then the platform's default; under
  /// `flutter test` a temporary folder instead, so no test touches the
  /// user's data.
  static DataDirectory get current => _current ??= DataDirectory(
    Platform.environment.containsKey('FLUTTER_TEST')
        ? p.join(Directory.systemTemp.path, 'baocode-test-data-$pid')
        : defaultPath(Platform.environment),
  );
  static set current(DataDirectory value) => _current = value;
  static DataDirectory? _current;

  final String path;
  final DataDirectorySource source;

  /// What the user edits: settings, keybindings, language servers.
  String get userDir => p.join(path, 'User');
  String get settingsFile => p.join(userDir, 'settings.json');
  String get keybindingsFile => p.join(userDir, 'keybindings.json');
  String get lspSettingsFile => p.join(userDir, 'lsp.json');

  /// The display language (`locale`), as VS Code's `argv.json`.
  String get argvFile => p.join(path, 'argv.json');
  String get keymapsDir => p.join(path, 'keymaps');

  /// What the app keeps for itself.
  String get stateDir => p.join(path, 'state');

  /// The Workspace's preferences ([PreferenceStore]).
  String get stateFile => p.join(stateDir, 'state.json');

  /// Small app-wide values (`GlobalStorage`).
  String get storageFile => p.join(stateDir, 'storage.json');

  /// Where the child processes of one kind are listed
  /// (`ChildProcessRegistry`): `claude`, `lsp`, `pty`.
  String processRegistryFile(String name) =>
      p.join(stateDir, '$name-processes.json');
  String get serversDir => p.join(path, 'servers');
  String get languagePacksDir => p.join(path, 'language-packs');

  /// A Git repository per project, of snapshots of its files, which the
  /// agents' changes are kept or undone against (see change_review.dart).
  String get checkpointsDir => p.join(path, 'checkpoints');

  /// What is kept only to be quicker, made again if lost (e.g. the
  /// summaries of Claude Code's sessions).
  String get cacheDir => p.join(path, 'cache');

  /// The app's own entries, all others' left alone: what moving the folder
  /// copies and removing old data deletes.
  static const items = [
    'User',
    'argv.json',
    'keymaps',
    'state',
    'servers',
    'language-packs',
    'checkpoints',
    'cache',
  ];

  /// Entries that show a folder holds the app's data.
  static const markers = ['User', 'state', 'argv.json'];

  /// The platform's place for it: `%APPDATA%\baocode` on Windows,
  /// `~/Library/Application Support/baocode` on macOS, `~/.config/baocode`
  /// elsewhere.
  static String defaultPath(Map<String, String> environment) =>
      AppPaths.dataDir(environment);

  /// The environment variable that overrides everything else.
  static const environmentVariable = 'BAOCODE_DATA_DIR';

  @override
  bool operator ==(Object other) =>
      other is DataDirectory && other.path == path && other.source == source;

  @override
  int get hashCode => Object.hash(path, source);

  @override
  String toString() => 'DataDirectory($path, ${source.name})';
}

/// `~/.baocode/config-dir.json`: the folder the user moved the data to
/// (`dataDir`; the default when absent), and the one it was moved from
/// (`previousDataDir`) until the app has asked what to do with what is
/// left there.
class DataDirectoryPointer {
  const DataDirectoryPointer({this.dataDir, this.previousDataDir});

  /// As written: absolute, or starting with `~`.
  final String? dataDir;
  final String? previousDataDir;

  /// Where it is, under [home].
  static String fileIn(String home) =>
      p.join(home, '.baocode', 'config-dir.json');

  /// What [file] says; null when there is no such file. Throws a
  /// [FormatException] when it is not a pointer (or cannot be read).
  static DataDirectoryPointer? read(File file) {
    final String text;
    try {
      if (!file.existsSync()) return null;
      text = file.readAsStringSync();
    } on FileSystemException catch (error) {
      throw FormatException('Cannot read ${file.path}: ${error.message}');
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('${file.path} is not JSON: ${error.message}');
    }
    if (json is! Map) {
      throw FormatException('${file.path} does not hold an object');
    }
    final entries = json;
    String? path(String key) => switch (entries[key]) {
      null => null,
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => throw FormatException('${file.path}: "$key" is not a path'),
    };
    return DataDirectoryPointer(
      dataDir: path('dataDir'),
      previousDataDir: path('previousDataDir'),
    );
  }

  /// Writes it to [file] whole or not at all (aside, then renamed over);
  /// with neither entry, [file] goes.
  Future<void> write(File file) async {
    if (dataDir == null && previousDataDir == null) {
      if (await file.exists()) await file.delete();
      return;
    }
    await file.parent.create(recursive: true);
    await writeFileAtomically(
      file,
      '${const JsonEncoder.withIndent('  ').convert({'dataDir': ?dataDir, 'previousDataDir': ?previousDataDir})}\n',
    );
  }
}

/// Writes [text] to [file] aside, then renames it over: a reader never
/// sees half a file, and nothing is left aside when that fails. Where the
/// rename cannot replace the file (Windows, while another program has it
/// open) it is written in place.
Future<void> writeFileAtomically(File file, String text) async {
  final aside = File('${file.path}.$pid.${_asides++}.tmp');
  try {
    await aside.writeAsString(text, flush: true);
    try {
      await aside.rename(file.path);
    } on FileSystemException {
      await file.writeAsString(text, flush: true);
    }
  } finally {
    try {
      if (await aside.exists()) await aside.delete();
    } on FileSystemException {
      // Gone already, or a later sweep finds it.
    }
  }
}

int _asides = 0;

/// Why the data directory configured cannot be used.
enum DataDirectoryProblem {
  /// `~/.baocode/config-dir.json` cannot be read, or is not a pointer.
  invalidPointer,

  /// The folder is not there (e.g. on a drive that is gone).
  missing,

  /// The folder is there, but files cannot be made in it.
  notWritable,
}

/// Where the data directory is, and whether it can be used.
class DataDirectoryResolution {
  const DataDirectoryResolution({
    required this.path,
    required this.source,
    required this.defaultPath,
    required this.pointerFile,
    this.problem,
    this.error,
  });

  /// The folder found; with an invalid pointer, [defaultPath].
  final String path;
  final DataDirectorySource source;

  /// The platform's place for it.
  final String defaultPath;

  /// `~/.baocode/config-dir.json`.
  final String pointerFile;

  /// Why [path] cannot be used; null when it can.
  final DataDirectoryProblem? problem;

  /// [problem] for the user.
  final String? error;

  bool get ok => problem == null;

  DataDirectory get directory => DataDirectory(path, source: source);
}

/// Where the data directory is: `BAOCODE_DATA_DIR`, else the folder
/// `~/.baocode/config-dir.json` names (`{"dataDir": "..."}`), else the
/// platform's default. One set by either must exist and take files; one
/// that does not is reported, never replaced by the default unasked (a
/// drive may just be gone for now). [environment] is the process's and
/// [home] the user's home folder by default.
DataDirectoryResolution resolveDataDirectory({
  Map<String, String>? environment,
  String? home,
}) {
  environment ??= Platform.environment;
  home ??= AppPaths.home(environment);
  final defaultPath = DataDirectory.defaultPath(environment);
  final pointerFile = DataDirectoryPointer.fileIn(home);

  DataDirectoryResolution resolved(
    String path,
    DataDirectorySource source, {
    DataDirectoryProblem? problem,
    String? error,
  }) => DataDirectoryResolution(
    path: path,
    source: source,
    defaultPath: defaultPath,
    pointerFile: pointerFile,
    problem: problem,
    error: error,
  );

  DataDirectoryResolution checked(String path, DataDirectorySource source) {
    final (problem, error) = checkDataDirectory(path);
    return resolved(path, source, problem: problem, error: error);
  }

  final variable = environment[DataDirectory.environmentVariable]?.trim();
  if (variable != null && variable.isNotEmpty) {
    final path = expandDataDirectory(variable, home);
    return checked(
      p.isAbsolute(path) ? p.normalize(path) : p.absolute(path),
      DataDirectorySource.environment,
    );
  }
  final DataDirectoryPointer? pointer;
  try {
    pointer = DataDirectoryPointer.read(File(pointerFile));
  } on FormatException catch (error) {
    return resolved(
      defaultPath,
      DataDirectorySource.pointer,
      problem: DataDirectoryProblem.invalidPointer,
      error: error.message,
    );
  }
  if (pointer?.dataDir case final dataDir?) {
    final path = expandDataDirectory(dataDir, home);
    if (!p.isAbsolute(path)) {
      return resolved(
        defaultPath,
        DataDirectorySource.pointer,
        problem: DataDirectoryProblem.invalidPointer,
        error:
            '$pointerFile: "dataDir" must be an absolute path or start '
            'with ~ ($dataDir)',
      );
    }
    return checked(p.normalize(path), DataDirectorySource.pointer);
  }
  return resolved(defaultPath, DataDirectorySource.defaultLocation);
}

/// [path] with a leading `~` spelled out as [home].
String expandDataDirectory(String path, String home) {
  if (path == '~') return home;
  if (path.startsWith('~/') || path.startsWith(r'~\')) {
    return p.join(home, path.substring(2));
  }
  return path;
}

/// Why the folder at [path] cannot hold the data: missing (or not a
/// folder), or no file can be made in it; `(null, null)` when it can.
(DataDirectoryProblem?, String?) checkDataDirectory(String path) {
  final type = FileSystemEntity.typeSync(path);
  if (type == FileSystemEntityType.notFound) {
    return (DataDirectoryProblem.missing, 'The folder $path is not there.');
  }
  if (type != FileSystemEntityType.directory) {
    return (DataDirectoryProblem.missing, '$path is not a folder.');
  }
  if (!canWriteIn(path)) {
    return (
      DataDirectoryProblem.notWritable,
      'Files cannot be written in $path.',
    );
  }
  return (null, null);
}

/// Whether a file can be made (and removed) in the folder at [path].
bool canWriteIn(String path) {
  final probe = File(p.join(path, '.baocode-write-probe-$pid'));
  try {
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } on FileSystemException {
    return false;
  }
}
