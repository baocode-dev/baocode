import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls of the native window, where there is one (the macOS app; see
/// MainFlutterWindow.swift).
abstract final class WindowControls {
  static const _channel = MethodChannel('monad/window');

  /// Whether the window can be kept on top: not in a browser tab.
  static bool get canKeepOnTop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  /// Keeps the window above other apps' windows, or not.
  static Future<void> setAlwaysOnTop(bool onTop) async {
    if (!canKeepOnTop) return;
    try {
      await _channel.invokeMethod<void>('setAlwaysOnTop', onTop);
    } on MissingPluginException {
      // A host without the channel (e.g. tests).
    }
  }
}
