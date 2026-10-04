import 'dart:io';

import 'package:bao_remote/client.dart';
import 'package:path/path.dart' as p;

/// The server builds in [directory] (tool/build_remote_server.dart writes
/// them): `baocode-server-linux-<arch>`, and `VERSION`, which names them.
class DirectoryServerBinaries implements RemoteServerBinaries {
  DirectoryServerBinaries(this.directory, this.version);

  /// Those in [directory], if it has a `VERSION`.
  static DirectoryServerBinaries? at(String directory) {
    final file = File(p.join(directory, 'VERSION'));
    if (!file.existsSync()) return null;
    final version = file.readAsStringSync().trim();
    if (version.isEmpty || version.contains(RegExp(r'[^A-Za-z0-9._+-]'))) {
      return null;
    }
    return DirectoryServerBinaries(directory, version);
  }

  final String directory;

  @override
  final String version;

  static String fileName(String arch) => 'baocode-server-linux-$arch';

  @override
  Future<List<int>?> read(String arch) async {
    final file = File(p.join(directory, fileName(arch)));
    return file.existsSync() ? file.readAsBytes() : null;
  }
}

/// The server builds the app carries: in the bundle's resources on macOS
/// (`Contents/Resources/remote`), beside the executable elsewhere
/// (`remote/`); `BAOCODE_REMOTE_SERVER_DIR`, else `build/remote` of the
/// checkout (the working folder's, or one the executable is built under),
/// in development. Null when there are none.
RemoteServerBinaries? bundledServerBinaries({
  Map<String, String>? environment,
  String? executable,
  String? current,
}) {
  environment ??= Platform.environment;
  executable ??= Platform.resolvedExecutable;
  current ??= Directory.current.path;
  final exeDir = p.dirname(executable);
  for (final directory in [
    ?environment['BAOCODE_REMOTE_SERVER_DIR'],
    if (Platform.isMacOS) p.join(p.dirname(exeDir), 'Resources', 'remote'),
    p.join(exeDir, 'remote'),
    p.join(exeDir, 'data', 'remote'),
    p.join(current, 'build', 'remote'),
    // A debug build's executable is under the checkout's build/.
    for (var dir = exeDir, i = 0; i < 10; dir = p.dirname(dir), i++)
      if (p.basename(dir) == 'build') p.join(dir, 'remote'),
  ]) {
    if (DirectoryServerBinaries.at(directory) case final found?) return found;
  }
  return null;
}
