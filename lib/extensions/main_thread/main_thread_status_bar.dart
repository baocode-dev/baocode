/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadStatusBar.ts.
//
// Deviations: the `contributes.statusBarItems` entries are (re)read from
// the session's extensions as it starts, where upstream's extension point
// handler reads them as extensions change.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../extension_host_service_io.dart';
import '../window/status_bar_service.dart';
import 'main_thread_context.dart';

final class MainThreadStatusBar extends MainThreadStatusBarUnsupported {
  MainThreadStatusBar(this._service, this._proxy, this._context) {
    // Once, at startup, the entries there are go over; then the ones
    // added (`$acceptStaticEntries`).
    unawaited(
      _proxy
          .$acceptStaticEntries([
            for (final entry in _service.entries) entry.toDto(),
          ])
          .catchError((Object _) {}),
    );
    _context.listen(
      _service.added.listen(
        (entry) => unawaited(
          _proxy.$acceptStaticEntries([entry.toDto()]).catchError((Object _) {}),
        ),
      ),
    );
    _service.tooltipProvider = provideTooltip;
    _context.onDispose(() {
      if (_service.tooltipProvider == provideTooltip) {
        _service.tooltipProvider = null;
      }
      for (final entryId in [..._defined]) {
        _service.unsetEntry(entryId);
      }
      _defined.clear();
    });
  }

  final ExtensionStatusBarService _service;
  final ExtHostStatusBarProxy _proxy;
  final MainThreadContext _context;
  final Set<String> _defined = {};

  static RpcActor customer(MainThreadContext context) {
    final service = context.service<ExtensionStatusBarService>();
    if (context.maybeService<ExtensionHostService>() case final host?) {
      service.setContributions(host.extensions.value);
    }
    return MainThreadStatusBarActor(
      MainThreadStatusBar(service, ExtHostStatusBarProxy(context.rpc), context),
    );
  }

  /// `ExtHostStatusBar.$provideTooltip` for an entry with a tooltip
  /// provider.
  Future<Object?> provideTooltip(String entryId) =>
      _proxy.$provideTooltip(entryId);

  @override
  void $setEntry(
    String id,
    String statusId,
    String? extensionId,
    String statusName,
    String text,
    Object? tooltip,
    bool hasTooltipProvider,
    Map<String, Object?>? command,
    Object? color,
    Object? backgroundColor,
    bool alignLeft,
    num? priority,
    Map<String, Object?>? accessibilityInformation,
  ) {
    final kind = _service.setOrUpdateEntry(
      entryId: id,
      id: statusId,
      extensionId: extensionId,
      name: statusName,
      text: text,
      tooltip: tooltip,
      hasTooltipProvider: hasTooltipProvider,
      command: command,
      color: color,
      backgroundColor: backgroundColor,
      alignLeft: alignLeft,
      priority: priority,
      accessibilityInformation: accessibilityInformation,
    );
    if (kind == StatusBarUpdateKind.didDefine) _defined.add(id);
  }

  @override
  void $disposeEntry(String id) {
    if (_defined.remove(id)) _service.unsetEntry(id);
  }
}
