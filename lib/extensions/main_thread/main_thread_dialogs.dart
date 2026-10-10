/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDialogs.ts, with
// `IFileDialogService.defaultFilePath` (the workspace's first folder).
//
// Deviations: the app's native pickers (window_controls.dart) take no
// filters, title or button label on every platform; they get them, and
// show what they can. Only `file:` default URIs are used.

import 'dart:io';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:path/path.dart' as p;

import '../extension_host_service_io.dart';
import '../window/window_ports.dart';
import 'main_thread_context.dart';

final class MainThreadDialogs extends MainThreadDialogsUnsupported {
  MainThreadDialogs(this._pickers, {this.defaultDirectory});

  final ExtensionFilePickers _pickers;

  /// Where a dialog without a default URI starts: the workspace's folder.
  final String? defaultDirectory;

  static RpcActor customer(MainThreadContext context) {
    final folders = context
        .maybeService<ExtensionHostService>()
        ?.workspace
        .folders;
    return MainThreadDialogsActor(
      MainThreadDialogs(
        context.service<ExtensionFilePickers>(),
        defaultDirectory: folders == null || folders.isEmpty
            ? null
            : folders.first.uri.scheme == 'file'
            ? folders.first.uri.fsPath()
            : null,
      ),
    );
  }

  static Map<String, List<String>> _filters(Object? filters) => {
    if (filters is Map)
      for (final MapEntry(:key, :value) in filters.entries)
        '$key': [
          for (final extension in value as List? ?? const []) '$extension',
        ],
  };

  static String? _path(Object? uri) {
    final revived = VsUri.tryRevive(uri);
    if (revived == null || revived.scheme != 'file') return null;
    return revived.fsPath(windows: Platform.isWindows);
  }

  @override
  Future<List<VsUri>?> $showOpenDialog(Map<String, Object?>? options) async {
    final canSelectFolders = options?['canSelectFolders'] == true;
    final canSelectFiles =
        options?['canSelectFiles'] == true || !canSelectFolders;
    var directory = _path(options?['defaultUri']);
    if (directory != null &&
        !await Directory(directory).exists() &&
        await File(directory).exists()) {
      directory = p.dirname(directory);
    }
    final paths = await _pickers.pickOpen(
      files: canSelectFiles,
      folders: canSelectFolders,
      many: options?['canSelectMany'] == true,
      directory: directory ?? defaultDirectory,
      title: _label(options?['title']),
      openLabel: _label(options?['openLabel']),
      filters: _filters(options?['filters']),
    );
    if (paths == null || paths.isEmpty) return null;
    return [
      for (final path in paths) VsUri.file(path, windows: Platform.isWindows),
    ];
  }

  @override
  Future<VsUri?> $showSaveDialog(Map<String, Object?>? options) async {
    final defaultPath = _path(options?['defaultUri']);
    String? directory;
    String? name;
    if (defaultPath != null) {
      if (await Directory(defaultPath).exists()) {
        directory = defaultPath;
      } else {
        directory = p.dirname(defaultPath);
        name = p.basename(defaultPath);
      }
    }
    final path = await _pickers.pickSave(
      directory: directory ?? defaultDirectory,
      name: name,
      title: _label(options?['title']),
      saveLabel: _label(options?['saveLabel']),
      filters: _filters(options?['filters']),
    );
    return path == null ? null : VsUri.file(path, windows: Platform.isWindows);
  }

  /// `options.x || undefined`.
  static String? _label(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
