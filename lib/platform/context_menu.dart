import 'package:flutter/foundation.dart';

import 'context_menu_stub.dart'
    if (dart.library.io) 'context_menu_io.dart'
    as platform;

/// Where the system's context menu stands, as [ContextMenu.status] finds
/// it.
enum ContextMenuStatus {
  /// No menu to add here (the web, Linux), or none in this build of the
  /// app (a macOS one without its Finder extension).
  unsupported,

  /// Not in the menu.
  off,

  /// In the menu.
  on,
}

/// Why the menu could not be turned on or off, in words to show.
class ContextMenuException implements Exception {
  const ContextMenuException(this.message);

  final String message;

  @override
  String toString() => 'ContextMenuException: $message';
}

/// The menu's items, in the user's language: Open with BaoCode (a new
/// agent) and Open with Fast Ide (a new IDE window).
typedef ContextMenuLabels = ({String agent, String ide});

/// Open with BaoCode and Open with Fast Ide in the system's context menu on
/// files, folders and a folder's background: Explorer's on Windows (what
/// the installer's task adds, see tool/baocode.iss, written for the user
/// alone), Finder's on macOS (the app's Finder extension, see
/// macos/FinderExtension/FinderSync.swift, turned on or off as System
/// Settings would). Either way, what is chosen comes in through
/// OpenRequests as the same request.
abstract final class ContextMenu {
  /// Whether there is a menu to add: the desktop app.
  static bool get supported => _installer != null;

  static Future<ContextMenuStatus> status() async =>
      await _installer?.status() ?? ContextMenuStatus.unsupported;

  /// Puts the items in the menu, named [labels] where the platform names
  /// them (Windows; the Finder extension names its own). Throws a
  /// [ContextMenuException] when it cannot.
  static Future<void> install(ContextMenuLabels labels) async {
    final installer = _installer;
    if (installer == null) {
      throw const ContextMenuException(
        'The context menu is not available here.',
      );
    }
    await installer.install(labels);
  }

  /// Takes them out of the menu. Throws a [ContextMenuException] when it
  /// cannot.
  static Future<void> uninstall() async => _installer?.uninstall();

  /// Where the system turns it on and off itself (macOS' System Settings,
  /// its extensions), when there is such a place; null otherwise.
  static Future<void> Function()? get openSystemSettings =>
      _installer?.openSystemSettings;

  /// Stands in for the platform's own, e.g. one under test.
  @visibleForTesting
  static ContextMenuInstaller? debugInstaller;

  static ContextMenuInstaller? get _installer =>
      debugInstaller ?? platform.platformContextMenu();
}

/// What adds the menu on one platform (see context_menu_io.dart).
abstract interface class ContextMenuInstaller {
  Future<ContextMenuStatus> status();

  Future<void> install(ContextMenuLabels labels);

  Future<void> uninstall();

  Future<void> Function()? get openSystemSettings;
}
