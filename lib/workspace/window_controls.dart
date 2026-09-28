import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../chat/chat_models.dart';

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

  /// Whether there is a native folder picker: the desktop app.
  static bool get canPickDirectory => canKeepOnTop;

  /// Asks the user for a folder (the native open panel); null if they
  /// cancel or there is no such panel.
  static Future<String?> pickDirectory() async {
    if (!canKeepOnTop) return null;
    try {
      return await _channel.invokeMethod<String>('pickDirectory');
    } on MissingPluginException {
      return null;
    }
  }

  /// Images on the clipboard, when what it holds is images rather than
  /// text.
  static Future<List<ImageAttachment>> readPasteboardImages() =>
      _images('readPasteboardImages');

  static Future<List<ImageAttachment>> _images(String method) async {
    if (!canKeepOnTop) return const [];
    try {
      final images = await _channel.invokeListMethod<Map<Object?, Object?>>(
        method,
      );
      return [
        for (final image in images ?? const <Map<Object?, Object?>>[])
          if (image['bytes'] case final Uint8List bytes)
            ImageAttachment(
              bytes: bytes,
              mediaType: image['type'] as String? ?? 'image/png',
              name: image['name'] as String?,
            ),
      ];
    } on MissingPluginException {
      return const [];
    }
  }
}
