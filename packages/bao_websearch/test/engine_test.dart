import 'package:bao_websearch/bao_websearch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('canonical URLs', () {
    test('drop the fragment, trackers and a trailing slash', () {
      expect(
        canonicalUrl('https://example.com/a/?utm_source=x&id=3&gclid=y#top'),
        'https://example.com/a/?id=3',
      );
      expect(canonicalUrl('https://example.com/a/#x'), 'https://example.com/a');
      expect(canonicalUrl('https://example.com/'), 'https://example.com');
    });

    test('only http(s)', () {
      expect(canonicalUrl('ftp://example.com/x'), isNull);
      expect(canonicalUrl('/relative'), isNull);
    });

    test('undo the engines\' own redirects', () {
      final bing = Uri.parse('https://www.bing.com/search?q=x');
      // `a1` and the target, base64url without padding.
      expect(
        resultUrl(
          bing,
          '/ck/a?!&&p=1&u=a1aHR0cHM6Ly9kYXJ0LmRldi9ndWlkZXM&ntb=1',
        ),
        'https://dart.dev/guides',
      );
      final ddg = Uri.parse('https://html.duckduckgo.com/html/?q=x');
      expect(
        resultUrl(
          ddg,
          '//duckduckgo.com/l/?uddg=https%3A%2F%2Fpub.dev%2Fpackages%2Fhtml&rut=1',
        ),
        'https://pub.dev/packages/html',
      );
      final google = Uri.parse('https://www.google.com/search?q=x');
      expect(
        resultUrl(google, '/url?q=https://flutter.dev/&sa=U'),
        'https://flutter.dev',
      );
    });
  });

  test('an HTML engine reads its results by its selectors', () {
    const engine = HtmlEngine(
      'test',
      'https://search.test/?q={query}',
      result: 'li.r',
      title: 'h2',
      link: 'h2 a',
      snippet: '.s',
    );
    final hits = engine.parse('''
<ul>
  <li class="r"><h2><a href="/one">One   <b>title</b></a></h2><p class="s">First
    snippet</p></li>
  <li class="r"><h2><a href="https://two.test/page">Two</a></h2></li>
  <li class="r"><h2></h2><a href="/no-title">x</a></li>
  <li class="r"><h2>No link</h2></li>
</ul>''', Uri.parse('https://search.test/?q=x'));
    expect([for (final hit in hits) hit.title], ['One title', 'Two']);
    expect(hits[0].url, 'https://search.test/one');
    expect(hits[0].chunk, 'First snippet');
    expect(hits[0].engines, ['test']);
    expect(hits[1].chunk, '');
  });

  test('the catalog\'s selectors all parse', () {
    for (final engine in builtInEngines.whereType<HtmlEngine>()) {
      expect(
        () => engine.parse('<html></html>', Uri.parse(engine.url)),
        returnsNormally,
        reason: engine.id,
      );
    }
  });

  test('a JSON engine reads its results by JSON pointers', () {
    final wikipedia = builtInEngines.firstWhere((e) => e.id == 'wikipedia');
    final hits = wikipedia.parse('''
{"query": {"search": [
  {"title": "Dart (programming language)", "pageid": 33602021,
   "snippet": "<span class=\\"searchmatch\\">Dart</span> is a language"},
  {"pageid": 1}
]}}''', Uri.parse('https://en.wikipedia.org/w/api.php'));
    expect(hits, hasLength(1));
    expect(hits.single.title, 'Dart (programming language)');
    expect(hits.single.url, 'https://en.wikipedia.org/?curid=33602021');
    expect(hits.single.chunk, 'Dart is a language');
    expect(
      () => wikipedia.parse('{}', Uri.parse('https://en.wikipedia.org')),
      throwsFormatException,
    );
  });

  test('JSON pointers', () {
    final value = {
      'a': [
        {'b/c': 1, 'd~e': 2},
      ],
    };
    expect(jsonPointer(value, '/a/0/b~1c'), 1);
    expect(jsonPointer(value, '/a/0/d~0e'), 2);
    expect(jsonPointer(value, '/a/1'), isNull);
    expect(jsonPointer(value, ''), value);
  });
}
