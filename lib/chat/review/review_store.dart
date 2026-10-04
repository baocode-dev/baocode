import 'package:bao_remote/review.dart';

import '../../remote/remote_location.dart';
import '../../remote/ssh_host.dart';
import 'review_store_stub.dart'
    if (dart.library.io) 'review_store_io.dart'
    as platform;

export 'package:bao_remote/review.dart';

/// The store for the project at [root]; null where there is none (no Git,
/// no such folder, the web, or under test). A remote project's is its
/// host's: its checkpoints there, in the server's data folder.
Future<ReviewStore?> openReviewStore(String root) async {
  if (RemoteLocation.hostOf(root) case final host?) {
    if (!reviewSupported) return null;
    final client = await SshHosts.instance[host].ready;
    return client.openReview(RemoteLocation.pathOf(root));
  }
  return platform.openReviewStore(root);
}

/// Whether [openReviewStore] may give one: not on the web, nor under test.
bool get reviewSupported => platform.reviewSupported;
