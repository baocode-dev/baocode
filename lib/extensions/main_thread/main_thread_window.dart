/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadWindow.ts, with what
// `IOpenerService.open(…, {openExternal: true})` does with what extensions
// open (src/vs/editor/browser/services/openerService.ts: the app's own
// scheme goes to the URL service, `command:` URIs are not run, the rest go
// to the system) and the desktop's `resolveExternalUri`
// (src/vs/workbench/electron-browser/window.ts).
//
// Deviations: no link protection prompt for untrusted domains, no
// contributed external openers, and no port tunneling (`allowTunneling`):
// `$asExternalUri` returns local URIs as they are; the native window
// handle is not sent.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../window/url_service.dart';
import '../window/window_ports.dart';
import 'main_thread_context.dart';

final class MainThreadWindow extends MainThreadWindowUnsupported {
  MainThreadWindow(
    this._focus,
    this._proxy, {
    required this.opener,
    this.urls,
    MainThreadContext? context,
  }) {
    var focused = _focus.isFocused;
    var active = _focus.isActive;
    final subscription = _focus.changes.listen((_) {
      // `Event.latch`: only real changes go over.
      if (_focus.isFocused != focused) {
        focused = _focus.isFocused;
        unawaited(
          _proxy.$onDidChangeWindowFocus(focused).catchError((Object _) {}),
        );
      }
      if (_focus.isActive != active) {
        active = _focus.isActive;
        unawaited(
          _proxy.$onDidChangeWindowActive(active).catchError((Object _) {}),
        );
      }
    });
    context?.listen(subscription);
  }

  final ExtensionWindowFocus _focus;
  final ExtHostWindowProxy _proxy;
  final ExtensionExternalOpener opener;
  final ExtensionUrlService? urls;

  static RpcActor customer(MainThreadContext context) =>
      MainThreadWindowActor(
        MainThreadWindow(
          context.service<ExtensionWindowFocus>(),
          ExtHostWindowProxy(context.rpc),
          opener: context.service<ExtensionExternalOpener>(),
          urls: context.maybeService<ExtensionUrlService>(),
          context: context,
        ),
      );

  @override
  Future<Map<String, Object?>> $getInitialState() async => {
    'isFocused': _focus.isFocused,
    'isActive': _focus.isActive,
  };

  @override
  Future<bool> $openUri(
    VsUri uri,
    String? uriString,
    Map<String, Object?> options,
  ) async {
    // Called with a string that needed no transforming: it goes as it is.
    final target = uriString != null && VsUri.parse(uriString) == uri
        ? uriString
        : uri.toString();
    final urls = this.urls;
    if (urls != null && uri.scheme == urls.scheme) return urls.open(uri);
    // The command opener takes command URIs without running them.
    if (uri.scheme == 'command') return true;
    final parsed = uri.scheme == 'file'
        ? Uri.file(uri.fsPath())
        : Uri.tryParse(target);
    if (parsed == null) return false;
    return opener.openExternal(parsed);
  }

  @override
  Future<VsUri> $asExternalUri(VsUri uri, Map<String, Object?> options) async =>
      uri;
}
