/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// File and text search through the providers registered per scheme: the
// extension host's own ripgrep providers for `file` (it registers them
// when MainThreadSearch calls `$enableExtensionHostSearch`), and those
// extensions register for their schemes. A query waits for a provider of
// its scheme as upstream does while the extension host starts.
//
// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/services/search/common/searchService.ts
// (`registerSearchResultProvider`, `fileSearch`, `textSearch`,
// `searchWithProviders`, `groupFolderQueriesByScheme`, `waitForProvider`).
//
// Deviations:
// - No search cache, telemetry or open-editor results (the search view's
//   local matches of dirty documents).
// - Text results are the extension host's `IRawFileMatch2` JSON maps.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import 'query_builder.dart' show QueryType;

/// `ISearchResultProvider`: one scheme's provider of one [QueryType].
abstract interface class SearchResultProvider {
  /// `fileSearch`: the files found and whether the limit was hit.
  Future<SearchComplete> fileSearch(
    Map<String, Object?> query,
    CancellationToken token,
  );

  /// `textSearch`: each file's matches to [onProgress] as found.
  Future<SearchComplete> textSearch(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  );

  Future<void> clearCache(String cacheKey);
}

/// `ISearchComplete`: [results] are `IFileMatch` JSON (`resource`, and a
/// text match's `results`).
final class SearchComplete {
  const SearchComplete({
    this.results = const [],
    this.limitHit = false,
    this.messages = const [],
    this.stats,
  });

  final List<Map<String, Object?>> results;
  final bool limitHit;
  final List<Object?> messages;
  final Object? stats;
}

/// `ISearchService`.
final class SearchService {
  final _providers = <int, Map<String, SearchResultProvider>>{
    QueryType.file: {},
    QueryType.text: {},
    QueryType.aiText: {},
  };
  final _waiting = <int, Map<String, Completer<SearchResultProvider>>>{
    QueryType.file: {},
    QueryType.text: {},
    QueryType.aiText: {},
  };

  /// `registerSearchResultProvider`: the last registered for a scheme is
  /// its provider (a remote project's two extension hosts both register
  /// `vscode-userdata`); the returned function unregisters it.
  ///
  /// Deviation: unregistering one that was replaced leaves the one that
  /// replaced it (upstream deletes the scheme's).
  void Function() registerProvider(
    String scheme,
    int type,
    SearchResultProvider provider,
  ) {
    final providers = _providers[type]!;
    providers[scheme] = provider;
    _waiting[type]!.remove(scheme)?.complete(provider);
    return () {
      if (identical(providers[scheme], provider)) providers.remove(scheme);
    };
  }

  /// Whether [scheme] has a provider of [type].
  bool hasProvider(String scheme, int type) =>
      _providers[type]!.containsKey(scheme);

  /// `fileSearch`.
  Future<SearchComplete> fileSearch(
    Map<String, Object?> query, [
    CancellationToken token = CancellationToken.none,
  ]) => _search(query, null, token);

  /// `textSearch`: [onProgress] gets each file's matches.
  Future<SearchComplete> textSearch(
    Map<String, Object?> query, [
    CancellationToken token = CancellationToken.none,
    void Function(Map<String, Object?> match)? onProgress,
  ]) => _search(query, onProgress, token);

  Future<SearchComplete> _search(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  ) async {
    if (token.isCancellationRequested) throw const CancellationException();
    final type = (query['type']! as num).toInt();
    final byScheme = <String, List<Object?>>{};
    for (final fq in (query['folderQueries'] as List?) ?? const []) {
      final folder = VsUri.tryRevive((fq as Map)['folder']);
      if (folder == null) continue;
      (byScheme[folder.scheme] ??= []).add(fq);
    }
    for (final extra in (query['extraFileResources'] as List?) ?? const []) {
      final uri = VsUri.tryRevive(extra);
      if (uri != null) byScheme.putIfAbsent(uri.scheme, () => []);
    }
    final providers = _providers[type]!;
    final someSchemeHasProvider = byScheme.keys.any(providers.containsKey);
    final searches = <Future<SearchComplete>>[];
    for (final MapEntry(key: scheme, value: folderQueries) in byScheme.entries) {
      if (query['onlyFileScheme'] == true && scheme != 'file') continue;
      var provider = providers[scheme];
      if (provider == null) {
        if (someSchemeHasProvider) continue;
        provider = await _waitForProvider(type, scheme, token);
      }
      final oneSchemeQuery = {...query, 'folderQueries': folderQueries};
      searches.add(
        type == QueryType.file
            ? provider.fileSearch(oneSchemeQuery, token)
            : provider.textSearch(oneSchemeQuery, onProgress, token),
      );
    }
    final completes = await Future.wait(searches);
    if (token.isCancellationRequested) throw const CancellationException();
    return SearchComplete(
      results: [for (final c in completes) ...c.results],
      limitHit: completes.any((c) => c.limitHit),
      messages: [for (final c in completes) ...c.messages],
    );
  }

  Future<SearchResultProvider> _waitForProvider(
    int type,
    String scheme,
    CancellationToken token,
  ) {
    final completer = _waiting[type]!.putIfAbsent(scheme, Completer.new);
    return Future.any([
      completer.future,
      token.whenCancelled.then<SearchResultProvider>(
        (_) => throw const CancellationException(),
      ),
    ]);
  }

  /// `clearCache`.
  Future<void> clearCache(String cacheKey) async {
    await Future.wait([
      for (final p in {
        ..._providers[QueryType.file]!.values,
        ..._providers[QueryType.text]!.values,
      })
        p.clearCache(cacheKey),
    ]);
  }
}
