/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/label/common/labelService.ts
// (`registerFormatter`, `findFormatting`, `formatUri`): the resource label
// formatters extensions register
// (`workspace.registerResourceLabelFormatter`), for URIs of their schemes.
//
// Deviations: formatters are not cached across sessions (upstream keeps
// the last ones in a memento for its next start); an authority glob
// supports `*` and `?` only.

import 'dart:convert';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

/// `ResourceLabelFormatter`: `{scheme, authority?, priority?, formatting}`.
typedef ExtensionLabelFormatter = Map<String, Object?>;

/// The label formatters extensions registered, and labels by them.
final class ExtensionLabelService extends ChangeNotifier {
  ExtensionLabelService({this.userHome, this.windows = false});

  /// For `tildify`.
  final String? userHome;
  final bool windows;

  final List<ExtensionLabelFormatter> _formatters = [];

  List<ExtensionLabelFormatter> get formatters => List.unmodifiable(_formatters);

  /// `registerFormatter`; call the result to remove it.
  void Function() registerFormatter(ExtensionLabelFormatter formatter) {
    _formatters.add(formatter);
    notifyListeners();
    return () {
      if (_formatters.remove(formatter)) notifyListeners();
    };
  }

  /// `findFormatting`.
  Map<String, Object?>? findFormatting(VsUri resource) {
    ExtensionLabelFormatter? best;
    for (final formatter in _formatters) {
      if (formatter['scheme'] != resource.scheme) continue;
      final authority = formatter['authority'] as String?;
      final bestAuthority = best?['authority'] as String?;
      if (authority == null || authority.isEmpty) {
        if (best == null || formatter['priority'] == true) best = formatter;
        continue;
      }
      if (_glob(authority, resource.authority) &&
          (bestAuthority == null ||
              authority.length > bestAuthority.length ||
              (authority.length == bestAuthority.length &&
                  formatter['priority'] == true))) {
        best = formatter;
      }
    }
    return switch (best?['formatting']) {
      final Map<Object?, Object?> formatting => formatting.cast(),
      _ => null,
    };
  }

  /// The label of [resource] by a formatter; null when none formats it.
  String? uriLabel(VsUri resource) {
    final formatting = findFormatting(resource);
    return formatting == null ? null : formatUri(resource, formatting);
  }

  static final _labelMatching = RegExp(
    r'\$\{(scheme|authoritySuffix|authority|path|(query)\.(.+?))\}',
  );

  /// `formatUri`.
  String formatUri(VsUri resource, Map<String, Object?> formatting) {
    final separator = formatting['separator'] as String? ?? '/';
    var label = '${formatting['label'] ?? ''}'.replaceAllMapped(
      _labelMatching,
      (match) {
        switch (match[1]) {
          case 'scheme':
            return resource.scheme;
          case 'authority':
            return resource.authority;
          case 'authoritySuffix':
            final i = resource.authority.indexOf('+');
            return i == -1
                ? resource.authority
                : resource.authority.substring(i + 1);
          case 'path':
            var path = resource.path;
            final strip = formatting['stripPathSegments'];
            if (strip is num && strip > 0) {
              var pos = 0;
              for (var i = 0; i < strip; i++) {
                final next = path.indexOf('/', pos + 1);
                if (next == -1) break;
                pos = next;
              }
              path = path.substring(pos);
            }
            return formatting['stripPathStartingSeparator'] == true &&
                    path.isNotEmpty &&
                    path[0] == separator
                ? path.substring(1)
                : path;
        }
        if (match[2] == 'query') {
          final query = resource.query;
          if (query.startsWith('{') && query.endsWith('}')) {
            try {
              final json = jsonDecode(query);
              if (json is Map) return '${json[match[3]] ?? ''}';
            } on FormatException {
              // Not JSON.
            }
          }
        }
        return '';
      },
    );
    // `\c:\something` → `C:\something`.
    if (formatting['normalizeDriveLetter'] == true &&
        label.length > 2 &&
        label[2] == ':') {
      label = label[1].toUpperCase() + label.substring(2);
    }
    final home = userHome;
    if (formatting['tildify'] == true && home != null && !windows) {
      if (label == home) {
        label = '~';
      } else if (label.startsWith('$home/')) {
        label = '~${label.substring(home.length)}';
      }
    }
    if (formatting['authorityPrefix'] case final String prefix
        when resource.authority.isNotEmpty) {
      label = prefix + label;
    }
    return label.replaceAll(windows ? RegExp(r'[\\/]') : RegExp('/'), separator);
  }

  static bool _glob(String pattern, String value) {
    final regex = RegExp(
      '^${pattern.split('').map((c) => switch (c) {
        '*' => '.*',
        '?' => '.',
        _ => RegExp.escape(c),
      }).join()}\$',
      caseSensitive: false,
    );
    return regex.hasMatch(value);
  }
}
