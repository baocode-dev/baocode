/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// Ported from VS Code 08d4889f9ec4a1685d257b9b95de036c8e1ce1e5 (1.135.0):
// src/vs/workbench/api/browser/mainThreadSearch.ts (`MainThreadSearch`,
// `SearchOperation`, `RemoteSearchProvider`).
//
// Deviations:
// - No `searchContext.hasAIResultProvider` context key and no telemetry
//   (`$handleTelemetry` is dropped: the app sends none).
// - A provider's scheme goes through the connection's URI transformer, as
//   its URIs do: this machine's host in a remote window registers `file`,
//   which there is `vscode-local` (upstream's extension host transforms it
//   itself; ours knows no authority), not the remote host's `file`.

import 'dart:async';

import 'package:bao_exthost/bao_exthost.dart';

import '../search/query_builder.dart' show QueryType;
import '../search/search_service.dart';
import 'main_thread_context.dart';

final class MainThreadSearch extends MainThreadSearchUnsupported {
  MainThreadSearch({required RpcProtocol rpc, required this.search})
    : _proxy = ExtHostSearchProxy(rpc),
      _rpc = rpc {
    // The extension host's own ripgrep providers for `file`.
    unawaited(_proxy.$enableExtensionHostSearch().catchError((Object _) {}));
  }

  static RpcActor customer(MainThreadContext c) {
    final actor = MainThreadSearch(rpc: c.rpc, search: c.service<SearchService>());
    c.onDispose(actor.dispose);
    return MainThreadSearchActor(actor);
  }

  final ExtHostSearchProxy _proxy;
  final RpcProtocol _rpc;
  final SearchService search;
  final _providers = <int, RemoteSearchProvider>{};
  final _aiProviders = <int>{};

  /// Whether an extension provides AI text search results.
  bool get hasAIResultProvider => _aiProviders.isNotEmpty;

  void dispose() {
    for (final p in _providers.values) {
      p.dispose();
    }
    _providers.clear();
    _aiProviders.clear();
  }

  void _register(num handle, String scheme, int type) {
    final h = handle.toInt();
    _providers.remove(h)?.dispose();
    _providers[h] = RemoteSearchProvider(
      search,
      type,
      _rpc.transformIncomingScheme(scheme),
      h,
      _proxy,
    );
  }

  @override
  void $registerTextSearchProvider(num handle, String scheme) =>
      _register(handle, scheme, QueryType.text);

  @override
  void $registerAITextSearchProvider(num handle, String scheme) {
    _aiProviders.add(handle.toInt());
    _register(handle, scheme, QueryType.aiText);
  }

  @override
  void $registerFileSearchProvider(num handle, String scheme) =>
      _register(handle, scheme, QueryType.file);

  @override
  void $unregisterProvider(num handle) {
    _providers.remove(handle.toInt())?.dispose();
    _aiProviders.remove(handle.toInt());
  }

  RemoteSearchProvider _provider(num handle) =>
      _providers[handle.toInt()] ??
      (throw StateError('Got result for unknown provider'));

  @override
  void $handleFileMatch(num handle, num session, List<VsUri> data) =>
      _provider(handle).handleFindMatch(session.toInt(), [
        for (final uri in data) {'resource': uri.toJson()},
      ]);

  @override
  void $handleTextMatch(
    num handle,
    num session,
    List<Map<String, Object?>> data,
  ) => _provider(handle).handleFindMatch(session.toInt(), data);

  @override
  void $handleKeywordResult(
    num handle,
    num session,
    Map<String, Object?> data,
  ) => _provider(handle).handleKeywordResult(session.toInt(), data);

  @override
  void $handleTelemetry(String eventName, Object? data) {}
}

/// A search in progress (`SearchOperation`): its matches by resource.
final class _SearchOperation {
  _SearchOperation(this.id, this.progress);

  final int id;
  final void Function(Map<String, Object?> match)? progress;
  final matches = <String, Map<String, Object?>>{};
  final keywords = <Map<String, Object?>>[];

  void addMatch(Map<String, Object?> match) {
    final key = '${VsUri.tryRevive(match['resource'])}';
    final existing = matches[key];
    if (existing != null) {
      final results = existing['results'];
      final more = match['results'];
      if (results is List && more is List) {
        existing['results'] = [...results, ...more];
      }
    } else {
      matches[key] = {...match};
    }
    progress?.call(match);
  }
}

/// An extension's search provider of one scheme (`RemoteSearchProvider`).
final class RemoteSearchProvider implements SearchResultProvider {
  RemoteSearchProvider(
    SearchService search,
    this.type,
    this.scheme,
    this.handle,
    this._proxy,
  ) {
    _unregister = search.registerProvider(scheme, type, this);
  }

  final int type;
  final String scheme;
  final int handle;
  final ExtHostSearchProxy _proxy;
  late final void Function() _unregister;
  final _searches = <int, _SearchOperation>{};
  static var _idPool = 0;
  String? _aiName;

  /// `getAIName`.
  Future<String?> getAIName() async => _aiName ??= await _proxy.$getAIName(handle);

  void dispose() => _unregister();

  @override
  Future<SearchComplete> fileSearch(
    Map<String, Object?> query,
    CancellationToken token,
  ) => _doSearch(query, null, token);

  @override
  Future<SearchComplete> textSearch(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  ) => _doSearch(query, onProgress, token);

  Future<SearchComplete> _doSearch(
    Map<String, Object?> query,
    void Function(Map<String, Object?> match)? onProgress,
    CancellationToken token,
  ) async {
    if ((query['folderQueries'] as List?)?.isEmpty ?? true) {
      throw StateError('Empty folderQueries');
    }
    final search = _SearchOperation(++_idPool, onProgress);
    _searches[search.id] = search;
    try {
      final type = (query['type']! as num).toInt();
      final result = await switch (type) {
        QueryType.file => _proxy.$provideFileSearchResults(
          handle,
          search.id,
          query,
          token: token,
        ),
        QueryType.text => _proxy.$provideTextSearchResults(
          handle,
          search.id,
          query,
          token: token,
        ),
        _ => _proxy.$provideAITextSearchResults(
          handle,
          search.id,
          query,
          token: token,
        ),
      };
      return SearchComplete(
        results: search.matches.values.toList(),
        limitHit: result['limitHit'] == true,
        messages: (result['messages'] as List?) ?? const [],
        stats: result['stats'],
      );
    } finally {
      _searches.remove(search.id);
    }
  }

  @override
  Future<void> clearCache(String cacheKey) => _proxy.$clearCache(cacheKey);

  /// `handleFindMatch`: file matches (`{resource}`) or text ones
  /// (`IRawFileMatch2`) of [session].
  void handleFindMatch(int session, List<Map<String, Object?>> matches) {
    final search = _searches[session];
    if (search == null) return;
    for (final match in matches) {
      search.addMatch(match);
    }
  }

  void handleKeywordResult(int session, Map<String, Object?> keyword) {
    final search = _searches[session];
    if (search == null) return;
    search.keywords.add(keyword);
    search.progress?.call(keyword);
  }
}
