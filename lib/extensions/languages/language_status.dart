/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// `window.createLanguageStatusItem`: the entries an extension shows for a
// document's language (a server's state, the TypeScript version, a
// "Select Interpreter" button).
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/languageStatus/common/languageStatusService.ts
// (`ILanguageStatus`, `addStatus`, `getLanguageStatus`'s order),
// src/vs/workbench/api/browser/mainThreadLanguages.ts
// (`$setLanguageStatus`, `$removeLanguageStatus`) and the item's text from
// src/vs/workbench/contrib/languageStatus/browser/languageStatus.ts
// (`computeText`, the severity codicons).
//
// Deviations: matching uses the selector's score on the document's URI and
// language alone (no notebook cells); the workbench shows the items as one
// status bar entry whose hover lists them and whose click offers their
// commands (no pinning of dedicated entries).

import 'package:bao_exthost/bao_exthost.dart' show VsUri;
import 'package:flutter/foundation.dart';

import '../language/language_selector.dart';

/// `Severity` as `ILanguageStatus` has it.
abstract final class LanguageStatusSeverity {
  static const int ignore = 0;
  static const int info = 1;
  static const int warning = 2;
  static const int error = 3;
}

/// `ILanguageStatus`.
final class LanguageStatus {
  const LanguageStatus({
    required this.id,
    required this.name,
    required this.selector,
    this.severity = LanguageStatusSeverity.info,
    this.label = '',
    this.detail = '',
    this.busy = false,
    this.source = '',
    this.command,
    this.accessibilityLabel,
  });

  factory LanguageStatus.fromJson(Map<String, Object?> json) => LanguageStatus(
    id: '${json['id']}',
    name: '${json['name'] ?? ''}',
    selector:
        LanguageSelector.parse(json['selector']) ??
        const LanguageSelectorList([]),
    severity:
        (json['severity'] as num?)?.toInt() ?? LanguageStatusSeverity.info,
    label: switch (json['label']) {
      final String s => s,
      {'value': final String s} => s,
      _ => '',
    },
    detail: json['detail'] as String? ?? '',
    busy: json['busy'] == true,
    source: json['source'] as String? ?? '',
    command: (json['command'] as Map?)?.cast(),
    accessibilityLabel:
        (json['accessibilityInfo'] as Map?)?['label'] as String?,
  );

  /// `publisher.name/id`.
  final String id;
  final String name;
  final LanguageSelector selector;
  final int severity;

  /// The text, with `$(codicon)`s.
  final String label;
  final String detail;
  final bool busy;

  /// The extension's name.
  final String source;

  /// `{id, title, arguments, tooltip}`, its arguments the extension host's.
  final Map<String, Object?>? command;
  final String? accessibilityLabel;

  /// `computeText`: the label with a spinner while busy.
  String get text => busy
      ? (label.isEmpty ? r'$(loading~spin)' : '$label \$(loading~spin)')
      : label;
}

/// `ILanguageStatusService`: the items, by the extension host's handle.
final class LanguageStatusService extends ChangeNotifier {
  final Map<num, (LanguageStatus, int)> _items = {};
  int _clock = 0;

  /// `addStatus`; one handle's status replaces its last.
  void setStatus(num handle, LanguageStatus status) {
    _items[handle] = (status, _clock++);
    notifyListeners();
  }

  void removeStatus(num handle) {
    if (_items.remove(handle) == null) return;
    notifyListeners();
  }

  /// Every item, as set.
  List<LanguageStatus> get all => [for (final (s, _) in _items.values) s];

  /// Every handle's item gone (its extension host ended).
  void clear() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  /// `getLanguageStatus(model)`: the items whose selector matches the
  /// document, most severe first, then by source and id.
  List<LanguageStatus> forDocument(VsUri uri, String languageId) {
    final scored = [
      for (final (status, clock) in _items.values)
        (
          status,
          clock,
          score(status.selector, uri, languageId, true, null, null),
        ),
    ];
    // `LanguageFeatureRegistry.ordered`: by score, then newest first; then
    // sorted as `getLanguageStatus` does (stable).
    final matching = [
      for (final entry in scored)
        if (entry.$3 > 0) entry,
    ]..sort((a, b) => a.$3 != b.$3 ? b.$3 - a.$3 : b.$2 - a.$2);
    final ordered = [for (final (s, _, _) in matching) s];
    mergeSort(
      ordered,
      compare: (a, b) {
        var result = b.severity - a.severity;
        if (result == 0) result = a.source.compareTo(b.source);
        if (result == 0) result = a.id.compareTo(b.id);
        return result;
      },
    );
    return ordered;
  }
}
