import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/output_meter.dart';

void main() {
  late DateTime now;
  late OutputMeter meter;

  setUp(() {
    now = DateTime(2026);
    meter = OutputMeter(clock: () => now)..begin();
  });

  void after(int ms) => now = now.add(Duration(milliseconds: ms));

  /// [chunks] of 30 ASCII characters (10 tokens guessed), one every [every]
  /// milliseconds.
  void stream(int chunks, {int every = 100}) {
    for (var i = 0; i < chunks; i++) {
      after(every);
      meter.streamed('a' * 30);
    }
  }

  test('guesses tokens from the text, Han heavier than ASCII', () {
    expect(OutputMeter.estimateTokens('a' * 30), 10);
    expect(OutputMeter.estimateTokens('秋天' * 5), closeTo(13, 1e-9));
  });

  test('no speed before it has written for a while', () {
    stream(5);
    expect(meter.output.tokens, 50);
    expect(meter.output.tokensPerSecond, isNull);
  });

  test('the speed it writes at, not the burst it began with', () {
    // What the upstream held back, all at once, then 100 tokens a second.
    meter.streamed('a' * 3000);
    stream(30);
    expect(meter.output.tokensPerSecond, closeTo(100, 1e-6));
    expect(meter.output.tokens, 1300);
  });

  test('deltas close together all along are timed each', () {
    // A burst of what was held back, then a delta every 20ms.
    for (var i = 0; i < 5; i++) {
      after(2);
      meter.streamed('a' * 300);
    }
    stream(150, every: 20);
    expect(meter.output.tokensPerSecond, closeTo(500, 1e-6));
  });

  test('deltas read off in batches are timed by the batch', () {
    for (var batch = 0; batch < 30; batch++) {
      after(100);
      for (var i = 0; i < 4; i++) {
        meter.streamed('a' * 30);
      }
    }
    expect(meter.output.tokensPerSecond, closeTo(400, 1e-6));
  });

  test('follows the pace as it changes', () {
    stream(30);
    stream(60, every: 50);
    expect(meter.output.tokensPerSecond, closeTo(200, 1e-6));
  });

  test('the last sample between messages; the counts replace the '
      'guesses', () {
    stream(20);
    meter.endMessage(tokens: 300, written: 200);
    expect(meter.output.tokensPerSecond, closeTo(100, 1e-6));
    expect(meter.output.tokens, 300);
    meter.startMessage();
    // Guessed 200 for 200 written: the guess stands.
    stream(5);
    expect(meter.output.tokens, 350);
    // Too short to sample yet: the last sample.
    expect(meter.output.tokensPerSecond, closeTo(100, 1e-6));
  });

  test('short messages, a wait between each, are timed all together', () {
    // Half a second of 100 a second each: none sampled alone.
    for (var i = 0; i < 4; i++) {
      meter.startMessage();
      stream(6);
      meter.endMessage(tokens: 60);
      after(3000);
    }
    expect(meter.output.tokensPerSecond, closeTo(100, 1e-6));
    expect(meter.averageSpeed, closeTo(100, 1e-6));
  });

  test('a tool call\'s input all at once as it ends: timed from the '
      'call\'s start, after a thought', () {
    meter.startMessage();
    // A thought for a second, untimed.
    for (var i = 0; i < 10; i++) {
      after(100);
      meter.streamed('a' * 30, timed: false);
    }
    meter.startBlock();
    after(1000);
    // 100 tokens of input, written over that second.
    meter.streamed('a' * 300);
    // The next call's, with its start, at once.
    after(5);
    meter.startBlock();
    meter.streamed('a' * 300);
    meter.endMessage(tokens: 300);
    expect(meter.output.tokensPerSecond, closeTo(200 / 1.005, 1e-6));
  });

  test('a block held back, its start and deltas at once: not timed', () {
    meter.startMessage();
    after(3000);
    meter.startBlock();
    meter.streamed('a' * 3000);
    after(10);
    meter.streamed('a' * 3000);
    meter.endMessage(tokens: 2000);
    expect(meter.output.tokensPerSecond, isNull);
  });

  test('the last sample, not the average, after a faster message', () {
    stream(21);
    meter.endMessage(tokens: 210);
    meter.startMessage();
    stream(41, every: 50);
    meter.endMessage(tokens: 410);
    expect(meter.output.tokensPerSecond, closeTo(200, 1));
    expect(meter.averageSpeed, closeTo(150, 1));
  });

  test('guesses as the counts went', () {
    stream(20);
    // Twice what it guessed.
    meter.endMessage(tokens: 400, written: 400);
    stream(20);
    expect(meter.output.tokens, 800);
    expect(meter.output.tokensPerSecond, closeTo(200, 1e-6));
  });

  test("thoughts are counted, not timed", () {
    after(100);
    meter.streamed('a' * 300, timed: false);
    after(2000);
    meter.streamed('a' * 300, timed: false);
    expect(meter.output.tokens, 200);
    expect(meter.output.tokensPerSecond, isNull);
  });

  test('averages the tokens timed over the time written, the waits left '
      'out', () {
    expect(meter.averageSpeed, isNull);
    // 100 a second for 2s, and then, after a wait, 200 for 2s.
    stream(21);
    meter.endMessage(tokens: 210);
    after(5000);
    meter.startMessage();
    stream(41, every: 50);
    meter.endMessage(tokens: 410);
    expect(meter.averageSpeed, closeTo(150, 1));
    // A turn of messages too short to time has none.
    meter.begin();
    stream(3);
    meter.endMessage(tokens: 30);
    expect(meter.averageSpeed, isNull);
  });

  test('estimates output speed from streamed thoughts before warm-up, then hands off to exact speed', () {
    // 7 chunks of 10 tokens every 100 ms (600 ms active span, first chunk is burst).
    for (var i = 0; i < 7; i++) {
      after(100);
      meter.streamed('a' * 30, timed: false);
    }
    expect(meter.output.tokens, 70);
    expect(meter.output.tokensPerSecond, isNull);
    expect(meter.output.estimatedTokensPerSecond, closeTo(100, 1e-6));

    // Once exact timed text streams past warm-up, estimated speed yields to exact speed.
    meter.startMessage();
    stream(15);
    expect(meter.output.tokensPerSecond, closeTo(100, 1e-6));
    expect(meter.output.estimatedTokensPerSecond, isNull);
  });
}
