import 'dart:async';

import 'package:flutter/foundation.dart';

import '../platform/app_platform.dart';
import '../workspace/window_controls.dart';

/// settings.json's `window.blur`: whether the windows have the system's
/// blur under them (macOS's sidebar material, Windows 11's acrylic), what
/// is behind them showing through the sidebar and the conversation, as
/// Settings → Appearance turns it on or off. Unset: off, the windows
/// opaque.
abstract final class WindowBlur {
  static const settingKey = 'window.blur';

  /// Whether the windows are blurred now; main() keeps it to settings.json
  /// ([follow]), and the windows to it.
  static final ValueNotifier<bool> enabled = ValueNotifier(false);

  /// Where there is a blur to turn on: macOS, and Windows 11.
  static bool get available => AppPlatform.isMacOS || AppPlatform.isWindows11;

  /// [value] as settings.json has it.
  static bool parse(Object? value) => value == true;

  /// [on] as settings.json keeps it; null (not written) for off.
  static Object? setting(bool on) => on ? true : null;

  /// Sets [enabled] from [read] now and whenever [changes] notifies, and
  /// the windows' blur with it (they start as the last run left them).
  static void follow(Listenable changes, Object? Function() read) {
    void update() => enabled.value = parse(read());
    update();
    changes.addListener(update);
    void tell() => unawaited(WindowControls.setWindowBlur(enabled.value));
    tell();
    enabled.addListener(tell);
  }
}
