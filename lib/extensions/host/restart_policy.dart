/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/common/abstractExtensionService.ts
// (`ExtensionHostCrashTracker`).

/// Whether a crashed extension host is started again by itself: not once
/// it has crashed [crashLimit] times within [window] (then the user is
/// asked).
final class ExtensionHostCrashTracker {
  ExtensionHostCrashTracker({
    this.crashLimit = 3,
    this.window = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int crashLimit;
  final Duration window;
  final DateTime Function() _now;
  final _recentCrashes = <DateTime>[];

  void _removeOldCrashes() {
    final limit = _now().subtract(window);
    while (_recentCrashes.isNotEmpty && _recentCrashes.first.isBefore(limit)) {
      _recentCrashes.removeAt(0);
    }
  }

  void registerCrash() {
    _removeOldCrashes();
    _recentCrashes.add(_now());
  }

  bool shouldAutomaticallyRestart() {
    _removeOldCrashes();
    return _recentCrashes.length < crashLimit;
  }
}
