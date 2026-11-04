import 'dart:io';

import 'package:path/path.dart' as p;

/// [executable] as `cmd.exe` would find it: a bare name (no folder, no
/// extension) looked up on [environment]'s `PATH` with each of its
/// `PATHEXT`. Windows' own lookup tries `.exe` alone, so the `claude.cmd`
/// and `npm.cmd` Node's installs leave are not found by name. Anything
/// else, or a name found nowhere, as it was given.
String windowsExecutable(
  String executable,
  Map<String, String> environment, {
  bool Function(String path)? isFile,
}) {
  if (executable.contains(RegExp(r'[\\/:]')) ||
      p.windows.extension(executable).isNotEmpty) {
    return executable;
  }
  final exists = isFile ?? (path) => File(path).existsSync();
  final extensions = (_lookUp(environment, 'PATHEXT') ?? '.COM;.EXE;.BAT;.CMD')
      .toLowerCase()
      .split(';')
      .where((extension) => extension.isNotEmpty);
  for (final folder in (_lookUp(environment, 'PATH') ?? '').split(';')) {
    if (folder.trim().isEmpty) continue;
    for (final extension in extensions) {
      final candidate = p.windows.join(folder.trim(), '$executable$extension');
      if (exists(candidate)) return candidate;
    }
  }
  return executable;
}

/// [name] in [environment], whatever its case (Windows' variables are
/// `Path` as often as `PATH`).
String? _lookUp(Map<String, String> environment, String name) {
  if (environment[name] case final value?) return value;
  final upper = name.toUpperCase();
  for (final MapEntry(:key, :value) in environment.entries) {
    if (key.toUpperCase() == upper) return value;
  }
  return null;
}
