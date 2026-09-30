// Copyright (c) 2021 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/input/XParseColor.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/input/x_parse_color.dart';

void main() {
  group('XParseColor', () {
    group('parseColor', () {
      test('rgb:<r>/<g>/<b> scheme in 4/8/12/16 bit', () {
        // 4 bit
        expect(parseColor('rgb:0/0/0'), equals([0, 0, 0]));
        expect(parseColor('rgb:f/f/f'), equals([255, 255, 255]));
        expect(parseColor('rgb:1/2/3'), equals([17, 34, 51]));
        // 8 bit
        expect(parseColor('rgb:00/00/00'), equals([0, 0, 0]));
        expect(parseColor('rgb:ff/ff/ff'), equals([255, 255, 255]));
        expect(parseColor('rgb:11/22/33'), equals([17, 34, 51]));
        // 12 bit
        expect(parseColor('rgb:000/000/000'), equals([0, 0, 0]));
        expect(parseColor('rgb:fff/fff/fff'), equals([255, 255, 255]));
        expect(parseColor('rgb:111/222/333'), equals([17, 34, 51]));
        // 16 bit
        expect(parseColor('rgb:0000/0000/0000'), equals([0, 0, 0]));
        expect(parseColor('rgb:ffff/ffff/ffff'), equals([255, 255, 255]));
        expect(parseColor('rgb:1111/2222/3333'), equals([17, 34, 51]));
      });
      test('#RGB scheme in 4/8/12/16 bit', () {
        // 4 bit
        expect(parseColor('#000'), equals([0, 0, 0]));
        expect(parseColor('#fff'), equals([240, 240, 240]));
        expect(parseColor('#123'), equals([16, 32, 48]));
        // 8 bit
        expect(parseColor('#000000'), equals([0, 0, 0]));
        expect(parseColor('#ffffff'), equals([255, 255, 255]));
        expect(parseColor('#112233'), equals([17, 34, 51]));
        // 12 bit
        expect(parseColor('#000000000'), equals([0, 0, 0]));
        expect(parseColor('#fffffffff'), equals([255, 255, 255]));
        expect(parseColor('#111222333'), equals([17, 34, 51]));
        // 16 bit
        expect(parseColor('#000000000000'), equals([0, 0, 0]));
        expect(parseColor('#ffffffffffff'), equals([255, 255, 255]));
        expect(parseColor('#111122223333'), equals([17, 34, 51]));
      });
      test('supports upper case', () {
        expect(parseColor('RGB:0/A/F'), equals([0, 170, 255]));
        expect(parseColor('#FFF'), equals([240, 240, 240]));
      });
      test('does not parse illegal combinations', () {
        // shifting bit width
        expect(parseColor('rgb:0/11/222'), isNull);
        // unsupported scheme
        expect(parseColor('rgbi:00/11/22'), isNull);
        // broken # specifier
        expect(parseColor('#aabbbcc'), isNull);
        // out of range
        expect(parseColor('#aabbgg'), isNull);
        expect(parseColor('rgb:aa/bb/gg'), isNull);
      });
    });
    group('toXColorRgb', () {
      test('rgb:<r>/<g>/<b> scheme in 4/8/12/16 bit', () {
        // 4 bit
        expect(toRgbString(parseColor('rgb:0/0/0')!, 4), 'rgb:0/0/0');
        expect(toRgbString(parseColor('rgb:f/f/f')!, 4), 'rgb:f/f/f');
        expect(toRgbString(parseColor('rgb:1/2/3')!, 4), 'rgb:1/2/3');
        // 8 bit
        expect(toRgbString(parseColor('rgb:00/00/00')!, 8), 'rgb:00/00/00');
        expect(toRgbString(parseColor('rgb:ff/ff/ff')!, 8), 'rgb:ff/ff/ff');
        expect(toRgbString(parseColor('rgb:11/22/33')!, 8), 'rgb:11/22/33');
        // 12 bit
        expect(
          toRgbString(parseColor('rgb:000/000/000')!, 12),
          'rgb:000/000/000',
        );
        expect(
          toRgbString(parseColor('rgb:fff/fff/fff')!, 12),
          'rgb:fff/fff/fff',
        );
        expect(
          toRgbString(parseColor('rgb:111/222/333')!, 12),
          'rgb:111/222/333',
        );
        // 16 bit
        expect(
          toRgbString(parseColor('rgb:0000/0000/0000')!, 16),
          'rgb:0000/0000/0000',
        );
        expect(
          toRgbString(parseColor('rgb:ffff/ffff/ffff')!, 16),
          'rgb:ffff/ffff/ffff',
        );
        expect(
          toRgbString(parseColor('rgb:1111/2222/3333')!, 16),
          'rgb:1111/2222/3333',
        );
      });
      test('defaults to 16 bit output', () {
        expect(toRgbString(parseColor('rgb:1/2/3')!), 'rgb:1111/2222/3333');
        expect(toRgbString(parseColor('rgb:11/22/33')!), 'rgb:1111/2222/3333');
        expect(
          toRgbString(parseColor('rgb:111/222/333')!),
          'rgb:1111/2222/3333',
        );
        expect(
          toRgbString(parseColor('rgb:123/123/123')!),
          'rgb:1212/1212/1212',
        );
      });
      test('reduces colors to 8 bit resolution', () {
        expect(
          toRgbString(parseColor('rgb:123/123/123')!, 12),
          'rgb:121/121/121',
        );
        expect(
          toRgbString(parseColor('rgb:1234/1234/1234')!, 16),
          'rgb:1212/1212/1212',
        );
      });
    });
  });
}
