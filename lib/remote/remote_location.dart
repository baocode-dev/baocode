import 'package:path/path.dart' as p;

/// Where a project is: a folder of this machine (its path), or of a host
/// reached over SSH, `ssh://<host>/<absolute path>` (the host as the user
/// gave it: an alias of `~/.ssh/config`, or `user@host`, with a port after
/// a colon). The location names the project in the app (the sidebar, what
/// is kept between runs); the services of its host take the path.
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
    return p.posix.normalize(rest.substring(slash));
  }

  /// The location of [path] on [host]; [path] itself for none.
  static String of(String? host, String path) =>
      host == null ? path : '$scheme$host${p.posix.normalize(path)}';

  /// How paths are spelled where [location] is: POSIX on a remote host
  /// (Linux or macOS), this machine's own otherwise.
  static p.Context pathsOf(String location) =>
      isRemote(location) ? p.posix : p.context;

  /// What the sidebar and titles show of [location]: its folder's name.
  static String nameOf(String location) {
    final name = pathsOf(location).basename(pathOf(location));
    return name.isEmpty ? location : name;
  }
}
