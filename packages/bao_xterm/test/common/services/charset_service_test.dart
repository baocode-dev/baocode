// Copyright (c) 2026 The xterm.js authors. All rights reserved.
// Licensed under the MIT License. See lib/ide/terminal/xterm/LICENSE.txt.
// Adapted from xterm.js src/common/services/CharsetService.test.ts (c58ea36).

import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/ide/terminal/xterm/common/data/charsets.dart';
import 'package:baocode/ide/terminal/xterm/common/services/charset_service.dart';

void main() {
  group('CharsetService', () {
    late CharsetService service;

    setUp(() {
      service = CharsetService();
    });

    test(
      'should not update active charset when designating an inactive glevel',
      () {
        service.setgCharset(1, charsets['0']);
        expect(service.glevel, 0);
        expect(service.charset == null, isTrue);
      },
    );

    test('should expose the designated charset after setgLevel', () {
      service.setgCharset(1, charsets['0']);
      service.setgLevel(1);
      expect(service.charset, same(charsets['0']));
    });

    test(
      'should update active charset when designating the current glevel',
      () {
        service.setgLevel(1);
        service.setgCharset(1, charsets['0']);
        expect(service.charset, same(charsets['0']));
      },
    );

    test('should reset glevel, charsets, and active charset', () {
      service.setgCharset(1, charsets['0']);
      service.setgLevel(1);
      service.reset();
      expect(service.glevel, 0);
      expect(service.charsets, equals(<Object?>[]));
      expect(service.charset == null, isTrue);
    });
  });
}
