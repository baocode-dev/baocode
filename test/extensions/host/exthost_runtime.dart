import 'dart:io';

/// An extracted runtime for tests tagged `exthost`: `BAOCODE_EXTHOST_DIR`,
/// else the one the experiments downloaded; null when there is none.
String? exthostRuntimeDir() {
  for (final dir in [
    Platform.environment['BAOCODE_EXTHOST_DIR'],
    '/tmp/exthost-dl/reh-darwin-arm64',
  ]) {
    if (dir != null && File('$dir/out/server-main.js').existsSync()) {
      return dir;
    }
  }
  return null;
}
