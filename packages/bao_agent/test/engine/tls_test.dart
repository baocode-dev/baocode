import 'dart:io';

import 'package:bao_agent/bao_agent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// A CA of the test's own, and a server's certificate (for localhost and
/// 127.0.0.1) it signed: as an upstream's whose CA the host trusts and
/// Mozilla does not. Fixtures, for tests only.
const _ca = 'test/support/tls/ca.pem';
const _certificate = 'test/support/tls/server.pem';
const _key = 'test/support/tls/server.key';

/// An answer to a Messages request, as the API streams it: what the
/// engine reads, none of the text being what this test is about.
const _answer =
    'event: message_start\n'
    'data: {"type":"message_start","message":{"id":"m","type":"message",'
    '"role":"assistant","model":"m","content":[],"stop_reason":null,'
    '"stop_sequence":null,"usage":{"input_tokens":1,"output_tokens":1}}}\n\n'
    'event: message_stop\ndata: {"type":"message_stop"}\n\n';

void main() {
  test(
    'an isolate trusts the roots it is given beside the bundled ones',
    () async {
      final server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        SecurityContext()
          ..useCertificateChain(_certificate)
          ..usePrivateKey(_key),
      );
      var requests = 0;
      server.listen((request) async {
        requests++;
        request.response
          ..headers.contentType = ContentType('text', 'event-stream')
          ..write(_answer);
        await request.response.close();
      });
      final root = Directory.systemTemp.createTempSync('bao_tls_');
      final agent = await AgentIsolate.spawn(
        EngineOptions(
          cwd: root.path,
          configDir: p.join(root.path, 'config'),
          environment: {
            'HOME': root.path,
            'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
            'ANTHROPIC_BASE_URL': 'https://127.0.0.1:${server.port}',
            'ANTHROPIC_API_KEY': 'sk-tls',
          },
          // The certificate's CA, as the app gives the machine's own.
          rootCertificates: [await File(_ca).readAsString()],
        ),
      );
      agent.write({
        'type': 'user',
        'uuid': 'u-1',
        'message': {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': 'hi'},
          ],
        },
        'parent_tool_use_id': null,
        'session_id': '',
      });
      await agent.messages
          .firstWhere((message) => message['type'] == 'result')
          .timeout(const Duration(seconds: 20));
      // The bundled roots do not know the CA: reached only as it was given.
      expect(requests, greaterThan(0));
      agent.close();
      await agent.exited.timeout(const Duration(seconds: 20));
      await server.close(force: true);
      root.deleteSync(recursive: true);
    },
  );
}
