import 'dart:convert';
import 'dart:io';

/// [url]'s text, through the app's proxy as every [HttpClient]; null when
/// it does not answer 200 in time.
Future<String?> fetchCodexFeed(Uri url) async {
  const timeout = Duration(seconds: 8);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  try {
    final request = await client.getUrl(url).timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != HttpStatus.ok) {
      await response.drain<void>();
      return null;
    }
    return await response.transform(utf8.decoder).join().timeout(timeout);
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}
