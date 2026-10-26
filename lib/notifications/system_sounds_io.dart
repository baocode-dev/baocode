import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// The system's sounds, name to file: macOS's alert sounds (Glass, Ping…)
/// and the user's own beside them, Windows's in its Media folder.
Future<Map<String, String>> listSystemSounds() async {
  final List<String> folders;
  if (Platform.isMacOS) {
    folders = [
      '/System/Library/Sounds',
      if (Platform.environment['HOME'] case final home?)
        p.join(home, 'Library', 'Sounds'),
    ];
  } else if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    folders = [p.join(root, 'Media')];
  } else if (Platform.isLinux) {
    // The freedesktop sound theme's, which desktops play their own from.
    folders = ['/usr/share/sounds/freedesktop/stereo'];
  } else {
    return const {};
  }
  final sounds = <String, String>{};
  for (final folder in folders) {
    try {
      await for (final entry in Directory(folder).list()) {
        if (entry is! File) continue;
        final extension = p.extension(entry.path).toLowerCase();
        if (!const {
          '.aiff',
          '.aif',
          '.wav',
          '.caf',
          '.mp3',
          '.m4a',
          '.oga',
          '.ogg',
        }.contains(extension)) {
          continue;
        }
        // Windows only plays WAV files as they are.
        if (Platform.isWindows && extension != '.wav') continue;
        sounds.putIfAbsent(
          p.basenameWithoutExtension(entry.path),
          () => entry.path,
        );
      }
    } on FileSystemException {
      // A folder that is not there.
    }
  }
  return Map.fromEntries(
    sounds.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase())),
  );
}

/// The players a Linux desktop has, tried in turn: PipeWire's, PulseAudio's
/// (PipeWire's stand-in for it too), ALSA's (WAV files only).
const linuxSoundPlayers = ['pw-play', 'paplay', 'aplay'];

/// Plays a sound file at [path], or one's [bytes], with the first of
/// [linuxSoundPlayers] there is (#229): Linux has no player of the app's,
/// the system's does. Nothing when there is none.
Future<void> playLinuxSound({String? path, Uint8List? bytes}) async {
  final file = path ?? (bytes == null ? null : await _soundFile(bytes));
  if (file == null) return;
  for (final player in linuxSoundPlayers) {
    try {
      await Process.start(player, [file], mode: ProcessStartMode.detached);
      return;
    } on ProcessException {
      // Not installed: the next.
    }
  }
}

/// [bytes] as a file to play, written once: by their length and a hash.
Future<String> _soundFile(Uint8List bytes) async {
  var hash = 0x811c9dc5;
  for (final byte in bytes) {
    hash = ((hash ^ byte) * 0x01000193) & 0xffffffff;
  }
  final file = File(
    p.join(
      Directory.systemTemp.path,
      'baocode-sounds',
      '${bytes.length}-${hash.toRadixString(16)}.wav',
    ),
  );
  if (!await file.exists()) {
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }
  return file.path;
}

/// A notification of the desktop's, by `notify-send` (libnotify), where
/// there is one: no sound of its own, and nothing when clicked.
Future<void> notifyLinux(String title, String body) async {
  try {
    await Process.start('notify-send', [
      '--app-name=BaoCode',
      title,
      body,
    ], mode: ProcessStartMode.detached);
  } on ProcessException {
    // No libnotify.
  }
}
