/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadUrls.ts.
//
// Deviations: `$createAppUri` adds the workspace's id as `windowId` (the
// desktop's URL service adds the window's), which routes the URI back to
// this workspace's extension host.

import 'package:bao_exthost/bao_exthost.dart';

import '../extension_host_service_io.dart';
import '../window/extension_descriptions.dart';
import '../window/url_service.dart';
import 'main_thread_context.dart';

/// A workspace's [ExtensionHostService] as the URL service sees it.
final class ExtensionHostUrlHost implements ExtensionUrlHost {
  ExtensionHostUrlHost._(this._host);

  /// The one of [host] (the same for every session).
  factory ExtensionHostUrlHost.of(ExtensionHostService host) =>
      _hosts[host] ??= ExtensionHostUrlHost._(host);

  static final _hosts = Expando<ExtensionHostUrlHost>();

  final ExtensionHostService _host;

  @override
  String get windowId => _host.workspace.id;

  @override
  Map<String, Object?>? extension(String id) =>
      findExtension(_host.extensions.value, id);

  @override
  Future<void> activateByEvent(String event) => _host.activateByEvent(event);
}

final class MainThreadUrls extends MainThreadUrlsUnsupported {
  MainThreadUrls(this._urls, this._host, this._proxy);

  final ExtensionUrlService _urls;
  final ExtensionUrlHost _host;
  final ExtHostUrlsProxy _proxy;
  final Map<num, String> _handlers = {};

  static RpcActor customer(MainThreadContext context) {
    final urls = context.service<ExtensionUrlService>();
    final host = ExtensionHostUrlHost.of(context.service<ExtensionHostService>());
    urls.addHost(host);
    final actor = MainThreadUrls(urls, host, ExtHostUrlsProxy(context.rpc));
    context.onDispose(actor.dispose);
    return MainThreadUrlsActor(actor);
  }

  @override
  Future<void> $registerUriHandler(
    num handle,
    Map<String, Object?> extensionId,
    String extensionDisplayName,
  ) async {
    final id = extensionIdFromWire(extensionId);
    _handlers[handle] = id;
    _urls.registerExtensionHandler(
      _host,
      id,
      extensionDisplayName,
      (uri) => _proxy.$handleExternalUri(handle, uri),
    );
  }

  @override
  Future<void> $unregisterUriHandler(num handle) async {
    final id = _handlers.remove(handle);
    if (id != null) _urls.unregisterExtensionHandler(_host, id);
  }

  @override
  Future<VsUri> $createAppUri(VsUri uri) async =>
      _urls.create(uri, windowId: _host.windowId);

  void dispose() {
    for (final id in _handlers.values) {
      _urls.unregisterExtensionHandler(_host, id);
    }
    _handlers.clear();
  }
}
