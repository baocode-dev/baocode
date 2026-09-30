/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Checks the links the detectors found against the file system: a path is a
// link only if a file or folder is there.
//
// Adapted from VS Code 6a598d4a13031703d483d103c1d934a36ad27971:
// src/vs/workbench/contrib/terminalContrib/links/browser/
// terminalLinkResolver.ts (and `uriToFsPath` of src/vs/base/common/uri.ts).
//
// Upstream's `ITerminalLinkResolver.resolveLink(processManager, link, uri?)`
// with the workbench's file service is [TerminalLinkResolver.resolve] with
// the directory relative links resolve against; a `file://` link is its own
// URI. [TerminalFileLinkResolver] is upstream's resolver on a stat function,
// dart:io's by default (none on the web, where nothing resolves).
//
// Deviations: no remote terminals (`vscode-remote` URIs) and no WSL `/mnt/`
// paths (upstream asks the backend's `wslpath`); `\\wsl$\` paths are left as
// they are when the process's OS is Windows (upstream: when the app runs on
// Windows). The cache is keyed by the directory as well as the link (the
// cwd can change), and expires 10 s after the last write by a clock instead
// of a timer. A `file://` URI on macOS or Linux is its path, without
// upstream's (Windows-only meaningful) drive letter handling.

import 'package:path/path.dart' as p;

import 'terminal_link_parsing.dart';
import 'terminal_link_resolver_stub.dart'
    if (dart.library.io) 'terminal_link_resolver_io.dart'
    as platform;

/// A link that exists on the file system: its absolute [path], and whether
/// that is a folder.
typedef ResolvedTerminalLink = ({String path, bool isDirectory});

/// Resolves links to files and folders.
abstract interface class TerminalLinkResolver {
  /// Where [link] is on the file system, or null when nothing is there.
  ///
  /// [link] is the link's text: an absolute path, a path relative to [cwd]
  /// or the user's home (`~`), possibly with a line and column suffix or a
  /// query string, or a `file://` URI. [cwd] is empty when unknown, and then
  /// relative links do not resolve.
  Future<ResolvedTerminalLink?> resolve(String link, String cwd);
}

/// Whether [path] is a folder (true), a file (false) or nothing (null).
typedef TerminalLinkStat = Future<bool?> Function(String path);

/// The operating system the app runs on (Linux on the web).
OperatingSystem get hostOperatingSystem => platform.hostOperatingSystem;

/// Path syntax of [os], upstream's `osPathModule`.
p.Context osPathContext(OperatingSystem os) =>
    os == OperatingSystem.windows ? p.windows : p.posix;

/// Joins paths as Node.js' `path.join` does: [part] is appended even when
/// absolute (package:path would start over at it).
String joinPath(p.Context osPath, String base, String part) =>
    osPath.normalize('$base${osPath.separator}$part');

/// The file system path of a `file://` [uri] on [os], or null for another
/// scheme. An authority is a UNC host (`//host/path`).
String? fileUriToPath(Uri uri, OperatingSystem os) {
  if (uri.scheme != 'file') {
    return null;
  }
  try {
    final authority = Uri.decodeComponent(uri.authority);
    final path = Uri.decodeComponent(uri.path);
    String value;
    if (authority.isNotEmpty && path.length > 1) {
      // unc path: file://shares/c$/far/boo
      value = '//$authority$path';
    } else if (os == OperatingSystem.windows &&
        RegExp(r'^/[a-zA-Z]:').hasMatch(path)) {
      // windows drive letter: file:///c:/far/boo
      value = path.substring(1);
    } else {
      // other path
      value = path;
    }
    if (os == OperatingSystem.windows) {
      value = value.replaceAll('/', r'\');
    }
    return value;
  } on ArgumentError {
    return null;
  }
}

/// The `file:` URI of [path] on [os], as VS Code's `URI.file`: `\` is a
/// separator on Windows, `//host/...` is a UNC host. Unlike Dart's
/// `Uri.file`, any character is accepted (`:` in a Windows file name).
Uri pathToFileUri(String path, OperatingSystem os) {
  var authority = '';
  // normalize to fwd-slashes on windows, on other systems bwd-slashes are
  // valid filename character, eg /f\oo/ba\r.txt
  if (os == OperatingSystem.windows) {
    path = path.replaceAll(r'\', '/');
  }
  // check for authority as used in UNC shares or use the path as given
  if (path.startsWith('//')) {
    final idx = path.indexOf('/', 2);
    if (idx == -1) {
      authority = path.substring(2);
      path = '/';
    } else {
      authority = path.substring(2, idx);
      path = path.substring(idx);
    }
  }
  if (!path.startsWith('/')) {
    path = '/$path';
  }
  // `%` and `\` are characters of the name, not an escape and a separator
  // (Dart's Uri would read them so).
  return Uri(
    scheme: 'file',
    host: authority,
    path: path.replaceAll('%', '%25').replaceAll(r'\', '%5C'),
  );
}

/// Upstream's `TerminalLinkResolver`: strips the line and column suffix and
/// the query, resolves `~` against [userHome] and relative paths against the
/// cwd, and asks [stat] whether something is there.
class TerminalFileLinkResolver implements TerminalLinkResolver {
  TerminalFileLinkResolver({
    OperatingSystem? os,
    String? userHome,
    TerminalLinkStat? stat,
  }) : os = os ?? platform.hostOperatingSystem,
       userHome = userHome ?? platform.hostUserHome,
       _stat = stat ?? platform.statPath;

  /// The path syntax of the links.
  final OperatingSystem os;

  /// Where `~` points; `~` links do not resolve without it.
  final String? userHome;

  final TerminalLinkStat _stat;
  final _LinkCache _cache = _LinkCache();

  @override
  Future<ResolvedTerminalLink?> resolve(String link, String cwd) async {
    // Check resolved link cache first
    final key = '$cwd\u0000$link';
    final cached = _cache.get(key);
    if (cached != null) {
      return cached.value;
    }

    if (link.startsWith('file://')) {
      final uri = Uri.tryParse(link);
      final path = uri == null ? null : fileUriToPath(uri, os);
      final result = path == null ? null : await _statLink(path);
      _cache.set(key, result);
      return result;
    }

    // Remove any line/col suffix
    var linkUrl = removeLinkSuffix(link);

    // Remove any query string
    linkUrl = removeLinkQueryString(linkUrl);

    // Exit early if the link is determines as not valid already
    if (linkUrl.isEmpty) {
      _cache.set(key, null);
      return null;
    }

    // Skip preprocessing if it looks like a special Windows -> WSL link
    if (os == OperatingSystem.windows &&
        RegExp(r'^(?:\/\/|\\\\)wsl(?:\$|\.localhost)(\/|\\)').hasMatch(link)) {
      // No-op, it's already the right format
    }
    // Handle all non-WSL links
    else {
      final preprocessedLink = _preprocessPath(linkUrl, cwd);
      if (preprocessedLink == null) {
        _cache.set(key, null);
        return null;
      }
      linkUrl = preprocessedLink;
    }

    final result = await _statLink(linkUrl);
    _cache.set(key, result);
    return result;
  }

  Future<ResolvedTerminalLink?> _statLink(String path) async {
    final isDirectory = await _stat(path);
    return isDirectory == null ? null : (path: path, isDirectory: isDirectory);
  }

  String? _preprocessPath(String link, String initialCwd) {
    final osPath = osPathContext(os);
    if (link[0] == '~') {
      // Resolve ~ -> userHome
      final userHome = this.userHome;
      if (userHome == null || userHome.isEmpty) {
        return null;
      }
      link = joinPath(osPath, userHome, link.substring(1));
    } else if (link[0] != '/' && link[0] != '~') {
      // Resolve workspace path . | .. | <relative_path> -> <path>/. |
      // <path>/.. | <path>/<relative_path>
      if (os == OperatingSystem.windows) {
        if (!RegExp('^$winDrivePrefix').hasMatch(link) &&
            !link.startsWith(r'\\?\')) {
          if (initialCwd.isEmpty) {
            // Abort if no workspace is open
            return null;
          }
          link = joinPath(osPath, initialCwd, link);
        } else {
          // Remove \\?\ from paths so that they share the same underlying
          // uri and don't open multiple tabs for the same file
          link = link.replaceFirst(RegExp(r'^\\\\\?\\'), '');
        }
      } else {
        if (initialCwd.isEmpty) {
          // Abort if no workspace is open
          return null;
        }
        link = joinPath(osPath, initialCwd, link);
      }
    }
    return osPath.normalize(link);
  }
}

/// How long to cache links for; the time restarts whenever a value is set.
const Duration _linkCacheTtl = Duration(milliseconds: 10000);

class _LinkCache {
  final Map<String, ResolvedTerminalLink?> _cache = {};
  final Stopwatch _clock = Stopwatch()..start();
  Duration _expires = Duration.zero;

  void set(String link, ResolvedTerminalLink? value) {
    _expire();
    // Reset cached link TTL on any set
    _expires = _clock.elapsed + _linkCacheTtl;
    _cache[link] = value;
  }

  /// The cached value in a record, so that a cached null is told apart from
  /// nothing cached.
  ({ResolvedTerminalLink? value})? get(String link) {
    _expire();
    if (!_cache.containsKey(link)) {
      return null;
    }
    return (value: _cache[link]);
  }

  void _expire() {
    if (_clock.elapsed >= _expires) {
      _cache.clear();
    }
  }
}
