/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `editor.defaultFormatter`, and what happens when a document has several
// formatters and none is the default: a format on save says so with a
// Configure... action; Format Document asks for one at once. The pick is
// kept as the language's `editor.defaultFormatter`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/contrib/format/browser/formatActionsMultiple.ts
// (`DefaultFormatter._selectFormatter`, `_pickAndPersistDefaultFormatter`).
//
// Deviation: Format Document picks without the "Configure Default
// Formatter" confirmation first.

import 'dart:async';

import '../../ide/ide_notifications.dart';
import '../configuration/configuration_service.dart';
import '../language/language_feature_document.dart';
import '../language/language_providers.dart';
import '../language/language_types.dart';

final class DefaultFormatter {
  DefaultFormatter({
    required this.configuration,
    required this.notifications,
    required this.pick,
    this.languageName,
  });

  final ConfigurationService configuration;
  final IdeNotifications notifications;

  /// Shows a quick pick of labels and descriptions; the picked index.
  final Future<int?> Function(
    List<({String label, String? description})> items,
    String placeholder,
  )
  pick;

  /// A language's name, for the pick's placeholder.
  final String Function(String languageId)? languageName;

  /// `editor.defaultFormatter` for [document].
  String? id(LanguageFeatureDocument document) => switch (configuration
      .getValue(
        'editor.defaultFormatter',
        resource: document.uri,
        languageId: document.languageId,
      )) {
    final String id when id.isNotEmpty => id,
    _ => null,
  };

  /// `_selectFormatter` when the default does not decide: silently a
  /// notice, else the pick.
  Future<int?> resolve(
    String message,
    List<LanguageFeatureProvider> formatters,
    LanguageFeatureDocument document,
    FormattingMode mode,
  ) async {
    if (mode == FormattingMode.silent) {
      notifications.notify(
        IdeSeverity.info,
        message,
        primary: [
          IdeNotificationAction(
            'Configure...',
            () => unawaited(_pickAndPersist(formatters, document)),
          ),
        ],
      );
      return null;
    }
    return _pickAndPersist(formatters, document);
  }

  Future<int?> _pickAndPersist(
    List<LanguageFeatureProvider> formatters,
    LanguageFeatureDocument document,
  ) async {
    final language =
        languageName?.call(document.languageId) ?? document.languageId;
    final index = await pick([
      for (final formatter in formatters)
        (
          label: formatter.displayName ?? formatter.extensionId ?? '???',
          description: formatter.extensionId,
        ),
    ], "Select a default formatter for '$language' files");
    if (index == null || index < 0 || index >= formatters.length) {
      return null;
    }
    final extensionId = formatters[index].extensionId;
    if (extensionId != null) {
      await configuration.update(
        'editor.defaultFormatter',
        extensionId,
        overrideIdentifier: document.languageId,
      );
    }
    return index;
  }
}
