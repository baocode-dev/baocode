import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/window/window_frame.dart';

const _main = ScreenArea('main', Rect.fromLTWH(0, 25, 1440, 875));
const _right = ScreenArea('right', Rect.fromLTWH(1440, 0, 1920, 1080));

void main() {
  test('JSON round trip; a frame without size is none', () {
    const frame = WindowFrame(
      Rect.fromLTWH(10, 20, 800, 600),
      maximized: true,
      screen: 'main',
    );
    expect(WindowFrame.fromJson(frame.toJson()), frame);
    expect(
      WindowFrame.fromJson({'x': 1, 'y': 2, 'width': 0, 'height': 3}),
      isNull,
    );
    expect(WindowFrame.fromJson({'x': 1}), isNull);
    expect(WindowFrame.fromJson('x'), isNull);
    expect(
      ScreenArea.fromJson({'id': 7, 'x': 0, 'y': 0, 'width': 1, 'height': 1})
          ?.id,
      '7',
    );
  });

  group('fit', () {
    test('a frame on its screen stays where it is', () {
      const frame = WindowFrame(
        Rect.fromLTWH(1600, 100, 800, 600),
        screen: 'right',
      );
      expect(frame.fit([_main, _right]), frame);
    });

    test('its screen named but gone, it is still kept where it shows', () {
      const frame = WindowFrame(
        Rect.fromLTWH(1500, 100, 800, 600),
        screen: 'gone',
      );
      expect(frame.fit([_main, _right]), frame);
    });

    test('off every screen, it is moved onto the nearest and made to fit', () {
      const frame = WindowFrame(
        Rect.fromLTWH(5000, 3000, 2000, 1200),
        maximized: true,
      );
      final fitted = frame.fit([_main, _right]);
      expect(fitted.screen, 'right');
      expect(fitted.bounds, const Rect.fromLTWH(1440, 0, 1920, 1080));
      expect(fitted.maximized, isTrue);
    });

    test('its screen there but the window off it: back onto that screen', () {
      const frame = WindowFrame(
        Rect.fromLTWH(-900, 200, 800, 600),
        screen: 'main',
      );
      final fitted = frame.fit([_main, _right]);
      expect(fitted.screen, 'main');
      expect(fitted.bounds, const Rect.fromLTWH(0, 200, 800, 600));
    });

    test('a title bar above the screen\'s top is pulled down', () {
      const frame = WindowFrame(
        Rect.fromLTWH(100, -300, 800, 600),
        screen: 'main',
      );
      expect(frame.fit([_main]).bounds, const Rect.fromLTWH(100, 25, 800, 600));
    });

    test('a sliver showing is not enough', () {
      const frame = WindowFrame(
        Rect.fromLTWH(1400, 100, 800, 600),
        screen: 'main',
      );
      final fitted = frame.fit([_main]);
      expect(fitted.bounds, const Rect.fromLTWH(640, 100, 800, 600));
    });

    test('no screens known: as it was', () {
      const frame = WindowFrame(Rect.fromLTWH(9000, 9000, 10, 10));
      expect(frame.fit(const []), frame);
    });
  });

  test('cascade: down and right; back to the top left at the edge', () {
    const frame = WindowFrame(
      Rect.fromLTWH(100, 100, 800, 600),
      screen: 'main',
    );
    expect(
      frame.cascade([_main]).bounds,
      const Rect.fromLTWH(130, 130, 800, 600),
    );
    const edge = WindowFrame(Rect.fromLTWH(630, 290, 800, 600), screen: 'main');
    expect(edge.cascade([_main]).bounds, const Rect.fromLTWH(0, 25, 800, 600));
  });
}
