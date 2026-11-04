import 'dart:io';

/// Ends process [pid] and every process it started, on Windows
/// (`taskkill /T /F`); [Process.killPid] elsewhere.
void killProcessTree(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
  if (!Platform.isWindows) {
    Process.killPid(pid, signal);
    return;
  }
  try {
    Process.runSync('taskkill', ['/T', '/F', '/PID', '$pid']);
  } on ProcessException {
    Process.killPid(pid);
  }
}
