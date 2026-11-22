import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;

/// One result of a search: on several engines' lists when they agree
/// ([engines]), ranked by [score] (see `WebSearch`).
class SearchHit {
  SearchHit(this.title, this.url, this.chunk, this.engines);

  final String title;

  /// Canonical ([canonicalUrl]): the same page from two engines is one.
  final String url;

  /// What the engine shows of the page: the longest of those that list it.
  String chunk;

  final List<String> engines;
  double score = 0;

  @override
  String toString() => 'SearchHit($title, $url)';
}

/// A search engine, its results read from the page (or JSON) its search
/// answers with.
sealed class SearchEngine {
  const SearchEngine(this.id, this.url);

  final String id;

  /// The search's URL, `{query}` where the query goes.
  final String url;

  /// What is asked for (the `Accept` header).
  String get accept;

  Uri searchUrl(String query) =>
      Uri.parse(url.replaceAll('{query}', Uri.encodeQueryComponent(query)));

  /// The first 10 results in [body], the answer from [responseUrl].
  /// Throws [FormatException] when it cannot be read.
  List<SearchHit> parse(String body, Uri responseUrl);
}

/// An engine answering with an HTML page: each [result] element holds a
/// result, its [title], its [link] (an `href`) and its [snippet], each
/// found by a CSS selector within it.
class HtmlEngine extends SearchEngine {
  const HtmlEngine(
    super.id,
    super.url, {
    required this.result,
    required this.title,
    required this.link,
    required this.snippet,
  });

  final String result;
  final String title;
  final String link;
  final String snippet;

  @override
  String get accept => 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.1';

  @override
  List<SearchHit> parse(String body, Uri responseUrl) {
    final document = html.parse(body);
    final List<Element> items;
    try {
      items = document.querySelectorAll(result);
    } on Object catch (error) {
      throw FormatException('invalid selector: $result ($error)');
    }
    final hits = <SearchHit>[];
    for (final item in items) {
      if (_item(item, responseUrl) case final hit?) hits.add(hit);
      if (hits.length == 10) break;
    }
    return hits;
  }

  SearchHit? _item(Element item, Uri responseUrl) {
    final titled = item.querySelector(title);
    if (titled == null) return null;
    final name = _text(titled);
    final href =
        item.querySelector(link)?.attributes['href'] ?? item.attributes['href'];
    if (href == null) return null;
    final url = resultUrl(responseUrl, href);
    if (url == null) return null;
    final chunk = switch (item.querySelector(snippet)) {
      final element? => _text(element),
      null => '',
    };
    return name.isEmpty ? null : SearchHit(name, url, chunk, [id]);
  }
}

/// An engine answering with JSON: [items], a JSON Pointer (RFC 6901), is
/// the list of results; [title], [link] and [snippet] are pointers within
/// each. A [linkTemplate] makes the link of what [link] gives (`{value}`).
class JsonEngine extends SearchEngine {
  const JsonEngine(
    super.id,
    super.url, {
    required this.items,
    required this.title,
    required this.link,
    required this.snippet,
    this.linkTemplate,
  });

  final String items;
  final String title;
  final String link;
  final String snippet;
  final String? linkTemplate;

  @override
  String get accept => 'application/json';

  @override
  List<SearchHit> parse(String body, Uri responseUrl) {
    final list = jsonPointer(jsonDecode(body), items);
    if (list is! List) throw FormatException('missing result array: $items');
    final hits = <SearchHit>[];
    for (final item in list) {
      if (_item(item) case final hit?) hits.add(hit);
      if (hits.length == 10) break;
    }
    return hits;
  }

  SearchHit? _item(Object? item) {
    final titled = jsonPointer(item, title);
    if (titled == null) return null;
    final name = plainText(_jsonText(titled));
    final linked = jsonPointer(item, link);
    if (linked == null) return null;
    var href = _jsonText(linked);
    if (linkTemplate case final template?) {
      href = template.replaceAll('{value}', Uri.encodeQueryComponent(href));
    }
    final url = canonicalUrl(href);
    if (url == null) return null;
    final chunk = switch (jsonPointer(item, snippet)) {
      final value? => plainText(_jsonText(value)),
      null => '',
    };
    return name.isEmpty ? null : SearchHit(name, url, chunk, [id]);
  }
}

/// What [pointer] (RFC 6901) points at in [value], or null.
Object? jsonPointer(Object? value, String pointer) {
  if (pointer.isEmpty) return value;
  if (!pointer.startsWith('/')) return null;
  for (final raw in pointer.substring(1).split('/')) {
    final key = raw.replaceAll('~1', '/').replaceAll('~0', '~');
    value = switch (value) {
      Map() => value[key],
      List() => switch (int.tryParse(key)) {
        final i? when i >= 0 && i < value.length => value[i],
        _ => null,
      },
      _ => null,
    };
    if (value == null) return null;
  }
  return value;
}

String _jsonText(Object value) => switch (value) {
  String() => value,
  num() => '$value',
  _ => '',
};

final _space = RegExp(r'\s+');

String _text(Element element) => element.text.trim().replaceAll(_space, ' ');

/// [value], a fragment of HTML (a snippet's highlights), as its text.
String plainText(String value) =>
    html.parseFragment(value).text?.trim().replaceAll(_space, ' ') ?? '';

/// [value] canonical, or null when it is not an http(s) URL.
String? canonicalUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri == null || !uri.hasScheme ? null : _canonicalize(uri);
}

/// [href], on a page at [base], canonical.
String? resultUrl(Uri base, String href) {
  try {
    return _canonicalize(base.resolve(href));
  } on FormatException {
    return null;
  }
}

const _tracking = {'gclid', 'fbclid', 'mc_cid', 'mc_eid'};

/// Where an engine's link to a result goes (its redirect undone), without
/// its fragment, its trackers' parameters or a trailing `/`.
String? _canonicalize(Uri url) {
  if (_redirectedTarget(url) case final target?) url = target;
  if (url.scheme != 'http' && url.scheme != 'https') return null;
  if (url.host.isEmpty) return null;
  final kept = [
    for (final (key, value) in _queryPairs(url.query))
      if (!key.startsWith('utm_') && !_tracking.contains(key)) (key, value),
  ];
  final out = Uri(
    scheme: url.scheme,
    userInfo: url.userInfo.isEmpty ? null : url.userInfo,
    host: url.host,
    port: url.hasPort ? url.port : null,
    path: url.path,
    query: kept.isEmpty
        ? null
        : [
            for (final (key, value) in kept)
              '${Uri.encodeQueryComponent(key)}='
                  '${Uri.encodeQueryComponent(value)}',
          ].join('&'),
  );
  var text = out.toString();
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// [query]'s pairs, in order, repeats kept.
List<(String, String)> _queryPairs(String query) => [
  for (final pair in query.split('&'))
    if (pair.isNotEmpty)
      switch (pair.indexOf('=')) {
        -1 => (_decode(pair), ''),
        final i => (
          _decode(pair.substring(0, i)),
          _decode(pair.substring(i + 1)),
        ),
      },
];

String _decode(String component) {
  try {
    return Uri.decodeQueryComponent(component);
  } on ArgumentError {
    return component;
  }
}

String? _param(Uri url, String name) {
  for (final (key, value) in _queryPairs(url.query)) {
    if (key == name) return value;
  }
  return null;
}

/// The result an engine's own redirect ([url]) goes to: Bing's `/ck/a`,
/// DuckDuckGo's `uddg`, Google's `/url`.
Uri? _redirectedTarget(Uri url) {
  final host = url.host;
  String? target;
  if (host.contains('bing.com') && url.path == '/ck/a') {
    final value = _param(url, 'u');
    if (value == null || !value.startsWith('a1')) return null;
    try {
      target = utf8.decode(base64Url.decode(_padded(value.substring(2))));
    } on FormatException {
      return null;
    }
  } else if (host.contains('duckduckgo.com')) {
    target = _param(url, 'uddg');
  } else if (host.contains('google.') && url.path == '/url') {
    target = _param(url, 'q');
  }
  if (target == null) return null;
  final parsed = Uri.tryParse(target);
  return parsed != null && parsed.hasScheme ? parsed : null;
}

String _padded(String base64) =>
    base64.padRight(base64.length + (4 - base64.length % 4) % 4, '=');
