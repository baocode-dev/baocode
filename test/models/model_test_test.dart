import 'dart:async';

import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_test.dart';
import 'package:baocode/models/model_test_stream.dart';
import 'package:flutter_test/flutter_test.dart';

const provider = ModelProvider(id: 'p', name: 'Provider');
const model = ProviderModel(id: 'm');

void main() {
  test('native protocols parse text, thinking, usage and completion', () {
    final chat = ModelTestStreamParser(ProviderProtocol.openaiChat);
    chat.addLine('data: {"choices":[{"delta":{"role":"assistant"}}]}');
    expect(chat.addLine('')!.text, isEmpty);
    chat.addLine(
      'data: {"choices":[{"delta":{"content":"1 2","reasoning_content":"think"}}]}',
    );
    final delta = chat.addLine('')!;
    expect(delta.text, '1 2');
    expect(delta.thinking, 'think');
    chat.addLine(
      'data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":3}}',
    );
    expect(chat.addLine('')!.outputTokens, 3);
    expect(chat.done, isFalse);
    chat.addLine('data: [DONE]');
    expect(chat.addLine('')!.done, isTrue);

    final anthropic = ModelTestStreamParser(ProviderProtocol.anthropic);
    anthropic.addLine(
      'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"中文"}}',
    );
    expect(anthropic.addLine('')!.text, '中文');
    anthropic.addLine(
      'data: {"type":"message_delta","usage":{"output_tokens":12}}',
    );
    expect(anthropic.addLine('')!.outputTokens, 12);
    anthropic.addLine('data: {"type":"message_stop"}');
    expect(anthropic.finish()!.done, isTrue);

    for (final protocol in [
      ProviderProtocol.openaiResponses,
      ProviderProtocol.codex,
    ]) {
      final responses = ModelTestStreamParser(protocol);
      responses.addLine(': heartbeat');
      expect(responses.addLine(''), isNull);
      responses.addLine(
        'data: {"type":"response.output_text.delta","delta":"hello"}',
      );
      expect(responses.addLine('')!.text, 'hello');
      responses.addLine(
        'data: {"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":5,"output_tokens":8}}}',
      );
      final end = responses.addLine('')!;
      expect(end.done, isTrue);
      expect(end.outputTokens, 8);
      expect(end.inputTokens, 5);
    }
  });

  test('SSE multiline frames, malformed/error/truncated streams', () {
    final parser = ModelTestStreamParser(ProviderProtocol.openaiResponses);
    parser.addLine('data: {"type":"response.output_text.delta",');
    parser.addLine('data: "delta":"ok"}');
    expect(parser.addLine('')!.text, 'ok');
    expect(parser.done, isFalse);
    parser.addLine('data: {"type":"response.incomplete"}');
    expect(() => parser.addLine(''), throwsFormatException);
    parser.addLine('data: invalid');
    expect(() => parser.addLine(''), throwsFormatException);
    final chat = ModelTestStreamParser(ProviderProtocol.openaiChat);
    chat.addLine('data: {"choices":[{"delta":{},"finish_reason":"length"}]}');
    expect(() => chat.addLine(''), throwsFormatException);
  });

  test('requests omit sampling and enable no reasoning by default', () {
    for (final protocol in ProviderProtocol.values) {
      final body = modelTestRequest(
        provider.copyWith(protocol: protocol),
        model,
        modelTestPrompt,
      );
      expect(body['stream'], isTrue);
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('reasoning'), isFalse);
      expect(body.containsKey('reasoning_effort'), isFalse);
      expect(body.containsKey('tools'), isFalse);
    }
    final body = modelTestRequest(
      provider.copyWith(protocol: ProviderProtocol.openaiResponses),
      const ProviderModel(id: 'm', efforts: ['none', 'low']),
      'hello',
    );
    expect(body['reasoning'], {'effort': 'none'});
  });

  test('first text excludes reasoning and usage overrides estimates', () async {
    final service = ModelTestService(
      run: (_, _, _, _, emit) async {
        emit(const ModelTestEvent(thinking: 'thinking'));
        await Future<void>.delayed(const Duration(milliseconds: 3));
        emit(
          const ModelTestEvent(text: 'hello', inputTokens: 10, outputTokens: 7),
        );
        emit(const ModelTestEvent(done: true));
      },
    );
    addTearDown(service.dispose);
    service.start(provider, [model]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final result = service.result('p', 'm')!;
    expect(result.status, ModelTestStatus.passed);
    expect(result.output, 'hello');
    expect(result.thinking, 'thinking');
    expect(result.firstText!, greaterThan(result.firstEvent!));
    expect(result.outputTokens, 7);
    expect(result.tokensEstimated, isFalse);
    expect(result.tokensPerSecond, greaterThan(0));
    expect(
      ModelTestService(run: (_, _, _, _, _) async {}).result('p', 'm'),
      isNull,
    );
  });

  test(
    'bounded workers, deduplication, queued and active cancellation',
    () async {
      final gates = <Completer<void>>[];
      var running = 0;
      var peak = 0;
      final service = ModelTestService(
        concurrency: 2,
        run: (_, _, _, cancellation, emit) async {
          running++;
          if (running > peak) peak = running;
          final gate = Completer<void>();
          gates.add(gate);
          await Future.any([gate.future, cancellation.whenCancelled]);
          emit(const ModelTestEvent(text: 'ok', done: true));
          running--;
        },
      );
      addTearDown(service.dispose);
      service.start(provider, const [
        ProviderModel(id: 'a'),
        ProviderModel(id: 'b'),
        ProviderModel(id: 'c'),
      ]);
      service.start(provider, const [ProviderModel(id: 'a')]);
      expect(gates.length, 2);
      expect(service.result('p', 'c')!.status, ModelTestStatus.queued);
      service.cancel('p', 'c');
      expect(service.result('p', 'c')!.status, ModelTestStatus.cancelled);
      service.cancel('p', 'a');
      gates[1].complete();
      await Future<void>.delayed(Duration.zero);
      expect(peak, 2);
      expect(service.result('p', 'a')!.status, ModelTestStatus.cancelled);
      expect(service.result('p', 'b')!.status, ModelTestStatus.passed);
      expect(gates.length, 2);
    },
  );

  test('incomplete/empty streams fail and output storage is bounded', () async {
    final service = ModelTestService(
      run: (_, model, _, _, emit) async {
        if (model.id == 'empty') {
          emit(const ModelTestEvent(done: true));
          return;
        }
        emit(ModelTestEvent(text: 'a' * 70000, done: model.id == 'long'));
      },
    );
    addTearDown(service.dispose);
    service.start(provider, const [
      ProviderModel(id: 'empty'),
      ProviderModel(id: 'long'),
      ProviderModel(id: 'cut'),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(service.result('p', 'empty')!.error, 'empty_output');
    expect(service.result('p', 'cut')!.error, 'incomplete_stream');
    final result = service.result('p', 'long')!;
    expect(result.status, ModelTestStatus.passed);
    expect(result.output.length, 65536);
    expect(result.outputTruncated, isTrue);
    expect(result.tokensEstimated, isTrue);
  });

  test('timeout cancels transport and releases worker', () async {
    late ModelTestCancellation cancellation;
    final service = ModelTestService(
      timeout: const Duration(milliseconds: 5),
      run: (_, _, _, token, _) async {
        cancellation = token;
        await token.whenCancelled;
      },
    );
    addTearDown(service.dispose);
    service.start(provider, [model]);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(service.result('p', 'm')!.error, 'timeout');
    expect(cancellation.cancelled, isTrue);
  });
}
