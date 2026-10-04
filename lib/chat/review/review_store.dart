import 'package:bao_remote/review.dart';

import 'review_store_stub.dart'
    if (dart.library.io) 'review_store_io.dart'
    as platform;

export 'package:bao_remote/review.dart';

/// The store for the project at [root]; null where there is none (no Git,
/// no such folder, the web, or under test).
Future<ReviewStore?> openReviewStore(String root) =>
    platform.openReviewStore(root);

/// Whether [openReviewStore] may give one: not on the web, nor under test.
bool get reviewSupported => platform.reviewSupported;
