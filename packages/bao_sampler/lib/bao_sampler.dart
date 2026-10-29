import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'src/sampler_native.dart';

/// What the app's UI thread (the one the Dart code runs on) was doing, on
/// Windows and Linux: its stack taken every [StackSampler.start]'s
/// interval, from a native thread, and written down as a text report (the
/// same stacks counted together, the most first). Its frames are
/// `module+0x…`: the Dart code's are `app.so+0x…` (Windows) or
/// `libapp.so+0x…` (Linux), named by the release's symbols.
///
/// The thread is held only while its registers and the top of its stack
/// are copied (some microseconds), then walked from the copy.
abstract final class StackSampler {
  static bool? _ready;

  /// Whether this platform samples (Windows and Linux, the app built
  /// ahead of time: under `flutter test` or `flutter run` the Dart code is
  /// not in a file, so not).
  ///
  /// The first call sets it up, and must be on the UI thread: the root
  /// isolate's.
  static bool get available => _ready ??= _init();

  static bool _init() {
    if (!Platform.isWindows && !Platform.isLinux) return false;
    try {
      return samplerInit() != 0;
    } on Object {
      // No native half built (an asset missing).
      return false;
    }
  }

  /// Samples the UI thread for [duration], every [interval], into the file
  /// at [path], written once done. False if one is under way, or this
  /// platform samples not.
  static bool start(
    String path, {
    Duration duration = const Duration(seconds: 3),
    Duration interval = const Duration(milliseconds: 20),
  }) {
    if (!available) return false;
    final bytes = Uint8List.fromList([...utf8.encode(path), 0]);
    return samplerStart(
          bytes.address,
          duration.inMilliseconds,
          interval.inMilliseconds,
        ) !=
        0;
  }
}

/// Writes a crash of the app down on Linux, which keeps no report of it
/// the app can read (native/bao_crash.c): a `crash-<time>-<pid>.txt` of
/// the signal and the stack in [reports], and a line in the event log at
/// [events], `<time> [exit] crashed: SIGSEGV at libapp.so+0x…`.
abstract final class CrashHandler {
  /// Sets it up, the reports' first line [header] (the app's version);
  /// false on other platforms, or without the native half.
  static bool install({
    required String events,
    required String reports,
    required String header,
  }) {
    if (!Platform.isLinux) return false;
    Uint8List z(String text) => Uint8List.fromList([...utf8.encode(text), 0]);
    try {
      final (e, r, h) = (z(events), z(reports), z(header));
      return crashInstall(e.address, r.address, h.address) != 0;
    } on Object {
      return false;
    }
  }
}
