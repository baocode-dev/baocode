import 'dart:io';

import 'package:bao_remote/local.dart';
import 'package:path/path.dart' as p;

import '../../platform/data_dir.dart';

export 'package:bao_remote/local.dart' show GitReviewError, GitReviewStore;

/// Not under `flutter test`, where no test should run Git on its own.
bool get reviewSupported => !Platform.environment.containsKey('FLUTTER_TEST');

/// The project's store in the data folder's `checkpoints/`.
Future<ReviewStore?> openReviewStore(String root) async {
  if (!reviewSupported) return null;
  return GitReviewStore.open(
    root,
    checkpoints: DataDirectory.current.checkpointsDir,
  );
}

/// The bytes this machine's checkpoints take up (none under test).
Future<int> checkpointsSize() async {
  if (!reviewSupported) return 0;
  return GitReviewStore.sizeOf(DataDirectory.current.checkpointsDir);
}

/// Deletes this machine's checkpoints but for the open conversations'.
Future<void> clearCheckpoints() async {
  if (!reviewSupported) return;
  await GitReviewStore.clear(DataDirectory.current.checkpointsDir);
}

/// [path] with its links resolved, where that is another path (macOS's
/// `/tmp`, a folder opened through a link); null where it is not.
Future<String?> realPathOf(String path) async {
  try {
    final real = await Directory(path).resolveSymbolicLinks();
    return p.equals(real, path) ? null : real;
  } on FileSystemException {
    return null;
  }
}
