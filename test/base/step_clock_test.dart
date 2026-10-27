import 'package:baocode/base/step_clock.dart';
import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tells once a step, on the steps of the shared clock', (
    tester,
  ) async {
    final clock = StepClock(const Duration(milliseconds: 100));
    addTearDown(clock.dispose);
    var told = 0;
    clock
      ..addListener(() => told++)
      ..start();
    final first = clock.ticks;

    await tester.pump(const Duration(milliseconds: 1000));
    // Ten steps, give or take where in a step it started.
    expect(told, inInclusiveRange(9, 11));
    expect(clock.ticks - first, told);
    expect(clock.time, const Duration(milliseconds: 100) * clock.ticks);

    clock.stop();
    await tester.pump(const Duration(milliseconds: 500));
    expect(told, inInclusiveRange(9, 11));
  });

  testWidgets('clocks on other steps change in the same frames, no more '
      'than 30 a second', (tester) async {
    final frame = StepClock.frame.inMicroseconds;
    final told = <int>{};
    final clocks = [
      for (final ms in [53, 62, 120, 33]) StepClock(Duration(milliseconds: ms)),
    ];
    for (final each in clocks) {
      each
        ..addListener(() => told.add(clock.now().microsecondsSinceEpoch))
        ..start();
    }
    await tester.pump(const Duration(seconds: 2));
    for (final each in clocks) {
      each.dispose();
    }
    expect(told, isNotEmpty);
    expect(told.every((at) => at % frame == 0), isTrue);
    expect(told.length, lessThanOrEqualTo(61));
  });

  testWidgets('still where tickers are off or motion is turned down', (
    tester,
  ) async {
    final clock = StepClock(const Duration(milliseconds: 100));
    addTearDown(clock.dispose);
    bool? still;
    Widget under({required bool tickers, required bool motionDown}) =>
        MediaQuery(
          data: MediaQueryData(disableAnimations: motionDown),
          child: TickerMode(
            enabled: tickers,
            child: Builder(
              builder: (context) {
                still = clock.keepTo(context);
                return const SizedBox();
              },
            ),
          ),
        );

    await tester.pumpWidget(under(tickers: true, motionDown: false));
    expect(clock.isRunning, isTrue);
    expect(still, isFalse);

    await tester.pumpWidget(under(tickers: false, motionDown: false));
    expect(clock.isRunning, isFalse);

    await tester.pumpWidget(under(tickers: true, motionDown: true));
    expect(clock.isRunning, isFalse);
    expect(still, isTrue);
  });
}
