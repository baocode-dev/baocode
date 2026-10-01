import 'package:flutter/foundation.dart';

import 'shell_command_stub.dart'
    if (dart.library.io) 'shell_command_io.dart'
    as platform;

/// Where the `code` command stands, as [ShellCommand.status] finds it.
enum ShellCommandStatus {
  /// No command to install here (the web).
  unsupported,

  /// Not there, or not where a shell would find it.
  notInstalled,

  /// Ours, and the one a shell runs.
  installed,

  /// Another app's `code` (VS Code's, say) is where ours would go, or comes
  /// first on the PATH: installing ours would take its place.
  occupied,
}

/// Why the command could not be installed or removed, in words to show.
class ShellCommandException implements Exception {
  const ShellCommandException(this.message, {this.cancelled = false});

  final String message;

  /// Whether the user said no to the system asking for an administrator's
  /// password (macOS), so there is nothing to tell them.
  final bool cancelled;

  @override
  String toString() => 'ShellCommandException: $message';
}

/// The `code` command, which opens files and folders in the app from a
/// terminal as VS Code's own does (and so may take its place): a script in
/// /usr/local/bin on macOS, which hands them to the app through `open`;
/// a `code.cmd` on the user's PATH on Windows, which starts the app with
/// them (the one running takes them, see windows/runner/main.cpp). Either
/// way they come in through OpenRequests.
abstract final class ShellCommand {
  static const name = 'code';

  /// Whether there is a command to install: the desktop app.
  static bool get supported => _installer != null;

  /// Whether it is installed, and the one a shell finds.
  static Future<ShellCommandStatus> status() async =>
      await _installer?.status() ?? ShellCommandStatus.unsupported;

  /// Installs it, or puts it back as it should be (on Windows, its folder
  /// on the user's PATH). Throws a [ShellCommandException] when it cannot,
  /// the user's refusal to give the password included, and when the place
  /// is [ShellCommandStatus.occupied] unless [overwrite].
  static Future<void> install({bool overwrite = false}) async {
    final installer = _installer;
    if (installer == null) {
      throw const ShellCommandException(
        'The shell command is not available here.',
      );
    }
    await installer.install(overwrite: overwrite);
  }

  /// Removes it, when it is ours; another app's is left as it is.
  static Future<void> uninstall() async => _installer?.uninstall();

  /// Where it is, or would be, installed; empty where it cannot be.
  static String get location => _installer?.location ?? '';

  /// Stands in for the platform's own, e.g. one under test.
  @visibleForTesting
  static ShellCommandInstaller? debugInstaller;

  static ShellCommandInstaller? get _installer =>
      debugInstaller ?? platform.platformShellCommand();
}

/// What installs the command on one platform (see shell_command_io.dart).
abstract interface class ShellCommandInstaller {
  String get location;

  Future<ShellCommandStatus> status();

  Future<void> install({bool overwrite = false});

  Future<void> uninstall();
}
