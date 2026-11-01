import 'dart:typed_data';

/// What a file held, kept: its mode (`100644`, `100755`, `120000` for a
/// symbolic link) and its content's id (its SHA-256, in hex).
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

/// Why a change cannot be reviewed.
class ReviewUnavailable implements Exception {
  const ReviewUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What files were before agents changed them, and what they left, kept
/// on the machine the files are on (in the data folder's `checkpoints/`),
/// with each conversation's account of them; and the file operations a
/// review needs. Paths are absolute.
abstract interface class ReviewStore {
  /// What is at [path] now, kept; null when nothing (or a folder) is.
  Future<ReviewBlob?> take(String path);

  /// What is at [path] now, not kept: to tell whether it changed.
  Future<ReviewBlob?> current(String path);

  Future<Uint8List> read(ReviewBlob blob);

  /// Keeps [bytes] as a blob of [mode] (one no file had, such as what was
  /// there before with part of a change kept).
  Future<ReviewBlob> store(Uint8List bytes, {required String mode});

  /// Puts [blob] at [path]; null deletes the file, and the folders it
  /// leaves empty up to [root] (where it is in it).
  Future<void> restore(String path, ReviewBlob? blob, {String? root});

  Future<void> write(String path, Uint8List bytes);

  /// [mine] with the change from [from] to [to] carried over to it; null
  /// where they conflict or cannot be merged (a binary file).
  Future<Uint8List?> merge(ReviewBlob mine, ReviewBlob from, ReviewBlob to);

  /// Lines added and removed from [from] to [to] (null: no file); null
  /// for a binary file.
  Future<({int added, int removed})?> lineCounts(
    ReviewBlob? from,
    ReviewBlob? to,
  );

  /// What [save] kept for [session]; null when nothing.
  Future<String?> load(String session);

  /// Keeps [data] for [session], and with it [blobs] (which would
  /// otherwise be collected).
  Future<void> save(
    String session,
    String data, {
    required Iterable<ReviewBlob> blobs,
  });

  Future<void> forget(String session);
}
