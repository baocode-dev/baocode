import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baocode/models/codex/codex_accounts_io.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/models/model_test_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/models/secret_store.dart';

import 'codex_test.dart' show FakeOpenAI, tokens;

void main() {
  late HttpServer server;
  late CodexAccounts codex;
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Only loopback fixture requests; undo the widget binding's fake HTTP 400.
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    codex = CodexAccounts(providers: () => ModelProviders.memory());
  });
  tearDown(() async {
    codex.close();
    await server.close(force: true);
  });

  ModelProvider provider(ProviderProtocol protocol) => ModelProvider(
    id: 'p',
    name: 'Local',
    protocol: protocol,
    baseUrl: 'http://127.0.0.1:${server.port}',
  );

  for (final protocol in [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
  ]) {
    test('real HTTP $protocol streams split UTF-8 and native usage', () async {
      final seen = Completer<(String, Map)>();
      server.listen((request) async {
        final body = jsonDecode(await utf8.decodeStream(request)) as Map;
        expect(request.method, 'POST');
        expect(
          request.headers.value(HttpHeaders.acceptHeader),
          'text/event-stream',
        );
        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer secret',
        );
        if (protocol == ProviderProtocol.anthropic) {
          expect(request.headers.value('anthropic-version'), '2023-06-01');
          expect(body['max_tokens'], 2048);
        }
        expect(body['model'], 'm');
        expect(body.containsKey('temperature'), isFalse);
        seen.complete((request.uri.path, body));
        final response = request.response;
        response.headers.contentType = ContentType('text', 'event-stream');
        response.bufferOutput = false;
        final frames = switch (protocol) {
          ProviderProtocol.anthropic => [
            {
              'type': 'content_block_delta',
              'delta': {'type': 'text_delta', 'text': '你好'},
            },
            {
              'type': 'message_delta',
              'usage': {'output_tokens': 2},
            },
            {'type': 'message_stop'},
          ],
          ProviderProtocol.openaiChat => [
            {
              'choices': [
                {
                  'delta': {'content': '你好'},
                },
              ],
            },
            {
              'choices': [],
              'usage': {'completion_tokens': 2},
            },
          ],
          _ => [
            {'type': 'response.output_text.delta', 'delta': '你好'},
            {
              'type': 'response.completed',
              'response': {
                'status': 'completed',
                'usage': {'output_tokens': 2},
              },
            },
          ],
        };
        final bytes = utf8.encode(
          [
            for (final frame in frames) 'data: ${jsonEncode(frame)}\n\n',
            if (protocol == ProviderProtocol.openaiChat) 'data: [DONE]\n\n',
          ].join(),
        );
        for (var i = 0; i < bytes.length; i += 2) {
          response.add(bytes.sublist(i, (i + 2).clamp(0, bytes.length)));
          await response.flush();
        }
        await response.close();
      });
      final service = ModelTestService(
        run: (p, m, prompt, cancellation, emit) => runModelTest(
          p,
          m,
          prompt,
          cancellation,
          emit,
          keyOf: (_) async => 'secret',
          codex: codex,
        ),
      );
      addTearDown(service.dispose);
      final finished = Completer<void>();
      service.addListener(() {
        if (service.result('p', 'm')?.active == false &&
            !finished.isCompleted) {
          finished.complete();
        }
      });
      service.start(provider(protocol), const [ProviderModel(id: 'm')]);
      await finished.future.timeout(const Duration(seconds: 5));
      final result = service.result('p', 'm')!;
      expect(result.status, ModelTestStatus.passed);
      expect(result.output, '你好');
      expect(result.outputTokens, 2);
      final (path, body) = await seen.future;
      expect(path, switch (protocol) {
        ProviderProtocol.anthropic => '/v1/messages',
        ProviderProtocol.openaiChat => '/v1/chat/completions',
        _ => '/v1/responses',
      });
      expect(body['stream'], isTrue);
    });
  }

  test(
    'HTTP error redacts the key and premature EOF does not complete',
    () async {
      var calls = 0;
      server.listen((request) async {
        await request.drain<void>();
        if (calls++ == 0) {
          request.response.statusCode = 401;
          request.response.write('{"error":{"message":"echo secret-key"}}');
        } else {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: {"choices":[{"delta":{"content":"partial"}}]}\n\n',
          );
        }
        await request.response.close();
      });
      final cancellation = ModelTestCancellation();
      addTearDown(cancellation.cancel);
      await expectLater(
        runModelTest(
          provider(ProviderProtocol.openaiChat),
          const ProviderModel(id: 'm'),
          'hi',
          cancellation,
          (_) {},
          keyOf: (_) async => 'secret-key',
          codex: codex,
        ),
        throwsA(
          predicate(
            (error) =>
                '$error'.contains('[redacted]') &&
                !'$error'.contains('secret-key'),
          ),
        ),
      );
      final events = <ModelTestEvent>[];
      await runModelTest(
        provider(ProviderProtocol.openaiChat),
        const ProviderModel(id: 'm'),
        'hi',
        cancellation,
        events.add,
        keyOf: (_) async => null,
        codex: codex,
      );
      expect(events.any((e) => e.done), isFalse);
      expect(events.map((e) => e.text).join(), 'partial');
    },
  );

  test(
    'Codex streams through account refresh and native Responses endpoint',
    () async {
      final openai = await FakeOpenAI.start();
      addTearDown(openai.close);
      final secrets = MemorySecretStore({
        ModelProvider.accountRefFor('cx', 'a'): 'fixture-refresh',
      });
      final providers = ModelProviders.memory(
        secrets: secrets,
        providers: [
          const ModelProvider(
            id: 'cx',
            name: 'Codex',
            protocol: ProviderProtocol.codex,
            accounts: [ProviderAccount(id: 'a', accountId: 'workspace-a')],
          ),
        ],
      );
      addTearDown(providers.dispose);
      final accounts = CodexAccounts(
        providers: () => providers,
        endpoints: openai.endpoints(),
      );
      addTearDown(accounts.close);
      openai.reply = (path, _, _) => path == '/oauth/token'
          ? tokens('fixture-access', refresh: 'fixture-next')
          : (
              200,
              {'content-type': 'text/event-stream'},
              [
                'data: {"type":"response.reasoning_summary_text.delta","delta":"reason"}',
                '',
                'data: {"type":"response.output_text.delta","delta":"OK"}',
                '',
                'data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":12,"output_tokens":3}}}',
                '',
              ],
            );
      final events = <ModelTestEvent>[];
      final cancellation = ModelTestCancellation();
      addTearDown(cancellation.cancel);
      await runModelTest(
        providers.provider('cx')!,
        const ProviderModel(id: 'gpt-test', efforts: ['none']),
        'custom prompt',
        cancellation,
        events.add,
        keyOf: (_) async => throw StateError('Codex must not read API key'),
        codex: accounts,
      );
      expect(events.map((e) => e.text).join(), 'OK');
      expect(events.map((e) => e.thinking).join(), 'reason');
      expect(events.last.done, isTrue);
      expect(events.last.outputTokens, 3);
      final request = openai.to('/backend-api/codex/responses').single;
      final body = jsonDecode(request.body) as Map;
      expect(request.headers['authorization'], 'Bearer fixture-access');
      expect(request.headers['chatgpt-account-id'], 'workspace-a');
      expect(body['instructions'], '');
      expect(body['stream'], isTrue);
      expect(body['store'], isFalse);
      expect(body['reasoning'], {'effort': 'none'});
      expect(body['input'], [
        {'role': 'user', 'content': 'custom prompt'},
      ]);
      expect(body.containsKey('temperature'), isFalse);
      expect(
        await secrets.read(ModelProvider.accountRefFor('cx', 'a')),
        'fixture-next',
      );
    },
  );

  test('Codex without an account fails before any upstream call', () async {
    final cancel = ModelTestCancellation();
    addTearDown(cancel.cancel);
    await expectLater(
      runModelTest(
        provider(ProviderProtocol.codex),
        const ProviderModel(id: 'm'),
        'hello',
        cancel,
        (_) {},
        keyOf: (_) async => null,
        codex: codex,
      ),
      throwsA(predicate((e) => '$e'.contains('No available ChatGPT account'))),
    );
  });

  for (final protocol in [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
  ]) {
    test(
      '$protocol rejects HTTP errors, SSE errors, malformed data and truncated streams',
      () async {
        var call = 0;
        server.listen((request) async {
          await request.drain<void>();
          final response = request.response;
          response.headers.contentType = ContentType('text', 'event-stream');
          switch (call++) {
            case 0:
              response.statusCode = 429;
              response.write('{"error":{"message":"rate limited"}}');
            case 1:
              response.write(
                'data: {"type":"error","error":{"message":"stream failed"}}\n\n',
              );
            case 2:
              response.write('data: invalid-json\n\n');
            default:
              response.write(': heartbeat\n\n');
          }
          await response.close();
        });
        final cancel = ModelTestCancellation();
        addTearDown(cancel.cancel);
        for (var n = 0; n < 3; n++) {
          await expectLater(
            runModelTest(
              provider(protocol),
              const ProviderModel(id: 'm'),
              'hi',
              cancel,
              (_) {},
              keyOf: (_) async => null,
              codex: codex,
            ),
            throwsA(isA<HttpException>()),
          );
        }
        final events = <ModelTestEvent>[];
        await runModelTest(
          provider(protocol),
          const ProviderModel(id: 'm'),
          'hi',
          cancel,
          events.add,
          keyOf: (_) async => null,
          codex: codex,
        );
        expect(events.any((e) => e.done), isFalse);
      },
    );
  }

  for (final protocol in [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
  ]) {
    for (final auth in [ProviderAuth.apiKey, ProviderAuth.bearer]) {
      test(
        '$protocol $auth preserves explicit /v1 URL and authentication',
        () async {
          final received = Completer<void>();
          server.listen((request) async {
            await request.drain<void>();
            expect(request.uri.path, switch (protocol) {
              ProviderProtocol.anthropic => '/v1/messages',
              ProviderProtocol.openaiChat => '/v1/chat/completions',
              _ => '/v1/responses',
            });
            expect(
              request.headers.value('x-api-key'),
              auth == ProviderAuth.apiKey ? 'fixture-key' : null,
            );
            expect(
              request.headers.value('authorization'),
              auth == ProviderAuth.bearer ? 'Bearer fixture-key' : null,
            );
            request.response.headers.contentType = ContentType(
              'text',
              'event-stream',
            );
            request.response.write(switch (protocol) {
              ProviderProtocol.anthropic => 'data: {"type":"message_stop"}\n\n',
              ProviderProtocol.openaiChat => 'data: [DONE]\n\n',
              _ => 'data: {"type":"response.completed","response":{"status":"completed"}}\n\n',
            });
            await request.response.close();
            received.complete();
          });
          final cancellation = ModelTestCancellation();
          addTearDown(cancellation.cancel);
          final events = <ModelTestEvent>[];
          await runModelTest(
            provider(protocol).copyWith(
              baseUrl: 'http://127.0.0.1:${server.port}/v1',
              auth: auth,
            ),
            const ProviderModel(id: 'm'),
            'hello',
            cancellation,
            events.add,
            keyOf: (_) async => 'fixture-key',
            codex: codex,
          );
          await received.future.timeout(const Duration(seconds: 5));
          expect(events.any((e) => e.done), isTrue);
        },
      );
    }
  }

  for (final protocol in [
    ProviderProtocol.anthropic,
    ProviderProtocol.openaiChat,
    ProviderProtocol.openaiResponses,
  ]) {
    test('$protocol cancellation closes the HTTP response reader', () async {
      final opened = Completer<void>();
      server.listen((request) async {
        await request.drain<void>();
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.bufferOutput = false;
        request.response.write(': heartbeat\n\n');
        await request.response.flush();
        opened.complete();
      });
      final cancellation = ModelTestCancellation();
      final run = runModelTest(
        provider(protocol),
        const ProviderModel(id: 'm'),
        'hi',
        cancellation,
        (_) {},
        keyOf: (_) async => null,
        codex: codex,
      );
      await opened.future.timeout(const Duration(seconds: 5));
      cancellation.cancel();
      await run.timeout(const Duration(seconds: 5));
    });
  }
}
