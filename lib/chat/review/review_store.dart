import 'dart:typed_data';

import 'review_store_stub.dart'
    if (dart.library.io) 'review_store_io.dart'
    as platform;

/// A file's content as Git keeps it: its mode (`100644`, `100755`,
/// `120000` for a symbolic link) and its blob.
class ReviewBlob {
  const ReviewBlob(this.mode, this.oid);

  final String mode;
  final String oid;

  bool get isLink => mode == '120000';

  /// The same text (or link): an executable bit alone does not count.
  bool sameContent(ReviewBlob? other) =>
      other != null && other.oid == oid && other.isLink == isLink;

  List<String> toJson() => [mode, oid];

  static ReviewBlob? fromJson(Object? json) => switch (json) {
    [final String mode, final String oid] => ReviewBlob(mode, oid),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is ReviewBlob && other.mode == mode && other.oid == oid;

  @override
  int get hashCode => Object.hash(mode, oid);

  @override
  String toString() => 'ReviewBlob($mode $oid)';
}

/// A path that differs between two snapshots: what it was and what it is
/// (null where it is not there).
class ReviewTreeChange {
  const ReviewTreeChange(this.path, this.before, this.after);

  /// Relative to the project, with `/`.
  final String path;
  final ReviewBlob? before;
  final ReviewBlob? after;
}

/// Why a project's changes cannot be reviewed.
class ReviewUnavailable implements Exception {
  const ReviewUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Snapshots of a project's files, kept in a Git repository of the app's
/// own (in the data folder's `checkpoints/`, not the project's `.git`), and
/// the file operations a review needs. Paths are relative to [root], with
/// `/`.
abstract interface class ReviewStore {
  /// The store for the project at [root]; null where there is none (no
  /// Git, no such folder, the web, or under test).
  static Future<ReviewStore?> open(String root) =>
      platform.openReviewStore(root);

  /// Whether [open] may give one: not on the web, nor under test.
  static bool get supported => platform.reviewSupported;

  /// The project's directory.
  String get root;

  /// A snapshot of the project's files (only [paths], the rest as in the
  /// last one), as a tree. Ignored files and files too large are left out.
  Future<String> snapshot({Iterable<String>? paths});

  /// The paths that differ from tree [from] to tree [to].
  Future<List<ReviewTreeChange>> diff(String from, String to);

  /// Lines added and removed per path from tree [from] to [to]; null for
  /// a binary file.
  Future<Map<String, ({int added, int removed})?>> lineCounts(
    String from,
    String to,
  );

  /// Tree [tree] with [entries] in place of its own (null takes the path
  /// out).
  Future<String> overlay(String tree, Map<String, ReviewBlob?> entries);

  /// Whether tree [tree] has [path].
  Future<bool> contains(String tree, String path);

  /// Whether anything is at [path].
  Future<bool> exists(String path);

  /// What is at [path] now; null when nothing (or a folder) is.
  Future<ReviewBlob?> current(String path);

  Future<Uint8List> read(ReviewBlob blob);

  /// Puts [blob] at [path]; null deletes the file (and the folders it
  /// leaves empty).
  Future<void> restore(String path, ReviewBlob? blob);

  /// The file at [path] with the change from [from] to [to] carried over
  /// to it, merged as Git merges; null where they conflict or cannot be
  /// merged (a binary file).
  Future<Uint8List?> merge(String path, ReviewBlob from, ReviewBlob to);

  Future<void> write(String path, Uint8List bytes);

  /// What [save] kept for [session]; null when nothing.
  Future<String?> load(String session);

  /// Keeps [data] for [session], and with it [trees] and [blobs] (which
  /// would otherwise be collected).
  Future<void> save(
    String session,
    String data, {
    required Iterable<String> trees,
    required Iterable<ReviewBlob> blobs,
  });

  Future<void> forget(String session);
}
