/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/labels.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971: `tildify`.

import 'platform.dart' as platform;
import 'strings.dart';

String? _cachedHome;
String? _cachedNormalizedHome;

/// Upstream `tildify`: [path] under [userHome] as `~/…` (case-insensitively
/// but on Linux); unchanged on Windows.
String tildify(String path, String userHome, [platform.OperatingSystem? os]) {
  os ??= platform.os;
  if (os == platform.OperatingSystem.windows ||
      path.isEmpty ||
      userHome.isEmpty) {
    return path; // unsupported on Windows
  }

  var normalizedUserHome = _cachedHome == userHome
      ? _cachedNormalizedHome
      : null;
  if (normalizedUserHome == null) {
    normalizedUserHome = userHome;
    if (platform.isWindows) {
      // make sure that the path is POSIX normalized on Windows
      normalizedUserHome = _toSlashes(normalizedUserHome);
    }
    normalizedUserHome = '${rtrim(normalizedUserHome, '/')}/';
    _cachedHome = userHome;
    _cachedNormalizedHome = normalizedUserHome;
  }

  var normalizedPath = path;
  if (platform.isWindows) {
    // make sure that the path is POSIX normalized on Windows
    normalizedPath = _toSlashes(normalizedPath);
  }

  // Linux: case sensitive, macOS: case insensitive
  if (os == platform.OperatingSystem.linux
      ? normalizedPath.startsWith(normalizedUserHome)
      : startsWithIgnoreCase(normalizedPath, normalizedUserHome)) {
    return '~/${normalizedPath.substring(normalizedUserHome.length)}';
  }

  return path;
}

/// extpath.ts `toSlashes`.
String _toSlashes(String osPath) => osPath.replaceAll(r'\', '/');
