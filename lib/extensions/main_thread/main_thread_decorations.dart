/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadDecorations.ts.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../decorations/file_decorations_service.dart';
import 'main_thread_context.dart';

/// `DecorationRequestsQueue`: a provider's requests of one turn of the
/// event loop, sent together.
final class _DecorationRequestsQueue {
  _DecorationRequestsQueue(this._proxy, this._handle);

  final ExtHostDecorationsProxy _proxy;
  final int _handle;
  int _idPool = 0;
  Map<int, Map<String, Object?>> _requests = {};
  Map<int, Completer<List<Object?>?>> _resolver = {};
  Timer? _timer;

  Future<List<Object?>?> enqueue(VsUri uri) {
    final id = ++_idPool;
    final completer = Completer<List<Object?>?>();
    _requests[id] = {'id': id, 'uri': uri};
    _resolver[id] = completer;
    _processQueue();
    return completer.future;
  }

  void _processQueue() {
    if (_timer != null) return;
    _timer = Timer(Duration.zero, () {
      final requests = _requests;
      final resolver = _resolver;
      unawaited(
        _proxy.$provideDecorations(_handle, [...requests.values]).then(
          (data) {
            for (final MapEntry(:key, :value) in resolver.entries) {
              value.complete(data['$key']);
            }
          },
          onError: (Object error) {
            for (final completer in resolver.values) {
              completer.completeError(error);
            }
          },
        ),
      );
      _requests = {};
      _resolver = {};
      _timer = null;
    });
  }

  void dispose() => _timer?.cancel();
}

final class MainThreadDecorations extends MainThreadDecorationsUnsupported {
  MainThreadDecorations(this._service, this._proxy, MainThreadContext context) {
    context.onDispose(_dispose);
  }

  final FileDecorationsService _service;
  final ExtHostDecorationsProxy _proxy;
  final Map<
    int,
    ({
      void Function(List<VsUri>? uris) changed,
      void Function() dispose,
      _DecorationRequestsQueue queue,
    })
  >
  _providers = {};

  static RpcActor customer(MainThreadContext context) =>
      MainThreadDecorationsActor(
        MainThreadDecorations(
          context.service<FileDecorationsService>(),
          ExtHostDecorationsProxy(context.rpc),
          context,
        ),
      );

  @override
  void $registerDecorationProvider(num handle, String label) {
    final queue = _DecorationRequestsQueue(_proxy, handle.toInt());
    final registration = _service.register(
      FileDecorationsProvider(
        label: label,
        provide: (uri) async {
          final data = await queue.enqueue(uri);
          if (data == null) return null;
          // `[bubble, tooltip, letter, themeColor]`.
          Object? at(int i) => i < data.length ? data[i] : null;
          return FileDecorationData(
            weight: 10,
            bubble: at(0) == true,
            tooltip: at(1) as String?,
            letter: at(2) as String?,
            colorId: switch (at(3)) {
              {'id': final String id} => id,
              _ => null,
            },
          );
        },
      ),
    );
    _providers[handle.toInt()] = (
      changed: registration.changed,
      dispose: registration.dispose,
      queue: queue,
    );
  }

  @override
  void $onDidChange(num handle, List<VsUri>? resources) =>
      _providers[handle.toInt()]?.changed(resources);

  @override
  void $unregisterDecorationProvider(num handle) {
    final provider = _providers.remove(handle.toInt());
    provider?.queue.dispose();
    provider?.dispose();
  }

  void _dispose() {
    for (final provider in _providers.values) {
      provider.queue.dispose();
      provider.dispose();
    }
    _providers.clear();
  }
}
