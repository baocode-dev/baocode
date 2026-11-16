import 'dart:io';

import 'package:baocode/network/tls.dart';
import 'package:flutter_test/flutter_test.dart';

/// A CA of the test's own, and a server's certificate (for localhost and
/// 127.0.0.1) it signed: as an upstream's whose CA the machine trusts and
/// Mozilla does not. Fixtures, for tests only.
const _ca = 'test/network/fixtures/ca.pem';
const _certificate = 'test/network/fixtures/server.pem';
const _key = 'test/network/fixtures/server.key';

Future<HttpServer> _serve() async {
  final server = await HttpServer.bindSecure(
    InternetAddress.loopbackIPv4,
    0,
    SecurityContext()
      ..useCertificateChain(_certificate)
      ..usePrivateKey(_key),
  );
  server.listen((request) async {
    request.response
      ..statusCode = 200
      ..write('ok');
    await request.response.close();
  });
  return server;
}

Future<int> _get(HttpClient client, int port) async {
  final response = await (await client.getUrl(
    Uri.parse('https://127.0.0.1:$port/'),
  )).close();
  await response.drain<void>();
  return response.statusCode;
}

void main() {
  // The test binding answers every request itself (400); a server here is
  // asked for real.
  setUpAll(() => HttpOverrides.global = null);

  test('a certificate is each block of PEM, however the lines end', () {
    const one = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----';
    const two =
        '-----BEGIN CERTIFICATE-----\r\nMIIB\r\n'
        '-----END CERTIFICATE-----';
    expect(pemCertificates(one), [one]);
    expect(pemCertificates('$two\n\n$one\n'), [two, one]);
    expect(pemCertificates(''), isEmpty);
    expect(pemCertificates('not a certificate'), isEmpty);
  });

  test('what a failed handshake was is told, not only that it failed', () {
    final error = HandshakeException(
      'Handshake error in client',
      OSError(
        '\n\tCERTIFICATE_VERIFY_FAILED: unable to get local issuer '
        'certificate(handshake.cc:392)',
      ),
    );
    expect(
      handshakeFailure(error),
      'CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate',
    );
    expect(
      handshakeFailure(const HandshakeException('Handshake error in client')),
      'Handshake error in client',
    );
  });

  test('a root the bundled ones lack is trusted once the machine\'s are '
      'added', () async {
    final server = await _serve();
    addTearDown(() => server.close(force: true));

    final bundledOnly = HttpClient();
    addTearDown(bundledOnly.close);
    await expectLater(
      _get(bundledOnly, server.port),
      throwsA(isA<HandshakeException>()),
    );

    final withSystem = HttpClient(
      context: contextTrusting(await File(_ca).readAsString()),
    );
    addTearDown(withSystem.close);
    expect(await _get(withSystem, server.port), 200);
  });
}
