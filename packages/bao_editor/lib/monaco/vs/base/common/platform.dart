/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/platform.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `OperatingSystem`, `OS`,
// `isWindows`, `isMacintosh` and `isLinux`.
// Deviations: upstream fixes the platform once, when the module loads (from
// Node's `process.platform` or the browser user agent). Here the host comes
// from `dart:io`, and [debugOperatingSystemOverride] can replace it at any
// time so tests can run the Windows and POSIX code paths on one machine.
// Everything derived from it (`path.sep`, `URI.fsPath`, glob) reads it on each
// call. Set the override before creating objects that capture the platform
// (parsed globs, registered language associations).

import 'dart:io' as io;

/// Upstream `OperatingSystem` (`Windows = 1`, `Macintosh = 2`, `Linux = 3`).
enum OperatingSystem {
  windows(1),
  macintosh(2),
  linux(3);

  const OperatingSystem(this.value);

  final int value;
}

/// When non-null, replaces the host operating system for [os], [isWindows],
/// [isMacintosh] and [isLinux]. For tests; `null` restores the host.
OperatingSystem? debugOperatingSystemOverride;

final OperatingSystem _host = io.Platform.isWindows
    ? OperatingSystem.windows
    : io.Platform.isMacOS || io.Platform.isIOS
    ? OperatingSystem.macintosh
    : OperatingSystem.linux;

/// Upstream `OS`.
OperatingSystem get os => debugOperatingSystemOverride ?? _host;

bool get isWindows => os == OperatingSystem.windows;

bool get isMacintosh => os == OperatingSystem.macintosh;

bool get isLinux => os == OperatingSystem.linux;
