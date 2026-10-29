import 'dart:io';

import 'package:bao_sampler/bao_sampler.dart';
import 'package:path/path.dart' as p;

import '../platform/event_log.dart';
import '../update/version.dart';

/// How the app ends, written down: the signals that end it ([watchExitSignals])
/// and, on Linux, a crash ([installCrashHandler]). A quit is written by
/// main.dart's onExitRequested; Windows' session end and crash by its
/// runner (windows/runner/log_folder.h, hang_watchdog.h); macOS' crash is
/// its own report, the next run's to find (see [EventLog]).
void watchExit(String logsFolder) {
  watchExitSignals();
  installCrashHandler(logsFolder);
}

/// Writes down a signal that ends the app (macOS, Linux): SIGTERM (`kill`,
/// the session ending), SIGHUP (the terminal it was started from gone),
/// SIGINT (Ctrl+C there). Then the app ends as it would have, by the
/// signal's code. SIGKILL is not to be caught: the next run tells of the
/// run that ended without a word (see [EventLog]).
void watchExitSignals() {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  for (final signal in exitSignals) {
    try {
      signal.watch().listen((_) {
        appExit(signal.name);
        exit(128 + signal.signalNumber);
      });
    } on Object {
      // Not to be watched here.
    }
  }
}

/// The signals [watchExitSignals] writes down.
const exitSignals = [
  ProcessSignal.sigterm,
  ProcessSignal.sighup,
  ProcessSignal.sigint,
];

/// The most crash reports Linux' handler leaves in `hangs/`: the oldest go.
const keptCrashReports = 10;

/// Linux' crash handler (package:bao_sampler's [CrashHandler]): its reports
/// in [logsFolder]'s `hangs/`, room left for one more.
void installCrashHandler(String logsFolder) {
  if (!Platform.isLinux) return;
  final hangs = Directory(p.join(logsFolder, 'hangs'));
  try {
    hangs.createSync(recursive: true);
    final reports = [
      for (final entity in hangs.listSync(followLinks: false))
        if (entity is File &&
            p.basename(entity.path).startsWith('crash-') &&
            entity.path.endsWith('.txt'))
          entity,
    ]..sort((a, b) => b.path.compareTo(a.path));
    for (final old in reports.skip(keptCrashReports - 1)) {
      old.deleteSync();
    }
  } on FileSystemException {
    // Written where it can be, if at all.
  }
  CrashHandler.install(
    events: p.join(logsFolder, 'events.log'),
    reports: hangs.path,
    header: 'BaoCode $appVersionString',
  );
}
