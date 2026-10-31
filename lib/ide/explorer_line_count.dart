/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'file_service.dart';
import 'git/git_model.dart';

/// Manages and caches line count badges for files in the Explorer tree,
/// displaying compact counts like `45`, `1h`..`9h`, `1k`..`9k` alongside Git status.
class IdeExplorerLineCount extends ChangeNotifier {
  IdeExplorerLineCount({
    required this.files,
    p.Context? paths,
    this.enabled = true,
    this.maxFileSize = 2 * 1024 * 1024,
    this.minLineDisplay = 0,
    Set<String>? allowedExtensions,
    Set<String>? ignoredFolders,
  }) : paths = paths ?? p.context,
       allowedExtensions = allowedExtensions ?? defaultAllowedExtensions,
       ignoredFolders = ignoredFolders ?? defaultIgnoredFolders;

  static const settingEnabled = 'explorerLineCount.enabled';
  static const settingMaxFileSize = 'explorerLineCount.maxFileSize';
  static const settingMinLineDisplay = 'explorerLineCount.minLineDisplay';

  final IdeFileService files;
  final p.Context paths;

  bool enabled;
  int maxFileSize;
  int minLineDisplay;
  Set<String> allowedExtensions;
  Set<String> ignoredFolders;

  bool _disposed = false;
  bool _notifyScheduled = false;

  /// Cache: path -> line count (-1 if exceeded maxFileSize, null if failed to read).
  final Map<String, int?> _cache = {};
  final Set<String> _pending = {};

  static const defaultAllowedExtensions = {
    '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs', '.vue', '.svelte', '.astro',
    '.dart', '.py', '.java', '.kt', '.cs', '.go', '.rs', '.cpp', '.hpp', '.c', '.h',
    '.php', '.rb', '.swift', '.sql', '.graphql', '.gql',
    '.json', '.yaml', '.yml', '.toml', '.xml', '.html', '.css', '.scss', '.sass', '.less',
    '.md', '.sh', '.bat', '.ps1', '.env',
  };

  static const defaultIgnoredFolders = {
    'node_modules', '.git', 'dist', 'build',
    '.dart_tool', '.idea', '.vscode',
  };

  /// Decides if [path] should be skipped based on extension or folder path.
  bool shouldIgnore(String path) {
    if (!enabled) return true;

    // Normalizing slashes ensures safe matching across Windows and POSIX paths.
    final normalized = path.replaceAll(r'\', '/');
    final ext = p.posix.extension(normalized).toLowerCase();
    if (!allowedExtensions.contains(ext)) return true;

    final parts = normalized.split('/');
    for (var i = 0; i < parts.length - 1; i++) {
      if (ignoredFolders.contains(parts[i])) {
        return true;
      }
    }
    return false;
  }

  /// Format badge representation for [lines]:
  /// - lines >= 1000: Displays with 1 decimal place if not a whole thousand (e.g. 1.3k, 1.4k, 1.5k, 2k).
  /// - lines >= 100: Math.floor(lines / 100) + 'h' (e.g. 1h..9h).
  /// - otherwise: String(lines)
  static String formatBadge(int lines) {
    if (lines >= 1000) {
      final k = lines / 1000.0;
      if (k >= 100) return '${lines ~/ 1000}k';
      final formatted = k.toStringAsFixed(1);
      final trimmed = formatted.endsWith('.0')
          ? formatted.substring(0, formatted.length - 2)
          : formatted;
      return '${trimmed}k';
    }
    if (lines >= 100) return '${lines ~/ 100}h';
    return '$lines';
  }

  /// Count number of lines (newline bytes `0x0A`) in [bytes].
  static int countLines(Uint8List bytes) {
    if (bytes.isEmpty) return 0;
    var lines = 1;
    final length = bytes.length;
    for (var i = 0; i < length; i++) {
      if (bytes[i] == 0x0A) {
        lines++;
      }
    }
    return lines;
  }

  /// Returns [IdeGitDecoration] for [path], or null if ignored/not loaded.
  /// If not yet cached, schedules an asynchronous read.
  IdeGitDecoration? decorationFor(String path) {
    if (shouldIgnore(path)) return null;

    if (_cache.containsKey(path)) {
      final cached = _cache[path];
      if (cached == null) return null;
      if (cached == -1) {
        return IdeGitDecoration(
          tooltip: 'File limit exceeded (> ${(maxFileSize / (1024 * 1024)).round()}MB)',
          colorId: null,
        );
      }
      if (cached < minLineDisplay) {
        return IdeGitDecoration(
          tooltip: cached == 1 ? '1 line' : '$cached lines',
          colorId: null,
        );
      }
      return IdeGitDecoration(
        letter: formatBadge(cached),
        tooltip: cached == 1 ? '1 line' : '$cached lines',
        colorId: null,
      );
    }

    if (!_pending.contains(path)) {
      _pending.add(path);
      _fetchLineCount(path);
    }

    return null;
  }

  Future<void> _fetchLineCount(String path) async {
    try {
      final size = await byteSizeThrough(files, path);
      if (_disposed) return;
      if (size != null && size > maxFileSize) {
        _cache[path] = -1;
        _pending.remove(path);
        _scheduleNotify();
        return;
      }

      Uint8List bytes;
      try {
        bytes = await readBytesThrough(files, path);
      } catch (_) {
        bytes = utf8.encode(await files.read(path, force: true));
      }

      if (_disposed) return;
      if (bytes.length > maxFileSize) {
        _cache[path] = -1;
      } else {
        _cache[path] = countLines(bytes);
      }
    } catch (_) {
      if (_disposed) return;
      _cache[path] = null;
    } finally {
      _pending.remove(path);
      _scheduleNotify();
    }
  }

  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) {
        notifyListeners();
      }
    });
  }

  void invalidate(String path) {
    _cache.remove(path);
    _pending.remove(path);
    _scheduleNotify();
  }

  void update(String path, int lines) {
    _cache[path] = lines;
    _pending.remove(path);
    _scheduleNotify();
  }

  void clear() {
    _cache.clear();
    _pending.clear();
    _scheduleNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    _pending.clear();
    super.dispose();
  }
}
