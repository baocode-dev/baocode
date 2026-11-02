import 'dart:io';

import 'package:baocode/forge/forge_api.dart';
import 'package:baocode/forge/forge_io.dart';
import 'package:flutter_test/flutter_test.dart';

/// The self-signed certificate the server here presents (for localhost and
/// 127.0.0.1), made to be trusted. A fixture, for tests only.
const _certificate = 'test/forge/fixtures/localhost.pem';
const _key = 'test/forge/fixtures/localhost.key';

Future<void> _answer(HttpRequest request) async {
  request.response
    ..statusCode = 200
    ..write('ok');
  await request.response.close();
}

Future<HttpServer> _serve({required bool secure}) async {
  final server = secure
      ? await HttpServer.bindSecure(
          InternetAddress.loopbackIPv4,
          0,
          SecurityContext()
            ..useCertificateChain(_certificate)
            ..usePrivateKey(_key),
        )
      : await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen(_answer);
  return server;
}

void main() {
  // The test binding answers every request itself (400); a server here is
  // asked for real.
  setUpAll(() => HttpOverrides.global = null);

  test('an http forge is spoken to as it is served', () async {
    final server = await _serve(secure: false);
    addTearDown(() => server.close(force: true));
    final response = await IoForgeHttp().send(
      'GET',
      Uri.parse('http://127.0.0.1:${server.port}/user'),
    );
    expect(response.body, 'ok');
  });

  test('a self-signed certificate is refused, then taken once trusted, and '
      'only as the one trusted', () async {
    final server = await _serve(secure: true);
    addTearDown(() => server.close(force: true));
    final url = Uri.parse('https://127.0.0.1:${server.port}/user');
    final host = '127.0.0.1:${server.port}';

    final http = IoForgeHttp();
    final refused = await http
        .send('GET', url)
        .then<Object?>((_) => null, onError: (Object error) => error);
    expect(refused, isA<ForgeCertificateException>());
    final problem = refused! as ForgeCertificateException;
    expect(problem.host, host);
    expect(problem.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));

    // Another fingerprint is not the one confirmed: still refused.
    final other = IoForgeHttp()..trustCertificate(host, '0' * 64);
    await expectLater(
      other.send('GET', url),
      throwsA(isA<ForgeCertificateException>()),
    );

    // The one confirmed: taken.
    http.trustCertificate(host, problem.sha256);
    expect((await http.send('GET', url)).body, 'ok');
  });

  test('what a certificate says of itself is passed on', () async {
    final server = await _serve(secure: true);
    addTearDown(() => server.close(force: true));
    final url = Uri.parse('https://127.0.0.1:${server.port}/user');
    final problem = await IoForgeHttp()
        .send('GET', url)
        .then<Object?>((_) => null, onError: (Object error) => error);
    final certificate = problem! as ForgeCertificateException;
    expect(certificate.subject, contains('localhost'));
    expect(certificate.issuer, contains('localhost'));
  });
}
