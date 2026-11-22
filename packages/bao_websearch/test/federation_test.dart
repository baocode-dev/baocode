import 'dart:async';
import 'dart:io';

import 'package:bao_websearch/bao_websearch.dart';
import 'package:flutter_test/flutter_test.dart';

SearchHit hit(String url, String engine, String chunk) =>
    SearchHit('title', url, chunk, [engine]);

double rrf(int rank) => 1 / (WebSearch.rrfK + rank + 1);

void main() {
  group('merge', () {
    test('an engine that lists one url twice contributes a single term', () {
      final merged = <String, SearchHit>{};
      merge(merged, 'duckduckgo', [
        hit('https://example.com/p', 'duckduckgo', 'short'),
        hit('https://example.com/p', 'duckduckgo', 'longer snippet'),
      ]);
      final entry = merged['https://example.com/p']!;
      expect(entry.engines, ['duckduckgo']);
      expect(entry.score, rrf(0));
      expect(entry.chunk, 'longer snippet');
    });

    test('two engines that agree on a url still sum both ranks', () {
      final merged = <String, SearchHit>{};
      merge(merged, 'google', [hit('https://example.com/p', 'google', 'a')]);
      merge(merged, 'bing', [
        hit('https://example.com/other', 'bing', 'b'),
        hit('https://example.com/p', 'bing', 'c'),
      ]);
      final entry = merged['https://example.com/p']!;
      expect(entry.engines, ['google', 'bing']);
      expect(entry.score, rrf(0) + rrf(1));
    });

    test('agreement between engines outranks one engine repeating itself', () {
      final merged = <String, SearchHit>{};
      merge(merged, 'duckduckgo', [
        hit('https://example.com/repeated', 'duckduckgo', 'a'),
        hit('https://example.com/repeated', 'duckduckgo', 'b'),
        hit('https://example.com/agreed', 'duckduckgo', 'c'),
      ]);
      merge(merged, 'brave', [hit('https://example.com/agreed', 'brave', 'd')]);
      expect(
        merged['https://example.com/agreed']!.score,
        greaterThan(merged['https://example.com/repeated']!.score),
      );
    });
  });

  group('search', () {
    late HttpServer server;
    late String base;
    final hang = Completer<void>();
    final asked = <String>[];

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((request) async {
        asked.add(request.uri.toString());
        final response = request.response;
        switch (request.uri.path) {
          case '/a':
            response.headers.contentType = ContentType.html;
            response.write('''
<div class="r"><a href="https://one.test/">One</a><p>from a</p></div>
<div class="r"><a href="https://two.test/x">Two</a><p>a two</p></div>
<div class="r"><a href="https://blocked.test/">Blocked</a></div>''');
          case '/b':
            response.headers.contentType = ContentType.html;
            response.write(
              '''
<div class="r"><a href="https://two.test/x?utm_medium=y">Two</a><p>b two, longer</p></div>''',
            );
          case '/broken':
            response.statusCode = 503;
          case '/slow':
            await hang.future;
        }
        await response.close();
      });
    });

    tearDownAll(() async {
      if (!hang.isCompleted) hang.complete();
      await server.close(force: true);
    });

    HtmlEngine engine(String id, String path) => HtmlEngine(
      id,
      '$base$path?q={query}',
      result: 'div.r',
      title: 'a',
      link: 'a',
      snippet: 'p',
    );

    test(
      'merges the engines that answer, leaving out those that fail',
      () async {
        final search = WebSearch(
          engines: [
            engine('a', '/a'),
            engine('b', '/b'),
            engine('broken', '/broken'),
            engine('slow', '/slow'),
          ],
          settle: const Duration(milliseconds: 300),
        );
        final watch = Stopwatch()..start();
        final hits = await search.search(
          'dart isolates',
          blockedDomains: ['blocked.test'],
        );
        expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
        expect(
          [for (final hit in hits) hit.url],
          ['https://two.test/x', 'https://one.test'],
        );
        expect(hits.first.engines, ['a', 'b']);
        expect(hits.first.chunk, 'b two, longer');
        expect(asked, contains('/a?q=dart+isolates'));
      },
    );

    test('keeps to allowed domains, asking with site:', () async {
      asked.clear();
      final hits = await WebSearch(engines: [engine('a', '/a')])
          .search('x', allowedDomains: ['one.test']);
      expect([for (final hit in hits) hit.url], ['https://one.test']);
      expect(asked.single, '/a?q=x+site%3Aone.test');
    });

    test('fails when no engine has results', () async {
      await expectLater(
        WebSearch(engines: [engine('broken', '/broken')]).search('x'),
        throwsA(isA<SearchException>()),
      );
      await expectLater(
        WebSearch(engines: [engine('a', '/a')]).search('  '),
        throwsA(isA<SearchException>()),
      );
    });
  });
}
