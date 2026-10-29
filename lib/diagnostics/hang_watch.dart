import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../platform/app_platform.dart';
import '../platform/event_log.dart';
import 'frame_watch.dart';

/// The app's own side's logs: the Windows app's (windows/runner/
/// log_folder.h) and the macOS app's hang watchdog's (macos/Runner/
/// HangWatchdog.swift).
const logsChannel = MethodChannel('baocode/logs');

/// Tells the app's own side where the logs [folder] is (`setFolder`): its
/// own logs go there too (Windows' window.log, the hang reports in
/// hangs/), and the Windows app keeps it for what it writes before Dart
/// runs. On macOS, a hang the watchdog wrote down is told as it ends
/// ([handleHostCall]).
Future<void> shareLogsFolder(String folder) async {
  if (!AppPlatform.isWindows && !AppPlatform.isMacOS) return;
  if (AppPlatform.isMacOS) logsChannel.setMethodCallHandler(handleHostCall);
  try {
    await logsChannel.invokeMethod<void>('setFolder', folder);
  } on MissingPluginException {
    // A host without the channel.
  } on PlatformException catch (error) {
    debugPrint('logs.setFolder: $error');
  }
}

/// `hangEnded` (seconds, sample): the main thread answers again after the
/// hang the macOS watchdog wrote down as it began (`[hang]`, and its
/// sample under hangs/). Written with what the app shows now: what it was
/// at, most likely, the hang being over just now.
@visibleForTesting
Future<void> handleHostCall(MethodCall call) async {
  if (call.method != 'hangEnded') throw MissingPluginException();
  final arguments = call.arguments is Map ? call.arguments as Map : const {};
  final seconds = arguments['seconds'];
  final sample = arguments['sample'];
  appEvent(
    'hang',
    [
      'answering again after '
          '${seconds is num ? seconds.toStringAsFixed(1) : '?'} s',
      if (sample is String) 'sample $sample',
      FrameWatch.describeState(),
    ].join('; '),
  );
}
