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

  testWidgets('a loop goes round on the shared clock\'s frames, not every '
      'vsync: there and back where it turns back', (tester) async {
    final loop = StepLoop(const Duration(seconds: 1), reverse: true);
    addTearDown(loop.dispose);
    final values = <double>[];
    loop.addListener(() => values.add(loop.value));
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (c) {
          context = c;
          return const SizedBox();
        },
      ),
    );
    expect(loop.value, 0);
    loop.start(context);
    await tester.pump(const Duration(milliseconds: 500));
    expect(loop.value, closeTo(0.5, 0.05));
    await tester.pump(const Duration(milliseconds: 1000));
    expect(loop.value, closeTo(0.5, 0.05), reason: 'on its way back');
    expect(values.length, inInclusiveRange(40, 46));
    expect(tester.hasRunningAnimations, isFalse);
    loop.stop();
    expect(loop.value, 0);
  });
}
