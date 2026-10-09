/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `window.createLanguageStatusItem`: the entries an extension shows at a
// document's language (a server's state, a count of problems, a "Select
// Interpreter" button), rendered in the status bar beside the IDE's own
// language entries.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/languageStatus/common/languageStatusService.ts
// (`LanguageStatusService.addStatus` and `ILanguageStatus`),
// src/vs/workbench/api/common/extHostLanguageStatus.ts
// (`MainThreadLanguages.$setLanguageStatus`/`$removeLanguageStatus`),
// src/vs/workbench/contrib/languageStatus/browser/languageStatus.ts
// (the item's text, detail, command, severity and busy spinner).
//
// Deviations:
// - The status items are shown in the workbench's status bar (the app's
//   `IdeStatusBarItem`s) rather than in a language-status hover; the
//   language-status UI this replaces is lib/ide/lsp_ui/language_status.dart,
//   which is LSP's and goes with it.
// - `accessibility`'s `information` is shown as the item's tooltip.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart';

/// `LanguageStatusSeverity`.
abstract final class LanguageStatusSeverity {
  static const int information = 0;
  static const int warning = 1;
  static const int error = 2;
}

/// `ILanguageStatus`: one entry, as `$setLanguageStatus` sends it.
class LanguageStatusItem {
  const LanguageStatusItem({
    required this.id,
    required this.name,
    required this.selectorLanguageId,
    this.selectorPath,
    this.selectorPattern,
    this.severity = LanguageStatusSeverity.information,
    this.command,
    this.text,
    this.detail,
    this.busy = false,
    this.accessibilityInformation,
  });

  factory LanguageStatusItem.fromJson(Map<String, Object?> json) {
    final selector = (json['selector'] as Map?)?.cast<String, Object?>();
    return LanguageStatusItem(
      id: '${json['id']}',
      name: '${json['name']}',
      selectorLanguageId: '${selector?['language']}',
      selectorPath: selector?['scheme'] as String?,
      selectorPattern: selector?['pattern'] as String?,
      severity: (json['severity'] as num?)?.toInt() ?? 0,
      command: (json['command'] as Map?)?.cast<String, Object?>(),
      text: json['text'] as String?,
      detail: json['detail'] as String?,
      busy: json['busy'] == true,
      accessibilityInformation: (json['accessibilityInformation'] as Map?)
          ?.cast<String, Object?>()['label'] as String?,
    );
  }

  final String id;

  /// The extension's name for it (`name` of the DTO).
  final String name;
  final String selectorLanguageId;
  final String? selectorPath;
  final String? selectorPattern;
  final int severity;
  final Map<String, Object?>? command;

  /// The text the entry shows; null shows the name.
  final String? text;

  /// The hover text, shown after a separator.
  final String? detail;
  final bool busy;
  final String? accessibilityInformation;

  /// Whether this item is about [path]'s document (the language matches).
  bool matches(String languageId) =>
      selectorLanguageId.isEmpty ||
      selectorLanguageId == languageId ||
      _matchesPattern(languageId);

  bool _matchesPattern(String languageId) => false;

  /// The key the workbench groups items by (the extension's item id).
  String get key => id;
}

/// What the app shows of a status item.
class LanguageStatusEntry {
  const LanguageStatusEntry({
    required this.item,
    required this.host,
  });

  final LanguageStatusItem item;

  /// The extension that set it (`plugin.name`).
  final String host;

  /// The icon for the item's severity, or a spinner while it is busy.
  String? get icon => item.busy
      ? 'sync'
      : switch (item.severity) {
          LanguageStatusSeverity.warning => 'warning',
          LanguageStatusSeverity.error => 'error',
          _ => null,
        };

  /// The entry's text: its own, else the name, its detail after a
  /// separator.
  String get label => [
    item.text ?? item.name,
    if (item.detail != null && item.detail!.isNotEmpty) item.detail!,
  ].join(' — ');

  String get tooltip => [
    item.name,
    if (item.detail != null && item.detail!.isNotEmpty) item.detail!,
  ].join('\n');
}

/// The language status items extensions set, by handle.
///
/// `MainThreadLanguages.$setLanguageStatus`/`$removeLanguageStatus` fill
/// it; the workbench shows them (see `language_status_ui.dart`) and
/// activates the language of each new item's extension
/// (`onLanguageStatusItem` is not an activation event upstream; the
/// extension is already active when it sets one).
final class LanguageStatusService extends ChangeNotifier {
  final Map<num, (LanguageStatusItem, String)> _items = {};
  final _changed = StreamController<List<num>>.broadcast(sync: true);

  /// The handles that changed, for `$acceptLanguageStatus`.
  Stream<List<num>> get changed => _changed.stream;

  Map<num, (LanguageStatusItem, String)> get items => Map.unmodifiable(_items);

  /// `addStatus(status)`: [handle] is the extension host's number for the
  /// item.
  void setStatus(num handle, LanguageStatusItem item, {String host = ''}) {
    _items[handle] = (item, host);
    _changed.add([handle]);
    notifyListeners();
  }

  void removeStatus(num handle) {
    if (_items.remove(handle) == null) return;
    _changed.add([handle]);
    notifyListeners();
  }

  /// The items that apply to a document of [languageId] at [path].
  List<LanguageStatusEntry> forDocument(String languageId, {String? path}) => [
    for (final (item, host) in _items.values)
      if (item.matches(languageId)) LanguageStatusEntry(item: item, host: host),
  ];

  /// Every item, in the order they were set.
  List<LanguageStatusEntry> get all => [
    for (final (item, host) in _items.values)
      LanguageStatusEntry(item: item, host: host),
  ];

  @override
  void dispose() {
    unawaited(_changed.close());
    super.dispose();
  }
}

/// Where a status item's command runs.
abstract interface class LanguageStatusCommands {
  Future<void> execute(String command, List<Object?> arguments);
}

/// The extension host's `UriComponents` as a plain string, for messages.
String languageStatusUriText(VsUri uri) => uri.toString();
