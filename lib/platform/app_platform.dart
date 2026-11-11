import 'package:flutter/foundation.dart';

import 'windows_build.dart' if (dart.library.io) 'windows_build_io.dart';

/// Which desktop app this is: macOS, Windows, Linux, or neither (the web).
/// Follows [defaultTargetPlatform], so a test picks one with its variant.
abstract final class AppPlatform {
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  /// The GTK desktop (linux/). Not the SSH remote server.
  static bool get isLinux =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  /// A desktop window, as opposed to the web. Linux is one: file dialogs and
  /// the shell run here. Native menus stay macOS and Windows (see
  /// WindowControls.hasNativeMenus).
  static bool get isDesktop => isMacOS || isWindows || isLinux;

  /// Windows, and this process really on it: not a test that targets
  /// Windows from another host.
  static bool get isWindowsHost => isWindows && hostReportsWindows;

  /// Windows 11 (build 22000), whose window carries the system's acrylic
  /// backdrop (see win32_window.cpp). A test that targets Windows from
  /// another host has no build to read, and uses this one.
  static bool get isWindows11 {
    if (!isWindows) return false;
    if (!hostReportsWindows) return true;
    return hostWindowsBuild >= 22000;
  }
}
