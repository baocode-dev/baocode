/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadOutputService.ts.
//
// Deviations: the channels, the id pool and the panel are
// ExtensionOutputService's (one per workspace); `workbench.view.showQuietly`
// (a status bar item instead of the panel) is not read.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

import '../window/output/extension_output_service.dart';
import 'main_thread_context.dart';

final class MainThreadOutputService extends MainThreadOutputServiceUnsupported {
  /// Tells the extension host which channel is visible through [rpc] now
  /// and as it changes.
  MainThreadOutputService(this._output, RpcProtocol rpc) {
    final proxy = ExtHostOutputServiceProxy(rpc);
    _stopVisible = _output.addVisibleChannelListener(
      (id) => unawaited(
        proxy.$setVisibleChannel(id).catchError((Object _) {}),
      ),
    );
  }

  final ExtensionOutputService _output;
  late final VoidCallback _stopVisible;

  /// The channels this session registered: disposed with it.
  final _registered = <String>{};

  static RpcActor customer(MainThreadContext context) {
    final service = MainThreadOutputService(
      context.service<ExtensionOutputService>(),
      context.rpc,
    );
    context.onDispose(service.dispose);
    return MainThreadOutputServiceActor(service);
  }

  @override
  Future<String> $register(
    String label,
    VsUri file,
    String? languageId,
    String extensionId,
  ) async {
    final id = _output.registerExtensionChannel(
      label,
      file,
      languageId,
      extensionId,
    );
    _registered.add(id);
    return id;
  }

  @override
  void $update(String channelId, int mode, num? till) {
    final updateMode = OutputChannelUpdateMode.fromWire(mode);
    if (updateMode == null) return;
    _output.updateChannel(channelId, updateMode, till?.toInt());
  }

  @override
  void $reveal(String channelId, bool preserveFocus) =>
      _output.showChannel(channelId, preserveFocus: preserveFocus);

  @override
  void $close(String channelId) => _output.closeChannel(channelId);

  @override
  void $dispose(String channelId) {
    _registered.remove(channelId);
    _output.disposeChannel(channelId);
  }

  void dispose() {
    _stopVisible();
    for (final id in _registered) {
      _output.disposeChannel(id);
    }
    _registered.clear();
  }
}
