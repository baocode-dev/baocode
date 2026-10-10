// A GalleryHttp answering from responses recorded from Open VSX
// (test/fixtures/extensions/openvsx/index.json), and from ones a test adds.

import 'dart:convert';
import 'dart:io';

import 'package:baocode/base/cancellation.dart';
import 'package:baocode/extensions/gallery/gallery_http.dart';

const openVsxFixtures = 'test/fixtures/extensions/openvsx';

class FixtureHttp implements GalleryHttp {
  FixtureHttp({bool recorded = true}) {
    if (!recorded) return;
    final index = jsonDecode(
      File('$openVsxFixtures/index.json').readAsStringSync(),
    ) as Map<String, Object?>;
    for (final response in index['responses']! as List) {
      final entry = response as Map<String, Object?>;
      final file = File('$openVsxFixtures/${entry['file']}');
      add(
        entry['url']! as String,
        file.existsSync() ? file.readAsBytesSync() : const [],
        status: entry['status']! as int,
      );
    }
  }

  final Map<String, ({int status, List<int> body})> _responses = {};

  /// The URLs asked for, as keys of [add].
  final List<String> requests = [];

  /// Answers [url] (a path and query, or a whole URL) with [body].
  void add(String url, List<int> body, {int status = 200}) =>
      _responses[_key(Uri.parse(url))] = (status: status, body: body);

  void addJson(String url, Object? json, {int status = 200}) =>
      add(url, utf8.encode(jsonEncode(json)), status: status);

  @override
  Future<GalleryResponse> get(
    Uri url, {
    CancellationToken cancel = CancellationToken.none,
  }) async {
    if (cancel.isCancellationRequested) throw const CancellationException();
    final key = _key(url);
    requests.add(key);
    final response = _responses[key];
    if (response == null) {
      throw StateError('No recorded response for $key');
    }
    return GalleryResponse.bytes(response.status, response.body, url: url);
  }

  /// The path and the query, its parameters sorted.
  static String _key(Uri url) {
    final params = url.queryParameters.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final query = params.isEmpty
        ? ''
        : '?${params.map((e) => '${e.key}=${e.value}').join('&')}';
    return '${url.path}$query';
  }
}
