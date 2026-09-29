import 'package:flutter/foundation.dart';

/// Which desktop app this is: the macOS one, the Windows one, or neither
/// (the web, whatever it runs on). Follows [defaultTargetPlatform], so a
/// test picks one with its variant.
abstract final class AppPlatform {
  static bool get isMacOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
}
