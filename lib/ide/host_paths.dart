import 'package:path/path.dart' as p;

/// How [path], a remote host's, is spelled: Windows' for one with a drive
/// (`C:\…`) or of a share (`\\server\…`), POSIX otherwise (Linux, macOS).
p.Context hostPathsFor(String path) =>
    isWindowsPath(path) ? p.windows : p.posix;

/// Whether [path] is a Windows one: with a drive, or of a share.
bool isWindowsPath(String path) => _windowsPath.hasMatch(path);

final _windowsPath = RegExp(r'^[A-Za-z]:([\\/]|$)|^\\\\');
