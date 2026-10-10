/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/extensions/browser/extensionUrlHandler.ts
// (`ExtensionUrlHandler`: the trust prompt, buffering a URI while its
// extension activates on `onUri:<id>`, dropping buffered URIs after five
// minutes, installing an extension that is not there),
// src/vs/platform/url/common/urlService.ts (`AbstractURLService.open`,
// `NativeURLService.create`) and
// src/vs/workbench/services/url/electron-browser/urlService.ts (`create`
// adds the window's id, which routes a URI back to its window).
//
// Deviations: one service for the app, hosts (one a workspace) register
// with it; a URI goes to the host its `windowId` names, else the one whose
// extension handles it, else the last active one with the extension; the
// trusted extension list is upstream's product.json's (VSCodium's has
// none); an extension installed by the prompt but not loaded is reported,
// not reloaded for.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../l10n/l10n.dart';
import 'extension_descriptions.dart';
import 'json_state_store.dart';
import 'window_ports.dart';

/// A workspace's extension host as URI handling sees it.
abstract interface class ExtensionUrlHost {
  /// The window's id in URIs made for it (`windowId=`): the workspace id.
  String get windowId;

  /// The installed, enabled extension [id] of this host; null when none.
  Map<String, Object?>? extension(String id);

  Future<void> activateByEvent(String event);
}

/// A handler of all URIs (`IURLHandler`): true when it took [uri].
typedef ExtensionUriHandler = Future<bool> Function(VsUri uri);

final class _ExtensionHandler {
  _ExtensionHandler(this.host, this.displayName, this.handle);

  final ExtensionUrlHost host;
  final String displayName;
  final Future<void> Function(VsUri uri) handle;
}

/// Routes `baocode://<publisher.name>/…` URIs to the extensions' URI
/// handlers (`vscode.window.registerUriHandler`), activating an extension
/// for one when it has none yet.
final class ExtensionUrlService {
  ExtensionUrlService({
    this.scheme = 'baocode',
    this.dialogs,
    this.commands,
    this.trustStore,
    AppLocalizations Function()? l10n,
    DateTime Function()? now,
  }) : _l10n = l10n ?? (() => englishLocalizations),
       _now = now ?? DateTime.now;

  /// The app's URL scheme (product.json's `urlProtocol`).
  final String scheme;

  /// Asks before an extension opens a URI it did not make; null trusts all.
  final ExtensionDialogs? dialogs;

  /// Runs `workbench.extensions.installExtension` for a URI of an extension
  /// that is not installed.
  final ExtensionCommandExecutor? commands;

  /// Remembers the extensions the user trusts (`extensionUrlHandler.
  /// confirmedExtensions`).
  final JsonStateStore? trustStore;

  final AppLocalizations Function() _l10n;
  final DateTime Function() _now;

  /// The extensions trusted without asking (VS Code's product.json
  /// `trustedExtensionProtocolHandlers`).
  static const trustedExtensions = {
    'vscode.git',
    'vscode.github-authentication',
    'vscode.microsoft-authentication',
  };

  /// The marker of a request carrying a URI the system asked the app to
  /// open (see [handleOpenRequest]).
  static const requestMarker = '\u0000uri';

  static const _trustKey = 'extensionUrlHandler.confirmedExtensions';
  static const _bufferLife = Duration(minutes: 5);

  final List<ExtensionUrlHost> _hosts = [];
  final List<ExtensionUriHandler> _handlers = [];
  final Map<String, _ExtensionHandler> _extensionHandlers = {};
  final Map<String, List<({DateTime at, VsUri uri, ExtensionUrlHost host})>>
  _buffer = {};

  /// Adds a workspace's host; the last added or [activate]d is the one a
  /// URI goes to when nothing else decides.
  void addHost(ExtensionUrlHost host) {
    _hosts
      ..remove(host)
      ..add(host);
  }

  void removeHost(ExtensionUrlHost host) {
    _hosts.remove(host);
    _extensionHandlers.removeWhere((_, handler) => handler.host == host);
    for (final uris in _buffer.values) {
      uris.removeWhere((entry) => entry.host == host);
    }
  }

  /// [host]'s window became the active one.
  void activate(ExtensionUrlHost host) => addHost(host);

  /// Registers a handler of all URIs, asked before the extensions'
  /// (`IURLService.registerHandler`); call the result to remove it.
  void Function() registerHandler(ExtensionUriHandler handler) {
    _handlers.add(handler);
    return () => _handlers.remove(handler);
  }

  /// [extensionId]'s handler in [host] (`registerExtensionHandler`): the URIs
  /// that waited for it go to it now.
  void registerExtensionHandler(
    ExtensionUrlHost host,
    String extensionId,
    String displayName,
    Future<void> Function(VsUri uri) handle,
  ) {
    final key = extensionKey(extensionId);
    final handler = _ExtensionHandler(host, displayName, handle);
    _extensionHandlers[key] = handler;
    final waiting = _buffer.remove(key) ?? const [];
    final now = _now();
    for (final entry in waiting) {
      if (now.difference(entry.at) < _bufferLife) {
        unawaited(handle(entry.uri).catchError((Object _) {}));
      }
    }
  }

  void unregisterExtensionHandler(ExtensionUrlHost host, String extensionId) {
    final key = extensionKey(extensionId);
    if (_extensionHandlers[key]?.host == host) _extensionHandlers.remove(key);
  }

  /// Whether [extensionId] has a handler.
  bool hasExtensionHandler(String extensionId) =>
      _extensionHandlers.containsKey(extensionKey(extensionId));

  /// A URI of the app for [uri]'s parts (`IURLService.create`): its scheme
  /// the app's, `/` before a path with an authority, and the window's id
  /// added to its query.
  VsUri create(VsUri uri, {String? windowId}) {
    var path = uri.path;
    if (uri.authority.isNotEmpty && path.isNotEmpty && !path.startsWith('/')) {
      path = '/$path';
    }
    var query = uri.query;
    if (windowId != null) {
      // `encodeURIComponent`: a space is `%20`, not Dart's query `+`.
      final param = 'windowId=${Uri.encodeComponent(windowId)}';
      query = query.isEmpty ? param : '$query&$param';
    }
    return VsUri(
      scheme,
      authority: uri.authority,
      path: path,
      query: query,
      fragment: uri.fragment,
    );
  }

  /// Takes a request of the system's (see open_requests.dart): [requestMarker]
  /// then the URI. False when [request] is something else.
  bool handleOpenRequest(List<String> request) {
    if (request.length < 2 || request.first != requestMarker) return false;
    for (final value in request.skip(1)) {
      final uri = VsUri.parse(value);
      if (uri.scheme == scheme) unawaited(open(uri));
    }
    return true;
  }

  /// Opens a URI of the app's scheme: true when something took it
  /// (`IURLService.open`).
  Future<bool> open(VsUri uri) async {
    if (uri.scheme != scheme) return false;
    for (final handler in [..._handlers]) {
      if (await handler(uri)) return true;
    }
    return _handleExtensionUri(uri);
  }

  /// `ExtensionUrlHandler.handleURL`.
  Future<bool> _handleExtensionUri(VsUri uri) async {
    final extensionId = uri.authority;
    if (!_isExtensionId(extensionId)) return false;
    final key = extensionKey(extensionId);
    final handler = _extensionHandlers[key];
    final host = _hostFor(uri, extensionId, handler);
    final description = host?.extension(extensionId);
    if (handler == null && (host == null || description == null)) {
      await _handleUnhandled(uri, extensionId);
      return true;
    }
    final displayName =
        handler?.displayName ?? extensionDisplayName(description!);
    if (!await _trusted(uri, key, displayName)) return true;
    // The handler may have come while the user was asked.
    final now = _extensionHandlers[key];
    if (now != null) {
      await now.handle(uri);
      return true;
    }
    final target = host!;
    _gcBuffer();
    (_buffer[key] ??= []).add((at: _now(), uri: uri, host: target));
    await target.activateByEvent('onUri:$key');
    return true;
  }

  ExtensionUrlHost? _hostFor(
    VsUri uri,
    String extensionId,
    _ExtensionHandler? handler,
  ) {
    final windowId = Uri.splitQueryString(uri.query)['windowId'];
    if (windowId != null) {
      for (final host in _hosts) {
        if (host.windowId == windowId) return host;
      }
    }
    if (handler != null) return handler.host;
    for (final host in _hosts.reversed) {
      if (host.extension(extensionId) != null) return host;
    }
    return _hosts.lastOrNull;
  }

  Future<bool> _trusted(VsUri uri, String key, String displayName) async {
    if (trustedExtensions.contains(key)) return true;
    final store = trustStore;
    await store?.load();
    final trusted = switch (store?.getJson(_trustKey)) {
      final List<Object?> ids => ids.contains(key),
      _ => false,
    };
    if (trusted) return true;
    final dialogs = this.dialogs;
    if (dialogs == null) return true;
    final l10n = _l10n();
    var label = uri.toString();
    if (label.length > 40) {
      label =
          '${label.substring(0, 30)}...${label.substring(label.length - 5)}';
    }
    final answer = await dialogs.prompt(
      severity: ExtensionSeverity.info,
      message: l10n.windowUrlConfirm(displayName),
      detail: label,
      buttons: [l10n.windowUrlOpen],
      cancel: l10n.commonCancel,
      checkbox: l10n.windowUrlRemember,
    );
    if (answer.button != 0) return false;
    if (answer.checked && store != null) {
      final ids = switch (store.getJson(_trustKey)) {
        final List<Object?> list => [...list.whereType<String>()],
        _ => <String>[],
      };
      store.setJson(_trustKey, [...ids, key]);
    }
    return true;
  }

  Future<void> _handleUnhandled(VsUri uri, String extensionId) async {
    final commands = this.commands;
    if (commands == null) return;
    try {
      await commands.executeCommand('workbench.extensions.installExtension', [
        extensionId,
        {
          'justification': {
            'reason': '${_l10n().windowUrlInstallDetail}\n${uri.toString()}',
            'action': _l10n().windowUrlOpenUri,
          },
          'enable': true,
        },
      ]);
    } on Object {
      return;
    }
    for (final host in _hosts.reversed) {
      if (host.extension(extensionId) != null) {
        await _handleExtensionUri(uri);
        return;
      }
    }
  }

  void _gcBuffer() {
    final now = _now();
    _buffer.removeWhere((_, uris) {
      uris.removeWhere((entry) => now.difference(entry.at) >= _bufferLife);
      return uris.isEmpty;
    });
  }

  static final _extensionIdPattern = RegExp(
    r'^([a-z0-9A-Z][a-z0-9-A-Z]*)\.([a-z0-9A-Z][a-z0-9-A-Z]*)$',
  );

  /// `isExtensionId`: `publisher.name`.
  static bool _isExtensionId(String value) =>
      _extensionIdPattern.hasMatch(value);
}
