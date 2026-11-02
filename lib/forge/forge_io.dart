import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import 'forge_address.dart';
import 'forge_api.dart';

/// [certificate]'s SHA-256, in hex: what the user confirms, and what is
/// kept.
String _fingerprint(X509Certificate certificate) =>
    sha256.convert(certificate.der).toString();

/// [ForgeHttp] with dart:io's client (through the app's proxy, as every
/// client is: see NetworkProxyOverrides).
class IoForgeHttp implements ForgeHttp, ForgeCertificateTrust {
  late final HttpClient _client = HttpClient()
    ..userAgent = 'BaoCode'
    ..connectionTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = _isTrusted;

  /// The SHA-256 of the certificate trusted for each host: a self-signed
  /// one, or a private CA's, that the user confirmed.
  final Map<String, String> _trusted = {};

  @override
  void trustCertificate(String host, String sha256) =>
      _trusted[host.toLowerCase()] = sha256.toLowerCase();

  /// Whether [certificate] is the one trusted for [host], and only then:
  /// every other certificate is checked as usual.
  bool _isTrusted(X509Certificate certificate, String host, int port) =>
      _trusted[_authority(host, port)] == _fingerprint(certificate);

  static String _authority(String host, int port) {
    final name = host.toLowerCase();
    if (port == 443) return name;
    return '${name.contains(':') ? '[$name]' : name}:$port';
  }

  @override
  Future<ForgeResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    Object? json,
    Map<String, String>? form,
    List<int>? bytes,
  }) async {
    try {
      final request = await _client.openUrl(method, url);
      headers.forEach(request.headers.set);
      if (form != null) {
        request.headers.contentType = ContentType(
          'application',
          'x-www-form-urlencoded',
          charset: 'utf-8',
        );
        request.write(Uri(queryParameters: form).query);
      } else if (json != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(json));
      } else if (bytes != null) {
        request.contentLength = bytes.length;
        request.add(bytes);
      }
      // A picture uploaded may take its time.
      final response = await request.close().timeout(
        Duration(seconds: bytes == null ? 30 : 120),
      );
      final body = await response
          .transform(const Utf8Decoder(allowMalformed: true))
          .join()
          .timeout(const Duration(seconds: 30));
      return ForgeResponse(response.statusCode, body);
    } on HandshakeException catch (error) {
      throw await _certificateProblem(url) ?? ForgeException('$error');
    } on TlsException catch (error) {
      throw await _certificateProblem(url) ?? ForgeException('$error');
    } on TimeoutException {
      throw ForgeException('$url did not answer.');
    } on IOException catch (error) {
      throw ForgeException('$error');
    }
  }

  /// What [url]'s server presented when its certificate was refused: for
  /// the user to confirm. Null when nothing was captured (the connection
  /// failed for another reason).
  Future<ForgeException?> _certificateProblem(Uri url) async {
    if (!url.isScheme('https')) return null;
    X509Certificate? certificate;
    try {
      final socket = await SecureSocket.connect(
        url.host,
        url.port,
        onBadCertificate: (refused) {
          certificate = refused;
          return false;
        },
      ).timeout(const Duration(seconds: 10));
      socket.destroy();
    } on Object {
      // Refused, as asked; what it presented is in [certificate].
    }
    final found = certificate;
    if (found == null) return null;
    final host = forgeAuthority(url);
    final fingerprint = _fingerprint(found);
    return ForgeCertificateException(
      _trusted.containsKey(host)
          ? 'The certificate of $host has changed since it was trusted.'
          : 'The certificate of $host is not trusted.',
      host: host,
      sha256: fingerprint,
      subject: found.subject,
      issuer: found.issuer,
    );
  }
}

/// The URLs of the Git remotes of the repository [folder] is in, `origin`
/// first; none for none (or no Git).
Future<List<String>> gitRemoteUrls(String folder) async {
  try {
    final result = await Process.run('git', [
      'config',
      '--get-regexp',
      r'^remote\..*\.url$',
    ], workingDirectory: folder).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return const [];
    final remotes = <(String, String)>[
      for (final line in const LineSplitter().convert('${result.stdout}'))
        if (RegExp(r'^remote\.(.+)\.url\s+(.+)$').firstMatch(line)
            case final match?)
          (match[1]!, match[2]!.trim()),
    ];
    remotes.sort((a, b) => a.$1 == 'origin' ? -1 : (b.$1 == 'origin' ? 1 : 0));
    return [for (final (_, url) in remotes) url];
  } on Object {
    return const [];
  }
}
