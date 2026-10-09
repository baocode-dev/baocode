/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// What the Webview shapes share: the app's side of the degradation (the
// placeholders the workbench shows in a Webview's place, one notice per
// extension, and the actions a placeholder's line offers).
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadWebviews.ts,
// mainThreadWebviewPanels.ts (`$createWebviewPanel` then
// `ExtHostWebviewPanels.$onDidDisposeWebviewPanel` on dispose),
// mainThreadWebviewViews.ts (`$registerWebviewViewProvider`, title,
// description, badge, `$show`) and mainThreadCustomEditors.ts
// (`$registerTextEditorProvider`/`$registerCustomEditorProvider`,
// `$onDidEdit`/`$onContentChange` for a resolved edit).
//
// Deviations, all intended by the goal (五.15): nothing is ever rendered;
// `$createWebviewPanel` answers the disposal at once; `$postMessage`
// answers false; `$onDidChangeWebviewPanelViewStates` is accepted and
// ignored (a panel is gone by then); a custom editor's documents open in
// BaoCode's own editors.

import 'dart:async';

import '../../ide/ide_notifications.dart';
import '../../l10n/l10n.dart';
import 'extension_descriptions.dart';
import 'webview_placeholders.dart';
import 'window_ports.dart';

/// What the degradation needs: the placeholders it keeps, where the notice
/// goes, and how its actions open what they name.
final class ExtensionWebviewUi {
  const ExtensionWebviewUi({
    required this.placeholders,
    this.notifications,
    this.commands,
    this.opener,
    this.l10n,
    this.onOutput,
    this.onNotice,
  });

  /// The placeholders of this session.
  final ExtensionWebviewPlaceholders placeholders;

  /// Where the one-time notice per extension shows; null shows none.
  final IdeNotifications? notifications;

  /// Runs a command a fallback action names (an extension's, or the
  /// workbench's).
  final ExtensionCommandExecutor? commands;

  /// Opens an address a placeholder offers; null offers none.
  final ExtensionExternalOpener? opener;

  /// Shows the Output panel, where the placeholder's line is.
  final VoidCallbackLike? onOutput;

  /// Told once per extension as its notice shows (tests, telemetry).
  final void Function(Map<String, Object?> extension)? onNotice;

  final AppLocalizations Function()? l10n;

  AppLocalizations get strings => l10n?.call() ?? englishLocalizations;
}

/// A no-argument callback.
typedef VoidCallbackLike = void Function();

/// The one-time notice per extension: "此功能需要 Webview，BaoCode 不支持"
/// — and never twice for the same extension, as the goal asks.
final class ExtensionWebviewNotices {
  ExtensionWebviewNotices(this.ui);

  final ExtensionWebviewUi ui;
  final Set<String> _noticed = {};

  bool noticed(String extensionId) => _noticed.contains(extensionKey(extensionId));

  /// Shows the notice for [extension] once.
  void notice(
    Map<String, Object?> extension,
    String message, {
    List<IdeNotificationAction> primary = const [],
    String? logLine,
    String? reason,
  }) {
    final id = extensionKey(extensionIdOf(extension));
    if (!_noticed.add(id)) return;
    ui.onNotice?.call(extension);
    if (logLine != null) ui.placeholders.logLine(logLine);
    final notifications = ui.notifications;
    if (notifications == null) return;
    notifications.notify(
      IdeSeverity.warning,
      '$message\n${reason ?? ui.strings.windowWebviewUnsupported}',
      source: extensionDisplayName(extension),
      primary: primary,
    );
  }
}

/// The actions a placeholder offers: the panel's HTML when it is an
/// address, and the Output panel where the placeholder's line is.
List<IdeNotificationAction> webviewFallbackActions(
  ExtensionWebviewUi ui,
  String handle,
) {
  final content = ui.placeholders.html[handle];
  final opener = ui.opener;
  final output = ui.onOutput;
  return [
    if (opener != null && content != null)
      if (Uri.tryParse(content.trim()) case final uri?
          when uri.scheme == 'http' || uri.scheme == 'https')
        IdeNotificationAction(
          ui.strings.windowWebviewOpenInBrowser,
          () => unawaited(opener.openExternal(uri)),
        ),
    if (output != null)
      IdeNotificationAction(ui.strings.windowWebviewShowOutput, output),
  ];
}
