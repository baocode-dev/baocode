import 'package:bao_remote/client.dart' show SshTarget;
import 'package:path/path.dart' as p;

import '../ide/host_paths.dart';

/// Where a project is: a folder of this machine (its path), or of a host
/// reached over SSH, `ssh://<host>/<absolute path>` (the host as the user
/// gave it: an alias of `~/.ssh/config`, or `user@host`, with a port after
/// a colon). The location names the project in the app (the sidebar, what
/// is kept between runs); the services of its host take the path. A WSL
/// distribution is a host too, `wsl+<distribution>` (see [SshTarget]).
///
/// A Windows host's paths are its own (`C:\Users\me\app`), spelled with
/// slashes in a location (`ssh://<host>/C:/Users/me/app`): a path tells
/// by its drive which host's it is ([pathsFor]).
abstract final class RemoteLocation {
  static const scheme = 'ssh://';

  /// Whether [location] is on another machine.
  static bool isRemote(String location) => location.startsWith(scheme);

  /// [location]'s host; null for this machine.
  static String? hostOf(String location) {
    if (!isRemote(location)) return null;
    final rest = location.substring(scheme.length);
    final slash = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(0, slash);
  }

  /// [location]'s path on its host: itself for a local one.
  static String pathOf(String location) {
    if (!isRemote(location)) return location;
    final rest = location.substring(scheme.length);
    final slash = rest.indexOf('/');
    if (slash < 0) return '/';
    final path = rest.substring(slash);
    if (_windowsInLocation.hasMatch(path)) {
      final drive = path.substring(1);
      return p.windows.normalize(drive.length == 2 ? '$drive\\' : drive);
    }
    return p.posix.normalize(path);
  }

  /// The location of [path] on [host]; [path] itself for none.
  static String of(String? host, String path) => host == null
      ? path
      : isWindowsPath(path)
      ? '$scheme$host/${p.windows.normalize(path).replaceAll('\\', '/')}'
      : '$scheme$host${p.posix.normalize(path)}';

  /// How paths are spelled where [location] is: a remote host's own
  /// (POSIX on Linux and macOS, Windows' on Windows), this machine's own
  /// otherwise.
  static p.Context pathsOf(String location) =>
      isRemote(location) ? pathsFor(pathOf(location)) : p.context;

  /// How [path], a remote host's, is spelled (see [hostPathsFor]).
  static p.Context pathsFor(String path) => hostPathsFor(path);
  static final _windowsInLocation = RegExp(r'^/[A-Za-z]:(/|$)');

  /// What the sidebar and titles show of [location]: its folder's name.
  static String nameOf(String location) {
    final name = pathsOf(location).basename(pathOf(location));
    return name.isEmpty ? location : name;
  }

  /// Whether [host] is a WSL distribution of this machine.
  static bool isWsl(String host) => host.startsWith(SshTarget.wslPrefix);

  /// How [host] is reached, as titles and the status bar say it: `WSL` or
  /// `SSH`.
  static String reachedBy(String host) => isWsl(host) ? 'WSL' : 'SSH';

  /// What [host] is called when the user has not named it: a WSL
  /// distribution by its name, any other as given.
  static String hostName(String host) =>
      isWsl(host) ? host.substring(SshTarget.wslPrefix.length) : host;
}
