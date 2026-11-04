import 'package:path/path.dart' as p;

/// How [path], a remote host's, is spelled: Windows' for one with a drive
/// (`C:\…`) or of a share (`\\server\…`), POSIX otherwise (Linux, macOS).
p.Context hostPathsFor(String path) =>
    isWindowsPath(path) ? p.windows : p.posix;

/// Whether [path] is a Windows one: with a drive, or of a share.
bool isWindowsPath(String path) => _windowsPath.hasMatch(path);

final _windowsPath = RegExp(r'^[A-Za-z]:([\\/]|$)|^\\\\');

/// The context for [path], one of this machine's or a remote host's: a
/// Windows host's (from a Mac or Linux) is told by its drive; anything
/// else is this machine's as before. The IDE's views name the open files
/// with these, whichever host they are on.
p.Context hostContext(String path) =>
    isWindowsPath(path) ? p.windows : p.context;

String hostBasename(String path) => hostContext(path).basename(path);

String hostDirname(String path) => hostContext(path).dirname(path);

List<String> hostSplit(String path) => hostContext(path).split(path);

bool hostIsWithin(String parent, String child) =>
    hostContext(parent).isWithin(parent, child);

bool hostEquals(String a, String b) => hostContext(a).equals(a, b);

String hostRelative(String path, {required String from}) =>
    hostContext(from).relative(path, from: from);

/// [path] with its Windows drive in capitals (`c:\…` as `C:\…`), as the
/// app spells paths; language servers' URIs may have it in small letters
/// (`file:///c%3A/…`, typescript-language-server's).
String capitalDrive(String path) => _smallDrive.hasMatch(path)
    ? path[0].toUpperCase() + path.substring(1)
    : path;

final _smallDrive = RegExp(r'^[a-z]:([\\/]|$)');
