import 'package:flutter/foundation.dart';

import 'windows_build.dart' if (dart.library.io) 'windows_build_io.dart';

/// Which desktop app this is: the macOS one, the Windows one, or neither
/// (the web, whatever it runs on). Follows [defaultTargetPlatform], so a
/// test picks one with its variant.
abstract final class AppPlatform {
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// Windows 11 (build 22000), whose window carries the system's acrylic
  /// backdrop (see win32_window.cpp). A test that targets Windows from
  /// another host has no build to read, and uses this one.
  static bool get isWindows11 {
    if (!isWindows) return false;
    if (!hostReportsWindows) return true;
    return hostWindowsBuild >= 22000;
  }
}
