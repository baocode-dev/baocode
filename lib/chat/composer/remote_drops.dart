import 'package:path/path.dart' as p;

import '../../ide/file_service.dart';
import '../../ide/host_paths.dart';
import '../../remote/remote_services.dart';
import 'composer_files.dart';

/// Files of this machine's put in a remote project's composer (let go on
/// it from another app, pasted, picked): its agent, on the host, cannot
/// read them here, so they are copied there first, each put in a folder of
/// its own under [folder], and their tags are of the copies.
abstract final class RemoteDrops {
  /// Where on a Linux or macOS host they go.
  static const folder = '/tmp/baocode-drops';

  /// Where on [host]'s they go: [folder], or on a Windows host the user's
  /// temporary folder's.
  static String folderOf(IdeFileService host) {
    if (host case RemoteIdeFileService(host: final ssh)
        when ssh.hello?.platform.os == 'win') {
      final home = ssh.hello!.home;
      return p.windows.join(home, 'AppData', 'Local', 'Temp', 'baocode-drops');
    }
    return folder;
  }

  /// [folder], and as macOS resolves it: the agent may read what is in
  /// them without asking (see [ClaudeLaunch.readable]).
  static const folders = [folder, '/private$folder'];

  /// Copies [files] onto the host through [host], [onProgress] told how
  /// far; what the agent is to read of them there, in their order.
  static Future<List<ComposerFile>> copy(
    IdeFileService host,
    List<ComposerFile> files, {
    DateTime? now,
    TransferProgress? onProgress,
  }) async {
    final folder = folderOf(host);
    final paths = hostPathsFor(folder);
    final into = paths.join(
      folder,
      (now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36),
    );
    final taken = <String>{};
    final items = <({String from, String to})>[];
    final copies = <ComposerFile>[];
    for (final file in files) {
      // The same name from two folders: the second numbered.
      var name = p.basename(file.path);
      for (var n = 2; !taken.add(name); n++) {
        name =
            '${p.basenameWithoutExtension(file.path)} $n'
            '${p.extension(file.path)}';
      }
      final to = paths.join(into, name);
      items.add((from: file.path, to: to));
      copies.add(ComposerFile(to, directory: file.directory));
    }
    for (final directory in [folder, into]) {
      try {
        await host.create(directory, directory: true);
      } on IdeFileExistsException {
        // Made for files put in before.
      }
    }
    await uploadTo(host, items, onProgress: onProgress);
    return copies;
  }
}
