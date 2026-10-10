/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadFileSystem.ts
// (`MainThreadFileSystem`, `RemoteFileSystemProvider`).
//
// Deviations:
// - An extension's provider is used with whole buffers only: no
//   open/read/write/close transfers.
// - `$ensureActivation` and a scheme the app has no provider for activate
//   `onFileSystem:<scheme>` through the session's ExtensionHostService
//   (or an [ExtensionActivator] given).

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:bao_exthost/bao_exthost.dart';

import '../extension_host_service_io.dart';
import '../files/file_service.dart';
import '../files/file_types.dart';
import 'main_thread_context.dart';

/// Activates extensions by activation event (ExtensionHostService's
/// `activateByEvent`), for actors run without a service.
final class ExtensionActivator {
  const ExtensionActivator(this.activateByEvent);

  final Future<void> Function(String activationEvent) activateByEvent;

  /// [context]'s activator: an [ExtensionActivator] given, else its
  /// ExtensionHostService's.
  static Future<void> Function(String)? of(MainThreadContext context) =>
      context.maybeService<ExtensionActivator>()?.activateByEvent ??
      context.maybeService<ExtensionHostService>()?.activateByEvent;
}

final class MainThreadFileSystem extends MainThreadFileSystemUnsupported {
  MainThreadFileSystem({
    required RpcProtocol rpc,
    required this.files,
    Future<void> Function(String activationEvent)? activate,
  }) : _proxy = ExtHostFileSystemProxy(rpc) {
    final info = ExtHostFileSystemInfoProxy(rpc);
    for (final entry in files.listCapabilities()) {
      _send(info.$acceptProviderInfos(_dummy(entry.scheme), entry.capabilities));
    }
    _registrations = files.onDidChangeRegistrations.listen((e) {
      _send(info.$acceptProviderInfos(_dummy(e.scheme), e.capabilities));
    });
    if (activate != null) {
      _removeActivator = files.addActivator(
        (scheme) => activate('onFileSystem:$scheme'),
      );
    }
  }

  static RpcActor customer(MainThreadContext c) {
    final actor = MainThreadFileSystem(
      rpc: c.rpc,
      files: c.service<FileService>(),
      activate: ExtensionActivator.of(c),
    );
    c.onDispose(actor.dispose);
    return MainThreadFileSystemActor(actor);
  }

  final ExtHostFileSystemProxy _proxy;
  final FileService files;
  final _providers = <int, ExtensionFileSystemProvider>{};
  late final StreamSubscription<void> _registrations;
  void Function()? _removeActivator;

  static VsUri _dummy(String scheme) => VsUri(scheme, path: '/dummy');

  static void _send(Future<void> call) =>
      unawaited(call.catchError((Object _) {}));

  void dispose() {
    unawaited(_registrations.cancel());
    _removeActivator?.call();
    for (final p in _providers.values) {
      p.dispose();
    }
    _providers.clear();
  }

  @override
  Future<void> $registerFileSystemProvider(
    num handle,
    String scheme,
    int capabilities,
    Map<String, Object?>? readonlyMessage,
  ) async {
    final h = handle.toInt();
    _providers.remove(h)?.dispose();
    _providers[h] = ExtensionFileSystemProvider(
      files,
      scheme,
      capabilities,
      h,
      _proxy,
      readonlyMessage: readonlyMessage,
    );
  }

  @override
  void $unregisterProvider(num handle) =>
      _providers.remove(handle.toInt())?.dispose();

  @override
  void $onFileSystemChange(num handle, List<Map<String, Object?>> resource) {
    final provider = _providers[handle.toInt()];
    if (provider == null) throw StateError('Unknown file provider');
    provider.fireChanges([for (final dto in resource) FileChange.fromJson(dto)]);
  }

  // --- consumer fs, vscode.workspace.fs

  @override
  Future<Map<String, Object?>> $stat(VsUri resource) async {
    try {
      final stat = await files.stat(resource);
      return {
        'ctime': stat.ctime,
        'mtime': stat.mtime,
        'size': stat.size,
        if (stat.readonly) 'permissions': FilePermission.readonly,
        'type': _asFileType(stat),
      };
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<List<List<Object?>>> $readdir(VsUri resource) async {
    try {
      final stat = await files.resolve(resource);
      if (!stat.isDirectory) {
        throw RpcRemoteError(
          name: FileSystemProviderErrorCode.fileNotADirectory.value,
          message: stat.name,
        );
      }
      return [
        for (final child in stat.children ?? const <ResolvedFileStat>[])
          [child.name, _asFileType(child.stat)],
      ];
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  static int _asFileType(FileStat stat) {
    var type = 0;
    if (stat.isFile) {
      type += FileType.file;
    } else if (stat.isDirectory) {
      type += FileType.directory;
    }
    if (stat.isSymbolicLink) type += FileType.symbolicLink;
    return type;
  }

  @override
  Future<RpcBuffer> $readFile(VsUri resource) async {
    try {
      return RpcBuffer(await files.readFile(resource));
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $writeFile(VsUri resource, RpcBuffer content) async {
    try {
      await files.writeFile(resource, content.bytes);
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $rename(
    VsUri resource,
    VsUri target,
    Map<String, Object?> opts,
  ) async {
    try {
      await files.move(resource, target, overwrite: opts['overwrite'] == true);
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $copy(VsUri resource, VsUri target, Map<String, Object?> opts) async {
    try {
      await files.copy(resource, target, overwrite: opts['overwrite'] == true);
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $mkdir(VsUri resource) async {
    try {
      await files.createFolder(resource);
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $delete(VsUri resource, Map<String, Object?> opts) async {
    try {
      await files.delete(
        resource,
        recursive: opts['recursive'] == true,
        useTrash: opts['useTrash'] == true,
      );
    } on Object catch (e) {
      throw handleError(e);
    }
  }

  @override
  Future<void> $ensureActivation(String scheme) =>
      files.activateProvider(scheme);

  /// `_handleError`: the error as the extension host's `workspace.fs`
  /// reads it, its name a `FileSystemProviderErrorCode`.
  static Object handleError(Object error) {
    if (error is RpcRemoteError && !error.name.endsWith('(FileSystemError)')) {
      return error;
    }
    if (error is FileOperationException) {
      final name = switch (error.result) {
        FileOperationResult.fileNotFound =>
          FileSystemProviderErrorCode.fileNotFound.value,
        FileOperationResult.fileIsDirectory =>
          FileSystemProviderErrorCode.fileIsADirectory.value,
        FileOperationResult.filePermissionDenied =>
          FileSystemProviderErrorCode.noPermissions.value,
        FileOperationResult.fileMoveConflict =>
          FileSystemProviderErrorCode.fileExists.value,
        _ => 'Error',
      };
      return RpcRemoteError(name: name, message: error.message);
    }
    final code = toFileSystemProviderErrorCode(error);
    final message = switch (error) {
      FileSystemProviderException(:final message) => message,
      RpcRemoteError(:final message) => message,
      _ => '$error',
    };
    return RpcRemoteError(
      name: code == FileSystemProviderErrorCode.unknown ? 'Error' : code.value,
      message: message,
    );
  }
}

/// An extension's file system provider (`RemoteFileSystemProvider`),
/// registered with the [FileService] while it lives.
final class ExtensionFileSystemProvider extends FileSystemProvider {
  ExtensionFileSystemProvider(
    FileService files,
    this.scheme,
    this.capabilities,
    this.handle,
    this._proxy, {
    this.readonlyMessage,
  }) {
    _unregister = files.registerProvider(scheme, this);
  }

  final String scheme;
  @override
  final int capabilities;
  final int handle;
  final Map<String, Object?>? readonlyMessage;
  final ExtHostFileSystemProxy _proxy;
  late final void Function() _unregister;
  final _changes = StreamController<List<FileChange>>.broadcast();
  static final _random = Random();

  @override
  Stream<List<FileChange>> get onDidChangeFile => _changes.stream;

  void fireChanges(List<FileChange> changes) {
    if (!_changes.isClosed) _changes.add(changes);
  }

  void dispose() {
    _unregister();
    unawaited(_changes.close());
  }

  @override
  void Function() watch(
    VsUri resource,
    WatchOptions options, {
    void Function(List<FileChange> changes)? correlated,
  }) {
    final session = _random.nextDouble();
    unawaited(
      _proxy
          .$watch(handle, session, resource, {
            'recursive': options.recursive,
            'excludes': options.excludes,
            if (options.includes case final includes?)
              'includes': [
                for (final i in includes)
                  switch (i) {
                    (base: final String base, pattern: final String pattern) => {
                      'base': base,
                      'pattern': pattern,
                    },
                    _ => '$i',
                  },
              ],
            'filter': ?options.filter,
          })
          .catchError((Object _) {}),
    );
    return () =>
        unawaited(_proxy.$unwatch(handle, session).catchError((Object _) {}));
  }

  @override
  Future<FileStat> stat(VsUri resource) async =>
      FileStat.fromJson(await _proxy.$stat(handle, resource));

  @override
  Future<List<(String, int)>> readdir(VsUri resource) async => [
    for (final entry in await _proxy.$readdir(handle, resource))
      ('${entry[0]}', (entry[1] as num?)?.toInt() ?? FileType.unknown),
  ];

  @override
  Future<Uint8List> readFile(VsUri resource) async =>
      (await _proxy.$readFile(handle, resource)).bytes;

  @override
  Future<void> writeFile(
    VsUri resource,
    Uint8List content, {
    bool create = true,
    bool overwrite = true,
  }) => _proxy.$writeFile(handle, resource, RpcBuffer(content), {
    'create': create,
    'overwrite': overwrite,
    'unlock': false,
    'atomic': false,
  });

  @override
  Future<void> delete(
    VsUri resource, {
    bool recursive = false,
    bool useTrash = false,
  }) => _proxy.$delete(handle, resource, {
    'recursive': recursive,
    'useTrash': useTrash,
    'atomic': false,
  });

  @override
  Future<void> mkdir(VsUri resource) => _proxy.$mkdir(handle, resource);

  @override
  Future<void> rename(VsUri from, VsUri to, {bool overwrite = false}) =>
      _proxy.$rename(handle, from, to, {'overwrite': overwrite});

  @override
  Future<void> copy(VsUri from, VsUri to, {bool overwrite = false}) =>
      _proxy.$copy(handle, from, to, {'overwrite': overwrite});
}
