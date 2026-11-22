// Searches the web for real, each engine on its own then all merged:
// which engines answer from here, and what the search gives.
//
//   dart run packages/bao_websearch/tool/live_search.dart "dart 3.10 release"
//
// Goes through the proxy in HTTPS_PROXY / HTTP_PROXY, if set.
import 'dart:io';

import 'package:bao_websearch/bao_websearch.dart';

Future<void> main(List<String> args) async {
  final query = args.isEmpty ? 'flutter impeller' : args.join(' ');
  Future<HttpClient> client() async => HttpClient()
    ..findProxy = (url) => HttpClient.findProxyFromEnvironment(
      url,
      environment: Platform.environment,
    );
  for (final engine in builtInEngines) {
    final watch = Stopwatch()..start();
    try {
      final hits = await WebSearch(
        engines: [engine],
        client: client,
      ).search(query);
      stdout.writeln(
        '${engine.id.padRight(14)} ${hits.length} results '
        '${watch.elapsedMilliseconds}ms  ${hits.first.url}',
      );
    } on Object catch (error) {
      stdout.writeln(
        '${engine.id.padRight(14)} -          '
        '${watch.elapsedMilliseconds}ms  $error',
      );
    }
  }
  final watch = Stopwatch()..start();
  final hits = await WebSearch(client: client).search(query);
  stdout
    ..writeln('\nAll engines: ${hits.length} in ${watch.elapsedMilliseconds}ms')
    ..writeln(searchResultsText(hits));
}
