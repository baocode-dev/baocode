// HTTP for the gallery: GET requests that follow redirects (Open VSX
// serves files from another host) and can be cancelled. An interface, so
// tests answer from recorded responses.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../../base/cancellation.dart'
    show CancellationException, CancellationToken;

/// A response: its status and body, read once.
class GalleryResponse {
  GalleryResponse({
    required this.statusCode,
    required this.body,
    this.contentLength,
    this.url,
  });

  /// A response whose body is [bytes].
  factory GalleryResponse.bytes(int statusCode, List<int> bytes, {Uri? url}) =>
      GalleryResponse(
        statusCode: statusCode,
        body: Stream.value(bytes),
        contentLength: bytes.length,
        url: url,
      );

  final int statusCode;
  final Stream<List<int>> body;

  /// When the server said (null or negative when not).
  final int? contentLength;

  /// Where it came from, after redirects.
  final Uri? url;

  bool get ok => statusCode >= 200 && statusCode < 300;

  Future<Uint8List> bytes() async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in body) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// Discards the body.
  Future<void> drain() => body.drain<void>();
}

/// Sends GET requests.
abstract interface class GalleryHttp {
  /// GETs [url]; throws [CancellationException] once [cancel] is, also
  /// while the body streams, and [GalleryNetworkException] when there is no
  /// answer.
  Future<GalleryResponse> get(
    Uri url, {
    CancellationToken cancel = CancellationToken.none,
  });
}

/// No answer: no network, a refused connection, a timeout.
class GalleryNetworkException implements Exception {
  const GalleryNetworkException(this.url, this.message);

  final Uri url;
  final String message;

  @override
  String toString() => 'GalleryNetworkException($url): $message';
}

/// [GalleryHttp] with dart:io's client: no proxy (the gallery is fetched
/// directly, as the runtime download does), up to 5 redirects, a
/// `User-Agent` of the app's.
class IoGalleryHttp implements GalleryHttp {
  IoGalleryHttp({
    String userAgent = 'BaoCode',
    Duration connectionTimeout = const Duration(seconds: 20),
    this.stallTimeout = const Duration(seconds: 60),
  }) : _client = HttpClient()
         ..findProxy = ((_) => 'DIRECT')
         ..userAgent = userAgent
         ..connectionTimeout = connectionTimeout
         ..idleTimeout = const Duration(seconds: 15);

  final HttpClient _client;

  /// How long a response may stall before it fails.
  final Duration stallTimeout;

  @override
  Future<GalleryResponse> get(
    Uri url, {
    CancellationToken cancel = CancellationToken.none,
  }) async {
    if (cancel.isCancellationRequested) throw const CancellationException();
    HttpClientRequest? request;
    var done = false;
    unawaited(
      cancel.whenCancelled.then((_) {
        if (!done) request?.abort(const CancellationException());
      }),
    );
    try {
      request = await _client.getUrl(url);
      if (cancel.isCancellationRequested) {
        request.abort(const CancellationException());
        throw const CancellationException();
      }
      request
        ..followRedirects = true
        ..maxRedirects = 5
        ..headers.set(HttpHeaders.acceptHeader, 'application/json, */*');
      final response = await request.close();
      final body = response
          .timeout(
            stallTimeout,
            onTimeout: (sink) => sink.addError(
              GalleryNetworkException(url, 'The response stalled'),
            ),
          )
          .handleError(
            (Object error) => throw cancel.isCancellationRequested
                ? const CancellationException()
                : GalleryNetworkException(url, '$error'),
            test: (error) =>
                error is! GalleryNetworkException &&
                error is! CancellationException,
          );
      return GalleryResponse(
        statusCode: response.statusCode,
        body: _untilDone(body, () => done = true),
        contentLength: response.contentLength,
        url: response.redirects.isEmpty
            ? url
            : response.redirects.last.location,
      );
    } on CancellationException {
      done = true;
      rethrow;
    } on SocketException catch (error) {
      done = true;
      if (cancel.isCancellationRequested) throw const CancellationException();
      throw GalleryNetworkException(url, error.message);
    } on HttpException catch (error) {
      done = true;
      if (cancel.isCancellationRequested) throw const CancellationException();
      throw GalleryNetworkException(url, error.message);
    } on HandshakeException catch (error) {
      done = true;
      throw GalleryNetworkException(url, error.message);
    } on TimeoutException catch (error) {
      done = true;
      throw GalleryNetworkException(url, error.message ?? 'Timed out');
    }
  }

  void close() => _client.close(force: true);
}

Stream<List<int>> _untilDone(Stream<List<int>> body, void Function() done) =>
    body.transform(
      StreamTransformer.fromHandlers(
        handleDone: (sink) {
          done();
          sink.close();
        },
      ),
    );
