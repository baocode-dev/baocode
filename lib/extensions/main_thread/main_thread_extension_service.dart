/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadExtensionService.ts.
//
// Deviations: `$activateExtension` goes to this host
// (`ExtHostExtensionService.$activate`), the one that knows the extension;
// `$setPerformanceMarks` keeps the marks for the Running Extensions view
// rather than handing them to a timer service (BaoCode has none);
// `$asBrowserUri` returns the URI unchanged, since BaoCode has no webview
// host to serve it from (see the Webview degradation); a missing
// dependency that is not installed is reported without offering to install
// it (the extension gallery's install command is another area's).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_notifications.dart';
import '../../l10n/l10n.dart';
import '../extension_host_service_io.dart';
import '../window/extension_descriptions.dart';
import '../window/runtime_extensions.dart';
import 'main_thread_context.dart';
import 'main_thread_message_service.dart' show ExtensionMessageUi;

/// A `PerformanceMark` of `$setPerformanceMarks`.
typedef ExtensionPerformanceMark = ({
  String name,
  num startTime,
  num duration,
});

final class MainThreadExtensionService
    extends MainThreadExtensionServiceUnsupported {
  MainThreadExtensionService(
    this._host,
    this._proxy,
    this._extensions, {
    this.ui,
    this.hostId = 'window',
  });

  final ExtensionHostService _host;

  /// This session's `ExtHostExtensionService`.
  final ExtHostExtensionServiceProxy _proxy;
  final RunningExtensionsService _extensions;
  final ExtensionMessageUi? ui;
  final String hostId;

  /// The marks the host sent, most recent last.
  final List<ExtensionPerformanceMark> performanceMarks = [];

  static RpcActor customer(MainThreadContext context) {
    final host = context.service<ExtensionHostService>();
    return MainThreadExtensionServiceActor(
      MainThreadExtensionService(
        host,
        ExtHostExtensionServiceProxy(context.rpc),
        context.service<RunningExtensionsService>(),
        ui: context.maybeService<ExtensionMessageUi>(),
        hostId: host.workspace.id,
      ),
    );
  }

  AppLocalizations? get _l10n => ui?.l10n?.call();

  /// The scanned description of [id], or null.
  Map<String, Object?>? _description(String id) =>
      findExtension(_host.extensions.value, id);

  String _nameOf(String id) {
    final description = _description(id);
    return description == null ? id : extensionDisplayName(description);
  }

  @override
  Future<Map<String, Object?>?> $getExtension(String extensionId) async =>
      _description(extensionId);

  @override
  Future<void> $activateExtension(
    Map<String, Object?> extensionId,
    Map<String, Object?> reason,
  ) async {
    if (_description(extensionIdFromWire(extensionId)) == null) return;
    // The extension host decides what the reason means.
    await _proxy.$activate(extensionId, reason);
  }

  @override
  void $onWillActivateExtension(Map<String, Object?> extensionId) {
    final id = extensionIdFromWire(extensionId);
    _host.didActivate(id);
    _extensions.willActivate(id, _nameOf(id), hostId);
  }

  @override
  void $onDidActivateExtension(
    Map<String, Object?> extensionId,
    num codeLoadingTime,
    num activateCallTime,
    num activateResolvedTime,
    Map<String, Object?> activationReason,
  ) {
    final id = extensionIdFromWire(extensionId);
    _host.didActivate(id);
    _extensions.didActivate(
      id,
      _nameOf(id),
      hostId,
      codeLoadingTime: codeLoadingTime,
      activateCallTime: activateCallTime,
      activateResolvedTime: activateResolvedTime,
      reason: ExtensionActivationReason.fromJson(activationReason),
    );
  }

  @override
  void $onExtensionRuntimeError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
  ) {
    final id = extensionIdFromWire(extensionId);
    final (:message, :stack) = serializedError(error);
    _extensions.runtimeError(
      id,
      _nameOf(id),
      hostId,
      ExtensionRuntimeException(message, stack),
    );
  }

  @override
  Future<void> $onExtensionActivationError(
    Map<String, Object?> extensionId,
    Map<String, Object?> error,
    Map<String, Object?>? missingExtensionDependency,
  ) async {
    final id = extensionIdFromWire(extensionId);
    final (:message, :stack) = serializedError(error);
    final missing = missingExtensionDependency?['dependency'] as String?;
    _extensions.activationError(
      id,
      _nameOf(id),
      hostId,
      ExtensionActivationError(message, stack, missing: missing),
    );
    final displayName = _nameOf(id);
    final ui = this.ui;
    final l10n = _l10n;
    if (ui == null || l10n == null) return;
    if (missing == null) {
      ui.notifications.notify(IdeSeverity.error, message, source: displayName);
      return;
    }
    // The dependency is installed but not loaded (the host only reports a
    // missing dependency it knows): offer to reload.
    ui.notifications.notify(
      IdeSeverity.error,
      l10n.windowExtensionMissingDependency(displayName, missing),
      source: displayName,
      primary: [
        if (ui.commands case final commands?)
          IdeNotificationAction(
            l10n.windowExtensionReloadWindow,
            () => unawaited(
              commands
                  .executeCommand('workbench.action.reloadWindow')
                  .catchError((Object _) => null),
            ),
          ),
      ],
    );
  }

  @override
  Future<void> $setPerformanceMarks(List<Map<String, Object?>> marks) async {
    for (final mark in marks) {
      final name = mark['name'];
      if (name is! String) continue;
      performanceMarks.add((
        name: name,
        startTime: mark['startTime'] as num? ?? 0,
        duration: mark['duration'] as num? ?? 0,
      ));
    }
  }

  @override
  Future<VsUri> $asBrowserUri(VsUri uri) async => uri;
}
