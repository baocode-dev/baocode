/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The workspace's own watches: every folder, recursively, less
// `files.watcherExclude`, and the extra paths of `files.watcherInclude`.
// Their changes are what `createFileSystemWatcher` with a string glob
// sees (the extension host watches nothing itself for those).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/files/browser/workspaceWatcher.ts
// (`WorkspaceWatcher`: `refresh`, `watchWorkspace`, the excludes of
// `files.watcherExclude` set to true, `files.watcherInclude`).
//
// Deviations: no notification when watching fails (Dart's watchers stop
// quietly, and bao_remote reports Linux's watch limit itself).

import 'package:bao_exthost/bao_exthost.dart';

import '../configuration/configuration_service.dart';
import '../workspace/workspace_context.dart';
import 'file_service.dart';
import 'file_types.dart';

/// `files.watcherExclude`'s default.
const defaultWatcherExclude = <String, Object?>{
  '.git/objects/**': true,
  '.git/subtree-cache/**': true,
  '.hg/store/**': true,
  '*/.git/objects/**': true,
  '*/.git/subtree-cache/**': true,
  '*/.hg/store/**': true,
};

final class WorkspaceFileWatcher {
  WorkspaceFileWatcher({
    required this.files,
    required this.workspace,
    this.configuration,
  }) {
    workspace.addListener(refresh);
    _configurationChanges = configuration?.changes.listen((event) {
      final keys = (event.change['keys'] as List?) ?? const [];
      if (keys.any((k) => '$k'.startsWith('files.watcher'))) refresh();
    }).cancel;
    refresh();
  }

  final FileService files;
  final WorkspaceContextService workspace;
  final ConfigurationService? configuration;

  final _watches = <void Function()>[];
  Future<void> Function()? _configurationChanges;
  bool _disposed = false;

  /// The folders and options watched now.
  List<(VsUri, WatchOptions)> get watched => List.unmodifiable(_requests);
  final _requests = <(VsUri, WatchOptions)>[];

  /// `refresh`: watches the folders as they and the settings are now.
  void refresh() {
    if (_disposed) return;
    for (final stop in _watches) {
      stop();
    }
    _watches.clear();
    _requests.clear();
    for (final folder in workspace.workspaceFolders) {
      final excludes = <String>[];
      final config = configuration?.getValue(
            'files.watcherExclude',
            resource: folder.uri,
          ) ??
          defaultWatcherExclude;
      if (config is Map) {
        for (final MapEntry(:key, :value) in config.entries) {
          if ('$key'.isNotEmpty && value == true) excludes.add('$key');
        }
      }
      _watch(folder.uri, WatchOptions(recursive: true, excludes: excludes));
      final includes = configuration?.getValue(
        'files.watcherInclude',
        resource: folder.uri,
      );
      if (includes is List) {
        for (final include in includes.whereType<String>()) {
          if (include.trim().isEmpty) continue;
          final uri = include.startsWith('/')
              ? folder.uri.replace(path: include)
              : folder.uri.joinPath([include]);
          _watch(uri, WatchOptions(recursive: true, excludes: excludes));
        }
      }
    }
  }

  void _watch(VsUri uri, WatchOptions options) {
    _requests.add((uri, options));
    _watches.add(files.watch(uri, options));
  }

  void dispose() {
    _disposed = true;
    workspace.removeListener(refresh);
    _configurationChanges?.call();
    for (final stop in _watches) {
      stop();
    }
    _watches.clear();
  }
}
