/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// The providers registered for one language feature, ordered for a
// document by selector score, then builtin-last, then most recent first.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/editor/common/languageFeatureRegistry.ts (`LanguageFeatureRegistry`,
// `NotebookInfo`, `NotebookInfoResolver`, `MatchCandidate`).
//
// Deviations:
// - `onDidChange` is a synchronous broadcast stream of the entry count.
// - `register` returns a [FeatureRegistration] (`IDisposable`).
// - Sorting is stable (Dart's `List.sort` is not; JavaScript's is).

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart' show VsUri;

import 'language_feature_document.dart';
import 'language_selector.dart';

/// `IDisposable` for a registration.
abstract interface class FeatureRegistration {
  void dispose();

  factory FeatureRegistration(void Function() dispose) = _Registration;
}

class _Registration implements FeatureRegistration {
  _Registration(this._dispose);

  void Function()? _dispose;

  @override
  void dispose() {
    final dispose = _dispose;
    _dispose = null;
    dispose?.call();
  }
}

/// `NotebookInfo`.
class NotebookInfo {
  const NotebookInfo(this.uri, this.type);

  final VsUri uri;
  final String type;
}

/// `NotebookInfoResolver`.
typedef NotebookInfoResolver = NotebookInfo? Function(VsUri uri);

class _Entry<T> {
  _Entry(this.selector, this.provider, this.time);

  final LanguageSelector selector;
  final T provider;
  int score = -1;
  final int time;
}

class _MatchCandidate {
  const _MatchCandidate(
    this.uri,
    this.languageId,
    this.notebookUri,
    this.notebookType,
    this.recursive,
  );

  final VsUri uri;
  final String languageId;
  final VsUri? notebookUri;
  final String? notebookType;
  final bool recursive;

  bool equals(_MatchCandidate other) =>
      notebookType == other.notebookType &&
      languageId == other.languageId &&
      uri.toString() == other.uri.toString() &&
      notebookUri?.toString() == other.notebookUri?.toString() &&
      recursive == other.recursive;
}

class LanguageFeatureRegistry<T> {
  LanguageFeatureRegistry([this._notebookInfoResolver]);

  final NotebookInfoResolver? _notebookInfoResolver;
  int _clock = 0;
  final List<_Entry<T>> _entries = [];
  _MatchCandidate? _lastCandidate;

  final _onDidChange = StreamController<int>.broadcast(sync: true);

  /// Fires the number of registered providers after each change.
  Stream<int> get onDidChange => _onDidChange.stream;

  FeatureRegistration register(LanguageSelector selector, T provider) {
    final entry = _Entry<T>(selector, provider, _clock++);
    _entries.add(entry);
    _lastCandidate = null;
    _fire();
    var registered = true;
    return FeatureRegistration(() {
      if (!registered) return;
      registered = false;
      final index = _entries.indexOf(entry);
      if (index >= 0) {
        _entries.removeAt(index);
        _lastCandidate = null;
        _fire();
      }
    });
  }

  bool has(LanguageFeatureDocument model) => all(model).isNotEmpty;

  /// Matching providers, in the last computed order.
  List<T> all(LanguageFeatureDocument model) {
    _updateScores(model, false);
    return [
      for (final entry in _entries)
        if (entry.score > 0) entry.provider,
    ];
  }

  List<T> allNoModel() => [for (final entry in _entries) entry.provider];

  Set<String> get registeredLanguageIds {
    final result = <String>{};
    for (final entry in _entries) {
      selectLanguageIds(entry.selector, result);
    }
    return result;
  }

  /// Matching providers: best score first, builtin providers after others
  /// of the same score, then the most recently registered first.
  List<T> ordered(LanguageFeatureDocument model, {bool recursive = false}) {
    final result = <T>[];
    _orderedForEach(model, recursive, (entry) => result.add(entry.provider));
    return result;
  }

  /// [ordered], grouped by equal score.
  List<List<T>> orderedGroups(LanguageFeatureDocument model) {
    final result = <List<T>>[];
    List<T>? lastBucket;
    int? lastBucketScore;
    _orderedForEach(model, false, (entry) {
      if (lastBucket != null && lastBucketScore == entry.score) {
        lastBucket!.add(entry.provider);
      } else {
        lastBucketScore = entry.score;
        lastBucket = [entry.provider];
        result.add(lastBucket!);
      }
    });
    return result;
  }

  void _orderedForEach(
    LanguageFeatureDocument model,
    bool recursive,
    void Function(_Entry<T> entry) callback,
  ) {
    _updateScores(model, recursive);
    for (final entry in _entries) {
      if (entry.score > 0) callback(entry);
    }
  }

  void _updateScores(LanguageFeatureDocument model, bool recursive) {
    final notebookInfo = _notebookInfoResolver?.call(model.uri);

    // use the uri (scheme, pattern) of the notebook info iff we have one
    // otherwise it's the model's/document's uri
    final candidate = _MatchCandidate(
      model.uri,
      model.languageId,
      notebookInfo?.uri,
      notebookInfo?.type,
      recursive,
    );

    if (_lastCandidate?.equals(candidate) ?? false) {
      // nothing has changed
      return;
    }

    _lastCandidate = candidate;

    for (final entry in _entries) {
      entry.score = score(
        entry.selector,
        candidate.uri,
        candidate.languageId,
        model.isSynchronized,
        candidate.notebookUri,
        candidate.notebookType,
      );

      if (isExclusiveSelector(entry.selector) && entry.score > 0) {
        if (recursive) {
          entry.score = 0;
        } else {
          // support for one exclusive selector that overwrites
          // any other selector
          for (final other in _entries) {
            other.score = 0;
          }
          entry.score = 1000;
          break;
        }
      }
    }

    // needs sorting
    stableSort(_entries, _compareByScoreAndTime);
  }

  static int _compareByScoreAndTime(_Entry<Object?> a, _Entry<Object?> b) {
    if (a.score < b.score) {
      return 1;
    } else if (a.score > b.score) {
      return -1;
    }

    // De-prioritize built-in providers
    if (isBuiltinSelector(a.selector) && !isBuiltinSelector(b.selector)) {
      return 1;
    } else if (!isBuiltinSelector(a.selector) &&
        isBuiltinSelector(b.selector)) {
      return -1;
    }

    if (a.time < b.time) {
      return 1;
    } else if (a.time > b.time) {
      return -1;
    } else {
      return 0;
    }
  }

  void _fire() {
    if (!_onDidChange.isClosed) _onDidChange.add(_entries.length);
  }

  void dispose() => _onDidChange.close();
}

/// Sorts [list] in place keeping equal elements in order, as JavaScript's
/// `Array.prototype.sort` does.
void stableSort<E>(List<E> list, int Function(E a, E b) compare) {
  if (list.length < 2) return;
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
  indexed.sort((a, b) {
    final order = compare(a.$2, b.$2);
    return order != 0 ? order : a.$1.compareTo(b.$1);
  });
  for (var i = 0; i < list.length; i++) {
    list[i] = indexed[i].$2;
  }
}
