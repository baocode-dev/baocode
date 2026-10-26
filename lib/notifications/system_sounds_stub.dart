import 'dart:typed_data';

/// No system sounds to list on the web.
Future<Map<String, String>> listSystemSounds() async => const {};

/// No sound players on the web.
Future<void> playLinuxSound({String? path, Uint8List? bytes}) async {}

/// No desktop notifications on the web.
Future<void> notifyLinux(String title, String body) async {}
