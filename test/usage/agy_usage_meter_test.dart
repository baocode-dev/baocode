import 'package:baocode/usage/agy_usage_meter.dart';
import 'package:baocode/usage/usage_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late List<UsageCall> kept;
  late AgyUsageMeter meter;

  setUp(() {
    now = DateTime(2026, 11, 24, 10);
    kept = [];
    meter = AgyUsageMeter(
      record: (call, {trace}) => kept.add(call),
      session: () => 's1',
      provider: 'provider-3',
      providerName: 'Antigravity',
      effort: 'high',
      clock: () => now,
    );
  });

  test('a turn: one call, timed, its tokens as agy told them', () {
    meter.receive({
      'type': 'system',
      'subtype': 'init',
      'model': 'gemini-3.8-flash',
    });
    meter.requested();
    now = now.add(const Duration(seconds: 2));
    meter.receive({
      'type': 'stream_event',
      'event': {'type': 'content_block_delta'},
    });
    now = now.add(const Duration(seconds: 8));
    meter.receive({
      'type': 'result',
      'is_error': false,
      'usage': {
        'input_tokens': 10854,
        'output_tokens': 300,
        'cache_read_input_tokens': 8794,
        'cache_creation_input_tokens': 0,
        'reasoning_tokens': 237,
      },
      'modelUsage': {
        'gemini-3.8-flash': {'contextWindow': 1048576},
      },
    });
    final call = kept.single;
    expect(call.provider, 'provider-3');
    expect(call.protocol, 'agy');
    expect(call.model, 'gemini-3.8-flash');
    expect(call.effort, 'high');
    expect(call.session, 's1');
    expect(call.firstToken, const Duration(seconds: 2));
    expect(call.duration, const Duration(seconds: 10));
    expect(
      (call.input, call.output, call.cacheRead, call.reasoning),
      (10854, 300, 8794, 237),
    );
  });

  test('failed: kept as failed, with no tokens', () {
    meter.requested();
    meter.receive({
      'type': 'result',
      'is_error': true,
      'result': 'quota exhausted',
      'usage': {'input_tokens': 9000, 'output_tokens': 0},
    });
    final call = kept.single;
    expect(call.status, 0);
    expect(call.error, 'quota exhausted');
    expect(call.input, 0);
  });

  test('stopped before agy said what it took: nothing kept', () {
    meter.requested();
    meter.receive({
      'type': 'result',
      'is_error': false,
      'usage': {'input_tokens': 0, 'output_tokens': 0},
    });
    expect(kept, isEmpty);
  });
}
