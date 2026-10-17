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

  test('follows the pace as it changes', () {
    stream(30);
    stream(60, every: 50);
    expect(meter.output.tokensPerSecond, closeTo(200, 1e-6));
  });

  test('none between messages; the counts replace the guesses', () {
    stream(20);
    meter.endMessage(tokens: 300, written: 200);
    expect(meter.output.tokensPerSecond, isNull);
    expect(meter.output.tokens, 300);
    meter.startMessage();
    // Guessed 200 for 200 written: the guess stands.
    stream(5);
    expect(meter.output.tokens, 350);
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

  test('averages the speed shown over the time it was', () {
    expect(meter.averageSpeed, isNull);
    // 100 a second shown for 1s, and then, after a wait, 200 for 1s.
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
}
