import 'package:bao_remote/review.dart';

import '../../remote/remote_location.dart';
import '../../remote/ssh_host.dart';
import 'review_store_stub.dart'
    if (dart.library.io) 'review_store_io.dart'
    as platform;

export 'package:bao_remote/review.dart';

/// The store for the files of the project at [root]: its machine's; null
/// where there is none (the web, or under test). A remote project's is
/// its host's: its checkpoints there, in the server's data folder.
Future<ReviewStore?> openReviewStore(String root) async {
  if (RemoteLocation.hostOf(root) case final host?) {
    if (!reviewSupported) return null;
    final client = await SshHosts.instance[host].ready;
    return client.openReview();
  }
  return platform.openReviewStore();
}

/// [root] with its links resolved, where that is another path; null where
/// it is not (or is a remote project's).
Future<String?> realRootOf(String root) async =>
    RemoteLocation.isRemote(root) ? null : platform.realPathOf(root);

/// Whether [openReviewStore] may give one: not on the web, nor under test.
bool get reviewSupported => platform.reviewSupported;

/// The bytes this machine's checkpoints take up (the remote projects' are
/// their hosts').
Future<int> checkpointsSize() => platform.checkpointsSize();

/// Deletes this machine's checkpoints, but for those of the conversations
/// open: the changes the others left can no longer be undone.
Future<void> clearCheckpoints() => platform.clearCheckpoints();
