/// [path] with a Windows drive as Git Bash, MSYS2 and Cygwin write it
/// (`/c/Users/a`, `/cygdrive/c/Users/a`), or as a URL's path has it
/// (`/C:/Users/a`), spelled as Windows does: `C:/Users/a`. Any other path
/// as it is. On Windows, `/c/Users/a` would otherwise be `\c\Users\a` on
/// the current drive.
String windowsDrivePath(String path) {
  final match = _posixDrive.firstMatch(path);
  if (match == null) return path;
  final rest = path.substring(match.end);
  return '${match[1]!.toUpperCase()}:${rest.isEmpty ? '/' : rest}';
}

final _posixDrive = RegExp(r'^(?:/cygdrive)?/([A-Za-z]):?(?=[/\\]|$)');
