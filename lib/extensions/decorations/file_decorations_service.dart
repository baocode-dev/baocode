/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The file decorations extensions provide (`FileDecorationProvider`): a
// resource's badge letter, color and tooltip, asked for as the workbench
// shows it, kept until the provider says it changed; folders show a dot
// for their decorated children that `bubble`.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/decorations/browser/decorationsService.ts
// (`DecorationsService`: `registerDecorationsProvider`, `getDecoration`,
// `_fetchData`, `_keepItem`; `DecorationStyles.asDecoration` and
// `DecorationRule._appendForMany`: the heaviest first, the first color,
// the letters joined, the tooltips joined with ` • `).
//
// Deviations: resources are keyed by their URI string (their path for
// files, case-sensitively); a letter that is a `ThemeIcon` is not
// supported (extensions' letters are strings); change events are batched
// in a microtask rather than a debounce emitter.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';
import 'package:flutter/foundation.dart';

/// `IDecorationData`.
@immutable
final class FileDecorationData {
  const FileDecorationData({
    this.weight = 0,
    this.colorId,
    this.letter,
    this.tooltip,
    this.bubble = false,
    this.strikethrough = false,
  });

  final int weight;

  /// A theme color's id.
  final String? colorId;
  final String? letter;
  final String? tooltip;

  /// Its folders show a dot for it.
  final bool bubble;
  final bool strikethrough;
}

/// `IDecoration`: what a resource shows, merged from every provider.
@immutable
final class FileDecoration {
  const FileDecoration({
    this.colorId,
    this.letter,
    this.tooltip = '',
    this.bubbleOnly = false,
    this.strikethrough = false,
  });

  final String? colorId;

  /// The letters, joined with `, `.
  final String? letter;
  final String tooltip;

  /// Only its children's decorations: a dot ("Contains emphasized
  /// items").
  final bool bubbleOnly;
  final bool strikethrough;
}

/// One provider: what it gives for a resource, and its changes (null: all
/// of its resources).
final class FileDecorationsProvider {
  FileDecorationsProvider({required this.label, required this.provide});

  final String label;
  final Future<FileDecorationData?> Function(VsUri uri) provide;
}

/// Every provider's decorations, per resource.
final class FileDecorationsService extends ChangeNotifier {
  final List<FileDecorationsProvider> _providers = [];

  /// By resource: each provider's data, null for none, or the request.
  final Map<String, ({VsUri uri, Map<FileDecorationsProvider, Object?> data})>
  _data = {};
  final Set<String> _changed = {};
  bool _everything = false;
  bool _scheduled = false;
  bool _disposed = false;

  /// The resources whose decorations changed since the last notification
  /// (all of them when null).
  Set<String>? get lastChanged => _lastChanged;
  Set<String>? _lastChanged;

  /// Adds [provider] (the newest first); the returned functions tell its
  /// changes and remove it.
  ({void Function(List<VsUri>? uris) changed, void Function() dispose})
  register(FileDecorationsProvider provider) {
    _providers.insert(0, provider);
    _fireAll();

    void removeAll() {
      for (final MapEntry(:key, :value) in _data.entries) {
        if (value.data.remove(provider) != null) _fire(key);
      }
    }

    return (
      changed: (uris) {
        if (_disposed || !_providers.contains(provider)) return;
        if (uris == null) {
          removeAll();
          return;
        }
        for (final uri in uris) {
          final entry = _ensureEntry(uri);
          _fetch(entry.data, uri, provider);
        }
      },
      dispose: () {
        if (!_providers.remove(provider)) return;
        removeAll();
      },
    );
  }

  ({VsUri uri, Map<FileDecorationsProvider, Object?> data}) _ensureEntry(
    VsUri uri,
  ) => _data.putIfAbsent('$uri', () => (uri: uri, data: {}));

  /// What [uri] shows, asking the providers that have not answered; with
  /// [includeChildren] (a folder), its children's that bubble too.
  FileDecoration? getDecoration(VsUri uri, {bool includeChildren = false}) {
    final all = <FileDecorationData>[];
    var containsChildren = false;
    final entry = _ensureEntry(uri);
    for (final provider in _providers) {
      var data = entry.data.containsKey(provider) ? entry.data[provider] : _no;
      if (identical(data, _no)) data = _fetch(entry.data, uri, provider);
      if (data is FileDecorationData) all.add(data);
    }
    if (includeChildren) {
      final prefix = '$uri'.endsWith('/') ? '$uri' : '$uri/';
      for (final MapEntry(:key, :value) in _data.entries) {
        if (!key.startsWith(prefix)) continue;
        for (final data in value.data.values) {
          if (data is FileDecorationData && data.bubble) {
            all.add(data);
            containsChildren = true;
          }
        }
      }
    }
    if (all.isEmpty) return null;
    return _asDecoration(all, containsChildren);
  }

  static const _no = Object();

  /// `asDecoration`: the heaviest first.
  static FileDecoration _asDecoration(
    List<FileDecorationData> data,
    bool onlyChildren,
  ) {
    final sorted = [...data]..sort((a, b) => b.weight - a.weight);
    final letters = [
      for (final d in sorted)
        if (d.letter case final letter? when letter.isNotEmpty) letter,
    ];
    final tooltips = <String>{
      for (final d in sorted)
        if (d.tooltip case final tooltip? when tooltip.trim().isNotEmpty)
          tooltip,
    };
    return FileDecoration(
      colorId: sorted.map((d) => d.colorId).nonNulls.firstOrNull,
      letter: letters.isEmpty ? null : letters.join(', '),
      tooltip: onlyChildren ? '' : tooltips.join(' • '),
      bubbleOnly: onlyChildren,
      strikethrough: sorted.any((d) => d.strikethrough),
    );
  }

  Object? _fetch(
    Map<FileDecorationsProvider, Object?> map,
    VsUri uri,
    FileDecorationsProvider provider,
  ) {
    final previous = map[provider];
    final request = Object();
    map[provider] = request;
    unawaited(
      provider
          .provide(uri)
          .then(
            (data) {
              if (_disposed || !identical(map[provider], request)) return;
              map[provider] = data;
              // Only told when something changed.
              if (data != null || previous is FileDecorationData) {
                _fire('$uri');
              }
            },
            onError: (Object _) {
              if (identical(map[provider], request)) map.remove(provider);
            },
          ),
    );
    return null;
  }

  void _fire(String key) {
    _changed.add(key);
    _schedule();
  }

  void _fireAll() {
    _everything = true;
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed) return;
      _lastChanged = _everything ? null : {..._changed};
      _everything = false;
      _changed.clear();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _data.clear();
    _providers.clear();
    super.dispose();
  }
}
