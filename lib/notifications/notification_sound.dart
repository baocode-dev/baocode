import 'package:flutter/services.dart';

import 'attention_host.dart';
import 'attention_settings.dart';
import 'system_sounds_stub.dart'
    if (dart.library.io) 'system_sounds_io.dart'
    as platform;

/// The sounds `notifications.sound` can name, and playing them.
abstract final class NotificationSound {
  /// The app's own "ding" (tool/generate_notification_sound.dart).
  static const microwaveAsset = 'assets/sounds/microwave.wav';

  static Future<Uint8List>? _microwave;

  /// The system's sounds, name to file, sorted by name; read once.
  static Future<Map<String, String>> systemSounds() =>
      _systemSounds ??= platform.listSystemSounds();
  static Future<Map<String, String>>? _systemSounds;

  /// Plays [value] (see [NotificationSoundValue]) on [host]; nothing for
  /// none, or a system sound that is not there.
  static Future<void> play(AttentionHost host, String value) async {
    if (value == NotificationSoundValue.none) return;
    if (value == NotificationSoundValue.microwave) {
      final bytes = await (_microwave ??= rootBundle
          .load(microwaveAsset)
          .then((data) => data.buffer.asUint8List()));
      return host.playSound(bytes: bytes);
    }
    if (NotificationSoundValue.systemName(value) case final name?) {
      final path = (await systemSounds())[name];
      if (path != null) await host.playSound(path: path);
      return;
    }
    await host.playSound(path: value);
  }
}
