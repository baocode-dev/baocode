import 'package:baocode/chat/widgets/pixel_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    for (final role in PixelLoaderRole.values) {
      role.style.value = PixelLoaderStyle.fill;
      role.speed.value = role.defaultSpeed;
    }
  });

  test('every frame is a 3×3 grid, none of them empty', () {
    for (final style in PixelLoaderStyle.values) {
      if (style == PixelLoaderStyle.circle) continue;
      expect(style.frames, isNotEmpty, reason: style.name);
      for (var i = 0; i < style.frames.length; i++) {
        expect(style.frames[i], matches(r'^([#+\-.]{3}/){2}[#+\-.]{3}$'));
        expect(style.alphas(i), hasLength(9));
        expect(style.alphas(i).any((a) => a > 0), isTrue, reason: style.name);
      }
      expect(style.rest, lessThan(style.frames.length));
    }
  });

  test('unset, both play Fill and Empty, an agent at 1.5×, a subagent at '
      '1.3×; what settings.json says is read as the nearest offered', () {
    expect(PixelLoaderStyle.parse(null), PixelLoaderStyle.fill);
    expect(PixelLoaderStyle.parse('nonsense'), PixelLoaderStyle.fill);
    expect(PixelLoaderStyle.parse('rain'), PixelLoaderStyle.rain);
    expect(PixelLoaderStyle.fill.setting, isNull);
    expect(PixelLoaderStyle.circle.setting, 'circle');

    final agent = PixelLoaderRole.agent;
    expect(agent.parseSpeed(null), 1.5);
    expect(PixelLoaderRole.subagent.parseSpeed(null), 1.3);
    expect(agent.parseSpeed(2.2), 2.0);
    expect(agent.parseSpeed('fast'), 1.5);
    expect(agent.speedSetting(1.5), isNull);
    expect(agent.speedSetting(2.0), 2.0);
    for (final role in PixelLoaderRole.values) {
      expect(PixelLoaderRole.speeds, contains(role.defaultSpeed));
    }
  });

  test('a role follows settings.json as it changes', () {
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    var settings = <String, Object?>{};
    PixelLoaderRole.follow(changes, (key) => settings[key]);
    expect(PixelLoaderRole.agent.style.value, PixelLoaderStyle.fill);

    settings = {
      'chat.agentLoadingStyle': 'rain',
      'chat.subagentLoadingSpeed': 2.5,
    };
    changes.value++;
    expect(PixelLoaderRole.agent.style.value, PixelLoaderStyle.rain);
    expect(PixelLoaderRole.subagent.style.value, PixelLoaderStyle.fill);
    expect(PixelLoaderRole.subagent.speed.value, 2.5);
  });

  testWidgets('runs, in the style set, and rests where motion is turned down', (
    tester,
  ) async {
    await tester.pumpWidget(const Center(child: PixelLoader.agent(size: 10)));
    expect(tester.getSize(find.byType(PixelLoader)), const Size.square(10));
    // A frame only as its own changes, not at every vsync.
    expect(tester.hasRunningAnimations, isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.binding.delayed(const Duration(milliseconds: 200));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump();

    // The ring there was before.
    PixelLoaderRole.agent.style.value = PixelLoaderStyle.circle;
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Center(child: PixelLoader.subagent()),
      ),
    );
    await tester.pump();
    await tester.binding.delayed(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
