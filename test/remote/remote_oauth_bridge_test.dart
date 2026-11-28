import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:baocode/remote/remote_oauth_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'remote_harness.dart';

void main() {
  group('parseOAuthUrl', () {
    test('extracts Google OAuth URL with encoded 127.0.0.1 callback port', () {
      const line =
          'Please open this URL in your browser: '
          'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=test-client.apps.googleusercontent.com'
          '&redirect_uri=http%3A%2F%2F127.0.0.1%3A45678%2Foauth2callback'
          '&response_type=code&scope=openid.';

      final info = parseOAuthUrl(line);
      expect(info, isNotNull);
      expect(info!.url.host, 'accounts.google.com');
      expect(info.url.toString(), isNot(endsWith('.')));
      expect(info.callbackPort, 45678);
      expect(info.needsCode, isFalse);
    });

    test('extracts localhost and IPv6 ::1 callback ports and strips ANSI/punctuation', () {
      const localhostLine =
          'Open (\x1b[4mhttps://accounts.google.com/o/oauth2/auth'
          '?client_id=abc&redirect_uri=http://localhost:8085/callback\x1b[0m), '
          'to continue.';
      final localhostInfo = parseOAuthUrl(localhostLine);
      expect(localhostInfo, isNotNull);
      expect(localhostInfo!.callbackPort, 8085);
      expect(localhostInfo.needsCode, isFalse);
      expect(
        localhostInfo.url.toString(),
        'https://accounts.google.com/o/oauth2/auth'
        '?client_id=abc&redirect_uri=http://localhost:8085/callback',
      );

      const ipv6Line =
          'URL: "https://accounts.google.com/o/oauth2/auth'
          '?client_id=abc&redirect_uri=http%3A%2F%2F%5B%3A%3A1%5D%3A9123%2Fcb"';
      final ipv6Info = parseOAuthUrl(ipv6Line);
      expect(ipv6Info, isNotNull);
      expect(ipv6Info!.callbackPort, 9123);
      expect(ipv6Info.needsCode, isFalse);
    });

    test('extracts non-Google OAuth URL with redirect_uri or client_id', () {
      const line =
          'Docs: https://example.com/help — '
          'Auth: https://auth.example.org/authorize'
          '?client_id=my-app&redirect_uri=http%3A%2F%2F127.0.0.1%3A55123%2Fcb;';

      final info = parseOAuthUrl(line);
      expect(info, isNotNull);
      expect(info!.url.host, 'auth.example.org');
      expect(info.callbackPort, 55123);
      expect(info.needsCode, isFalse);
    });

    test('detects out-of-band / manual code flows when no loopback port exists', () {
      const oobLine =
          'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=abc&redirect_uri=urn:ietf:wg:oauth:2.0:oob';
      final oob = parseOAuthUrl(oobLine);
      expect(oob, isNotNull);
      expect(oob!.callbackPort, isNull);
      expect(oob.needsCode, isTrue);

      const webRedirectLine =
          'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=abc&redirect_uri=https%3A%2F%2Fcodeassist.google.com%2Fauthcode';
      final webRedirect = parseOAuthUrl(webRedirectLine);
      expect(webRedirect, isNotNull);
      expect(webRedirect!.callbackPort, isNull);
      expect(webRedirect.needsCode, isTrue);

      const noPortLoopback =
          'https://accounts.google.com/o/oauth2/v2/auth'
          '?client_id=abc&redirect_uri=http://localhost/callback';
      final noPort = parseOAuthUrl(noPortLoopback);
      expect(noPort, isNotNull);
      expect(noPort!.callbackPort, isNull);
      expect(noPort.needsCode, isTrue);
    });

    test('returns null for non-OAuth lines', () {
      expect(parseOAuthUrl('Waiting for browser authentication...'), isNull);
      expect(parseOAuthUrl('See https://example.com/docs for details'), isNull);
      expect(
        parseOAuthUrl('http://127.0.0.1:8085/callback?code=123'),
        isNull,
      );
    });
  });

  group('RemoteOAuthCallbackBridge', () {
    late RemoteHarness harness;

    setUp(() async {
      harness = await RemoteHarness.start();
    });

    tearDown(() async {
      await harness.close();
    });

    test('forwards local HTTP OAuth callback bidirectionally to remote server', () async {
      final receivedRequests = <Uri>[];
      final remoteCallbackServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(() => remoteCallbackServer.close(force: true));
      remoteCallbackServer.listen((request) {
        receivedRequests.add(request.uri);
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.html
          ..write('<html><body>Signed in: ${request.uri.queryParameters['code']}</body></html>')
          ..close();
      });

      final bridge = await RemoteOAuthCallbackBridge.start(
        harness.client,
        remoteCallbackServer.port,
        localPort: 0,
      );
      expect(bridge, isNotNull);
      addTearDown(() => bridge!.close());

      final socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        bridge!.localPort,
      );
      socket.write(
        'GET /oauth2callback?code=secret_code_42&state=ok HTTP/1.0\r\n'
        'Host: 127.0.0.1:${bridge.localPort}\r\n\r\n',
      );
      await socket.flush();
      final response = await utf8.decoder.bind(socket).join();
      socket.destroy();

      expect(receivedRequests, hasLength(1));
      expect(receivedRequests.single.path, '/oauth2callback');
      expect(receivedRequests.single.queryParameters['code'], 'secret_code_42');
      expect(response, contains('200 OK'));
      expect(response, contains('Signed in: secret_code_42'));
    });

    test('transfers multi-chunk bidirectional TCP payload cleanly', () async {
      final remoteEcho = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(remoteEcho.close);
      remoteEcho.listen((remoteSocket) {
        final chunks = BytesBuilder();
        remoteSocket.listen(
          (data) {
            chunks.add(data);
            if (chunks.length >= 65536) {
              remoteSocket.add(chunks.takeBytes());
              remoteSocket.close();
            }
          },
          onError: (Object _) => remoteSocket.destroy(),
        );
      });

      final bridge = await RemoteOAuthCallbackBridge.start(
        harness.client,
        remoteEcho.port,
        localPort: 0,
      );
      expect(bridge, isNotNull);
      addTearDown(() => bridge!.close());

      final payload = Uint8List.fromList(
        List<int>.generate(65536, (i) => i & 0xff),
      );
      final clientSocket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        bridge!.localPort,
      );
      clientSocket.add(payload);
      await clientSocket.flush();

      final received = BytesBuilder();
      await for (final chunk in clientSocket) {
        received.add(chunk);
      }
      clientSocket.destroy();

      expect(received.takeBytes(), orderedEquals(payload));
    });

    test('returns null when exact local port is already occupied', () async {
      final occupied = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(occupied.close);

      final bridge = await RemoteOAuthCallbackBridge.start(
        harness.client,
        occupied.port,
      );
      expect(bridge, isNull);
    });

    test('close stops listener and tears down active sockets and tunnels', () async {
      final remoteConnected = Completer<Socket>();
      final remoteClosed = Completer<void>();
      final remoteServer = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(remoteServer.close);
      remoteServer.listen((socket) {
        if (!remoteConnected.isCompleted) remoteConnected.complete(socket);
        socket.listen(
          (_) {},
          onDone: () {
            if (!remoteClosed.isCompleted) remoteClosed.complete();
          },
          onError: (Object _) {
            if (!remoteClosed.isCompleted) remoteClosed.complete();
          },
        );
      });

      final bridge = await RemoteOAuthCallbackBridge.start(
        harness.client,
        remoteServer.port,
        localPort: 0,
      );
      expect(bridge, isNotNull);
      final port = bridge!.localPort;

      final localClient = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
      );
      final localClosed = Completer<void>();
      localClient.listen(
        (_) {},
        onDone: () {
          if (!localClosed.isCompleted) localClosed.complete();
        },
        onError: (Object _) {
          if (!localClosed.isCompleted) localClosed.complete();
        },
      );

      // Ensure tunnel is established end-to-end before closing bridge.
      await remoteConnected.future.timeout(const Duration(seconds: 5));

      await bridge.close();
      expect(bridge.isClosed, isTrue);

      await Future.wait([
        localClosed.future.timeout(const Duration(seconds: 5)),
        remoteClosed.future.timeout(const Duration(seconds: 5)),
      ]);

      await expectLater(
        Socket.connect(InternetAddress.loopbackIPv4, port),
        throwsA(isA<SocketException>()),
      );
    });
  });
}
