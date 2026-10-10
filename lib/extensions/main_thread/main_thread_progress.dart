/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadProgress.ts.
//
// Deviations: a location the progress service cannot show is logged to
// the app's error log, as upstream's `onUnexpectedExternalError` does.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_notifications.dart';
import '../../l10n/l10n.dart';
import '../../platform/error_log.dart';
import '../window/progress_service.dart';
import '../window/window_ports.dart';
import 'main_thread_context.dart';
import 'main_thread_message_service.dart' show ExtensionMessageUi;

final class MainThreadProgress extends MainThreadProgressUnsupported {
  MainThreadProgress(
    this._service,
    this._proxy, {
    this.commands,
    this.errorLog,
    AppLocalizations Function()? l10n,
  }) : _l10n = l10n ?? (() => englishLocalizations);

  final ExtensionProgressService _service;
  final ExtHostProgressProxy _proxy;
  final ExtensionCommandExecutor? commands;
  final ErrorLog? errorLog;
  final AppLocalizations Function() _l10n;
  final Map<num, ExtensionProgressTask> _progress = {};

  static const urgentProgressSources = [
    'vscode.github-authentication',
    'vscode.microsoft-authentication',
  ];

  static RpcActor customer(MainThreadContext context) {
    final actor = MainThreadProgress(
      context.service<ExtensionProgressService>(),
      ExtHostProgressProxy(context.rpc),
      commands: context.maybeService<ExtensionCommandExecutor>(),
      errorLog: context.maybeService<ErrorLog>(),
      l10n: context.maybeService<ExtensionMessageUi>()?.l10n,
    );
    context.onDispose(actor.dispose);
    return MainThreadProgressActor(actor);
  }

  /// Ends every progress, as the session ends.
  void dispose() {
    for (final task in _progress.values) {
      task.done();
    }
    _progress.clear();
  }

  @override
  void $startProgress(
    num handle,
    Map<String, Object?> options,
    String? extensionId,
  ) {
    final location = options['location'];
    final notification =
        location == ExtensionProgressLocation.notification &&
        extensionId != null;
    final source = switch (options['source']) {
      final String label => label,
      final Map<Object?, Object?> source => source['label'] as String?,
      _ => null,
    };
    try {
      _progress[handle] = _service.start(
        location: location ?? 0,
        title: options['title'] as String?,
        source: source,
        total: options['total'] as num?,
        cancellable: options['cancellable'],
        buttons: [
          for (final button in options['buttons'] as List? ?? const [])
            '$button',
        ],
        urgent: notification && urgentProgressSources.contains(extensionId),
        onCancel: (_) => unawaited(
          _proxy.$acceptProgressCanceled(handle).catchError((Object _) {}),
        ),
        secondaryActions: [
          if (notification && commands != null)
            IdeNotificationAction(
              _l10n().windowMessageManageExtension,
              () => unawaited(
                commands!
                    .executeCommand('_extensions.manage', [extensionId])
                    .catchError((Object _) => null),
              ),
            ),
        ],
      );
    } on ArgumentError catch (error, stack) {
      errorLog?.record(error, stack, source: 'Extension Host');
    }
  }

  @override
  void $progressReport(num handle, Map<String, Object?> message) =>
      _progress[handle]?.report(progressStepFromJson(message));

  @override
  void $progressEnd(num handle) => _progress.remove(handle)?.done();
}
