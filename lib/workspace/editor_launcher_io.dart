import 'dart:io';

/// `open [-a app] path`, on macOS.
Future<bool> openPath(String path, {String? appName}) async {
  if (!Platform.isMacOS) return false;
  final home = Platform.environment['HOME'];
  if (path.startsWith('~/') && home != null) {
    path = '$home${path.substring(1)}';
  }
  try {
    final result = await Process.run('open', [
      if (appName != null) ...['-a', appName],
      path,
    ]);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
