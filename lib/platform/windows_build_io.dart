import 'dart:io';

/// Whether this process is actually running on Windows. A test can target
/// Windows from another host, which reports no build.
bool get hostReportsWindows => Platform.isWindows;

/// Whether this process is a `flutter test` run, which sets FLUTTER_TEST.
bool get hostIsTest => Platform.environment.containsKey('FLUTTER_TEST');

/// The OS build, from `Platform.operatingSystemVersion` (`Build 26100`).
/// Zero when it is not Windows, or the string has no build.
int get hostWindowsBuild {
  if (!Platform.isWindows) return 0;
  final match = RegExp(r'Build (\d+)')
      .firstMatch(Platform.operatingSystemVersion);
  return int.tryParse(match?.group(1) ?? '') ?? 0;
}
