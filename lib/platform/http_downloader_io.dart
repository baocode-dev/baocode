import 'dart:async';
import 'dart:io';

/// Downloads over HTTPS with `dart:io`, following redirects (GitHub
/// release assets redirect to their storage), into a temporary file that
/// is renamed once complete.
class HttpDownloader {
  HttpDownloader({HttpClient Function()? client})
    : _client = client ?? HttpClient.new;

  final HttpClient Function() _client;

  /// Writes [url]'s body to [destination]; [onProgress] gets bytes so far
  /// and the total when known. Throws on failure (an HTTP error status
  /// included).
  Future<void> download(
    Uri url,
    String destination, {
    void Function(int received, int? total)? onProgress,
  }) async {
    final client = _client()..userAgent = 'baocode-ide';
    final partial = File('$destination.part');
    try {
      final request = await client.getUrl(url);
      request.followRedirects = true;
      request.maxRedirects = 10;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw HttpException('HTTP ${response.statusCode}', uri: url);
      }
      final total = response.contentLength >= 0 ? response.contentLength : null;
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
      await partial.rename(destination);
    } finally {
      client.close(force: true);
      if (await partial.exists()) await partial.delete();
    }
  }
}
