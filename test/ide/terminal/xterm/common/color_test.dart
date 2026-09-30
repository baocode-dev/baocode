// Copyright (c) 2017 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/Color.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:monad/ide/terminal/xterm/common/color.dart';
import 'package:monad/ide/terminal/xterm/common/types.dart';

void main() {
  group('Color', () {
    group('channels', () {
      group('toCss', () {
        test('should convert an rgb array to css hex string', () {
          expect(channels.toCss(0x00, 0x00, 0x00), '#000000');
          expect(channels.toCss(0x10, 0x10, 0x10), '#101010');
          expect(channels.toCss(0x20, 0x20, 0x20), '#202020');
          expect(channels.toCss(0x30, 0x30, 0x30), '#303030');
          expect(channels.toCss(0x40, 0x40, 0x40), '#404040');
          expect(channels.toCss(0x50, 0x50, 0x50), '#505050');
          expect(channels.toCss(0x60, 0x60, 0x60), '#606060');
          expect(channels.toCss(0x70, 0x70, 0x70), '#707070');
          expect(channels.toCss(0x80, 0x80, 0x80), '#808080');
          expect(channels.toCss(0x90, 0x90, 0x90), '#909090');
          expect(channels.toCss(0xa0, 0xa0, 0xa0), '#a0a0a0');
          expect(channels.toCss(0xb0, 0xb0, 0xb0), '#b0b0b0');
          expect(channels.toCss(0xc0, 0xc0, 0xc0), '#c0c0c0');
          expect(channels.toCss(0xd0, 0xd0, 0xd0), '#d0d0d0');
          expect(channels.toCss(0xe0, 0xe0, 0xe0), '#e0e0e0');
          expect(channels.toCss(0xf0, 0xf0, 0xf0), '#f0f0f0');
          expect(channels.toCss(0xff, 0xff, 0xff), '#ffffff');
        });
        test('should convert an rgba array to css hex string', () {
          expect(channels.toCss(0x00, 0x00, 0x00, 0x00), '#00000000');
          expect(channels.toCss(0x10, 0x10, 0x10, 0x10), '#10101010');
          expect(channels.toCss(0x20, 0x20, 0x20, 0x20), '#20202020');
          expect(channels.toCss(0x30, 0x30, 0x30, 0x30), '#30303030');
          expect(channels.toCss(0x40, 0x40, 0x40, 0x40), '#40404040');
          expect(channels.toCss(0x50, 0x50, 0x50, 0x50), '#50505050');
          expect(channels.toCss(0x60, 0x60, 0x60, 0x60), '#60606060');
          expect(channels.toCss(0x70, 0x70, 0x70, 0x70), '#70707070');
          expect(channels.toCss(0x80, 0x80, 0x80, 0x80), '#80808080');
          expect(channels.toCss(0x90, 0x90, 0x90, 0x90), '#90909090');
          expect(channels.toCss(0xa0, 0xa0, 0xa0, 0xa0), '#a0a0a0a0');
          expect(channels.toCss(0xb0, 0xb0, 0xb0, 0xb0), '#b0b0b0b0');
          expect(channels.toCss(0xc0, 0xc0, 0xc0, 0xc0), '#c0c0c0c0');
          expect(channels.toCss(0xd0, 0xd0, 0xd0, 0xd0), '#d0d0d0d0');
          expect(channels.toCss(0xe0, 0xe0, 0xe0, 0xe0), '#e0e0e0e0');
          expect(channels.toCss(0xf0, 0xf0, 0xf0, 0xf0), '#f0f0f0f0');
          expect(channels.toCss(0xff, 0xff, 0xff, 0xff), '#ffffffff');
        });
      });

      group('toRgba', () {
        test('should convert an rgb array to an rgba number', () {
          expect(channels.toRgba(0x00, 0x00, 0x00), 0x000000FF);
          expect(channels.toRgba(0x10, 0x10, 0x10), 0x101010FF);
          expect(channels.toRgba(0x20, 0x20, 0x20), 0x202020FF);
          expect(channels.toRgba(0x30, 0x30, 0x30), 0x303030FF);
          expect(channels.toRgba(0x40, 0x40, 0x40), 0x404040FF);
          expect(channels.toRgba(0x50, 0x50, 0x50), 0x505050FF);
          expect(channels.toRgba(0x60, 0x60, 0x60), 0x606060FF);
          expect(channels.toRgba(0x70, 0x70, 0x70), 0x707070FF);
          expect(channels.toRgba(0x80, 0x80, 0x80), 0x808080FF);
          expect(channels.toRgba(0x90, 0x90, 0x90), 0x909090FF);
          expect(channels.toRgba(0xa0, 0xa0, 0xa0), 0xa0a0a0FF);
          expect(channels.toRgba(0xb0, 0xb0, 0xb0), 0xb0b0b0FF);
          expect(channels.toRgba(0xc0, 0xc0, 0xc0), 0xc0c0c0FF);
          expect(channels.toRgba(0xd0, 0xd0, 0xd0), 0xd0d0d0FF);
          expect(channels.toRgba(0xe0, 0xe0, 0xe0), 0xe0e0e0FF);
          expect(channels.toRgba(0xf0, 0xf0, 0xf0), 0xf0f0f0FF);
          expect(channels.toRgba(0xff, 0xff, 0xff), 0xffffffFF);
        });
        test('should convert an rgba array to an rgba number', () {
          expect(channels.toRgba(0x00, 0x00, 0x00, 0x00), 0x00000000);
          expect(channels.toRgba(0x10, 0x10, 0x10, 0x10), 0x10101010);
          expect(channels.toRgba(0x20, 0x20, 0x20, 0x20), 0x20202020);
          expect(channels.toRgba(0x30, 0x30, 0x30, 0x30), 0x30303030);
          expect(channels.toRgba(0x40, 0x40, 0x40, 0x40), 0x40404040);
          expect(channels.toRgba(0x50, 0x50, 0x50, 0x50), 0x50505050);
          expect(channels.toRgba(0x60, 0x60, 0x60, 0x60), 0x60606060);
          expect(channels.toRgba(0x70, 0x70, 0x70, 0x70), 0x70707070);
          expect(channels.toRgba(0x80, 0x80, 0x80, 0x80), 0x80808080);
          expect(channels.toRgba(0x90, 0x90, 0x90, 0x90), 0x90909090);
          expect(channels.toRgba(0xa0, 0xa0, 0xa0, 0xa0), 0xa0a0a0a0);
          expect(channels.toRgba(0xb0, 0xb0, 0xb0, 0xb0), 0xb0b0b0b0);
          expect(channels.toRgba(0xc0, 0xc0, 0xc0, 0xc0), 0xc0c0c0c0);
          expect(channels.toRgba(0xd0, 0xd0, 0xd0, 0xd0), 0xd0d0d0d0);
          expect(channels.toRgba(0xe0, 0xe0, 0xe0, 0xe0), 0xe0e0e0e0);
          expect(channels.toRgba(0xf0, 0xf0, 0xf0, 0xf0), 0xf0f0f0f0);
          expect(channels.toRgba(0xff, 0xff, 0xff, 0xff), 0xffffffff);
        });
      });

      group('toColor', () {
        test('should convert an rgb array to an IColor', () {
          expect(
            channels.toColor(0x00, 0x00, 0x00),
            IColor(css: '#000000', rgba: 0x000000FF),
          );
          expect(
            channels.toColor(0x10, 0x10, 0x10),
            IColor(css: '#101010', rgba: 0x101010FF),
          );
          expect(
            channels.toColor(0x20, 0x20, 0x20),
            IColor(css: '#202020', rgba: 0x202020FF),
          );
          expect(
            channels.toColor(0x30, 0x30, 0x30),
            IColor(css: '#303030', rgba: 0x303030FF),
          );
          expect(
            channels.toColor(0x40, 0x40, 0x40),
            IColor(css: '#404040', rgba: 0x404040FF),
          );
          expect(
            channels.toColor(0x50, 0x50, 0x50),
            IColor(css: '#505050', rgba: 0x505050FF),
          );
          expect(
            channels.toColor(0x60, 0x60, 0x60),
            IColor(css: '#606060', rgba: 0x606060FF),
          );
          expect(
            channels.toColor(0x70, 0x70, 0x70),
            IColor(css: '#707070', rgba: 0x707070FF),
          );
          expect(
            channels.toColor(0x80, 0x80, 0x80),
            IColor(css: '#808080', rgba: 0x808080FF),
          );
          expect(
            channels.toColor(0x90, 0x90, 0x90),
            IColor(css: '#909090', rgba: 0x909090FF),
          );
          expect(
            channels.toColor(0xa0, 0xa0, 0xa0),
            IColor(css: '#a0a0a0', rgba: 0xa0a0a0FF),
          );
          expect(
            channels.toColor(0xb0, 0xb0, 0xb0),
            IColor(css: '#b0b0b0', rgba: 0xb0b0b0FF),
          );
          expect(
            channels.toColor(0xc0, 0xc0, 0xc0),
            IColor(css: '#c0c0c0', rgba: 0xc0c0c0FF),
          );
          expect(
            channels.toColor(0xd0, 0xd0, 0xd0),
            IColor(css: '#d0d0d0', rgba: 0xd0d0d0FF),
          );
          expect(
            channels.toColor(0xe0, 0xe0, 0xe0),
            IColor(css: '#e0e0e0', rgba: 0xe0e0e0FF),
          );
          expect(
            channels.toColor(0xf0, 0xf0, 0xf0),
            IColor(css: '#f0f0f0', rgba: 0xf0f0f0FF),
          );
          expect(
            channels.toColor(0xff, 0xff, 0xff),
            IColor(css: '#ffffff', rgba: 0xffffffFF),
          );
        });
        test('should convert an rgba array to an IColor', () {
          expect(
            channels.toColor(0x00, 0x00, 0x00, 0x00),
            IColor(css: '#00000000', rgba: 0x00000000),
          );
          expect(
            channels.toColor(0x10, 0x10, 0x10, 0x10),
            IColor(css: '#10101010', rgba: 0x10101010),
          );
          expect(
            channels.toColor(0x20, 0x20, 0x20, 0x20),
            IColor(css: '#20202020', rgba: 0x20202020),
          );
          expect(
            channels.toColor(0x30, 0x30, 0x30, 0x30),
            IColor(css: '#30303030', rgba: 0x30303030),
          );
          expect(
            channels.toColor(0x40, 0x40, 0x40, 0x40),
            IColor(css: '#40404040', rgba: 0x40404040),
          );
          expect(
            channels.toColor(0x50, 0x50, 0x50, 0x50),
            IColor(css: '#50505050', rgba: 0x50505050),
          );
          expect(
            channels.toColor(0x60, 0x60, 0x60, 0x60),
            IColor(css: '#60606060', rgba: 0x60606060),
          );
          expect(
            channels.toColor(0x70, 0x70, 0x70, 0x70),
            IColor(css: '#70707070', rgba: 0x70707070),
          );
          expect(
            channels.toColor(0x80, 0x80, 0x80, 0x80),
            IColor(css: '#80808080', rgba: 0x80808080),
          );
          expect(
            channels.toColor(0x90, 0x90, 0x90, 0x90),
            IColor(css: '#90909090', rgba: 0x90909090),
          );
          expect(
            channels.toColor(0xa0, 0xa0, 0xa0, 0xa0),
            IColor(css: '#a0a0a0a0', rgba: 0xa0a0a0a0),
          );
          expect(
            channels.toColor(0xb0, 0xb0, 0xb0, 0xb0),
            IColor(css: '#b0b0b0b0', rgba: 0xb0b0b0b0),
          );
          expect(
            channels.toColor(0xc0, 0xc0, 0xc0, 0xc0),
            IColor(css: '#c0c0c0c0', rgba: 0xc0c0c0c0),
          );
          expect(
            channels.toColor(0xd0, 0xd0, 0xd0, 0xd0),
            IColor(css: '#d0d0d0d0', rgba: 0xd0d0d0d0),
          );
          expect(
            channels.toColor(0xe0, 0xe0, 0xe0, 0xe0),
            IColor(css: '#e0e0e0e0', rgba: 0xe0e0e0e0),
          );
          expect(
            channels.toColor(0xf0, 0xf0, 0xf0, 0xf0),
            IColor(css: '#f0f0f0f0', rgba: 0xf0f0f0f0),
          );
          expect(
            channels.toColor(0xff, 0xff, 0xff, 0xff),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
        });
      });
    });

    group('color', () {
      group('blend', () {
        test('should blend colors based on the alpha channel', () {
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF00', rgba: 0xFFFFFF00),
            ),
            IColor(css: '#000000', rgba: 0x000000FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF10', rgba: 0xFFFFFF10),
            ),
            IColor(css: '#101010', rgba: 0x101010FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF20', rgba: 0xFFFFFF20),
            ),
            IColor(css: '#202020', rgba: 0x202020FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF30', rgba: 0xFFFFFF30),
            ),
            IColor(css: '#303030', rgba: 0x303030FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF40', rgba: 0xFFFFFF40),
            ),
            IColor(css: '#404040', rgba: 0x404040FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF50', rgba: 0xFFFFFF50),
            ),
            IColor(css: '#505050', rgba: 0x505050FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF60', rgba: 0xFFFFFF60),
            ),
            IColor(css: '#606060', rgba: 0x606060FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF70', rgba: 0xFFFFFF70),
            ),
            IColor(css: '#707070', rgba: 0x707070FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF80', rgba: 0xFFFFFF80),
            ),
            IColor(css: '#808080', rgba: 0x808080FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFF90', rgba: 0xFFFFFF90),
            ),
            IColor(css: '#909090', rgba: 0x909090FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFA0', rgba: 0xFFFFFFA0),
            ),
            IColor(css: '#a0a0a0', rgba: 0xA0A0A0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFB0', rgba: 0xFFFFFFB0),
            ),
            IColor(css: '#b0b0b0', rgba: 0xB0B0B0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFC0', rgba: 0xFFFFFFC0),
            ),
            IColor(css: '#c0c0c0', rgba: 0xC0C0C0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFD0', rgba: 0xFFFFFFD0),
            ),
            IColor(css: '#d0d0d0', rgba: 0xD0D0D0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFE0', rgba: 0xFFFFFFE0),
            ),
            IColor(css: '#e0e0e0', rgba: 0xE0E0E0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFF0', rgba: 0xFFFFFFF0),
            ),
            IColor(css: '#f0f0f0', rgba: 0xF0F0F0FF),
          );
          expect(
            color.blend(
              IColor(css: '#000000', rgba: 0x000000FF),
              IColor(css: '#FFFFFFFF', rgba: 0xFFFFFFFF),
            ),
            IColor(css: '#FFFFFFFF', rgba: 0xFFFFFFFF),
          );
        });
      });

      group('opaque', () {
        test('should make the color opaque', () {
          expect(
            color.opaque(IColor(css: '#00000000', rgba: 0x00000000)),
            IColor(css: '#000000', rgba: 0x000000FF),
          );
          expect(
            color.opaque(IColor(css: '#10101010', rgba: 0x10101010)),
            IColor(css: '#101010', rgba: 0x101010FF),
          );
          expect(
            color.opaque(IColor(css: '#20202020', rgba: 0x20202020)),
            IColor(css: '#202020', rgba: 0x202020FF),
          );
          expect(
            color.opaque(IColor(css: '#30303030', rgba: 0x30303030)),
            IColor(css: '#303030', rgba: 0x303030FF),
          );
          expect(
            color.opaque(IColor(css: '#40404040', rgba: 0x40404040)),
            IColor(css: '#404040', rgba: 0x404040FF),
          );
          expect(
            color.opaque(IColor(css: '#50505050', rgba: 0x50505050)),
            IColor(css: '#505050', rgba: 0x505050FF),
          );
          expect(
            color.opaque(IColor(css: '#60606060', rgba: 0x60606060)),
            IColor(css: '#606060', rgba: 0x606060FF),
          );
          expect(
            color.opaque(IColor(css: '#70707070', rgba: 0x70707070)),
            IColor(css: '#707070', rgba: 0x707070FF),
          );
          expect(
            color.opaque(IColor(css: '#80808080', rgba: 0x80808080)),
            IColor(css: '#808080', rgba: 0x808080FF),
          );
          expect(
            color.opaque(IColor(css: '#90909090', rgba: 0x90909090)),
            IColor(css: '#909090', rgba: 0x909090FF),
          );
          expect(
            color.opaque(IColor(css: '#a0a0a0a0', rgba: 0xa0a0a0a0)),
            IColor(css: '#a0a0a0', rgba: 0xa0a0a0FF),
          );
          expect(
            color.opaque(IColor(css: '#b0b0b0b0', rgba: 0xb0b0b0b0)),
            IColor(css: '#b0b0b0', rgba: 0xb0b0b0FF),
          );
          expect(
            color.opaque(IColor(css: '#c0c0c0c0', rgba: 0xc0c0c0c0)),
            IColor(css: '#c0c0c0', rgba: 0xc0c0c0FF),
          );
          expect(
            color.opaque(IColor(css: '#d0d0d0d0', rgba: 0xd0d0d0d0)),
            IColor(css: '#d0d0d0', rgba: 0xd0d0d0FF),
          );
          expect(
            color.opaque(IColor(css: '#e0e0e0e0', rgba: 0xe0e0e0e0)),
            IColor(css: '#e0e0e0', rgba: 0xe0e0e0FF),
          );
          expect(
            color.opaque(IColor(css: '#f0f0f0f0', rgba: 0xf0f0f0f0)),
            IColor(css: '#f0f0f0', rgba: 0xf0f0f0FF),
          );
          expect(
            color.opaque(IColor(css: '#ffffffff', rgba: 0xffffffff)),
            IColor(css: '#ffffff', rgba: 0xffffffFF),
          );
        });
      });

      group('isOpaque', () {
        test('should return true for opaque colors', () {
          expect(color.isOpaque(css.toColor('#000000')), isTrue);
          expect(color.isOpaque(css.toColor('#000000ff')), isTrue);
          expect(color.isOpaque(css.toColor('#808080')), isTrue);
          expect(color.isOpaque(css.toColor('#808080ff')), isTrue);
          expect(color.isOpaque(css.toColor('#ffffff')), isTrue);
          expect(color.isOpaque(css.toColor('#ffffffff')), isTrue);
        });
        test('should return false for transparent colors', () {
          expect(color.isOpaque(css.toColor('#00000000')), isFalse);
          expect(color.isOpaque(css.toColor('#00000080')), isFalse);
          expect(color.isOpaque(css.toColor('#000000fe')), isFalse);
          expect(color.isOpaque(css.toColor('#80808000')), isFalse);
          expect(color.isOpaque(css.toColor('#80808080')), isFalse);
          expect(color.isOpaque(css.toColor('#808080fe')), isFalse);
          expect(color.isOpaque(css.toColor('#ffffff00')), isFalse);
          expect(color.isOpaque(css.toColor('#ffffff80')), isFalse);
          expect(color.isOpaque(css.toColor('#fffffffe')), isFalse);
        });
      });

      group('opacity', () {
        test('should make the color transparent', () {
          expect(
            color.opacity(css.toColor('#000000'), 0),
            IColor(css: '#00000000', rgba: 0x00000000),
          );
          expect(
            color.opacity(css.toColor('#000000'), 0.25),
            IColor(css: '#00000040', rgba: 0x00000040),
          );
          expect(
            color.opacity(css.toColor('#000000'), 0.5),
            IColor(css: '#00000080', rgba: 0x00000080),
          );
          expect(
            color.opacity(css.toColor('#000000'), 0.75),
            IColor(css: '#000000bf', rgba: 0x000000bf),
          );
          expect(
            color.opacity(css.toColor('#000000'), 1),
            IColor(css: '#000000ff', rgba: 0x000000ff),
          );
        });
      });
    });

    group('css', () {
      group('toColor', () {
        test('should convert the #rgb format to an IColor', () {
          expect(css.toColor('#000'), IColor(css: '#000000', rgba: 0x000000FF));
          expect(css.toColor('#111'), IColor(css: '#111111', rgba: 0x111111FF));
          expect(css.toColor('#222'), IColor(css: '#222222', rgba: 0x222222FF));
          expect(css.toColor('#333'), IColor(css: '#333333', rgba: 0x333333FF));
          expect(css.toColor('#444'), IColor(css: '#444444', rgba: 0x444444FF));
          expect(css.toColor('#555'), IColor(css: '#555555', rgba: 0x555555FF));
          expect(css.toColor('#666'), IColor(css: '#666666', rgba: 0x666666FF));
          expect(css.toColor('#777'), IColor(css: '#777777', rgba: 0x777777FF));
          expect(css.toColor('#888'), IColor(css: '#888888', rgba: 0x888888FF));
          expect(css.toColor('#999'), IColor(css: '#999999', rgba: 0x999999FF));
          expect(css.toColor('#aaa'), IColor(css: '#aaaaaa', rgba: 0xaaaaaaFF));
          expect(css.toColor('#bbb'), IColor(css: '#bbbbbb', rgba: 0xbbbbbbFF));
          expect(css.toColor('#ccc'), IColor(css: '#cccccc', rgba: 0xccccccFF));
          expect(css.toColor('#ddd'), IColor(css: '#dddddd', rgba: 0xddddddFF));
          expect(css.toColor('#eee'), IColor(css: '#eeeeee', rgba: 0xeeeeeeFF));
          expect(css.toColor('#fff'), IColor(css: '#ffffff', rgba: 0xffffffFF));
          expect(css.toColor('#fff'), IColor(css: '#ffffff', rgba: 0xffffffFF));
        });
        test('should convert the #rgb format to an IColor', () {
          expect(
            css.toColor('#0000'),
            IColor(css: '#00000000', rgba: 0x00000000),
          );
          expect(
            css.toColor('#1111'),
            IColor(css: '#11111111', rgba: 0x11111111),
          );
          expect(
            css.toColor('#2222'),
            IColor(css: '#22222222', rgba: 0x22222222),
          );
          expect(
            css.toColor('#3333'),
            IColor(css: '#33333333', rgba: 0x33333333),
          );
          expect(
            css.toColor('#4444'),
            IColor(css: '#44444444', rgba: 0x44444444),
          );
          expect(
            css.toColor('#5555'),
            IColor(css: '#55555555', rgba: 0x55555555),
          );
          expect(
            css.toColor('#6666'),
            IColor(css: '#66666666', rgba: 0x66666666),
          );
          expect(
            css.toColor('#7777'),
            IColor(css: '#77777777', rgba: 0x77777777),
          );
          expect(
            css.toColor('#8888'),
            IColor(css: '#88888888', rgba: 0x88888888),
          );
          expect(
            css.toColor('#9999'),
            IColor(css: '#99999999', rgba: 0x99999999),
          );
          expect(
            css.toColor('#aaaa'),
            IColor(css: '#aaaaaaaa', rgba: 0xaaaaaaaa),
          );
          expect(
            css.toColor('#bbbb'),
            IColor(css: '#bbbbbbbb', rgba: 0xbbbbbbbb),
          );
          expect(
            css.toColor('#cccc'),
            IColor(css: '#cccccccc', rgba: 0xcccccccc),
          );
          expect(
            css.toColor('#dddd'),
            IColor(css: '#dddddddd', rgba: 0xdddddddd),
          );
          expect(
            css.toColor('#eeee'),
            IColor(css: '#eeeeeeee', rgba: 0xeeeeeeee),
          );
          expect(
            css.toColor('#ffff'),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
          expect(
            css.toColor('#ffff'),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
        });
        test('should convert the #rrggbb format to an IColor', () {
          expect(
            css.toColor('#000000'),
            IColor(css: '#000000', rgba: 0x000000FF),
          );
          expect(
            css.toColor('#101010'),
            IColor(css: '#101010', rgba: 0x101010FF),
          );
          expect(
            css.toColor('#202020'),
            IColor(css: '#202020', rgba: 0x202020FF),
          );
          expect(
            css.toColor('#303030'),
            IColor(css: '#303030', rgba: 0x303030FF),
          );
          expect(
            css.toColor('#404040'),
            IColor(css: '#404040', rgba: 0x404040FF),
          );
          expect(
            css.toColor('#505050'),
            IColor(css: '#505050', rgba: 0x505050FF),
          );
          expect(
            css.toColor('#606060'),
            IColor(css: '#606060', rgba: 0x606060FF),
          );
          expect(
            css.toColor('#707070'),
            IColor(css: '#707070', rgba: 0x707070FF),
          );
          expect(
            css.toColor('#808080'),
            IColor(css: '#808080', rgba: 0x808080FF),
          );
          expect(
            css.toColor('#909090'),
            IColor(css: '#909090', rgba: 0x909090FF),
          );
          expect(
            css.toColor('#a0a0a0'),
            IColor(css: '#a0a0a0', rgba: 0xa0a0a0FF),
          );
          expect(
            css.toColor('#b0b0b0'),
            IColor(css: '#b0b0b0', rgba: 0xb0b0b0FF),
          );
          expect(
            css.toColor('#c0c0c0'),
            IColor(css: '#c0c0c0', rgba: 0xc0c0c0FF),
          );
          expect(
            css.toColor('#d0d0d0'),
            IColor(css: '#d0d0d0', rgba: 0xd0d0d0FF),
          );
          expect(
            css.toColor('#e0e0e0'),
            IColor(css: '#e0e0e0', rgba: 0xe0e0e0FF),
          );
          expect(
            css.toColor('#f0f0f0'),
            IColor(css: '#f0f0f0', rgba: 0xf0f0f0FF),
          );
          expect(
            css.toColor('#ffffff'),
            IColor(css: '#ffffff', rgba: 0xffffffFF),
          );
        });
        test('should convert the #rrggbbaa format to an IColor', () {
          expect(
            css.toColor('#00000000'),
            IColor(css: '#00000000', rgba: 0x00000000),
          );
          expect(
            css.toColor('#10101010'),
            IColor(css: '#10101010', rgba: 0x10101010),
          );
          expect(
            css.toColor('#20202020'),
            IColor(css: '#20202020', rgba: 0x20202020),
          );
          expect(
            css.toColor('#30303030'),
            IColor(css: '#30303030', rgba: 0x30303030),
          );
          expect(
            css.toColor('#40404040'),
            IColor(css: '#40404040', rgba: 0x40404040),
          );
          expect(
            css.toColor('#50505050'),
            IColor(css: '#50505050', rgba: 0x50505050),
          );
          expect(
            css.toColor('#60606060'),
            IColor(css: '#60606060', rgba: 0x60606060),
          );
          expect(
            css.toColor('#70707070'),
            IColor(css: '#70707070', rgba: 0x70707070),
          );
          expect(
            css.toColor('#80808080'),
            IColor(css: '#80808080', rgba: 0x80808080),
          );
          expect(
            css.toColor('#90909090'),
            IColor(css: '#90909090', rgba: 0x90909090),
          );
          expect(
            css.toColor('#a0a0a0a0'),
            IColor(css: '#a0a0a0a0', rgba: 0xa0a0a0a0),
          );
          expect(
            css.toColor('#b0b0b0b0'),
            IColor(css: '#b0b0b0b0', rgba: 0xb0b0b0b0),
          );
          expect(
            css.toColor('#c0c0c0c0'),
            IColor(css: '#c0c0c0c0', rgba: 0xc0c0c0c0),
          );
          expect(
            css.toColor('#d0d0d0d0'),
            IColor(css: '#d0d0d0d0', rgba: 0xd0d0d0d0),
          );
          expect(
            css.toColor('#e0e0e0e0'),
            IColor(css: '#e0e0e0e0', rgba: 0xe0e0e0e0),
          );
          expect(
            css.toColor('#f0f0f0f0'),
            IColor(css: '#f0f0f0f0', rgba: 0xf0f0f0f0),
          );
          expect(
            css.toColor('#ffffffff'),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
        });
        test('should convert the rgb() format to an IColor', () {
          expect(
            css.toColor('rgb(0, 0, 0)'),
            IColor(css: '#000000ff', rgba: 0x000000ff),
          );
          expect(
            css.toColor('rgb(80, 0, 0)'),
            IColor(css: '#500000ff', rgba: 0x500000ff),
          );
          expect(
            css.toColor('rgb(0, 80, 0)'),
            IColor(css: '#005000ff', rgba: 0x005000ff),
          );
          expect(
            css.toColor('rgb(0, 0, 80)'),
            IColor(css: '#000050ff', rgba: 0x000050ff),
          );
          expect(
            css.toColor('rgb(255, 255, 255)'),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
        });
        test('should convert the rgba() format to an IColor', () {
          expect(
            css.toColor('rgba(0, 0, 0, 0)'),
            IColor(css: '#00000000', rgba: 0x00000000),
          );
          expect(
            css.toColor('rgba(80, 0, 0, 0.5)'),
            IColor(css: '#50000080', rgba: 0x50000080),
          );
          expect(
            css.toColor('rgba(0, 80, 0, 0.5)'),
            IColor(css: '#00500080', rgba: 0x00500080),
          );
          expect(
            css.toColor('rgba(0, 0, 80, 0.5)'),
            IColor(css: '#00005080', rgba: 0x00005080),
          );
          expect(
            css.toColor('rgba(255, 255, 255, 1)'),
            IColor(css: '#ffffffff', rgba: 0xffffffff),
          );
        });
        test('should convert "transparent" to an IColor', () {
          expect(
            css.toColor('transparent'),
            IColor(css: 'transparent', rgba: 0x00000000),
          );
        });
      });
    });

    group('rgb', () {
      group('relativeLuminance', () {
        test('should calculate the relative luminance of the color', () {
          expect(rgb.relativeLuminance(0x000000), 0);
          expect(rgb.relativeLuminance(0x101010).toStringAsFixed(4), '0.0052');
          expect(rgb.relativeLuminance(0x202020).toStringAsFixed(4), '0.0144');
          expect(rgb.relativeLuminance(0x303030).toStringAsFixed(4), '0.0296');
          expect(rgb.relativeLuminance(0x404040).toStringAsFixed(4), '0.0513');
          expect(rgb.relativeLuminance(0x505050).toStringAsFixed(4), '0.0802');
          expect(rgb.relativeLuminance(0x606060).toStringAsFixed(4), '0.1170');
          expect(rgb.relativeLuminance(0x707070).toStringAsFixed(4), '0.1620');
          expect(rgb.relativeLuminance(0x808080).toStringAsFixed(4), '0.2159');
          expect(rgb.relativeLuminance(0x909090).toStringAsFixed(4), '0.2789');
          expect(rgb.relativeLuminance(0xA0A0A0).toStringAsFixed(4), '0.3515');
          expect(rgb.relativeLuminance(0xB0B0B0).toStringAsFixed(4), '0.4342');
          expect(rgb.relativeLuminance(0xC0C0C0).toStringAsFixed(4), '0.5271');
          expect(rgb.relativeLuminance(0xD0D0D0).toStringAsFixed(4), '0.6308');
          expect(rgb.relativeLuminance(0xE0E0E0).toStringAsFixed(4), '0.7454');
          expect(rgb.relativeLuminance(0xF0F0F0).toStringAsFixed(4), '0.8714');
          expect(rgb.relativeLuminance(0xFFFFFF), 1);
        });
      });
    });

    group('rgba', () {
      group('blend', () {
        test('should blend colors based on the alpha channel', () {
          expect(rgba.blend(0x000000FF, 0xFFFFFF00), 0x000000FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF10), 0x101010FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF20), 0x202020FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF30), 0x303030FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF40), 0x404040FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF50), 0x505050FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF60), 0x606060FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF70), 0x707070FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF80), 0x808080FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFF90), 0x909090FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFA0), 0xA0A0A0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFB0), 0xB0B0B0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFC0), 0xC0C0C0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFD0), 0xD0D0D0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFE0), 0xE0E0E0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFF0), 0xF0F0F0FF);
          expect(rgba.blend(0x000000FF, 0xFFFFFFFF), 0xFFFFFFFF);
        });
      });
      group('ensureContrastRatio', () {
        test('should return null if the color already meets the contrast ratio (black bg)', () {
          expect(rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 1), null);
          expect(rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 2), null);
          expect(rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 3), null);
        });
        test(
          'should return a color that meets the contrast ratio (black bg)',
          () {
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 4),
              0x707070ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 5),
              0x7f7f7fff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 6),
              0x8c8c8cff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 7),
              0x989898ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 8),
              0xa3a3a3ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 9),
              0xadadadff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 10),
              0xb6b6b6ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 11),
              0xbebebeff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 12),
              0xc5c5c5ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 13),
              0xd1d1d1ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 14),
              0xd6d6d6ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 15),
              0xdbdbdbff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 16),
              0xe3e3e3ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 17),
              0xe9e9e9ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 18),
              0xeeeeeeff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 19),
              0xf4f4f4ff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 20),
              0xfafafaff,
            );
            expect(
              rgba.ensureContrastRatio(0x000000ff, 0x606060ff, 21),
              0xffffffff,
            );
          },
        );
        test('should return null if the color already meets the contrast ratio (white bg)', () {
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 1), null);
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 2), null);
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 3), null);
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 4), null);
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 5), null);
          expect(rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 6), null);
        });
        test(
          'should return a color that meets the contrast ratio (white bg)',
          () {
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 7),
              0x565656ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 8),
              0x4d4d4dff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 9),
              0x454545ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 10),
              0x3e3e3eff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 11),
              0x373737ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 12),
              0x313131ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 13),
              0x313131ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 14),
              0x272727ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 15),
              0x232323ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 16),
              0x1f1f1fff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 17),
              0x1b1b1bff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 18),
              0x151515ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 19),
              0x101010ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 20),
              0x080808ff,
            );
            expect(
              rgba.ensureContrastRatio(0xffffffff, 0x606060ff, 21),
              0x000000ff,
            );
          },
        );
      });

      group('toChannels', () {
        test('should convert an rgba number to an rgba array', () {
          expect(rgba.toChannels(0x00000000), [0x00, 0x00, 0x00, 0x00]);
          expect(rgba.toChannels(0x10101010), [0x10, 0x10, 0x10, 0x10]);
          expect(rgba.toChannels(0x20202020), [0x20, 0x20, 0x20, 0x20]);
          expect(rgba.toChannels(0x30303030), [0x30, 0x30, 0x30, 0x30]);
          expect(rgba.toChannels(0x40404040), [0x40, 0x40, 0x40, 0x40]);
          expect(rgba.toChannels(0x50505050), [0x50, 0x50, 0x50, 0x50]);
          expect(rgba.toChannels(0x60606060), [0x60, 0x60, 0x60, 0x60]);
          expect(rgba.toChannels(0x70707070), [0x70, 0x70, 0x70, 0x70]);
          expect(rgba.toChannels(0x80808080), [0x80, 0x80, 0x80, 0x80]);
          expect(rgba.toChannels(0x90909090), [0x90, 0x90, 0x90, 0x90]);
          expect(rgba.toChannels(0xa0a0a0a0), [0xa0, 0xa0, 0xa0, 0xa0]);
          expect(rgba.toChannels(0xb0b0b0b0), [0xb0, 0xb0, 0xb0, 0xb0]);
          expect(rgba.toChannels(0xc0c0c0c0), [0xc0, 0xc0, 0xc0, 0xc0]);
          expect(rgba.toChannels(0xd0d0d0d0), [0xd0, 0xd0, 0xd0, 0xd0]);
          expect(rgba.toChannels(0xe0e0e0e0), [0xe0, 0xe0, 0xe0, 0xe0]);
          expect(rgba.toChannels(0xf0f0f0f0), [0xf0, 0xf0, 0xf0, 0xf0]);
          expect(rgba.toChannels(0xffffffff), [0xff, 0xff, 0xff, 0xff]);
        });
      });
    });

    group('toPaddedHex', () {
      test('should convert numbers to 2-digit hex values', () {
        expect(toPaddedHex(0x00), '00');
        expect(toPaddedHex(0x10), '10');
        expect(toPaddedHex(0x20), '20');
        expect(toPaddedHex(0x30), '30');
        expect(toPaddedHex(0x40), '40');
        expect(toPaddedHex(0x50), '50');
        expect(toPaddedHex(0x60), '60');
        expect(toPaddedHex(0x70), '70');
        expect(toPaddedHex(0x80), '80');
        expect(toPaddedHex(0x90), '90');
        expect(toPaddedHex(0xa0), 'a0');
        expect(toPaddedHex(0xb0), 'b0');
        expect(toPaddedHex(0xc0), 'c0');
        expect(toPaddedHex(0xd0), 'd0');
        expect(toPaddedHex(0xe0), 'e0');
        expect(toPaddedHex(0xf0), 'f0');
        expect(toPaddedHex(0xff), 'ff');
      });
    });

    group('contrastRatio', () {
      test('should calculate the relative luminance of the color', () {
        expect(contrastRatio(0, 0), 1);
        expect(contrastRatio(0, 0.5), 11);
        expect(contrastRatio(0, 1), 21);
      });
      test('should work regardless of the parameter order', () {
        expect(contrastRatio(0, 1), 21);
        expect(contrastRatio(1, 0), 21);
      });
    });
  });
}
