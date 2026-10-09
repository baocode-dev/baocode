/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadMessageService.ts.
//
// Deviations: urgent sources (the authentication extensions) are sticky
// toasts, as upstream's are, but there is no Do Not Disturb filter to
// bypass; `useCustom` has no effect (every dialog is the app's own).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../../ide/ide_notifications.dart';
import '../../l10n/l10n.dart';
import '../window/window_ports.dart';
import 'main_thread_context.dart';

/// What the message service shows with: the window's notifications, its
/// dialogs and commands (for Manage Extension), in the app's language.
final class ExtensionMessageUi {
  const ExtensionMessageUi({
    required this.notifications,
    required this.dialogs,
    this.commands,
    this.l10n,
  });

  final IdeNotifications notifications;
  final ExtensionDialogs dialogs;
  final ExtensionCommandExecutor? commands;
  final AppLocalizations Function()? l10n;
}

final class MainThreadMessageService
    extends MainThreadMessageServiceUnsupported {
  MainThreadMessageService(this._ui);

  final ExtensionMessageUi _ui;

  static const urgentNotificationSources = [
    'vscode.github-authentication',
    'vscode.microsoft-authentication',
  ];

  static RpcActor customer(MainThreadContext context) =>
      MainThreadMessageServiceActor(
        MainThreadMessageService(context.service<ExtensionMessageUi>()),
      );

  AppLocalizations get _l10n => _ui.l10n?.call() ?? englishLocalizations;

  @override
  Future<num?> $showMessage(
    int severity,
    String message,
    Map<String, Object?> options,
    List<Map<String, Object?>> commands,
  ) {
    final level = ExtensionSeverity.fromWire(severity);
    if (options['modal'] == true) {
      return _showModalMessage(
        level,
        message,
        options['detail'] as String?,
        commands,
      );
    }
    return _showMessage(level, message, commands, options);
  }

  Future<num?> _showMessage(
    ExtensionSeverity severity,
    String message,
    List<Map<String, Object?>> commands,
    Map<String, Object?> options,
  ) {
    final result = Completer<num?>();
    void resolve(num? handle) {
      if (!result.isCompleted) result.complete(handle);
    }

    final primary = [
      for (final command in commands)
        IdeNotificationAction(
          '${command['title']}',
          () => resolve(command['handle'] as num?),
        ),
    ];
    String source;
    String? sourceId;
    var urgent = false;
    if (options['source'] case final Map<Object?, Object?> from) {
      source = '${from['label']}';
      sourceId = switch (from['identifier']) {
        final Map<Object?, Object?> id => '${id['value']}',
        final String id => id,
        _ => null,
      };
      urgent = urgentNotificationSources.contains(sourceId);
    } else {
      source = _l10n.windowMessageDefaultSource;
    }
    final secondary = [
      if (sourceId != null && _ui.commands != null)
        IdeNotificationAction(
          _l10n.windowMessageManageExtension,
          () => unawaited(
            _ui.commands!
                .executeCommand('_extensions.manage', [sourceId])
                .catchError((Object _) => null),
          ),
        ),
    ];
    _ui.notifications.notify(
      switch (severity) {
        ExtensionSeverity.warning => IdeSeverity.warning,
        ExtensionSeverity.error => IdeSeverity.error,
        _ => IdeSeverity.info,
      },
      message,
      source: source,
      primary: primary,
      secondary: secondary,
      sticky: urgent,
      // Once it closes without a button, the answer is undefined (a
      // button closes it just before it runs: its answer goes first).
      onClose: () => scheduleMicrotask(() => resolve(null)),
    );
    return result.future;
  }

  Future<num?> _showModalMessage(
    ExtensionSeverity severity,
    String message,
    String? detail,
    List<Map<String, Object?>> commands,
  ) async {
    final buttons = <Map<String, Object?>>[];
    Map<String, Object?>? cancelButton;
    for (final command in commands) {
      if (command['isCloseAffordance'] == true) {
        cancelButton = command;
      } else {
        buttons.add(command);
      }
    }
    final cancel =
        cancelButton?['title'] as String? ??
        (buttons.isNotEmpty ? _l10n.commonCancel : _l10n.commonOk);
    final answer = await _ui.dialogs.prompt(
      severity: severity,
      message: message,
      detail: detail,
      buttons: [for (final button in buttons) '${button['title']}'],
      cancel: cancel,
    );
    final index = answer.button;
    if (index == null || index < 0 || index >= buttons.length) {
      return cancelButton?['handle'] as num?;
    }
    return buttons[index]['handle'] as num?;
  }
}
