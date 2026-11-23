import 'package:path/path.dart' as p;

/// [path] as [paths] (this machine's when null) has it: on Windows, a drive
/// as Git Bash writes it (`/c/a.dart`, `/cygdrive/c/a.dart`) or as a URL's
/// path has it (`/C:/a.dart`, a code citation's) is `C:/a.dart`, not
/// `\c\a.dart` on whatever drive is the current one. An agent in Git Bash
/// names files so (issue #1145).
String nativePath(String path, [p.Context? paths]) {
  if ((paths ?? p.context).style != p.Style.windows) return path;
  final match = _posixDrive.firstMatch(path);
  if (match == null) return path;
  final rest = path.substring(match.end);
  return '${match[1]!.toUpperCase()}:${rest.isEmpty ? '/' : rest}';
}

final _posixDrive = RegExp(r'^(?:/cygdrive)?/([A-Za-z]):?(?=[/\\]|$)');
