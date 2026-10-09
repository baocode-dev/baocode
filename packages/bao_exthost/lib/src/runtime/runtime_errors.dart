// Why the extension runtime could not be had.

enum ExtHostRuntimeErrorKind {
  /// No build for this machine.
  unsupportedPlatform,

  /// The download failed: no connection, a timeout, a dropped transfer,
  /// an HTTP error.
  network,

  /// The download was not the file the manifest names: its size or
  /// SHA-256 differ.
  verification,

  /// The archive could not be unpacked, or the disk refused it.
  install,

  /// What was installed (or given by `BAOCODE_EXTHOST_DIR`) is not a
  /// runtime.
  layout,
}

final class ExtHostRuntimeException implements Exception {
  const ExtHostRuntimeException(
    this.kind,
    this.message, {
    this.cause,
    this.statusCode,
  });

  final ExtHostRuntimeErrorKind kind;
  final String message;
  final Object? cause;

  /// The HTTP status, for a download the server refused.
  final int? statusCode;

  /// Whether trying again may help: a network failure, but not a 404.
  bool get transient =>
      kind == ExtHostRuntimeErrorKind.network &&
      (statusCode == null ||
          statusCode! >= 500 ||
          statusCode == 408 ||
          statusCode == 429);

  @override
  String toString() => cause == null ? message : '$message ($cause)';
}
