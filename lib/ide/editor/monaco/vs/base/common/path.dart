/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See ../../../LICENSE.txt for license information.
 *--------------------------------------------------------------------------------------------*/
// Subset of VS Code src/vs/base/common/path.ts at
// 6a598d4a13031703d483d103c1d934a36ad27971 (VS Code's copy of Node's
// lib/path.js, v22.15.0, Copyright Joyent, Inc. and other Node contributors,
// MIT): `normalize`, `basename` and `extname` of `win32` and `posix`, `sep`,
// `delimiter`, and the platform-selected top-level functions.
// Deviation: the top-level functions pick `win32` or `posix` from
// platform.dart's `isWindows` on each call (upstream fixes the choice when the
// module loads). Argument type validation is left to Dart's type system.

import 'platform.dart';

const int _charUppercaseA = 65; // A
const int _charLowercaseA = 97; // a
const int _charUppercaseZ = 90; // Z
const int _charLowercaseZ = 122; // z
const int _charDot = 46; // .
const int _charForwardSlash = 47; // /
const int _charBackwardSlash = 92; // \
const int _charColon = 58; // :

bool _isPathSeparator(int code) =>
    code == _charForwardSlash || code == _charBackwardSlash;

bool _isPosixPathSeparator(int code) => code == _charForwardSlash;

bool _isWindowsDeviceRoot(int code) =>
    (code >= _charUppercaseA && code <= _charUppercaseZ) ||
    (code >= _charLowercaseA && code <= _charLowercaseZ);

// Resolves . and .. elements in a path with directory names.
String _normalizeString(
  String path,
  bool allowAboveRoot,
  String separator,
  bool Function(int code) isPathSeparator,
) {
  var res = '';
  var lastSegmentLength = 0;
  var lastSlash = -1;
  var dots = 0;
  var code = 0;
  for (var i = 0; i <= path.length; ++i) {
    if (i < path.length) {
      code = path.codeUnitAt(i);
    } else if (isPathSeparator(code)) {
      break;
    } else {
      code = _charForwardSlash;
    }

    if (isPathSeparator(code)) {
      if (lastSlash == i - 1 || dots == 1) {
        // NOOP
      } else if (dots == 2) {
        if (res.length < 2 ||
            lastSegmentLength != 2 ||
            res.codeUnitAt(res.length - 1) != _charDot ||
            res.codeUnitAt(res.length - 2) != _charDot) {
          if (res.length > 2) {
            final lastSlashIndex = res.lastIndexOf(separator);
            if (lastSlashIndex == -1) {
              res = '';
              lastSegmentLength = 0;
            } else {
              res = res.substring(0, lastSlashIndex);
              lastSegmentLength = res.length - 1 - res.lastIndexOf(separator);
            }
            lastSlash = i;
            dots = 0;
            continue;
          } else if (res.isNotEmpty) {
            res = '';
            lastSegmentLength = 0;
            lastSlash = i;
            dots = 0;
            continue;
          }
        }
        if (allowAboveRoot) {
          res += res.isNotEmpty ? '$separator..' : '..';
          lastSegmentLength = 2;
        }
      } else {
        if (res.isNotEmpty) {
          res += '$separator${path.substring(lastSlash + 1, i)}';
        } else {
          res = path.substring(lastSlash + 1, i);
        }
        lastSegmentLength = i - lastSlash - 1;
      }
      lastSlash = i;
      dots = 0;
    } else if (code == _charDot && dots != -1) {
      ++dots;
    } else {
      dots = -1;
    }
  }
  return res;
}

/// Upstream `IPath` (subset).
abstract interface class IPath {
  String normalize(String path);
  String basename(String path, [String? suffix]);
  String extname(String path);
  String get sep;
  String get delimiter;
}

final class _Win32 implements IPath {
  const _Win32();

  @override
  String get sep => '\\';

  @override
  String get delimiter => ';';

  @override
  String normalize(String path) {
    final len = path.length;
    if (len == 0) return '.';
    var rootEnd = 0;
    String? device;
    var isAbsolute = false;
    final code = path.codeUnitAt(0);

    // Try to match a root.
    if (len == 1) {
      // `path` contains just a single char, exit early.
      return _isPosixPathSeparator(code) ? '\\' : path;
    }
    if (_isPathSeparator(code)) {
      // Possible UNC root. A leading separator means an absolute path of
      // some kind (UNC or otherwise).
      isAbsolute = true;
      if (_isPathSeparator(path.codeUnitAt(1))) {
        // Matched double path separator at the beginning.
        var j = 2;
        var last = j;
        // Match 1 or more non-path separators.
        while (j < len && !_isPathSeparator(path.codeUnitAt(j))) {
          j++;
        }
        if (j < len && j != last) {
          final firstPart = path.substring(last, j);
          last = j;
          // Match 1 or more path separators.
          while (j < len && _isPathSeparator(path.codeUnitAt(j))) {
            j++;
          }
          if (j < len && j != last) {
            last = j;
            // Match 1 or more non-path separators.
            while (j < len && !_isPathSeparator(path.codeUnitAt(j))) {
              j++;
            }
            if (j == len) {
              // A UNC root only: return its normalized version.
              return '\\\\$firstPart\\${path.substring(last)}\\';
            }
            if (j != last) {
              // A UNC root with leftovers.
              device = '\\\\$firstPart\\${path.substring(last, j)}';
              rootEnd = j;
            }
          }
        }
      } else {
        rootEnd = 1;
      }
    } else if (_isWindowsDeviceRoot(code) && path.codeUnitAt(1) == _charColon) {
      // Possible device root.
      device = path.substring(0, 2);
      rootEnd = 2;
      if (len > 2 && _isPathSeparator(path.codeUnitAt(2))) {
        // A separator after the drive name means an absolute path.
        isAbsolute = true;
        rootEnd = 3;
      }
    }

    var tail = rootEnd < len
        ? _normalizeString(
            path.substring(rootEnd),
            !isAbsolute,
            '\\',
            _isPathSeparator,
          )
        : '';
    if (tail.isEmpty && !isAbsolute) {
      tail = '.';
    }
    if (tail.isNotEmpty && _isPathSeparator(path.codeUnitAt(len - 1))) {
      tail += '\\';
    }
    if (!isAbsolute && device == null && path.contains(':')) {
      // Make sure `tail` has not become something Windows might interpret
      // as an absolute path (CVE-2024-36139).
      if (tail.length >= 2 &&
          _isWindowsDeviceRoot(tail.codeUnitAt(0)) &&
          tail.codeUnitAt(1) == _charColon) {
        return '.\\$tail';
      }
      var index = path.indexOf(':');
      do {
        if (index == len - 1 || _isPathSeparator(path.codeUnitAt(index + 1))) {
          return '.\\$tail';
        }
      } while ((index = path.indexOf(':', index + 1)) != -1);
    }
    if (device == null) {
      return isAbsolute ? '\\$tail' : tail;
    }
    return isAbsolute ? '$device\\$tail' : '$device$tail';
  }

  @override
  String basename(String path, [String? suffix]) {
    var start = 0;
    var end = -1;
    var matchedSlash = true;
    int i;

    // Skip a drive letter prefix so its separator is not taken as an extra
    // separator at the end of the path.
    if (path.length >= 2 &&
        _isWindowsDeviceRoot(path.codeUnitAt(0)) &&
        path.codeUnitAt(1) == _charColon) {
      start = 2;
    }

    if (suffix != null && suffix.isNotEmpty && suffix.length <= path.length) {
      if (suffix == path) return '';
      var extIdx = suffix.length - 1;
      var firstNonSlashEnd = -1;
      for (i = path.length - 1; i >= start; --i) {
        final code = path.codeUnitAt(i);
        if (_isPathSeparator(code)) {
          // Stop at a separator that is not part of the trailing ones.
          if (!matchedSlash) {
            start = i + 1;
            break;
          }
        } else {
          if (firstNonSlashEnd == -1) {
            // Remember the first non-separator in case the extension does
            // not match.
            matchedSlash = false;
            firstNonSlashEnd = i + 1;
          }
          if (extIdx >= 0) {
            // Try to match the explicit extension.
            if (code == suffix.codeUnitAt(extIdx)) {
              if (--extIdx == -1) {
                // Matched the extension: this is the end of the component.
                end = i;
              }
            } else {
              // No match: the result is the entire path component.
              extIdx = -1;
              end = firstNonSlashEnd;
            }
          }
        }
      }
      if (start == end) {
        end = firstNonSlashEnd;
      } else if (end == -1) {
        end = path.length;
      }
      return path.substring(start, end);
    }
    for (i = path.length - 1; i >= start; --i) {
      if (_isPathSeparator(path.codeUnitAt(i))) {
        // Stop at a separator that is not part of the trailing ones.
        if (!matchedSlash) {
          start = i + 1;
          break;
        }
      } else if (end == -1) {
        // The first non-separator marks the end of the component.
        matchedSlash = false;
        end = i + 1;
      }
    }
    if (end == -1) return '';
    return path.substring(start, end);
  }

  @override
  String extname(String path) {
    var start = 0;
    var startDot = -1;
    var startPart = 0;
    var end = -1;
    var matchedSlash = true;
    // State of the characters (if any) before the first dot and after any
    // path separator.
    var preDotState = 0;

    // Skip a drive letter prefix so its separator is not taken as an extra
    // separator at the end of the path.
    if (path.length >= 2 &&
        path.codeUnitAt(1) == _charColon &&
        _isWindowsDeviceRoot(path.codeUnitAt(0))) {
      start = startPart = 2;
    }

    for (var i = path.length - 1; i >= start; --i) {
      final code = path.codeUnitAt(i);
      if (_isPathSeparator(code)) {
        // Stop at a separator that is not part of the trailing ones.
        if (!matchedSlash) {
          startPart = i + 1;
          break;
        }
        continue;
      }
      if (end == -1) {
        // The first non-separator marks the end of the extension.
        matchedSlash = false;
        end = i + 1;
      }
      if (code == _charDot) {
        // The first dot marks the start of the extension.
        if (startDot == -1) {
          startDot = i;
        } else if (preDotState != 1) {
          preDotState = 1;
        }
      } else if (startDot != -1) {
        // A non-dot, non-separator before the dot: likely a non-empty
        // extension.
        preDotState = -1;
      }
    }

    if (startDot == -1 ||
        end == -1 ||
        // A non-dot character immediately before the dot.
        preDotState == 0 ||
        // The right-most trimmed path component is exactly '..'.
        (preDotState == 1 &&
            startDot == end - 1 &&
            startDot == startPart + 1)) {
      return '';
    }
    return path.substring(startDot, end);
  }
}

final class _Posix implements IPath {
  const _Posix();

  @override
  String get sep => '/';

  @override
  String get delimiter => ':';

  @override
  String normalize(String path) {
    if (path.isEmpty) return '.';
    final isAbsolute = path.codeUnitAt(0) == _charForwardSlash;
    final trailingSeparator =
        path.codeUnitAt(path.length - 1) == _charForwardSlash;

    // Normalize the path.
    path = _normalizeString(path, !isAbsolute, '/', _isPosixPathSeparator);

    if (path.isEmpty) {
      if (isAbsolute) return '/';
      return trailingSeparator ? './' : '.';
    }
    if (trailingSeparator) path += '/';
    return isAbsolute ? '/$path' : path;
  }

  @override
  String basename(String path, [String? suffix]) {
    var start = 0;
    var end = -1;
    var matchedSlash = true;
    int i;

    if (suffix != null && suffix.isNotEmpty && suffix.length <= path.length) {
      if (suffix == path) return '';
      var extIdx = suffix.length - 1;
      var firstNonSlashEnd = -1;
      for (i = path.length - 1; i >= 0; --i) {
        final code = path.codeUnitAt(i);
        if (code == _charForwardSlash) {
          // Stop at a separator that is not part of the trailing ones.
          if (!matchedSlash) {
            start = i + 1;
            break;
          }
        } else {
          if (firstNonSlashEnd == -1) {
            // Remember the first non-separator in case the extension does
            // not match.
            matchedSlash = false;
            firstNonSlashEnd = i + 1;
          }
          if (extIdx >= 0) {
            // Try to match the explicit extension.
            if (code == suffix.codeUnitAt(extIdx)) {
              if (--extIdx == -1) {
                // Matched the extension: this is the end of the component.
                end = i;
              }
            } else {
              // No match: the result is the entire path component.
              extIdx = -1;
              end = firstNonSlashEnd;
            }
          }
        }
      }
      if (start == end) {
        end = firstNonSlashEnd;
      } else if (end == -1) {
        end = path.length;
      }
      return path.substring(start, end);
    }
    for (i = path.length - 1; i >= 0; --i) {
      if (path.codeUnitAt(i) == _charForwardSlash) {
        // Stop at a separator that is not part of the trailing ones.
        if (!matchedSlash) {
          start = i + 1;
          break;
        }
      } else if (end == -1) {
        // The first non-separator marks the end of the component.
        matchedSlash = false;
        end = i + 1;
      }
    }
    if (end == -1) return '';
    return path.substring(start, end);
  }

  @override
  String extname(String path) {
    var startDot = -1;
    var startPart = 0;
    var end = -1;
    var matchedSlash = true;
    // State of the characters (if any) before the first dot and after any
    // path separator.
    var preDotState = 0;
    for (var i = path.length - 1; i >= 0; --i) {
      final char = path.codeUnitAt(i);
      if (char == _charForwardSlash) {
        // Stop at a separator that is not part of the trailing ones.
        if (!matchedSlash) {
          startPart = i + 1;
          break;
        }
        continue;
      }
      if (end == -1) {
        // The first non-separator marks the end of the extension.
        matchedSlash = false;
        end = i + 1;
      }
      if (char == _charDot) {
        // The first dot marks the start of the extension.
        if (startDot == -1) {
          startDot = i;
        } else if (preDotState != 1) {
          preDotState = 1;
        }
      } else if (startDot != -1) {
        // A non-dot, non-separator before the dot: likely a non-empty
        // extension.
        preDotState = -1;
      }
    }

    if (startDot == -1 ||
        end == -1 ||
        // A non-dot character immediately before the dot.
        preDotState == 0 ||
        // The right-most trimmed path component is exactly '..'.
        (preDotState == 1 &&
            startDot == end - 1 &&
            startDot == startPart + 1)) {
      return '';
    }
    return path.substring(startDot, end);
  }
}

const IPath win32 = _Win32();
const IPath posix = _Posix();

IPath get _platformPath => isWindows ? win32 : posix;

String normalize(String path) => _platformPath.normalize(path);

String basename(String path, [String? suffix]) =>
    _platformPath.basename(path, suffix);

String extname(String path) => _platformPath.extname(path);

String get sep => _platformPath.sep;

String get delimiter => _platformPath.delimiter;
