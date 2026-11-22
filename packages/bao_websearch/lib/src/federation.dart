import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'catalog.dart';
import 'engine.dart';

/// A search that failed: no engine had a result.
class SearchException implements Exception {
  const SearchException(this.message);

  final String message;

  @override
  String toString() => 'web search failed: $message';
}

/// Searches the web by asking every engine at once and merging their
/// lists by reciprocal rank fusion: a page high on several lists comes
/// first.
///
/// An engine that fails (refuses, times out, has changed its page) is left
/// out; the search fails only when none answers. Pages are parsed off this
/// isolate, so a search does not hold up the one it is made on.
class WebSearch {
  WebSearch({
    List<SearchEngine>? engines,
    this._client,
    this.timeout = const Duration(seconds: 12),
    this.settle = const Duration(seconds: 3),
    this.userAgent = defaultUserAgent,
  }) : engines = engines ?? builtInEngines;

  static const defaultUserAgent =
      'Mozilla/5.0 (compatible; BaoCode/1.0; +https://baocode.dev)';
  static const rrfK = 60.0;
  static const maxResults = 15;
  static const maxBytes = 5 * 1024 * 1024;

  final List<SearchEngine> engines;

  /// The client a search's requests go by (its proxy, the roots it
  /// trusts): Dart's own without it.
  final Future<HttpClient> Function()? _client;

  /// How long an engine is waited for.
  final Duration timeout;

  /// How long the others are waited for once one has results: the slowest
  /// engine does not hold up a search the rest have answered.
  final Duration settle;

  final String userAgent;

  List<String> get engineIds => [for (final engine in engines) engine.id];

  /// The best results for [query], at most [maxResults]: with
  /// [allowedDomains], only from those sites (each engine told so with
  /// `site:`), with [blockedDomains], none from those.
  Future<List<SearchHit>> search(
    String query, {
    List<String> allowedDomains = const [],
    List<String> blockedDomains = const [],
  }) async {
    query = query.trim();
    if (query.isEmpty) throw const SearchException('query is empty');
    final asked = allowedDomains.isEmpty
        ? query
        : '$query ${[for (final domain in allowedDomains) 'site:$domain'].join(' OR ')}';
    final client = await (_client?.call() ?? Future.value(HttpClient()));
    client.connectionTimeout ??= timeout;
    final lists = <String, List<SearchHit>>{};
    final failures = <String>[];
    final done = Completer<void>();
    var pending = engines.length;
    Timer? settling;
    void settled() {
      if (!done.isCompleted) done.complete();
    }

    for (final engine in engines) {
      unawaited(
        _ask(client, engine, asked)
            .timeout(timeout)
            .then((hits) {
              if (hits.isEmpty) {
                failures.add(engine.id);
              } else {
                lists[engine.id] = hits;
                settling ??= Timer(settle, settled);
              }
            }, onError: (Object _) => failures.add(engine.id))
            .whenComplete(() {
              if (--pending == 0) settled();
            }),
      );
    }
    if (engines.isEmpty) settled();
    await done.future;
    settling?.cancel();
    // Those still out are let go of.
    client.close(force: true);

    final merged = <String, SearchHit>{};
    // In the engines' order, so that ties break the same way each time.
    for (final engine in engines) {
      if (lists[engine.id] case final hits?) merge(merged, engine.id, hits);
    }
    if (merged.isEmpty) {
      throw SearchException('no results from engines: ${failures.join(', ')}');
    }
    final results =
        merged.values
            .where((hit) => _allowed(hit.url, allowedDomains, blockedDomains))
            .toList()
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            return byScore != 0 ? byScore : a.url.compareTo(b.url);
          });
    return results.length > maxResults
        ? results.sublist(0, maxResults)
        : results;
  }

  Future<List<SearchHit>> _ask(
    HttpClient client,
    SearchEngine engine,
    String query,
  ) async {
    final url = engine.searchUrl(query);
    final request = await client.getUrl(url);
    request.headers
      ..set(HttpHeaders.userAgentHeader, userAgent)
      ..set(HttpHeaders.acceptHeader, engine.accept);
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>().catchError((_) {});
      throw HttpException('HTTP ${response.statusCode}', uri: url);
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) break;
    }
    final at = response.redirects.isEmpty
        ? url
        : url.resolveUri(response.redirects.last.location);
    return _parse(
      engine,
      bytes.takeBytes(),
      response.headers.contentType?.charset,
      at,
    );
  }

  /// [engine]'s results in [bytes], parsed on an isolate of its own: only
  /// what is sent is captured.
  static Future<List<SearchHit>> _parse(
    SearchEngine engine,
    Uint8List bytes,
    String? charset,
    Uri at,
  ) => Isolate.run(() {
    final latin = charset?.toLowerCase();
    final body = latin == 'iso-8859-1' || latin == 'latin1'
        ? latin1.decode(bytes)
        : utf8.decode(bytes, allowMalformed: true);
    return engine.parse(body, at);
  });
}

/// Adds [engine]'s ranked [results] to [merged]: each a term of
/// 1 / ([WebSearch.rrfK] + rank) to its page's score.
void merge(
  Map<String, SearchHit> merged,
  String engine,
  List<SearchHit> results,
) {
  for (final (rank, result) in results.indexed) {
    final score = 1 / (WebSearch.rrfK + rank + 1);
    final existing = merged[result.url];
    if (existing == null) {
      result.score = score;
      merged[result.url] = result;
      continue;
    }
    // Reciprocal Rank Fusion sums one term per ranked list. One engine
    // listing a URL more than once is still one list, so only its best
    // rank counts; a later repeat contributes nothing but its snippet.
    if (!existing.engines.contains(engine)) {
      existing.score += score;
      existing.engines.add(engine);
    }
    if (result.chunk.length > existing.chunk.length) {
      existing.chunk = result.chunk;
    }
  }
}

bool _allowed(String url, List<String> allowed, List<String> blocked) {
  final host = Uri.tryParse(url)?.host.toLowerCase();
  if (host == null) return false;
  bool on(String domain) {
    domain = domain.trim().toLowerCase();
    if (domain.startsWith('*.')) domain = domain.substring(2);
    return host == domain || host.endsWith('.$domain');
  }

  if (allowed.isNotEmpty && !allowed.any(on)) return false;
  return !blocked.any(on);
}
